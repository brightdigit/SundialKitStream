//
//  ContextEngine+Sync.swift
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

import SundialKitStream

extension ContextEngine {
  /// Stamps the next revision, builds the current outbound snapshot, and sends it.
  ///
  /// Fire-and-forget. Drives change-, heartbeat-, reconnect-, and reply-triggered
  /// sends — every path increments the revision so the application context always
  /// differs and is never silently deduped in transit.
  public func assertNow() {
    // Track a single replaceable handle rather than spawning an untracked Task per
    // call: a rapid caller (e.g. a SwiftUI onChange) can't pile up unbounded Tasks,
    // and stop() cancels a queued assert so it short-circuits at performAssert()'s
    // phase guard. (send() itself doesn't honor cancellation, so an already-running
    // send still completes — the win is the bounded handle, not interruption.)
    assertTask?.cancel()
    assertTask = Task { await self.performAssert() }
  }

  /// The awaitable core of ``assertNow()`` — stamp, build, send.
  ///
  /// Every send (change-driven, heartbeat, reconnect, reply-on-inbound) funnels
  /// through here, so the single ``ContextEngine/Phase/stopped`` guard is what
  /// makes ``stop()`` actually halt sends — including an in-flight ``assertNow()``
  /// `Task` that only lands after `stop()`.
  internal func performAssert() async {
    guard phase != .stopped else {
      return
    }
    outboundRevision += 1
    let message = makeOutbound(outboundRevision)
    await send(message)
  }

  private func send(_ message: Outbound) async {
    do {
      _ = try await observer.send(message)
      lastSendError = nil
    } catch {
      lastSendError = error
    }
  }

  internal func applyReachable(_ value: Bool) async {
    let wasReachable = isReachable
    isReachable = value
    // Re-sync on a fresh connection (false → true), prompting a reply.
    if reassertOnReachable, value, !wasReachable {
      await performAssert()
    }
  }

  internal func applyInstalled(_ value: Bool) {
    isPairedAppInstalled = value
  }

  internal func handleInbound(_ inbound: Inbound) async {
    onInbound(inbound)
    if replyOnInbound {
      await performAssert()
    }
  }
}

extension ContextEngine {
  /// Consumes the observer's three streams until the task is cancelled or the engine
  /// deallocates.
  ///
  /// Deliberately `nonisolated static` taking a *weak-engine* closure rather than an
  /// instance method: an `await self?.consumeStreams()` would hold `self` strongly for
  /// the whole task-group lifetime, so an inner `[weak self]` could never become nil
  /// and dropping the engine without ``ContextEngine/stop()`` would leak it. Here
  /// nothing pins the engine — each loop re-resolves it per event and exits via
  /// `guard let engine` once it deallocates.
  nonisolated internal static func consumeStreams(
    observer: ConnectivityObserver,
    engine: @escaping @Sendable () -> ContextEngine?
  ) async {
    await withTaskGroup(of: Void.self) { group in
      group.addTask { await Self.consumeReachability(observer, engine) }
      group.addTask { await Self.consumeInstalled(observer, engine) }
      group.addTask { await Self.consumeInbound(observer, engine) }
    }
  }

  nonisolated private static func consumeReachability(
    _ observer: ConnectivityObserver,
    _ engine: @Sendable () -> ContextEngine?
  ) async {
    for await value in await observer.reachabilityUpdates() {
      guard let engine = engine() else {
        return
      }
      await engine.applyReachable(value)
    }
  }

  nonisolated private static func consumeInstalled(
    _ observer: ConnectivityObserver,
    _ engine: @Sendable () -> ContextEngine?
  ) async {
    for await value in await observer.pairedAppInstalledUpdates() {
      guard let engine = engine() else {
        return
      }
      await engine.applyInstalled(value)
    }
  }

  nonisolated private static func consumeInbound(
    _ observer: ConnectivityObserver,
    _ engine: @Sendable () -> ContextEngine?
  ) async {
    for await message in await observer.typedMessageStream() {
      guard let engine = engine() else {
        return
      }
      guard let inbound = message as? Inbound else {
        continue
      }
      await engine.handleInbound(inbound)
    }
  }
}
