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

    test('sends candidate selection payload without API key leakage', () async {
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
          ),
        ],
        timeoutSeconds: 5,
      );

      expect(result?.selectedCandidateId, 'netease:123');
      expect(capturedBody?['model'], 'gpt-test');
      final bodyText = jsonEncode(capturedBody);
      expect(bodyText, contains('Video Title'));
      expect(bodyText, contains('Uploader'));
      expect(bodyText, contains('netease:123'));
      expect(bodyText, isNot(contains('secret-key')));
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
