# 測試插件 `fmp-test-http`

契約執行器（`test/plugins/contract/`）的第二個測試插件：會發 HTTP 請求，讓重播、
網域與遮蔽的檢查真的被執行到。網域是 RFC 2606 保留的 `.test`，回應全部由
`fixtures/` 重播，不會真的連網；也不打包進 App。

- `http_test_plugin.js`：安裝檔，能力 `search`、`resolveStream`。請求帶一個假的
  `access_key`，fixture 與 log 裡只能看到 `***`；manifest 追加遮蔽鍵名
  `demo_session`。
- `checks.json`：`search` 期望成功；`resolveStream` 期望 `Unavailable`
  （`copyright`），示範錯誤案例。
- `fixtures/`：手寫，每個檔的 `meta.edited` 寫明理由，錄製模式不會覆蓋。
