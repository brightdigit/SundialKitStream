//
//  ContextEngineLifecycleTests.swift
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
@testable import SundialKitContext
@testable import SundialKitStream

@Suite("ContextEngine lifecycle")
@MainActor
internal struct ContextEngineLifecycleTests {
  private typealias Ping = ContextEngineFixtures.Ping

  private struct TestError: Error {}

  /// Counts the main-actor `shouldReassert` evaluations the heartbeat loop makes each
  /// tick, so a test can prove the loop stopped after `stop()`.
  @MainActor private final class Probe {
    var evaluations = 0
    var sentRevisions: [UInt64] = []
  }

  private static func makeSync(
    session: MockConnectivitySession,
    probe: Probe,
    heartbeat: Duration = .seconds(3),
    shouldReassert: @escaping @MainActor () -> Bool = { false }
  ) -> ContextEngine<Ping, Ping> {
    ContextEngine<Ping, Ping>(
      observer: ConnectivityObserver(session: session),
      heartbeat: heartbeat,
      shouldReassert: shouldReassert,
      makeOutbound: { revision in
        probe.sentRevisions.append(revision)
        return Ping(revision: revision)
      },
      onInbound: { _ in }
    )
  }

  @Test("applyInstalled updates the observable companion-installed flag")
  internal func applyInstalledUpdatesFlag() {
    let sync = Self.makeSync(session: ContextEngineFixtures.pairedSession(), probe: Probe())

    #expect(!sync.isPairedAppInstalled)
    sync.applyInstalled(true)
    #expect(sync.isPairedAppInstalled)
  }

  @Test("A send failure sets lastSendError; a later success clears it")
  internal func sendErrorSetsAndClearsLastSendError() async {
    let session = ContextEngineFixtures.pairedSession()
    let sync = Self.makeSync(session: session, probe: Probe())

    session.updateApplicationContextError = TestError()
    await sync.performAssert()
    #expect(sync.lastSendError != nil)

    session.updateApplicationContextError = nil
    await sync.performAssert()
    #expect(sync.lastSendError == nil)
  }

  @Test("Activation failure sets lastActivationError, not lastSendError, and skips the heartbeat")
  internal func activationFailureIsDistinctAndSkipsHeartbeat() async {
    let session = ContextEngineFixtures.pairedSession()
    session.activateError = TestError()
    let probe = Probe()
    let sync = Self.makeSync(
      session: session, probe: probe, heartbeat: .milliseconds(10), shouldReassert: { true }
    )

    await sync.start()

    #expect(sync.lastActivationError != nil)
    #expect(sync.lastSendError == nil)

    // Heartbeat must not have started: no sends fire even past several intervals.
    try? await Task.sleep(for: .milliseconds(60))
    #expect(probe.sentRevisions.isEmpty)
  }

  @Test("A successful send does not erase a prior activation error")
  internal func successfulSendPreservesActivationError() async {
    let session = ContextEngineFixtures.pairedSession()
    session.activateError = TestError()
    let sync = Self.makeSync(session: session, probe: Probe())

    await sync.start()
    #expect(sync.lastActivationError != nil)

    session.activateError = nil
    await sync.performAssert()

    #expect(sync.lastSendError == nil)
    #expect(sync.lastActivationError != nil)
  }

  @Test("The heartbeat drives a send while running")
  internal func heartbeatFiresWhileRunning() async {
    let probe = Probe()
    let sync = Self.makeSync(
      session: ContextEngineFixtures.pairedSession(),
      probe: probe,
      heartbeat: .milliseconds(10),
      shouldReassert: { true }
    )

    await sync.start()
    defer { sync.stop() }

    var waited = 0
    while probe.sentRevisions.isEmpty, waited < 100 {
      try? await Task.sleep(for: .milliseconds(20))
      waited += 1
    }
    #expect(!probe.sentRevisions.isEmpty)
  }

  @Test("stop() halts the heartbeat loop — no further reassert evaluation fires")
  internal func heartbeatHaltsAfterStop() async {
    let probe = Probe()
    // Return false so the loop only evaluates `shouldReassert` (synchronous) and never
    // spawns a fire-and-forget assert — isolating the loop's stop behavior.
    let sync = Self.makeSync(
      session: ContextEngineFixtures.pairedSession(),
      probe: probe,
      heartbeat: .milliseconds(15),
      shouldReassert: {
        probe.evaluations += 1
        return false
      }
    )

    await sync.start()

    var waited = 0
    while probe.evaluations == 0, waited < 100 {
      try? await Task.sleep(for: .milliseconds(20))
      waited += 1
    }
    #expect(probe.evaluations >= 1)

    // Capture the heartbeat handle before stop() nils it, then drain it: awaiting
    // the cancelled task is deterministic (no sleep race) and guarantees the loop
    // has fully exited before we assert no further evaluation fired.
    let heartbeat = sync.heartbeatTask
    sync.stop()
    let evaluationsAtStop = probe.evaluations
    await heartbeat?.value
    #expect(probe.evaluations == evaluationsAtStop)
  }

  @Test("A second start() is a no-op")
  internal func secondStartIsNoOp() async {
    let sync = Self.makeSync(session: ContextEngineFixtures.pairedSession(), probe: Probe())

    await sync.start()
    await sync.start()
    sync.stop()

    #expect(sync.lastActivationError == nil)
  }

  @Test("performAssert after stop() sends nothing")
  internal func noSendAfterStop() async {
    let probe = Probe()
    let sync = Self.makeSync(session: ContextEngineFixtures.pairedSession(), probe: probe)
    await sync.start()
    sync.stop()
    await sync.performAssert()
    #expect(probe.sentRevisions.isEmpty)
  }

  @Test("Activation failure is retryable: a later start() re-activates and runs the heartbeat")
  internal func activationFailureIsRetryable() async {
    let session = ContextEngineFixtures.pairedSession()
    session.activateError = TestError()
    let probe = Probe()
    let sync = Self.makeSync(
      session: session, probe: probe, heartbeat: .milliseconds(10), shouldReassert: { true }
    )
    await sync.start()
    #expect(sync.lastActivationError != nil)
    #expect(probe.sentRevisions.isEmpty)

    session.activateError = nil
    await sync.start()
    defer { sync.stop() }
    var waited = 0
    while probe.sentRevisions.isEmpty, waited < 100 {
      try? await Task.sleep(for: .milliseconds(20))
      waited += 1
    }
    #expect(!probe.sentRevisions.isEmpty)
  }
}
