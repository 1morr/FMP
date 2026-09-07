import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/lyrics_match.dart';
import 'package:fmp/data/repositories/lyrics_repository.dart';
import 'package:fmp/providers/audio/audio_settings_provider.dart';
import 'package:fmp/providers/database/repository_providers.dart';
import 'package:fmp/providers/lyrics/lyrics_provider.dart';
import 'package:fmp/services/lyrics/lrclib_source.dart';
import 'package:fmp/services/lyrics/lyrics_cache_service.dart';
import 'package:fmp/services/lyrics/lyrics_result.dart';
import 'package:fmp/services/lyrics/netease_source.dart';
import 'package:fmp/services/lyrics/qqmusic_source.dart';
import 'package:isar_community/isar.dart';
import '../support/isar_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LyricsSearchNotifier', () {
    late Directory tempDir;
    late Isar isar;

    setUpAll(() async {
      await initializeIsarForTests();
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'lyrics_search_notifier_',
      );
      isar = await Isar.open(
        [LyricsMatchSchema],
        directory: tempDir.path,
        name: 'lyrics_search_notifier_test',
      );
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('single-source filters do not query disabled lyrics sources',
        () async {
      final netease = _FakeNeteaseSource()
        ..results = [_lyricsResult(id: 'netease-1', source: 'netease')];
      final notifier = _notifier(
        netease: netease,
        repo: LyricsRepository(isar),
        disabledSources: const {'netease'},
      );

      notifier.setFilter(LyricsSourceFilter.netease);
      await notifier.search(query: 'Song Name');

      expect(netease.searchCalls, isEmpty);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.results, isEmpty);
      expect(notifier.state.error, isNull);
    });
  });
}

LyricsResult _lyricsResult({
  required String id,
  required String source,
}) {
  return LyricsResult(
    id: id,
    trackName: 'Song Name',
    artistName: 'Singer',
    albumName: 'Album',
    duration: 180,
    instrumental: false,
    syncedLyrics: '[00:01.00]line',
    source: source,
  );
}

class _FakeNeteaseSource extends NeteaseSource {
  final List<String> searchCalls = [];
  List<LyricsResult> results = [];

  @override
  Future<List<LyricsResult>> searchLyrics({
    String? query,
    String? trackName,
    String? artistName,
    int limit = 10,
  }) async {
    searchCalls
        .add(query ?? [trackName, artistName].whereType<String>().join(' '));
    return results;
  }
}

class _FakeQQMusicSource extends QQMusicSource {
  @override
  Future<List<LyricsResult>> searchLyrics({
    String? query,
    String? trackName,
    String? artistName,
    int limit = 10,
  }) async {
    return [];
  }
}

class _FakeLrclibSource extends LrclibSource {
  @override
  Future<List<LyricsResult>> search({
    String? q,
    String? trackName,
    String? artistName,
  }) async {
    return [];
  }
}

/// `LyricsSearchNotifier` 以前吃五個位置參數 ＋ 兩個具名參數；`Notifier.new`
/// 不吃參數，所以全部改由 container 注入。來源順序與停用清單本來就來自
/// `audioSettingsProvider`，這裡用一個回傳固定狀態的子類蓋掉它。
LyricsSearchNotifier _notifier({
  required NeteaseSource netease,
  required LyricsRepository repo,
  Set<String> disabledSources = const {},
}) {
  final container = ProviderContainer(overrides: [
    lrclibSourceProvider.overrideWith((ref) => _FakeLrclibSource()),
    neteaseSourceProvider.overrideWith((ref) => netease),
    qqmusicSourceProvider.overrideWith((ref) => _FakeQQMusicSource()),
    lyricsRepositoryProvider.overrideWith((ref) => repo),
    lyricsCacheServiceProvider.overrideWith((ref) => LyricsCacheService()),
    audioSettingsProvider
        .overrideWith(() => _FixedAudioSettings(disabledSources)),
  ]);
  addTearDown(container.dispose);
  return container.read(lyricsSearchProvider.notifier);
}

class _FixedAudioSettings extends AudioSettingsNotifier {
  _FixedAudioSettings(this._disabled);

  final Set<String> _disabled;

  @override
  AudioSettingsState build() =>
      AudioSettingsState(disabledLyricsSources: _disabled);
}
