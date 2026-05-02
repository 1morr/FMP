import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/models/account.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/providers/database_provider.dart';
import 'package:fmp/providers/refresh_provider.dart';
import 'package:fmp/services/import/import_service.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RefreshManagerNotifier stale cleanup', () {
    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    test('older delayed cleanup does not remove newer refresh state', () async {
      final harness = await _RefreshHarness.create();
      addTearDown(harness.dispose);

      final playlist = Playlist()
        ..name = 'Refreshable Playlist'
        ..sourceUrl = 'https://example.com/playlist'
        ..importSourceType = SourceType.youtube;
      playlist.id = await harness.isar.writeTxn(
        () => harness.isar.playlists.put(playlist),
      );

      final notifier = harness.container.read(refreshManagerProvider.notifier);

      final firstParse = harness.source.enqueueParse();
      final firstFuture = notifier.refreshPlaylist(playlist);
      await _pumpUntil(
        () => harness.source.parseCalls == 1,
        reason: 'first refresh should reach playlist parsing',
      );

      firstParse.complete(_parseResult('first-refresh-track'));
      await firstFuture;
      expect(
        harness.container
            .read(refreshManagerProvider)
            .getRefreshState(playlist.id)
            ?.status,
        ImportStatus.completed,
      );

      final secondParse = harness.source.enqueueParse();
      final secondFuture = notifier.refreshPlaylist(playlist);
      await _pumpUntil(
        () => harness.source.parseCalls == 2,
        reason: 'second refresh should start before old cleanup fires',
      );
      expect(
        harness.container
            .read(refreshManagerProvider)
            .getRefreshState(playlist.id)
            ?.isRefreshing,
        isTrue,
      );

      await Future<void>.delayed(const Duration(milliseconds: 3200));

      try {
        final state = harness.container
            .read(refreshManagerProvider)
            .getRefreshState(playlist.id);
        expect(state, isNotNull);
        expect(state!.isRefreshing, isTrue);
      } finally {
        final state = harness.container
            .read(refreshManagerProvider)
            .getRefreshState(playlist.id);
        if (state != null && !secondParse.isCompleted) {
          secondParse.complete(_parseResult('second-refresh-track'));
          await secondFuture.timeout(const Duration(seconds: 2));
        }
      }
    });
  });
}

class _RefreshHarness {
  _RefreshHarness({
    required this.container,
    required this.isar,
    required this.tempDir,
    required this.source,
    required this.sourceManager,
  });

  final ProviderContainer container;
  final Isar isar;
  final Directory tempDir;
  final _ControllableRefreshSource source;
  final _RefreshSourceManager sourceManager;

  static Future<_RefreshHarness> create() async {
    final tempDir = await Directory.systemTemp.createTemp(
      'refresh_provider_stale_cleanup_',
    );
    final isar = await Isar.open(
      [TrackSchema, PlaylistSchema, SettingsSchema, AccountSchema],
      directory: tempDir.path,
      name: 'refresh_provider_stale_cleanup_test',
    );
    final source = _ControllableRefreshSource();
    final sourceManager = _RefreshSourceManager(source);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) => isar),
        sourceManagerProvider.overrideWithValue(sourceManager),
        toastServiceProvider.overrideWithValue(ToastService()),
      ],
    );

    return _RefreshHarness(
      container: container,
      isar: isar,
      tempDir: tempDir,
      source: source,
      sourceManager: sourceManager,
    );
  }

  Future<void> dispose() async {
    container.dispose();
    sourceManager.dispose();
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

class _RefreshSourceManager extends SourceManager {
  _RefreshSourceManager(this.source) : super();

  final _ControllableRefreshSource source;

  @override
  BaseSource? detectSource(String url) => source;

  @override
  BaseSource? getSource(SourceType type) =>
      type == SourceType.youtube ? source : null;
}

class _ControllableRefreshSource extends BaseSource {
  final Queue<Completer<PlaylistParseResult>> _parseCompleters = Queue();
  int parseCalls = 0;

  Completer<PlaylistParseResult> enqueueParse() {
    final completer = Completer<PlaylistParseResult>();
    _parseCompleters.add(completer);
    return completer;
  }

  @override
  SourceType get sourceType => SourceType.youtube;

  @override
  Future<PlaylistParseResult> parsePlaylist(
    String playlistUrl, {
    int page = 1,
    int pageSize = 20,
    Map<String, String>? authHeaders,
  }) {
    parseCalls++;
    return _parseCompleters.removeFirst().future;
  }

  @override
  bool isPlaylistUrl(String url) => true;

  @override
  String? parseId(String url) => url;

  @override
  bool isValidId(String id) => true;

  @override
  Future<bool> checkAvailability(String sourceId) async => true;

  @override
  Future<AudioStreamResult> getAudioStream(
    String sourceId, {
    AudioStreamConfig config = AudioStreamConfig.defaultConfig,
    Map<String, String>? authHeaders,
  }) async {
    return AudioStreamResult(
      url: 'https://example.com/$sourceId.m4a',
      streamType: StreamType.audioOnly,
    );
  }

  @override
  Future<Track> getTrackInfo(String sourceId,
      {Map<String, String>? authHeaders}) async {
    return _track(sourceId);
  }

  @override
  Future<Track> refreshAudioUrl(Track track,
      {Map<String, String>? authHeaders}) async {
    return track;
  }

  @override
  Future<SearchResult> search(
    String query, {
    int page = 1,
    int pageSize = 20,
    SearchOrder order = SearchOrder.relevance,
  }) async {
    return SearchResult.empty();
  }
}

PlaylistParseResult _parseResult(String sourceId) {
  return PlaylistParseResult(
    title: 'Refresh Test Playlist',
    tracks: [_track(sourceId)],
    totalCount: 1,
    sourceUrl: 'https://example.com/playlist',
  );
}

Track _track(String sourceId) {
  return Track()
    ..sourceId = sourceId
    ..sourceType = SourceType.youtube
    ..title = 'Track $sourceId'
    ..artist = 'Refresh Tester';
}

Future<void> _pumpUntil(
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  if (!condition()) fail(reason);
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile = File(
    '${Directory.current.path}/.dart_tool/package_config.json',
  );
  final packageConfig = jsonDecode(await packageConfigFile.readAsString())
      as Map<String, dynamic>;
  final packages = packageConfig['packages'] as List<dynamic>;
  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');

  for (final package in packages) {
    if (package is! Map<String, dynamic> ||
        package['name'] != 'isar_flutter_libs') {
      continue;
    }
    final packageDir = Directory(
      packageConfigDir.uri.resolve(package['rootUri'] as String).toFilePath(),
    );
    if (Platform.isWindows) return '${packageDir.path}/windows/isar.dll';
    if (Platform.isLinux) return '${packageDir.path}/linux/libisar.so';
    if (Platform.isMacOS) return '${packageDir.path}/macos/libisar.dylib';
  }

  throw StateError('Unsupported platform for Isar test setup');
}
