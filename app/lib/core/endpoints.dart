/// 宿主知道的外部網址（`fmp_url_literal` 唯一允許網址字面值的檔案）。
library;

/// 官方插件 index（`1morr/fmp-plugins` 的 `main` 分支）。
///
/// raw.githubusercontent.com 有約 5 分鐘的 CDN 快取：插件庫剛合併後，index 與
/// 插件檔可能暫時不是同一版，SHA-256 不符是預期內的，稍後重試即可（design §7.1）。
const officialPluginIndexUrl =
    'https://raw.githubusercontent.com/1morr/fmp-plugins/main/index.json';
