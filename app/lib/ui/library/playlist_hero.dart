import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/library/library_state.dart';
import 'package:fmp/ui/library/playlist_cover.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/plugins/source_icon.dart';
import 'package:fmp/ui/shell/page_app_bar.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/tracks/track_selection.dart';

/// 歌單詳情的頂圖（ADR 0035，R7.6，舊版的 `CollapsingHeroSliverAppBar`）：展開時 [AppLayout.playlistHeroHeight]，
/// 背景是模糊的歌單封面加深色遮罩，前景是封面、名稱、描述、擁有者、首數與總時長、來源徽章；往上捲
/// 就淡出，收成置中標題的一般頁頂（返回鈕的 tooltip 與行為同 [PageAppBar]）。
///
/// 沒有動畫：隨捲動位置變化，所以「減少動態」不需要另外處理。背景不論封面是什麼都壓同一層遮罩，字一律
/// 白色（[AppLayout.onHero]），對比度與封面無關；來源徽章是成對的語意色（同舊版的徽章）。
///
/// 字級放大時頂圖跟著長高（[playlistHeroHeight]），放不下的部分才整塊等比縮小。
class PlaylistHeroBar extends StatelessWidget {
  const PlaylistHeroBar({super.key, required this.detail});

  final PlaylistDetail detail;

  @override
  Widget build(BuildContext context) => SliverAppBar(
    pinned: true,
    automaticallyImplyLeading: false,
    expandedHeight: playlistHeroHeight(context, detail),
    // 捲動時 `_HeroSpace` 每一格都重建（它讀 `FlexibleSpaceBarSettings`）：模糊的背景與頂圖的內容在這裡
    // 建好一次傳進去，同一個 widget 實例不跟著重建；背景另有自己的圖層，淡出時不重畫模糊。
    flexibleSpace: _HeroSpace(
      name: detail.playlist.name,
      backdrop: RepaintBoundary(child: _Backdrop(detail: detail)),
      content: _HeroContent(detail: detail),
    ),
  );
}

/// 頂圖展開時的高度：字級 1.0 是 [AppLayout.playlistHeroHeight]；放大時加上文字多出來的高度（照
/// [_HeroContent] 實際會有的行與各行的字級角色算，Android 的非線性縮放對大字放得少），最多到視窗高度的
/// [AppLayout.playlistHeroMaxShare]（橫向手機上頂圖不佔滿整頁）。超過的部分由 [_HeroContent] 等比縮小。
double playlistHeroHeight(BuildContext context, PlaylistDetail detail) {
  final text = Theme.of(context).textTheme;
  final description = detail.playlist.description;
  final owner = detail.remote?.ownerName;
  double block(TextScaler scaler) {
    double lines(TextStyle? style, int count) {
      final size = style?.fontSize ?? 14;
      return scaler.scale(size) * (style?.height ?? 1.4) * count;
    }

    return lines(text.titleLarge, 2) +
        (description != null && description.isNotEmpty
            ? lines(text.bodyMedium, 2)
            : 0) +
        (owner != null && owner.isNotEmpty ? lines(text.bodyMedium, 1) : 0) +
        lines(text.bodyMedium, 1) +
        lines(text.labelMedium, 1);
  }

  final extra =
      block(MediaQuery.textScalerOf(context)) - block(TextScaler.noScaling);
  if (extra <= 0) return AppLayout.playlistHeroHeight;
  final cap = math.max(
    AppLayout.playlistHeroHeight,
    MediaQuery.sizeOf(context).height * AppLayout.playlistHeroMaxShare,
  );
  return math.min(AppLayout.playlistHeroHeight + extra, cap);
}

class _HeroSpace extends ConsumerWidget {
  const _HeroSpace({
    required this.name,
    required this.backdrop,
    required this.content,
  });

  final String name;
  final Widget backdrop;
  final Widget content;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final scheme = Theme.of(context).colorScheme;
    final spacing = AppTokens.of(context).spacing;
    final top = MediaQuery.paddingOf(context).top;
    // 1＝完全展開、0＝收成頁頂。
    final range = settings == null
        ? 0.0
        : settings.maxExtent - settings.minExtent;
    final expand = settings == null || range <= 0
        ? 1.0
        : ((settings.currentExtent - settings.minExtent) / range).clamp(
            0.0,
            1.0,
          );
    // 選取模式時選取列蓋住頁頂，返回鈕不留在樹上（同其他頁：選取列沒有返回鈕）。
    final selecting =
        TrackSelectionScope.maybeOf<int>(context)?.active ?? false;
    final back = selecting
        ? null
        : pageBackButton(
            context,
            ref,
            color: Color.lerp(scheme.onSurface, AppLayout.onHero, expand),
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(opacity: expand, child: backdrop),
        // 收起來之後的置中標題：前半段還看得到頂圖的字，所以到一半以後才出現、淡入（展開時不放，
        // 免得名稱在樹上出現兩次）。
        if (expand < 0.5)
          Positioned(
            top: top,
            left: 0,
            right: 0,
            height: kToolbarHeight,
            child: Opacity(
              opacity: (1 - expand * 2).clamp(0.0, 1.0),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: kMinInteractiveDimension + spacing.x2,
                ),
                child: Center(
                  child: Semantics(
                    header: true,
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (back != null)
          Positioned(
            top: top,
            left: spacing.x1,
            height: kToolbarHeight,
            child: back,
          ),
        if (expand > 0.4)
          Positioned(
            top: top + kToolbarHeight,
            left: spacing.x4,
            right: spacing.x4,
            bottom: spacing.x6,
            child: IgnorePointer(
              child: Opacity(
                opacity: ((expand - 0.4) / 0.6).clamp(0.0, 1.0),
                child: content,
              ),
            ),
          ),
      ],
    );
  }
}

/// 模糊的封面加遮罩，底部漸層到頁面底色（接上下面的清單）。
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.detail});

  final PlaylistDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final playlist = detail.playlist;
    return Stack(
      fit: StackFit.expand,
      children: [
        // 小圖放大再模糊：不必為了背景解碼一張全寬的大圖。
        ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: AppLayout.heroBlur,
              sigmaY: AppLayout.heroBlur,
              tileMode: TileMode.clamp,
            ),
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: PlaylistCover(
                artwork: playlist.artwork,
                firstTrack: detail.entries.firstOrNull?.track,
                size: AppLayout.heroBackdropSource,
              ),
            ),
          ),
        ),
        const ColoredBox(color: AppLayout.heroScrim),
        Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: AppTokens.of(context).spacing.x6,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [scheme.surface.withValues(alpha: 0), scheme.surface],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroContent extends ConsumerWidget {
  const _HeroContent({required this.detail});

  final PlaylistDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).library;
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    final spacing = tokens.spacing;
    final playlist = detail.playlist;
    final remote = detail.remote;
    final description = playlist.description;
    final owner = remote?.ownerName;
    final duration = durationText(t, detail.totalDuration);
    final count = trackCountText(t, detail.entries.length);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: AppLayout.onHeroMuted,
    );
    final sourceName = remote == null
        ? null
        : ref.watch(pluginNameProvider(remote.pluginId)) ?? remote.pluginId;
    // 字放得太大時整塊等比縮小，不讓它溢出頂圖（頂圖高度固定）。
    return LayoutBuilder(
      builder: (context, constraints) {
        final textWidth =
            constraints.maxWidth - AppLayout.playlistHeroCover - spacing.x4;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(tokens.radius.medium),
                boxShadow: [
                  BoxShadow(
                    color: AppLayout.heroScrim,
                    blurRadius: spacing.x4,
                    offset: Offset(0, spacing.x1),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(tokens.radius.medium),
                child: PlaylistCover(
                  artwork: playlist.artwork,
                  firstTrack: detail.entries.firstOrNull?.track,
                  size: AppLayout.playlistHeroCover,
                ),
              ),
            ),
            SizedBox(width: spacing.x4),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.bottomStart,
                child: SizedBox(
                  width: textWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 展開時這裡是頁面的標題（收起來時是頁頂中央那一個）。
                      Semantics(
                        header: true,
                        child: Text(
                          playlist.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: AppLayout.onHero,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (description != null && description.isNotEmpty)
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                      if (owner != null && owner.isNotEmpty)
                        Text(
                          t.heroOwner(name: owner),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                      Text(
                        duration == null ? count : '$count · $duration',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                      SizedBox(height: spacing.x1),
                      _Badge(
                        pluginId: remote?.pluginId,
                        label: sourceName == null
                            ? t.local
                            : t.heroImported(source: sourceName),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 來源徽章：本機歌單是「本機」，匯入歌單是來源圖示加「已匯入 · 音源名」。底色與字是成對的
/// `primaryContainer`／`onPrimaryContainer`（舊版的徽章）：半透明白底在淺色封面上只有約 3.7:1，
/// 不到小字的 4.5:1。
class _Badge extends StatelessWidget {
  const _Badge({required this.pluginId, required this.label});

  final String? pluginId;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final spacing = tokens.spacing;
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(tokens.radius.small),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.x2,
          vertical: spacing.x1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pluginId case final id?) ...[
              SourceIcon(pluginId: id, size: AppLayout.inlineIcon + spacing.x1),
              SizedBox(width: spacing.x1),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: scheme.onPrimaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
