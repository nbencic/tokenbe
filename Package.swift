// swift-tools-version: 6.0
import PackageDescription
let package = Package(
  name: "TokenBeCore",
  platforms: [.macOS(.v15)],
  products: [.library(name: "TokenBeCore", targets: ["TokenBeCore"])],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.12.0")   // pin; bump only via a dedicated PR
  ],
  targets: [
    .target(name: "TokenBeCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            resources: [.copy("Store/Migrations")],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency"), .swiftLanguageMode(.v6)]),
    .testTarget(name: "TokenBeCoreTests", dependencies: ["TokenBeCore"], resources: [.copy("../Fixtures")])
  ]
)
