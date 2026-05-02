import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/logger.dart';

class AiLyricsCandidate {
  const AiLyricsCandidate({
    required this.candidateId,
    required this.source,
    required this.sourcePriorityRank,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    required this.durationSeconds,
    required this.videoDurationSeconds,
    required this.durationDiffSeconds,
    required this.hasSyncedLyrics,
    required this.hasPlainLyrics,
    required this.hasTranslatedLyrics,
    required this.hasRomajiLyrics,
    this.lyricsPreview = '',
  });

  final String candidateId;
  final String source;
  final int sourcePriorityRank;
  final String trackName;
  final String artistName;
  final String albumName;
  final int durationSeconds;
  final int videoDurationSeconds;
  final int durationDiffSeconds;
  final bool hasSyncedLyrics;
  final bool hasPlainLyrics;
  final bool hasTranslatedLyrics;
  final bool hasRomajiLyrics;
  final String lyricsPreview;

  Map<String, dynamic> toJson() => {
        'candidateId': candidateId,
        'source': source,
        'sourcePriorityRank': sourcePriorityRank,
        'trackName': trackName,
        'artistName': artistName,
        'albumName': albumName,
        'durationSeconds': durationSeconds,
        'videoDurationSeconds': videoDurationSeconds,
        'durationDiffSeconds': durationDiffSeconds,
        'hasSyncedLyrics': hasSyncedLyrics,
        'hasPlainLyrics': hasPlainLyrics,
        'hasTranslatedLyrics': hasTranslatedLyrics,
        'hasRomajiLyrics': hasRomajiLyrics,
        'lyricsPreview': lyricsPreview,
      };
}

class AiLyricsSelection {
  const AiLyricsSelection({
    required this.selectedCandidateId,
    required this.confidence,
    required this.reason,
  });

  final String? selectedCandidateId;
  final double confidence;
  final String reason;
}

class AiLyricsSelector with Logging {
  AiLyricsSelector({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<AiLyricsSelection?> select({
    required String endpoint,
    required String apiKey,
    required String model,
    required String title,
    String? uploader,
    String? videoDescription,
    required int durationSeconds,
    required List<String> sourcePriority,
    required bool allowPlainLyricsAutoMatch,
    required List<AiLyricsCandidate> candidates,
    required int timeoutSeconds,
  }) async {
    final trimmedEndpoint = endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    final trimmedApiKey = apiKey.trim();
    final trimmedModel = model.trim();
    final timeout = Duration(seconds: timeoutSeconds < 1 ? 10 : timeoutSeconds);
    final normalizedVideoDescription =
        _normalizeOptionalText(videoDescription, maxChars: 500);
    if (trimmedEndpoint.isEmpty ||
        trimmedApiKey.isEmpty ||
        trimmedModel.isEmpty) {
      logDebug(
          'AI lyrics selector skipped because configuration is incomplete');
      return null;
    }

    final userPayload = {
      'title': title,
      if (uploader != null && uploader.trim().isNotEmpty)
        'uploader': uploader.trim(),
      if (normalizedVideoDescription != null)
        'videoDescription': normalizedVideoDescription,
      'durationSeconds': durationSeconds,
      'sourcePriority': sourcePriority,
      'allowPlainLyricsAutoMatch': allowPlainLyricsAutoMatch,
      'candidates': candidates.map((candidate) => candidate.toJson()).toList(),
    };
    logDebug('AI lyrics selector request payload: ${jsonEncode(userPayload)}');

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
              'content': 'Choose the best lyrics candidate for the provided '
                  'video. You may use videoDescription as extra context when '
                  'present. The uploader is context and is not necessarily the '
                  'artist. Use lyricsPreview to compare candidate content '
                  'against the title, uploader, and videoDescription. Always '
                  'choose the closest acceptable candidate, including a cover, '
                  'remix, live version, or alternate performance when that is '
                  'the best available match for the same song. Use '
                  'selectedCandidateId null only when every candidate is a '
                  'completely different song. Respect sourcePriority when '
                  'candidates are otherwise similarly accurate. Always prefer '
                  'synced lyrics over plain lyrics. Return strict JSON only '
                  'with exactly these fields: selectedCandidateId, confidence, '
                  'reason.',
            },
            {'role': 'user', 'content': jsonEncode(userPayload)},
          ],
        },
      );

      final content = _extractContent(response.data);
      if (content == null) {
        logWarning('AI lyrics selector response has no content');
        return null;
      }
      logDebug('AI lyrics selector raw response content: $content');
      final parsed = parseContent(content);
      logDebug(
        'AI lyrics selector parsed result: selected='
        '${parsed?.selectedCandidateId}, confidence=${parsed?.confidence}, '
        'reason=${parsed?.reason}',
      );
      return parsed;
    } on DioException catch (e) {
      logWarning(
        'AI lyrics selector request failed: ${e.message ?? e.error ?? e.type}',
      );
      return null;
    } catch (e) {
      logWarning('AI lyrics selector failed: $e');
      return null;
    }
  }

  static String? _normalizeOptionalText(String? text, {required int maxChars}) {
    if (text == null) return null;
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return null;
    if (normalized.length <= maxChars) return normalized;
    return normalized.substring(0, maxChars);
  }

  static AiLyricsSelection? parseContent(String content) {
    try {
      final decoded = jsonDecode(_stripCodeFence(content));
      if (decoded is! Map<String, dynamic>) return null;
      final selected = decoded['selectedCandidateId'];
      final confidence = decoded['confidence'];
      final reason = decoded['reason'];
      if (selected != null && selected is! String) return null;
      if (confidence is! num) return null;
      return AiLyricsSelection(
        selectedCandidateId: selected as String?,
        confidence: confidence.toDouble(),
        reason: reason is String ? reason : '',
      );
    } catch (_) {
      return null;
    }
  }

  static String? _extractContent(dynamic data) {
    if (data is! Map<String, dynamic>) return null;
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final firstChoice = choices.first;
    if (firstChoice is! Map<String, dynamic>) return null;
    final message = firstChoice['message'];
    if (message is! Map<String, dynamic>) return null;
    final content = message['content'];
    return content is String ? content : null;
  }

  static String _stripCodeFence(String content) {
    final trimmed = content.trim();
    final match = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    return match?.group(1)?.trim() ?? trimmed;
  }
}
