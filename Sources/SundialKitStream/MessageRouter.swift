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
  /// When the counterpart is unreachable but the companion app is installed,
  /// the message is queued via `transferUserInfo` by default (FIFO, every
  /// message delivered). Pass `.useApplicationContext` in `options` to coalesce
  /// to the latest-state `updateApplicationContext` transport instead.
  ///
  /// - Parameters:
  ///   - message: The message to send
  ///   - options: Send options; only `.useApplicationContext` affects routing here
  /// - Returns: The send result
  /// - Throws: Error if the message cannot be sent
  internal func send(
    _ message: ConnectivityMessage,
    options: SendOptions = []
  ) async throws -> ConnectivitySendResult {
    if session.isReachable {
      // Use sendMessage for immediate delivery when reachable
      return try await withCheckedThrowingContinuation { continuation in
        session.sendMessage(message) { result in
          let sendResult = ConnectivitySendResult(message: message, context: .init(result))
          continuation.resume(returning: sendResult)
        }
      }
    } else if session.isPairedAppInstalled {
      let context: ConnectivitySendContext
      if options.contains(.useApplicationContext) {
        // Coalescing latest-state delivery (explicit opt-in)
        try session.updateApplicationContext(message)
        context = .applicationContext(transport: .dictionary)
      } else {
        // Default: queued FIFO delivery via transferUserInfo
        session.transferUserInfo(message)
        context = .queued(transport: .dictionary)
      }
      return ConnectivitySendResult(message: message, context: context)
    } else {
      // No way to deliver the message - determine specific reason
      throw undeliverableError()
    }
  }

  /// Returns the specific error describing why a message cannot be delivered
  /// when the counterpart is neither reachable nor (paired and installed).
  private func undeliverableError() -> ConnectivityError {
    if !session.isPaired {
      if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
        SundialLogger.stream.error(
          "MessageRouter: Cannot send - devices not paired (isPaired=\(session.isPaired))"
        )
      }
      return .deviceNotPaired
    }
    // Devices are paired but app not installed
    if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
      SundialLogger.stream.error(
        // swiftlint:disable:next line_length
        "MessageRouter: Cannot send - companion app not installed (isPaired=\(session.isPaired), isPairedAppInstalled=\(session.isPairedAppInstalled))"
      )
    }
    return .companionAppNotInstalled
  }

  // MARK: - Binary Message Routing

  /// Routes a binary message using the best available transport.
  ///
  /// The typed message yields two representations, both derived here:
  /// - `BinaryMessageEncoder.encode(message)` — footer-included `Data` for the
  ///   raw transports (`sendMessageData` when reachable, `transferFile` when queued).
  /// - `message.message()` — the dictionary envelope (`__type` + `__parameters`,
  ///   with the encoded payload already embedded under `__data` by
  ///   `BinaryMessagable`'s synthesized `parameters()`). Used as the send-result
  ///   payload and as the `updateApplicationContext` payload.
  ///
  /// Because the binary already rides inside that dictionary, the
  /// `.useApplicationContext` path round-trips through `MessageDecoder.decode`
  /// on receive — the footer-based `decodeBinary` is only needed for the raw
  /// `Data` transports, which have no dictionary envelope.
  ///
  /// - Parameters:
  ///   - message: The typed binary message to send
  ///   - options: Send options; only `.useApplicationContext` affects routing here
  /// - Returns: The send result
  /// - Throws: Error if encoding fails or the message cannot be sent
  internal func sendBinary(
    _ message: some BinaryMessagable,
    options: SendOptions = []
  ) async throws -> ConnectivitySendResult {
    let data = try BinaryMessageEncoder.encode(message)
    let messageDictionary = message.message()

    if session.isReachable {
      return try await withCheckedThrowingContinuation { continuation in
        session.sendMessageData(data) { result in
          switch result {
          case .success:
            // Note: Binary messages don't have reply data in current WatchConnectivity API
            let sendResult = ConnectivitySendResult(
              message: messageDictionary,
              context: .reply([:], transport: .binary)
            )
            continuation.resume(returning: sendResult)
          case .failure(let error):
            continuation.resume(throwing: error)
          }
        }
      }
    } else if session.isPairedAppInstalled {
      let context: ConnectivitySendContext
      if options.contains(.useApplicationContext) {
        // Coalescing latest-state delivery; the encoded binary already rides
        // inside messageDictionary under __parameters.__data
        try session.updateApplicationContext(messageDictionary)
        context = .applicationContext(transport: .binary)
      } else {
        // Default: queued FIFO delivery via transferFile (footer included)
        session.transferFile(data, metadata: nil)
        context = .queued(transport: .binary)
      }
      return ConnectivitySendResult(message: messageDictionary, context: context)
    } else {
      // No way to deliver the message - determine specific reason
      throw undeliverableError()
    }
  }
}
