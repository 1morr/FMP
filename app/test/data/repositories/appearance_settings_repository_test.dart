import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/repositories/appearance_settings_repository.dart';
import 'package:fmp/domain/appearance.dart';

import '../../support/memory_database.dart';

void main() {
  test('reads all fields unset before anything is written', () async {
    final repository = AppearanceSettingsRepository(memoryDatabase());

    expect(await repository.read(), AppearanceSettings.empty);
  });

  test('reads back what was written', () async {
    final repository = AppearanceSettingsRepository(memoryDatabase());

    await repository.write(
      themeMode: ThemeModeSetting.light,
      locale: LocaleSetting.zhCn,
    );

    expect(
      await repository.read(),
      const AppearanceSettings(
        themeMode: ThemeModeSetting.light,
        locale: LocaleSetting.zhCn,
      ),
    );
  });

  test('a partial write keeps the other field', () async {
    final repository = AppearanceSettingsRepository(memoryDatabase());

    await repository.write(locale: LocaleSetting.en);
    await repository.write(themeMode: ThemeModeSetting.dark);

    expect(
      await repository.read(),
      const AppearanceSettings(
        themeMode: ThemeModeSetting.dark,
        locale: LocaleSetting.en,
      ),
    );
  });

  test('watch emits the current value and every write', () async {
    final repository = AppearanceSettingsRepository(memoryDatabase());
    final events = StreamIterator(repository.watch());
    addTearDown(events.cancel);

    expect(await events.moveNext(), isTrue);
    expect(events.current, AppearanceSettings.empty);

    await repository.write(themeMode: ThemeModeSetting.system);
    expect(await events.moveNext(), isTrue);
    expect(
      events.current,
      const AppearanceSettings(themeMode: ThemeModeSetting.system),
    );
  });

  group('stored format', () {
    // 資料庫裡的字串是持久化格式（ADR 0010 §決定 2），不是 enum 的名字。
    test('is pinned for every value', () async {
      final database = memoryDatabase();
      final repository = AppearanceSettingsRepository(database);
      Future<List<Object?>> stored() async =>
          (await database
                  .customSelect(
                    'SELECT theme_mode, locale FROM appearance_settings',
                  )
                  .getSingle())
              .data
              .values
              .toList();

      for (final (themeMode, locale, expected) in [
        (ThemeModeSetting.system, LocaleSetting.zhTw, ['system', 'zh-TW']),
        (ThemeModeSetting.light, LocaleSetting.zhCn, ['light', 'zh-CN']),
        (ThemeModeSetting.dark, LocaleSetting.en, ['dark', 'en']),
      ]) {
        await repository.write(themeMode: themeMode, locale: locale);
        expect(await stored(), expected);
      }
    });

    for (final (column, value) in [('theme_mode', 'sepia'), ('locale', 'ja')]) {
      test('an unknown stored $column is an error, not a guess', () async {
        final database = memoryDatabase();
        await database.customStatement(
          'INSERT INTO appearance_settings (id, $column) VALUES (1, ?)',
          [value],
        );

        await expectLater(
          AppearanceSettingsRepository(database).read(),
          throwsFormatException,
        );
      });
    }
  });
}
