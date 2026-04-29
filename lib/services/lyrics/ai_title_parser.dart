import 'dart:convert';

import 'package:dio/dio.dart';

class AiParsedTitle {
  const AiParsedTitle({
    required this.trackName,
    required this.artistName,
    required this.artistConfidence,
  });

  final String trackName;
  final String? artistName;
  final double artistConfidence;
}

class AiTitleParser {
  AiTitleParser({Dio? dio}) : _dio = dio ?? Dio();

  static const double minArtistConfidence = 0.8;

  final Dio _dio;

  Future<AiParsedTitle?> parse({
    required String endpoint,
    required String apiKey,
    required String model,
    required String title,
    required int timeoutSeconds,
  }) async {
    final trimmedEndpoint = endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    final trimmedApiKey = apiKey.trim();
    final trimmedModel = model.trim();
    if (trimmedEndpoint.isEmpty ||
        trimmedApiKey.isEmpty ||
        trimmedModel.isEmpty) {
      return null;
    }

    final timeout = Duration(seconds: timeoutSeconds < 1 ? 10 : timeoutSeconds);

    try {
      final response = await _dio.post<dynamic>(
        '$trimmedEndpoint/chat/completions',
        options: Options(
          headers: {
            Headers.contentTypeHeader: Headers.jsonContentType,
            'Authorization': 'Bearer $trimmedApiKey',
          },
          connectTimeout: timeout,
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
        data: {
          'model': trimmedModel,
          'temperature': 0.1,
          'messages': [
            {
              'role': 'system',
              'content':
                  'Extract the likely music track title and artist from the provided video title. Respond with strict JSON only using exactly these fields: trackName, artistName, artistConfidence.',
            },
            {
              'role': 'user',
              'content': jsonEncode({'title': title}),
            },
          ],
        },
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return null;
      }
      final choices = data['choices'];
      if (choices is! List || choices.isEmpty) {
        return null;
      }
      final firstChoice = choices.first;
      if (firstChoice is! Map<String, dynamic>) {
        return null;
      }
      final message = firstChoice['message'];
      if (message is! Map<String, dynamic>) {
        return null;
      }
      final content = message['content'];
      if (content is! String) {
        return null;
      }
      return parseContent(content);
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static AiParsedTitle? parseContent(String content) {
    try {
      final decoded = jsonDecode(_stripCodeFence(content));
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final trackNameValue = decoded['trackName'];
      final artistNameValue = decoded['artistName'];
      final artistConfidenceValue = decoded['artistConfidence'];

      if (trackNameValue is! String ||
          artistNameValue is! String ||
          artistConfidenceValue is! num) {
        return null;
      }

      final trackName = trackNameValue.trim();
      if (trackName.isEmpty) {
        return null;
      }

      final artistName = artistNameValue.trim();
      final artistConfidence = artistConfidenceValue.toDouble();
      return AiParsedTitle(
        trackName: trackName,
        artistName:
            artistName.isNotEmpty && artistConfidence >= minArtistConfidence
                ? artistName
                : null,
        artistConfidence: artistConfidence,
      );
    } catch (_) {
      return null;
    }
  }

  static String _stripCodeFence(String content) {
    final trimmed = content.trim();
    final match =
        RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$', caseSensitive: false)
            .firstMatch(trimmed);
    return match?.group(1)?.trim() ?? trimmed;
  }
}
