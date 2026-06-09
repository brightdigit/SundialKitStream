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

#if canImport(os.log)
  import os.log
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

  private let session: any ConnectivitySession

  // MARK: - Initialization

  /// Creates a new message router.
  ///
  /// - Parameter session: The connectivity session to use for sending
  internal init(session: any ConnectivitySession) {
    self.session = session
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
      // Check if devices are paired at all
      if !session.isPaired {
        if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
          SundialLogger.stream.error(
            "MessageRouter: Cannot send - devices not paired (isPaired=\(session.isPaired))"
          )
        }
        throw ConnectivityError.deviceNotPaired
      } else {
        // Devices are paired but app not installed
        if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
          SundialLogger.stream.error(
            // swiftlint:disable:next line_length
            "MessageRouter: Cannot send - companion app not installed (isPaired=\(session.isPaired), isPairedAppInstalled=\(session.isPairedAppInstalled))"
          )
        }
        throw ConnectivityError.companionAppNotInstalled
      }
    }
  }

  // MARK: - Binary Message Routing

  /// Routes a binary message using sendMessageData.
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
      if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
        SundialLogger.stream.error(
          // swiftlint:disable:next line_length
          "MessageRouter: Cannot send binary - not reachable (isReachable=\(session.isReachable), isPaired=\(session.isPaired), isPairedAppInstalled=\(session.isPairedAppInstalled))"
        )
      }
      throw ConnectivityError.notReachable
    }

    return try await withCheckedThrowingContinuation { continuation in
      session.sendMessageData(data) { result in
        switch result {
        case .success:
          // Note: Binary messages don't have reply data in current WatchConnectivity API
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
  }
}
