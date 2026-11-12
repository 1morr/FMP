import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/ui/placeholder/placeholder_search.dart';

/// M0 的佔位畫面：App 名稱與一個搜尋框；照設計稿的畫面從 M1 開始。
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

class _TrackTile extends StatelessWidget {
  const _TrackTile(this.track);

  final Track track;

  @override
  Widget build(BuildContext context) {
    final duration = track.duration;
    return ListTile(
      title: Text(track.title),
      subtitle: Text(
        duration == null
            ? track.author
            : '${track.author} · ${formatDuration(duration)}',
      ),
    );
  }
}

/// `m:ss`，一小時以上 `h:mm:ss`。
String formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final seconds = two(d.inSeconds % 60);
  return d.inHours > 0
      ? '${d.inHours}:${two(d.inMinutes % 60)}:$seconds'
      : '${d.inMinutes}:$seconds';
}
