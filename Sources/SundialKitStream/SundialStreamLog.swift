//
//  SundialStreamLog.swift
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

internal import Synchronization

/// A host-installable sink for SundialKitStream's stream-category diagnostics.
///
/// SundialKitStream logs its send/receive path through OSLog (and an optional
/// stdout mirror). A host app can additionally route those diagnostics into its
/// own structured logger — e.g. Broadcast — by installing a sink via
/// ``setSink(_:)``. ``ConnectivityObserver`` send-path logging (``MessageRouter``,
/// ``MessageDistributor``, message dispatch) then forwards to that sink, letting
/// the app capture the full watch↔phone communication trail in one place.
///
/// The sink receives a structured ``Event`` — a human-readable message plus
/// ordered key/value fields (message type, transport, reachability, …) — so the
/// host can preserve that structure rather than re-parse a string. The sink is
/// stored behind a `Mutex`, so installing and forwarding are safe from any
/// isolation domain. Apps typically install it once during launch.
public enum SundialStreamLog {
  /// The severity of a forwarded stream-log event.
  public enum Level: Sendable {
    /// Routine send-path diagnostics.
    case debug
    /// A send-path failure or undeliverable-message condition.
    case error
  }

  /// Box holding the installed sink.
  ///
  /// The closure is deliberately wrapped in a struct rather than stored as a
  /// bare function value. Reading a bare `@Sendable (Event) -> Void` back out of
  /// a `Mutex` *mutates* it: `withLock` yields the value as generic `inout`,
  /// materializing a function across that abstraction boundary wraps it in a
  /// reabstraction thunk pair, and the write-back stores the wrapped copy over
  /// the original. The layers compose and are never collapsed, so N reads leave
  /// a 2N-deep thunk chain and the sink eventually overflows the stack — which
  /// killed the AtLeast watch app ~23 minutes into every session
  /// (brightdigit/AtLeast#329). Wrapping the function in a `Sendable` struct
  /// keeps it from crossing that boundary bare.
  ///
  /// See [swiftlang/swift#91348](https://github.com/swiftlang/swift/issues/91348)
  /// (duplicate of #54724). Note that issue reports the accumulation as
  /// `-Onone`-only; measured on Swift 6.4 / arm64-apple-macosx27 it reproduces at
  /// **both** `-Onone` and `-O`, so this is not a debug-only concern.
  ///
  /// Covered by `SundialStreamLogTests.forwardDoesNotAccumulateStackDepth`,
  /// which fails without this wrapper at either optimization level.
  private struct Sink: Sendable {
    fileprivate var call: (@Sendable (Event) -> Void)?
  }

  private static let storage = Mutex<Sink>(Sink())

  /// Installs (or clears, when `nil`) the host sink that receives stream events.
  ///
  /// - Parameter sink: A `Sendable` closure invoked for every stream-category
  ///   event, or `nil` to stop forwarding.
  public static func setSink(_ sink: (@Sendable (Event) -> Void)?) {
    self.storage.withLock { $0.call = sink }
  }

  /// Forwards an event to the installed sink, if any.
  internal static func forward(_ event: Event) {
    let sink = self.storage.withLock { $0.call }
    sink?(event)
  }

  /// Emits a structured event through the same pipeline as the framework's own
  /// send/receive diagnostics — OSLog (mirrored to stdout when `SUNDIAL_CONSOLE`
  /// is set) plus any installed ``setSink(_:)``.
  ///
  /// The framework logs its internal path itself; this is the public entry point
  /// for layered code built on top of it (e.g. `SundialKitContext`'s
  /// `ContextEngine`) to surface its own drops and sends into the same trail.
  public static func emit(
    _ level: Level,
    _ kind: Kind,
    _ message: String,
    fields: [Event.Field] = []
  ) {
    SundialLogger.streamEvent(level, kind, message, fields: fields)
  }
}
