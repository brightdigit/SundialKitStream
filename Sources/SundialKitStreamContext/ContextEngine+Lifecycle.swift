//
//  ContextEngine+Lifecycle.swift
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
  /// Starts consuming the observer's streams, activates the session, and begins the
  /// heartbeat. A no-op once running; after an activation failure it returns the
  /// engine to idle so a later call can retry. A call after ``stop()`` is a no-op —
  /// `stop()` is terminal, so create a new instance to restart.
  public func start() async {
    guard phase == .idle else {
      return
    }
    phase = .starting

    // Subscribe before activating so a pending application context flushed at
    // activation already has a subscriber instead of racing the callback. The
    // consumer is fed a weak-engine closure (not `self?.consumeStreams()`) so the
    // running task never pins `self`: dropping the engine without stop() lets it
    // deallocate and the stream loops exit on their next event.
    let engine: @Sendable () -> ContextEngine? = { [weak self] in self }
    streamTask = Task { [observer] in
      await Self.consumeStreams(observer: observer, engine: engine)
    }
    do {
      try await observer.activate()
    } catch {
      // Activation failed — surface it distinctly and tear down. Returning to
      // .idle makes a retry possible; cancelling streamTask stops the consume
      // loop from sending into the never-activated session (reply-on-inbound /
      // reassert-on-reachable both route through performAssert).
      lastActivationError = error
      streamTask?.cancel()
      streamTask = nil
      // stop() may have raced the activate() suspension above and set .stopped;
      // only revert to .idle (retryable) when it didn't, so stop() stays terminal.
      if phase != .stopped {
        phase = .idle
      }
      return
    }
    // stop() may have run during the activation suspension above: it set
    // phase = .stopped and already cancelled the tasks, so don't start the
    // heartbeat (which would otherwise outlive the stop and keep sending).
    guard phase == .starting else {
      return
    }
    phase = .running
    startHeartbeat()
  }

  /// Cancels the stream and heartbeat tasks and blocks further sends. Terminal:
  /// ``start()`` will not resume a stopped engine — create a new instance instead.
  public func stop() {
    phase = .stopped
    streamTask?.cancel()
    heartbeatTask?.cancel()
    assertTask?.cancel()
    streamTask = nil
    heartbeatTask = nil
    assertTask = nil
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
        // Await the assert directly rather than spawning an untracked Task per
        // tick: this loop is already async @MainActor, so awaiting keeps the
        // sends ordered and lets the phase guard short-circuit a post-stop tick.
        if self.shouldReassert() {
          await self.performAssert()
        }
      }
    }
  }
}
