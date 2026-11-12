import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/redaction/redact.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/ui/placeholder/placeholder_search.dart';
import 'package:fmp/ui/placeholder/placeholder_stream.dart';

/// M0 的佔位畫面：App 名稱、一個搜尋框與點選曲目解析出的串流；照設計稿的
/// 畫面從 M1 開始。
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
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Text(t.app.name, style: textTheme.displayMedium),
            const SizedBox(height: 8),
            Text(t.placeholder.subtitle, style: textTheme.titleMedium),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: t.placeholder.search.hint,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: t.placeholder.search.hint,
                    icon: const Icon(Icons.search),
                    onPressed: _search,
                  ),
                ),
              ),
            ),
            const _StreamPanel(),
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
                style: Theme.of(context).textTheme.titleSmall,
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
    return ListTile(
      onTap: () => ref.read(placeholderStreamProvider.notifier).resolve(track),
      title: Text(track.title),
      subtitle: Text(
        duration == null
            ? track.author
            : '${track.author} · ${formatDuration(duration)}',
      ),
    );
  }
}

/// 點過的曲目解析出的串流：音質、到期時間與遮蔽過的網址（brief §13）。
class _StreamPanel extends ConsumerWidget {
  const _StreamPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(placeholderStreamProvider);
    if (selected == null) return const SizedBox.shrink();
    final t = context.t;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selected.track.title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            ...switch (selected.stream) {
              AsyncData(:final value) => _details(t, value),
              AsyncError(:final error) => [Text(_errorText(t, error))],
              _ => [const LinearProgressIndicator()],
            },
          ],
        ),
      ),
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

  static String _errorText(Translations t, Object error) => switch (error) {
    NotFound() => t.placeholder.stream.notFound,
    Unavailable() => t.placeholder.stream.unavailable,
    Unsupported() => t.placeholder.stream.unsupported,
    NetworkError() => t.placeholder.search.network,
    RateLimited() => t.placeholder.search.rateLimited,
    _ => t.placeholder.stream.failed,
  };
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
