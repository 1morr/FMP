import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/plugins/plugins.dart';
import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/common/fmp_button.dart';
import 'package:fmp/ui/common/format.dart';
import 'package:fmp/ui/common/source_mark.dart';
import 'package:fmp/ui/common/track_actions.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';

/// 打開 [track] 的曲目資訊（`docs/design/player.html`〈曲目資訊〉）：手機
/// （窄、觸控）從底部升起 sheet，平板與桌面是置中的對話框（`DESIGN.md`
/// 〈中寬度〉）。跟著 App 的主題，不跟播放頁的色場。系統開「減少動態效果」時
/// 只淡入淡出（`DESIGN.md`〈動態〉）。
///
/// 曲目上已有的（音源、時長、分 P 數、網址）馬上列出，插件能力 `trackInfo`
/// 的欄位載入後補上；給不了的欄位不顯示（ADR 0039）。
Future<void> showTrackInfo(BuildContext context, Track track) {
  final form = FormFactor.of(context);
  final touch = form.density == Density.touch;
  final phone = form.widthClass == WidthClass.narrow && touch;
  final reduce = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: context.fmpColors.scrim,
    transitionDuration: phone && !reduce ? FmpMotion.mid : FmpMotion.fast,
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: FmpMotion.outCurve,
      );
      if (!phone || reduce) {
        return FadeTransition(
          key: const Key('track-info-fade'),
          opacity: curved,
          child: child,
        );
      }
      return SlideTransition(
        key: const Key('track-info-slide'),
        position: Tween(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
    pageBuilder: (context, _, _) => phone
        ? Align(
            alignment: Alignment.bottomCenter,
            child: _TrackInfoSheet(track: track),
          )
        : Center(
            child: _TrackInfoDialog(track: track, touch: touch),
          ),
  );
}

/// 手機的 sheet（`.sheet.lg`）：浮動的厚玻璃、圓角 34，標頭是置中的標題與
/// 右邊的關閉。往下滑或點外面收起。
class _TrackInfoSheet extends StatelessWidget {
  const _TrackInfoSheet({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final colors = context.fmpColors;
    final media = MediaQuery.of(context);
    return GestureDetector(
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 200) Navigator.of(context).pop();
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(8, 0, 8, 8 + media.viewPadding.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: media.size.height - media.viewPadding.top - 60,
          ),
          child: _Frame(
            label: t.trackInfo.title,
            radius: 34,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 5,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: colors.label4,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                // `.shead`：左邊空 44 讓標題置中，右邊關閉。
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Row(
                    children: [
                      const SizedBox(width: 44),
                      Expanded(
                        child: Text(
                          t.trackInfo.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                            color: colors.glassInk,
                          ),
                        ),
                      ),
                      _CloseButton(touch: true, tooltip: t.trackInfo.close),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: TrackInfoDetails(track: track, touch: true),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 平板與桌面的對話框（`.dlg`）：桌面寬 480、圓角 16；平板是表單大小 540、
/// 圓角 26。Esc 或點外面關掉。
class _TrackInfoDialog extends StatelessWidget {
  const _TrackInfoDialog({required this.track, required this.touch});

  final Track track;
  final bool touch;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final colors = context.fmpColors;
    final height = MediaQuery.sizeOf(context).height;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: touch ? 540 : 480,
        maxHeight: height - 80,
      ),
      child: _Frame(
        label: t.trackInfo.title,
        radius: touch ? 26 : 16,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: touch
                  ? const EdgeInsets.fromLTRB(20, 16, 16, 10)
                  : const EdgeInsets.fromLTRB(18, 14, 14, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.trackInfo.title,
                      style: TextStyle(
                        fontSize: touch ? 17 : 15,
                        height: touch ? 22 / 17 : 20 / 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                        color: colors.glassInk,
                      ),
                    ),
                  ),
                  _CloseButton(
                    touch: touch,
                    tooltip: touch
                        ? t.trackInfo.close
                        : t.trackInfo.closeShortcut(key: 'Esc'),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: touch
                    ? const EdgeInsets.fromLTRB(20, 0, 20, 16)
                    : const EdgeInsets.fromLTRB(18, 0, 18, 14),
                child: TrackInfoDetails(track: track, touch: touch),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 厚玻璃的外框，螢幕閱讀器當成一個有名字的對話框。
class _Frame extends StatelessWidget {
  const _Frame({
    required this.label,
    required this.radius,
    required this.child,
  });

  final String label;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    scopesRoute: true,
    namesRoute: true,
    explicitChildNodes: true,
    label: label,
    child: Glass(
      variant: GlassVariant.thick,
      radius: radius,
      child: Material(type: MaterialType.transparency, child: child),
    ),
  );
}

/// 關閉鈕（`.ibtn`）：手機 44、桌面 32；鍵盤選得到。
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.touch, required this.tooltip});

  final bool touch;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final size = touch ? 44.0 : 32.0;
    return ShellButton(
      key: const Key('track-info-close'),
      onTap: () => Navigator.of(context).pop(),
      tooltip: tooltip,
      label: tooltip,
      focusRadius: 999,
      builder: (context, hovered) => AnimatedContainer(
        duration: FmpMotion.fast,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: hovered ? colors.glassInk.withValues(alpha: .08) : null,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: FmpIcon(
          FmpIcons.close,
          size: touch ? 22 : 18,
          color: colors.glassInk,
        ),
      ),
    );
  }
}

/// 曲目資訊的內容（`plInfoSheet` 的 `.sbody`）：封面、曲名與作者，一列一列
/// 的欄位，有網址時底下是「在<音源>打開」與「複製連結」。
class TrackInfoDetails extends ConsumerWidget {
  const TrackInfoDetails({super.key, required this.track, required this.touch});

  final Track track;
  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final colors = context.fmpColors;
    final info = ref.watch(trackInfoProvider(track.ref));
    final source =
        ref.watch(pluginManifestProvider(track.ref.pluginId))?.name ??
        track.ref.pluginId;
    final value = info.value;
    final mono = TextStyle(
      fontFeatures: const [FontFeature.tabularFigures()],
      color: colors.glassInk,
    );
    final rows = <Widget>[
      _Row(
        label: t.trackInfo.source,
        child: SourceChip(
          pluginId: track.ref.pluginId,
          background: colors.glassInk.withValues(alpha: .08),
          foreground: colors.glassInk,
        ),
      ),
      if (value?.album case final album?)
        _Row(label: t.trackInfo.album, text: album),
      if (value?.publishedAt case final at?)
        _Row(
          label: t.trackInfo.published,
          child: Text(formatDate(at), style: mono),
        ),
      if (track.duration case final d?)
        _Row(
          label: t.trackInfo.duration,
          child: Text(formatDuration(d), style: mono),
        ),
      if (track.partCount case final n? when n > 1)
        _Row(
          label: t.trackInfo.parts,
          text: t.trackInfo.partsValue(count: n),
        ),
      if (value?.playCount case final n?)
        _Row(
          label: t.trackInfo.plays,
          child: Text(formatGrouped(n), style: mono),
        ),
      if (value?.likeCount case final n?)
        _Row(
          label: t.trackInfo.likes,
          child: Text(formatGrouped(n), style: mono),
        ),
      if (value?.commentCount case final n?)
        _Row(
          label: t.trackInfo.comments,
          child: Text(formatGrouped(n), style: mono),
        ),
      if (value?.description case final text?)
        _Row(
          label: t.trackInfo.description,
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              height: 20 / 14,
              letterSpacing: 0,
              color: colors.glassInk2,
            ),
          ),
        ),
      if (info.isLoading)
        _Note(
          key: const Key('track-info-loading'),
          text: t.trackInfo.loading,
          busy: true,
        )
      else if (info.hasError)
        _Note(
          key: const Key('track-info-failed'),
          text: t.trackInfo.failed,
          action: FmpButton(
            key: const Key('track-info-retry'),
            label: t.trackInfo.retry,
            size: FmpButtonSize.small,
            onTap: () => ref.invalidate(trackInfoProvider(track.ref)),
            touchTarget: true,
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `.pl-ih`：封面 72、曲名 18/23、作者 14/19。
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
          child: Row(
            children: [
              Cover(url: track.coverUrl, size: 72, radius: 10),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        height: 23 / 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                        color: colors.glassInk,
                      ),
                    ),
                    Text(
                      track.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 19 / 14,
                        letterSpacing: 0,
                        color: colors.glassInk2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (final (i, row) in rows.indexed) ...[
          if (i > 0)
            Container(
              height: .5,
              margin: const EdgeInsets.only(left: 4),
              color: colors.glassInk.withValues(alpha: .12),
            ),
          row,
        ],
        if (track.url != null) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FmpButton(
                  key: const Key('track-info-open'),
                  label: t.trackInfo.openIn(source: source),
                  icon: FmpIcons.external,
                  onTap: () => trackActionRunner(context, ref)(
                    TrackAction.openInBrowser,
                    [track],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FmpButton(
                  key: const Key('track-info-copy'),
                  label: t.search.actions.copyLink,
                  icon: FmpIcons.copy,
                  onTap: () => trackActionRunner(context, ref)(
                    TrackAction.copyLink,
                    [track],
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 一列欄位（`.pl-kv`）：左邊 76 寬的灰色標籤，右邊值；15/20。
class _Row extends StatelessWidget {
  const _Row({required this.label, this.text, this.child});

  final String label;
  final String? text;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: 15,
          height: 20 / 15,
          letterSpacing: 0,
          color: colors.glassInk,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: Text(label, style: TextStyle(color: colors.glassInk2)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: child ?? Text(text!),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 載入中或載入失敗的一列：稿沒畫，用欄位的版面寫一句灰字。
class _Note extends StatelessWidget {
  const _Note({super.key, required this.text, this.busy = false, this.action});

  final String text;
  final bool busy;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
      child: Row(
        children: [
          if (busy) ...[
            SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.glassInk2,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                height: 20 / 14,
                letterSpacing: 0,
                color: colors.glassInk2,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
