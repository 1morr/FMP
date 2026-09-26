# 階段一：現況審計（唯讀）

## 目標

讓使用者重新掌握 FMP 現況：產出 `docs/audit/` 下 12 份審計文件，作為階段二目標設計的事實基礎。
完整需求見 parent task `09-26-fmp-rewrite/prd.md` §「階段一」與 §「信任規則」，本檔不重述。

## 範圍與約束

- 只新增 `docs/audit/` 與 `.trellis/tasks/` 下的檔案；分支 `docs/audit`。
- 全部繁體中文，圖用 Mermaid；每份檔案開頭註明「現況描述，未經確認，不代表目標」。
- 證據優先序：實際執行的 App 行為 > 程式碼 > 測試 > 文檔／註釋；每個結論附 `檔案:行號`、log 或截圖。
- repo 內既有文檔、ADR、CONTEXT.md、spec、static-rule 測試都只是線索，需用代碼驗證；
  不一致兩邊都列並標「不一致」；推測標「推測」；查不到寫查不到。
- 套件平台支援以 pub.dev／官方文檔為準。
- 跑測試一律 `--exclude-tags live`，不為審計打真實 API。

## 交付物

`docs/audit/` 下：`features.md`、`architecture.md`、`playback.md`、`sources.md`、`errors.md`、
`data.md`、`downloads.md`（補充）、`accounts-network.md`、`platforms.md`、`ui.md`、`devtools.md`、`engineering.md`、
`questions.md`，另加 `README.md` 作為索引與一頁摘要。

## 補充需求（2026-09-26）

見 parent PRD 階段一 6a、7、12 的「補充」段：
- 新增 `downloads.md`（下載序列圖、音質／檔名／metadata／分 P、路徑設定與失效、已下載檔案的播放與清理、各平台權限）；
- `accounts-network.md` 補帳號系統全貌序列圖、「請求類型 × 音源」憑證矩陣、登入／未登入能力差異；
- `questions.md` 補下載、權限、帳號、「用登入狀態播放」相關決策。
- 已寫在其他審計檔案的內容只引用，不重寫。

## 驗收標準

- [ ] 13 份文件（含補充的 `downloads.md`）齊全，各自覆蓋 parent PRD 對應條目列出的每一小項（做不到的明寫原因）。
- [ ] 每份文件開頭有「現況描述，未經確認，不代表目標」。
- [ ] 結論皆附證據；文檔／代碼不一致處標「不一致」；推測標「推測」。
- [ ] `questions.md` 含 parent PRD 列出的必備項（每份 ADR、每個 CONTEXT.md 術語、平台綁定功能、
      測試類別、資料層、i18n 語言、發佈管道），按影響大小排序。
- [ ] `git diff main --stat` 只含 `docs/audit/` 與 `.trellis/tasks/`。
- [ ] 結束時給使用者一頁摘要與最需先決定的 10 件事，然後停下等回覆。
