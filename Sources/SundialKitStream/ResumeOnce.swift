//
//  ResumeOnce.swift
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

/// A one-shot guard that lets a `CheckedContinuation` be resumed at most once.
///
/// `WCSession`'s `sendMessageData` reply handler can fire more than once for a
/// single message when the link is flapping; resuming a checked continuation
/// twice traps. Routing every branch through ``claim()`` lets the first callback
/// win and silently drops any later one.
///
/// A `final class` rather than a bare `Mutex` value so the guard can be captured
/// by reference into the escaping completion handler (a `Mutex` is `~Copyable`);
/// `Sendable` is satisfied without `@unchecked` because the sole stored property
/// is itself `Sendable`.
internal final class ResumeOnce: Sendable {
  private let hasResumed = Mutex(false)

  /// Returns `true` for the first caller and `false` for every caller after.
  internal func claim() -> Bool {
    hasResumed.withLock { resumed in
      guard !resumed else {
        return false
      }
      resumed = true
      return true
    }
  }
}
