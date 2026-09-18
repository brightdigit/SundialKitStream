## What's Changed

The headline of this alpha is a **critical stack-overflow fix** in
`SundialStreamLog`, plus locking the SundialKit dependency to
`2.0.0-alpha.4` and bringing the Apple CI matrix onto Xcode 27 / 26.6.

> ContextEngine, the `SundialKitContext` product split, and the iOS 18 /
> watchOS 11 / tvOS 18 / macOS 15 floors already shipped in
> [1.0.0-alpha.3](https://github.com/brightdigit/SundialKitStream/releases/tag/1.0.0-alpha.3).
> This release does not re-introduce them — it documents them correctly in
> the README and DocC, which had still listed the old floors.

### ⚠️ Breaking

* **SundialKit floor raised to `2.0.0-alpha.4`** — replace any
  `from: "2.0.0-alpha.3"` (or branch pin) with
  `from: "2.0.0-alpha.4"`.

### Fixes

* **Stop `SundialStreamLog` accumulating reabstraction thunks** by @leogdion in https://github.com/brightdigit/SundialKitStream/pull/24 — reading a bare function value out of a `Mutex` wrapped the sink deeper on every forward until the stack blew (~23 minutes into every AtLeast watch session; brightdigit/AtLeast#329). Reproduces at both `-Onone` and `-O` on Swift 6.4. Upstream: [swiftlang/swift#91348](https://github.com/swiftlang/swift/issues/91348).

### Dependencies

* Bump SundialKit from `2.0.0-alpha.3` to **`2.0.0-alpha.4`** (version pin; co-development branch pin removed) via the release train in https://github.com/brightdigit/SundialKitStream/pull/25

### Documentation

* README and DocC now match the real deployment targets (iOS 18+ / watchOS 11+ / tvOS 18+ / macOS 15+) and install examples for `1.0.0-alpha.4` / SundialKit `2.0.0-alpha.4`
* Install snippets document the optional `SundialKitContext` product for `ContextEngine`
* Guides unchanged from alpha.3: [Context Engine](Documentation/CONTEXT_ENGINE.md), [Watch Comms Reliability](Documentation/WATCH_COMMS_RELIABILITY.md), [Debugging](Documentation/DEBUGGING.md)

### CI & Infrastructure

* Fix unresolvable `setup-sundialkit` action ref and move the Apple matrix to **Xcode 27** by @leogdion in https://github.com/brightdigit/SundialKitStream/pull/26
* Cover stable **Xcode 26.6** on `macos-26` (SPM + iOS / watchOS / tvOS 26.5 simulators); drop the Xcode 16.4 legs
* Drop the co-development `setup-sundialkit` CI steps now that SundialKit is pinned by release tag again
* Remove the temporary `#26` verification guards from the workflow

### Maintenance

* Release polish (docs, version pin, CI cleanup) in https://github.com/brightdigit/SundialKitStream/pull/27

**Full Changelog**: https://github.com/brightdigit/SundialKitStream/compare/1.0.0-alpha.3...1.0.0-alpha.4
