//
//  SundialLogger+Mirror.swift
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

#if canImport(os.log)
  import os.log
#endif

extension SundialLogger {
  #if canImport(os.log)
    /// Whether log lines should also be printed to standard output.
    ///
    /// OSLog output is not carried by `devicectl device process launch
    /// --console`, which only attaches the process's standard streams. Setting
    /// the `SUNDIAL_CONSOLE` environment variable (e.g. via devicectl's
    /// `DEVICECTL_CHILD_` prefix) mirrors stream-category diagnostics to
    /// stdout so they reach the attached console.
    private static let mirrorsToStandardOutput: Bool =
      ProcessInfo.processInfo.environment["SUNDIAL_CONSOLE"] != nil
  #endif

  /// Logs a debug-level diagnostic with no structured fields.
  /// - Parameter message: The message to log.
  internal static func streamDebug(_ message: String) {
    emitStream(SundialStreamLog.Event(level: .debug, kind: .generic, message: message))
  }

  /// Logs an error-level diagnostic with no structured fields.
  /// - Parameter message: The message to log.
  internal static func streamError(_ message: String) {
    emitStream(SundialStreamLog.Event(level: .error, kind: .generic, message: message))
  }

  /// Logs a structured stream event — message plus key/value fields — to OSLog
  /// (mirrored to stdout when enabled) and forwards it to the host sink.
  /// - Parameters:
  ///   - level: Severity.
  ///   - kind: The event's intent, mapped by the host onto its own taxonomy.
  ///   - message: Human-readable summary.
  ///   - fields: Ordered diagnostic detail.
  internal static func streamEvent(
    _ level: SundialStreamLog.Level,
    _ kind: SundialStreamLog.Kind,
    _ message: String,
    fields: [SundialStreamLog.Event.Field] = []
  ) {
    emitStream(
      SundialStreamLog.Event(level: level, kind: kind, message: message, fields: fields)
    )
  }

  #if canImport(os.log)
    /// Emits an event to OSLog, the optional stdout mirror, and the host sink.
    private static func emitStream(_ event: SundialStreamLog.Event) {
      // Public: deliberate diagnostics with no user data; the default
      // .private redaction makes streamed device logs useless.
      let rendered = event.rendered
      switch event.level {
      case .debug:
        stream.debug("\(rendered, privacy: .public)")
      case .error:
        stream.error("\(rendered, privacy: .public)")
      }
      if mirrorsToStandardOutput {
        print("[SundialKit.Stream] \(rendered)")
      }
      SundialStreamLog.forward(event)
    }
  #else
    /// Emits an event to the fallback logger (which already prints) and the host
    /// sink.
    private static func emitStream(_ event: SundialStreamLog.Event) {
      let rendered = event.rendered
      switch event.level {
      case .debug:
        stream.debug(rendered)
      case .error:
        stream.error(rendered)
      }
      SundialStreamLog.forward(event)
    }
  #endif
}
