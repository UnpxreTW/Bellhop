//
//  Bellhop
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the MIT License. See LICENSE for details.
//
//  SPDX-License-Identifier: MIT

import BellhopKit

/// 薄入口：只負責啟動，邏輯全在 `BellhopKit` 以保持可單元測試。
@main
struct Bellhop {

	/// 啟動 stdio server 並等待連線結束。
	static func main() async throws {
		try await BellhopServer.run()
	}
}
