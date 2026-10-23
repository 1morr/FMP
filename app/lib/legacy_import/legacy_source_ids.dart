// 舊版的三個音源 id，與新版官方插件的 id 字面相同，不轉換（M5 design §5.1）。官方插件 id 的字面值
// 只准寫在 `lib/legacy_import/`（`fmp_source_id_literal`）。

const legacyBilibili = 'bilibili';
const legacyYoutube = 'youtube';
const legacyNetease = 'netease';

/// 舊版有、新版也有同名插件的音源。其他值的列略過（`SkipReason.unknownSource`）。
const legacySourceIds = {legacyBilibili, legacyYoutube, legacyNetease};

/// 外部匯入的來源平台（`track_origins.origin_plugin_id`）：舊 `Track.originalSource` 的值，
/// 與新版官方插件的 id 相同。`spotify` 在舊版也有，但新版沒有對應的曲目 id，不匯入。
const legacyQqmusic = 'qqmusic';
