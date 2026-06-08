# Security Policy

## Reporting a vulnerability

請將安全問題以 email 回報至 **mail@unpxre.me**，**不要**開公開 issue。我會盡快回覆並協調修補與揭露時程。

## Security model

Bellhop 以**啟動它的使用者權限**運行。它透過 `osascript` 對 Terminal.app 發 Apple Event，並提供可執行任意 shell 命令的工具（`open_terminal`、`run_in_front_terminal`）。這在設計上等同**任意程式執行**——這正是「終端機控制」功能本身，不是缺陷。

因此使用上請注意：

- **只把 Bellhop 註冊給你信任的 MCP client。** 一個會讀取不受信任內容（例如 connected folder 內的檔案、網頁、郵件）的 agent，可能被注入的指示誘導去呼叫這些工具。
- Bellhop **不**暴露 `run_shell()` 這類泛用接口，只提供具名工具；但具名工具仍能執行命令。
- 若未來要把 Bellhop 給較不受信任的呼叫端使用，應先加上 cwd 白名單與命令 gating。

## Supported versions

專案處於 pre-1.0，僅最新發佈版本接受安全修補。
