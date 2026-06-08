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

extension MessageRouter {
  @Suite("MessageRouter routing")
  internal struct RoutingTests {
    /// Minimal `BinaryMessagable` relying on the synthesized `parameters()`/`init(from:)`.
    private struct BinaryProbe: BinaryMessagable {
      static let key: String = "probe"
      let value: String

      init(value: String) { self.value = value }
      init(from data: Data) throws { self.value = String(bytes: data, encoding: .utf8) ?? "" }
      func encode() throws -> Data { Data(value.utf8) }
    }

    private static let message: ConnectivityMessage = ["key": "value"]
    private static let binaryMessage = BinaryProbe(value: "probe")

    // MARK: - Dictionary Routing

    @Test("Reachable dictionary sends via sendMessage")
    internal func dictionaryReachable() async throws {
      let session = MockConnectivitySession()
      session.isReachable = true
      let router = MessageRouter(session: session)

      _ = try await router.send(Self.message)

      #expect(session.sentMessages.count == 1)
      #expect(session.transferredUserInfo.isEmpty)
      #expect(session.applicationContexts.isEmpty)
    }

    @Test("Unreachable + installed dictionary queues via transferUserInfo by default")
    internal func dictionaryQueuedByDefault() async throws {
      let session = MockConnectivitySession()
      session.isPaired = true
      session.isPairedAppInstalled = true
      let router = MessageRouter(session: session)

      let result = try await router.send(Self.message)

      #expect(session.transferredUserInfo.count == 1)
      #expect(session.sentMessages.isEmpty)
      #expect(session.applicationContexts.isEmpty)
      guard case .queued(let transport) = result.context else {
        Issue.record("Expected queued send context")
        return
      }
      #expect(transport == .dictionary)
    }

    @Test("Unreachable dictionary coalesces with useApplicationContext")
    internal func dictionaryApplicationContext() async throws {
      let session = MockConnectivitySession()
      session.isPaired = true
      session.isPairedAppInstalled = true
      let router = MessageRouter(session: session)

      _ = try await router.send(Self.message, options: .useApplicationContext)

      #expect(session.applicationContexts.count == 1)
      #expect(session.transferredUserInfo.isEmpty)
      #expect(session.sentMessages.isEmpty)
    }

    @Test("Unreachable + app not installed dictionary throws")
    internal func dictionaryNotInstalledThrows() async throws {
      let session = MockConnectivitySession()
      session.isPaired = true
      let router = MessageRouter(session: session)

      await #expect(throws: ConnectivityError.companionAppNotInstalled) {
        _ = try await router.send(Self.message)
      }
    }

    // MARK: - Binary Routing

    @Test("Reachable binary sends via sendMessageData")
    internal func binaryReachable() async throws {
      let session = MockConnectivitySession()
      session.isReachable = true
      let router = MessageRouter(session: session)

      _ = try await router.sendBinary(Self.binaryMessage)

      #expect(session.sentMessageData.count == 1)
      #expect(session.transferredFiles.isEmpty)
      #expect(session.applicationContexts.isEmpty)
    }

    @Test("Unreachable + installed binary queues via transferFile by default")
    internal func binaryQueuedByDefault() async throws {
      let session = MockConnectivitySession()
      session.isPaired = true
      session.isPairedAppInstalled = true
      let router = MessageRouter(session: session)

      let result = try await router.sendBinary(Self.binaryMessage)

      #expect(session.transferredFiles.count == 1)
      #expect(
        session.transferredFiles.first?.data
          == (try BinaryMessageEncoder.encode(Self.binaryMessage)))
      #expect(session.sentMessageData.isEmpty)
      guard case .queued(let transport) = result.context else {
        Issue.record("Expected queued send context")
        return
      }
      #expect(transport == .binary)
    }

    @Test("Unreachable binary coalesces with useApplicationContext")
    internal func binaryApplicationContext() async throws {
      let session = MockConnectivitySession()
      session.isPaired = true
      session.isPairedAppInstalled = true
      let router = MessageRouter(session: session)

      _ = try await router.sendBinary(Self.binaryMessage, options: .useApplicationContext)

      #expect(session.applicationContexts.count == 1)
      #expect(session.transferredFiles.isEmpty)
      #expect(session.sentMessageData.isEmpty)
    }

    @Test("Unreachable + app not installed binary throws")
    internal func binaryNotInstalledThrows() async throws {
      let session = MockConnectivitySession()
      session.isPaired = true
      let router = MessageRouter(session: session)

      await #expect(throws: ConnectivityError.companionAppNotInstalled) {
        _ = try await router.sendBinary(Self.binaryMessage)
      }
    }
  }
}
