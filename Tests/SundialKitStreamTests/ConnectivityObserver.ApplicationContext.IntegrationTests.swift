//
//  ConnectivityObserver.ApplicationContext.IntegrationTests.swift
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
@testable import SundialKitCore
@testable import SundialKitStream

#if canImport(AppKit)
  import AppKit
#endif

extension ConnectivityObserver {
  @Suite("Application Context Tests")
  internal enum ApplicationContext {}
}

extension ConnectivityObserver.ApplicationContext {
  /// Integration coverage for `ConnectivityObserver`'s public application-context
  /// API and the app-lifecycle observer that re-delivers a pending context when
  /// the app becomes active.
  @Suite("ConnectivityObserver application context integration")
  internal struct IntegrationTests {
    private static func installedSession() -> MockConnectivitySession {
      let session = MockConnectivitySession()
      session.isPaired = true
      session.isPairedAppInstalled = true
      return session
    }

    @Test("updateApplicationContext forwards the context to the session")
    internal func updateForwardsContext() async throws {
      let session = Self.installedSession()
      let observer = ConnectivityObserver(session: session)

      try await observer.updateApplicationContext(["__type": "Ping", "value": 1])

      #expect(session.applicationContexts.count == 1)
      #expect(session.applicationContexts.first?["__type"] as? String == "Ping")
    }

    @Test("updateApplicationContext propagates session errors")
    internal func updatePropagatesError() async {
      let session = Self.installedSession()
      session.updateApplicationContextError = ConnectivityError.payloadTooLarge
      let observer = ConnectivityObserver(session: session)

      await #expect(throws: ConnectivityError.payloadTooLarge) {
        try await observer.updateApplicationContext(["__type": "X"])
      }
    }

    // The watchOS fix swaps the dead `NSExtensionHost…` name for
    // `WKApplication.didBecomeActiveNotification`; that branch can't run under
    // `swift test` on macOS, so this exercises the structurally identical
    // `NSApplication.didBecomeActiveNotification` branch — the same
    // "pending context delivered on becoming active" wiring. The notification
    // observer subscribes asynchronously, so the test re-posts on a bounded
    // schedule (which also bounds the test) rather than relying on a single post.
    #if canImport(AppKit)
      @Test("Pending application context is delivered when the app becomes active")
      internal func deliversPendingContextOnBecomingActive() async throws {
        let session = Self.installedSession()
        session.receivedApplicationContext = ["__type": "Pending", "value": 7]
        let observer = ConnectivityObserver(session: session)

        let stream = await observer.messageStream()
        await observer.setupAppLifecycleObserver()

        let delivered = await withTaskGroup(of: ConnectivityReceiveResult?.self) { group in
          group.addTask {
            for await result in stream {
              return result
            }
            return nil
          }
          group.addTask {
            for _ in 0..<200 where !Task.isCancelled {
              NotificationCenter.default.post(
                name: NSApplication.didBecomeActiveNotification,
                object: nil
              )
              try? await Task.sleep(for: .milliseconds(10))
            }
            return nil
          }
          var received: ConnectivityReceiveResult?
          for await case let result? in group {
            received = result
            break
          }
          group.cancelAll()
          return received
        }

        let result = try #require(delivered)
        #expect(result.message["__type"] as? String == "Pending")
      }
    #endif
  }
}
