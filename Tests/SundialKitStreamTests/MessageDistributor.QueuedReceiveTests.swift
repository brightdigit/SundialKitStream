//
//  MessageDistributor.QueuedReceiveTests.swift
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

extension MessageDistributor {
  @Suite("MessageDistributor queued receive")
  internal struct QueuedReceiveTests {
    private struct DictMessage: Messagable {
      static let key: String = "dict"
      let value: String

      init(value: String) { self.value = value }

      init(from parameters: [String: any Sendable]) throws {
        guard let value = parameters["value"] as? String else {
          throw SerializationError.missingField("value")
        }
        self.value = value
      }

      func parameters() -> [String: any Sendable] { ["value": value] }
    }

    private struct BinaryMessage: BinaryMessagable {
      static let key: String = "binary"
      let value: String

      init(value: String) { self.value = value }

      init(from parameters: [String: any Sendable]) throws {
        guard let value = parameters["value"] as? String else {
          throw SerializationError.missingField("value")
        }
        self.value = value
      }

      init(from data: Data) throws {
        self.value = String(bytes: data, encoding: .utf8) ?? ""
      }

      func parameters() -> [String: any Sendable] { ["value": value] }

      func encode() throws -> Data { Data(value.utf8) }
    }

    private func captureFirstTypedMessage(
      from manager: SundialKitStream.StreamContinuationManager,
      capture: TestValueCapture,
      yield: @Sendable @escaping () async -> Void
    ) async throws {
      let id = UUID()
      let stream = AsyncStream<any Messagable> { continuation in
        Task { await manager.registerTypedMessage(id: id, continuation: continuation) }
      }
      let task = Task { @Sendable in
        for await message in stream {
          await capture.set(typedMessage: message)
          break
        }
      }
      // Give subscriber time to register
      try await Task.sleep(for: .milliseconds(50))
      await yield()
      _ = await task.value
    }

    @Test("Received user info yields to typed message stream")
    internal func userInfoYieldsTyped() async throws {
      let manager = SundialKitStream.StreamContinuationManager()
      let decoder = MessageDecoder(messagableTypes: [DictMessage.self])
      let distributor = MessageDistributor(continuationManager: manager, messageDecoder: decoder)
      let capture = TestValueCapture()

      try await captureFirstTypedMessage(from: manager, capture: capture) {
        await distributor.handleUserInfo(DictMessage(value: "hello").message())
      }

      let received = await capture.typedMessage
      #expect((received as? DictMessage)?.value == "hello")
    }

    @Test("Received file yields to typed message stream")
    internal func fileYieldsTyped() async throws {
      let manager = SundialKitStream.StreamContinuationManager()
      let decoder = MessageDecoder(messagableTypes: [BinaryMessage.self])
      let distributor = MessageDistributor(continuationManager: manager, messageDecoder: decoder)
      let capture = TestValueCapture()
      let data = try BinaryMessageEncoder.encode(BinaryMessage(value: "world"))

      try await captureFirstTypedMessage(from: manager, capture: capture) {
        await distributor.handleFile(data, metadata: nil)
      }

      let received = await capture.typedMessage
      #expect((received as? BinaryMessage)?.value == "world")
    }
  }
}
