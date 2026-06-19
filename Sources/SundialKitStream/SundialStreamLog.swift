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
/// The sink is stored behind a `Mutex`, so installing and forwarding are safe
/// from any isolation domain. Apps typically install it once during launch.
public enum SundialStreamLog {
  /// The severity of a forwarded stream-log message.
  public enum Level: Sendable {
    /// Routine send-path diagnostics.
    case debug
    /// A send-path failure or undeliverable-message condition.
    case error
  }

  private static let storage = Mutex<(@Sendable (Level, String) -> Void)?>(nil)

  /// Installs (or clears, when `nil`) the host sink that receives stream logs.
  ///
  /// - Parameter sink: A `Sendable` closure invoked for every stream-category
  ///   log, or `nil` to stop forwarding.
  public static func setSink(_ sink: (@Sendable (Level, String) -> Void)?) {
    self.storage.withLock { $0 = sink }
  }

  /// Forwards a message to the installed sink, if any.
  internal static func forward(_ level: Level, _ message: String) {
    let sink = self.storage.withLock { $0 }
    sink?(level, message)
  }
}
