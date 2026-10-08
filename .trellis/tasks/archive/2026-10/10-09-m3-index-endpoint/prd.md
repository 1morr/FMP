# 官方 index 網址與 manifest 的 `description`（M3 PR 3 的 FMP 部分）

> 父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`。design §7.1（官方網址放 `lib/core/endpoints.dart`）；`fmp-plugins` 那一半（CI、`index.json`、B 站修正）是 1morr/fmp-plugins 的 PR，本 PR 合併後它的 `FMP_REF` 指到這裡。

## 目標

宿主知道官方插件 index 在哪；插件能在 manifest 寫一句描述，index 從那裡帶過去，插件頁（PR 5）顯示得出來。

## 做什麼

1. `lib/core/endpoints.dart` 建檔，放官方 index 網址 `https://raw.githubusercontent.com/1morr/fmp-plugins/main/index.json`（`fmp_url_literal` 的允許檔第一次有內容）。
2. manifest 加選填的 `description?: string | null`（宿主 API v1 還沒凍結，design §4.1；慣例：Obsidian 的 `manifest.json` 有 `description`，社群清單從那裡帶）：`fmp-plugin.d.ts`、`manifestShapes`、`PluginManifest`，`type_definitions_test.dart` 同步；有上限（例如 200 字元，超過拒收）。
3. design §7.1 加一行更正：index 的 `description` 取自 manifest 的 `description`（空＝空字串）。
4. 文件：`app/AGENTS.md` 與 plugins spec 有列 manifest 欄位的地方。

## 驗收

- [ ] 測試：manifest 帶與不帶 `description` 都能解析、超過上限拒收、型別不對拒收；`type_definitions_test.dart`；`fmp_url_literal` 對 `endpoints.dart` 不報、對別處報（既有測試若已涵蓋就不重複）。
- [ ] 驗證清單全綠。實機：沒有使用者看得到的改動，不做。
