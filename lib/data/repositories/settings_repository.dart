import 'package:isar/isar.dart';
import '../models/settings.dart';

/// Settings 数据仓库
class SettingsRepository {
  final Isar _isar;

  SettingsRepository(this._isar);

  /// 获取设置（单例，ID始终为0）
  Future<Settings> get() async {
    var settings = await _isar.settings.get(0);
    if (settings == null) {
      settings = Settings();
      await _isar.writeTxn(() => _isar.settings.put(settings!));
    }
    return settings;
  }

  /// 保存设置
  Future<void> save(Settings settings) async {
    settings.id = 0; // 确保始终使用ID 0
    await _isar.writeTxn(() => _isar.settings.put(settings));
  }

  /// 监听设置变化
  Stream<Settings?> watch() {
    return _isar.settings.watchObject(0);
  }
}
