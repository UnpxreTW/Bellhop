//
//  BellhopKitTests
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Testing

@testable import BellhopKit

struct SubprocessTests {

	@Test("收齊 stdout 與 stderr 並回 exit status")
	func capturesOutputsAndStatus() async throws {
		let output = try await Subprocess.run(
			"/bin/sh", arguments: ["-c", "printf out; printf err 1>&2; exit 3"]
		)
		#expect(output.status == 3)
		#expect(output.standardOutput == "out")
		#expect(output.standardError == "err")
	}

	@Test("兩條 pipe 同時超過 64KB buffer 上限不 deadlock")
	func drainsBothPipesBeyondBufferLimit() async throws {
		let output = try await Subprocess.run(
			"/bin/sh",
			arguments: ["-c", "head -c 200000 /dev/zero | tr '\\0' x; head -c 200000 /dev/zero | tr '\\0' y 1>&2"]
		)
		#expect(output.status == 0)
		#expect(output.standardOutput.count == 200_000)
		#expect(output.standardError.count == 200_000)
	}

	@Test("逾時終止子程序並丟錯")
	func terminatesOnTimeout() async {
		let clock: ContinuousClock = .init()
		let elapsed = await clock.measure {
			await #expect(throws: SubprocessError.self) {
				_ = try await Subprocess.run("/bin/sleep", arguments: ["10"], timeout: 0.3)
			}
		}
		#expect(elapsed < .seconds(5))
	}
}
