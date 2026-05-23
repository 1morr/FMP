import '../models/settings.dart';
import '../models/track.dart';
import 'base_source.dart';
import 'bilibili_source.dart';
import 'source_exception.dart';

List<AudioQualityLevel> audioQualityFallbackLevels(
  AudioQualityLevel qualityLevel, {
  bool includeCurrent = true,
}) {
  final levels = switch (qualityLevel) {
    AudioQualityLevel.high => const [
        AudioQualityLevel.high,
        AudioQualityLevel.medium,
        AudioQualityLevel.low,
      ],
    AudioQualityLevel.medium => const [
        AudioQualityLevel.medium,
        AudioQualityLevel.low,
      ],
    AudioQualityLevel.low => const [
        AudioQualityLevel.low,
      ],
  };

  return includeCurrent ? levels : levels.skip(1).toList(growable: false);
}

Future<AudioStreamResult> fetchAudioStreamWithQualityFallback({
  required BaseSource source,
  required String sourceId,
  required AudioStreamConfig config,
  Map<String, String>? authHeaders,
}) async {
  final levels = audioQualityFallbackLevels(config.qualityLevel);
  SourceApiException? lastQualityError;
  StackTrace? lastQualityStackTrace;

  for (var i = 0; i < levels.length; i++) {
    final level = levels[i];
    try {
      return await source.getAudioStream(
        sourceId,
        config: config.copyWith(qualityLevel: level),
        authHeaders: authHeaders,
      );
    } on SourceApiException catch (error, stackTrace) {
      lastQualityError = error;
      lastQualityStackTrace = stackTrace;
      final hasLowerQuality = i < levels.length - 1;
      if (!hasLowerQuality || !error.kind.canFallbackToLowerAudioQuality) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
  }

  Error.throwWithStackTrace(lastQualityError!, lastQualityStackTrace!);
}

Future<AudioStreamResult> fetchTrackAudioStreamWithQualityFallback({
  required BaseSource source,
  required Track track,
  required AudioStreamConfig config,
  Map<String, String>? authHeaders,
}) async {
  final levels = audioQualityFallbackLevels(config.qualityLevel);
  SourceApiException? lastQualityError;
  StackTrace? lastQualityStackTrace;

  for (var i = 0; i < levels.length; i++) {
    final level = levels[i];
    try {
      return await fetchTrackAudioStream(
        source: source,
        track: track,
        config: config.copyWith(qualityLevel: level),
        authHeaders: authHeaders,
      );
    } on SourceApiException catch (error, stackTrace) {
      lastQualityError = error;
      lastQualityStackTrace = stackTrace;
      final hasLowerQuality = i < levels.length - 1;
      if (!hasLowerQuality || !error.kind.canFallbackToLowerAudioQuality) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
  }

  Error.throwWithStackTrace(lastQualityError!, lastQualityStackTrace!);
}

Future<AudioStreamResult> fetchTrackAudioStream({
  required BaseSource source,
  required Track track,
  required AudioStreamConfig config,
  Map<String, String>? authHeaders,
}) {
  if (source is BilibiliSource && track.cid != null) {
    return source.getAudioStreamWithCid(
      track.sourceId,
      track.cid!,
      config: config,
      authHeaders: authHeaders,
    );
  }

  return source.getAudioStream(
    track.sourceId,
    config: config,
    authHeaders: authHeaders,
  );
}

Future<AudioStreamResult?> fetchTrackAlternativeAudioStream({
  required BaseSource source,
  required Track track,
  String? failedUrl,
  required AudioStreamConfig config,
  Map<String, String>? authHeaders,
}) {
  if (source is BilibiliSource && track.cid != null) {
    return source.getAlternativeAudioStreamWithCid(
      track.sourceId,
      track.cid!,
      failedUrl: failedUrl,
      config: config,
      authHeaders: authHeaders,
    );
  }

  return source.getAlternativeAudioStream(
    track.sourceId,
    failedUrl: failedUrl,
    config: config,
    authHeaders: authHeaders,
  );
}
