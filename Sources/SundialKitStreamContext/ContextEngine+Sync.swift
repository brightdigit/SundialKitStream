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
    Task { await self.performAssert() }
  }

  /// The awaitable core of ``assertNow()`` — stamp, build, send.
  internal func performAssert() async {
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

  internal func consumeStreams() async {
    await withTaskGroup(of: Void.self) { group in
      group.addTask { [weak self, observer] in
        for await value in await observer.reachabilityUpdates() {
          await self?.applyReachable(value)
        }
      }
      group.addTask { [weak self, observer] in
        for await value in await observer.pairedAppInstalledUpdates() {
          await self?.applyInstalled(value)
        }
      }
      group.addTask { [weak self, observer] in
        for await message in await observer.typedMessageStream() {
          guard let inbound = message as? Inbound else {
            continue
          }
          await self?.handleInbound(inbound)
        }
      }
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
