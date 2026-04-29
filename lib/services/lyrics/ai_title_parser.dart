import 'dart:convert';

import 'package:dio/dio.dart';

import '../../data/models/track.dart';

class AiParsedTitle {
  const AiParsedTitle({
    required this.trackName,
    required this.artistName,
    required this.alternativeTrackNames,
    required this.alternativeArtistNames,
    required this.confidence,
  });

  final String trackName;
  final String? artistName;
  final List<String> alternativeTrackNames;
  final List<String> alternativeArtistNames;
  final double confidence;
}

class AiTitleParser {
  AiTitleParser({Dio? dio}) : _dio = dio ?? Dio();

  static const double minConfidence = 0.6;
  static const int maxAliases = 5;
  static const int maxAliasLength = 80;

  final Dio _dio;

  Future<AiParsedTitle?> parse({
    required String endpoint,
    required String apiKey,
    required String model,
    required String title,
    required String artist,
    required SourceType sourceType,
    required int? durationMs,
    required int timeoutSeconds,
  }) async {
    final trimmedEndpoint = endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    final trimmedApiKey = apiKey.trim();
    final trimmedModel = model.trim();
    if (trimmedEndpoint.isEmpty || trimmedApiKey.isEmpty || trimmedModel.isEmpty) {
      return null;
    }

    final timeout = Duration(seconds: timeoutSeconds < 1 ? 10 : timeoutSeconds);
    final durationSeconds = durationMs == null ? null : (durationMs / 1000).round();

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
              'content': 'Extract the likely music track title and artist from the provided minimal metadata. Respond with strict JSON only using exactly these fields: trackName, artistName, alternativeTrackNames, alternativeArtistNames, confidence.',
            },
            {
              'role': 'user',
              'content': jsonEncode({
                'title': title,
                'artist': artist,
                'sourceType': sourceType.name,
                'durationSeconds': durationSeconds,
              }),
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
      final alternativeTrackNamesValue = decoded['alternativeTrackNames'];
      final alternativeArtistNamesValue = decoded['alternativeArtistNames'];
      final confidenceValue = decoded['confidence'];

      if (trackNameValue is! String ||
          artistNameValue is! String ||
          alternativeTrackNamesValue is! List ||
          alternativeArtistNamesValue is! List ||
          confidenceValue is! num) {
        return null;
      }

      final trackName = trackNameValue.trim();
      if (trackName.isEmpty) {
        return null;
      }

      final confidence = confidenceValue.toDouble();
      if (confidence < minConfidence) {
        return null;
      }

      final artistName = artistNameValue.trim();
      return AiParsedTitle(
        trackName: trackName,
        artistName: artistName.isEmpty ? null : artistName,
        alternativeTrackNames: _parseAliases(alternativeTrackNamesValue),
        alternativeArtistNames: _parseAliases(alternativeArtistNamesValue),
        confidence: confidence,
      );
    } catch (_) {
      return null;
    }
  }

  static String _stripCodeFence(String content) {
    final trimmed = content.trim();
    final match = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$', caseSensitive: false)
        .firstMatch(trimmed);
    return match?.group(1)?.trim() ?? trimmed;
  }

  static List<String> _parseAliases(Object? value) {
    if (value is! List) {
      return const [];
    }

    final aliases = <String>[];
    for (final alias in value) {
      if (alias is! String) {
        continue;
      }
      final trimmed = alias.trim();
      if (trimmed.isEmpty || trimmed.length > maxAliasLength) {
        continue;
      }
      aliases.add(trimmed);
      if (aliases.length == maxAliases) {
        break;
      }
    }
    return aliases;
  }
}
