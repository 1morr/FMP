import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `Settings` 的持久化欄位清單來自生成碼，不是手寫的 `settings.dart`。
///
/// 手寫檔會誤判：`Settings.useAuthForPlay(String)` 是方法，
/// `SourceSettingsEntry.useAuthForPlay` 是欄位，兩者同名。生成的
/// `PropertySchema` 才是「這個欄位真的會落盤」的唯一真相。
final _propertySchemaPattern = RegExp(
  r"PropertySchema\(\s*id:\s*\d+,\s*name:\s*r'([^']+)'",
);

/// `settings.g.dart` 裡有兩份 schema（`Settings` 與 `SourceSettingsEntry`），
/// 只取前者。
const _settingsSchemaAnchor = 'const SettingsSchema = CollectionSchema(';

/// 刻意不進備份的欄位。每一筆都要有理由 —— 沒有理由的遺漏正是這條規則要抓的東西。
const _deliberatelyExcludedSettingsFields = <String, String>{
  // 遷移簿記。匯入時由 `createBootstrapSettings()` 蓋上當前版本，
  // 讓備份帶著舊版本號回來會讓遷移重跑。
  'schemaVersion': 'migration bookkeeping, stamped by the importer',

  // 裝置相關：換一台機器就沒有意義，匯入時保留現值。
  'customDownloadDir': 'device-specific path, preserved on import',
  'preferredAudioDeviceId': 'device-specific audio device, preserved on import',
  'preferredAudioDeviceName':
      'device-specific audio device, preserved on import',

  // schema v2 之後由 `sourceSettings` 取代，只剩 v1→v2 遷移讀得到。
  'bilibiliStreamPriority': 'superseded by sourceSettings in schema v2',
  'youtubeStreamPriority': 'superseded by sourceSettings in schema v2',
  'neteaseStreamPriority': 'superseded by sourceSettings in schema v2',
  'useBilibiliAuthForPlay': 'superseded by sourceSettings in schema v2',
  'useYoutubeAuthForPlay': 'superseded by sourceSettings in schema v2',
  'useNeteaseAuthForPlay': 'superseded by sourceSettings in schema v2',
};

void main() {
  group('Settings backup coverage', () {
    test('every persisted Settings field is backed up or named as excluded',
        () {
      final generated =
          File('lib/data/models/settings.g.dart').readAsStringSync();
      final dto =
          File('lib/services/backup/backup_data.dart').readAsStringSync();
      final service =
          File('lib/services/backup/backup_service.dart').readAsStringSync();

      // 先釘住抽取本身有作用：anchor 一旦對不上，欄位集合會是空的，
      // 下面那條斷言就會無條件通過 —— 假綠比沒有測試更糟。
      expect(persistedSettingsFields(generated).length, greaterThan(40));

      expect(
        settingsBackupCoverageOffenders(generated, dto, service),
        isEmpty,
      );
    });

    test('no exclusion names a field that no longer exists', () {
      final generated =
          File('lib/data/models/settings.g.dart').readAsStringSync();

      expect(staleSettingsExclusions(generated), isEmpty);
    });

    test('guard detects a new persisted field that never reaches the backup',
        () {
      final generated = _syntheticSettingsSchema(['newKnob']);

      expect(
        settingsBackupCoverageOffenders(generated, '', ''),
        contains(contains('newKnob')),
      );
    });

    test('guard stays silent for a field wired through all three directions',
        () {
      final generated = _syntheticSettingsSchema(['newKnob']);
      const dto = "'newKnob': newKnob,\n json['newKnob'] as bool?";
      const service = 'newKnob: settings.newKnob\n'
          '..newKnob = settingsBackup.newKnob';

      expect(
        settingsBackupCoverageOffenders(generated, dto, service),
        isEmpty,
      );
    });

    test('guard detects a field that is exported but never imported back', () {
      final generated = _syntheticSettingsSchema(['newKnob']);
      const dto = "'newKnob': newKnob,\n json['newKnob'] as bool?";
      const service = 'newKnob: settings.newKnob';

      expect(
        settingsBackupCoverageOffenders(generated, dto, service),
        contains(contains('never written back')),
      );
    });

    test('guard detects a field whose JSON key only appears in one direction',
        () {
      final generated = _syntheticSettingsSchema(['newKnob']);
      const dto = "'newKnob': newKnob,";
      const service = 'newKnob: settings.newKnob\n'
          '..newKnob = settingsBackup.newKnob';

      expect(
        settingsBackupCoverageOffenders(generated, dto, service),
        contains(contains('JSON key')),
      );
    });

    test('guard stays silent for an excluded field', () {
      final generated = _syntheticSettingsSchema(['customDownloadDir']);

      expect(
        settingsBackupCoverageOffenders(generated, '', ''),
        isEmpty,
      );
    });

    test('stale-exclusion guard fires when an excluded field disappears', () {
      final generated = _syntheticSettingsSchema(['themeModeIndex']);

      expect(
        staleSettingsExclusions(generated),
        contains(contains('no longer a persisted field')),
      );
    });

    test('field extraction reads the Settings schema, not embedded schemas',
        () {
      final generated = '${_syntheticSettingsSchema(['themeModeIndex'])}\n'
          'const SourceSettingsEntrySchema = Schema(\n'
          '  properties: {\n'
          "    r'useAuthForPlay': PropertySchema(\n"
          '      id: 2,\n'
          "      name: r'useAuthForPlay',\n"
          '      type: IsarType.bool,\n'
          '    )\n'
          '  },\n'
          '  estimateSize: _estimateSize,\n'
          ');';

      expect(persistedSettingsFields(generated), {'themeModeIndex'});
    });
  });
}

/// 掃原始碼判斷「每個持久化的 `Settings` 欄位都到得了備份」。
///
/// 純函式，不碰檔案系統 —— 同一份邏輯能餵真實檔案，也能餵合成字串，
/// 所以上面的 meta 測試可以驗證這個 guard 自己抓不抓得到違規。
List<String> settingsBackupCoverageOffenders(
  String settingsGeneratedSource,
  String backupDtoSource,
  String backupServiceSource,
) {
  final offenders = <String>[];

  for (final field in persistedSettingsFields(settingsGeneratedSource)) {
    if (_deliberatelyExcludedSettingsFields.containsKey(field)) continue;

    // fromJson 與 toJson 各要出現一次。只出現一次代表單向 —— 匯得出去卻讀不
    // 回來，或反過來。`sourceSettings` 的 fromJson 走 `_readSourceSettings`，
    // 但那個 helper 同樣在這個檔案裡讀 `json['sourceSettings']`。
    final keyUses = "'$field'".allMatches(backupDtoSource).length;
    if (keyUses < 2) {
      offenders.add(
        '$field: JSON key appears $keyUses time(s) in backup_data.dart, '
        'needs both a fromJson read and a toJson write',
      );
    }
    // 建構子參數不用查 —— final 欄位少了參數本來就編不過。
    if (!backupServiceSource.contains('settings.$field')) {
      offenders.add('$field: never read out of Settings on export');
    }
    if (!backupServiceSource.contains('settingsBackup.$field')) {
      offenders.add('$field: never written back into Settings on import');
    }
  }

  return offenders;
}

/// 排除清單自己的衛生檢查：不讓它指向已經不存在的欄位而慢慢腐爛。
List<String> staleSettingsExclusions(String settingsGeneratedSource) {
  final persisted = persistedSettingsFields(settingsGeneratedSource);

  return [
    for (final excluded in _deliberatelyExcludedSettingsFields.keys)
      if (!persisted.contains(excluded))
        '$excluded: named as deliberately excluded but is no longer a '
            'persisted field — drop it from the exclusion list',
  ];
}

/// 從生成碼裡取 `Settings` 的持久化欄位名稱。
Set<String> persistedSettingsFields(String settingsGeneratedSource) {
  final anchor = settingsGeneratedSource.indexOf(_settingsSchemaAnchor);
  if (anchor < 0) return const {};

  final propertiesStart =
      settingsGeneratedSource.indexOf('properties: {', anchor);
  if (propertiesStart < 0) return const {};

  // `estimateSize:` 是 properties map 之後的第一個 top-level 欄位，用它當結尾，
  // 避免掃進同一個檔案裡別的 schema。
  final propertiesEnd =
      settingsGeneratedSource.indexOf('estimateSize:', propertiesStart);
  final block = propertiesEnd < 0
      ? settingsGeneratedSource.substring(propertiesStart)
      : settingsGeneratedSource.substring(propertiesStart, propertiesEnd);

  return _propertySchemaPattern
      .allMatches(block)
      .map((match) => match.group(1)!)
      .toSet();
}

String _syntheticSettingsSchema(List<String> fields) {
  final buffer = StringBuffer()
    ..writeln(_settingsSchemaAnchor)
    ..writeln('  properties: {');
  for (var i = 0; i < fields.length; i++) {
    buffer
      ..writeln("    r'${fields[i]}': PropertySchema(")
      ..writeln('      id: $i,')
      ..writeln("      name: r'${fields[i]}',")
      ..writeln('      type: IsarType.bool,')
      ..writeln('    ),');
  }
  return (buffer
        ..writeln('  },')
        ..writeln('  estimateSize: _estimateSize,')
        ..writeln(');'))
      .toString();
}
