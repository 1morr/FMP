/// 「開發者」設定組的 log 層級（ADR 0025 §決定 1、M3 design §3.3）。只有這兩個：
/// warning、error 一律記，不能調得比 info 更少。
///
/// 存進資料庫的字串在 `lib/data/database/converters.dart`，不是 [name]。
enum LogLevelSetting { debug, info }
