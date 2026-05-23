import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/logger.dart';
import 'openai_chat_client.dart';

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

class AiTitleParser with Logging {
  AiTitleParser({Dio? dio}) : _dio = dio ?? Dio();

  static const double minArtistConfidence = 0.8;

  final Dio _dio;

  Future<AiParsedTitle?> parse({
    required String endpoint,
    required String apiKey,
    required String model,
    required String title,
    String? uploader,
    required int timeoutSeconds,
  }) async {
    final config = resolveOpenAiChatConfig(
      endpoint: endpoint,
      apiKey: apiKey,
      model: model,
      timeoutSeconds: timeoutSeconds,
    );
    final trimmedUploader = uploader?.trim();
    if (!config.isComplete) {
      return null;
    }

    final userPayload = {
      'title': title,
      if (trimmedUploader != null && trimmedUploader.isNotEmpty)
        'uploader': trimmedUploader,
    };

    try {
      logInfo('Calling AI title parser: $title');
      logDebug(
          'AI title parser config: endpoint=${config.endpoint}, model=${config.model}, timeoutSeconds=${config.timeout.inSeconds}');
      logDebug('AI title parser request payload: ${jsonEncode(userPayload)}');
      final response = await postOpenAiChatCompletion(
        dio: _dio,
        config: config,
        systemPrompt:
            'Extract the likely music track title and artist from the provided video title and optional uploader context. The uploader is the video/content uploader and is not necessarily the song artist or performer. Use uploader only as context; do not copy it into artistName unless the title or context strongly indicates it is the actual music artist. Respond with strict JSON only using exactly these fields: trackName, artistName, artistConfidence.',
        userPayload: jsonEncode(userPayload),
      );

      final content = extractOpenAiChatMessageContent(response.data);
      if (content == null) {
        logWarning(
            'AI title parser response has no content for title "$title"');
        return null;
      }
      logDebug('AI title parser raw response content: $content');
      final parsed = parseContent(content);
      logDebug(
          'AI title parser parsed result: track=${parsed?.trackName}, artist=${parsed?.artistName}, artistConfidence=${parsed?.artistConfidence}');
      if (parsed == null) {
        logWarning(
            'AI title parser returned invalid content for title "$title"');
      }
      return parsed;
    } on DioException catch (e) {
      logWarning(
          'AI title parser request failed for title "$title": ${e.message ?? e.error ?? e.type}');
      return null;
    } catch (e) {
      logWarning('AI title parser failed for title "$title": $e');
      return null;
    }
  }

  static AiParsedTitle? parseContent(String content) {
    try {
      final decoded = jsonDecode(stripJsonCodeFence(content));
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final trackNameValue = decoded['trackName'];
      final artistNameValue = decoded['artistName'];
      final artistConfidenceValue = decoded['artistConfidence'];

      if (trackNameValue is! String) {
        return null;
      }

      final trackName = trackNameValue.trim();
      if (trackName.isEmpty) {
        return null;
      }

      final artistName =
          artistNameValue is String ? artistNameValue.trim() : '';
      final artistConfidence = _parseArtistConfidence(artistConfidenceValue);
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

  static double _parseArtistConfidence(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is! String) return 0.0;

    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      'high' => 1.0,
      'medium' => 0.6,
      'low' => 0.3,
      _ => double.tryParse(normalized) ?? 0.0,
    };
  }
}
