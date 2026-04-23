import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/data/sources/youtube_source.dart';
import 'package:fmp/services/account/netease_account_service.dart';
import 'package:fmp/services/account/youtube_account_service.dart';
import 'package:fmp/services/import/import_service.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImportService phase 4 dispatch', () {
    late Directory tempDir;
    late Isar isar;
    late PlaylistRepository playlistRepository;
    late TrackRepository trackRepository;
    late _FakeSourceManager sourceManager;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'import_service_phase4_',
      );
      isar = await Isar.open(
        [PlaylistSchema, TrackSchema],
        directory: tempDir.path,
        name: 'import_service_phase4_test',
      );
      playlistRepository = PlaylistRepository(isar);
      trackRepository = TrackRepository(isar);
      sourceManager = _FakeSourceManager();
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('importFromUrl routes regular youtube playlist URLs through parser path for YouTubeSource instances',
        () async {
      final source = _FakeYouTubeSource();
      sourceManager.detectedSource = source;
      final service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
      );

      await expectLater(
        () => service.importFromUrl(
          'https://www.youtube.com/playlist?list=PL123',
        ),
        throwsA(isA<_ParseSentinel>()),
      );

      expect(source.parsePlaylistCallCount, 1);
      expect(source.lastParseAuthHeaders, isNull);
    });

    test('importFromUrl passes auth headers to playlist parser when enabled',
        () async {
      final source = _FakeGenericSource(SourceType.youtube);
      sourceManager.detectedSource = source;
      final service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
        youtubeAccountService: _FakeYouTubeAccountService(isar),
      );

      await expectLater(
        () => service.importFromUrl(
          'https://www.youtube.com/playlist?list=PL123',
          useAuth: true,
        ),
        throwsA(isA<_ParseSentinel>()),
      );

      expect(source.lastParseAuthHeaders, {
        'Cookie': 'SAPISID=sapisid; __Secure-1PSID=1psid; __Secure-3PSID=3psid',
        'Authorization': 'Bearer youtube-auth',
      });
    });

    test('importFromUrl leaves auth headers null when auth is disabled',
        () async {
      final source = _FakeGenericSource(SourceType.netease);
      sourceManager.detectedSource = source;
      final service = ImportService(
        sourceManager: sourceManager,
        playlistRepository: playlistRepository,
        trackRepository: trackRepository,
        isar: isar,
        neteaseAccountService: _FakeNeteaseAccountService(isar),
      );

      await expectLater(
        () => service.importFromUrl('https://music.163.com/playlist?id=42'),
        throwsA(isA<_ParseSentinel>()),
      );

      expect(source.lastParseAuthHeaders, isNull);
    });
  });
}

class _FakeSourceManager extends SourceManager {
  _FakeSourceManager() : super();

  BaseSource? detectedSource;

  @override
  BaseSource? detectSource(String url) => detectedSource;

  @override
  BaseSource? getSourceForUrl(String url) => detectedSource;

  @override
  void dispose() {}
}

class _FakeGenericSource extends BaseSource {
  _FakeGenericSource(this._sourceType);

  final SourceType _sourceType;
  Map<String, String>? lastParseAuthHeaders;

  @override
  SourceType get sourceType => _sourceType;

  @override
  Future<bool> checkAvailability(String sourceId) async => true;

  @override
  Future<AudioStreamResult> getAudioStream(String sourceId,
      {AudioStreamConfig config = AudioStreamConfig.defaultConfig,
      Map<String, String>? authHeaders}) => throw UnimplementedError();

  @override
  Future<Track> getTrackInfo(String sourceId,
      {Map<String, String>? authHeaders}) => throw UnimplementedError();

  @override
  bool isPlaylistUrl(String url) => true;

  @override
  bool isValidId(String id) => true;

  @override
  String? parseId(String url) => 'id';

  @override
  Future<PlaylistParseResult> parsePlaylist(String playlistUrl,
      {int page = 1,
      int pageSize = 20,
      Map<String, String>? authHeaders}) async {
    lastParseAuthHeaders = authHeaders;
    throw _ParseSentinel();
  }

  @override
  Future<Track> refreshAudioUrl(Track track,
      {Map<String, String>? authHeaders}) => throw UnimplementedError();

  @override
  Future<SearchResult> search(String query,
      {int page = 1,
      int pageSize = 20,
      SearchOrder order = SearchOrder.relevance}) async {
    return SearchResult.empty();
  }
}

class _FakeYouTubeSource extends YouTubeSource {
  _FakeYouTubeSource();

  int parsePlaylistCallCount = 0;
  Map<String, String>? lastParseAuthHeaders;

  @override
  Future<PlaylistParseResult> parsePlaylist(String playlistUrl,
      {int page = 1,
      int pageSize = 20,
      Map<String, String>? authHeaders}) async {
    parsePlaylistCallCount++;
    lastParseAuthHeaders = authHeaders;
    throw _ParseSentinel();
  }
}

class _FakeYouTubeAccountService extends YouTubeAccountService {
  _FakeYouTubeAccountService(Isar isar) : super(isar: isar);

  @override
  Future<Map<String, String>?> getAuthHeaders() async => {
        'Cookie': 'SAPISID=sapisid; __Secure-1PSID=1psid; __Secure-3PSID=3psid',
        'Authorization': 'Bearer youtube-auth',
      };
}

class _FakeNeteaseAccountService extends NeteaseAccountService {
  _FakeNeteaseAccountService(Isar isar) : super(isar: isar);

  @override
  Future<String?> getAuthCookieString() async => 'MUSIC_U=music-u; __csrf=csrf';
}

class _MixImportSentinel implements Exception {}

class _ParseSentinel implements Exception {}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile =
      File('${Directory.current.path}/.dart_tool/package_config.json');
  final packageConfig = jsonDecode(await packageConfigFile.readAsString())
      as Map<String, dynamic>;
  final packages = packageConfig['packages'] as List<dynamic>;
  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');

  for (final package in packages) {
    if (package is! Map<String, dynamic> ||
        package['name'] != 'isar_flutter_libs') continue;
    final packageDir = Directory(
      packageConfigDir.uri.resolve(package['rootUri'] as String).toFilePath(),
    );
    if (Platform.isWindows) return '${packageDir.path}/windows/isar.dll';
    if (Platform.isLinux) return '${packageDir.path}/linux/libisar.so';
    if (Platform.isMacOS) return '${packageDir.path}/macos/libisar.dylib';
  }

  throw StateError('Unsupported platform for Isar test setup');
}
