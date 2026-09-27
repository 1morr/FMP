# 執行計畫

本任務只產出設計與 ADR。

- [x] 寫 `docs/adr/0014-script-source-plugins.md`：design.md §1–§8；被否決的選項（編譯期 Dart 插件、內建腳本隨 App 打包、插件放在主 repo、背景自動檢查插件更新、先 Dart 後轉腳本、hetu_script、允許腳本讀其他音源憑證或檔案系統、各功能各自的匹配評分）；「如何確認」（能力宣告與介面一致的結構測試、腳本重播契約測試、網域清單強制的測試、UI 無音源分支的 lint）。
- [x] ADR 0008 加註：音源邏輯改以舊程式碼為規格、用 JS 重寫（見 ADR 0014）。
- [x] `phase2-plan.md` 標記第 1 項完成，第一個里程碑必要驗證加入 YouTube 可行性驗證與 flutter_js 實測，並記下腳本插件是解除功能凍結的例外。
- [x] `phase2-plan.md` 記下：建立 `1morr/fmp-plugins` repo 與其 CI 排入里程碑規劃（不在本任務建立）。
- [x] 歸檔本任務。

驗證：Mermaid 以 mermaid-cli 渲染。
