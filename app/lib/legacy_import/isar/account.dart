import 'package:isar_community/isar.dart';

part 'account.g.dart';

/// 舊版帳號列（非敏感資訊；憑證在 secure storage）。
@collection
class Account {
  Id id = Isar.autoIncrement;
  late String platform;
  String? userId;
  String? userName;
  String? avatarUrl;
  bool isLoggedIn = false;
  DateTime? lastRefreshed;
  DateTime? loginAt;
  bool isVip = false;
  bool sessionExpired = false;
}
