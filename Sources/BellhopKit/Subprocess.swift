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
	/// 呼叫端 Task 被 cancel 時會對子程序送 `terminate()`，不會放著跑到自然結束或逾時；
	/// 送出後只再等一個 ``killGracePeriod``，不理 SIGTERM 的子程序會就地升級 SIGKILL，
	/// 而不是繼續佔著原本的逾時窗。
	///
	/// - Parameters:
	///   - executablePath: 執行檔絕對路徑。
	///   - arguments: 傳給執行檔的參數。
	///   - timeout: 逾時秒數，超過即送 SIGTERM（寬限後 SIGKILL）並丟 ``SubprocessError/timedOut(_:after:)``。
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
			return String(data: storage, encoding: .utf8) ?? ""
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

		/// 子程序退出、或呼叫端取消時被喚醒。
		///
		/// `runSync` 的主等待窗等的是這個、而不是只等子程序退出：只等退出的話，取消訊號送出後
		/// 若子程序不理 SIGTERM，這裡要等滿整個 `timeout` 才會發現、才會升級 SIGKILL。
		let wakeup: DispatchSemaphore = .init(value: 0)

		/// 是否已收到取消。`runSync` 被喚醒後靠它分辨「子程序自己結束了」與「呼叫端取消了」。
		var isCancelled: Bool {
			lock.lock()
			defer { lock.unlock() }
			return cancelled
		}

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
			let alreadyCancelled: Bool = cancelled
			cancelled = true
			let existing: Process? = process
			lock.unlock()
			existing?.terminate()
			// 一次取消喚醒一次就夠；`onCancel` 雖然只會觸發一次，但這裡不假設呼叫次數。
			if !alreadyCancelled {
				wakeup.signal()
			}
		}
	}

	/// SIGTERM 後等待子程序退出的寬限秒數，逾期升級 SIGKILL。
	private static let killGracePeriod: TimeInterval = 2

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
		process.terminationHandler = { _ in
			terminated.signal()
			processBox.wakeup.signal()
		}

		try process.run()
		processBox.register(process)

		var timedOut: Bool = false
		var abandoned: Bool = false
		var abandonedAfter: TimeInterval = 0
		if processBox.wakeup.wait(timeout: .now() + timeout) == .timedOut {
			// 等滿逾時窗仍無動靜：SIGTERM 由這裡送出，再接收尾升級。
			timedOut = true
			process.terminate()
			abandoned = awaitExitAfterTermination(process, terminated: terminated)
			abandonedAfter = timeout + killGracePeriod * 2
		} else if processBox.isCancelled {
			// 被取消喚醒：SIGTERM 已由 `ProcessBox` 送出（先 cancel 後 spawn 的順序由 register()
			// 補送），這裡直接接收尾升級——不再等滿原本的逾時窗。子程序不理 SIGTERM 時，
			// 這就是「等一個寬限期」與「等滿 timeout」的差別。
			abandoned = awaitExitAfterTermination(process, terminated: terminated)
			abandonedAfter = killGracePeriod * 2
		}
		let drainResult: DispatchTimeoutResult = drains.wait(timeout: .now() + killGracePeriod)
		stdout.fileHandleForReading.readabilityHandler = nil
		stderr.fileHandleForReading.readabilityHandler = nil

		if abandoned {
			throw SubprocessError.abandoned(executablePath, after: abandonedAfter)
		}
		if timedOut {
			throw SubprocessError.timedOut(executablePath, after: timeout)
		}
		return Output(
			status: process.terminationStatus,
			standardOutput: outBuffer.text,
			standardError: errBuffer.text,
			truncated: drainResult == .timedOut
		)
	}

	/// SIGTERM 已送出後等子程序退出：寬限期內沒退就升級 SIGKILL，再等一個寬限期仍沒退則放棄。
	///
	/// 逾時路徑與取消路徑共用同一段收尾，差別只在誰送出 SIGTERM、以及在此之前等了多久。
	///
	/// - Returns: 是否放棄等待（連 SIGKILL 都沒能讓子程序退出）。
	private static func awaitExitAfterTermination(_ process: Process, terminated: DispatchSemaphore) -> Bool {
		guard terminated.wait(timeout: .now() + killGracePeriod) == .timedOut else { return false }
		kill(process.processIdentifier, SIGKILL)
		return terminated.wait(timeout: .now() + killGracePeriod) == .timedOut
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

	case timedOut(String, after: TimeInterval)
	/// SIGKILL 送出後最終 `wait()` 仍逾時——子程序可能卡在不可中斷的核心睡眠態，
	/// Bellhop 放棄等待、不再無限阻塞。關聯值為執行檔路徑與放棄前的等待秒數
	/// （逾時路徑含逾時窗本身，取消路徑自送出 SIGTERM 起算）。
	case abandoned(String, after: TimeInterval)
}

// MARK: - + CustomStringConvertible

extension SubprocessError: CustomStringConvertible {

	var description: String {
		switch self {
		case let .timedOut(executablePath, seconds):
			"""
			\(executablePath) timed out after \(Int(seconds))s and was terminated — \
			a blocked system permission prompt on the machine can cause this; grant the \
			permission to the app that launches Bellhop, then retry.
			"""
		case let .abandoned(executablePath, seconds):
			"""
			\(executablePath) did not exit within \(Int(seconds))s even after SIGKILL — \
			it may be stuck in an uninterruptible kernel sleep, so Bellhop gave up waiting. \
			The process may still be running; check manually if this persists.
			"""
		}
	}
}
