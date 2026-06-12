// swift-tools-version:6.2
import PackageDescription

let package = Package(
	name: "Bellhop",
	platforms: [
		.macOS(.v14)
	],
	dependencies: [
		.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
		.package(url: "https://github.com/UnpxreTW/SwiftStyleKit.git", from: "1.2.0"),
	],
	targets: [
		.executableTarget(
			name: "Bellhop",
			dependencies: ["BellhopKit"],
			plugins: [.plugin(name: "SwiftStyleLint", package: "SwiftStyleKit")]
		),
		.target(
			name: "BellhopKit",
			dependencies: [
				.product(name: "MCP", package: "swift-sdk"),
			],
			plugins: [.plugin(name: "SwiftStyleLint", package: "SwiftStyleKit")]
		),
	]
)
