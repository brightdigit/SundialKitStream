//
//  MockConnectivitySession.swift
//  SundialKitStream
//
//  Created by Leo Dion.
//  Copyright © 2025 BrightDigit.
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

@testable import SundialKitConnectivity
@testable import SundialKitCore
@testable import SundialKitStream

// MARK: - Mock Session

internal final class MockConnectivitySession: ConnectivitySession, @unchecked Sendable {
  internal var delegate: (any ConnectivitySessionDelegate)?
  internal var isReachable: Bool = false
  internal var isPairedAppInstalled: Bool = false
  internal var isPaired: Bool = false
  internal var activationState: ActivationState = .notActivated
  internal var receivedApplicationContext: ConnectivityMessage?

  // MARK: - Transport call recording

  /// Every dictionary handed to `updateApplicationContext`, in order.
  internal var applicationContexts: [ConnectivityMessage] = []
  /// Every dictionary handed to `sendMessage`, in order.
  internal var sentMessages: [ConnectivityMessage] = []
  /// Every payload handed to `sendMessageData`, in order.
  internal var sentMessageData: [Data] = []
  /// When set, `updateApplicationContext` throws this instead of recording.
  internal var updateApplicationContextError: (any Error)?
  /// Reply delivered to `sendMessage`'s handler, if any.
  internal var nextSendMessageReply: Result<ConnectivityMessage, any Error>?
  /// Reply delivered to `sendMessageData`'s handler, if any.
  internal var nextSendMessageDataReply: Result<Data, any Error>?

  internal func activate() throws {}

  internal func updateApplicationContext(_ context: ConnectivityMessage) throws {
    if let updateApplicationContextError {
      throw updateApplicationContextError
    }
    applicationContexts.append(context)
  }

  internal func sendMessage(
    _ message: ConnectivityMessage,
    _ replyHandler: @escaping (Result<ConnectivityMessage, any Error>) -> Void
  ) {
    sentMessages.append(message)
    // Consume the queued reply so a second send does not silently re-fire it.
    if let nextSendMessageReply {
      self.nextSendMessageReply = nil
      replyHandler(nextSendMessageReply)
    }
  }

  internal func sendMessageData(
    _ data: Data,
    _ completion: @escaping (Result<Data, any Error>) -> Void
  ) {
    sentMessageData.append(data)
    // Consume the queued reply so a second send does not silently re-fire it.
    if let nextSendMessageDataReply {
      self.nextSendMessageDataReply = nil
      completion(nextSendMessageDataReply)
    }
  }
}
