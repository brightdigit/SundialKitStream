//
//  MessageRouter.swift
//  SundialKitStream
//
//  Created by Leo Dion.
//  Copyright © 2026 BrightDigit.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//

import Foundation
import SundialKitConnectivity
import SundialKitCore

#if canImport(Dispatch)
  import Dispatch
#endif

/// Internal helper for routing messages through appropriate transports.
///
/// `MessageRouter` encapsulates the logic for selecting the best transport
/// method based on session state and message type. It handles:
/// - Immediate delivery via `sendMessage` when reachable
/// - Background delivery via `updateApplicationContext` when not reachable
/// - Binary transport for `BinaryMessagable` types
/// - Dictionary transport for regular `Messagable` types
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
internal struct MessageRouter {
  // MARK: - Private Properties

  internal let session: any ConnectivitySession

  /// Serial queue for `updateApplicationContext` calls.
  ///
  /// The WCSession call is synchronous; invoking it from an async function
  /// blocks a cooperative-pool thread, and two racing calls can block *both*
  /// threads of a watch's 2-thread pool, starving every actor in the app.
  /// Hopping onto this queue (a) guarantees two calls never run concurrently
  /// and (b) keeps any blocking off the cooperative pool entirely.
  ///
  /// One router exists per `ConnectivityObserver`; struct copies share the
  /// queue, preserving serialization.
  ///
  /// Platforms without Dispatch (e.g. WASI/Wasm) are single-threaded, so no
  /// cross-thread serialization is possible or needed there; the queue is
  /// elided and `updateApplicationContext` is invoked directly.
  #if canImport(Dispatch)
    private let applicationContextQueue: DispatchQueue
  #endif

  // MARK: - Initialization

  /// Creates a new message router.
  ///
  /// - Parameter session: The connectivity session to use for sending
  internal init(session: any ConnectivitySession) {
    self.session = session
    #if canImport(Dispatch)
      self.applicationContextQueue = DispatchQueue(
        label: "com.brightdigit.SundialKitStream.MessageRouter.applicationContext"
      )
    #endif
  }

  /// Runs `updateApplicationContext` on the dedicated serial queue.
  ///
  /// - Parameter message: The message to send as application context
  /// - Throws: Error if the context update fails
  internal func updateApplicationContextSerialized(
    _ message: ConnectivityMessage
  ) async throws {
    let session = self.session
    #if canImport(Dispatch)
      // `withCheckedThrowingContinuation` does not inject `CancellationError` on
      // its own, and the queued block runs unconditionally once enqueued. Wrap
      // it in `withTaskCancellationHandler` and short-circuit inside the block so
      // a cancelled caller resumes promptly instead of holding a cooperative-pool
      // thread until the dispatch work finishes (a real starvation risk on
      // watchOS's 2-thread pool).
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, any Error>) in
          applicationContextQueue.async {
            guard !Task.isCancelled else {
              continuation.resume(throwing: CancellationError())
              return
            }
            do {
              try session.updateApplicationContext(message)
              continuation.resume()
            } catch {
              continuation.resume(throwing: error)
            }
          }
        }
      } onCancel: {
      }
    #else
      // Single-threaded platforms (WASI/Wasm) have no Dispatch; the call
      // cannot race, so invoke it directly.
      try session.updateApplicationContext(message)
    #endif
  }

  // MARK: - Dictionary Message Routing

  /// Routes a dictionary message using the best available transport.
  ///
  /// - Parameter message: The message to send
  /// - Returns: The send result
  /// - Throws: Error if the message cannot be sent
  internal func send(_ message: ConnectivityMessage) async throws -> ConnectivitySendResult {
    if session.isPairedAppInstalled {
      // Always deliver via application context, regardless of reachability.
      //
      // `session.isReachable` is intentionally not consulted on this dictionary
      // path (the binary `sendBinary` path still gates on it). The combination
      // `isPairedAppInstalled == true` with `isPaired == false` — which some
      // simulator states report — also falls through here on purpose: routing via
      // application context is harmless and correct in that case.
      //
      // This app's messages are latest-desired-state (start config, stop,
      // request, state update), for which application context is the correct
      // transport in every reachability state: WatchConnectivity delivers it
      // immediately when the counterpart is active and persists + replays it on
      // activation/reachability change otherwise.
      //
      // `sendMessage` is deliberately NOT used. It requires a stable reachable
      // link and a reply, and a flapping link makes WCSession invoke the error
      // handler more than once for the same message (WCErrorCodeNotReachable
      // then WCErrorCodeMessageReplyTimedOut), which both loses the command and
      // crashes the checked continuation with a double resume.
      try session.updateApplicationContext(message)
      return ConnectivitySendResult(
        message: message,
        context: .applicationContext(transport: .dictionary)
      )
    } else {
      // No way to deliver the message - determine specific reason
      throw undeliverableError()
    }
    // Always deliver via application context, regardless of reachability: these
    // messages are latest-desired-state, for which application context is correct
    // in every state, and `isReachable` gates only the binary `sendBinary` path.
    // `sendMessage` is deliberately NOT used — a flapping link makes WCSession fire
    // its error handler twice, double-resuming the checked continuation.
    SundialLogger.streamEvent(
      .debug,
      .send,
      "MessageRouter.send: calling updateApplicationContext",
      fields: [
        SundialStreamLog.Event.Field("type", messageType),
        SundialStreamLog.Event.Field("transport", "applicationContext"),
      ]
    )
    try await updateApplicationContextSerialized(message)
    SundialLogger.streamDebug("MessageRouter.send: updateApplicationContext returned")
    return ConnectivitySendResult(
      message: message,
      context: .applicationContext(transport: .dictionary)
    )
  }

  /// Determines the specific error for a message that cannot be delivered.
  ///
  /// - Returns: `.deviceNotPaired` when no counterpart device is paired,
  ///   otherwise `.companionAppNotInstalled`.
  private func undeliverableError() -> ConnectivityError {
    // Check if devices are paired at all
    if !session.isPaired {
      SundialLogger.streamError(
        "MessageRouter: Cannot send - devices not paired (isPaired=\(session.isPaired))"
      )
      return ConnectivityError.deviceNotPaired
    }
    // Devices are paired but app not installed
    SundialLogger.streamError(
      // swiftlint:disable:next line_length
      "MessageRouter: Cannot send - companion app not installed (isPaired=\(session.isPaired), isPairedAppInstalled=\(session.isPairedAppInstalled))"
    )
    return ConnectivityError.companionAppNotInstalled
  }
}
