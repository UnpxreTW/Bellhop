//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

// MARK: - FileAccessResolvedRoot

/// 載入後確認有效的 root：保留字面路徑與各種真實路徑形。
///
/// 每一形都可作為前綴比對的基準——請求可能以 `/tmp/...` 這類 symlink 形送進來，
/// 而 fd 回報的真實路徑是 `/private/tmp/...`；只認其中一種會讓另一種形永遠被拒。
internal struct FileAccessResolvedRoot: Equatable, Sendable {

	/// `~` 展開並字面正規化後的路徑。
	internal let literalPath: String

	/// 真實路徑（優先取 `F_GETPATH` 形、取不到時用 `realpath(3)` 形）。
	internal let realPath: String

	/// 前綴比對用的各形（字面形、`realpath(3)` 形、`F_GETPATH` 形，去重）。
	internal let paths: [String]

	/// 是否允許列出此 root 之下的目錄。
	internal let listable: Bool
}
