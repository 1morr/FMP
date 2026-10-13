import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/developer_settings_repository.dart';
import 'package:fmp/domain/developer.dart';

/// 這個建置的預設 log 層級（ADR 0011 §決定 2：debug build 是 debug，profile、release 是
/// info），也就是「開發者」組 log 層級沒設定過、或開發者模式關著時的生效值。
///
/// 是 provider 而不是直接讀 `kDebugMode`：`flutter test` 永遠是 debug build，測試要
/// override 它才驗得到 release 的行為。App 不 override，值來自門面的
/// [buildDefaultLogLevel]（`main()` 建門面時用同一個）。
final buildLogLevelProvider = Provider<LogLevelSetting>(
  (ref) => switch (buildDefaultLogLevel) {
    LogLevel.debug => LogLevelSetting.debug,
    LogLevel.info || LogLevel.warning || LogLevel.error => LogLevelSetting.info,
  },
);

/// 「開發者」設定套用預設之後的值（ADR 0025 §決定 1、M3 design §3.3）。
@immutable
final class Developer {
  const Developer({
    required this.developerMode,
    required this.logLevel,
    required this.defaultLogLevel,
    required this.stored,
  });

  /// 生效的開發者模式：使用者設定的，沒有就是 flavor 的預設（dev 開、prod 關）。
  final bool developerMode;

  /// 生效的 log 層級：開發者模式開著時是使用者設定的，沒設定過是 [defaultLogLevel]；
  /// 關著時一律是 [defaultLogLevel]（調整層級是開發者模式控制的東西之一，ADR 0025 §決定 1）。
  final LogLevelSetting logLevel;

  /// 這個建置的預設層級（[buildLogLevelProvider]）；Debug 頁標「（預設）」的那一個。
  final LogLevelSetting defaultLogLevel;

  /// 使用者設定過的值；欄位為 `null` 表示沒設定過、目前用的是預設。
  final DeveloperSettings stored;

  /// log 門面的最低層級（`Log.minimumLevel`）。
  LogLevel get minimumLogLevel => switch (logLevel) {
    LogLevelSetting.debug => LogLevel.debug,
    LogLevelSetting.info => LogLevel.info,
  };

  @override
  bool operator ==(Object other) =>
      other is Developer &&
      other.developerMode == developerMode &&
      other.logLevel == logLevel &&
      other.defaultLogLevel == defaultLogLevel &&
      other.stored == stored;

  @override
  int get hashCode =>
      Object.hash(developerMode, logLevel, defaultLogLevel, stored);

  @override
  String toString() =>
      'Developer(developerMode: $developerMode, logLevel: $logLevel, '
      'defaultLogLevel: $defaultLogLevel, stored: $stored)';
}

/// 在讀取時套用預設（ADR 0011 §決定 7）：開發者模式沒設定過時 [AppFlavor.dev] 開、
/// [AppFlavor.prod] 關；log 層級沒設定過是這個建置的預設 [buildLogLevel]。預設值不寫進
/// 資料庫。
Developer resolveDeveloper(
  DeveloperSettings stored, {
  required AppFlavor flavor,
  required LogLevelSetting buildLogLevel,
}) {
  final developerMode = stored.developerMode ?? flavor == AppFlavor.dev;
  return Developer(
    developerMode: developerMode,
    logLevel: developerMode ? stored.logLevel ?? buildLogLevel : buildLogLevel,
    defaultLogLevel: buildLogLevel,
    stored: stored,
  );
}

/// 「開發者」設定：監看 `developer_settings` 那一列，對外是套用預設後的 [Developer]。
final developerProvider = StreamNotifierProvider<DeveloperNotifier, Developer>(
  DeveloperNotifier.new,
);

final class DeveloperNotifier extends StreamNotifier<Developer> {
  @override
  Stream<Developer> build() {
    final flavor = ref.watch(appFlavorProvider);
    final buildLogLevel = ref.watch(buildLogLevelProvider);
    return ref
        .watch(developerSettingsRepositoryProvider)
        .watch()
        .map(
          (stored) => resolveDeveloper(
            stored,
            flavor: flavor,
            buildLogLevel: buildLogLevel,
          ),
        );
  }

  /// 開啟（「關於」的版本列連點 7 次）只寫 `developer_mode`；關閉（Debug 頁的總開關）
  /// 在同一筆寫入清空 log 層級與插件開發資料夾（ADR 0025 §決定 1）。
  Future<void> setDeveloperMode(bool enabled) {
    final repository = ref.read(developerSettingsRepositoryProvider);
    return enabled
        ? repository.write(developerMode: true)
        : repository.turnOffDeveloperMode();
  }

  /// 只寫 log 層級這個欄位；`null` 清回沒設定過（這個建置的預設）。
  Future<void> setLogLevel(LogLevelSetting? level) {
    final repository = ref.read(developerSettingsRepositoryProvider);
    return level == null
        ? repository.clear(logLevel: true)
        : repository.write(logLevel: level);
  }
}
