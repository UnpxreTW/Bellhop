// swift-tools-version:6.2
import PackageDescription

let package = Package(
	name: "Bellhop",
	platforms: [
		.macOS(.v14)
	],
	dependencies: [
		// Official MCP Swift SDK. Pinned exactly: pre-1.0, minor bumps may break.
		.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
	],
	targets: [
		// Thin executable: wires up and runs the server.
		.executableTarget(
			name: "Bellhop",
			dependencies: ["BellhopKit"]
		),
		// Library: tool definitions, handlers, and server assembly (testable).
		.target(
			name: "BellhopKit",
			dependencies: [
				.product(name: "MCP", package: "swift-sdk"),
			]
		),
		.testTarget(
			name: "BellhopKitTests",
			dependencies: ["BellhopKit"]
		),
	]
)
