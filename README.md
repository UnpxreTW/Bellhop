# Bellhop

> A Swift MCP server for operating macOS — purpose-built, typed tools.

Bellhop 是用 Swift 寫的 [MCP](https://modelcontextprotocol.io)（Model Context Protocol）server，讓 Claude Code、Claude Desktop 等 MCP client 透過**具名、強型別的工具**操作 macOS。

跟生態裡多數 macOS MCP server 不同，Bellhop **不是** computer-use（截圖 + 點擊），也不是「丟一段 AppleScript 我幫你跑」的通用 runner——它提供一組**目的明確、參數有型別**的工具。

## 為什麼

- **具名工具，不是通用 runner**：每個工具都有 JSON Schema 定義的參數，client 一 handshake 就知道能做什麼、怎麼呼叫。
- **走 Apple Event，不靠 GUI**：透過 `osascript` 對 Terminal.app 發 Apple Event，不走截圖點擊。
- **單一編譯 binary**：純 Swift Package、零 Python / Node runtime，MCP client 直接 spawn。

## 需求

- macOS 26+
- Swift 6.0+（Xcode 26+）
