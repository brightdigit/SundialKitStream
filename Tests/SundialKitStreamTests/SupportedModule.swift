//
//  WASMSupport.swift
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

internal struct SupportedModule: OptionSet, Hashable {
  internal static let dispatch: Self = .init(rawValue: 1)
  internal static let network: Self = .init(rawValue: 2)

  private static let supported: Self = {
    var values: [Self] = []
    #if canImport(Network)
      values.append(.network)
    #endif
    #if canImport(Dispatch)
      values.append(.dispatch)
    #endif
    return .init(values)
  }()

  internal let rawValue: Int

  internal var isSupported: Bool {
    self.isSubset(of: Self.supported)
  }

  internal init(rawValue: Int) {
    self.rawValue = rawValue
  }
}
