import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/lyrics/ai_title_parser.dart';

void main() {
  group('AiTitleParser', () {
    test('sends only minimal metadata, appends path, and sets auth header',
        () async {
      final dio = Dio();
      RequestOptions? capturedOptions;
      Map<String, dynamic>? capturedBody;
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        capturedOptions = options;
        capturedBody =
            jsonDecode(requestBody as String) as Map<String, dynamic>;
        return _jsonResponse({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'trackName': 'Song',
                  'artistName': 'Artist',
                  'artistConfidence': 0.9,
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
        timeoutSeconds: 7,
      );

      expect(result?.trackName, 'Song');
      expect(capturedOptions?.uri.toString(),
          'https://api.example.com/v1/chat/completions');
      expect(capturedOptions?.headers['Authorization'], 'Bearer secret-key');
      expect(capturedOptions?.headers['Content-Type'],
          contains('application/json'));
      expect(capturedOptions?.connectTimeout, const Duration(seconds: 7));
      expect(capturedOptions?.sendTimeout, const Duration(seconds: 7));
      expect(capturedOptions?.receiveTimeout, const Duration(seconds: 7));

      expect(capturedBody?['model'], 'gpt-test');
      expect(capturedBody?['temperature'], 0.1);
      final messages = capturedBody?['messages'] as List<dynamic>;
      final userMessage = messages.singleWhere(
        (message) => (message as Map<String, dynamic>)['role'] == 'user',
      ) as Map<String, dynamic>;
      final metadata =
          jsonDecode(userMessage['content'] as String) as Map<String, dynamic>;
      expect(metadata, {'title': 'Song - Artist'});
    });

    test('strips code-fenced JSON and parses content', () {
      final result = AiTitleParser.parseContent('''```json
{"trackName":"Song","artistName":"Artist","artistConfidence":0.8}
```''');

      expect(result?.trackName, 'Song');
      expect(result?.artistName, 'Artist');
      expect(result?.artistConfidence, 0.8);
    });

    test('missing trackName returns null', () {
      final result = AiTitleParser.parseContent(jsonEncode({
        'artistName': 'Artist',
        'artistConfidence': 0.8,
      }));

      expect(result, isNull);
    });

    test('missing artistName returns null', () {
      final result = AiTitleParser.parseContent(jsonEncode({
        'trackName': 'Song',
        'artistConfidence': 0.8,
      }));

      expect(result, isNull);
    });

    test('missing artistConfidence returns null', () {
      final result = AiTitleParser.parseContent(jsonEncode({
        'trackName': 'Song',
        'artistName': 'Artist',
      }));

      expect(result, isNull);
    });

    test('blank artistName string is accepted as null', () {
      final result = AiTitleParser.parseContent(jsonEncode({
        'trackName': 'Song',
        'artistName': '   ',
        'artistConfidence': 0.8,
      }));

      expect(result?.artistName, isNull);
    });

    test('artist confidence below minimum omits artist only', () {
      final result = AiTitleParser.parseContent(jsonEncode({
        'trackName': 'Song',
        'artistName': 'Artist',
        'artistConfidence': 0.79,
      }));

      expect(result?.trackName, 'Song');
      expect(result?.artistName, isNull);
      expect(result?.artistConfidence, 0.79);
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
