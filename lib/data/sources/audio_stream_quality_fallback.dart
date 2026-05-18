import '../models/settings.dart';
import 'base_source.dart';
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
