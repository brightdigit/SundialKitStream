//
//  MessageRouter+Binary.swift
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

@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
extension MessageRouter {
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
  }
}
