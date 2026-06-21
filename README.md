# Bellhop

> A Swift MCP server for operating macOS — purpose-built, typed tools.

Bellhop 是用 Swift 寫的 [MCP](https://modelcontextprotocol.io)（Model Context Protocol）server，讓 Claude Code、Claude Desktop 等 MCP client 透過**具名、強型別的工具**操作 macOS。

跟生態裡多數 macOS MCP server 不同，Bellhop **不是** computer-use（截圖 + 點擊），也不是「丟一段 AppleScript 我幫你跑」的通用 runner——它提供一組**目的明確、參數有型別**的工具。

## 核心用途

Bellhop 最初是為了一個情境而生：**人在手機上，透過 Claude app 的 dispatch 讓 Mac 開一個新的 Terminal session、跑起 `claude` 並預設啟用 Remote Control，然後直接在手機上接手那個 session。** dispatch 出來的 agent 只要呼叫 `terminal_open`，就能在 Mac 上開出帶 Remote Control 的 claude 視窗——這是 computer-use（截圖點擊）或沙盒內的 shell 做不到的（它們碰不到 host 的 Terminal）。

它也能當一般的 Terminal 控制 MCP 給任何 MCP client 用。

## 為什麼

- **具名工具，不是通用 runner**：每個工具都有 JSON Schema 定義的參數，client 一 handshake 就知道能做什麼、怎麼呼叫。
- **走 Apple Event，不靠 GUI**：透過 `osascript` 對 Terminal.app 發 Apple Event，不走截圖點擊——`do script` 在螢幕鎖定下照樣可達。
- **單一編譯 binary**：純 Swift Package、零 Python / Node runtime，MCP client 直接 spawn。

## 工具

| 工具 | 作用 | 參數 |
|---|---|---|
| `terminal_open` | 開新 Terminal 視窗，可選 cd 進目錄再跑命令，回傳新分頁識別碼 | `command`、`cwd`（皆可選；空＝乾淨 shell） |
| `terminal_run` | 在指定 `window_id` 的視窗跑命令；視窗忙碌（有前景程式在跑）就拒跑、不注入 | `command`、`window_id`（皆必填） |
| `terminal_list_windows` | 列出開啟中的視窗 id、標題與 `busy` 狀態 | 無 |

`terminal_run` 是「把命令打進該視窗當前在跑的程式」，所以只在視窗閒置於 shell 提示字元（`busy=false`）時乾淨執行——跑著程式的視窗（含其他編輯器 / session）會被自動拒跑、不被誤注入。先用 `terminal_list_windows` 挑 `busy=false` 的目標。

## 安裝與使用

到 [Releases](https://github.com/UnpxreTW/Bellhop/releases) 下載編譯好的 `Bellhop` 執行檔。下載後驗證 checksum（每個 release 附 `SHA256SUMS`）：

```sh
shasum -a 256 -c SHA256SUMS
```

下載的執行檔帶 quarantine，Gatekeeper 會擋，先移除：

```sh
xattr -dr com.apple.quarantine /path/to/Bellhop
```

把 Bellhop 註冊進 MCP client。依用途，可能要寫進一或兩個地方（格式相同，`command` 給執行檔的絕對路徑）：

- **本機 Claude Code session** → `~/.claude.json` 頂層 `mcpServers`
- **Claude app / 手機 dispatch（核心用途）** → `~/Library/Application Support/Claude/claude_desktop_config.json` 的 `mcpServers`

```json
"mcpServers": {
  "bellhop": { "command": "/path/to/Bellhop" }
}
```

Claude Code 用 `claude mcp list` 應顯示 `bellhop ✔ Connected`；改完 `claude_desktop_config.json` 要**重啟 Claude Desktop** 才生效。

## 首次使用權限

第一次呼叫工具時要過授權，之後不再問：

- **Mac**：跳出「Terminal.app 想要被控制」的 Automation 授權 → 同意。
- **手機端**：dispatch 的 session 第一次用這個工具會請你核准權限 → 同意。

> 執行需求：macOS 14+。

## 設定 Remote Control 預設開啟

核心用途要手機接管 dispatch 開出的 session，得讓那個 `claude` 一**啟動就帶 Remote Control**。在 `~/.claude/settings.json` 設：

```json
{
  "remoteControlAtStartup": true
}
```

（或在 Claude Code 內 `/config` → 開「Enable Remote Control for all sessions」；也可改成每次啟動加 flag：`claude --remote-control`。）

設好後，從手機 dispatch「用 `terminal_open` 開新視窗執行 `claude`」，新 session 就帶 Remote Control，在 Claude app 的 session 列表即可接管。

**前提**：用 claude.ai 帳號 `/login`（Remote Control 不支援 API key）、方案 Pro / Max 以上、Claude Code 版本需支援 `remoteControlAtStartup`。

## 開發

從原始碼建置：

```sh
swift build -c release
# 產物：.build/release/Bellhop
```

- **工具鏈**：Swift 6.2 / Xcode 26。**Xcode 26 需 macOS 15.6+**——故建置在 macOS 15.6+ 環境，產物部署目標則下探到 macOS 14。
- **Lint / format**：[SwiftStyleKit](https://github.com/UnpxreTW/SwiftStyleKit)（SwiftLint + SwiftFormat 打包）；`SWIFTSTYLELINT_STRICT=1` 把 warning 升 error。
- **測試 / CI**：`swift build` / `swift test`；GitHub Actions 跑 build 與 REUSE 授權合規檢查。
