import 'package:drift/drift.dart';

import 'package:fmp/domain/appearance.dart';

// 列舉與時間存進資料庫的格式（ADR 0010 §決定 2）。字串逐一寫死，不用 enum 的
// `name`：Dart 端改名不該悄悄改掉已存的資料。讀到不認得的值就拋錯，不猜。

/// [ThemeModeSetting] ↔ `system`／`light`／`dark`。
final class ThemeModeSettingConverter
    extends TypeConverter<ThemeModeSetting, String> {
  const ThemeModeSettingConverter();

  @override
  ThemeModeSetting fromSql(String fromDb) => switch (fromDb) {
    'system' => ThemeModeSetting.system,
    'light' => ThemeModeSetting.light,
    'dark' => ThemeModeSetting.dark,
    _ => throw FormatException('Unknown theme mode in the database', fromDb),
  };

  @override
  String toSql(ThemeModeSetting value) => switch (value) {
    ThemeModeSetting.system => 'system',
    ThemeModeSetting.light => 'light',
    ThemeModeSetting.dark => 'dark',
  };
}

/// [LocaleSetting] ↔ `zh-TW`／`zh-CN`／`en`。
final class LocaleSettingConverter
    extends TypeConverter<LocaleSetting, String> {
  const LocaleSettingConverter();

  @override
  LocaleSetting fromSql(String fromDb) => switch (fromDb) {
    'zh-TW' => LocaleSetting.zhTw,
    'zh-CN' => LocaleSetting.zhCn,
    'en' => LocaleSetting.en,
    _ => throw FormatException('Unknown locale in the database', fromDb),
  };

  @override
  String toSql(LocaleSetting value) => switch (value) {
    LocaleSetting.zhTw => 'zh-TW',
    LocaleSetting.zhCn => 'zh-CN',
    LocaleSetting.en => 'en',
  };
}

/// [DateTime] ↔ UTC epoch 毫秒。drift 內建的 `dateTime()` 存的是秒，所以不用。
final class EpochMillisecondsConverter extends TypeConverter<DateTime, int> {
  const EpochMillisecondsConverter();

  @override
  DateTime fromSql(int fromDb) =>
      DateTime.fromMillisecondsSinceEpoch(fromDb, isUtc: true);

  @override
  int toSql(DateTime value) => value.millisecondsSinceEpoch;
}
