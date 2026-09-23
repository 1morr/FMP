import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/database/database_provider.dart';
import 'package:fmp/data/database/repository_providers.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/playlist_mutation_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/library/playlist_provider.dart';
import 'package:fmp/services/library/playlist_service.dart';
import 'package:fmp/ui/widgets/dialogs/add_to_playlist_dialog.dart';
import 'package:isar_community/isar.dart';

import '../../../support/isar_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  _Harness? created;

  setUpAll(() async {
    await initializeIsarForTests();
  });

  // 在 testWidgets 的假時鐘區域裡關 Isar 會卡住，所以資料庫留到這裡才收。
  tearDownAll(() async => created?.closeDatabase());

  testWidgets(
    'unticking a playlist removes the tracks in one call and creates none',
    (tester) async {
      final harness = created = (await tester.runAsync(_Harness.create))!;
      addTearDown(harness.container.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      LocaleSettings.setLocale(AppLocale.en);

      bool? result;
      await tester.pumpWidget(
        TranslationProvider(
          child: UncontrolledProviderScope(
            container: harness.container,
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    // 搜尋結果或佇列裡的曲目是還沒存檔的新物件，只靠來源身分
                    // 對應資料庫裡的那一列。
                    onPressed: () async =>
                        result = await showAddToPlaylistDialog(
                          context: context,
                          tracks: [_track('BV1'), _track('BV2')],
                        ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      // 底部面板的進場動畫走假時鐘，`_settle` 的真實等待推不動它。
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await _settle(
        tester,
        () => find.byIcon(Icons.check_circle).evaluate().isNotEmpty,
        reason: 'the playlist that holds both tracks is preselected',
      );
      final lookupsBeforeConfirm = harness.trackRepository.getOrCreateCalls;

      await tester.tap(find.text('Favourites'));
      await tester.pump();
      expect(find.byIcon(Icons.check_circle), findsNothing);
      await tester.tap(find.byIcon(Icons.save));
      await _settle(
        tester,
        () => result != null,
        reason: 'the sheet closes after saving',
      );

      expect(result, isTrue);
      // 存檔會讓歌單列表失效，而面板退場期間還在 watch 它，於是觸發一次重讀。
      // 那筆讀取交易要在這裡跑完，否則之後關資料庫會一直等它。
      await tester.pump(const Duration(seconds: 1));
      await _settle(
        tester,
        () => !harness.container.read(allPlaylistsProvider).isLoading,
        reason: 'the playlist list refresh triggered by the save finishes',
      );
      // 一個歌單一次呼叫，帶齊所有曲目 —— 不是逐首各開一筆交易。
      expect(harness.playlistService.singleRemovals, 0);
      expect(harness.playlistService.batchRemovals, hasLength(1));
      final removal = harness.playlistService.batchRemovals.single;
      expect(removal.$1, harness.playlistId);
      expect(removal.$2, unorderedEquals(harness.trackIds));
      // 移除只查既有的列：走 getOrCreate 的話，資料庫裡不存在的曲目會在
      // 「從歌單移除」時被建出來。
      expect(
        harness.trackRepository.getOrCreateCalls,
        lookupsBeforeConfirm,
        reason: 'confirming a removal must not get-or-create any track',
      );

      final (trackCount, remaining) = (await tester.runAsync(() async {
        final playlist = await harness.isar.playlists.get(harness.playlistId);
        return (await harness.isar.tracks.count(), playlist!.trackIds);
      }))!;
      expect(remaining, isEmpty);
      // 兩首都只屬於這個歌單，移出後成為孤兒、由移除那一筆交易一起清掉。
      expect(trackCount, 0);
    },
  );
}

Track _track(String sourceId) => Track()
  ..sourceType = SourceIds.bilibili
  ..sourceId = sourceId
  ..title = sourceId;

/// Isar 的讀寫是真的 I/O，要在 `runAsync` 裡才走得動；每一輪讓它前進一點再
/// pump 一幀，直到條件成立或逾時。
Future<void> _settle(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump();
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('timed out after $timeout waiting: $reason');
}

class _Harness {
  _Harness._({
    required this.isar,
    required this.tempDir,
    required this.container,
    required this.trackRepository,
    required this.playlistService,
    required this.playlistId,
    required this.trackIds,
  });

  final Isar isar;
  final Directory tempDir;
  final ProviderContainer container;
  final _RecordingTrackRepository trackRepository;
  final _RecordingPlaylistService playlistService;
  final int playlistId;
  final List<int> trackIds;

  static Future<_Harness> create() async {
    final tempDir = await Directory.systemTemp.createTemp(
      'add_to_playlist_dialog_test_',
    );
    final isar = await Isar.open(
      [TrackSchema, PlaylistSchema, SettingsSchema],
      directory: tempDir.path,
      name: 'add_to_playlist_dialog_test',
    );

    final playlist = Playlist()..name = 'Favourites';
    await isar.writeTxn(() => isar.playlists.put(playlist));

    final trackRepository = _RecordingTrackRepository(isar);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) => isar),
        trackRepositoryProvider.overrideWithValue(trackRepository),
        playlistServiceProvider.overrideWith(
          (ref) => _RecordingPlaylistService(
            playlistRepository: ref.watch(playlistRepositoryProvider),
            trackRepository: trackRepository,
            settingsRepository: ref.watch(settingsRepositoryProvider),
            isar: isar,
          ),
        ),
        playlistCoverProvider.overrideWith(
          (ref, playlistId) => const PlaylistCoverData(),
        ),
      ],
    );
    final playlistService =
        container.read(playlistServiceProvider) as _RecordingPlaylistService;
    await playlistService.addTracksToPlaylist(playlist.id, [
      _track('BV1'),
      _track('BV2'),
    ]);
    final saved = await isar.playlists.get(playlist.id);

    return _Harness._(
      isar: isar,
      tempDir: tempDir,
      container: container,
      trackRepository: trackRepository,
      playlistService: playlistService,
      playlistId: playlist.id,
      trackIds: List.of(saved!.trackIds),
    );
  }

  Future<void> closeDatabase() async {
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

class _RecordingTrackRepository extends TrackRepository {
  _RecordingTrackRepository(super.isar);

  int getOrCreateCalls = 0;

  @override
  Future<Track> getOrCreate(Track track) {
    getOrCreateCalls++;
    return super.getOrCreate(track);
  }
}

class _RecordingPlaylistService extends PlaylistService {
  _RecordingPlaylistService({
    required super.playlistRepository,
    required super.trackRepository,
    required super.settingsRepository,
    required super.isar,
  });

  final batchRemovals = <(int, List<int>)>[];
  int singleRemovals = 0;

  @override
  Future<PlaylistMutationResult> removeTracksFromPlaylist(
    int playlistId,
    List<int> trackIds,
  ) {
    batchRemovals.add((playlistId, List.of(trackIds)));
    return super.removeTracksFromPlaylist(playlistId, trackIds);
  }

  @override
  Future<PlaylistMutationResult> removeTrackFromPlaylist(
    int playlistId,
    int trackId,
  ) {
    singleRemovals++;
    return super.removeTrackFromPlaylist(playlistId, trackId);
  }
}
