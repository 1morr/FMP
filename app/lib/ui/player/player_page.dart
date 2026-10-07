import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/domain/playback_speed.dart';
import 'package:fmp/domain/player_tab.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/ui/artwork/artwork_image.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/layout_state.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/player/glass_panel.dart';
import 'package:fmp/ui/player/player_controls.dart';
import 'package:fmp/ui/player/queue_view.dart';
import 'package:fmp/ui/player/track_details.dart';
import 'package:fmp/ui/shell/focus_regions.dart';
import 'package:fmp/ui/shell/now_playing_panel.dart';
import 'package:fmp/ui/shell/playback_shortcuts.dart';
import 'package:fmp/ui/shell/shell_shortcuts.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 播放頁（ADR 0024 §決定 4，design §9.3、§9.5、§9.6）：全螢幕、推在根 Navigator 上，
/// 所以提示（`ToastHost` 包住 Navigator）仍在它上面。
///
/// 版面依整個視窗的 `WindowClass`：
/// - compact、medium：封面與歌詞切換（點封面或按 Ctrl+L），控制在下方；佇列在右上角
///   「佇列」鈕（或 Ctrl+Q）開的底部面板（[showQueueSheet]）；
/// - expanded、large：左右各半。左是封面、曲名、進度與控制，右是分頁「歌詞｜佇列｜詳細」；
/// - extraLarge：三欄約 1：1.15：0.9，封面與控制｜歌詞｜分頁「佇列｜詳細」。
///
/// 背景是模糊的封面加遮罩，控制區與右欄是毛玻璃（[GlassPanel]）。
///
/// 關閉：左上角的收合鈕、Esc（頁面自己的 `Shortcuts`；對話框與選單照 Flutter 內建先
/// 關）、Android 返回鍵（route 先 pop，只關這一頁）。佇列變空或沒有目前這首時自己關閉。
///
/// 焦點分區：控制區｜（extraLarge 的）歌詞欄｜右欄分頁；F6 在頁內循環，Tab 只在區內。
/// 外殼的三區留在這頁底下不動。
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key, this.entry = PlayerPageEntry.none});

  /// 開啟時要先做的事（Ctrl+L、Ctrl+Q 開頁）。
  final PlayerPageEntry entry;

  /// 收合（關閉）鈕；測試與外殼以它找。
  static const closeKey = ValueKey('player-page-close');

  /// compact、medium 右上角的「佇列」鈕。
  static const queueKey = ValueKey('player-page-queue');

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

/// 開啟播放頁時順便要做的事。
enum PlayerPageEntry { none, lyrics, queue }

/// Esc：關閉播放頁。
final class ClosePlayerPageIntent extends Intent {
  const ClosePlayerPageIntent();
}

/// 播放頁在最上層（外殼之上）。外殼以它決定提示的底部位移：播放頁蓋住了播放列與導覽，
/// 提示只需要避開底部安全區（ADR 0023 §決定 2）；同時是 Ctrl+L、Ctrl+Q 判斷「已經開了」
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
Future<void> openPlayerPage(
  BuildContext context, {
  FocusNode? opener,
  PlayerPageEntry entry = PlayerPageEntry.none,
}) async {
  final container = ProviderScope.containerOf(context);
  if (container.read(playerPageOpenProvider)) return;
  opener ??= FocusManager.instance.primaryFocus;
  final route = _PlayerPageRoute(
    entry: entry,
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

/// 全螢幕的播放頁 route；push 時通知 [onOpenChanged] 開了，pop 或被移除
/// （`removeRoute`）時通知關了，各一次。
final class _PlayerPageRoute extends MaterialPageRoute<void> {
  _PlayerPageRoute({
    required PlayerPageEntry entry,
    required this.onOpenChanged,
  }) : super(
         fullscreenDialog: true,
         settings: const RouteSettings(name: 'player-page'),
         builder: (_) => PlayerPage(entry: entry),
       );

  final void Function(bool open) onOpenChanged;

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
  final _lyrics = FocusScopeNode(debugLabel: 'Player page lyrics');
  final _tabs = FocusScopeNode(debugLabel: 'Player page tabs');
  final _lyricsTarget = FocusNode(debugLabel: 'Player page lyrics column');

  /// 這次開著的期間使用者選的分頁；還沒選過用記住的（資料庫的值要等一下才讀出來）。
  PlayerTab? _selected;

  /// compact、medium：顯示歌詞而不是封面。
  var _lyricsFace = false;

  /// compact、medium 的佇列底部面板開著（Ctrl+Q 不再開第二個）。
  var _queueSheetOpen = false;

  @override
  void initState() {
    super.initState();
    if (widget.entry != PlayerPageEntry.none) {
      // 要等第一次 build 之後才知道視窗等級。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (widget.entry) {
          case PlayerPageEntry.lyrics:
            _showLyrics();
          case PlayerPageEntry.queue:
            _showQueue();
          case PlayerPageEntry.none:
            break;
        }
      });
    }
  }

  @override
  void dispose() {
    for (final node in [_controls, _lyrics, _tabs, _lyricsTarget]) {
      node.dispose();
    }
    super.dispose();
  }

  // ---- 分頁 -----------------------------------------------------------------

  /// 目前顯示的分頁：使用者選的，沒選過是記住的，再沒有是歌詞。extraLarge 沒有歌詞分頁，
  /// 記住的（或選的）是歌詞時顯示佇列，但不覆寫記憶。
  PlayerTab _tabOf(WindowClass windowClass) {
    final tab =
        _selected ??
        ref.watch(layoutStateProvider.select((s) => s.value?.playerTab)) ??
        PlayerTab.lyrics;
    return windowClass == WindowClass.extraLarge && tab == PlayerTab.lyrics
        ? PlayerTab.queue
        : tab;
  }

  void _select(PlayerTab tab) {
    setState(() => _selected = tab);
    unawaited(
      ref.read(layoutStateRepositoryProvider).write(playerTab: tab).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        ref
            .read(logProvider)
            .report(
              'Failed to remember the player tab',
              AppError.wrap(error, stackTrace),
              tag: 'layout',
            );
      }),
    );
  }

  bool get _hasTabs => switch (WindowClass.of(context)) {
    WindowClass.expanded || WindowClass.large || WindowClass.extraLarge => true,
    WindowClass.compact || WindowClass.medium => false,
  };

  /// Ctrl+L：右欄切到歌詞；extraLarge 的歌詞是一欄，焦點移過去；compact、medium 切到歌詞
  /// 那一面。
  void _showLyrics() {
    switch (WindowClass.of(context)) {
      case WindowClass.compact || WindowClass.medium:
        setState(() => _lyricsFace = true);
      case WindowClass.expanded || WindowClass.large:
        _select(PlayerTab.lyrics);
      case WindowClass.extraLarge:
        focusInto(_lyrics);
    }
  }

  /// Ctrl+Q：右欄切到佇列；compact、medium 的佇列是底部面板。
  void _showQueue() {
    if (_hasTabs) {
      _select(PlayerTab.queue);
    } else {
      unawaited(_openQueueSheet());
    }
  }

  Future<void> _openQueueSheet() async {
    if (_queueSheetOpen) return;
    _queueSheetOpen = true;
    try {
      await showQueueSheet(context);
    } finally {
      _queueSheetOpen = false;
    }
  }

  void _close() => unawaited(Navigator.of(context).maybePop());

  /// 播放頁還在這個 route 上才移除它：佇列清空的當下可能還有對話框蓋在上面。
  void _removeSelf() {
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
  }

  // ---- 版面 -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    ref.listen(
      playbackQueueProvider.select((queue) => queue.value?.current != null),
      (_, hasTrack) {
        if (!hasTrack) _removeSelf();
      },
    );
    final queue = ref.watch(playbackQueueProvider).value;
    final track = queue?.current;
    if (queue == null || track == null) {
      // 佇列在頁面第一次 build 之前就空了時，上面的 listen 看不到那次改變；不留下一個
      // 沒有收合鈕的空白頁。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _removeSelf();
      });
      return const SizedBox.shrink();
    }
    final windowClass = WindowClass.of(context);
    final tab = _tabOf(windowClass);
    final scheme = Theme.of(context).colorScheme;
    final spacing = AppTokens.of(context).spacing;

    Widget region(FocusScopeNode node, Widget child) => FocusScope(
      node: node,
      child: FocusTraversalGroup(child: child),
    );
    Widget panel(Widget child) => Padding(
      padding: EdgeInsets.all(spacing.x4),
      child: GlassPanel(child: child),
    );
    final left = region(
      _controls,
      _MainColumn(
        track: track,
        queue: queue,
        onClose: _close,
        // compact、medium 的歌詞那一面在這一欄裡；更寬的版面歌詞在別欄。
        lyricsFace: !_hasTabs && _lyricsFace,
        onOpenQueue: _hasTabs ? null : () => unawaited(_openQueueSheet()),
        onToggleFace: _hasTabs
            ? null
            : () => setState(() => _lyricsFace = !_lyricsFace),
      ),
    );
    final body = switch (windowClass) {
      WindowClass.compact || WindowClass.medium => left,
      WindowClass.expanded || WindowClass.large => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          Expanded(
            child: region(
              _tabs,
              panel(
                _PlayerTabs(
                  key: const ValueKey('tabs-3'),
                  tabs: PlayerTab.values,
                  selected: tab,
                  onSelected: _select,
                  track: track,
                  queue: queue,
                ),
              ),
            ),
          ),
        ],
      ),
      // 約 1：1.15：0.9。
      WindowClass.extraLarge => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 100, child: left),
          Expanded(
            flex: 115,
            child: region(
              _lyrics,
              panel(Focus(focusNode: _lyricsTarget, child: const _NoLyrics())),
            ),
          ),
          Expanded(
            flex: 90,
            child: region(
              _tabs,
              panel(
                _PlayerTabs(
                  key: const ValueKey('tabs-2'),
                  tabs: const [PlayerTab.queue, PlayerTab.details],
                  selected: tab,
                  onSelected: _select,
                  track: track,
                  queue: queue,
                ),
              ),
            ),
          ),
        ],
      ),
    };

    final regions = [
      _controls,
      if (windowClass == WindowClass.extraLarge) _lyrics,
      if (_hasTabs) _tabs,
    ];
    return PlaybackShortcuts(
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): ClosePlayerPageIntent(),
          SingleActivator(LogicalKeyboardKey.f6): NextRegionIntent(),
        },
        child: Actions(
          actions: {
            ClosePlayerPageIntent: CallbackAction<ClosePlayerPageIntent>(
              onInvoke: (_) => _close(),
            ),
            NextRegionIntent: CallbackAction<NextRegionIntent>(
              onInvoke: (_) => focusNextRegion(regions),
            ),
            ShowLyricsIntent: TextInputAwareAction<ShowLyricsIntent>(
              onInvoke: (_) => _showLyrics(),
            ),
            ShowQueueIntent: TextInputAwareAction<ShowQueueIntent>(
              onInvoke: (_) => _showQueue(),
            ),
          },
          // 一開始就有焦點在頁面裡，快捷鍵才收得到按鍵；它不在 Tab 的順序裡。
          child: Focus(
            autofocus: true,
            skipTraversal: true,
            child: Material(
              color: scheme.surface,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Backdrop(track: track),
                  SafeArea(child: body),
                ],
              ),
            ),
          ),
        ),
      ),
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
        ImageFiltered(
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
        // 遮罩用主題的 `surface` 而不是黑色：淺色主題下深色封面不會把毛玻璃底下墊黑，
        // 上面的深色字才有足夠的對比；深色主題下它本來就是深色。
        ColoredBox(
          color: scheme.surface.withValues(alpha: AppLayout.playerScrimOpacity),
        ),
      ],
    );
  }
}

/// 封面欄（左欄）：頂端的收合鈕、封面、毛玻璃上的曲名、進度與控制。compact、medium 時
/// 封面可以換成歌詞。
class _MainColumn extends ConsumerWidget {
  const _MainColumn({
    required this.track,
    required this.queue,
    required this.onClose,
    required this.lyricsFace,
    required this.onOpenQueue,
    required this.onToggleFace,
  });

  final TrackInfo track;
  final QueueState queue;
  final VoidCallback onClose;
  final bool lyricsFace;

  /// 右上角「佇列」鈕開底部面板；有分頁的版面沒有這顆鈕。
  final VoidCallback? onOpenQueue;

  /// 點封面（歌詞）切換；有分頁的版面沒有這個動作。
  final VoidCallback? onToggleFace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final spacing = AppTokens.of(context).spacing;
    final toggle = onToggleFace;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.all(spacing.x2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                key: PlayerPage.closeKey,
                tooltip: t.playerPage.closeTooltip,
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: onClose,
              ),
              if (onOpenQueue != null)
                IconButton(
                  key: PlayerPage.queueKey,
                  tooltip: t.playerPage.queueTooltip,
                  icon: const Icon(Icons.queue_music),
                  onPressed: onOpenQueue,
                ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.x4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = math.min(
                  AppLayout.playerArtworkMax,
                  math.min(constraints.maxWidth, constraints.maxHeight),
                );
                final face = lyricsFace
                    ? GlassPanel(child: const _NoLyrics())
                    : Center(
                        child: ArtworkImage(
                          pluginId: track.sourceTypeId,
                          artwork: track.artwork,
                          size: size,
                        ),
                      );
                if (toggle == null) return face;
                return Semantics(
                  button: true,
                  label: lyricsFace
                      ? t.playerPage.showArtworkTooltip
                      : t.playerPage.showLyricsTooltip,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(
                      AppTokens.of(context).radius.large,
                    ),
                    onTap: toggle,
                    child: face,
                  ),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(spacing.x4),
          child: GlassPanel(
            child: _Transport(track: track, queue: queue),
          ),
        ),
      ],
    );
  }
}

/// 曲名、上傳者與狀態、進度條、五個控制加「⋯」。
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
    final subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: EdgeInsets.all(spacing.x4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            track.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge,
          ),
          if (status != null || uploader != null)
            // 狀態在前、放不下就省略；狀態改變時讀出來（live region），不搶焦點。
            Semantics(
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
                      WidgetSpan(child: SizedBox(width: spacing.x2)),
                    if (uploader != null) TextSpan(text: uploader),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: subtitleStyle,
              ),
            ),
          const ProgressRow(),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ShuffleButton(enabled: queue.shuffleEnabled),
              const PreviousButton(),
              PlayPauseButton(state: state),
              NextButton(enabled: queue.hasNext),
              LoopButton(mode: queue.loopMode),
              const _MoreMenu(),
            ],
          ),
        ],
      ),
    );
  }
}

/// 「⋯」：播放速度（不持久化，重啟回到 1.0；design §7.6），以及 expanded 以上的
/// 「正在播放面板」勾選項（design §9.3；compact、medium 沒有面板）。
class _MoreMenu extends ConsumerWidget {
  const _MoreMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final speed = ref.watch(playbackSpeedProvider).value ?? 1.0;
    // 播放頁在根 Navigator 上，讀到的是整個視窗的等級。
    final hasPanel = hasNowPlayingPanel(WindowClass.of(context));
    final panelExpanded = ref.watch(panelExpandedProvider);
    return IconMenu(
      tooltip: t.player.more,
      icon: const Icon(Icons.more_horiz),
      menuChildren: [
        if (hasPanel)
          CheckboxMenuButton(
            value: panelExpanded,
            onChanged: (_) => rememberPanel(ref, expanded: !panelExpanded),
            child: Text(t.shell.panelMenuItem),
          ),
        SubmenuButton(
          leadingIcon: const Icon(Icons.speed),
          menuChildren: [
            for (final option in speedOptions)
              Semantics(
                selected: option == speed,
                child: MenuItemButton(
                  leadingIcon: Visibility.maintain(
                    visible: option == speed,
                    child: const Icon(Icons.check),
                  ),
                  onPressed: () => unawaited(
                    ref.read(playbackControllerProvider).setSpeed(option),
                  ),
                  child: Text(t.playerPage.speedValue(speed: option)),
                ),
              ),
          ],
          child: Text(t.playerPage.speed),
        ),
      ],
    );
  }
}

/// 歌詞：M2 一律是「沒有歌詞」（design §9.3；M7 接上內容）。
class _NoLyrics extends ConsumerWidget {
  const _NoLyrics();

  @override
  Widget build(BuildContext context, WidgetRef ref) => EmptyState(
    icon: Icons.lyrics_outlined,
    title: ref.watch(translationsProvider).playerPage.noLyrics,
  );
}

/// 右欄的分頁列與內容。分頁數不同（extraLarge 沒有歌詞）時以 key 換掉整個 state。
class _PlayerTabs extends ConsumerStatefulWidget {
  const _PlayerTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelected,
    required this.track,
    required this.queue,
  });

  final List<PlayerTab> tabs;
  final PlayerTab selected;
  final ValueChanged<PlayerTab> onSelected;
  final TrackInfo track;
  final QueueState queue;

  @override
  ConsumerState<_PlayerTabs> createState() => _PlayerTabsState();
}

class _PlayerTabsState extends ConsumerState<_PlayerTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(
    length: widget.tabs.length,
    vsync: this,
    initialIndex: _indexOf(widget.selected),
  );

  int _indexOf(PlayerTab tab) =>
      widget.tabs.indexOf(tab).clamp(0, widget.tabs.length - 1);

  @override
  void didUpdateWidget(_PlayerTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = _indexOf(widget.selected);
    if (_controller.index != index) _controller.index = index;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).playerPage;
    String label(PlayerTab tab) => switch (tab) {
      PlayerTab.lyrics => t.tabLyrics,
      PlayerTab.queue => t.tabQueue,
      PlayerTab.details => t.tabDetails,
    };
    final selected = widget.tabs[_indexOf(widget.selected)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _controller,
          onTap: (index) => widget.onSelected(widget.tabs[index]),
          tabs: [for (final tab in widget.tabs) Tab(text: label(tab))],
        ),
        Expanded(
          child: switch (selected) {
            PlayerTab.lyrics => const _NoLyrics(),
            PlayerTab.queue => const QueueView(),
            PlayerTab.details => TrackDetails(track: widget.track),
          },
        ),
      ],
    );
  }
}
