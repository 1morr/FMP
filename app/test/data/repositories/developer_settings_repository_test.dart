import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/repositories/developer_settings_repository.dart';
import 'package:fmp/domain/developer.dart';

import '../../support/memory_database.dart';
import '../../support/pump_until.dart';

void main() {
  test('reads all fields unset before anything is written', () async {
    final repository = DeveloperSettingsRepository(memoryDatabase());

    expect(await repository.read(), DeveloperSettings.empty);
  });

  test('reads back what was written', () async {
    final repository = DeveloperSettingsRepository(memoryDatabase());

    await repository.write(
      developerMode: true,
      logLevel: LogLevelSetting.debug,
      pluginDevFolder: r'C:\plugins',
      reportReminderDismissed: true,
    );

    expect(
      await repository.read(),
      const DeveloperSettings(
        developerMode: true,
        logLevel: LogLevelSetting.debug,
        pluginDevFolder: r'C:\plugins',
        reportReminderDismissed: true,
      ),
    );
  });

  test('a write only changes the fields it is given', () async {
    final database = memoryDatabase();
    final repository = DeveloperSettingsRepository(database);

    await repository.write(logLevel: LogLevelSetting.debug);

    final row = await database
        .customSelect(
          'SELECT developer_mode, log_level, plugin_dev_folder, '
          'report_reminder_dismissed FROM developer_settings',
        )
        .getSingle();
    expect(row.data, {
      'developer_mode': null,
      'log_level': 'debug',
      'plugin_dev_folder': null,
      'report_reminder_dismissed': null,
    });
  });

  group('clear', () {
    test('sets only the named fields back to unset, as NULL', () async {
      final database = memoryDatabase();
      final repository = DeveloperSettingsRepository(database);
      await repository.write(
        developerMode: true,
        logLevel: LogLevelSetting.debug,
        reportReminderDismissed: true,
      );

      await repository.clear(logLevel: true);

      expect(
        await repository.read(),
        const DeveloperSettings(
          developerMode: true,
          reportReminderDismissed: true,
        ),
      );
      final row = await database
          .customSelect('SELECT log_level FROM developer_settings')
          .getSingle();
      expect(row.data, {'log_level': null});
    });

    test('with nothing named changes nothing', () async {
      final repository = DeveloperSettingsRepository(memoryDatabase());
      await repository.write(developerMode: true);

      await repository.clear();

      expect(
        await repository.read(),
        const DeveloperSettings(developerMode: true),
      );
    });
  });

  group('turning developer mode off (ADR 0025 §決定 1)', () {
    test(
      'clears the log level and the plugin folder, keeps the reminder',
      () async {
        final repository = DeveloperSettingsRepository(memoryDatabase());
        await repository.write(
          developerMode: true,
          logLevel: LogLevelSetting.debug,
          pluginDevFolder: r'C:\plugins',
          reportReminderDismissed: true,
        );

        await repository.turnOffDeveloperMode();

        expect(
          await repository.read(),
          const DeveloperSettings(
            developerMode: false,
            reportReminderDismissed: true,
          ),
        );
      },
    );

    // 同一筆寫入：監看的一方不會看到「模式關了、層級仍是 debug」的中間狀態。
    test('is a single write', () async {
      final database = memoryDatabase();
      final repository = DeveloperSettingsRepository(database);
      await repository.write(
        developerMode: true,
        logLevel: LogLevelSetting.debug,
        pluginDevFolder: r'C:\plugins',
      );
      final events = StreamIterator(repository.watch());
      addTearDown(events.cancel);
      expect(await events.moveNext(), isTrue);
      // 以資料庫自己的寫入通知計數：drift 的 watch 會把緊接著的兩次寫入併成一個值，
      // 只看下一個值分不出拆成兩筆的寫法。
      var writes = 0;
      final updates = database
          .tableUpdates(
            TableUpdateQuery.onTable(database.developerSettingsTable),
          )
          .listen((_) => writes++);
      addTearDown(updates.cancel);

      await repository.turnOffDeveloperMode();

      expect(await events.moveNext(), isTrue);
      expect(events.current, const DeveloperSettings(developerMode: false));
      await settle();
      expect(writes, 1);
    });
  });

  test('watch emits the current value and every write', () async {
    final repository = DeveloperSettingsRepository(memoryDatabase());
    final events = StreamIterator(repository.watch());
    addTearDown(events.cancel);

    expect(await events.moveNext(), isTrue);
    expect(events.current, DeveloperSettings.empty);

    await repository.write(developerMode: true);
    expect(await events.moveNext(), isTrue);
    expect(events.current, const DeveloperSettings(developerMode: true));
  });

  group('stored format', () {
    // 資料庫裡的字串是持久化格式（ADR 0010 §決定 2），不是 enum 的名字；與 log 檔的層級
    // 字串相同。
    test('is pinned for every log level', () async {
      final database = memoryDatabase();
      final repository = DeveloperSettingsRepository(database);

      for (final (level, expected) in [
        (LogLevelSetting.debug, 'debug'),
        (LogLevelSetting.info, 'info'),
      ]) {
        await repository.write(logLevel: level);
        final row = await database
            .customSelect('SELECT log_level FROM developer_settings')
            .getSingle();
        expect(row.data['log_level'], expected);
      }
    });

    for (final value in ['warning', 'verbose']) {
      test(
        'an unknown stored log level "$value" is an error, not a guess',
        () async {
          final database = memoryDatabase();
          await database.customStatement(
            'INSERT INTO developer_settings (id, log_level) VALUES (1, ?)',
            [value],
          );

          await expectLater(
            DeveloperSettingsRepository(database).read(),
            throwsFormatException,
          );
        },
      );
    }
  });
}
