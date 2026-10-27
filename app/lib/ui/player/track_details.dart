import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/track_info.dart';
import 'package:fmp/platform/url_opener/url_opener.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/player/track_detail_parts.dart';
import 'package:fmp/ui/player/track_detail_provider.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/format/duration_text.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// 一首曲目的詳細資料：封面、曲名、上傳者、時長、音源名稱（design §9.3）。播放頁的
/// 「詳細」分頁與（M2 PR 19 的）右側「正在播放」面板共用。插件宣告 `trackDetail` 時在下面
/// 補發佈時間、專輯、統計與簡介，上傳者旁加頭像（design §11.2）；取不到只在這一區顯示失敗與重試。
class TrackDetails extends ConsumerWidget {
  const TrackDetails({
    super.key,
    required this.track,
    this.footer,
    this.scrollController,
  });

  final TrackInfo track;

  /// 詳細最後多放的東西（右側面板的「下一首」）；播放頁的詳細分頁沒有。
  final Widget? footer;

  /// 放在底部面板時，面板給的捲動控制器；其他地方沒有。
  final ScrollController? scrollController;

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
    final key = track.key;
    final declared = declaresTrackDetail(
      ref.watch(
        pluginRegistryProvider.select(
          (plugins) => plugins.value?[track.sourceTypeId],
        ),
      ),
    );
    final detailAsync = declared ? ref.watch(trackDetailProvider(key)) : null;
    final detail = detailAsync?.value;
    final avatar = [
      for (final image in detail?.uploaderAvatar ?? const <Artwork>[])
        TrackArtwork(url: image.url, width: image.width),
    ];
    // 插件給了原網頁（過了允許網域）且平台開得了瀏覽器，封面與標題才可以點（ADR 0035 §決定 10）。
    final detailUrl = detail?.webUrl;
    final webUrl = detailUrl == null || ref.watch(urlOpenerProvider) == null
        ? null
        : detailUrl;
    Future<void> openWeb() async {
      final uri = webUrl;
      if (uri == null) return;
      final toaster = ref.read(toasterProvider);
      final opened = await ref.read(urlOpenerProvider)?.open(uri) ?? false;
      if (!opened) toaster.warning(t.openWebFailed);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth.isFinite
            ? (constraints.maxWidth - spacing.x8).clamp(
                0.0,
                AppLayout.trackDetailsArtworkMax,
              )
            : AppLayout.trackDetailsArtworkMax;
        return SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.all(spacing.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: _WebLink(
                  label: t.openWebPage,
                  onOpen: webUrl == null ? null : openWeb,
                  child: ArtworkImage(
                    pluginId: track.sourceTypeId,
                    artwork: track.artwork,
                    size: size,
                  ),
                ),
              ),
              SizedBox(height: spacing.x4),
              _WebLink(
                label: t.openWebPage,
                onOpen: webUrl == null ? null : openWeb,
                minHeight: kMinInteractiveDimension,
                child: Text(
                  track.displayTitle,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              SizedBox(height: spacing.x4),
              if (uploader != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (avatar.isNotEmpty) ...[
                      ClipOval(
                        child: ArtworkImage(
                          pluginId: track.sourceTypeId,
                          artwork: avatar,
                          size: spacing.x10,
                          rounded: false,
                        ),
                      ),
                      SizedBox(width: spacing.x3),
                    ],
                    Expanded(
                      child: DetailsField(
                        label: t.detailsUploader,
                        value: uploader,
                      ),
                    ),
                  ],
                ),
              if (duration != null)
                DetailsField(
                  label: t.detailsDuration,
                  value: formatDuration(duration),
                ),
              DetailsField(label: t.detailsSource, value: source),
              if (detailAsync != null)
                if (detailAsync.isLoading)
                  const TrackDetailPlaceholder()
                else if (detailAsync.hasError)
                  TrackDetailFailure(
                    onRetry: () => ref.invalidate(trackDetailProvider(key)),
                  )
                else if (detail != null)
                  TrackDetailFields(detail: detail),
              ?footer,
            ],
          ),
        );
      },
    );
  }
}

/// 可以點開原網頁的封面或標題：[onOpen] 為 `null`（沒有網址）時什麼都不包，原樣畫 [child]。
/// 有的話帶「連結」語意，點擊區至少 [minHeight]。
class _WebLink extends StatelessWidget {
  const _WebLink({
    required this.label,
    required this.onOpen,
    required this.child,
    this.minHeight,
  });

  final String label;
  final VoidCallback? onOpen;
  final Widget child;
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    final onOpen = this.onOpen;
    if (onOpen == null) return child;
    final radius = BorderRadius.circular(AppTokens.of(context).radius.small);
    return Semantics(
      link: true,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onOpen,
          borderRadius: radius,
          child: minHeight == null
              ? child
              : ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight!),
                  child: Align(alignment: Alignment.centerLeft, child: child),
                ),
        ),
      ),
    );
  }
}

/// 詳細資料的一欄：小標題加內容（直播間的詳細也用它）。
class DetailsField extends StatelessWidget {
  const DetailsField({super.key, required this.label, required this.value});

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
