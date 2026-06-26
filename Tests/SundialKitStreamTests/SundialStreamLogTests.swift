//
//  SundialStreamLogTests.swift
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

@Suite("SundialStreamLog", .serialized)
@MainActor
internal struct SundialStreamLogTests {
  /// Thread-safe sink that records forwarded events; the `SundialStreamLog` sink is
  /// process-global and `@Sendable`, so capture is `NSLock`-guarded and tests filter by
  /// a unique marker to ignore concurrent noise from other suites.
  private final class LogSinkCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SundialStreamLog.Event] = []

    func install() {
      SundialStreamLog.setSink { [self] event in
        lock.lock()
        storage.append(event)
        lock.unlock()
      }
    }

    func snapshot() -> [SundialStreamLog.Event] {
      lock.lock()
      defer { lock.unlock() }
      return storage
    }

    /// Events whose `fields` carry a `type=<value>` pair — isolates this test's
    /// MessageRouter probe from any concurrent stream-log traffic.
    func events(forType value: String) -> [SundialStreamLog.Event] {
      snapshot().filter { event in
        event.fields.contains { $0.key == "type" && $0.value == value }
      }
    }
  }

  @Test("Event.rendered appends fields as space-joined key=value pairs")
  internal func renderedFormatsFields() {
    let withFields = SundialStreamLog.Event(
      level: .debug,
      kind: .generic,
      message: "hello",
      fields: [.init("a", "1"), .init("b", "2")]
    )
    #expect(withFields.rendered == "hello a=1 b=2")

    let noFields = SundialStreamLog.Event(level: .debug, kind: .generic, message: "bare")
    #expect(noFields.rendered == "bare")
  }

  @Test("An installed sink receives forwarded events; setSink(nil) stops forwarding")
  internal func sinkReceivesThenStops() {
    let capture = LogSinkCapture()
    capture.install()
    defer { SundialStreamLog.setSink(nil) }

    let marker = "marker-sinkReceivesThenStops"
    SundialLogger.streamEvent(.debug, .lifecycle, marker, fields: [.init("k", "v")])

    let received = capture.snapshot().filter { $0.message == marker }
    #expect(received.count == 1)
    #expect(received.first?.level == .debug)
    #expect(received.first?.kind == .lifecycle)
    #expect(received.first?.rendered == "\(marker) k=v")

    SundialStreamLog.setSink(nil)
    SundialLogger.streamEvent(.debug, .generic, marker)
    #expect(capture.snapshot().filter { $0.message == marker }.count == 1)
  }

  @Test("streamDebug and streamError carry the right level and generic kind")
  internal func debugAndErrorHelpers() {
    let capture = LogSinkCapture()
    capture.install()
    defer { SundialStreamLog.setSink(nil) }

    let debugMarker = "marker-debug"
    let errorMarker = "marker-error"
    SundialLogger.streamDebug(debugMarker)
    SundialLogger.streamError(errorMarker)

    let debugEvent = capture.snapshot().first { $0.message == debugMarker }
    let errorEvent = capture.snapshot().first { $0.message == errorMarker }
    #expect(debugEvent?.level == .debug)
    #expect(debugEvent?.kind == .generic)
    #expect(errorEvent?.level == .error)
    #expect(errorEvent?.kind == .generic)
  }

  @Test("MessageRouter logs transport=applicationContext only after the deliverability guard")
  internal func transportLoggedOnlyAfterGuard() async {
    let capture = LogSinkCapture()
    capture.install()
    defer { SundialStreamLog.setSink(nil) }

    let probeType = "TransportOrderProbe"
    let probe: ConnectivityMessage = ["__type": probeType]

    // Undeliverable: companion app not installed → no transport should be logged.
    let session = MockConnectivitySession()
    session.isPaired = true
    session.isPairedAppInstalled = false
    let router = MessageRouter(session: session)
    _ = try? await router.send(probe)

    let undeliverable = capture.events(forType: probeType)
    #expect(!undeliverable.isEmpty)
    #expect(
      !undeliverable.contains { event in
        event.fields.contains { $0.key == "transport" }
      }
    )

    // Deliverable: now the transport field appears once the guard passes.
    session.isPairedAppInstalled = true
    _ = try? await router.send(probe)

    let delivered = capture.events(forType: probeType)
    #expect(
      delivered.contains { event in
        event.fields.contains { $0.key == "transport" && $0.value == "applicationContext" }
      }
    )
  }
}
