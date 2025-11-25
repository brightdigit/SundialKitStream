# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

SundialKitStream is a modern Swift 6.1+ async/await observation plugin for SundialKit, providing actor-based observers with AsyncStream APIs for network monitoring and WatchConnectivity communication. The package prioritizes strict concurrency safety, avoiding `@unchecked Sendable` conformances in favor of proper actor isolation.

## Development Commands

### Building

```bash
# Build the package
swift build

# Build including tests
swift build --build-tests

# Run tests
swift test
```

### Linting

The project uses a comprehensive linting setup with SwiftLint, swift-format, and periphery (dead code detection):

```bash
# Run all linting and formatting
./Scripts/lint.sh

# Format only (skip linting checks)
FORMAT_ONLY=1 ./Scripts/lint.sh

# Strict mode (used in CI)
LINT_MODE=STRICT ./Scripts/lint.sh
```

**Important**: Linting requires `mise` to be installed. The lint script uses mise to manage tool versions via `.mise.toml`.

### Testing

```bash
# Run all tests
swift test

# Run a specific test target
swift test --filter SundialKitStreamTests

# Run a specific test class
swift test --filter NetworkObserverTests

# Run a specific test method
swift test --filter NetworkObserverTests.testStreamUpdates
```

## Code Architecture

### Layer Architecture

SundialKitStream follows a three-layer architecture:

1. **Core Protocols** (Dependencies from SundialKit package):
   - `SundialKitCore` - Base protocols and types (`ActivationState`, `ConnectivityError`, etc.)
   - `SundialKitNetwork` - Network monitoring protocols (`PathMonitor`, `NetworkPing`, `PathStatus`)
   - `SundialKitConnectivity` - WatchConnectivity protocols (`ConnectivitySession`, `Messagable`)

2. **Observer Layer** (This package - SundialKitStream):
   - Actor-based observers: `NetworkObserver`, `ConnectivityObserver`
   - AsyncStream-based state delivery
   - Manages continuations and distributes updates to multiple subscribers

### Core Observers

#### NetworkObserver

Actor-based network connectivity monitoring with AsyncStream APIs:

- **Generic over**: `PathMonitor` (typically `NWPathMonitorAdapter`) and `NetworkPing`
- **Streams**: `pathStatusStream`, `isExpensiveStream`, `isConstrainedStream`
- **Thread Safety**: Actor isolation ensures safe concurrent access
- **Location**: Sources/SundialKitStream/NetworkObserver.swift

#### ConnectivityObserver

Actor-based WatchConnectivity communication with AsyncStream APIs:

- **Protocols**: Conforms to `ConnectivitySessionDelegate`, `StateHandling`, `MessageHandling`
- **Key Components**:
  - `ConnectivityStateManager` - Manages activation, reachability, and pairing state
  - `StreamContinuationManager` - Centralized continuation management for all stream types
  - `MessageDistributor` - Handles incoming message distribution to subscribers
  - `MessageRouter` - Routes outgoing messages through appropriate transports
- **Streams**: `activationStates()`, `activationCompletionStream()`, `reachabilityStream()`, `messageStream()`, `typedMessageStream()`
- **Location**: Sources/SundialKitStream/ConnectivityObserver.swift

### Key Architectural Patterns

#### AsyncStream Continuation Management

The codebase uses a centralized continuation management pattern via `StreamContinuationManager`:

- Each stream type has its own continuation dictionary keyed by UUID
- Registration asserts prevent duplicate continuations
- Removal asserts catch programming errors
- Yielding iterates all registered continuations for fan-out distribution
- **Location**: Sources/SundialKitStream/StreamContinuationManager.swift

#### State Management

`ConnectivityStateManager` coordinates state updates with stream notifications:

- Maintains `ConnectivityState` with activation, reachability, and pairing information
- Synchronizes state updates with continuation notifications
- Provides read-only snapshot accessors for current state
- **Location**: Sources/SundialKitStream/ConnectivityStateManager.swift

#### Message Handling

Message flow uses a routing and distribution pattern:

- `MessageRouter` - Selects appropriate transport (interactive message, application context, etc.)
- `MessageDispatcher` - Transforms protocol-level callbacks into async operations
- `MessageDistributor` - Distributes received messages to all active stream subscribers
- Supports both untyped (`[String: any Sendable]`) and typed (`Messagable`) messages

## Swift Version and Compiler Settings

This package requires **Swift 6.1+** and enables extensive experimental features:

- **Swift 6.2 Upcoming Features**: ExistentialAny, InternalImportsByDefault, MemberImportVisibility, FullTypedThrows
- **Experimental Features**: BitwiseCopyable, BorrowingSwitch, NoncopyableGenerics, TransferringArgsAndResults, VariadicGenerics, and many more (see Package.swift:8-34)
- **Strict Concurrency**: The project operates in Swift 6 strict concurrency mode

When writing new code, ensure:
- All public types properly declare their concurrency characteristics (`actor`, `@MainActor`, `Sendable`)
- No `@unchecked Sendable` conformances are added
- AsyncStream continuations are managed through `StreamContinuationManager`

## File Organization

Source files use functional organization with extensions:

- Main type definition: `TypeName.swift`
- Extensions by functionality: `TypeName+Functionality.swift`
- Example: `ConnectivityObserver.swift`, `ConnectivityObserver+Lifecycle.swift`, `ConnectivityObserver+Messaging.swift`, `ConnectivityObserver+Streams.swift`

Tests follow a similar pattern with hierarchical organization:

- Test suites: `TypeName.swift`, `TypeName+Category.swift`
- Individual test files: `TypeName.Category.SpecificTests.swift`
- Example: `ConnectivityStateManager.swift`, `ConnectivityStateManager.State.swift`, `ConnectivityStateManager.State.UpdateTests.swift`

## Code Style and Linting

The project enforces strict code quality standards:

- **File Length**: Warning at 225 lines, error at 300 lines
- **Function Body Length**: Warning at 50 lines, error at 76 lines
- **Line Length**: Warning at 108 characters, error at 200 characters
- **Cyclomatic Complexity**: Warning at 6, error at 12
- **Indentation**: 2 spaces (configured in .swiftlint.yml:120)
- **Access Control**: Explicit access levels required (`explicit_acl`, `explicit_top_level_acl`)
- **File Headers**: All source files require proper copyright headers (enforced by Scripts/header.sh)

Disabled rules:
- `nesting`, `implicit_getter`, `switch_case_alignment`, `closure_parameter_position`, `trailing_comma`, `opening_brace`, `pattern_matching_keywords`, `todo`

## Dependencies

This package depends on SundialKit v2.0.0+ which provides three products:

- `SundialKitCore` - Core protocols and types
- `SundialKitNetwork` - Network monitoring abstractions over Apple's Network framework
- `SundialKitConnectivity` - WatchConnectivity abstractions

## Platform Support

- iOS 16+
- watchOS 9+
- tvOS 16+
- macOS 13+

## Testing Patterns

Tests use mock implementations for protocol-based abstractions:

- `MockPathMonitor` - Simulates network path changes
- `MockNetworkPing` - Simulates ping operations
- `MockConnectivitySession` - Simulates WatchConnectivity behavior
- `TestValueCapture` - Captures async stream values for testing

When writing tests:
- Use actor-isolated test methods when testing actors
- Capture stream values with async task groups or `TestValueCapture`
- Test both success and error paths for `Result`-based streams (e.g., `activationCompletionStream()`)
- In order to run the builds and tests for iOS or watchOS, use xcodebuild.
- Don't use swift package generate-xcodeproj