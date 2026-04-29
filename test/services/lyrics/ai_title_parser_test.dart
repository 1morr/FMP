import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/lyrics/ai_title_parser.dart';

void main() {
  group('AiTitleParser', () {
    test('sends only minimal metadata, appends path, and sets auth header', () async {
      final dio = Dio();
      RequestOptions? capturedOptions;
      Map<String, dynamic>? capturedBody;
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        capturedOptions = options;
        capturedBody = jsonDecode(requestBody as String) as Map<String, dynamic>;
        return _jsonResponse({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'trackName': 'Song',
                  'artistName': 'Artist',
                  'alternativeTrackNames': <String>[],
                  'alternativeArtistNames': <String>[],
                  'confidence': 0.9,
                }),
              },
            },
          ],
        });
      });

      final result = await AiTitleParser(dio: dio).parse(
        endpoint: ' https://api.example.com/v1/ ',
        apiKey: '  secret-key  ',
        model: 'gpt-test',
        title: 'Song - Artist',
        artist: 'Uploader',
        sourceType: SourceType.youtube,
        durationMs: 123456,
        timeoutSeconds: 7,
      );

      expect(result?.trackName, 'Song');
      expect(capturedOptions?.uri.toString(),
          'https://api.example.com/v1/chat/completions');
      expect(capturedOptions?.headers['Authorization'], 'Bearer secret-key');
      expect(capturedOptions?.headers['Content-Type'], contains('application/json'));
      expect(capturedOptions?.sendTimeout, const Duration(seconds: 7));
      expect(capturedOptions?.receiveTimeout, const Duration(seconds: 7));

      expect(capturedBody?['model'], 'gpt-test');
      expect(capturedBody?['temperature'], 0.1);
      final messages = capturedBody?['messages'] as List<dynamic>;
      final userMessage = messages.singleWhere(
        (message) => (message as Map<String, dynamic>)['role'] == 'user',
      ) as Map<String, dynamic>;
      final metadata = jsonDecode(userMessage['content'] as String) as Map<String, dynamic>;
      expect(metadata.keys, unorderedEquals([
        'title',
        'artist',
        'sourceType',
        'durationSeconds',
      ]));
      expect(metadata, {
        'title': 'Song - Artist',
        'artist': 'Uploader',
        'sourceType': 'youtube',
        'durationSeconds': 123,
      });
    });

    test('strips code-fenced JSON and parses content', () {
      final result = AiTitleParser.parseContent('''```json
{"trackName":"Song","artistName":"Artist","alternativeTrackNames":[],"alternativeArtistNames":[],"confidence":0.8}
```''');

      expect(result?.trackName, 'Song');
      expect(result?.artistName, 'Artist');
      expect(result?.confidence, 0.8);
    });

    test('missing trackName returns null', () {
      final result = AiTitleParser.parseContent(jsonEncode({
        'artistName': 'Artist',
        'alternativeTrackNames': <String>[],
        'alternativeArtistNames': <String>[],
        'confidence': 0.8,
      }));

      expect(result, isNull);
    });

    test('missing artistName returns null', () {
      final result = AiTitleParser.parseContent(jsonEncode({
        'trackName': 'Song',
        'alternativeTrackNames': <String>[],
        'alternativeArtistNames': <String>[],
        'confidence': 0.8,
      }));

      expect(result, isNull);
    });

    test('blank artistName string is accepted as null', () {
      final result = AiTitleParser.parseContent(jsonEncode({
        'trackName': 'Song',
        'artistName': '   ',
        'alternativeTrackNames': <String>[],
        'alternativeArtistNames': <String>[],
        'confidence': 0.8,
      }));

      expect(result?.artistName, isNull);
    });

    test('missing alias arrays return null without throwing', () {
      expect(
        () => AiTitleParser.parseContent(jsonEncode({
          'trackName': 'Song',
          'artistName': 'Artist',
          'confidence': 0.8,
        })),
        returnsNormally,
      );
      expect(
        AiTitleParser.parseContent(jsonEncode({
          'trackName': 'Song',
          'artistName': 'Artist',
          'confidence': 0.8,
        })),
        isNull,
      );
    });

    test('non-list alias arrays return null without throwing', () {
      expect(
        () => AiTitleParser.parseContent(jsonEncode({
          'trackName': 'Song',
          'artistName': 'Artist',
          'alternativeTrackNames': 'Song alias',
          'alternativeArtistNames': <String>[],
          'confidence': 0.8,
        })),
        returnsNormally,
      );
      expect(
        AiTitleParser.parseContent(jsonEncode({
          'trackName': 'Song',
          'artistName': 'Artist',
          'alternativeTrackNames': <String>[],
          'alternativeArtistNames': 'Artist alias',
          'confidence': 0.8,
        })),
        isNull,
      );
    });

    test('confidence below minimum returns null', () {
      final result = AiTitleParser.parseContent(jsonEncode({
        'trackName': 'Song',
        'artistName': 'Artist',
        'alternativeTrackNames': <String>[],
        'alternativeArtistNames': <String>[],
        'confidence': 0.59,
      }));

      expect(result, isNull);
    });

    test('caps alias arrays and discards long aliases', () {
      final longAlias = 'a' * 81;
      final result = AiTitleParser.parseContent(jsonEncode({
        'trackName': 'Song',
        'artistName': 'Artist',
        'alternativeTrackNames': [
          ' One ',
          '',
          longAlias,
          'Two',
          'Three',
          'Four',
          'Five',
          'Six',
        ],
        'alternativeArtistNames': [
          ' Artist One ',
          'Artist Two',
          'Artist Three',
          'Artist Four',
          'Artist Five',
          'Artist Six',
        ],
        'confidence': 0.95,
      }));

      expect(result?.alternativeTrackNames, [
        'One',
        'Two',
        'Three',
        'Four',
        'Five',
      ]);
      expect(result?.alternativeArtistNames, [
        'Artist One',
        'Artist Two',
        'Artist Three',
        'Artist Four',
        'Artist Five',
      ]);
    });

    test('invalid JSON returns null without throwing', () {
      expect(() => AiTitleParser.parseContent('not json'), returnsNormally);
      expect(AiTitleParser.parseContent('not json'), isNull);
    });
  });
}

ResponseBody _jsonResponse(Map<String, dynamic> body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);

  final ResponseBody Function(RequestOptions options, Object? requestBody) _handler;

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
