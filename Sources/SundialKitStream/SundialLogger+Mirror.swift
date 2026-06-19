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

  @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
  extension SundialLogger {
    /// Whether log lines should also be printed to standard output.
    ///
    /// OSLog output is not carried by `devicectl device process launch
    /// --console`, which only attaches the process's standard streams. Setting
    /// the `SUNDIAL_CONSOLE` environment variable (e.g. via devicectl's
    /// `DEVICECTL_CHILD_` prefix) mirrors stream-category diagnostics to
    /// stdout so they reach the attached console.
    internal static let mirrorsToStandardOutput: Bool =
      ProcessInfo.processInfo.environment["SUNDIAL_CONSOLE"] != nil

    /// Logs a debug-level message to the stream logger, mirrored to stdout
    /// when ``mirrorsToStandardOutput`` is enabled.
    ///
    /// Debug level keeps routine send-path diagnostics out of persisted
    /// production logs; the stdout mirror — what device-log streaming
    /// actually reads — is independent of the OSLog level.
    /// - Parameter message: The message to log.
    internal static func streamDebug(_ message: String) {
      // Public: deliberate diagnostics with no user data; the default
      // .private redaction makes streamed device logs useless.
      stream.debug("\(message, privacy: .public)")
      if mirrorsToStandardOutput {
        print("[SundialKit.Stream] \(message)")
      }
      SundialStreamLog.forward(.debug, message)
    }

    /// Logs an error-level message to the stream logger, mirrored to stdout
    /// when ``mirrorsToStandardOutput`` is enabled.
    /// - Parameter message: The message to log.
    internal static func streamError(_ message: String) {
      stream.error("\(message, privacy: .public)")
      if mirrorsToStandardOutput {
        print("[SundialKit.Stream] ERROR: \(message)")
      }
      SundialStreamLog.forward(.error, message)
    }
  }
#else
  extension SundialLogger {
    /// Logs a debug-level message to the stream logger.
    ///
    /// The fallback logger already prints to stdout, so no mirror is needed.
    /// - Parameter message: The message to log.
    internal static func streamDebug(_ message: String) {
      stream.debug(message)
      SundialStreamLog.forward(.debug, message)
    }

    /// Logs an error-level message to the stream logger.
    ///
    /// The fallback logger already prints to stdout, so no mirror is needed.
    /// - Parameter message: The message to log.
    internal static func streamError(_ message: String) {
      stream.error(message)
      SundialStreamLog.forward(.error, message)
    }
  }
#endif
