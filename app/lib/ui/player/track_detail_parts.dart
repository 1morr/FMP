import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/domain/appearance.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/format/count_text.dart';
import 'package:fmp/ui/format/date_text.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/player/track_details.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

// 詳細區在 TrackDetails 現有欄位下面多顯示的東西（M3 design §11.2）：發佈時間、專輯、
// 統計與簡介；載入中的佔位、失敗與重試。

/// 簡介收合時顯示幾行。
const _descriptionCollapsedLines = 4;

/// 詳細資料已取到時的欄位（頭像在上傳者那一列，不在這裡）。
class TrackDetailFields extends ConsumerWidget {
  const TrackDetailFields({super.key, required this.detail});

  final TrackDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).playerPage;
    final locale = ref.watch(uiLocaleProvider);
    final spacing = AppTokens.of(context).spacing;
    final publishedAt = detail.publishedAt;
    final album = detail.album;
    final description = detail.description;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (publishedAt != null)
          DetailsField(
            label: t.detailsPublished,
            value: formatDate(locale, publishedAt),
          ),
        if (album != null && album.trim().isNotEmpty)
          DetailsField(label: t.detailsAlbum, value: album),
        if (detail.stats.isNotEmpty) ...[
          _Stats(stats: detail.stats, locale: locale),
          SizedBox(height: spacing.x3),
        ],
        if (description != null && description.trim().isNotEmpty)
          _Description(label: t.detailsDescription, text: description),
      ],
    );
  }
}

IconData _statIcon(TrackStatKind kind) => switch (kind) {
  TrackStatKind.view => Icons.visibility_outlined,
  TrackStatKind.like => Icons.thumb_up_outlined,
  TrackStatKind.favorite => Icons.star_outline,
  TrackStatKind.comment => Icons.comment_outlined,
  TrackStatKind.share => Icons.share_outlined,
  TrackStatKind.danmaku => Icons.subtitles_outlined,
  TrackStatKind.coin => Icons.monetization_on_outlined,
};

class _Stats extends ConsumerWidget {
  const _Stats({required this.stats, required this.locale});

  final List<TrackStat> stats;
  final LocaleSetting locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).playerPage;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    String nameOf(TrackStatKind kind) => switch (kind) {
      TrackStatKind.view => t.statView,
      TrackStatKind.like => t.statLike,
      TrackStatKind.favorite => t.statFavorite,
      TrackStatKind.comment => t.statComment,
      TrackStatKind.share => t.statShare,
      TrackStatKind.danmaku => t.statDanmaku,
      TrackStatKind.coin => t.statCoin,
    };
    return Wrap(
      spacing: spacing.x4,
      runSpacing: spacing.x2,
      children: [
        for (final stat in stats)
          Semantics(
            label: '${nameOf(stat.kind)} ${formatCount(locale, stat.count)}',
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _statIcon(stat.kind),
                  size: spacing.x5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                SizedBox(width: spacing.x1),
                Text(
                  formatCount(locale, stat.count),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 簡介：預設收合在 [_descriptionCollapsedLines] 行，放不下時才有「展開」。
class _Description extends ConsumerStatefulWidget {
  const _Description({required this.label, required this.text});

  final String label;
  final String text;

  @override
  ConsumerState<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends ConsumerState<_Description> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).playerPage;
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final painter = TextPainter(
              text: TextSpan(text: widget.text, style: style),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: _descriptionCollapsedLines,
            )..layout(maxWidth: constraints.maxWidth);
            final overflows = painter.didExceedMaxLines;
            painter.dispose();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.text,
                  style: style,
                  maxLines: _expanded ? null : _descriptionCollapsedLines,
                  overflow: _expanded ? null : TextOverflow.ellipsis,
                ),
                if (overflows)
                  TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(
                      _expanded ? t.detailsCollapse : t.detailsExpand,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 載入中的佔位：幾條灰色的橫條，不動畫。
class TrackDetailPlaceholder extends ConsumerWidget {
  const TrackDetailPlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).playerPage;
    final tokens = AppTokens.of(context);
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double widthFactor) => Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.x2),
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: SizedBox(
          height: tokens.spacing.x4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(tokens.radius.small),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      label: t.detailsLoading,
      container: true,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [bar(0.4), bar(0.7), bar(1), bar(0.85)],
        ),
      ),
    );
  }
}

/// 取詳細失敗：只在詳細區顯示（不跳提示），離線時說離線；[onRetry] 重新取。
class TrackDetailFailure extends ConsumerWidget {
  const TrackDetailFailure({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translations = ref.watch(translationsProvider);
    final t = translations.playerPage;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final reason = switch (ref.watch(networkStatusProvider)) {
      NetworkStatus.online => null,
      NetworkStatus.noInterface => translations.offline.noInterface,
      NetworkStatus.unreachable => translations.offline.unreachable,
    };
    return Semantics(
      container: true,
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                reason == null ? Icons.error_outline : Icons.cloud_off,
                size: spacing.x5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              SizedBox(width: spacing.x2),
              Expanded(
                child: Text(
                  reason ?? t.detailsFailed,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          TextButton(onPressed: onRetry, child: Text(t.detailsRetry)),
        ],
      ),
    );
  }
}
