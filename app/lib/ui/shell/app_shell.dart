import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/settings/settings_page.dart';
import 'package:fmp/ui/shell/shell_shortcuts.dart';
import 'package:fmp/ui/toast/toast_host.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// 外殼的導覽項。
enum ShellDestination { search, settings }

/// App 的外殼（ADR 0024 §決定 3、5、8）：導覽、內容、播放列三區。
///
/// 導覽依整個視窗的 `WindowClass` 換元件（M3 的 window size class 與導覽元件
/// 對照；用 Material 內建的三個元件，ADR 否決了 `flutter_adaptive_scaffold`）：
///
/// - compact：底部 `NavigationBar`，播放列在它上面；
/// - medium、expanded：左側 `NavigationRail`；
/// - large 以上：左側常駐的 `NavigationDrawer`。
///
/// 後兩種的播放列在內容區下方、和內容區同寬（ADR 的「依內容區寬度」）。內容區
/// 與播放列各自有 `WindowClassScope`，頁面讀到的是自己那一塊的寬度等級。
///
/// 三區各是一個 `FocusScope`：Tab 只在區內循環，F6 換區（`shell_shortcuts.dart`）。
/// 底部被外殼佔住的高度（播放列、底部導覽列、安全區）量出來發佈給
/// `toastBottomInsetProvider`，提示浮在它們上面（ADR 0023 §決定 2）。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  var _destination = ShellDestination.search;

  final _navigation = FocusScopeNode(debugLabel: 'Shell navigation');
  final _content = FocusScopeNode(debugLabel: 'Shell content');
  final _playerBar = FocusScopeNode(debugLabel: 'Shell player bar');
  final _searchField = FocusNode(debugLabel: 'Search field');

  late final List<FocusScopeNode> _regions = [
    _navigation,
    _content,
    _playerBar,
  ];

  @override
  void dispose() {
    for (final node in [..._regions, _searchField]) {
      node.dispose();
    }
    super.dispose();
  }

  void _select(ShellDestination destination) {
    if (destination != _destination) setState(() => _destination = destination);
  }

  /// 換頁並在下一幀把焦點放進 [focus]（`IndexedStack` 換頁後，新頁的焦點才
  /// 不再被排除）。已經在那一頁時馬上放：不換頁就沒有重建，閒著時不會有下一幀。
  void _selectAndFocus(ShellDestination destination, void Function() focus) {
    if (destination == _destination) return focus();
    _select(destination);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) focus();
    });
  }

  // ---- 快捷鍵 ---------------------------------------------------------------

  void _playPause() {
    final controller = ref.read(playbackControllerProvider);
    switch (controller.state) {
      case Playing() || Loading() || Buffering() || Retrying():
        unawaited(controller.pause());
      case Idle() || Paused() || Failed():
        unawaited(controller.play());
    }
  }

  void _seekBy(Duration offset) {
    final progress = ref.read(playbackProgressProvider).value;
    if (progress == null) return;
    var target = progress.position + offset;
    if (target.isNegative) target = Duration.zero;
    final duration = progress.duration;
    if (duration != null && target > duration) target = duration;
    unawaited(ref.read(playbackControllerProvider).seek(target));
  }

  /// F6：從焦點所在的區往下一區，跳過不在畫面上或沒有可聚焦項目的區。焦點
  /// 不在任何一區時從導覽開始。
  void _nextRegion() {
    final focus = FocusManager.instance.primaryFocus;
    final current = focus == null
        ? -1
        : _regions.indexWhere(
            (region) => focus == region || focus.ancestors.contains(region),
          );
    for (var step = 1; step <= _regions.length; step++) {
      final region = _regions[(current + step) % _regions.length];
      if (_focusInto(region)) return;
    }
  }

  /// 回到 [region] 上次的焦點，沒有就是它的第一個可聚焦項目（樹的順序，三區
  /// 都是由上而下、由左而右排）。
  bool _focusInto(FocusScopeNode region) {
    if (region.context == null) return false;
    final previous = region.focusedChild;
    final target = previous != null && previous.canRequestFocus
        ? previous
        : region.traversalDescendants.firstOrNull;
    if (target == null) return false;
    target.requestFocus();
    return true;
  }

  // ---- 播放失敗的提示 ---------------------------------------------------------

  /// 播放停在 `Failed`（連續跳過到上限或最後一首也播不了）時提示一次。在
  /// listener 裡呼叫，不在 build 裡：`Toaster` 同步送出，`ToastHost` 會馬上
  /// `showSnackBar`。
  void _onPlaybackState(
    AsyncValue<PlaybackState>? previous,
    AsyncValue<PlaybackState> next,
  ) {
    if (next.value case Failed(:final error)
        when !identical(previous?.value, next.value)) {
      ref
          .read(toasterProvider)
          .error(error, operation: 'Playback stopped', tag: 'playback');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(playbackStateProvider, _onPlaybackState);
    final t = ref.watch(translationsProvider).shell;
    final hasTrack = ref.watch(
      playbackQueueProvider.select((queue) => queue.value?.current != null),
    );

    final content = FocusScope(
      node: _content,
      child: FocusTraversalGroup(
        child: WindowClassScope(
          child: IndexedStack(
            index: _destination.index,
            sizing: StackFit.expand,
            children: [
              SearchPage(fieldFocusNode: _searchField),
              const SettingsPage(),
            ],
          ),
        ),
      ),
    );
    final playerBar = hasTrack
        ? FocusScope(
            node: _playerBar,
            child: FocusTraversalGroup(
              child: const WindowClassScope(child: PlayerBar()),
            ),
          )
        : null;
    Widget navigation(Widget child) => FocusScope(
      node: _navigation,
      child: FocusTraversalGroup(child: child),
    );
    void onSelected(int index) => _select(ShellDestination.values[index]);
    final index = _destination.index;

    final body = switch (WindowClass.of(context)) {
      WindowClass.compact => Scaffold(
        body: SafeArea(bottom: false, child: content),
        bottomNavigationBar: _BottomInsetReporter(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?playerBar,
              navigation(
                NavigationBar(
                  selectedIndex: index,
                  onDestinationSelected: onSelected,
                  destinations: [
                    NavigationDestination(
                      icon: const Icon(Icons.search_outlined),
                      selectedIcon: const Icon(Icons.search),
                      label: t.search,
                      tooltip: t.searchTooltip,
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.settings_outlined),
                      selectedIcon: const Icon(Icons.settings),
                      label: t.settings,
                      tooltip: t.settingsTooltip,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      final windowClass => Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            navigation(switch (windowClass) {
              WindowClass.medium || WindowClass.expanded => SafeArea(
                right: false,
                child: NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: onSelected,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    NavigationRailDestination(
                      icon: const Icon(Icons.search_outlined),
                      selectedIcon: const Icon(Icons.search),
                      label: Text(t.search),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.settings_outlined),
                      selectedIcon: const Icon(Icons.settings),
                      label: Text(t.settings),
                    ),
                  ],
                ),
              ),
              _ => _PermanentDrawer(
                selectedIndex: index,
                onSelected: onSelected,
                search: t.search,
                settings: t.settings,
              ),
            }),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: SafeArea(
                      left: false,
                      bottom: playerBar == null,
                      child: content,
                    ),
                  ),
                  _BottomInsetReporter(
                    child: playerBar == null
                        ? const SizedBox.shrink()
                        : SafeArea(top: false, left: false, child: playerBar),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    };

    return Shortcuts(
      shortcuts: shellShortcuts,
      child: Actions(
        actions: {
          PlayPauseIntent: TextInputAwareAction<PlayPauseIntent>(
            onInvoke: (_) => _playPause(),
          ),
          PreviousTrackIntent: TextInputAwareAction<PreviousTrackIntent>(
            onInvoke: (_) =>
                unawaited(ref.read(playbackControllerProvider).previous()),
          ),
          NextTrackIntent: TextInputAwareAction<NextTrackIntent>(
            onInvoke: (_) =>
                unawaited(ref.read(playbackControllerProvider).next()),
          ),
          SeekByIntent: TextInputAwareAction<SeekByIntent>(
            onInvoke: (intent) => _seekBy(intent.offset),
          ),
          FocusSearchIntent: CallbackAction<FocusSearchIntent>(
            onInvoke: (_) => _selectAndFocus(
              ShellDestination.search,
              _searchField.requestFocus,
            ),
          ),
          OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(
            onInvoke: (_) => _selectAndFocus(
              ShellDestination.settings,
              () => _focusInto(_content),
            ),
          ),
          NextRegionIntent: CallbackAction<NextRegionIntent>(
            onInvoke: (_) => _nextRegion(),
          ),
        },
        // 一開始就有焦點在外殼裡，快捷鍵才收得到按鍵；它不在 Tab 的順序裡。
        child: Focus(autofocus: true, skipTraversal: true, child: body),
      ),
    );
  }
}

/// large 以上的常駐導覽抽屜。M3 的 standard drawer：和內容並排、沒有遮罩，
/// 所以不要 modal drawer 的圓角與陰影。
class _PermanentDrawer extends StatelessWidget {
  const _PermanentDrawer({
    required this.selectedIndex,
    required this.onSelected,
    required this.search,
    required this.settings,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String search;
  final String settings;

  @override
  Widget build(BuildContext context) => DrawerTheme(
    data: DrawerTheme.of(context)
        .copyWith(shape: const RoundedRectangleBorder()),
    child: NavigationDrawer(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      elevation: 0,
      children: [
        NavigationDrawerDestination(
          icon: const Icon(Icons.search_outlined),
          selectedIcon: const Icon(Icons.search),
          label: Text(search),
        ),
        NavigationDrawerDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: const Icon(Icons.settings),
          label: Text(settings),
        ),
      ],
    ),
  );
}

/// 量 [child] 的高度，發佈成 `toastBottomInsetProvider`：[child] 貼著視窗
/// 底邊，所以它的高度就是從底邊算起被佔住的高度（含它自己處理的安全區）。
class _BottomInsetReporter extends ConsumerWidget {
  const _BottomInsetReporter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _HeightReporter(
    // 在排版之後的那一幀結束才寫：排版與 build 中不能改 provider。
    onHeight: (height) => SchedulerBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        ref.read(toastBottomInsetProvider.notifier).set(height);
      }
    }),
    child: child,
  );
}

class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightReporter renderObject,
  ) => renderObject.onHeight = onHeight;
}

class _RenderHeightReporter extends RenderProxyBox {
  _RenderHeightReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (size.height != _reported) {
      _reported = size.height;
      onHeight(size.height);
    }
  }
}
