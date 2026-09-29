/// 使用者選的主題模式（ADR 0011 §決定 7）。沒選過時由上層套用預設值。
///
/// 存進資料庫的字串在 `lib/data/database/converters.dart`，不是 [name]：改名
/// 不會改到資料格式。
enum ThemeModeSetting { system, light, dark }

/// 使用者選的介面語言（ADR 0011 §決定 7）。沒選過時由上層套用預設值。
///
/// 存進資料庫的是 BCP 47 語言標籤（`zh-TW`、`zh-CN`、`en`），對照在
/// `lib/data/database/converters.dart`。
enum LocaleSetting { zhTw, zhCn, en }
