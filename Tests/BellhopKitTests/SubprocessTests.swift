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

	@Test("逾時錯誤帶出終止前已收到的輸出，而非連同診斷線索一起丟棄")
	func timeoutErrorCarriesOutputCapturedBeforeTermination() async throws {
		do {
			_ = try await Subprocess.run(
				"/bin/sh",
				arguments: ["-c", "printf whyitstuck; printf permissiondenied 1>&2; sleep 10"],
				timeout: 0.3
			)
			Issue.record("預期逾時丟錯，實際卻正常返回")
		} catch let error as SubprocessError {
			guard case let .timedOut(_, _, captured) = error else {
				Issue.record("預期 timedOut，實得 \(error)")
				return
			}
			#expect(captured.standardOutput == "whyitstuck")
			#expect(captured.standardError == "permissiondenied")
			// 錯誤字面值才是真正送到呼叫端的東西：關聯值帶到但沒印出去，等於仍然丟失。
			#expect("\(error)".contains("stdout: whyitstuck"))
			#expect("\(error)".contains("stderr: permissiondenied"))
		}
	}

	@Test("多位元組字元被腰斬也只壞那一個字，不是整段輸出一起消失")
	func capturedOutputSurvivesTruncatedMultibyteCharacter() async throws {
		do {
			// 前六個 byte 是「中文」，尾巴的 \346 是三位元組序列的開頭、後面被切掉——
			// 正是逾時終止會造成的形狀。用八進位是因為 /bin/sh 的 printf 不吃 \u 跳脫。
			_ = try await Subprocess.run(
				"/bin/sh",
				arguments: ["-c", "printf '\\344\\270\\255\\346\\226\\207'; printf '\\346'; sleep 10"],
				timeout: 0.3
			)
			Issue.record("預期逾時丟錯，實際卻正常返回")
		} catch let error as SubprocessError {
			guard case let .timedOut(_, _, captured) = error else {
				Issue.record("預期 timedOut，實得 \(error)")
				return
			}
			#expect(captured.standardOutput.hasPrefix("中文"))
			#expect("\(error)".contains("中文"))
		}
	}

	@Test("話多的子程序不會把整份輸出灌進錯誤訊息，診斷段有長度上限")
	func diagnosticSuffixIsLengthBounded() async throws {
		do {
			_ = try await Subprocess.run(
				"/bin/sh",
				arguments: ["-c", "head -c 200000 /dev/zero | tr '\\0' x; sleep 10"],
				timeout: 0.5
			)
			Issue.record("預期逾時丟錯，實際卻正常返回")
		} catch let error as SubprocessError {
			guard case let .timedOut(_, _, captured) = error else {
				Issue.record("預期 timedOut，實得 \(error)")
				return
			}
			// 關聯值保留全文（呼叫端要幾行自己決定），只有進錯誤訊息那份被裁短。
			// 這裡取下界而非等於 200_000：機器忙時 0.5 秒內未必寫完 200KB，斷言全等會變成
			// 在測機器速度。「保留全文」本身另由無逾時的 capturesOutputsAndStatus 覆蓋。
			#expect(captured.standardOutput.count > 2000)
			// 貼著實際界斷言：只寫「小於某個寬鬆值」的話，上限被調鬆時測試照樣綠。
			let keptCharacterCount: Int = captured.diagnosticSuffix.filter { $0 == "x" }.count
			#expect(keptCharacterCount == 2000)
			#expect(captured.diagnosticSuffix.contains("…"))
		}
	}

	@Test("無輸出可報時，逾時訊息與加上診斷段之前逐字相同")
	func timeoutMessageUnchangedWhenNothingWasCaptured() async throws {
		do {
			_ = try await Subprocess.run("/bin/sleep", arguments: ["10"], timeout: 0.3)
			Issue.record("預期逾時丟錯，實際卻正常返回")
		} catch let error as SubprocessError {
			#expect("\(error)".hasSuffix("then retry."))
			#expect(!"\(error)".contains("Output captured before termination"))
		}
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
