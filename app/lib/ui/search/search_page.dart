import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/redaction/redact.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/ui/search/placeholder_search.dart';
import 'package:fmp/ui/search/search_field.dart';
import 'package:fmp/ui/shell/shell_page.dart';

/// 搜尋頁：M1 先放 M0 的佔位搜尋（結果與播放面板），照稿的搜尋頁在之後的
/// 票。搜尋欄依寬度放在外殼的 dock 或側欄；中寬度的細欄只有搜尋項目，欄位
/// 在這一頁的頂端（`docs/design/DESIGN.md`〈中寬度〉）。
class SearchPage extends ConsumerWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final medium = FormFactor.of(context).widthClass == WidthClass.medium;
    return ShellPage(
      title: t.shell.nav.search,
      children: [
        if (medium) ...[
          const Align(
            alignment: Alignment.centerLeft,
            child: SearchField(placement: SearchFieldPlacement.page),
          ),
          const SizedBox(height: FmpSpace.s3),
        ],
        const _PlaybackPanel(),
        ..._results(context, ref.watch(placeholderSearchProvider)),
      ],
    );
  }

  static List<Widget> _results(
    BuildContext context,
    AsyncValue<List<PluginResults>>? results,
  ) {
    final t = context.t;
    return switch (results) {
      null => const [],
      AsyncData(:final value) => [
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
      AsyncError() => [
        Padding(
          padding: const EdgeInsets.all(FmpSpace.s6),
          child: Center(child: Text(t.placeholder.search.failed)),
        ),
      ],
      _ => const [
        Padding(
          padding: EdgeInsets.all(FmpSpace.s6),
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
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
