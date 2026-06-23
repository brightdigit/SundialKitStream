//
//  ContextEngineTests.swift
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
@testable import SundialKitStreamContext

@Suite("ContextEngine")
@MainActor
internal struct ContextEngineTests {
  /// A minimal ``RevisionedMessage`` used as both the outbound and inbound payload.
  private struct Ping: RevisionedMessage {
    static let key = "Ping"
    let revision: UInt64

    init(revision: UInt64) {
      self.revision = revision
    }

    init(from parameters: [String: any Sendable]) throws {
      self.revision = (parameters["revision"] as? UInt64) ?? 0
    }

    func parameters() -> [String: any Sendable] {
      ["revision": revision]
    }
  }

  /// Captures the revisions built by `makeOutbound` and the snapshots delivered to
  /// `onInbound`, so tests assert without decoding the wire form.
  @MainActor private final class Recorder {
    var sentRevisions: [UInt64] = []
    var received: [Ping] = []
  }

  private static func pairedSession() -> MockConnectivitySession {
    let session = MockConnectivitySession()
    session.isPaired = true
    session.isPairedAppInstalled = true
    return session
  }

  private static func makeSync(
    session: MockConnectivitySession,
    recorder: Recorder,
    replyOnInbound: Bool = false,
    reassertOnReachable: Bool = true
  ) -> ContextEngine<Ping, Ping> {
    ContextEngine<Ping, Ping>(
      observer: ConnectivityObserver(session: session),
      replyOnInbound: replyOnInbound,
      reassertOnReachable: reassertOnReachable,
      makeOutbound: { revision in
        recorder.sentRevisions.append(revision)
        return Ping(revision: revision)
      },
      onInbound: { recorder.received.append($0) }
    )
  }

  @Test("Each assert stamps a monotonically increasing revision and sends")
  internal func assertStampsIncrementingRevisions() async {
    let session = Self.pairedSession()
    let recorder = Recorder()
    let sync = Self.makeSync(session: session, recorder: recorder)

    await sync.performAssert()
    await sync.performAssert()

    #expect(recorder.sentRevisions == [1, 2])
    #expect(session.applicationContexts.count == 2)
  }

  @Test("Reply-on-inbound answers each received snapshot with current state")
  internal func replyOnInboundSendsState() async {
    let session = Self.pairedSession()
    let recorder = Recorder()
    let sync = Self.makeSync(session: session, recorder: recorder, replyOnInbound: true)

    await sync.handleInbound(Ping(revision: 99))

    #expect(recorder.received.map(\.revision) == [99])
    #expect(recorder.sentRevisions == [1])
  }

  @Test("Without reply-on-inbound, a received snapshot triggers no send")
  internal func noReplyWhenDisabled() async {
    let session = Self.pairedSession()
    let recorder = Recorder()
    let sync = Self.makeSync(session: session, recorder: recorder, replyOnInbound: false)

    await sync.handleInbound(Ping(revision: 7))

    #expect(recorder.received.count == 1)
    #expect(recorder.sentRevisions.isEmpty)
  }

  @Test("Becoming reachable re-asserts once; staying reachable does not")
  internal func reassertOnReconnect() async {
    let session = Self.pairedSession()
    let recorder = Recorder()
    let sync = Self.makeSync(session: session, recorder: recorder, reassertOnReachable: true)

    await sync.applyReachable(true)
    await sync.applyReachable(true)

    #expect(recorder.sentRevisions == [1])
    #expect(sync.isReachable)
  }

  @Test("reassertOnReachable=false updates reachability without sending")
  internal func noReassertWhenDisabled() async {
    let session = Self.pairedSession()
    let recorder = Recorder()
    let sync = Self.makeSync(session: session, recorder: recorder, reassertOnReachable: false)

    await sync.applyReachable(true)

    #expect(recorder.sentRevisions.isEmpty)
    #expect(sync.isReachable)
  }
}
