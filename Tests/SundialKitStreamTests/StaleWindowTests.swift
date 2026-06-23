//
//  StaleWindowTests.swift
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
@testable import SundialKitStream
@testable import SundialKitStreamSync

@Suite("StaleWindow")
internal struct StaleWindowTests {
  /// A minimal ``ExpiringMessage`` for window tests.
  private struct StubIntent: ExpiringMessage {
    static let key = "StubIntent"
    let revision: UInt64
    let sentAt: Date

    init(revision: UInt64 = 1, sentAt: Date) {
      self.revision = revision
      self.sentAt = sentAt
    }

    init(from parameters: [String: any Sendable]) throws {
      self.revision = (parameters["revision"] as? UInt64) ?? 0
      self.sentAt = (parameters["sentAt"] as? Date) ?? Date(timeIntervalSince1970: 0)
    }

    func parameters() -> [String: any Sendable] {
      ["revision": revision, "sentAt": sentAt]
    }
  }

  private static let now = Date(timeIntervalSince1970: 1_700_000_000)

  @Test("A message sent within the window is fresh")
  internal func freshWithinWindow() {
    let window = StaleWindow(30)
    let message = StubIntent(sentAt: Self.now.addingTimeInterval(-5))
    #expect(window.isFresh(message, now: Self.now))
  }

  @Test("A message older than the window is stale")
  internal func staleBeyondWindow() {
    let window = StaleWindow(30)
    let message = StubIntent(sentAt: Self.now.addingTimeInterval(-31))
    #expect(!window.isFresh(message, now: Self.now))
  }

  @Test("Exactly at the window boundary is still fresh")
  internal func boundaryIsFresh() {
    let window = StaleWindow(30)
    let message = StubIntent(sentAt: Self.now.addingTimeInterval(-30))
    #expect(window.isFresh(message, now: Self.now))
  }

  @Test("Small future clock skew is tolerated")
  internal func futureSkewTolerated() {
    let window = StaleWindow(30)
    let message = StubIntent(sentAt: Self.now.addingTimeInterval(5))
    #expect(window.isFresh(message, now: Self.now))
  }
}
