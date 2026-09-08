import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/models.dart';
import 'package:fmp/data/database/database_catalog.dart';
import 'package:fmp/data/database/database_migration.dart';
import 'package:isar_community/isar.dart';

import '../support/isar_test_harness.dart';

/// 拿真實資料庫的副本用**當前** schema 原地開啟，印出每個 collection 的列數、
/// 音源 id 直方圖與 schema id。改動持久化格式之後用它證明「資料還在、格式沒變」。
///
/// ```bash
/// FMP_PROBE_DB_DIR=/path/to/copy flutter test test/manual/real_db_probe.dart
/// ```
///
/// 那個目錄裡要有 `fmp_database.isar`。**永遠給副本，不要給正在用的資料庫** ——
/// Isar 開啟時會寫入 lock 檔，也可能觸發 compaction。
///
/// 加 `FMP_PROBE_MIGRATE=1` 會在傾印之前跑一次 `runDatabaseMigration`，用來驗證
/// 遷移在真實資料上的結果（前後各跑一次、diff 兩份 JSON）。
///
/// 輸出夾在 `PROBE_JSON_START` / `PROBE_JSON_END` 之間，方便前後兩次 diff。
void main() {
  final dir = Platform.environment['FMP_PROBE_DB_DIR'];

  test('probe a real database copy', () async {
    if (dir == null || dir.isEmpty) {
      fail(
        'set FMP_PROBE_DB_DIR to a directory holding a copy of '
        'fmp_database.isar',
      );
    }

    await initializeIsarForTests();
    final isar = await Isar.open(
      fmpDatabaseSchemas,
      directory: dir,
      name: 'fmp_database',
      maxSizeMiB: 2048,
    );

    if (Platform.environment['FMP_PROBE_MIGRATE'] == '1') {
      await runDatabaseMigration(isar);
    }

    final counts = <String, int>{};
    for (final collection in fmpDatabaseCollections) {
      counts[collection.name] = (await collection.query(isar)).length;
    }

    Map<String, int> hist(Iterable<String> values) {
      final result = <String, int>{};
      for (final value in values) {
        result[value] = (result[value] ?? 0) + 1;
      }
      return result;
    }

    final histograms = <String, Map<String, int>>{
      'track.sourceType': hist(
        (await isar.tracks.where().findAll()).map((e) => e.sourceType),
      ),
      'playHistory.sourceType': hist(
        (await isar.playHistorys.where().findAll()).map((e) => e.sourceType),
      ),
      'radioStation.sourceType': hist(
        (await isar.radioStations.where().findAll()).map((e) => e.sourceType),
      ),
      'playlist.importSourceType': hist(
        (await isar.playlists.where().findAll()).map(
          (e) => e.importSourceType ?? '<null>',
        ),
      ),
      'account.platform': hist(
        (await isar.accounts.where().findAll()).map((e) => e.platform),
      ),
    };

    final settings = await isar.settings.get(0);

    // ignore: avoid_print
    print('PROBE_JSON_START');
    // ignore: avoid_print
    print(
      const JsonEncoder.withIndent('  ').convert({
        'counts': counts,
        'total': counts.values.fold<int>(0, (sum, value) => sum + value),
        'schemaVersion': settings?.schemaVersion,
        'sourceSettings': [
          for (final entry in settings?.sourceSettings ?? const [])
            {
              'sourceId': entry.sourceId,
              'streamPriority': entry.streamPriority,
              'useAuthForPlay': entry.useAuthForPlay,
            },
        ],
        'legacyPerSourceFields': settings == null
            ? null
            : {
                // ignore: deprecated_member_use_from_same_package
                'bilibiliStreamPriority': settings.bilibiliStreamPriority,
                // ignore: deprecated_member_use_from_same_package
                'youtubeStreamPriority': settings.youtubeStreamPriority,
                // ignore: deprecated_member_use_from_same_package
                'neteaseStreamPriority': settings.neteaseStreamPriority,
                // ignore: deprecated_member_use_from_same_package
                'useBilibiliAuthForPlay': settings.useBilibiliAuthForPlay,
                // ignore: deprecated_member_use_from_same_package
                'useYoutubeAuthForPlay': settings.useYoutubeAuthForPlay,
                // ignore: deprecated_member_use_from_same_package
                'useNeteaseAuthForPlay': settings.useNeteaseAuthForPlay,
              },
        'histograms': histograms,
        'schemaIds': {
          'Track': TrackSchema.id,
          'PlayHistory': PlayHistorySchema.id,
          'RadioStation': RadioStationSchema.id,
          'Playlist': PlaylistSchema.id,
          'Account': AccountSchema.id,
        },
      }),
    );
    // ignore: avoid_print
    print('PROBE_JSON_END');

    await isar.close();
  });
}
