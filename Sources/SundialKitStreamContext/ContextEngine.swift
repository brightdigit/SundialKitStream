//
//  ContextEngine.swift
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

public import Observation
public import SundialKitConnectivity
public import SundialKitStream

/// Reliable, revisioned, heartbeated one-direction snapshot sync over a
/// ``ConnectivityObserver``'s application context.
///
/// Each peer owns a `ContextEngine`: it **sends** its whole desired `Outbound`
/// snapshot (stamped with a monotonic revision) to the single latest-wins
/// application-context slot, and **receives** the peer's `Inbound` snapshots. The
/// app supplies only the domain pieces — how to build the current outbound
/// snapshot, what to do with an inbound one, and (optionally) when the heartbeat
/// should re-assert — while `ContextEngine` owns the generic reliability mechanics:
///
/// - **Monotonic revision** on every send, so a re-assert is never deduped away.
/// - **Heartbeat** re-assertion on an interval, so a dropped delivery self-heals.
/// - **Reassert on reconnect**, so a peer that just became reachable re-syncs.
/// - **Reply-on-inbound**, so a responder can answer every received snapshot with
///   its current state.
///
/// `@MainActor @Observable`, so SwiftUI can observe ``isReachable`` /
/// ``isPairedAppInstalled`` directly. The domain layer applies inbound snapshots
/// *idempotently* (see ``StaleWindow`` for the intent-side stale filter).
@MainActor @Observable
public final class ContextEngine<Outbound, Inbound>
where Outbound: RevisionedMessage, Inbound: Messagable {
  /// Whether the counterpart app is reachable for immediate delivery.
  public internal(set) var isReachable: Bool = false
  /// Whether the paired device has the counterpart app installed.
  public internal(set) var isPairedAppInstalled: Bool = false
  /// The error from the most recent send, or `nil` if it succeeded.
  public internal(set) var lastSendError: (any Error)?
  /// The error from the most recent activation attempt, or `nil` if it succeeded.
  ///
  /// Kept separate from ``lastSendError`` so a later successful send does not erase
  /// an activation failure — the two require different recovery (recreate vs retry).
  public internal(set) var lastActivationError: (any Error)?

  @ObservationIgnored internal let observer: ConnectivityObserver
  @ObservationIgnored internal let heartbeatInterval: Duration
  @ObservationIgnored internal let replyOnInbound: Bool
  @ObservationIgnored internal let reassertOnReachable: Bool
  @ObservationIgnored internal let shouldReassert: @MainActor () -> Bool
  @ObservationIgnored internal let makeOutbound: @MainActor (UInt64) -> Outbound
  @ObservationIgnored internal let onInbound: @MainActor (Inbound) -> Void

  @ObservationIgnored internal var outboundRevision: UInt64 = 0
  @ObservationIgnored private var hasStarted = false
  @ObservationIgnored private var streamTask: Task<Void, Never>?
  @ObservationIgnored private var heartbeatTask: Task<Void, Never>?

  /// Creates a sync around an existing `observer` (inject a mock-backed one for
  /// tests).
  ///
  /// - Parameters:
  ///   - observer: The connectivity observer to send through and receive from.
  ///   - heartbeat: How often to re-assert the latest snapshot.
  ///   - replyOnInbound: When `true`, send the current outbound snapshot after
  ///     every received inbound one (a responder answering each request).
  ///   - reassertOnReachable: When `true`, re-assert when the peer becomes
  ///     reachable, so a reconnect re-syncs.
  ///   - shouldReassert: Whether the heartbeat should re-assert right now (e.g.
  ///     only while a session is live). Defaults to never.
  ///   - makeOutbound: Builds the current outbound snapshot stamped with the
  ///     given revision (and a fresh `sentAt` for an ``ExpiringMessage``).
  ///   - onInbound: Applies a received inbound snapshot, idempotently.
  public init(
    observer: ConnectivityObserver,
    heartbeat: Duration = .seconds(3),
    replyOnInbound: Bool = false,
    reassertOnReachable: Bool = true,
    shouldReassert: @escaping @MainActor () -> Bool = { false },
    makeOutbound: @escaping @MainActor (UInt64) -> Outbound,
    onInbound: @escaping @MainActor (Inbound) -> Void
  ) {
    self.observer = observer
    self.heartbeatInterval = heartbeat
    self.replyOnInbound = replyOnInbound
    self.reassertOnReachable = reassertOnReachable
    self.shouldReassert = shouldReassert
    self.makeOutbound = makeOutbound
    self.onInbound = onInbound
  }

  /// Starts consuming the observer's streams, activates the session (once), and
  /// begins the heartbeat. Safe to call more than once; only the first activates.
  public func start() async {
    // Not resumable: a second start() after stop() is a documented no-op (create a
    // new instance instead). assertNow()/heartbeat remain wired to the first run.
    guard !hasStarted else {
      return
    }
    hasStarted = true

    // Subscribe before activating so a pending application context flushed at
    // activation already has a subscriber instead of racing the callback.
    streamTask = Task { [weak self] in
      await self?.consumeStreams()
    }
    do {
      try await observer.activate()
    } catch {
      // Activation failed — surface it distinctly and skip the heartbeat, which
      // would otherwise send into a never-activated session every interval.
      lastActivationError = error
      return
    }
    startHeartbeat()
  }

  /// Cancels the stream and heartbeat tasks. Sending stops; call ``start()`` to
  /// resume is not supported — create a new instance instead.
  public func stop() {
    streamTask?.cancel()
    heartbeatTask?.cancel()
    streamTask = nil
    heartbeatTask = nil
  }

  /// Starts the heartbeat task; stored so it survives view lifecycle.
  internal func startHeartbeat() {
    // @MainActor-isolated so the only suspension point is the sleep: after it
    // resumes there is no actor hop before `shouldReassert()`, so `stop()` cannot
    // cancel between the cancellation check and the evaluation.
    heartbeatTask = Task { @MainActor [weak self, interval = heartbeatInterval] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: interval)
        } catch {
          // Cancelled mid-sleep (e.g. stop()) — exit instead of falling through
          // to one spurious reassert after the engine is considered stopped.
          return
        }
        // Re-check after the sleep: stop() may have cancelled while suspended.
        guard let self, !Task.isCancelled else {
          return
        }
        if self.shouldReassert() {
          self.assertNow()
        }
      }
    }
  }
}
