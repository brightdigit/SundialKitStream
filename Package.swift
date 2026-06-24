// swift-tools-version: 6.1
// swiftlint:disable explicit_acl explicit_top_level_acl

import PackageDescription

// MARK: - Swift Settings Configuration

let swiftSettings: [SwiftSetting] = [
  // Swift 6.2 Upcoming Features
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("InternalImportsByDefault"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("FullTypedThrows"),

  // Experimental Features
  .enableExperimentalFeature("BitwiseCopyable"),
  .enableExperimentalFeature("BorrowingSwitch"),
  .enableExperimentalFeature("ExtensionMacros"),
  .enableExperimentalFeature("FreestandingExpressionMacros"),
  .enableExperimentalFeature("InitAccessors"),
  .enableExperimentalFeature("IsolatedAny"),
  .enableExperimentalFeature("MoveOnlyClasses"),
  .enableExperimentalFeature("MoveOnlyEnumDeinits"),
  .enableExperimentalFeature("MoveOnlyPartialConsumption"),
  .enableExperimentalFeature("MoveOnlyResilientTypes"),
  .enableExperimentalFeature("MoveOnlyTuples"),
  .enableExperimentalFeature("NoncopyableGenerics"),
  .enableExperimentalFeature("RawLayout"),
  .enableExperimentalFeature("ReferenceBindings"),
  .enableExperimentalFeature("SendingArgsAndResults"),
  .enableExperimentalFeature("SymbolLinkageMarkers"),
  .enableExperimentalFeature("TransferringArgsAndResults"),
  .enableExperimentalFeature("VariadicGenerics"),
  .enableExperimentalFeature("WarnUnsafeReflection")

  // Enhanced compiler checking
  // .unsafeFlags([
  //   "-warn-concurrency",
  //   "-enable-actor-data-race-checks",
  //   "-strict-concurrency=complete",
  //   "-enable-testing",
  //   "-Xfrontend", "-warn-long-function-bodies=100",
  //   "-Xfrontend", "-warn-long-expression-type-checking=100"
  // ])
]

let package = Package(
  name: "SundialKitStream",
  platforms: [
    // Raised to the floor required by `Synchronization.Mutex` (used by the
    // host-log bridge in SundialStreamLog).
    .iOS(.v18),
    .watchOS(.v11),
    .tvOS(.v18),
    .macOS(.v15)
  ],
  products: [
    .library(
      name: "SundialKitStream",
      targets: ["SundialKitStream"]
    ),
    .library(
      name: "SundialKitStreamContext",
      targets: ["SundialKitStreamContext"]
    )
  ],
  dependencies: [
    // Pinned to the matching SundialKit beta branch during co-development: the two
    // packages evolve together until the API stabilizes. This intentionally trades
    // build reproducibility for that lockstep — move to a version constraint
    // (e.g. .upToNextMinor(from:)) once SundialKit cuts a release tag.
    .package(url: "https://github.com/brightdigit/SundialKit.git", branch: "atleast-beta.6")
  ],
  targets: [
    .target(
      name: "SundialKitStream",
      dependencies: [
        .product(name: "SundialKitCore", package: "SundialKit"),
        .product(name: "SundialKitNetwork", package: "SundialKit"),
        .product(name: "SundialKitConnectivity", package: "SundialKit")
      ],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "SundialKitStreamContext",
      dependencies: [
        "SundialKitStream",
        .product(name: "SundialKitConnectivity", package: "SundialKit"),
        .product(name: "SundialKitCore", package: "SundialKit")
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "SundialKitStreamTests",
      dependencies: ["SundialKitStream", "SundialKitStreamContext"],
      swiftSettings: swiftSettings
    )
  ]
)
// swiftlint:enable explicit_acl explicit_top_level_acl
