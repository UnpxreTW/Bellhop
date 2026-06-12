//
//  BellhopKitTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the MIT License. See LICENSE for details.
//
//  SPDX-License-Identifier: MIT

@testable import BellhopKit
import Testing

private struct BellhopServerTests {

	@Test
	private func `server identity`() {
		#expect(BellhopServer.name == "bellhop")
		#expect(BellhopServer.version == "0.1.0")
	}

	@Test
	private func `make server assembles`() async {
		_ = await BellhopServer.makeServer()
	}
}
