//
//  NetworkObserver+Handlers.swift
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

#if canImport(Network)
  import Foundation
  import SundialKitNetwork

  @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
  extension NetworkObserver {
    // MARK: - Internal Handlers

    internal func handlePathUpdate(_ path: MonitorType.PathType) {
      currentPath = path

      // Notify all active path stream subscribers
      for continuation in pathContinuations.values {
        continuation.yield(path)
      }
      for continuation in pathStatusContinuations.values {
        continuation.yield(path.pathStatus)
      }
      for continuation in isExpensiveContinuations.values {
        continuation.yield(path.isExpensive)
      }
      for continuation in isConstrainedContinuations.values {
        continuation.yield(path.isConstrained)
      }
    }

    internal func handlePingStatusUpdate(_ status: PingType.StatusType) {
      currentPingStatus = status

      // Notify all active ping status stream subscribers
      for continuation in pingStatusContinuations.values {
        continuation.yield(status)
      }
    }

    // MARK: - Continuation Removal

    internal func removePathContinuation(id: UUID) {
      pathContinuations.removeValue(forKey: id)
    }

    internal func removePathStatusContinuation(id: UUID) {
      pathStatusContinuations.removeValue(forKey: id)
    }

    internal func removeIsExpensiveContinuation(id: UUID) {
      isExpensiveContinuations.removeValue(forKey: id)
    }

    internal func removeIsConstrainedContinuation(id: UUID) {
      isConstrainedContinuations.removeValue(forKey: id)
    }

    internal func removePingStatusContinuation(id: UUID) {
      pingStatusContinuations.removeValue(forKey: id)
    }
  }
#endif
