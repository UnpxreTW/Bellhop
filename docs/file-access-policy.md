# 檔案存取政策

`BellhopKit` 內含一組唯讀檔案工具（`file_stat`、`file_list`、`file_read`）與其存取政策檢查。這三個工具**尚未註冊**進 MCP server，client 看不到也呼叫不到；本文件說明政策檔格式與判定規則。完整說明見原始碼 DocC（`FileAccessPolicy`、`FileAccessChecker`、`FileAccessCredentialStores`、`FileTools`）。

## 政策檔

預設位置 `~/Library/Application Support/Bellhop/file-access-policy.json`。檔不存在＝全拒；讀不到、JSON 不合法、出現未知的鍵、或路徑欄不合法＝全拒（原因碼 `policyUnavailable`）。每次工具呼叫都重新讀取。

```json
{
  "enabled": true,
  "roots": [
    { "path": "~/Documents/Notes", "listable": true },
    { "path": "/Volumes/Shared/Reports", "listable": false }
  ],
  "denies": ["~/Documents/Notes/private"]
}
```

| 欄位 | 必填 | 說明 |
|---|---|---|
| `enabled` | 是 | `false`＝全拒 |
| `roots[].path` | 是 | 可服務的資料夾；絕對路徑或以 `~` 開頭 |
| `roots[].listable` | 否（預設 `false`） | `false`＝只能對已知路徑查屬性與讀取，不能列目錄 |
| `denies` | 否（預設空） | 自訂的拒絕前綴；絕對路徑或以 `~` 開頭 |

root 不存在、或為 `/`、家目錄本身、家目錄的祖先目錄時，該 root 無效（略過、不報錯）。

## 內建硬拒清單

政策檔蓋不掉；比對不分大小寫、先做 Unicode NFC 正規化。

- 任一路徑段為 `.ssh`、`.gnupg`、`.aws`、`.azure`、`.kube`
- 家目錄下的 `.docker/config.json`、`.config/gh`、`.config/gcloud`、`.netrc`、`.npmrc`、`.pypirc`、`.git-credentials`、`.claude.json`、`Library/Keychains`、`Library/Application Support/com.apple.TCC`、`Library/Application Support/Bellhop`（含其下所有內容）
- 檔名符合 `.env`、`.env.*`、`*.pem`、`*.p12`、`*.pfx`、`*.p8`、`*.key`、`*.keychain`、`*.keychain-db`、`*.mobileprovision`、`id_rsa*`、`id_dsa*`、`id_ecdsa*`、`id_ed25519*`

## 判定流程

1. 政策不合法 → `policyUnavailable`；`enabled` 為 `false` → `disabled`。
2. 輸入檢查：空字串、含 NUL、相對路徑 → `invalidPath`。
3. 字面階段（不碰檔案系統）：消去 `.`、`..`、重複斜線 → 內建硬拒（`credentialStore`）→ `denies`（`userDenied`）→ 必須落在有效 root 之下（`outsideRoots`）。前綴以路徑段為單位比對。
4. 開啟階段：以 `O_RDONLY | O_CLOEXEC | O_NONBLOCK` 開啟，用 `F_GETPATH` 取 fd 的真實路徑，對真實路徑重做步驟 3 的三項檢查，再以 `fstat` 判型別（`unsupportedFileType`）。之後只對這個 fd 讀取。
5. 工具層：列目錄要求 root 可列（`notListable`）；讀取上限 10 MiB（`tooLarge`）、內容須為 UTF-8（`notText`）；系統呼叫失敗 → `ioError`。

## 稽核紀錄

每次呼叫寫一行 JSON 到 `~/Library/Application Support/Bellhop/file-access-audit.jsonl`（目錄 0700、檔案 0600、附加寫入），欄位為 `time`、`tool`、`requested_path`、`real_path`（取得了才有）、`result`、`reason`。不記檔案內容與列出的檔名。紀錄寫不進去時，該次呼叫改判拒絕（`ioError`）。
