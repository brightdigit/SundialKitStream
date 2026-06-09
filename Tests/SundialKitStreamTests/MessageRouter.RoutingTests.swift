//
//  MessageRouter.RoutingTests.swift
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
import Testing

@testable import SundialKitConnectivity
@testable import SundialKitCore
@testable import SundialKitStream

@Suite("MessageRouter routing")
internal struct MessageRouterRoutingTests {
  private static func installedSession(reachable: Bool) -> MockConnectivitySession {
    let session = MockConnectivitySession()
    session.isPaired = true
    session.isPairedAppInstalled = true
    session.isReachable = reachable
    return session
  }

  // MARK: - Dictionary Routing

  @Test("Dictionary send uses application context when reachable — never sendMessage")
  internal func reachableUsesApplicationContext() async throws {
    let session = Self.installedSession(reachable: true)
    let router = MessageRouter(session: session)

    let message: ConnectivityMessage = ["__type": "StartTimerCommand"]
    let result = try await router.send(message)

    // The reachable path must NOT take the fragile reply-expecting sendMessage
    // route — that is the regression this routing guarantees against.
    #expect(session.sentMessages.isEmpty)
    #expect(session.applicationContexts.count == 1)
    #expect(session.applicationContexts.first?["__type"] as? String == "StartTimerCommand")
    #expect(result.context.transport == .dictionary)
    if case .applicationContext = result.context {
    } else {
      Issue.record("Expected .applicationContext, got \(result.context)")
    }
  }

  @Test("Dictionary send uses application context when unreachable")
  internal func unreachableUsesApplicationContext() async throws {
    let session = Self.installedSession(reachable: false)
    let router = MessageRouter(session: session)

    _ = try await router.send(["__type": "StopTimerCommand"])

    #expect(session.sentMessages.isEmpty)
    #expect(session.applicationContexts.count == 1)
  }

  @Test("Dictionary send propagates updateApplicationContext error")
  internal func propagatesApplicationContextError() async {
    let session = Self.installedSession(reachable: true)
    session.updateApplicationContextError = ConnectivityError.payloadTooLarge
    let router = MessageRouter(session: session)

    await #expect(throws: ConnectivityError.payloadTooLarge) {
      _ = try await router.send(["__type": "X"])
    }
  }

  @Test("Dictionary send throws deviceNotPaired when not paired")
  internal func throwsWhenNotPaired() async {
    let session = MockConnectivitySession()
    session.isPaired = false
    session.isPairedAppInstalled = false
    let router = MessageRouter(session: session)

    await #expect(throws: ConnectivityError.deviceNotPaired) {
      _ = try await router.send(["__type": "X"])
    }
  }

  @Test("Dictionary send throws companionAppNotInstalled when paired but app missing")
  internal func throwsWhenCompanionMissing() async {
    let session = MockConnectivitySession()
    session.isPaired = true
    session.isPairedAppInstalled = false
    let router = MessageRouter(session: session)

    await #expect(throws: ConnectivityError.companionAppNotInstalled) {
      _ = try await router.send(["__type": "X"])
    }
  }

  // MARK: - Binary Routing

  @Test("Binary send throws notReachable when not reachable")
  internal func binaryRequiresReachability() async {
    let session = Self.installedSession(reachable: false)
    let router = MessageRouter(session: session)

    await #expect(throws: ConnectivityError.notReachable) {
      _ = try await router.sendBinary(Data([0x01, 0x02]), originalMessage: ["__type": "B"])
    }
    #expect(session.sentMessageData.isEmpty)
  }

  @Test("Binary send uses sendMessageData when reachable")
  internal func binaryUsesMessageDataWhenReachable() async throws {
    let session = Self.installedSession(reachable: true)
    session.nextSendMessageDataReply = .success(Data())
    let router = MessageRouter(session: session)

    let payload = Data([0x0A, 0x0B, 0x0C])
    let result = try await router.sendBinary(payload, originalMessage: ["__type": "B"])

    #expect(session.sentMessageData == [payload])
    #expect(session.applicationContexts.isEmpty)
    #expect(result.context.transport == .binary)
  }
}
