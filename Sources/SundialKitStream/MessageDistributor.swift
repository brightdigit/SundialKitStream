//
//  MessageDistributor.swift
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

public import Foundation
public import SundialKitConnectivity
public import SundialKitCore

/// Distributes incoming messages to appropriate stream subscribers
///
/// This type handles message decoding and distribution to both
/// raw message streams and typed message streams.
@available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
public actor MessageDistributor {
  // MARK: - Properties

  private let continuationManager: StreamContinuationManager
  private let messageDecoder: MessageDecoder?

  /// The last application context successfully delivered to subscribers.
  ///
  /// WatchConnectivity persists the counterpart's last context and the
  /// observer re-checks it after activation, on every reachability change,
  /// and on foreground — so the same dictionary arrives here repeatedly.
  /// Exact duplicates are suppressed; WCSession never transmits two
  /// identical consecutive contexts, so only replays are affected.
  private var lastDeliveredApplicationContext: ConnectivityMessage?

  // MARK: - Initialization

  internal init(
    continuationManager: StreamContinuationManager,
    messageDecoder: MessageDecoder?
  ) {
    self.continuationManager = continuationManager
    self.messageDecoder = messageDecoder
  }

  // MARK: - Context Comparison

  /// Compares two application contexts for equality in a way that is stable
  /// across platforms.
  ///
  /// `NSDictionary.isEqual(to:)` relies on Objective-C bridging of the
  /// heterogeneous `[String: any Sendable]` values, which swift-corelibs
  /// Foundation (Linux/Windows/Android/WASI) does not reproduce — identical
  /// contexts compare unequal there, defeating replay suppression. Canonical
  /// JSON (sorted keys) yields identical bytes for equal contexts on every
  /// platform. A context holding non-JSON property-list values (e.g. `Date`,
  /// `Data`) falls back to `NSDictionary`; in that case it is treated as
  /// changed off Apple platforms and delivered, which is safe (replays only).
  private static func applicationContext(
    _ lhs: ConnectivityMessage,
    matches rhs: ConnectivityMessage
  ) -> Bool {
    let options: JSONSerialization.WritingOptions = [.sortedKeys]
    if let lhsData = try? JSONSerialization.data(withJSONObject: lhs, options: options),
      let rhsData = try? JSONSerialization.data(withJSONObject: rhs, options: options)
    {
      return lhsData == rhsData
    }
    // Non-JSON property-list values (e.g. Date/Data): equality falls back to
    // NSDictionary, which is only reliable on Apple platforms.
    SundialLogger.streamDebug(
      "applicationContext comparison fell back to NSDictionary (non-JSON values)"
    )
    return NSDictionary(dictionary: lhs).isEqual(to: rhs)
  }

  // MARK: - Message Handling

  internal func handleMessage(
    _ message: ConnectivityMessage,
    replyHandler: @escaping @Sendable ([String: any Sendable]) -> Void
  ) async {
    // Send to raw stream subscribers
    let result = ConnectivityReceiveResult(message: message, context: .replyWith(replyHandler))
    await continuationManager.yieldMessageReceived(result)

    // Decode and send to typed stream subscribers
    if let decoder = messageDecoder {
      do {
        let decoded = try decoder.decode(message)
        await continuationManager.yieldTypedMessage(decoded)
      } catch {
        // Remote input, not a programmer error — a counterpart running a
        // different build sends schemas we can't decode. Log and drop.
        SundialLogger.streamError("Failed to decode message: \(String(describing: error))")
      }
    }
  }

  internal func handleApplicationContext(
    _ applicationContext: ConnectivityMessage,
    error: (any Error)?
  ) async {
    // Suppress replays of the context already delivered (see
    // `lastDeliveredApplicationContext`). Errored deliveries bypass the
    // cache: they reach raw subscribers and are never recorded as delivered.
    if error == nil {
      if let last = lastDeliveredApplicationContext,
        Self.applicationContext(applicationContext, matches: last)
      {
        SundialLogger.streamDebug("Skipping replayed application context")
        return
      }
      lastDeliveredApplicationContext = applicationContext
    }

    // Send to raw stream subscribers
    let result = ConnectivityReceiveResult(
      message: applicationContext,
      context: .applicationContext
    )
    await continuationManager.yieldMessageReceived(result)

    // Decode and send to typed stream subscribers if no error
    if error == nil, let decoder = messageDecoder {
      do {
        let decoded = try decoder.decode(applicationContext)
        await continuationManager.yieldTypedMessage(decoded)
      } catch {
        // Remote input, not a programmer error — a counterpart running a
        // different build sends schemas we can't decode. Log and drop.
        SundialLogger.streamError(
          "Failed to decode application context: \(String(describing: error))"
        )
      }
    }
  }

  internal func handleBinaryMessage(
    _ data: Data,
    replyHandler: @escaping @Sendable (Data) -> Void
  ) async {
    // TODO: Emit to raw message stream with reply handler like handleMessage does
    // This will require extending ConnectivityReceiveResult to support binary data

    // Decode and send to typed stream subscribers
    if let decoder = messageDecoder {
      do {
        let decoded = try decoder.decodeBinary(data)
        await continuationManager.yieldTypedMessage(decoded)
      } catch {
        // Remote input, not a programmer error — a counterpart running a
        // different build sends schemas we can't decode. Log and drop.
        SundialLogger.streamError(
          "Failed to decode binary message: \(String(describing: error))"
        )
      }
    }
  }

  internal func notifySendResult(_ result: ConnectivitySendResult) async {
    await continuationManager.yieldSendResult(result)
  }
}
