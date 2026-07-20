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

	@Test("Task 被 cancel 會提前終止子程序，而非等到自然結束或逾時")
	func terminatesOnTaskCancellation() async throws {
		let task: Task<Subprocess.Output, Error> = Task {
			try await Subprocess.run("/bin/sleep", arguments: ["10"], timeout: 30)
		}
		try await Task.sleep(for: .milliseconds(100))
		let clock: ContinuousClock = .init()
		let elapsed = await clock.measure {
			task.cancel()
			_ = await task.result
		}
		#expect(elapsed < .seconds(3))
	}

	@Test("孫程序繼承 pipe 撐住 EOF 時，drain 逾時標記 truncated 而非無限等待")
	func marksTruncatedWhenGrandchildHoldsPipeOpen() async throws {
		let output = try await Subprocess.run(
			"/bin/sh", arguments: ["-c", "( sleep 10 & ) ; exit 0"]
		)
		#expect(output.status == 0)
		#expect(output.truncated)
	}

	@Test("N 個並發呼叫互不干擾，各自收齊自己的輸出與 exit status")
	func handlesConcurrentInvocationsIndependently() async throws {
		let count = 20
		try await withThrowingTaskGroup(of: (Int, Subprocess.Output).self) { group in
			for index in 0..<count {
				group.addTask {
					let output = try await Subprocess.run(
						"/bin/sh", arguments: ["-c", "printf 'out\(index)'; exit \(index % 5)"]
					)
					return (index, output)
				}
			}
			var seen: Set<Int> = []
			for try await (index, output) in group {
				#expect(output.standardOutput == "out\(index)")
				#expect(output.status == Int32(index % 5))
				seen.insert(index)
			}
			#expect(seen.count == count)
		}
	}
}
