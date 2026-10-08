import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/track_info.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/format/duration_text.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 一首曲目的詳細資料：封面、曲名、上傳者、時長、音源名稱（design §9.3）。播放頁的
/// 「詳細」分頁與（M2 PR 19 的）右側「正在播放」面板共用。M3 有 `trackDetail` 時補欄位。
class TrackDetails extends ConsumerWidget {
  const TrackDetails({super.key, required this.track});

  final TrackInfo track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).playerPage;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    // 清單還沒載入完時用插件 id，同 `Toaster` 的作法。
    final source =
        ref.watch(pluginNameProvider(track.sourceTypeId)) ?? track.sourceTypeId;
    final uploader = track.uploader;
    final duration = track.duration;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth.isFinite
            ? (constraints.maxWidth - spacing.x8).clamp(
                0.0,
                AppLayout.trackDetailsArtworkMax,
              )
            : AppLayout.trackDetailsArtworkMax;
        return SingleChildScrollView(
          padding: EdgeInsets.all(spacing.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: ArtworkImage(
                  pluginId: track.sourceTypeId,
                  artwork: track.artwork,
                  size: size,
                ),
              ),
              SizedBox(height: spacing.x4),
              Text(track.title, style: theme.textTheme.titleLarge),
              SizedBox(height: spacing.x4),
              if (uploader != null)
                _Field(label: t.detailsUploader, value: uploader),
              if (duration != null)
                _Field(
                  label: t.detailsDuration,
                  value: formatDuration(duration),
                ),
              _Field(label: t.detailsSource, value: source),
            ],
          ),
        );
      },
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: AppTokens.of(context).spacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
