import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/app_scope.dart';
import 'package:fmp/app/fmp_app.dart';
import 'package:fmp/app/startup_maintenance.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_file.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/queue_repository.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';
import 'package:fmp/platform/connectivity/connectivity.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/ui/shell/app_shell.dart';
import 'package:path/path.dart' as p;

import '../support/fake_network_interfaces.dart';
import '../support/memory_database.dart';

void main() {
  Log newLog() => Log(redactor: Redactor(), minimumLevel: LogLevel.debug);

  Iterable<LogRecord> maintenance(Log log) =>
      log.history.where((record) => record.tag == 'maintenance');

  test(
    'runs in order; a failing task is reported and the next still runs',
    () async {
      final log = newLog();
      final ran = <String>[];
      await runStartupMaintenance([
        StartupMaintenanceTask(id: 'a', run: () async => ran.add('a')),
        StartupMaintenanceTask(
          id: 'b',
          run: () async {
            ran.add('b');
            throw StateError('boom');
          },
        ),
        StartupMaintenanceTask(id: 'c', run: () async => ran.add('c')),
      ], log);

      expect(ran, ['a', 'b', 'c']);
      final records = maintenance(log).toList();
      expect(
        [for (final r in records) (r.fields['id'], r.fields['outcome'])],
        [('a', 'ok'), (null, null), ('b', 'failed'), ('c', 'ok')],
      );
      final failure = records[1];
      expect(failure.level, LogLevel.error);
      expect(failure.message, 'Startup maintenance task failed');
      expect(failure.fields['type'], 'UnexpectedError');
    },
  );

  testWidgets('runs once, after the first frame', (tester) async {
    final log = newLog();
    var runs = 0;
    bool? shellPainted;
    Future<void> pump() => tester.pumpWidget(
      appProviderScope(
        overrides: [
          dataDirectoryProvider.overrideWithValue(Directory('/data/fmp-dev')),
          appDatabaseProvider.overrideWithValue(memoryDatabase()),
          redactorProvider.overrideWithValue(Redactor()),
          logProvider.overrideWithValue(log),
          platformCapabilitiesProvider.overrideWithValue(
            PlatformCapabilities.none,
          ),
          networkInterfacesProvider.overrideWithValue(FakeNetworkInterfaces()),
          startupMaintenanceTasksProvider.overrideWithValue([
            StartupMaintenanceTask(
              id: 'count',
              run: () async {
                runs++;
                // 跑的時候外殼已經建好、排版並畫過：不在 initState、build 或
                // runApp 的同步段裡。
                final shell = find.byType(AppShell);
                shellPainted =
                    shell.evaluate().isNotEmpty &&
                    !tester.renderObject(shell).debugNeedsPaint;
              },
            ),
          ]),
        ],
        child: const FmpApp(flavor: AppFlavor.dev),
      ),
    );

    await pump();
    expect(runs, 1);
    expect(shellPainted, isTrue);

    // 之後的幀、同一棵樹再建一次（FmpApp 只更新、不重掛）都不再跑。
    await pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(runs, 1);
    expect(maintenance(log).single.fields['id'], 'count');
  });

  group('the default list', () {
    late Directory temp;
    setUp(() async {
      temp = await Directory.systemTemp.createTemp('fmp_startup_test');
      addTearDown(() => temp.delete(recursive: true));
    });

    Future<void> runDefault(Log log, {AppDatabase? database}) {
      final container = ProviderContainer(
        overrides: [
          logProvider.overrideWithValue(log),
          appDatabaseProvider.overrideWithValue(database ?? memoryDatabase()),
        ],
      );
      addTearDown(container.dispose);
      return runStartupMaintenance(
        container.read(startupMaintenanceTasksProvider),
        log,
      );
    }

    test('log-retention deletes expired log files', () async {
      final logs = Directory(p.join(temp.path, 'logs'))..createSync();
      final expired = File(p.join(logs.path, 'fmp.1.jsonl'))
        ..writeAsStringSync('{}\n')
        ..setLastModifiedSync(DateTime.now().subtract(const Duration(days: 8)));
      final log = Log(
        redactor: Redactor(),
        minimumLevel: LogLevel.debug,
        file: LogFile(logs),
      );

      await runDefault(log);

      expect(expired.existsSync(), isFalse);
      final records = maintenance(log).toList();
      expect(
        [for (final r in records) r.message],
        [
          'Deleted expired log files',
          'Startup maintenance task finished',
          'Deleted orphan tracks',
          'Startup maintenance task finished',
        ],
      );
      expect(records.first.fields, {'count': 1});
      expect(records[1].fields, {'id': 'log-retention', 'outcome': 'ok'});
    });

    test('log-retention has nothing to do without a log file', () async {
      final log = newLog();

      await runDefault(log);

      expect(
        [
          for (final r in maintenance(log))
            if (r.message == 'Startup maintenance task finished') r.fields,
        ],
        [
          {'id': 'log-retention', 'outcome': 'ok'},
          {'id': 'orphan-tracks', 'outcome': 'ok'},
        ],
      );
    });

    test('orphan-tracks deletes only the tracks nothing refers to', () async {
      final database = memoryDatabase();
      final repository = QueueRepository(database);
      TrackInfo track(String id) =>
          TrackInfo(sourceTypeId: 'fmp-test', sourceId: id, title: id);
      await repository.write(
        edit: QueueRangeEdit(
          from: 0,
          removed: 0,
          inserted: [track('kept'), track('orphan')],
        ),
        player: const PlayerState(
          currentPosition: 0,
          position: Duration.zero,
          loopMode: LoopMode.off,
          shuffleEnabled: false,
          volume: 1,
          muted: false,
        ),
      );
      await repository.write(
        edit: const QueueRangeEdit(from: 1, removed: 1, inserted: []),
        player: const PlayerState(
          currentPosition: 0,
          position: Duration.zero,
          loopMode: LoopMode.off,
          shuffleEnabled: false,
          volume: 1,
          muted: false,
        ),
      );
      final log = newLog();

      await runDefault(log, database: database);

      expect(
        [
          for (final row
              in await database
                  .customSelect('SELECT track_key FROM tracks')
                  .get())
            row.read<String>('track_key'),
        ],
        ['fmp-test:kept'],
      );
      expect(
        maintenance(log)
            .firstWhere((r) => r.message == 'Deleted orphan tracks')
            .fields,
        {'count': 1},
      );
    });
  });
}
