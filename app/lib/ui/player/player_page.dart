import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/glass/glass.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/platform/traffic_lights.dart';
import 'package:fmp/platform/window_chrome.dart';
import 'package:fmp/platform/window_drag.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/ui/common/cover.dart';
import 'package:fmp/ui/common/track_actions.dart';
import 'package:fmp/ui/player/ambient_colors.dart';
import 'package:fmp/ui/player/player_background.dart';
import 'package:fmp/ui/player/player_controls.dart';
import 'package:fmp/ui/player/player_queue.dart';
import 'package:fmp/ui/player/player_swipe.dart';
import 'package:fmp/ui/shell/caption_buttons.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:fmp/ui/toast/toast_layer.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// 桌面與橫向兩欄的右欄要不要顯示佇列（頂列右端的「佇列」開關）：預設開，
/// 這次開 App 期間記住。
final playerQueueShownProvider = NotifierProvider<PlayerQueueShown, bool>(
  PlayerQueueShown.new,
);

class PlayerQueueShown extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

/// 全螢幕播放頁（`docs/design/player.html`，`docs/design/DESIGN.md`〈播放頁
/// 音源膠囊〉）：蓋住整個外殼，背景是封面色場，上面一律白字。手機與平板直向
/// 是「佇列 ← 封面」左右滑（[PlayerSwipe]）；桌面、窄視窗與平板橫向是兩欄：
/// 左邊封面與控制，右邊佇列（頂列右端可關）。Esc、左上的收起或系統返回
/// 回原頁；手機也能往下拉收起。沒有目前曲目時（佇列清空）自己收起。
///
/// 還沒有的功能不出現入口：歌詞、加入歌單、曲目資訊、存取等級與音質、桌面的
/// 音量（還沒有音量控制）。
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  bool _closing = false;

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    final popped = await Navigator.of(context).maybePop();
    // 播放頁是第一頁（例如直接開到 `/player`）時回首頁。
    if (!popped && mounted) {
      _closing = false;
      context.go(Destination.home.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(playbackProvider.select((state) => state?.track));
    if (track == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _close();
      });
    }
    final shown = track ?? _lastTrack;
    _lastTrack = shown;
    final theme = Theme.of(context);
    final colors = context.fmpColors.onMedia;
    final ambient = switch (shown) {
      null => AmbientColors.fallback,
      final t =>
        ref.watch(ambientColorsProvider(t.largestCoverUrl)).value ??
            _lastAmbient ??
            AmbientColors.fallback,
    };
    _lastAmbient = ambient;
    final form = FormFactor.of(context);
    final size = MediaQuery.sizeOf(context);
    final touch = form.density == Density.touch;
    final swipe =
        form.widthClass == WidthClass.narrow ||
        (touch && size.height > size.width);
    // 色場上一律白字：狀態列圖示也用淺色。
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Theme(
        data: theme.copyWith(
          extensions: [colors, context.fmpText, context.fmpMetrics],
        ),
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
          child: Focus(
            autofocus: true,
            child: Material(
              type: MaterialType.transparency,
              child: Stack(
                children: [
                  Positioned.fill(child: PlayerBackground(colors: ambient)),
                  if (shown != null)
                    Positioned.fill(
                      child: swipe
                          ? PlayerSwipe(
                              track: shown,
                              tablet: form.widthClass != WidthClass.narrow,
                              topBar: _topBar(shown, touch: true),
                              onClose: _close,
                            )
                          : _Columns(
                              track: shown,
                              touch: touch,
                              wide: form.widthClass == WidthClass.wide,
                              topBar: _topBar(shown, touch: touch),
                            ),
                    ),
                  // 提示（例如「已複製連結」、播放失敗）浮在控制上方；手機在
                  // 音源膠囊上面，其他在視窗底部置中。
                  Positioned.fill(
                    child: ToastLayer(
                      bottom: swipe
                          ? MediaQuery.viewPaddingOf(context).bottom + 290
                          : 24,
                      stretch: form.widthClass == WidthClass.narrow,
                      touch: touch,
                      reportsFailures: false,
                    ),
                  ),
                  if (WindowChrome.insetTrafficLights && !swipe)
                    // 紅綠燈留在左上（`.side` 在 top 4、left 6，燈從 (8, 14) 起）。
                    const Positioned(
                      left: 6,
                      top: 4,
                      child: TrafficLightsArea(
                        spot: Offset(8, 14),
                        child: SizedBox(width: 80, height: 40),
                      ),
                    ),
                  if (WindowChrome.captionButtons)
                    const Positioned(top: 0, right: 0, child: CaptionButtons()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Track? _lastTrack;
  AmbientColors? _lastAmbient;

  PlayerTopButtons _topBar(Track track, {required bool touch}) =>
      PlayerTopButtons(track: track, touch: touch, onClose: _close);
}

/// 頂列兩端的玻璃圓鈕（`.pl-top`／`.pl-dtop`）：左邊收起、右邊 ⋮；排法由
/// 各版面自己決定（手機中間是播放來源，兩欄最右是「佇列」開關）。
class PlayerTopButtons {
  const PlayerTopButtons({
    required this.track,
    required this.touch,
    required this.onClose,
  });

  final Track track;
  final bool touch;
  final VoidCallback onClose;

  Widget collapse(BuildContext context) {
    final t = context.t;
    return GlassIconButton(
      key: const Key('player-collapse'),
      icon: FmpIcons.chevD,
      tooltip: touch
          ? t.player.collapse
          : t.player.collapseShortcut(key: 'Esc'),
      onTap: onClose,
      touch: touch,
      variant: GlassVariant.clear,
    );
  }

  /// ⋮：目前這首的「更多」，M1 只有複製連結與在瀏覽器開啟；曲目沒有網址時
  /// 不出現。
  Widget? more(BuildContext context, WidgetRef ref) {
    if (track.url == null) return null;
    return Builder(
      builder: (context) => GlassIconButton(
        key: const Key('player-more'),
        icon: FmpIcons.more,
        tooltip: context.t.queue.more,
        touch: touch,
        variant: GlassVariant.clear,
        onTap: () {
          final box = context.findRenderObject()! as RenderBox;
          showTrackActions(
            context,
            ref,
            track,
            at: box.localToGlobal(box.size.bottomRight(Offset.zero)),
            actions: const [TrackAction.copyLink, TrackAction.openInBrowser],
          );
        },
      ),
    );
  }
}

/// 頂列右端的「佇列」開關（`.pl-seg`，歌詞那段還沒有）：清玻璃膠囊裡一段，
/// 開著時 `--glass-press` 的底。
class _QueueToggle extends ConsumerWidget {
  const _QueueToggle({required this.touch});

  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final colors = context.fmpColors;
    final on = ref.watch(playerQueueShownProvider);
    final (height, padding, font, icon) = touch
        ? (38.0, 16.0, 15.0, 18.0)
        : (28.0, 14.0, 12.5, 14.0);
    return Glass(
      variant: GlassVariant.clear,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Semantics(
          toggled: on,
          child: ShellButton(
            key: const Key('player-queue-toggle'),
            onTap: ref.read(playerQueueShownProvider.notifier).toggle,
            focusRadius: 999,
            builder: (context, hovered) => AnimatedContainer(
              duration: FmpMotion.fast,
              height: height,
              padding: EdgeInsets.symmetric(horizontal: padding),
              decoration: BoxDecoration(
                color: on || hovered ? colors.glassPress : null,
                borderRadius: BorderRadius.circular(height / 2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FmpIcon(FmpIcons.queue, size: icon, color: colors.glassInk),
                  const SizedBox(width: 5),
                  Text(
                    t.player.queue,
                    style: TextStyle(
                      fontSize: font,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                      color: colors.glassInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 播放頁的大封面（`.pl-cover`／`.pl-dcover`）：圓角 14、浮起的陰影。用插件
/// 給的大圖，沒有就用縮圖。
class PlayerCover extends StatelessWidget {
  const PlayerCover({super.key, required this.track, required this.size});

  final Track track;
  final double size;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(context.fmpMetrics.radii.coverLarge),
      boxShadow: [
        BoxShadow(
          color: const Color.fromRGBO(0, 0, 0, .38),
          // 手機 0 24 50、桌面 0 30 60（`.pl-cover`、`.pl-dcover`）。
          offset: Offset(0, size > 340 ? 30 : 24),
          blurRadius: size > 340 ? 60 : 50,
        ),
      ],
    ),
    child: Cover(
      url: track.largestCoverUrl,
      size: size,
      radius: context.fmpMetrics.radii.coverLarge,
    ),
  );
}

/// 曲名與作者（`.pl-title`、`.pl-artist`）。
class PlayerTitle extends StatelessWidget {
  const PlayerTitle({
    super.key,
    required this.track,
    required this.titleSize,
    required this.artistSize,
    this.titleHeight,
    this.artistHeight,
  });

  final Track track;
  final double titleSize;
  final double artistSize;
  final double? titleHeight;
  final double? artistHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final text = context.fmpText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.title2.copyWith(
            fontSize: titleSize,
            height: titleHeight,
            fontWeight: FontWeight.w700,
            color: colors.label,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          track.author,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: artistSize,
            height: artistHeight,
            letterSpacing: 0,
            color: colors.label2,
          ),
        ),
      ],
    );
  }
}

/// 兩欄（桌面、窄視窗、平板橫向，`plDesk`／`plMid` 的兩欄版）：左欄封面、
/// 曲名作者、音源膠囊、進度、控制，在頂列與底邊之間垂直置中；右欄佇列。
/// 關掉佇列時左欄移到中間。
class _Columns extends ConsumerWidget {
  const _Columns({
    required this.track,
    required this.touch,
    required this.wide,
    required this.topBar,
  });

  final Track track;
  final bool touch;

  /// 寬級（桌面 1280）：左欄從 132、寬 380；否則是窄視窗（56、300）或平板（56、380）。
  final bool wide;
  final PlayerTopButtons topBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final density = PlayerDensity(touch: touch);
    final queueShown = ref.watch(playerQueueShownProvider);
    final (lx, lw, gap) = touch
        ? (56.0, 380.0, 84.0)
        : wide
        ? (132.0, 380.0, 108.0)
        : (56.0, 300.0, 64.0);
    final top0 = touch ? media.viewPadding.top : 0.0;
    // 左欄：頂 70、底 30（平板頂 96）；右欄：頂 64、底 28（平板頂 90）。
    // 桌面照稿從頂 80 排起（`.pl-dcover`），窄視窗與平板在中間（`.pl-mlc`）。
    final topAligned = wide && !touch;
    final leftTop =
        top0 +
        (topAligned
            ? 80.0
            : touch
            ? 72.0
            : 70.0);
    final rightTop = top0 + (touch ? 66.0 : 64.0);
    final bottom = math.max(30.0, media.viewPadding.bottom);
    // 封面以外的高：曲名作者、音源膠囊、進度、控制與它們之間的距離。
    final rest = touch ? 237.0 : 214.0;
    final cover = math.max(
      120.0,
      math.min(lw, size.height - leftTop - bottom - rest),
    );
    final left = queueShown ? lx : (size.width - lw) / 2;
    final barTop = touch ? top0 + 6 : 10.0;
    final barHeight = touch ? 52.0 : 40.0;
    final more = topBar.more(context, ref);
    final column = SizedBox(
      width: lw,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: PlayerCover(track: track, size: cover),
          ),
          SizedBox(height: touch ? 18 : 16),
          PlayerTitle(
            track: track,
            titleSize: touch ? 24 : 21,
            titleHeight: touch ? 30 / 24 : 27 / 21,
            artistSize: touch ? 17 : 15,
            artistHeight: touch ? 22 / 17 : 20 / 15,
          ),
          SizedBox(height: touch ? 14 : 18),
          SignatureCapsule(density: density),
          SizedBox(
            height: (touch ? 12 : 19) - PlayerProgress.overhangOf(density),
          ),
          PlayerProgress(density: density),
          SizedBox(height: touch ? 6 : 0),
          PlayerControls(density: density),
        ],
      ),
    );
    final page = Stack(
      children: [
        AnimatedPositioned(
          // 減少動態效果時直接到位（`DESIGN.md`〈動態〉）。
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : FmpMotion.morph,
          curve: FmpMotion.morphCurve,
          left: left,
          top: leftTop,
          bottom: bottom,
          width: lw,
          child: Align(
            alignment: topAligned ? Alignment.topCenter : Alignment.center,
            child: column,
          ),
        ),
        if (queueShown)
          Positioned(
            left: lx + lw + gap,
            right: 28,
            top: rightTop + (touch ? 24 : 0),
            bottom: 28,
            child: PlayerQueue(
              column: true,
              touch: touch,
              note: wide && !touch,
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          top: barTop,
          height: barHeight,
          child: Padding(
            padding: EdgeInsets.only(
              left: touch ? 24 : (WindowChrome.insetTrafficLights ? 86 : 20),
              right: (touch ? 24 : 20) + WindowChrome.captionButtonsWidth,
            ),
            child: Row(
              children: [
                topBar.collapse(context),
                // 頂列中間寫播放來源（`DESIGN.md`〈播放頁音源膠囊〉的其他規則）。
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: PlayerContext(),
                  ),
                ),
                if (more != null) ...[more, const SizedBox(width: 8)],
                _QueueToggle(touch: touch),
              ],
            ),
          ),
        ),
      ],
    );
    return touch ? page : WindowDragArea(height: 50, child: page);
  }
}
