//
//  MessageDistributorContextTests.swift
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

@Suite("MessageDistributor application context handling")
internal struct MessageDistributorContextTests {
  private struct TestMessage: Messagable {
    static let key: String = "test"
    let value: String

    init(from message: ConnectivityMessage) {
      self.value = message["value"] as? String ?? ""
    }

    func parameters() -> ConnectivityMessage {
      ["value": value]
    }
  }

  /// Collects everything yielded to the raw message-received stream, then
  /// finishes it so the values can be read back.
  private static func collectRawDeliveries(
    drive: (MessageDistributor) async -> Void
  ) async -> [ConnectivityMessage] {
    let manager = SundialKitStream.StreamContinuationManager()
    let distributor = MessageDistributor(continuationManager: manager, messageDecoder: nil)

    let (stream, continuation) = AsyncStream<ConnectivityReceiveResult>.makeStream()
    await manager.registerMessageReceived(id: UUID(), continuation: continuation)
    await drive(distributor)
    continuation.finish()

    var received: [ConnectivityMessage] = []
    for await result in stream {
      received.append(result.message)
    }
    return received
  }

  @Test("Replayed identical application context is delivered once")
  internal func duplicateContextDeliveredOnce() async {
    let received = await Self.collectRawDeliveries { distributor in
      let context: ConnectivityMessage = ["__type": "Start", "value": 1]
      // Same dictionary three times — activation, reachability, foreground replays.
      await distributor.handleApplicationContext(context, error: nil)
      await distributor.handleApplicationContext(context, error: nil)
      await distributor.handleApplicationContext(context, error: nil)
    }

    #expect(received.count == 1)
  }

  @Test("Differing application contexts are all delivered")
  internal func differingContextsAllDelivered() async {
    let received = await Self.collectRawDeliveries { distributor in
      await distributor.handleApplicationContext(["value": 1], error: nil)
      await distributor.handleApplicationContext(["value": 2], error: nil)
      await distributor.handleApplicationContext(["value": 1], error: nil)
    }

    // The third differs from the *last delivered* context, so it passes too.
    #expect(received.count == 3)
  }

  @Test("Undecodable message is dropped without trapping")
  internal func undecodableMessageIsDropped() async {
    let manager = SundialKitStream.StreamContinuationManager()
    let decoder = MessageDecoder(messagableTypes: [TestMessage.self])
    let distributor = MessageDistributor(continuationManager: manager, messageDecoder: decoder)

    let (stream, continuation) = AsyncStream<any Messagable>.makeStream()
    await manager.registerTypedMessage(id: UUID(), continuation: continuation)

    // Unknown type key — e.g. a counterpart running a newer build. Must log
    // and drop, never assert.
    await distributor.handleApplicationContext(
      ["__type": "UnknownFutureCommand", "payload": "x"],
      error: nil
    )
    continuation.finish()

    var typed: [any Messagable] = []
    for await message in stream {
      typed.append(message)
    }
    #expect(typed.isEmpty)
  }
}
