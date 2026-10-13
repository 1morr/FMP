import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/developer_settings_repository.dart';
import 'package:fmp/domain/developer.dart';
import 'package:fmp/settings/developer_settings.dart';

import '../support/memory_database.dart';

void main() {
  /// [buildLogLevel] 固定建置模式：`flutter test` 永遠是 debug build，預設給 release 的 info。
  ProviderContainer containerFor(
    AppDatabase database,
    AppFlavor flavor, {
    LogLevelSetting buildLogLevel = LogLevelSetting.info,
  }) => ProviderContainer.test(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      appFlavorProvider.overrideWithValue(flavor),
      buildLogLevelProvider.overrideWithValue(buildLogLevel),
    ],
  );

  /// 訂閱 [developerProvider]，依序取得它發出的值。
  StreamIterator<Developer> developers(ProviderContainer container) {
    final controller = StreamController<Developer>();
    container.listen(developerProvider, (_, next) {
      if (next case AsyncData(:final value)) controller.add(value);
    }, fireImmediately: true);
    final iterator = StreamIterator(controller.stream);
    addTearDown(() async {
      await iterator.cancel();
      await controller.close();
    });
    return iterator;
  }

  group('defaults (ADR 0025 §決定 1、ADR 0011 §決定 2)', () {
    test('developer mode is on in dev and off in prod', () {
      for (final (flavor, on) in [
        (AppFlavor.dev, true),
        (AppFlavor.prod, false),
      ]) {
        expect(
          resolveDeveloper(
            DeveloperSettings.empty,
            flavor: flavor,
            buildLogLevel: LogLevelSetting.info,
          ).developerMode,
          on,
          reason: flavor.name,
        );
      }
    });

    test('an unset log level is the build default: info in a release build, '
        'debug in a debug build', () {
      for (final (build, level) in [
        (LogLevelSetting.info, LogLevel.info),
        (LogLevelSetting.debug, LogLevel.debug),
      ]) {
        for (final flavor in AppFlavor.values) {
          final developer = resolveDeveloper(
            DeveloperSettings.empty,
            flavor: flavor,
            buildLogLevel: build,
          );
          expect(developer.logLevel, build, reason: '$build, ${flavor.name}');
          expect(developer.defaultLogLevel, build);
          expect(developer.minimumLogLevel, level);
        }
      }
    });

    test('a value the user set wins over either flavor default', () {
      for (final flavor in AppFlavor.values) {
        for (final mode in [false, true]) {
          expect(
            resolveDeveloper(
              DeveloperSettings(developerMode: mode),
              flavor: flavor,
              buildLogLevel: LogLevelSetting.info,
            ).developerMode,
            mode,
          );
        }
      }
    });

    test('the stored log level counts only while developer mode is on; off, '
        'it is the build default', () {
      // release：存了 debug，開著是 debug，關著回到 info。
      const debug = DeveloperSettings(logLevel: LogLevelSetting.debug);
      final on = resolveDeveloper(
        debug,
        flavor: AppFlavor.dev,
        buildLogLevel: LogLevelSetting.info,
      );
      expect(on.logLevel, LogLevelSetting.debug);
      expect(on.minimumLogLevel, LogLevel.debug);
      final off = resolveDeveloper(
        debug,
        flavor: AppFlavor.prod,
        buildLogLevel: LogLevelSetting.info,
      );
      expect(off.logLevel, LogLevelSetting.info);
      expect(off.stored, debug, reason: 'the stored value is untouched');

      // debug build：存了 info，開著是 info，關著回到 debug。
      const info = DeveloperSettings(logLevel: LogLevelSetting.info);
      expect(
        resolveDeveloper(
          info,
          flavor: AppFlavor.dev,
          buildLogLevel: LogLevelSetting.debug,
        ).logLevel,
        LogLevelSetting.info,
      );
      expect(
        resolveDeveloper(
          info,
          flavor: AppFlavor.prod,
          buildLogLevel: LogLevelSetting.debug,
        ).logLevel,
        LogLevelSetting.debug,
      );
    });
  });

  test('in a debug build the notifier defaults to debug', () async {
    final container = containerFor(
      memoryDatabase(),
      AppFlavor.dev,
      buildLogLevel: LogLevelSetting.debug,
    );
    final values = developers(container);

    expect(await values.moveNext(), isTrue);
    expect(values.current.logLevel, LogLevelSetting.debug);
    expect(values.current.defaultLogLevel, LogLevelSetting.debug);
    expect(values.current.stored, DeveloperSettings.empty);
  });

  test('without a stored value the notifier follows the flavor', () async {
    for (final (flavor, on) in [
      (AppFlavor.dev, true),
      (AppFlavor.prod, false),
    ]) {
      final container = containerFor(memoryDatabase(), flavor);
      final values = developers(container);

      expect(await values.moveNext(), isTrue);
      expect(values.current.developerMode, on, reason: flavor.name);
      expect(values.current.stored, DeveloperSettings.empty);
    }
  });

  test('turning it on writes developer_mode = true and nothing else', () async {
    final database = memoryDatabase();
    final container = containerFor(database, AppFlavor.prod);
    final values = developers(container);
    expect(await values.moveNext(), isTrue);
    expect(values.current.developerMode, isFalse);

    await container.read(developerProvider.notifier).setDeveloperMode(true);

    expect(await values.moveNext(), isTrue);
    expect(values.current.developerMode, isTrue);
    expect(
      await DeveloperSettingsRepository(database).read(),
      const DeveloperSettings(developerMode: true),
    );
  });

  test('turning it off clears the log level and the plugin folder in the '
      'same write', () async {
    final database = memoryDatabase();
    await DeveloperSettingsRepository(database).write(
      developerMode: true,
      logLevel: LogLevelSetting.debug,
      pluginDevFolder: r'C:\plugins',
    );
    final container = containerFor(database, AppFlavor.dev);
    final values = developers(container);
    expect(await values.moveNext(), isTrue);
    expect(values.current.logLevel, LogLevelSetting.debug);

    await container.read(developerProvider.notifier).setDeveloperMode(false);

    // 下一個值就已經全部清掉：沒有「模式關了、層級仍是 debug」的那一刻。
    expect(await values.moveNext(), isTrue);
    expect(
      values.current,
      resolveDeveloper(
        const DeveloperSettings(developerMode: false),
        flavor: AppFlavor.dev,
        buildLogLevel: LogLevelSetting.info,
      ),
    );
    expect(values.current.logLevel, LogLevelSetting.info);
  });

  test('the log level setter writes only that field; null clears it', () async {
    final database = memoryDatabase();
    final container = containerFor(database, AppFlavor.dev);
    final values = developers(container);
    expect(await values.moveNext(), isTrue);
    final notifier = container.read(developerProvider.notifier);

    await notifier.setLogLevel(LogLevelSetting.debug);
    expect(await values.moveNext(), isTrue);
    expect(values.current.logLevel, LogLevelSetting.debug);
    final row = await database
        .customSelect(
          'SELECT developer_mode, log_level FROM developer_settings',
        )
        .getSingle();
    expect(row.data, {'developer_mode': null, 'log_level': 'debug'});

    await notifier.setLogLevel(null);
    expect(await values.moveNext(), isTrue);
    expect(values.current.logLevel, LogLevelSetting.info);
    expect(values.current.stored, DeveloperSettings.empty);
  });
}
