import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/accounts/account_guard.dart';
import 'package:fmp/playback/playback_events.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/layout_state.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/history/history_page.dart';
import 'package:fmp/ui/offline/offline.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/settings/settings_page.dart';
import 'package:fmp/ui/shell/focus_regions.dart';
import 'package:fmp/ui/shell/now_playing_panel.dart';
import 'package:fmp/ui/shell/playback_shortcuts.dart';
import 'package:fmp/ui/shell/shell_shortcuts.dart';
import 'package:fmp/ui/toast/toast_host.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// 外殼的導覽項。
enum ShellDestination { search, history, settings }

/// App 的外殼（ADR 0024 §決定 3、5、8）：導覽、內容、播放列三區。
///
/// 導覽依整個視窗的 `WindowClass` 換元件（M3 的 window size class 與導覽元件
/// 對照；用 Material 內建的三個元件，ADR 否決了 `flutter_adaptive_scaffold`）：
///
/// - compact：底部 `NavigationBar`，播放列在它上面；
/// - medium、expanded：左側 `NavigationRail`；
/// - large 以上：左側常駐的 `NavigationDrawer`。
///
/// 後兩種的播放列在內容區（與右側面板）下方、橫跨兩者（ADR 的「依內容區寬度」）。
/// 整個視窗 >= 840 時內容區右邊是「正在播放」面板與拖曳把手（[NowPlayingPanelSide]），
/// 頁面與播放列各自有 `WindowClassScope`，頁面讀到的是扣掉面板後的寬度等級。
///
/// 內容區頂端是全域離線提示（`OfflineBanner`，ADR 0016 §決定 7），換頁時
/// 留著。
///
/// 三區各是一個 `FocusScope`：Tab 只在區內循環，F6 換區（`shell_shortcuts.dart`；播放類快捷鍵在 `playback_shortcuts.dart`）。
/// 底部被外殼佔住的高度（播放列、底部導覽列、安全區）量出來發佈給
/// `toastBottomInsetProvider`，提示浮在它們上面（ADR 0023 §決定 2）。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  var _destination = ShellDestination.search;
  final _settingsBack = SettingsBack();

  final _navigation = FocusScopeNode(debugLabel: 'Shell navigation');
  final _content = FocusScopeNode(debugLabel: 'Shell content');
  final _playerBar = FocusScopeNode(debugLabel: 'Shell player bar');
  final _searchField = FocusNode(debugLabel: 'Search field');

  late final List<FocusScopeNode> _regions = [
    _navigation,
    _content,
    _playerBar,
  ];

  /// 外殼自己的底部被佔住的高度（最後一次量到的）；播放頁開著時提示不用它。
  double _measuredInset = 0;

  /// 量到外殼底部的高度。播放頁蓋在上面時不發佈：提示只需要避開底部安全區。
  void _publishInset(double height) {
    _measuredInset = height;
    if (!ref.read(playerPageOpenProvider)) {
      ref.read(toastBottomInsetProvider.notifier).set(height);
    }
  }

  /// 播放頁開著時提示貼底部安全區（ADR 0023 §決定 2），關掉時回到外殼量到的高度。
  void _onPlayerPageOpen(bool? previous, bool open) {
    ref
        .read(toastBottomInsetProvider.notifier)
        .set(open ? MediaQuery.viewPaddingOf(context).bottom : _measuredInset);
  }

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

  /// 搜尋頁的「前往插件頁」：換到設定頁並選「插件」區塊。
  void _openPlugins() {
    _select(ShellDestination.settings);
    _settingsBack.show(SettingsSection.plugins);
  }

  /// 憑證被音源拒絕：提示一次，附「登入」到設定頁的帳號區塊（design §6.5、ADR 0013 §決定 5）。
  void _onAccountInvalidated(
    AsyncValue<AccountInvalidated>? previous,
    AsyncValue<AccountInvalidated> next,
  ) {
    if (next case AsyncData(:final value)
        when !identical(previous?.value, value)) {
      final t = ref.read(translationsProvider).accounts;
      final name =
          ref.read(pluginNameProvider(value.pluginId)) ?? value.pluginId;
      ref
          .read(toasterProvider)
          .warning(
            t.invalidatedPrompt(name: name),
            action: ToastAction(label: t.signIn, onPressed: _openAccounts),
          );
    }
  }

  /// 失效提示的「登入」：換到設定頁並選「帳號」區塊。
  void _openAccounts() {
    if (!mounted) return;
    _select(ShellDestination.settings);
    _settingsBack.show(SettingsSection.accounts);
  }

  // ---- 快捷鍵（播放類在 PlaybackShortcuts）-----------------------------------

  /// F6：從焦點所在的區往下一區，跳過不在畫面上或沒有可聚焦項目的區。焦點
  /// 不在任何一區時從導覽開始。
  void _nextRegion() => focusNextRegion(_regions);

  void _openPlayer(PlayerPageEntry entry) {
    if (ref.read(playbackQueueProvider).value?.current == null) return;
    unawaited(openPlayerPage(context, entry: entry));
  }

  // ---- 播放的提示 -------------------------------------------------------------

  /// 播放控制器的一次性事件轉成提示（design §7.9）。在 listener 裡呼叫，不在
  /// build 裡：`Toaster` 同步送出，`ToastHost` 會馬上 `showSnackBar`。錯誤的
  /// 提示經 `Toaster.error`：先寫錯誤歷史，同類別＋同音源 5 秒內只顯示一次。
  void _onPlaybackEvent(
    AsyncValue<PlaybackEvent>? previous,
    AsyncValue<PlaybackEvent> next,
  ) {
    if (next case AsyncData(:final value)
        when !identical(previous?.value, value)) {
      final toaster = ref.read(toasterProvider);
      final t = ref.read(translationsProvider).player;
      switch (value) {
        case QueueFull(:final limit):
          toaster.warning(
            t.queueFull(
              // 千分位：三種介面語言都寫成 10,000。
              count: NumberFormat.decimalPattern('en').format(limit),
            ),
          );
        case TrackSkipped(:final error, :final track):
          toaster.error(
            error,
            operation: 'Track skipped',
            tag: 'playback',
            sentence: (reason) =>
                t.trackSkipped(title: track.title, reason: reason),
          );
        // 只有這一首播不了：說是哪一首、為什麼。
        case PlaybackStopped(:final error, :final track, failedInARow: 1):
          toaster.error(
            error,
            operation: 'Playback stopped',
            tag: 'playback',
            sentence: (reason) =>
                t.cannotPlay(title: track.title, reason: reason),
          );
        // 連續跳過到上限：每一首的原因已經在跳過時提示過（同類的被去重），
        // 這裡說停下來了。錯誤仍寫進錯誤歷史。
        case PlaybackStopped(:final error, :final failedInARow):
          ref
              .read(logProvider)
              .report('Playback stopped', error, tag: 'playback');
          toaster.warning(t.stoppedAfterFailures(count: failedInARow));
        case PreviewPlaying(:final track):
          toaster.info(t.previewPlaying(title: track.title));
        // 已經暫停（不跳過）；原因（mpv 的那一行）已由播放模組寫進 log。選過的
        // 裝置失敗時已改用系統預設；失敗的本來就是系統預設時只說已暫停。
        case OutputDeviceFailed(:final fellBack):
          toaster.warning(
            fellBack ? t.outputDeviceFellBack : t.outputDeviceFailed,
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(playbackEventsProvider, _onPlaybackEvent);
    ref.listen(accountInvalidationsProvider, _onAccountInvalidated);
    ref.listen(playerPageOpenProvider, _onPlayerPageOpen);
    // 記住的版面狀態先讀好，播放頁一開就是上次的分頁。
    ref.listen(layoutStateProvider, (_, _) {});
    final t = ref.watch(translationsProvider).shell;
    final hasTrack = ref.watch(
      playbackQueueProvider.select((queue) => queue.value?.current != null),
    );

    final windowClass = WindowClass.of(context);
    final hasPanel = hasNowPlayingPanel(windowClass);
    final pages = WindowClassScope(
      child: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: IndexedStack(
              index: _destination.index,
              sizing: StackFit.expand,
              children: [
                SearchPage(
                  fieldFocusNode: _searchField,
                  onOpenPlugins: _openPlugins,
                ),
                const HistoryPage(),
                SettingsPage(
                  visible: _destination == ShellDestination.settings,
                  back: _settingsBack,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    // 頁面與右側面板同在「內容」焦點區；頁面的 WindowClassScope 只量扣掉面板後的寬度。
    final content = FocusScope(
      node: _content,
      // 面板在頁面之後：F6 進來是頁面的第一個項目，Tab 走完頁面才到把手與面板。
      // 目前的版面裡預設的閱讀順序也是這樣（把手從頂端到底，同一帶裡由左而右），
      // 明訂順序是為了不依賴把手的形狀。結構不隨面板有無而變，視窗跨過 840 時
      // 頁面不重建（設定頁選的組、搜尋框的字都留著）。
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(0),
                child: pages,
              ),
            ),
            if (hasPanel)
              const FocusTraversalOrder(
                order: NumericFocusOrder(1),
                child: NowPlayingPanelSide(),
              ),
          ],
        ),
      ),
    );
    final playerBar = hasTrack
        ? FocusScope(
            node: _playerBar,
            child: FocusTraversalGroup(
              child: WindowClassScope(child: PlayerBar(panelToggle: hasPanel)),
            ),
          )
        : null;
    Widget navigation(Widget child) => FocusScope(
      node: _navigation,
      child: FocusTraversalGroup(child: child),
    );
    void onSelected(int index) => _select(ShellDestination.values[index]);
    final index = _destination.index;

    final body = switch (windowClass) {
      WindowClass.compact => Scaffold(
        body: SafeArea(bottom: false, child: content),
        bottomNavigationBar: _BottomInsetReporter(
          onHeight: _publishInset,
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
                      icon: const Icon(Icons.history_outlined),
                      selectedIcon: const Icon(Icons.history),
                      label: t.history,
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
      _ => Scaffold(
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
                      icon: const Icon(Icons.history_outlined),
                      selectedIcon: const Icon(Icons.history),
                      label: Text(t.history),
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
                history: t.history,
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
                    onHeight: _publishInset,
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

    // 返回鍵（design §9.1）：窄版設定頁點進某一組時先回到分組清單；否則不在第
    // 一個分頁時回到第一個分頁，在第一個分頁時放行
    // （根 route 沒得 pop，Android 端把 App 退到背景，見 MainActivity）。播放頁、
    // 面板與對話框是更上層的 route，Navigator 先關它們。
    return PopScope(
      canPop: _destination == ShellDestination.values.first,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _settingsBack.release()) return;
        _select(ShellDestination.values.first);
      },
      child: PlaybackShortcuts(
        child: Shortcuts(
          shortcuts: navigationShortcuts,
          child: Actions(
            actions: {
              FocusSearchIntent: CallbackAction<FocusSearchIntent>(
                onInvoke: (_) => _selectAndFocus(
                  ShellDestination.search,
                  _searchField.requestFocus,
                ),
              ),
              OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(
                onInvoke: (_) => _selectAndFocus(
                  ShellDestination.settings,
                  () => focusInto(_content),
                ),
              ),
              NextRegionIntent: CallbackAction<NextRegionIntent>(
                onInvoke: (_) => _nextRegion(),
              ),
              LeaveTextInputIntent: _LeaveTextInputAction(),
              // 播放頁沒開時 Ctrl+L、Ctrl+Q 先開播放頁（佇列不空才開）；開著時是頁面自己
              // 的 Actions 在處理（切分頁）。
              ShowLyricsIntent: TextInputAwareAction<ShowLyricsIntent>(
                onInvoke: (_) => _openPlayer(PlayerPageEntry.lyrics),
              ),
              ShowQueueIntent: TextInputAwareAction<ShowQueueIntent>(
                onInvoke: (_) => _openPlayer(PlayerPageEntry.queue),
              ),
            },
            // 一開始就有焦點在外殼裡，快捷鍵才收得到按鍵；它不在 Tab 的順序裡。
            child: Focus(autofocus: true, skipTraversal: true, child: body),
          ),
        ),
      ),
    );
  }
}

/// Esc：焦點在輸入框時離開它；沒有在輸入框就不處理（讓按鍵往上走）。
final class _LeaveTextInputAction extends Action<LeaveTextInputIntent> {
  @override
  bool isEnabled(LeaveTextInputIntent intent) => focusInTextInput();

  @override
  void invoke(LeaveTextInputIntent intent) =>
      FocusManager.instance.primaryFocus?.unfocus();
}

/// large 以上的常駐導覽抽屜。M3 的 standard drawer：和內容並排、沒有遮罩，
/// 所以不要 modal drawer 的圓角與陰影。
class _PermanentDrawer extends StatelessWidget {
  const _PermanentDrawer({
    required this.selectedIndex,
    required this.onSelected,
    required this.search,
    required this.history,
    required this.settings,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String search;
  final String history;
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
          icon: const Icon(Icons.history_outlined),
          selectedIcon: const Icon(Icons.history),
          label: Text(history),
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

/// 量 [child] 的高度交給 [onHeight]（外殼發佈成 `toastBottomInsetProvider`）：[child]
/// 貼著視窗底邊，所以它的高度就是從底邊算起被佔住的高度（含它自己處理的安全區）。
class _BottomInsetReporter extends StatelessWidget {
  const _BottomInsetReporter({required this.onHeight, required this.child});

  final ValueChanged<double> onHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) => _HeightReporter(
    // 在排版之後的那一幀結束才寫：排版與 build 中不能改 provider。
    onHeight: (height) => SchedulerBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) onHeight(height);
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
