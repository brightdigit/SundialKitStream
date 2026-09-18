//
//  SundialStreamLogThunkAccumulationTests.swift
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

@testable import SundialKitStream

@Suite("SundialStreamLog.ThunkAccumulation", .serialized)
internal struct SundialStreamLogThunkAccumulationTests {
  /// Distinguishes this test's events from any other suite's concurrent traffic
  /// through the process-global sink.
  fileprivate static let marker = "marker-forwardDoesNotAccumulateStackDepth"

  /// Repeated `forward(_:)` must not grow the stack depth at which the sink runs.
  ///
  /// Regression test for a stack overflow that killed the AtLeast watch app ~23
  /// minutes into every session (brightdigit/AtLeast#329). Reading a bare
  /// function value out of a `Mutex` used to *mutate* it: `withLock` hands the
  /// value over as generic `inout`, materializing it across that abstraction
  /// boundary wraps it in a reabstraction thunk pair, and the write-back stored
  /// the wrapped copy over the original. The layers composed and were never
  /// collapsed, so N reads left a 2N-deep thunk chain and calling the sink
  /// eventually ran out of stack — a depth-3302 `EXC_BAD_ACCESS` into the Stack
  /// Guard page on a 3-second heartbeat.
  ///
  /// See swiftlang/swift#91348 (dup of #54724). Storing the closure inside a
  /// `Sendable` struct keeps the function value from crossing that boundary
  /// bare, which is what ``SundialStreamLog`` now does.
  ///
  /// This test must be run at **both** optimization levels. The upstream issue
  /// describes the accumulation as `-Onone`-only, but measured on Swift 6.4 it
  /// fails without the wrapper at `-O` as well.
  ///
  /// Measures the sink's actual stack pointer rather than counting frames: drift
  /// is exactly what accumulating thunks cause, and it stays flat when fixed.
  @Test("forward(_:) does not accumulate stack depth across repeated reads")
  internal func forwardDoesNotAccumulateStackDepth() throws {
    /// Records the sink's stack depth, but only for this test's own marker —
    /// the `SundialStreamLog` sink is process-global, so a concurrently running
    /// suite can install over it or push unrelated traffic through it.
    final class DepthProbe: @unchecked Sendable {
      private let lock = NSLock()
      private var depths: [UInt] = []

      func record(_ event: SundialStreamLog.Event) {
        guard event.message == SundialStreamLogThunkAccumulationTests.marker else {
          return
        }
        var probe: UInt8 = 0
        let depth = withUnsafePointer(to: &probe) { UInt(bitPattern: $0) }
        lock.lock()
        depths.append(depth)
        lock.unlock()
      }

      func snapshot() -> [UInt] {
        lock.lock()
        defer { lock.unlock() }
        return depths
      }
    }

    let probe = DepthProbe()
    SundialStreamLog.setSink { probe.record($0) }
    defer { SundialStreamLog.setSink(nil) }

    // Enough reads to be unambiguous: the watch crash took ~1650 pairs, and the
    // unwrapped form drifts 64 bytes per read, so this overflows before the fix.
    let iterations = 5_000
    let event = SundialStreamLog.Event(level: .debug, kind: .generic, message: Self.marker)
    for _ in 0..<iterations {
      SundialStreamLog.forward(event)
    }

    // A sibling suite may have replaced the sink partway through, so assert on
    // what actually arrived rather than on an exact count. The drift check is
    // the real assertion; it needs only enough samples to be meaningful.
    let depths = probe.snapshot()
    try #require(depths.count > 1)

    // Every invocation must run at the same stack depth as the first one.
    let baseline = depths[0]
    let drift = depths.map { Int(bitPattern: baseline &- $0) }
    #expect(drift.allSatisfy { $0 == 0 })
  }
}
