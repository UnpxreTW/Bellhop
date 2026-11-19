//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

// MARK: - FileAccessPath

/// 檔案存取政策用的路徑運算：`~` 展開、字面正規化、以路徑段為單位的前綴比對。
///
/// 字面運算一律不碰檔案系統；碰檔案系統的只有 ``resolved(_:)``、``descriptorResolved(_:)``
/// 與 ``path(ofDescriptor:)``——前兩者只用在載入政策時解析 root、`denies` 與家目錄，請求路徑的真實路徑
/// 則由開啟後的 fd 取得。
internal enum FileAccessPath {

	// MARK: Internal

	/// 把政策或請求中的路徑展開成絕對路徑。
	///
	/// - Parameters:
	///   - raw: 原始字串；`~` 與 `~/…` 展開為家目錄，其餘必須以 `/` 開頭。
	///   - homeDirectory: 家目錄（可注入，測試用假家目錄）。
	/// - Returns: 展開後的字串；空字串、含 NUL、相對路徑、`~user` 形回 nil。
	internal static func expand(_ raw: String, homeDirectory: String) -> String? {
		guard
			!raw.isEmpty,
			!raw.utf8.contains(0)
		else { return nil }
		if raw == "~" { return homeDirectory }
		if raw.hasPrefix("~/") { return homeDirectory + raw.dropFirst(1) }
		guard raw.hasPrefix("/") else { return nil }
		return raw
	}

	/// 字面正規化：消去 `.`、`..` 與重複斜線，不解析 symlink。
	///
	/// 輸入須為絕對路徑；`..` 越過根目錄時停在 `/`。路徑段以 UTF-8 位元組 `/` 切分（見 ``components(of:)``）。
	internal static func lexicallyNormalized(_ path: String) -> String {
		var kept: [String] = []
		for component in components(of: path) {
			switch component {
			case ".":
				continue
			case "..":
				_ = kept.popLast()
			default:
				kept.append(component)
			}
		}
		return "/" + kept.joined(separator: "/")
	}

	/// `path` 是否等於 `ancestor` 或位於其下，以路徑段為單位比對。
	///
	/// `/a/Documents2` 不在 `/a/Documents` 之下；`/` 是所有絕對路徑的祖先。兩側都先做
	/// Unicode NFC 正規化，`caseInsensitive` 為 `true` 時再轉小寫。
	///
	/// - Parameters:
	///   - path: 待判斷的路徑（已字面正規化）。
	///   - ancestor: 前綴路徑（已字面正規化）。
	///   - caseInsensitive: 是否不分大小寫。
	internal static func isWithin(_ path: String, ancestor: String, caseInsensitive: Bool) -> Bool {
		let pathComponents: [String] = components(of: comparable(path, caseInsensitive: caseInsensitive))
		let ancestorComponents: [String] = components(of: comparable(ancestor, caseInsensitive: caseInsensitive))
		guard ancestorComponents.count <= pathComponents.count else { return false }
		return zip(ancestorComponents, pathComponents).allSatisfy { sameBytes($0, $1) }
	}

	/// 兩字串的 UTF-8 位元組是否完全相同。
	///
	/// 刻意不用 `==`：Swift `String` 的比較以 canonical equivalence 與字素叢集為單位，
	/// 比對規則必須和檔案系統看到的位元組一致，正規化由 ``comparable(_:caseInsensitive:)`` 明確做。
	internal static func sameBytes(_ lhs: String, _ rhs: String) -> Bool {
		lhs.utf8.elementsEqual(rhs.utf8)
	}

	/// 比對用的字串形：Unicode NFC，`caseInsensitive` 時再轉小寫。
	internal static func comparable(_ string: String, caseInsensitive: Bool) -> String {
		let normalized: String = string.precomposedStringWithCanonicalMapping
		return caseInsensitive ? normalized.lowercased() : normalized
	}

	/// 路徑段（不含空段），以 UTF-8 位元組 `/` 切分。
	///
	/// 不用 `String.split(separator: "/")`：它以字素叢集切分，`/` 後面接組合字元
	/// （例如 U+0301）時兩者合成一個字元、不被當成分隔符，而檔案系統照樣把該位元組當分隔符。
	internal static func components(of path: String) -> [String] {
		path.utf8.split(separator: UInt8(ascii: "/")).map { String(Substring($0)) }
	}

	/// 以 `realpath(3)` 解析真實路徑；路徑不存在或解析失敗回 nil。
	internal static func resolved(_ path: String) -> String? {
		guard let pointer: UnsafeMutablePointer<CChar> = realpath(path, nil) else { return nil }
		defer { free(pointer) }
		return String(validatingCString: pointer)
	}

	/// 以開啟後 `F_GETPATH` 的方式解析真實路徑。
	///
	/// 與 `realpath(3)` 對 firmlink 的處理不同（例如 `/System/Volumes/Data/...` 形，`realpath` 原樣回傳、
	/// `F_GETPATH` 回 `/Users/...` 形）；請求端的真實路徑取自 `F_GETPATH`，政策端也要有這一形才比得上。
	///
	/// 路徑本身開不了（不存在、或目錄只有搜尋權沒有讀權）時，逐層往上找開得了的祖先，取它的
	/// `F_GETPATH` 再接回其餘路徑段——拒絕前綴不能因為開不了就少一形。連 `/` 都開不了時回 nil。
	internal static func descriptorResolved(_ path: String) -> String? {
		var head: [String] = components(of: path)
		var tail: [String] = []
		while true {
			let descriptor: Int32 = open("/" + head.joined(separator: "/"), O_RDONLY | O_CLOEXEC | O_NONBLOCK)
			if descriptor >= 0 {
				let base: String? = self.path(ofDescriptor: descriptor)
				close(descriptor)
				guard let base else { return nil }
				return lexicallyNormalized(([base] + tail.reversed()).joined(separator: "/"))
			}
			guard let last: String = head.popLast() else { return nil }
			tail.append(last)
		}
	}

	/// 取 fd 的真實路徑（`F_GETPATH`）；失敗回 nil。
	internal static func path(ofDescriptor descriptor: Int32) -> String? {
		var buffer: [CChar] = .init(repeating: 0, count: Int(MAXPATHLEN))
		return buffer.withUnsafeMutableBufferPointer { pointer -> String? in
			guard let base: UnsafeMutablePointer<CChar> = pointer.baseAddress else { return nil }
			guard fcntl(descriptor, F_GETPATH, base) != -1 else { return nil }
			return String(validatingCString: base)
		}
	}

	/// 一條已正規化路徑的各種形：字面形、`realpath(3)` 形、`F_GETPATH` 形（存在且不同者才加入）。
	internal static func forms(of path: String) -> [String] {
		var result: [String] = [path]
		for candidate in [resolved(path), descriptorResolved(path)] {
			guard
				let candidate,
				!result.contains(where: { sameBytes($0, candidate) })
			else { continue }
			result.append(candidate)
		}
		return result
	}
}
