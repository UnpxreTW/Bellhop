//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - WindowLayout

/// 具名視窗排列快照（schema v1），存於 `~/Library/Application Support/Bellhop/layouts/<name>.json`。
///
/// 快照走 CGWindowList、可跨 Space 記錄；還原走 AX、只碰得到當前 Space——
/// 這個結構性不對稱是 API 限制，schema 兩側都要能表達。視窗記錄**不以
/// windowNumber 當比對 key**（重開機／重啟 app 後不穩定，僅留作 debug 附註），
/// 還原比對靠 bundle id＋標題。
struct WindowLayout: Codable, Equatable {

	/// 快照當下的一個螢幕（display 指紋：以 frame 識別排列組態）。
	struct Display: Codable, Equatable {

		/// 螢幕在 CG 全域座標系的 frame。
		let frame: WindowFrame
	}

	/// schema 版本；現行為 1。
	let version: Int

	/// 快照時間。
	let savedAt: Date

	/// 快照當下的螢幕排列（display 指紋）。
	let displays: [Display]

	/// 快照當下的視窗（可含其他 Space 與最小化的）。
	let windows: [WindowRecord]

	private enum CodingKeys: String, CodingKey {

		case version
		case savedAt = "saved_at"
		case displays
		case windows
	}
}

// MARK: - + 存取與驗證

extension WindowLayout {

	/// layout 檔存放目錄：`~/Library/Application Support/Bellhop/layouts/`。
	///
	/// 這是 Bellhop 的第一個 state 目錄；呼叫端寫入前自行確保目錄存在。
	static func layoutsDirectory() throws -> URL {
		let base: URL = try FileManager.default.url(
			for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
		)
		return base.appendingPathComponent("Bellhop").appendingPathComponent("layouts")
	}

	/// 驗證並整理 layout 名稱；不合法回 nil。
	///
	/// 名稱會成為檔名的一部分，拒收路徑分隔符、冒號、控制字元、`.` 開頭
	/// （涵蓋 `..` 上跳與隱藏檔）與超過 64 字的輸入。
	static func sanitizedName(_ raw: String) -> String? {
		let name: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !name.isEmpty, name.count <= 64 else { return nil }
		guard !name.contains("/"), !name.contains(":"), !name.hasPrefix(".") else { return nil }
		guard name.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
		return name
	}

	/// 兩組螢幕指紋是否等價（忽略列舉順序）。
	static func displaysMatch(_ lhs: [Display], _ rhs: [Display]) -> Bool {
		let sortKey: (Display, Display) -> Bool = {
			($0.frame.originX, $0.frame.originY, $0.frame.width, $0.frame.height)
				< ($1.frame.originX, $1.frame.originY, $1.frame.width, $1.frame.height)
		}
		return lhs.sorted(by: sortKey) == rhs.sorted(by: sortKey)
	}

	/// 視窗 frame 主要落在哪個螢幕（交集面積最大者的索引）；皆無交集回 nil。
	static func displayIndex(for frame: WindowFrame, in displays: [WindowFrame]) -> Int? {
		var best: (index: Int, area: Int)?
		for (index, display) in displays.enumerated() {
			let area: Int = frame.intersectionArea(with: display)
			if area > 0, area > (best?.area ?? 0) { best = (index, area) }
		}
		return best?.index
	}

	/// layout 專用 JSON encoder（ISO 8601 時間、鍵排序、pretty print——diff 友善）。
	static func encoder() -> JSONEncoder {
		let encoder: JSONEncoder = .init()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		return encoder
	}

	/// layout 專用 JSON decoder（對應 ``encoder()``）。
	static func decoder() -> JSONDecoder {
		let decoder: JSONDecoder = .init()
		decoder.dateDecodingStrategy = .iso8601
		return decoder
	}
}
