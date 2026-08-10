//
//  BellhopKit
//
//  Copyright © 2026 Unpxre (GitHub: UnpxreTW)
//  Licensed under the Apache License 2.0. See LICENSE for details.
//
//  SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - Subprocess

/// 共用的 subprocess 執行器。
///
/// 三個健壯性保證：stdout / stderr **並行 drain**（單邊塞爆 64KB pipe buffer 不會
/// deadlock）、**逾時終止**（子程序卡住——例如系統權限對話框擋在前面——不會無限阻塞
/// 整個 server）、以及**不佔用 Swift concurrency 合作執行緒**（阻塞等待落在 GCD 執行緒）。
enum Subprocess {

	// MARK: Internal

	/// 子程序執行結果。
	struct Output {

		let status: Int32
		let standardOutput: String
		let standardError: String
		/// drain 因逾時提前收尾時為 true——此時 `standardOutput` / `standardError` 可能不完整，
		/// 即使 `status` 本身是父程序真實成功碼。
		let truncated: Bool
	}

	/// 預設逾時秒數。
	static let defaultTimeout: TimeInterval = 30

	/// 執行子程序並收齊輸出。
	///
	/// 呼叫端 Task 被 cancel 時會對子程序送 `terminate()`，不會放著跑到自然結束或逾時。
	///
	/// - Parameters:
	///   - executablePath: 執行檔絕對路徑。
	///   - arguments: 傳給執行檔的參數。
	///   - timeout: 逾時秒數，超過即送 SIGTERM（寬限後 SIGKILL）並丟
	///     ``SubprocessError/timedOut(_:after:captured:)``——該錯誤會帶上終止前已收到的輸出。
	static func run(
		_ executablePath: String,
		arguments: [String],
		timeout: TimeInterval = defaultTimeout
	) async throws -> Output {
		let processBox: ProcessBox = .init()
		return try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { continuation in
				DispatchQueue.global(qos: .userInitiated).async {
					continuation.resume(with: Result {
						try runSync(executablePath, arguments: arguments, timeout: timeout, processBox: processBox)
					})
				}
			}
		} onCancel: {
			processBox.cancel()
		}
	}

	// MARK: Private

	/// 執行緒安全的輸出累積 buffer。
	private final class DataBuffer: @unchecked Sendable {

		var text: String {
			lock.lock()
			defer { lock.unlock() }
			// !!!: 刻意走 lossy 解碼。`optional_data_string_conversion` 想擋的是「隨手把解碼失敗
			// 吞掉」，但這裡的失敗是預期中的：逾時終止會把多位元組字元從中切開，而 failable 版本
			// 只要遇到一個無效 byte 就整段回 nil——最需要看到輸出的情境反而會一個字都拿不到。
			// swiftlint:disable:next optional_data_string_conversion
			return String(decoding: storage, as: UTF8.self)
		}

		private let lock: NSLock = .init()
		private var storage: Data = .init()

		func append(_ data: Data) {
			lock.lock()
			storage.append(data)
			lock.unlock()
		}
	}

	/// 跨執行緒交握子程序控制權的容器，讓 Task cancellation 能 terminate() 一個可能還沒
	/// spawn 完成的子程序。
	///
	/// `onCancel` 可能在任意執行緒、任意時間點（含 `runSync` 尚未跑到 `process.run()` 前）
	/// 同步觸發；用鎖 + 旗標讓「先 cancel 後 process 就緒」與「先 process 就緒後 cancel」
	/// 兩種到達順序都導向同一個 `terminate()` 呼叫——`Process.terminate()` 本身可重複呼叫、
	/// 可在任意執行緒呼叫，是安全的。
	private final class ProcessBox: @unchecked Sendable {

		private let lock: NSLock = .init()
		private var process: Process?
		private var cancelled: Bool = false

		/// `runSync` 成功 `process.run()` 後登記，讓已發生的 cancel 有東西可 terminate()。
		func register(_ process: Process) {
			lock.lock()
			self.process = process
			let shouldTerminate: Bool = cancelled
			lock.unlock()
			if shouldTerminate {
				process.terminate()
			}
		}

		/// Task cancellation 觸發；process 已就緒就直接 terminate()，否則記旗標待 register() 補送。
		func cancel() {
			lock.lock()
			cancelled = true
			let existing: Process? = process
			lock.unlock()
			existing?.terminate()
		}
	}

	/// SIGTERM 後等待子程序退出的寬限秒數，逾期升級 SIGKILL。
	private static let killGracePeriod: TimeInterval = 2

	/// 等待兩條 pipe drain 收尾的上限秒數，逾期即收手並標記為不完整
	/// （成功路徑記在 ``Output/truncated``、丟錯路徑記在 ``SubprocessError/CapturedOutput/truncated``）。
	///
	/// 初值與 ``killGracePeriod`` 相同但語義不相干——前者答「還要給子程序多久乖乖退出」、
	/// 本常數答「還要等 pipe 收多久」（孫程序繼承 fd 撐住 EOF 時就靠它收手）。
	/// 分成兩個常數，是為了調其中一邊不會連帶改動另一邊。
	private static let drainGracePeriod: TimeInterval = 2

	/// 在呼叫端執行緒（GCD）上同步執行子程序；兩條 pipe 各以 readabilityHandler 並行 drain。
	private static func runSync(
		_ executablePath: String,
		arguments: [String],
		timeout: TimeInterval,
		processBox: ProcessBox
	) throws -> Output {
		let process: Process = .init()
		process.executableURL = URL(fileURLWithPath: executablePath)
		process.arguments = arguments
		process.standardInput = FileHandle.nullDevice

		let stdout: Pipe = .init()
		let stderr: Pipe = .init()
		process.standardOutput = stdout
		process.standardError = stderr

		let drains: DispatchGroup = .init()
		let outBuffer = drain(stdout, group: drains)
		let errBuffer = drain(stderr, group: drains)

		let terminated: DispatchSemaphore = .init(value: 0)
		process.terminationHandler = { _ in terminated.signal() }

		try process.run()
		processBox.register(process)

		var timedOut = false
		var abandoned: Bool = false
		if terminated.wait(timeout: .now() + timeout) == .timedOut {
			timedOut = true
			process.terminate()
			if terminated.wait(timeout: .now() + killGracePeriod) == .timedOut {
				kill(process.processIdentifier, SIGKILL)
				if terminated.wait(timeout: .now() + killGracePeriod) == .timedOut {
					abandoned = true
				}
			}
		}
		let drainResult: DispatchTimeoutResult = drains.wait(timeout: .now() + drainGracePeriod)
		stdout.fileHandleForReading.readabilityHandler = nil
		stderr.fileHandleForReading.readabilityHandler = nil

		// 各取一次快照：`.text` 每次都要整份解碼，且 drain 逾時後 handler 可能還在 append，
		// 讀兩次會讓錯誤帶的內容與 Output 帶的內容對不起來。
		let standardOutput: String = outBuffer.text
		let standardError: String = errBuffer.text
		let truncated: Bool = drainResult == .timedOut

		// !!!: 兩個 throw 都在 drain 收尾之後，buffer 裡已經有卡住前寫出的內容——那正是要交給
		// 使用者判斷「為什麼卡住」的線索，故隨錯誤帶出，不隨著丟錯誤一起扔掉。
		let captured: SubprocessError.CapturedOutput = .init(
			standardOutput: standardOutput, standardError: standardError, truncated: truncated
		)
		if abandoned {
			throw SubprocessError.abandoned(
				executablePath, after: timeout + killGracePeriod * 2, captured: captured
			)
		}
		if timedOut {
			throw SubprocessError.timedOut(executablePath, after: timeout, captured: captured)
		}
		return Output(
			status: process.terminationStatus,
			standardOutput: standardOutput,
			standardError: standardError,
			truncated: truncated
		)
	}

	/// 持續讀空 pipe 直到 EOF；回傳累積輸出的 buffer。
	private static func drain(_ pipe: Pipe, group: DispatchGroup) -> DataBuffer {
		let buffer: DataBuffer = .init()
		group.enter()
		pipe.fileHandleForReading.readabilityHandler = { handle in
			let data = handle.availableData
			if data.isEmpty {
				handle.readabilityHandler = nil
				group.leave()
			} else {
				buffer.append(data)
			}
		}
		return buffer
	}
}

// MARK: - SubprocessError

/// 子程序執行失敗。
enum SubprocessError: Error {

	/// 逾時後子程序已被終止。關聯值為執行檔路徑、逾時秒數，與終止前已收到的部分輸出。
	case timedOut(String, after: TimeInterval, captured: CapturedOutput)

	/// SIGKILL 送出後最終 `wait()` 仍逾時——子程序可能卡在不可中斷的核心睡眠態，
	/// Bellhop 放棄等待、不再無限阻塞。關聯值為執行檔路徑、放棄前的總等待秒數，
	/// 與放棄前已收到的部分輸出。
	case abandoned(String, after: TimeInterval, captured: CapturedOutput)
}

// MARK: SubprocessError.CapturedOutput

extension SubprocessError {

	/// 丟出錯誤前已 drain 到的部分輸出。
	///
	/// 與 ``Subprocess/Output`` 分開是刻意的：那個型別描述「跑完了、這是結果」，
	/// 本型別描述「沒跑完、這是當時手上有的」——沒有 exit status 可言，也不保證完整。
	struct CapturedOutput {

		/// 終止前已收到的 stdout；可能為空、可能不完整。
		let standardOutput: String

		/// 終止前已收到的 stderr；可能為空、可能不完整。
		let standardError: String

		/// drain 在收到 EOF 之前就先逾時收手——為真時，上面兩段**可能**還缺後半。
		///
		/// 只是「沒等到 EOF」、不等於真有資料沒收到：孫程序繼承 fd 撐住 pipe 時，
		/// 子程序本身可能早已把話說完。
		let truncated: Bool

		/// 附加在錯誤說明尾端的診斷段。
		///
		/// 兩邊都沒有內容時回空字串——沒東西可報時，錯誤訊息維持與加上本欄位之前逐字相同。
		var diagnosticSuffix: String {
			let out: String = Self.condensed(standardOutput)
			let error: String = Self.condensed(standardError)
			var segments: [String] = []
			if !out.isEmpty { segments.append("stdout: \(out)") }
			if !error.isEmpty { segments.append("stderr: \(error)") }
			guard !segments.isEmpty else { return "" }
			let caveat: String = truncated ? " (drain timed out, so the tail may be missing)" : ""
			return " Output captured before termination\(caveat) — \(segments.joined(separator: " / "))"
		}

		/// 診斷段每條串流保留的 Unicode 純量數上限。
		///
		/// 錯誤說明會被呼叫端原樣塞進回給 client 的文字，不設上限等於讓一個話多的子程序
		/// 把整份輸出灌進一則錯誤訊息裡。以純量而非 `String.count` 計：後者算的是 grapheme
		/// cluster，單一 cluster 可由任意多個純量組成（結合符可以無限接），拿它當上限等於沒有
		/// 上限；純量最多 4 bytes，故本上限同時是實際位元組量的上界。
		private static let maximumSegmentScalars: Int = 2000

		/// 去掉頭尾空白；超長時只留尾端——卡住前最後寫出的內容離失敗點最近。
		private static func condensed(_ text: String) -> String {
			let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
			guard trimmed.unicodeScalars.count > maximumSegmentScalars else { return trimmed }
			let tail: String.UnicodeScalarView.SubSequence = trimmed.unicodeScalars.suffix(maximumSegmentScalars)
			return "…" + String(String.UnicodeScalarView(tail))
		}
	}
}

// MARK: - + CustomStringConvertible

extension SubprocessError: CustomStringConvertible {

	var description: String {
		switch self {
		case let .timedOut(executablePath, seconds, captured):
			"""
			\(executablePath) timed out after \(Int(seconds))s and was terminated — \
			a blocked system permission prompt on the machine can cause this; grant the \
			permission to the app that launches Bellhop, then retry.\(captured.diagnosticSuffix)
			"""
		case let .abandoned(executablePath, seconds, captured):
			"""
			\(executablePath) did not exit within \(Int(seconds))s even after SIGKILL — \
			it may be stuck in an uninterruptible kernel sleep, so Bellhop gave up waiting. \
			The process may still be running; check manually if this persists.\
			\(captured.diagnosticSuffix)
			"""
		}
	}
}
