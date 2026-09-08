import 'package:fmp/i18n/strings.g.dart';

/// 音源識別碼。
///
/// 音源在磁碟上一直都是字串（`@Enumerated(EnumType.name)` 寫的就是 enum 名稱），
/// 這裡只是把 Dart 端的型別對齊成同一件事。改成字串之後：
///
/// - 讀到未知的音源 id 時**原值保留**。舊的封閉 enum 讓 Isar 生成的 reader 在
///   五個 collection 裡各有一句 `?? SourceIds.bilibili`，會把別人備份裡的
///   第四個音源靜默改寫成 B 站。
/// - 新增音源不必動 enum，只要註冊 adapter 並補一筆 i18n。
///
/// 代價是失去編譯期窮盡檢查，所以每個依音源分支的地方都必須明確決定未知 id 的
/// 行為，而不是靠 `default:` 帶過。
abstract final class SourceIds {
  static const String bilibili = 'bilibili';
  static const String youtube = 'youtube';
  static const String netease = 'netease';

  /// 內建音源，順序即預設顯示順序。
  ///
  /// 這是模型層的常數而不是從 `SourceManager` 推導：`Settings` 需要它當預設值，
  /// 而讓 `lib/data/models/` 依賴 `lib/data/sources/` 會把依賴方向倒過來。
  static const List<String> values = [bilibili, youtube, netease];

  /// 音源的顯示名稱；查不到 i18n 條目時回傳原始 id。
  ///
  /// 走 slang 的 flat map，所以新增音源只要在 `importPlatform.i18n.json` 補一筆
  /// 就有名字，不用改這裡。未知 key 在生成的查表 switch 裡是 `_ => null`。
  static String displayNameFor(String sourceId) {
    final value = t['importPlatform.$sourceId'];
    return value is String ? value : sourceId;
  }
}
