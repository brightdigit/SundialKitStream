//
//  RevisionedMessage.swift
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

public import SundialKitConnectivity

/// A message stamped with a monotonic ``revision`` so each application-context
/// write is a distinct payload that transport-layer dedup can never silently
/// drop.
///
/// WatchConnectivity's application context is a single latest-wins slot, and it
/// (and SundialKitStream's own coalescing) discards a context identical to the
/// previous one. A re-asserted snapshot — sent by a heartbeat or on reconnect to
/// self-heal a dropped delivery — would therefore be lost unless something makes
/// it differ. A monotonically increasing `revision` is that something. It is *not*
/// used to gate inbound application (apply each snapshot idempotently instead),
/// because the counter resets when the sender relaunches.
public protocol RevisionedMessage: Messagable, Sendable, Equatable {
  /// A counter the sender increments on every send (change, reconnect, heartbeat).
  var revision: UInt64 { get }
}
