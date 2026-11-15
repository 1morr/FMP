import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/redaction/redact.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/ui/placeholder/placeholder_search.dart';

/// M0 的佔位畫面：App 名稱、一個搜尋框、搜尋結果，點一首就播放；照設計稿
/// 的畫面從 M1 開始。
class PlaceholderPage extends ConsumerStatefulWidget {
  const PlaceholderPage({super.key});

  @override
  ConsumerState<PlaceholderPage> createState() => _PlaceholderPageState();
}

class _PlaceholderPageState extends ConsumerState<PlaceholderPage> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() =>
      ref.read(placeholderSearchProvider.notifier).search(_query.text);

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final text = context.fmpText;
    final colors = context.fmpColors;
    final metrics = context.fmpMetrics;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: FmpSpace.s6),
            Text(t.app.name, style: text.large),
            const SizedBox(height: FmpSpace.s2),
            Text(
              t.placeholder.subtitle,
              style: text.sub.copyWith(color: colors.label2),
            ),
            Padding(
              padding: EdgeInsets.all(metrics.pagePadding),
              child: TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: t.placeholder.search.hint,
                  hintStyle: TextStyle(color: colors.label3),
                  filled: true,
                  fillColor: colors.fill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(metrics.radii.field),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    tooltip: t.placeholder.search.hint,
                    icon: const Icon(Icons.search),
                    onPressed: _search,
                  ),
                ),
              ),
            ),
            const _PlaybackPanel(),
            const Expanded(child: _Results()),
          ],
        ),
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    return switch (ref.watch(placeholderSearchProvider)) {
      null => const SizedBox.shrink(),
      AsyncData(:final value) => ListView(
        children: [
          for (final source in value) ...[
            ListTile(
              title: Text(
                source.pluginName,
                style: context.fmpText.head.copyWith(
                  color: context.fmpColors.label2,
                ),
              ),
            ),
            if (source.error case final error?)
              ListTile(title: Text(_errorText(t, error)))
            else if (source.tracks.isEmpty)
              ListTile(title: Text(t.placeholder.search.empty))
            else
              for (final track in source.tracks) _TrackTile(track),
          ],
        ],
      ),
      AsyncError() => Center(child: Text(t.placeholder.search.failed)),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  static String _errorText(Translations t, AppError error) => switch (error) {
    NetworkError() => t.placeholder.search.network,
    RateLimited() => t.placeholder.search.rateLimited,
    _ => t.placeholder.search.failed,
  };
}

class _TrackTile extends ConsumerWidget {
  const _TrackTile(this.track);

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final duration = track.duration;
    final text = context.fmpText;
    return ListTile(
      onTap: () => ref.read(playbackProvider.notifier).play(track),
      title: Text(track.title, style: text.body),
      subtitle: Text(
        style: text.sub.copyWith(color: context.fmpColors.label2),
        duration == null
            ? track.author
            : '${track.author} · ${formatDuration(duration)}',
      ),
    );
  }
}

/// 正在播的曲目：播放狀態、進度、暫停與繼續，以及它的串流的音質、到期時間
/// 與遮蔽過的網址（brief〈錯誤、log 與診斷〉）。
class _PlaybackPanel extends ConsumerWidget {
  const _PlaybackPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    if (playback == null) return const SizedBox.shrink();
    final t = context.t;
    final stream = playback.stream;
    final colors = context.fmpColors;
    final metrics = context.fmpMetrics;
    return Container(
      margin: EdgeInsets.symmetric(horizontal: metrics.pagePadding),
      padding: const EdgeInsets.all(FmpSpace.s3),
      decoration: BoxDecoration(
        color: colors.cell,
        borderRadius: BorderRadius.circular(metrics.radii.group),
      ),
      child: DefaultTextStyle.merge(
        style: context.fmpText.foot.copyWith(color: colors.label2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              playback.track.title,
              style: context.fmpText.head.copyWith(color: colors.label),
            ),
            const SizedBox(height: FmpSpace.s1),
            _controls(context, ref, t, playback),
            // 播放失敗時也顯示，方便看是哪個 CDN。
            if (stream != null) ..._details(t, stream),
          ],
        ),
      ),
    );
  }

  static Widget _controls(
    BuildContext context,
    WidgetRef ref,
    Translations t,
    PlaybackState playback,
  ) {
    final notifier = ref.read(playbackProvider.notifier);
    final status = switch (playback.status) {
      PlaybackStatus.resolving => t.placeholder.playback.resolving,
      PlaybackStatus.loading => t.placeholder.playback.loading,
      PlaybackStatus.buffering => t.placeholder.playback.buffering,
      PlaybackStatus.playing => t.placeholder.playback.playing,
      PlaybackStatus.paused => t.placeholder.playback.paused,
      PlaybackStatus.completed => t.placeholder.playback.completed,
      PlaybackStatus.failed => _errorText(t, playback),
    };
    final button = switch (playback.status) {
      PlaybackStatus.playing || PlaybackStatus.buffering => IconButton(
        tooltip: t.placeholder.playback.pause,
        icon: const Icon(Icons.pause),
        onPressed: notifier.pause,
      ),
      PlaybackStatus.paused => IconButton(
        tooltip: t.placeholder.playback.play,
        icon: const Icon(Icons.play_arrow),
        onPressed: notifier.resume,
      ),
      _ => null,
    };
    final duration = playback.duration;
    return Row(
      children: [
        ?button,
        Expanded(child: Text(status)),
        if (playback.status != PlaybackStatus.failed && duration != null)
          Text(
            '${formatDuration(playback.position)} / '
            '${formatDuration(duration)}',
            style: context.fmpText.foot.tabular,
          ),
      ],
    );
  }

  static List<Widget> _details(Translations t, AudioStream stream) {
    final bitrate = stream.bitrate;
    final quality = [
      ?stream.codec,
      if (bitrate != null) '${(bitrate / 1000).round()} kbps',
    ].join(' · ');
    final expiresAt = stream.expiresAt;
    return [
      Text(
        t.placeholder.stream.quality(
          value: quality.isEmpty ? t.placeholder.stream.unknown : quality,
        ),
      ),
      Text(
        t.placeholder.stream.expires(
          value: expiresAt == null
              ? t.placeholder.stream.unknown
              : formatExpiry(expiresAt.toLocal()),
        ),
      ),
      Text(
        t.placeholder.stream.url(value: redact(stream.url.toString())),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    ];
  }

  /// 還沒有串流時是解析失敗，有了之後是播放失敗。
  static String _errorText(Translations t, PlaybackState playback) {
    final resolved = playback.stream != null;
    return switch (playback.error) {
      NotFound() => t.placeholder.stream.notFound,
      Unavailable() => t.placeholder.stream.unavailable,
      Unsupported() when resolved => t.placeholder.playback.unsupportedFormat,
      Unsupported() => t.placeholder.stream.unsupported,
      NetworkError() => t.placeholder.search.network,
      RateLimited() => t.placeholder.search.rateLimited,
      _ when resolved => t.placeholder.playback.failed,
      _ => t.placeholder.stream.failed,
    };
  }
}

/// 到期時間：`yyyy-MM-dd HH:mm`，照傳入的時區（畫面傳本地時間）。
String formatExpiry(DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${at.year}-${two(at.month)}-${two(at.day)} '
      '${two(at.hour)}:${two(at.minute)}';
}

/// `m:ss`，一小時以上 `h:mm:ss`。
String formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final seconds = two(d.inSeconds % 60);
  return d.inHours > 0
      ? '${d.inHours}:${two(d.inMinutes % 60)}:$seconds'
      : '${d.inMinutes}:$seconds';
}
