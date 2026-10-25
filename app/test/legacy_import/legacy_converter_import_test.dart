import 'dart:io';
import 'dart:math';
import 'dart:ui' show Color;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/import/import_bundle.dart';
import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/data/import/staging_import.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/data/repositories/appearance_settings_repository.dart';
import 'package:fmp/data/repositories/layout_state_repository.dart';
import 'package:fmp/data/repositories/network_settings_repository.dart';
import 'package:fmp/data/repositories/playback_settings_repository.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/domain/legacy_import.dart';
import 'package:fmp/domain/playlist.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/legacy_import/legacy_converter.dart';
import 'package:fmp/legacy_import/legacy_database_reader.dart';
import 'package:fmp/legacy_import/legacy_settings_converter.dart';
import 'package:fmp/legacy_import/legacy_snapshot.dart';
import 'package:path/path.dart' as p;

import '../support/legacy_database.dart';
import 'legacy_credential_fixtures.dart';
import 'legacy_snapshot_builders.dart';

/// 每個 collection：讀到的 = 寫出的 + 略過的筆數（註記在 `notes`，不算）。
void _expectBalanced(ImportBundle bundle) {
  for (final MapEntry(:key, :value)
      in bundle.record.summary.collections.entries) {
    final skipped = value.skipped.values.fold<int>(0, (sum, n) => sum + n);
    expect(value.read, value.written + skipped, reason: key);
  }
}

Future<void> _writeAndVerify(ImportBundle bundle, Directory temp) async {
  final staging = File(p.join(temp.path, 'legacy-import', 'staging.db'));
  final stager = StagingImport(
    Log(redactor: Redactor(), minimumLevel: LogLevel.warning),
    random: Random(1),
  );
  await stager.write(bundle, staging, importedAt: DateTime.utc(2026, 10, 23));
  await stager.verify(bundle, staging);
  expect(staging.existsSync(), isTrue);
}

// PR 1 的合成舊庫 → 讀取器 → 轉換器 → PR 2 的 `StagingImport.write` 與 `verify`：證明轉換結果滿足
// 驗證的不變式（每個被參照的鍵都在 `tracks`、沒有孤兒曲目、筆數與抽樣一致）。全是編造資料。

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('fmp_legacy_convert_');
    addTearDown(() => temp.deleteSync(recursive: true));
  });

  test('a converted synthetic legacy database writes and verifies', () async {
    final file = await writeSyntheticLegacyDatabase(
      Directory(p.join(temp.path, 'source')),
    );
    final snapshot = await LegacyDatabaseReader(log: (message, fields) {})
        .read(file, Directory(p.join(temp.path, 'work')));

    final bundle = const LegacyConverter()
        .convert(
          snapshot,
          source: LegacyImportSource.database,
          now: DateTime.utc(2026, 10, 23),
        )
        .bundle;

    // 合成庫的內容對照：
    // - 曲目：3 號（單 P、兩段）與 4 號（單 P、舊版補了 cid）去 cid；多 P 兩首留 cid；
    //   重複鍵的 youtube 併成一列；歷史補出兩首（`BV9gone000009`、兩段鍵的 `BV1synthetic0001`）。
    final keys = bundle.tracks.map((t) => t.key.toString()).toSet();
    expect(keys, {
      'bilibili:BV1synthetic0001:1001',
      'bilibili:BV1synthetic0001:1002',
      'bilibili:BV3synthetic0003',
      'bilibili:BV4synthetic0004',
      'youtube:ytsynthetic01',
      'netease:10001',
      'bilibili:BV9gone000009:9009',
      // 歷史第 2 筆是兩段鍵（那時曲目還沒有 cid），`Track` 裡沒有同一個鍵：用歷史快照補一首。
      'bilibili:BV1synthetic0001',
    });
    // - 歌單：Mix（0）、匯入（1，網址是 example.invalid，認不出，轉本機）、本機（2）。
    expect(bundle.playlists.map((p) => p.name), [
      'Synthetic Mix',
      'Synthetic Imported',
      'Synthetic Local',
    ]);
    expect(bundle.playlists.map((p) => p.kind), [
      PlaylistKind.mix,
      PlaylistKind.local,
      PlaylistKind.local,
    ]);
    expect(bundle.playlists.map((p) => p.legacyPlaylistId), [3, 2, 1]);
    // - 本機歌單的懸空 id 略過；單 P 去 cid 後仍接得上。
    expect(bundle.playlists.last.entries.map((e) => e.track.toString()), [
      'bilibili:BV1synthetic0001:1001',
      'bilibili:BV1synthetic0001:1002',
      'bilibili:BV3synthetic0003',
      'youtube:ytsynthetic01',
      'netease:10001',
    ]);
    // - 歷史：兩段與三段的多 P 鍵都對得上 `Track`。
    expect(bundle.history, hasLength(SyntheticLegacy.playHistoryCount));
    expect(bundle.history.first.track, isA<TrackKeyParts>());
    // - 外部來源：netease 的 id 全數字。
    expect(bundle.trackOrigins.single.originId, '10001');
    expect(bundle.radioStations, hasLength(SyntheticLegacy.radioStationCount));

    // 摘要的筆數平衡：讀到的 = 寫出的 + 略過的。
    _expectBalanced(bundle);

    // 暫存庫：寫入、驗證都通過（驗證會擋孤兒曲目與缺少的鍵）。
    await _writeAndVerify(bundle, temp);
  });

  test(
    'the settings of a synthetic database convert, write and read back',
    () async {
      final file = await writeSyntheticLegacyDatabase(
        Directory(p.join(temp.path, 'source')),
      );
      final snapshot = await LegacyDatabaseReader(log: (message, fields) {})
          .read(file, Directory(p.join(temp.path, 'work')));
      final bundle = const LegacyConverter()
          .convert(
            snapshot,
            source: LegacyImportSource.database,
            now: DateTime.utc(2026, 10, 23),
          )
          .bundle;

      // 合成庫的設定：深色、zh_TW、重啟倒帶 5 秒，歷史上限與面板寬度是型別預設（不寫），面板收起照舊值寫，
      // 主色改過（匯入成主題色），三個音源的 useAuthForPlay 是舊預設。
      final expectedAppearance = AppearanceSettings(
        themeMode: ThemeModeSetting.dark,
        locale: LocaleSetting.zhTw,
        seedColor: const Color(0xFF336699),
      );
      final expectedPlayback = PlaybackSettings(restartRewindSeconds: 5);
      final expectedBrowse = {
        'bilibili': true,
        'youtube': false,
        'netease': true,
      };
      expect(bundle.appearance, expectedAppearance);
      expect(bundle.playback, expectedPlayback);
      expect(bundle.network, NetworkSettings.empty);
      expect(
        bundle.layout,
        const LayoutState(panelExpanded: false, railExpanded: false),
      );
      expect(bundle.browseAsLoggedIn, expectedBrowse);
      expect(bundle.record.summary.unimportedSettings, [
        UnimportedSetting.searchHistory,
      ]);

      await _writeAndVerify(bundle, temp);

      final database = AppDatabase(
        NativeDatabase(File(p.join(temp.path, 'legacy-import', 'staging.db'))),
      );
      addTearDown(database.close);
      expect(
        await AppearanceSettingsRepository(database).read(),
        expectedAppearance,
      );
      expect(
        await PlaybackSettingsRepository(database).read(),
        expectedPlayback,
      );
      expect(
        await NetworkSettingsRepository(database).read(),
        NetworkSettings.empty,
      );
      final sources = SourceSettingsRepository(database);
      for (final entry in expectedBrowse.entries) {
        expect(await sources.browseAsLoggedIn(entry.key), entry.value);
      }
    },
  );

  test('the tricky cases of a hand-built snapshot write and verify', () async {
    // 合成庫沒有的：認得的匯入歌單（含重複的遠端）、單 P 兩段與三段併成一列後被歌單、佇列、
    // 歷史同時參照、重複列的外部來源、隨機中的 Mix 佇列、不認得的音源、重複電台。
    final snapshot = legacySnapshot(
      tracks: [
        legacyTrack(id: 1, sourceId: 'BVsingle'),
        legacyTrack(id: 2, sourceId: 'BVsingle', cid: 11, pageCount: 1),
        legacyTrack(
          id: 3,
          sourceId: 'BVmulti',
          cid: 21,
          pageCount: 2,
          pageNum: 1,
          parentTitle: 'Parent',
          isAvailable: false,
        ),
        legacyTrack(
          id: 4,
          sourceId: 'BVmulti',
          cid: 22,
          pageCount: 2,
          pageNum: 2,
          parentTitle: 'Parent',
        ),
        legacyTrack(id: 5, sourceType: 'unknown', sourceId: 'x'),
        legacyTrack(
          id: 6,
          sourceType: 'youtube',
          sourceId: 'yt1',
          originalSource: 'netease',
          originalSongId: '123',
        ),
        legacyTrack(
          id: 7,
          sourceType: 'youtube',
          sourceId: 'yt1',
          updatedAt: baseTime.add(const Duration(days: 1)),
          originalSource: 'netease',
          originalSongId: '456',
        ),
        legacyTrack(
          id: 8,
          sourceType: 'netease',
          sourceId: '1001',
          originalSource: 'qqmusic',
          originalSongId: 'mid001',
        ),
        legacyTrack(id: 9, sourceId: 'BVunreferenced'),
      ],
      playlists: [
        legacyPlaylist(
          id: 10,
          sourceUrl: 'https://space.bilibili.com/1/favlist?fid=42',
          ownerUserId: '1',
          refreshIntervalHours: 24,
          lastRefreshed: baseTime,
          trackIds: [1, 2, 3, 4, 99, 5],
        ),
        legacyPlaylist(
          id: 11,
          sourceUrl: 'https://www.bilibili.com/medialist/detail/ml42',
          trackIds: [3],
          sortOrder: 1,
        ),
        legacyPlaylist(
          id: 12,
          isMix: true,
          mixSeedVideoId: 'seed',
          sortOrder: 2,
        ),
        legacyPlaylist(id: 13, trackIds: [6, 8], sortOrder: 3),
      ],
      queue: legacyQueue(
        trackIds: [4, 2, 6, 1, 2],
        originalOrder: [1, 2, 4, 6, 2],
        currentIndex: 4,
        isShuffleEnabled: true,
        loopMode: LegacyLoopMode.all,
        lastVolume: 0.5,
        lastPositionMs: 1234,
        isMixMode: true,
        mixPlaylistId: 'RDseed',
        mixTitle: 'Mix',
      ),
      history: [
        legacyHistory(id: 1, sourceId: 'BVsingle', cid: 11, playedAt: baseTime),
        legacyHistory(
          id: 2,
          sourceId: 'BVsingle',
          playedAt: baseTime.add(const Duration(minutes: 1)),
        ),
        legacyHistory(
          id: 3,
          sourceId: 'BVgone',
          cid: 99,
          playedAt: baseTime.add(const Duration(minutes: 2)),
        ),
        legacyHistory(
          id: 4,
          sourceType: 'youtube',
          sourceId: 'yt1',
          playedAt: baseTime.add(const Duration(minutes: 3)),
        ),
        legacyHistory(
          id: 5,
          sourceType: 'unknown',
          sourceId: 'x',
          playedAt: baseTime.add(const Duration(minutes: 4)),
        ),
      ],
      radio: [
        legacyRadio(id: 1, sourceId: '100'),
        legacyRadio(id: 2, sourceId: '100', sortOrder: 1),
      ],
      accounts: [legacyAccount(platform: 'bilibili', userId: '1')],
    );

    // 帳號段要有舊憑證：B 站的帳號才匯入，歌單才標可寫。
    final bundle = const LegacyConverter()
        .convert(
          snapshot,
          source: LegacyImportSource.database,
          now: DateTime.utc(2026, 10, 23),
          credentials: legacyReads(
            bilibili: legacyBilibiliJson(dedeUserId: '1'),
          ),
        )
        .bundle;

    expect(bundle.tracks.map((t) => t.key.toString()).toSet(), {
      'bilibili:BVsingle',
      'bilibili:BVmulti:21',
      'bilibili:BVmulti:22',
      'youtube:yt1',
      'netease:1001',
      'bilibili:BVgone:99',
    });
    expect(bundle.playlists.map((p) => p.kind), [
      PlaylistKind.imported,
      PlaylistKind.local,
      PlaylistKind.mix,
      PlaylistKind.local,
    ]);
    expect(bundle.playlists.first.remote!.writable, isTrue);
    // 重複列（6、7 號）只留新的那列的外部來源。
    expect(bundle.trackOrigins.map((o) => o.originId).toSet(), {
      '456',
      'mid001',
    });
    // 目前曲目是 trackIds 的第 2 次出現的 2 號 → 自然順序的第 2 次出現（位置 4）。
    expect(bundle.playerState!.currentPosition, 4);
    expect(bundle.playerState!.mix, isNotNull);
    _expectBalanced(bundle);

    await _writeAndVerify(bundle, temp);
  });

  test('a player state with an empty queue writes and verifies', () async {
    final bundle = const LegacyConverter()
        .convert(
          legacySnapshot(
            queue: legacyQueue(
              loopMode: LegacyLoopMode.all,
              lastVolume: 0.4,
              isMixMode: true,
              mixPlaylistId: 'RDseed',
              mixTitle: 'Mix',
            ),
          ),
          source: LegacyImportSource.database,
          now: DateTime.utc(2026, 10, 23),
        )
        .bundle;
    expect(bundle.queue, isEmpty);
    expect(bundle.playerState, isNotNull);
    await _writeAndVerify(bundle, temp);
  });
}
