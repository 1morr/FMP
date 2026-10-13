/// 宿主知道的外部網址（`fmp_url_literal` 唯一允許網址字面值的檔案）。
library;

/// 官方插件 index（`1morr/fmp-plugins` 的 `main` 分支）。
///
/// raw.githubusercontent.com 有約 5 分鐘的 CDN 快取：插件庫剛合併後，index 與
/// 插件檔可能暫時不是同一版，SHA-256 不符是預期內的，稍後重試即可（design §7.1）。
const officialPluginIndexUrl =
    'https://raw.githubusercontent.com/1morr/fmp-plugins/main/index.json';

/// 「在 GitHub 回報」開的新增 issue 頁（bug 範本，`.github/ISSUE_TEMPLATE/bug_report.yml`）。
/// 報告內容不放進網址：網址會被瀏覽器記錄、也有長度上限（ADR 0023 §考慮過的選項）。
/// 一律回報到 `1morr/FMP`，插件的問題由維護者 Transfer 到插件庫（M3 design §13）。
const newIssueUrl =
    'https://github.com/1morr/FMP/issues/new?template=bug_report.yml';
