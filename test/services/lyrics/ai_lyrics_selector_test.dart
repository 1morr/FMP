import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/lyrics/ai_lyrics_selector.dart';

void main() {
  group('AiLyricsSelector', () {
    test('parses selected candidate JSON', () {
      final result = AiLyricsSelector.parseContent(jsonEncode({
        'selectedCandidateId': 'netease:123',
        'confidence': 0.91,
        'reason': 'good match',
      }));
      expect(result?.selectedCandidateId, 'netease:123');
      expect(result?.confidence, 0.91);
      expect(result?.reason, 'good match');
    });

    test('parses null selection JSON', () {
      final result = AiLyricsSelector.parseContent(jsonEncode({
        'selectedCandidateId': null,
        'confidence': 0.42,
        'reason': 'not reliable',
      }));
      expect(result?.selectedCandidateId, isNull);
      expect(result?.confidence, 0.42);
      expect(result?.reason, 'not reliable');
    });

    test('invalid JSON returns null', () {
      expect(AiLyricsSelector.parseContent('not json'), isNull);
    });

    test('sends enriched candidate selection payload without API key leakage',
        () async {
      final dio = Dio();
      Map<String, dynamic>? capturedBody;
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        capturedBody =
            jsonDecode(requestBody as String) as Map<String, dynamic>;
        return _jsonResponse({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'selectedCandidateId': 'netease:123',
                  'confidence': 0.91,
                  'reason': 'synced and close duration',
                }),
              },
            },
          ],
        });
      });

      final selector = AiLyricsSelector(dio: dio);
      final result = await selector.select(
        endpoint: 'https://api.example.com/v1',
        apiKey: 'secret-key',
        model: 'gpt-test',
        title: 'Video Title',
        uploader: 'Uploader',
        videoDescription:
            '  Official music video\nwith  lyrics in description.  ',
        durationSeconds: 180,
        sourcePriority: const ['netease', 'qqmusic'],
        allowPlainLyricsAutoMatch: false,
        candidates: const [
          AiLyricsCandidate(
            candidateId: 'netease:123',
            source: 'netease',
            sourcePriorityRank: 0,
            trackName: 'Song',
            artistName: 'Artist',
            albumName: 'Album',
            durationSeconds: 181,
            videoDurationSeconds: 180,
            durationDiffSeconds: 1,
            hasSyncedLyrics: true,
            hasPlainLyrics: true,
            hasTranslatedLyrics: false,
            hasRomajiLyrics: false,
            lyricsPreview: 'first line\nchorus line',
          ),
        ],
        timeoutSeconds: 5,
      );

      expect(result?.selectedCandidateId, 'netease:123');
      expect(capturedBody?['model'], 'gpt-test');
      final messages = capturedBody?['messages'] as List<dynamic>;
      final userMessage = messages.firstWhere(
        (message) => (message as Map<String, dynamic>)['role'] == 'user',
      ) as Map<String, dynamic>;
      final userPayload =
          jsonDecode(userMessage['content'] as String) as Map<String, dynamic>;
      expect(
        userPayload['videoDescription'],
        'Official music video with lyrics in description.',
      );
      final candidates = userPayload['candidates'] as List<dynamic>;
      final candidate = candidates.single as Map<String, dynamic>;
      expect(candidate['lyricsPreview'], 'first line\nchorus line');
      final bodyText = jsonEncode(capturedBody);
      expect(bodyText, contains('Video Title'));
      expect(bodyText, contains('Uploader'));
      expect(bodyText, contains('netease:123'));
      expect(bodyText, isNot(contains('secret-key')));
    });

    test('does not append chat completions path twice', () async {
      final dio = Dio();
      RequestOptions? capturedOptions;
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        capturedOptions = options;
        return _jsonResponse({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'selectedCandidateId': null,
                  'confidence': 0.1,
                  'reason': 'no reliable match',
                }),
              },
            },
          ],
        });
      });

      await AiLyricsSelector(dio: dio).select(
        endpoint: ' https://api.example.com/v1/chat/completions/ ',
        apiKey: 'secret-key',
        model: 'gpt-test',
        title: 'Video Title',
        durationSeconds: 180,
        sourcePriority: const ['netease'],
        allowPlainLyricsAutoMatch: false,
        candidates: const [],
        timeoutSeconds: 5,
      );

      expect(capturedOptions?.uri.toString(),
          'https://api.example.com/v1/chat/completions');
    });

    test('blank endpoint skips request as incomplete configuration', () async {
      final dio = Dio();
      var requestSent = false;
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        requestSent = true;
        return _jsonResponse({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'selectedCandidateId': 'netease:123',
                  'confidence': 0.9,
                  'reason': 'should not be used',
                }),
              },
            },
          ],
        });
      });

      final result = await AiLyricsSelector(dio: dio).select(
        endpoint: '   ',
        apiKey: 'secret-key',
        model: 'gpt-test',
        title: 'Video Title',
        durationSeconds: 180,
        sourcePriority: const ['netease'],
        allowPlainLyricsAutoMatch: false,
        candidates: const [],
        timeoutSeconds: 5,
      );

      expect(result, isNull);
      expect(requestSent, isFalse);
    });

    test('omits blank video description and preserves empty lyrics preview',
        () async {
      final dio = Dio();
      Map<String, dynamic>? capturedBody;
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        capturedBody =
            jsonDecode(requestBody as String) as Map<String, dynamic>;
        return _jsonResponse({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'selectedCandidateId': null,
                  'confidence': 0.1,
                  'reason': 'no reliable match',
                }),
              },
            },
          ],
        });
      });

      await AiLyricsSelector(dio: dio).select(
        endpoint: 'https://api.example.com/v1',
        apiKey: 'secret-key',
        model: 'gpt-test',
        title: 'Video Title',
        uploader: 'Uploader',
        videoDescription: '  \n\t  ',
        durationSeconds: 180,
        sourcePriority: const ['netease'],
        allowPlainLyricsAutoMatch: false,
        candidates: const [
          AiLyricsCandidate(
            candidateId: 'netease:123',
            source: 'netease',
            sourcePriorityRank: 0,
            trackName: 'Song',
            artistName: 'Artist',
            albumName: 'Album',
            durationSeconds: 181,
            videoDurationSeconds: 180,
            durationDiffSeconds: 1,
            hasSyncedLyrics: true,
            hasPlainLyrics: true,
            hasTranslatedLyrics: false,
            hasRomajiLyrics: false,
            lyricsPreview: '',
          ),
        ],
        timeoutSeconds: 5,
      );

      final messages = capturedBody?['messages'] as List<dynamic>;
      final userMessage = messages.firstWhere(
        (message) => (message as Map<String, dynamic>)['role'] == 'user',
      ) as Map<String, dynamic>;
      final userPayload =
          jsonDecode(userMessage['content'] as String) as Map<String, dynamic>;
      expect(userPayload.containsKey('videoDescription'), isFalse);
      final candidates = userPayload['candidates'] as List<dynamic>;
      final candidate = candidates.single as Map<String, dynamic>;
      expect(candidate['lyricsPreview'], '');
    });

    test('caps video description to 500 characters', () async {
      final dio = Dio();
      Map<String, dynamic>? capturedBody;
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        capturedBody =
            jsonDecode(requestBody as String) as Map<String, dynamic>;
        return _jsonResponse({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'selectedCandidateId': null,
                  'confidence': 0.1,
                  'reason': 'no reliable match',
                }),
              },
            },
          ],
        });
      });

      await AiLyricsSelector(dio: dio).select(
        endpoint: 'https://api.example.com/v1',
        apiKey: 'secret-key',
        model: 'gpt-test',
        title: 'Video Title',
        uploader: 'Uploader',
        videoDescription: List.filled(520, 'a').join(),
        durationSeconds: 180,
        sourcePriority: const ['netease'],
        allowPlainLyricsAutoMatch: false,
        candidates: const [
          AiLyricsCandidate(
            candidateId: 'netease:123',
            source: 'netease',
            sourcePriorityRank: 0,
            trackName: 'Song',
            artistName: 'Artist',
            albumName: 'Album',
            durationSeconds: 181,
            videoDurationSeconds: 180,
            durationDiffSeconds: 1,
            hasSyncedLyrics: true,
            hasPlainLyrics: true,
            hasTranslatedLyrics: false,
            hasRomajiLyrics: false,
            lyricsPreview: 'preview',
          ),
        ],
        timeoutSeconds: 5,
      );

      final messages = capturedBody?['messages'] as List<dynamic>;
      final userMessage = messages.firstWhere(
        (message) => (message as Map<String, dynamic>)['role'] == 'user',
      ) as Map<String, dynamic>;
      final userPayload =
          jsonDecode(userMessage['content'] as String) as Map<String, dynamic>;
      expect(userPayload['videoDescription'], List.filled(500, 'a').join());
    });

    test('prompt asks AI to pick closest acceptable candidate', () async {
      final dio = Dio();
      Map<String, dynamic>? capturedBody;
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        capturedBody =
            jsonDecode(requestBody as String) as Map<String, dynamic>;
        return _jsonResponse({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'selectedCandidateId': 'lrclib:50332',
                  'confidence': 0.45,
                  'reason': 'closest available version',
                }),
              },
            },
          ],
        });
      });

      await AiLyricsSelector(dio: dio).select(
        endpoint: 'https://api.example.com/v1',
        apiKey: 'secret-key',
        model: 'gpt-test',
        title: 'Lady Gaga - Poker Face (Official Music Video)',
        uploader: 'Lady Gaga',
        durationSeconds: 214,
        sourcePriority: const ['netease', 'qqmusic', 'lrclib'],
        allowPlainLyricsAutoMatch: true,
        candidates: const [
          AiLyricsCandidate(
            candidateId: 'lrclib:50332',
            source: 'lrclib',
            sourcePriorityRank: 2,
            trackName: 'Poker Face (Piano & Voice Version) [Live]',
            artistName: 'Lady Gaga',
            albumName: 'The Cherrytree Sessions (Live)',
            durationSeconds: 218,
            videoDurationSeconds: 214,
            durationDiffSeconds: 4,
            hasSyncedLyrics: true,
            hasPlainLyrics: true,
            hasTranslatedLyrics: false,
            hasRomajiLyrics: false,
            lyricsPreview: 'poker face chorus preview',
          ),
        ],
        timeoutSeconds: 5,
      );

      final messages = capturedBody?['messages'] as List<dynamic>;
      final systemMessage = messages.firstWhere(
        (message) => (message as Map<String, dynamic>)['role'] == 'system',
      ) as Map<String, dynamic>;
      final prompt = systemMessage['content'] as String;
      expect(prompt, contains('Always choose'));
      expect(prompt, contains('closest acceptable'));
      expect(prompt, contains('cover'));
      expect(prompt, contains('remix'));
      expect(prompt, contains('completely different song'));
      expect(prompt, contains('videoDescription'));
      expect(prompt, contains('lyricsPreview'));
      expect(prompt, contains('compare candidate content'));
    });
  });
}

ResponseBody _jsonResponse(Map<String, dynamic> body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json']
    },
  );
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);
  final ResponseBody Function(RequestOptions options, Object? requestBody)
      _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final requestBody = requestStream == null
        ? null
        : utf8.decode(await requestStream.expand((chunk) => chunk).toList());
    return _handler(options, requestBody);
  }

  @override
  void close({bool force = false}) {}
}
