# Bellhop

> A Swift MCP server for operating macOS — purpose-built, typed tools.

Bellhop 是用 Swift 寫的 [MCP](https://modelcontextprotocol.io)（Model Context Protocol）server，讓 Claude Code、Claude Desktop 等 MCP client 透過**具名、強型別的工具**操作 macOS。

跟生態裡多數 macOS MCP server 不同，Bellhop **不是** computer-use（截圖 + 點擊），也不是「丟一段 AppleScript 我幫你跑」的通用 runner——它提供一組**目的明確、參數有型別**的工具。

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

從原始碼建置（工具鏈需求見〈開發〉）：

```sh
swift build -c release
```

把產出的 binary 註冊進 MCP client。以 Claude Code 為例，寫進 `~/.claude.json` 頂層 `mcpServers`（與其他 server 同層）：

```json
"bellhop": {
  "type": "stdio",
  "command": "/絕對路徑/Bellhop/.build/release/Bellhop"
}
```

`claude mcp list` 應顯示 `bellhop ✔ Connected`。首次呼叫工具時，macOS 會要求授權 Terminal.app 的 Automation 權限。

> 編譯產物部署目標為 macOS 14+；亦即 binary 可在 macOS 14 以上執行（注意「建置」的系統需求較高，見下）。

## 開發

- **工具鏈**：Swift 6.2 / Xcode 26。**Xcode 26 需 macOS 15.6+**——故建置在 macOS 15.6+ 環境，產物的部署目標則下探到 macOS 14。
- **Lint / format**：[SwiftStyleKit](https://github.com/UnpxreTW/SwiftStyleKit)（SwiftLint + SwiftFormat 打包）；`SWIFTSTYLELINT_STRICT=1` 把 warning 升 error。
- **測試 / CI**：`swift build` / `swift test`；GitHub Actions 跑 build 與 REUSE 授權合規檢查。
