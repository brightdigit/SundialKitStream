//
//  MessageRouterSerializationTests.swift
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

/// Regression tests for the watchOS cooperative-pool deadlock: two racing
/// `send` calls used to block two pool threads inside the synchronous
/// `updateApplicationContext`, starving every actor in the app. Sends must
/// now be serialized onto a dedicated queue.
@Suite("MessageRouter send serialization")
internal struct MessageRouterSerializationTests {
  private static func installedSession() -> MockConnectivitySession {
    let session = MockConnectivitySession()
    session.isPaired = true
    session.isPairedAppInstalled = true
    return session
  }

  @Test("Two racing sends both complete — the deadlock regression")
  internal func racingSendsBothComplete() async throws {
    let session = Self.installedSession()
    session.updateApplicationContextDelay = 0.05
    let router = MessageRouter(session: session)

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { _ = try await router.send(["__type": "First"]) }
      group.addTask { _ = try await router.send(["__type": "Second"]) }
      try await group.waitForAll()
    }

    #expect(session.applicationContexts.count == 2)
  }

  @Test("updateApplicationContext executions never overlap")
  internal func sendsNeverOverlap() async throws {
    let session = Self.installedSession()
    session.updateApplicationContextDelay = 0.02
    let router = MessageRouter(session: session)

    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<10 {
        group.addTask { _ = try await router.send(["__type": "Msg", "index": index]) }
      }
      try await group.waitForAll()
    }

    #expect(session.applicationContexts.count == 10)
    #expect(session.maxConcurrentContextUpdates == 1)
  }

  @Test("Errors propagate through the serialized queue hop")
  internal func errorPropagatesThroughQueue() async {
    let session = Self.installedSession()
    session.updateApplicationContextError = ConnectivityError.payloadTooLarge
    let router = MessageRouter(session: session)

    await #expect(throws: ConnectivityError.payloadTooLarge) {
      _ = try await router.send(["__type": "X"])
    }
  }
}
