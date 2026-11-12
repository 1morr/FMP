import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/plugins/plugins.dart';

/// 點過的曲目與它的串流（解析中、解析到的串流，或失敗的原因）。
class TrackStream {
  const TrackStream(this.track, this.stream);

  final Track track;
  final AsyncValue<AudioStream> stream;
}

/// 佔位畫面點一首曲目時解析它的串流（M0 票 10；播放在票 11）。還沒點過是
/// null；連點時只留最後一首的結果。
final placeholderStreamProvider =
    NotifierProvider<PlaceholderStream, TrackStream?>(PlaceholderStream.new);

class PlaceholderStream extends Notifier<TrackStream?> {
  int _generation = 0;

  @override
  TrackStream? build() => null;

  /// 用提供 [track] 的插件解析；沒有這個插件、或它沒宣告 resolveStream 時
  /// 是 [Unsupported]。
  Future<void> resolve(Track track) async {
    final generation = ++_generation;
    state = TrackStream(track, const AsyncLoading());
    final result = await AsyncValue.guard(() async {
      final host = await ref.read(pluginHostProvider.future);
      final plugin = host.plugins
          .where((p) => p.manifest.id == track.source)
          .firstOrNull;
      if (plugin == null) throw const Unsupported();
      return plugin.resolveStream(track.id);
    });
    if (!ref.mounted) return;
    if (result case AsyncError(:final error, :final stackTrace)
        when error is! AppError) {
      // 錯誤分類以外的例外是程式錯誤，畫面只說解析失敗，細節留在 log。
      ref
          .read(logProvider)
          .error(
            'Resolving a stream failed',
            error: error,
            stackTrace: stackTrace,
          );
    }
    if (generation == _generation) state = TrackStream(track, result);
  }
}
