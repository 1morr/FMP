/// 電台最後一次查到的直播狀態（ADR 0031 §決定 1）。「查詢失敗」與「還沒查過」不是
/// 這個型別的值：前者只在記憶體（D10），後者是狀態欄位為空。
///
/// 存進資料庫的字串在 `lib/data/database/converters.dart`，不是 [name]。
enum RadioLiveStatus { live, offline }
