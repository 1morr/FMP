import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/audio_stream_quality_fallback.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_exception.dart';

void main() {
  group('audio stream quality fallback', () {
    test('primary fallback preserves track identity and auth headers',
        () async {
      final source = _RecordingSource()
        ..failQualities.add(AudioQualityLevel.high);
      final request = AudioStreamRequest(
        sourceId: 'BVmulti',
        cid: 24680,
        pageNum: 2,
        config: const AudioStreamConfig(
          qualityLevel: AudioQualityLevel.high,
        ),
        authHeaders: const {'Cookie': 'SESSDATA=token'},
      );

      final result = await fetchAudioStreamWithQualityFallback(
        source: source,
        request: request,
      );

      expect(result.url, 'https://example.com/BVmulti-medium.m4a');
      expect(source.primaryRequests.map((r) => r.config.qualityLevel), [
        AudioQualityLevel.high,
        AudioQualityLevel.medium,
      ]);
      expect(
          source.primaryRequests.every((r) => r.sourceId == 'BVmulti'), isTrue);
      expect(source.primaryRequests.every((r) => r.cid == 24680), isTrue);
      expect(source.primaryRequests.every((r) => r.pageNum == 2), isTrue);
      expect(
        source.primaryRequests.every(
          (r) => r.authHeaders?['Cookie'] == 'SESSDATA=token',
        ),
        isTrue,
      );
    });

    test('alternative fallback preserves failedUrl and identity', () async {
      final source = _RecordingSource()..returnNullAlternativeForHigh = true;
      final request = AudioStreamRequest(
        sourceId: 'BVmulti',
        cid: 13579,
        pageNum: 3,
        failedUrl: 'https://failed.example/audio.m4a',
        config: const AudioStreamConfig(
          qualityLevel: AudioQualityLevel.high,
        ),
        authHeaders: const {'Cookie': 'SESSDATA=token'},
      );

      final result = await fetchAlternativeAudioStreamWithQualityFallback(
        source: source,
        request: request,
      );

      expect(result?.url, 'https://example.com/BVmulti-medium-alt.m4a');
      expect(source.alternativeRequests.map((r) => r.config.qualityLevel), [
        AudioQualityLevel.medium,
      ]);
      expect(source.alternativeRequests.single.failedUrl, request.failedUrl);
      expect(source.alternativeRequests.single.cid, 13579);
      expect(source.alternativeRequests.single.pageNum, 3);
      expect(
        source.alternativeRequests.single.authHeaders?['Cookie'],
        'SESSDATA=token',
      );
    });

    test('non-fallbackable source errors are rethrown', () async {
      final source = _RecordingSource()
        ..failQualities.add(AudioQualityLevel.high)
        ..failingKind = SourceErrorKind.network;
      final request = AudioStreamRequest(
        sourceId: 'network-failure',
        config: const AudioStreamConfig(
          qualityLevel: AudioQualityLevel.high,
        ),
      );

      await expectLater(
        fetchAudioStreamWithQualityFallback(
          source: source,
          request: request,
        ),
        throwsA(isA<_FakeSourceException>()),
      );

      expect(source.primaryRequests.map((r) => r.config.qualityLevel), [
        AudioQualityLevel.high,
      ]);
    });
  });
}

class _RecordingSource extends BaseSource {
  final primaryRequests = <AudioStreamRequest>[];
  final alternativeRequests = <AudioStreamRequest>[];
  final failQualities = <AudioQualityLevel>{};
  var failingKind = SourceErrorKind.unavailable;
  var returnNullAlternativeForHigh = false;

  @override
  SourceType get sourceType => SourceType.bilibili;

  @override
  String? parseId(String url) => url;

  @override
  bool isValidId(String id) => id.isNotEmpty;

  @override
  Future<Track> getTrackInfo(
    String sourceId, {
    Map<String, String>? authHeaders,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
    primaryRequests.add(request);
    if (failQualities.contains(request.config.qualityLevel)) {
      throw _FakeSourceException(failingKind);
    }
    return AudioStreamResult(
      url:
          'https://example.com/${request.sourceId}-${request.config.qualityLevel.name}.m4a',
      streamType: StreamType.audioOnly,
    );
  }

  @override
  Future<AudioStreamResult?> getAlternativeAudioStream(
    AudioStreamRequest request,
  ) async {
    if (request.config.qualityLevel == AudioQualityLevel.high &&
        returnNullAlternativeForHigh) {
      return null;
    }
    alternativeRequests.add(request);
    return AudioStreamResult(
      url:
          'https://example.com/${request.sourceId}-${request.config.qualityLevel.name}-alt.m4a',
      streamType: StreamType.audioOnly,
    );
  }

  @override
  Future<Track> refreshAudioUrl(
    Track track, {
    Map<String, String>? authHeaders,
  }) async {
    throw UnimplementedError();
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

  @override
  Future<PlaylistParseResult> parsePlaylist(
    String playlistUrl, {
    int page = 1,
    int pageSize = 20,
    Map<String, String>? authHeaders,
  }) async {
    throw UnimplementedError();
  }

  @override
  bool isPlaylistUrl(String url) => false;

  @override
  Future<bool> checkAvailability(String sourceId) async => true;
}

class _FakeSourceException extends SourceApiException {
  final SourceErrorKind _kind;

  const _FakeSourceException(this._kind);

  @override
  String get code => 'fake';

  @override
  SourceErrorKind get kind => _kind;

  @override
  String get message => 'fake failure';

  @override
  SourceType get sourceType => SourceType.bilibili;
}
