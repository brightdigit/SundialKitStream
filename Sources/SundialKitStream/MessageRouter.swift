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
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        applicationContextQueue.async {
          do {
            try session.updateApplicationContext(message)
            continuation.resume()
          } catch {
            continuation.resume(throwing: error)
          }
        }
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
    let messageType = message.messageType
    // Attempt record only — no `transport` field here, since the message has not
    // reached WCSession yet and the guard below may reject it as undeliverable.
    SundialLogger.streamEvent(
      .debug,
      .send,
      "MessageRouter.send",
      fields: [
        SundialStreamLog.Event.Field("type", messageType),
        SundialStreamLog.Event.Field(
          "isPairedAppInstalled", String(session.isPairedAppInstalled)
        ),
        SundialStreamLog.Event.Field("isReachable", String(session.isReachable)),
      ]
    )
    guard session.isPairedAppInstalled else {
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

  /// Determines the specific error for a message that cannot be delivered.
  ///
  /// Binary messages require reachability and cannot use application context.
  ///
  /// - Parameters:
  ///   - data: The encoded binary message data
  ///   - originalMessage: The original message dictionary for result tracking
  /// - Returns: The send result
  /// - Throws: Error if the message cannot be sent or counterpart is not reachable
  internal func sendBinary(
    _ data: Data,
    originalMessage: ConnectivityMessage
  ) async throws -> ConnectivitySendResult {
    guard session.isReachable else {
      // Binary messages require reachability - can't use application context
      SundialLogger.streamError(
        // swiftlint:disable:next line_length
        "MessageRouter: Cannot send binary - not reachable (isReachable=\(session.isReachable), isPaired=\(session.isPaired), isPairedAppInstalled=\(session.isPairedAppInstalled))"
      )
      throw ConnectivityError.notReachable
    }

    // A flapping link can fire sendMessageData's handler more than once; claim()
    // lets the first callback win so the checked continuation is never double-resumed.
    let resumeGuard = ResumeOnce()
    return try await withCheckedThrowingContinuation { continuation in
      session.sendMessageData(data) { result in
        guard resumeGuard.claim() else {
          return
        }
        switch result {
        case .success:
          let sendResult = ConnectivitySendResult(
            message: originalMessage,
            context: .reply([:], transport: .binary)
          )
          continuation.resume(returning: sendResult)
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      }
    }
    // Devices are paired but app not installed
    SundialLogger.streamError(
      // swiftlint:disable:next line_length
      "MessageRouter: Cannot send - companion app not installed (isPaired=\(session.isPaired), isPairedAppInstalled=\(session.isPairedAppInstalled))"
    )
    return ConnectivityError.companionAppNotInstalled
  }
}
