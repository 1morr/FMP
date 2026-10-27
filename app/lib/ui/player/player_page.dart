import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/track_info.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/playback/live_play.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/player/live_widgets.dart';
import 'package:fmp/ui/player/player_controls.dart';
import 'package:fmp/ui/player/player_top_bar.dart';
import 'package:fmp/ui/player/track_details.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/shell/focus_regions.dart';
import 'package:fmp/ui/shell/open_queue.dart';
import 'package:fmp/ui/shell/playback_shortcuts.dart';
import 'package:fmp/ui/shell/shell_shortcuts.dart';
import 'package:fmp/ui/shell/window_title_bar.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 播放頁的三種版面（ADR 0035 §決定 3，design §4）。
enum PlayerLayout {
  /// 寬 >= 840 且高 >= 520。M7 之前沒有歌詞，所以單欄置中（內容寬上限 720）；M7 加歌詞時
  /// 改成左 5 份封面與控制、右 7 份歌詞（design §4）。
  wide,

  /// 單欄：封面在上、控制在下。
  narrow,

  /// 寬大於高而高 < 520（橫向手機）：左封面、右控制。
  short,
}

/// [size]（整個視窗）該用哪一套版面。
PlayerLayout resolvePlayerLayout(Size size) {
  final isShort = size.height < AppLayout.playerWideMinHeight;
  if (!isShort && size.width >= AppLayout.playerWideMinWidth) {
    return PlayerLayout.wide;
  }
  return isShort && size.width > size.height
      ? PlayerLayout.short
      : PlayerLayout.narrow;
}

/// 播放頁（ADR 0035 §決定 3，design §4）：全螢幕、推在根 Navigator 上，所以提示
/// （`ToastHost` 包住 Navigator）仍在它上面。從底部上滑開啟、下滑關閉。
///
/// 版面看整個視窗的寬高（[PlayerLayout]）。頂列是收合、加入歌單、輸出裝置與音量（桌面）、
/// 資訊、「⋯」（[PlayerTopBar]）；資訊在窄版開底部面板、寬版開右側滑入的面板，內容都是
/// [TrackDetails]。曲名置中粗體、80dp 實心播放鍵，沒有底板。歌詞 M7 才做，封面與歌詞的切換
/// 也在那時回來。
///
/// 佇列不在這一頁：它是外殼的導覽目的地（ADR 0035 §決定 2）；Ctrl+Q 關掉這一頁並切過去。
///
/// 背景是模糊的封面加遮罩。
///
/// 關閉：左上角的收合鈕、Esc（頁面自己的 `Shortcuts`；對話框與選單照 Flutter 內建先
/// 關；右側詳細面板開著時先關面板）、Android 返回鍵（route 先 pop，只關這一頁）。
/// 佇列變空或沒有目前這首時自己關閉。
///
/// 焦點分區：控制區｜（開著時的）右側詳細面板；F6 在頁內循環，Tab 只在區內。
/// 外殼的三區留在這頁底下不動。
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});

  /// 收合（關閉）鈕；測試與外殼以它找。
  static const closeKey = PlayerTopBar.closeKey;

  /// 資訊鈕。
  static const infoKey = PlayerTopBar.infoKey;

  /// 寬版右側滑入的詳細面板與它的關閉鈕。
  static const detailsPanelKey = ValueKey('player-page-details-panel');
  static const closeDetailsKey = ValueKey('player-page-details-close');

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

/// Esc：關閉播放頁。
final class ClosePlayerPageIntent extends Intent {
  const ClosePlayerPageIntent();
}

/// 播放頁在最上層（外殼之上）。外殼以它決定提示的底部位移：播放頁蓋住了播放列與導覽，
/// 提示只需要避開底部安全區（ADR 0023 §決定 2）；同時是 Ctrl+L 判斷「已經開了」
/// 的依據。由 [openPlayerPage] 開的 route 在 push、pop、移除時設定。
final playerPageOpenProvider = NotifierProvider<PlayerPageOpen, bool>(
  PlayerPageOpen.new,
);

final class PlayerPageOpen extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool open) => state = open;
}

/// 開播放頁：推在根 Navigator 上。已經開著就什麼都不做。關閉之後（轉場結束）焦點回到
/// [opener]（沒給就是開的當下有焦點的元件）。
Future<void> openPlayerPage(BuildContext context, {FocusNode? opener}) async {
  final container = ProviderScope.containerOf(context);
  if (container.read(playerPageOpenProvider)) return;
  opener ??= FocusManager.instance.primaryFocus;
  final route = _PlayerPageRoute(
    onOpenChanged: (open) =>
        container.read(playerPageOpenProvider.notifier).set(open),
  );
  await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  // 開它的元件還在樹上才還；整個外殼重建過就算了。關閉的轉場中又開了一個播放頁
  // （轉場中的頁面不收點擊，點擊落到播放列）時不還，否則焦點被拉出新的那一頁。
  if (opener != null &&
      opener.parent != null &&
      opener.canRequestFocus &&
      !container.read(playerPageOpenProvider)) {
    opener.requestFocus();
  }
}

/// 全螢幕的播放頁 route：從底部上滑（`easeOutCubic`），關閉時下滑（`easeInCubic`），同舊版
/// `router.dart`；系統要求減少動態時改成淡入淡出。push 時通知 [onOpenChanged] 開了，pop 或
/// 被移除（`removeRoute`）時通知關了，各一次。
final class _PlayerPageRoute extends PageRouteBuilder<void> {
  _PlayerPageRoute({required this.onOpenChanged})
    : super(
        fullscreenDialog: true,
        settings: const RouteSettings(name: 'player-page'),
        transitionDuration: AppLayout.playerTransition,
        reverseTransitionDuration: AppLayout.playerTransition,
        pageBuilder: (_, _, _) => const PlayerPage(),
        transitionsBuilder: _transition,
      );

  final void Function(bool open) onOpenChanged;

  static Widget _transition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: curved, child: child);
    }
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(curved),
      child: child,
    );
  }

  var _open = false;

  void _report(bool open) {
    if (_open == open) return;
    _open = open;
    onOpenChanged(open);
  }

  @override
  TickerFuture didPush() {
    _report(true);
    return super.didPush();
  }

  // pop 與 `removeRoute`（佇列清空時自己關閉）都經過這裡，而且是當下：等到轉場結束、
  // dispose 時才報的話，那之前又開的新播放頁會被這個舊的標成「沒開」。
  @override
  void didComplete(void result) {
    _report(false);
    super.didComplete(result);
  }

  // 沒有 complete 就被丟掉（整個 Navigator 拆掉）時。
  @override
  void dispose() {
    _report(false);
    super.dispose();
  }
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  final _controls = FocusScopeNode(debugLabel: 'Player page controls');
  final _details = FocusScopeNode(debugLabel: 'Player page details');

  /// 使用者打開了寬版右側的詳細面板。只有寬版畫得出來，看 [_panelOpen]。
  var _detailsOpen = false;

  /// 上一次 build 的版面（視窗縮放時跟著換）。
  PlayerLayout? _layout;

  /// 右側詳細面板畫在畫面上：打開了而且是寬版。視窗縮到不是寬版時面板收掉，Esc 直接關頁面。
  bool get _panelOpen => _detailsOpen && _layout == PlayerLayout.wide;

  /// 窄版的詳細底部面板開著。
  var _sheetOpen = false;

  /// 那個底部面板的 route（建好之後才有）。
  ModalRoute<void>? _sheet;

  @override
  void dispose() {
    _controls.dispose();
    _details.dispose();
    super.dispose();
  }

  /// Ctrl+Q：關掉播放頁，轉場結束後請外殼切到佇列目的地（和在外殼按 Ctrl+Q 同一個結果）。
  /// 等 route 完成，才排在 [openPlayerPage] 把焦點還給開它的元件之後，焦點才落在佇列頁。
  Future<void> _showQueue() async {
    final route = ModalRoute.of(context);
    final openQueue = ref.read(openQueueProvider);
    _close();
    await route?.completed;
    openQueue();
  }

  /// 關這一頁（收合鈕、Esc 在面板收著時、Ctrl+Q）。不經頁面的 `PopScope`：它只讓返回鍵先關
  /// 面板，收合鈕與 Ctrl+Q 面板開著也關整頁（`maybePop` 會被它攔下，Ctrl+Q 就一直等不到
  /// route 完成）。上面還有別的 route 時照舊 `maybePop`，關的是最上面那一個。
  void _close() {
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    if (route != null && route.isCurrent) {
      navigator.pop();
    } else {
      unawaited(navigator.maybePop());
    }
  }

  /// Esc：右側詳細面板開著先關它，否則關頁面。
  void _escape() {
    if (_panelOpen) {
      _closeDetails();
    } else {
      _close();
    }
  }

  /// 關右側詳細面板。焦點在面板裡時不用另外處理：面板的 scope 拆掉後，焦點照 Flutter 的
  /// scope 記錄回到控制區上次的焦點。
  void _closeDetails() => setState(() => _detailsOpen = false);

  /// 播放頁還在這個 route 上才移除它：佇列清空的當下可能還有對話框蓋在上面。
  void _removeSelf() {
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) {
      // 窄版的詳細面板是另一個 route，蓋在播放頁上，一起移除。指名移除它而不是 pop：
      // 最上層可能是別的 route（例如提示開的錯誤詳細頁）。
      final sheet = _sheet;
      if (sheet != null && sheet.isActive) route.navigator?.removeRoute(sheet);
      route.navigator?.removeRoute(route);
    }
  }

  void _onInfo(PlayerLayout layout) {
    if (layout == PlayerLayout.wide) {
      setState(() => _detailsOpen = !_detailsOpen);
      return;
    }
    unawaited(_showSheet());
  }

  Future<void> _showSheet() async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) {
          _sheet = ModalRoute.of(sheetContext);
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: AppLayout.playerDetailsSheetInitial,
            minChildSize: AppLayout.playerDetailsSheetMin,
            maxChildSize: AppLayout.playerDetailsSheetMax,
            builder: (_, scrollController) =>
                _CurrentDetails(scrollController: scrollController),
          );
        },
      );
    } finally {
      _sheetOpen = false;
      _sheet = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      playbackQueueProvider.select((queue) => hasNowPlaying(queue.value)),
      (_, playing) {
        if (!playing) _removeSelf();
      },
    );
    final queue = ref.watch(playbackQueueProvider).value;
    final track = queue?.current;
    // 收聽直播時沒有曲目（`current` 是 `null`）：直播版（ADR 0031 §決定 7）。
    final live = ref.watch(nowPlayingLiveProvider);
    if (queue == null || (track == null && live == null)) {
      // 佇列在頁面第一次 build 之前就空了時，上面的 listen 看不到那次改變；不留下一個
      // 沒有收合鈕的空白頁。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _removeSelf();
      });
      return const SizedBox.shrink();
    }
    // 整個視窗的寬高（頁面就是全螢幕）。
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = resolvePlayerLayout(constraints.biggest);
        final scheme = Theme.of(context).colorScheme;
        final backdrop = live?.toTrackInfo() ?? track!;
        final transport = live != null
            ? _LiveTransport(info: live)
            : _Transport(track: track!, queue: queue);
        final cover = _Cover(
          pluginId: backdrop.sourceTypeId,
          artwork: backdrop.artwork,
        );
        final content = switch (layout) {
          PlayerLayout.wide => _WideContent(cover: cover, transport: transport),
          PlayerLayout.narrow => _NarrowContent(
            cover: cover,
            transport: transport,
          ),
          PlayerLayout.short => _ShortContent(
            cover: cover,
            transport: transport,
          ),
        };
        _layout = layout;
        final panelOpen = _panelOpen;

        final regions = [_controls, if (panelOpen) _details];
        final endIsLeft = Directionality.of(context) == TextDirection.rtl;
        final modifier = ref.watch(
          platformCapabilitiesProvider.select((c) => c.shortcutModifier),
        );
        return PlaybackShortcuts(
          child: Shortcuts(
            shortcuts: {
              const SingleActivator(LogicalKeyboardKey.escape):
                  const ClosePlayerPageIntent(),
              const SingleActivator(LogicalKeyboardKey.f6):
                  const NextRegionIntent(),
              // 導覽類，輸入框裡也有效（這一頁沒有輸入框）；外殼的 `Shortcuts` 不在這個 route 之上。
              ...queueShortcuts(modifier),
            },
            child: Actions(
              actions: {
                ClosePlayerPageIntent: CallbackAction<ClosePlayerPageIntent>(
                  onInvoke: (_) => _escape(),
                ),
                NextRegionIntent: CallbackAction<NextRegionIntent>(
                  onInvoke: (_) => focusNextRegion(regions),
                ),
                ShowQueueIntent: CallbackAction<ShowQueueIntent>(
                  onInvoke: (_) {
                    unawaited(_showQueue());
                    return null;
                  },
                ),
              },
              // 一開始就有焦點在頁面裡，快捷鍵才收得到按鍵；它不在 Tab 的順序裡。
              child: Focus(
                autofocus: true,
                skipTraversal: true,
                // 返回鍵同 Esc：右側詳細面板開著先關面板，否則放行（route pop，關這一頁）。這一頁是根
                // Navigator 上的 route，外殼的 `PopScope` 在下面的 route，不會同時動作。
                child: PopScope(
                  canPop: !panelOpen,
                  onPopInvokedWithResult: (didPop, _) {
                    if (!didPop) _closeDetails();
                  },
                  child: Material(
                    color: scheme.surface,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _Backdrop(track: backdrop),
                        // 頂列後面的空白處也能拖曳視窗（舊版 `immersive_player_scaffold.dart:82`）。
                        const PositionedDirectional(
                          top: 0,
                          start: 0,
                          end: 0,
                          height: AppLayout.playerDragAreaHeight,
                          child: WindowDragArea(),
                        ),
                        SafeArea(
                          child: FocusScope(
                            node: _controls,
                            child: FocusTraversalGroup(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  PlayerTopBar(
                                    track: track,
                                    live: live,
                                    onClose: _close,
                                    onInfo: () => _onInfo(layout),
                                    infoOpen: panelOpen,
                                  ),
                                  Expanded(child: content),
                                ],
                              ),
                            ),
                          ),
                        ),
                        PositionedDirectional(
                          top: 0,
                          bottom: 0,
                          end: 0,
                          width: AppLayout.playerDetailsPanelWidth,
                          // 面板貼著結尾那一邊：開頭那一邊不在螢幕邊緣，不留安全區。
                          child: SafeArea(
                            left: endIsLeft,
                            right: !endIsLeft,
                            child: AnimatedSwitcher(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : AppLayout.playerTransition,
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              layoutBuilder: (current, previous) => Stack(
                                fit: StackFit.expand,
                                children: [...previous, ?current],
                              ),
                              transitionBuilder: (child, animation) =>
                                  SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(1, 0),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                              child: panelOpen
                                  ? _DetailsPanel(
                                      key: PlayerPage.detailsPanelKey,
                                      node: _details,
                                      onClose: _closeDetails,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 寬版右側滑入的曲目詳細面板：標題、關閉鈕與 [TrackDetails]（直播是 [LiveDetails]）。
class _DetailsPanel extends ConsumerWidget {
  const _DetailsPanel({super.key, required this.node, required this.onClose});

  final FocusScopeNode node;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).playerPage;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    return FocusScope(
      node: node,
      child: FocusTraversalGroup(
        child: Material(
          color: theme.colorScheme.surfaceContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: spacing.x4,
                  end: spacing.x2,
                  top: spacing.x2,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          t.infoTooltip,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ),
                    IconButton(
                      key: PlayerPage.closeDetailsKey,
                      tooltip: t.closeInfoTooltip,
                      icon: const Icon(Icons.close),
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
              const Expanded(child: _CurrentDetails()),
            ],
          ),
        ),
      ),
    );
  }
}

/// 目前這首（或直播間）的詳細；換歌時跟著換。窄版的底部面板與寬版的側邊面板共用。
class _CurrentDetails extends ConsumerWidget {
  const _CurrentDetails({this.scrollController});

  /// 底部面板的捲動控制器（拖曳面板與捲動內容接在一起）。
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(playbackQueueProvider).value?.current;
    final live = ref.watch(nowPlayingLiveProvider);
    return switch ((live, track)) {
      (final live?, _) => LiveDetails(
        info: live,
        scrollController: scrollController,
      ),
      (_, final track?) => TrackDetails(
        track: track,
        scrollController: scrollController,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// 窄版：封面在上可伸縮，控制在下。
class _NarrowContent extends StatelessWidget {
  const _NarrowContent({required this.cover, required this.transport});

  final Widget cover;
  final Widget transport;

  @override
  Widget build(BuildContext context) {
    final spacing = AppTokens.of(context).spacing;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.x4,
        spacing.x2,
        spacing.x4,
        spacing.x6,
      ),
      child: Column(
        children: [
          Expanded(child: cover),
          SizedBox(height: spacing.x8),
          transport,
        ],
      ),
    );
  }
}

/// 寬版：窄版的單欄置中，內容寬上限 720。M7 加歌詞時在這裡改成 5:7 雙欄。
class _WideContent extends StatelessWidget {
  const _WideContent({required this.cover, required this.transport});

  final Widget cover;
  final Widget transport;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: AppLayout.playerContentMaxWide,
      ),
      child: _NarrowContent(cover: cover, transport: transport),
    ),
  );
}

/// 矮版（橫向手機）：左邊封面，右邊控制，控制放不下時可以捲動。
class _ShortContent extends StatelessWidget {
  const _ShortContent({required this.cover, required this.transport});

  final Widget cover;
  final Widget transport;

  @override
  Widget build(BuildContext context) {
    final spacing = AppTokens.of(context).spacing;
    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.x6, 0, spacing.x6, spacing.x4),
      child: Row(
        children: [
          Expanded(child: cover),
          SizedBox(width: spacing.x8),
          Expanded(
            child: Center(
              child: SingleChildScrollView(primary: false, child: transport),
            ),
          ),
        ],
      ),
    );
  }
}

/// 大封面（P-17）：邊長取可用寬高的較小值、上限 420，大圓角加陰影。
class _Cover extends StatelessWidget {
  const _Cover({required this.pluginId, required this.artwork});

  final String pluginId;
  final List<TrackArtwork> artwork;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppTokens.of(context).radius.large);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.max(
          0.0,
          math.min(
            AppLayout.playerArtworkMax,
            math.min(constraints.maxWidth, constraints.maxHeight),
          ),
        );
        return Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(
                    alpha: AppLayout.playerCoverShadowOpacity,
                  ),
                  blurRadius: AppLayout.playerCoverShadowBlur,
                  offset: const Offset(0, AppLayout.playerCoverShadowOffset),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: ArtworkImage(
                pluginId: pluginId,
                artwork: artwork,
                size: size,
                rounded: false,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 背景：模糊的封面加遮罩；沒有封面（或還在載入）是實色的佔位背景。
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.track});

  final TrackInfo track;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        // 模糊會往外溢出約 3 倍 sigma，不裁的話畫到頁面上方，蓋住 Windows 的自繪標題列。
        ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: AppLayout.playerBackdropBlur,
              sigmaY: AppLayout.playerBackdropBlur,
              tileMode: TileMode.clamp,
            ),
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: ArtworkImage(
                pluginId: track.sourceTypeId,
                artwork: track.artwork,
                size: AppLayout.playerBackdropSource,
                rounded: false,
                fallback: ColoredBox(color: scheme.surfaceContainerHighest),
              ),
            ),
          ),
        ),
        // 遮罩用主題的 `surface` 而不是黑色：淺色主題下深色封面不會把背景墊黑，
        // 上面的深色字才有足夠的對比；深色主題下它本來就是深色。
        ColoredBox(
          color: scheme.surface.withValues(alpha: AppLayout.playerScrimOpacity),
        ),
      ],
    );
  }
}

/// 直播版的控制區（ADR 0031 §決定 7）：直播標題、狀態與主播、標記與已收聽時間與人數，
/// 播放（暫停就是停止串流）、停止收聽。沒有進度條，也沒有上一首、下一首、隨機、循環。
class _LiveTransport extends ConsumerWidget {
  const _LiveTransport({required this.info});

  final LiveInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translations = ref.watch(translationsProvider);
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final state = ref.watch(playbackStateProvider).value ?? const Idle();
    final status = liveStatusLabel(
      translations,
      state,
      info,
      sourceName: ref.watch(pluginNameProvider(info.target.pluginId)),
    );
    final host = info.hostName;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Title(info.title),
        if (status != null || host != null)
          _StatusLine(
            status: status,
            uploader: host,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        SizedBox(height: spacing.x2),
        LiveFacts(info: info, alignment: WrapAlignment.center),
        SizedBox(height: spacing.x2),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PlayPauseButton(
              state: state,
              diameter: AppLayout.playerPlayButton,
              iconSize: AppLayout.playerPlayIcon,
            ),
            const StopLiveButton(),
          ],
        ),
      ],
    );
  }
}

/// 曲名：置中、粗體、最多兩行（P-02）。
class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.headlineSmall
        ?.copyWith(fontWeight: FontWeight.bold),
  );
}

/// 曲名下那一行：狀態（主色）在前、上傳者或主播在後，置中，放不下就省略；狀態改變時讀出來
/// （live region），不搶焦點。
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.status,
    required this.uploader,
    required this.style,
  });

  final String? status;
  final String? uploader;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = this.status;
    final uploader = this.uploader;
    return Semantics(
      liveRegion: status != null,
      child: Text.rich(
        TextSpan(
          children: [
            if (status != null)
              TextSpan(
                text: status,
                style: TextStyle(color: theme.colorScheme.primary),
              ),
            if (status != null && uploader != null)
              WidgetSpan(
                child: SizedBox(width: AppTokens.of(context).spacing.x2),
              ),
            if (uploader != null) TextSpan(text: uploader),
          ],
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

/// 曲名、上傳者與狀態、進度條、五個控制（P-02）：隨機、上一首、80dp 實心播放鍵、下一首、
/// 循環，均分整列寬度。
class _Transport extends ConsumerWidget {
  const _Transport({required this.track, required this.queue});

  final TrackInfo track;
  final QueueState queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).player;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final state = ref.watch(playbackStateProvider).value ?? const Idle();
    final previewing = ref.watch(playbackPreviewProvider).value ?? false;
    final status = playbackStatusLabel(t, state, previewing: previewing);
    final uploader = track.uploader;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Title(track.displayTitle),
        if (status != null || uploader != null)
          _StatusLine(
            status: status,
            uploader: uploader,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        SizedBox(height: spacing.x4),
        const ProgressRow(),
        SizedBox(height: spacing.x2),
        // 五個控制的自然寬度加起來約 288dp；比它窄（橫向手機的右半邊）就整排縮小，不 overflow。
        LayoutBuilder(
          builder: (context, constraints) => FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: math.max(
                constraints.maxWidth,
                AppLayout.playerControlsMinWidth,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ShuffleButton(
                    enabled: queue.shuffleEnabled,
                    locked: queue.mix != null,
                  ),
                  const PreviousButton(iconSize: AppLayout.playerSkipIcon),
                  PlayPauseButton(
                    state: state,
                    diameter: AppLayout.playerPlayButton,
                    iconSize: AppLayout.playerPlayIcon,
                  ),
                  NextButton(
                    enabled: queue.hasNext,
                    iconSize: AppLayout.playerSkipIcon,
                  ),
                  LoopButton(mode: queue.loopMode, inMix: queue.mix != null),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
