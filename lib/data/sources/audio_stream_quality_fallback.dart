import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_exception.dart';

/// 依音質等級從已按碼率**由高到低**排好的清單裡挑一個：high 取第一個、
/// medium 取中間、low 取最後一個。Bilibili 與 YouTube 以前各有一份相同的私有
/// 版本；排序責任仍在呼叫端，這裡不重排。
T? selectByQualityLevel<T>(
  List<T> sortedByBitrateDesc,
  AudioQualityLevel level,
) {
  if (sortedByBitrateDesc.isEmpty) return null;
  return switch (level) {
    AudioQualityLevel.high => sortedByBitrateDesc.first,
    AudioQualityLevel.medium =>
      sortedByBitrateDesc[sortedByBitrateDesc.length ~/ 2],
    AudioQualityLevel.low => sortedByBitrateDesc.last,
  };
}

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
    AudioQualityLevel.low => const [AudioQualityLevel.low],
  };

  return includeCurrent ? levels : levels.skip(1).toList(growable: false);
}

Future<AudioStreamResult> fetchAudioStreamWithQualityFallback({
  required AudioStreamSource source,
  required AudioStreamRequest request,
}) async {
  final levels = audioQualityFallbackLevels(request.config.qualityLevel);
  SourceApiException? lastQualityError;
  StackTrace? lastQualityStackTrace;

  for (var i = 0; i < levels.length; i++) {
    final level = levels[i];
    try {
      return await source.getAudioStream(
        request.copyWith(config: request.config.copyWith(qualityLevel: level)),
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

Future<AudioStreamResult?> fetchAlternativeAudioStreamWithQualityFallback({
  required AudioStreamSource source,
  required AudioStreamRequest request,
}) async {
  for (final level in audioQualityFallbackLevels(
    request.config.qualityLevel,
    includeCurrent: false,
  )) {
    final fallbackRequest = request.copyWith(
      config: request.config.copyWith(qualityLevel: level),
    );
    final sourceAlternative = await source.getAlternativeAudioStream(
      fallbackRequest,
    );
    if (sourceAlternative != null) return sourceAlternative;

    try {
      final primaryFallback = await source.getAudioStream(fallbackRequest);
      if (primaryFallback.url != request.failedUrl) {
        return primaryFallback;
      }
    } on SourceApiException catch (error) {
      if (!error.kind.canFallbackToLowerAudioQuality) rethrow;
    }
  }

  return source.getAlternativeAudioStream(request);
}
