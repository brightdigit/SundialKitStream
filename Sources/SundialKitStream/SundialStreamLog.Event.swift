//
//  SundialStreamLog.Event.swift
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

extension SundialStreamLog {
  /// The intent of a stream-log event, so a host sink can map it onto its own
  /// structured signal taxonomy (e.g. Broadcast's `Log.Signal`).
  public enum Kind: String, Sendable {
    /// An outgoing send attempt (transport selection / dispatch).
    case send
    /// The result of a send, success or failure.
    case sendResult
    /// An incoming message handed to subscribers.
    case received
    /// A message intentionally dropped (e.g. a replayed application context).
    case dropped
    /// A reachability / pairing / activation state change.
    case reachability
    /// Session lifecycle (activation, teardown).
    case lifecycle
    /// Uncategorised diagnostic text.
    case generic
  }

  /// A structured stream-log event: a human-readable `message` plus ordered
  /// key/value `fields` carrying the diagnostic detail (message type, transport,
  /// reachability, …) that a string alone would lose.
  public struct Event: Sendable {
    /// A single rendered diagnostic field.
    public struct Field: Sendable {
      public let key: String
      public let value: String

      public init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
      }
    }

    public let level: Level
    public let kind: Kind
    public let message: String
    public let fields: [Field]

    /// `message` with any fields appended as `key=value`, for OSLog/stdout output.
    public var rendered: String {
      guard !fields.isEmpty else {
        return message
      }
      let fieldString = fields.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
      return "\(message) \(fieldString)"
    }

    public init(
      level: Level,
      kind: Kind,
      message: String,
      fields: [Field] = []
    ) {
      self.level = level
      self.kind = kind
      self.message = message
      self.fields = fields
    }
  }
}
