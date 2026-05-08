// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "TallyClaw",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .executable(name: "TallyClaw", targets: ["TallyClaw"]),
    .library(name: "TallyClawCore", targets: ["TallyClawCore"]),
    .library(name: "TallyClawDataSources", targets: ["TallyClawDataSources"]),
    .library(name: "TallyClawLedger", targets: ["TallyClawLedger"]),
    .library(name: "TallyClawUI", targets: ["TallyClawUI"])
  ],
  targets: [
    .executableTarget(
      name: "TallyClaw",
      dependencies: ["TallyClawCore", "TallyClawDataSources", "TallyClawLedger", "TallyClawUI"],
      path: "src/app"
    ),
    .target(
      name: "TallyClawCore",
      path: "src/core"
    ),
    .target(
      name: "TallyClawDataSources",
      dependencies: ["TallyClawCore"],
      path: "src/data-sources",
      linkerSettings: [
        .linkedLibrary("sqlite3")
      ]
    ),
    .target(
      name: "TallyClawLedger",
      dependencies: ["TallyClawCore"],
      path: "src/ledger",
      linkerSettings: [
        .linkedLibrary("sqlite3")
      ]
    ),
    .target(
      name: "TallyClawUI",
      dependencies: ["TallyClawCore"],
      path: "src/ui"
    ),
    .testTarget(
      name: "TallyClawCoreTests",
      dependencies: ["TallyClawCore"],
      path: "Tests/TallyClawCoreTests"
    ),
    .testTarget(
      name: "TallyClawDataSourcesTests",
      dependencies: ["TallyClawDataSources"],
      path: "Tests/TallyClawDataSourcesTests"
    ),
    .testTarget(
      name: "TallyClawLedgerTests",
      dependencies: ["TallyClawLedger"],
      path: "Tests/TallyClawLedgerTests"
    )
  ]
)
