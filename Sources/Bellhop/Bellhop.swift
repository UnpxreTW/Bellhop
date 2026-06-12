//
//  Bellhop
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the MIT License. See LICENSE for details.
//
//  SPDX-License-Identifier: MIT

import BellhopKit

@main
struct Bellhop {

	static func main() async throws {
		try await BellhopServer.run()
	}
}
