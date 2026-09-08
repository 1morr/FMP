import 'package:isar_community/isar.dart';
import 'package:fmp/data/models/settings.dart';

/// Settings 数据仓库
class SettingsRepository {
  final Isar _isar;

  SettingsRepository(this._isar);

  /// 讀取設定，沒有就回 null —— 刻意不建立。
  ///
  /// 給 `runApp()` 之前的主題預讀用：那時候 migration 還沒跑，
  /// 這條路徑不可以先寫進一列預設值。
  Future<Settings?> getOrNull() => _isar.settings.get(0);

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

  /// 原子更新设置（在单个事务中 读取最新值 → 修改 → 保存）
  ///
  /// 解决多个 Notifier 各自持有独立 Settings 副本时，
  /// save() 全量覆盖导致互相覆盖字段的竞态问题。
  Future<Settings> update(void Function(Settings settings) mutate) async {
    late Settings settings;
    await _isar.writeTxn(() async {
      settings = await _isar.settings.get(0) ?? Settings();
      mutate(settings);
      settings.id = 0;
      await _isar.settings.put(settings);
    });
    return settings;
  }

  /// 监听设置变化
  Stream<Settings?> watch() {
    return _isar.settings.watchObject(0);
  }
}
