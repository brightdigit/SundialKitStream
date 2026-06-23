//
//  StaleWindow.swift
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

public import Foundation

/// Decides whether an ``ExpiringMessage`` is recent enough to act on.
///
/// WatchConnectivity persists the last application context and re-delivers it on
/// activation/foreground, so a fresh launch can receive a snapshot produced long
/// ago. Filtering by `sentAt` against a bounded window drops those replays even on
/// first sight, while the heartbeat keeps a still-wanted snapshot's `sentAt`
/// current so it never ages out mid-wait.
public struct StaleWindow: Sendable, Equatable {
  /// The maximum age, in seconds, a snapshot may have and still be acted on.
  public let interval: TimeInterval

  /// Creates a window of `interval` seconds (default 30).
  public init(_ interval: TimeInterval = 30) {
    self.interval = interval
  }

  /// `true` when `message` was sent within the window (small future clock skew is
  /// tolerated — a negative age is still ≤ the window).
  public func isFresh(_ message: some ExpiringMessage, now: Date = Date()) -> Bool {
    now.timeIntervalSince(message.sentAt) <= interval
  }
}
