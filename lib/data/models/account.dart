import 'package:isar/isar.dart';

import 'track.dart';

part 'account.g.dart';

/// 帳號實體（Isar Collection）
///
/// 存儲非敏感的用戶信息和登錄狀態。
/// Cookie/Token 等敏感憑據存儲在 flutter_secure_storage 中。
@collection
class Account {
  Id id = Isar.autoIncrement;

  /// 平台類型
  @Enumerated(EnumType.name)
  late SourceType platform;

  /// 平台用戶 ID（Bilibili: DedeUserID）
  String? userId;

  /// 用戶暱稱
  String? userName;

  /// 頭像 URL
  String? avatarUrl;

  /// 是否已登錄
  bool isLoggedIn = false;

  /// 上次認證刷新時間
  DateTime? lastRefreshed;

  /// 登錄時間
  DateTime? loginAt;

  /// 是否為 VIP（目前僅網易雲使用）
  bool isVip = false;

  @override
  String toString() =>
      'Account(id: $id, platform: $platform, userName: $userName, isLoggedIn: $isLoggedIn)';
}
