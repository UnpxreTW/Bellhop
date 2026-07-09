//
//  BellhopVersionPlugin
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation
import PackagePlugin

/// 於 build 前從 git tag 產生 `BellhopVersion.swift`，讓版本號單一來源＝git tag。
///
/// 版本字串取 `git describe --tags`（去掉 `v` 前綴）；淺 clone 無 tag 時退回
/// commit hash（`--always`）、完全無 git 環境時退回 `0.0.0-unknown`。
@main
struct BellhopVersionPlugin: BuildToolPlugin {

	/// 建立 prebuild command：以 `/bin/sh` 跑 `git describe` 並寫出生成原始碼。
	func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
		let outputDirectory = context.pluginWorkDirectoryURL.appending(path: "GeneratedSources")
		let script = """
			set -u
			version=$(GIT_OPTIONAL_LOCKS=0 git -C "$1" describe --tags --always 2>/dev/null || echo 0.0.0-unknown)
			version=${version#v}
			mkdir -p "$2"
			file="$2/BellhopVersion.swift"
			content="// 由 BellhopVersionPlugin 自動生成，勿手動編輯、勿提交。
			enum BellhopVersion {
			\tstatic let current: String = \\"$version\\"
			}"
			if [ ! -f "$file" ] || [ "$content" != "$(cat "$file")" ]; then
			\tprintf '%s\\n' "$content" > "$file"
			fi
			"""
		return [
			.prebuildCommand(
				displayName: "Generate BellhopVersion.swift",
				executable: URL(fileURLWithPath: "/bin/sh"),
				arguments: ["-c", script, "bellhop-version", context.package.directoryURL.path, outputDirectory.path],
				outputFilesDirectory: outputDirectory
			)
		]
	}
}
