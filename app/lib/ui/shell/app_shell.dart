import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/plugins/accounts/account_guard.dart';
import 'package:fmp/playback/playback_events.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/layout_state.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/home/home_page.dart';
import 'package:fmp/ui/legacy_import/legacy_import_result.dart';
import 'package:fmp/ui/library/library_page.dart';
import 'package:fmp/ui/offline/offline.dart';
import 'package:fmp/ui/player/live_widgets.dart';
import 'package:fmp/ui/player/player_bar.dart';
import 'package:fmp/ui/player/player_page.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/plugins/plugin_onboarding.dart';
import 'package:fmp/ui/queue/queue_page.dart';
import 'package:fmp/ui/radio/radio_page.dart';
import 'package:fmp/ui/search/search_page.dart';
import 'package:fmp/ui/settings/settings_page.dart';
import 'package:fmp/ui/shell/focus_regions.dart';
import 'package:fmp/ui/shell/legacy_side_rail.dart';
import 'package:fmp/ui/shell/now_playing_panel.dart';
import 'package:fmp/ui/shell/open_accounts.dart';
import 'package:fmp/ui/shell/open_queue.dart';
import 'package:fmp/ui/shell/page_app_bar.dart';
import 'package:fmp/ui/shell/open_search.dart';
import 'package:fmp/ui/shell/playback_shortcuts.dart';
import 'package:fmp/ui/shell/shell_shortcuts.dart';
import 'package:fmp/ui/toast/toast_host.dart';
import 'package:fmp/ui/toast/toaster.dart';

/// 外殼的導覽項，依畫面上的順序（ADR 0035 §決定 2：首頁｜搜尋｜音樂庫｜佇列｜電台｜設定；
/// 各寬度同一組）。三種導覽元件與內容區的 `IndexedStack` 都照這個順序；App 開在第一個。
enum ShellDestination { home, search, library, queue, radio, settings }

/// App 的外殼（ADR 0024 §決定 3、5、8）：導覽、內容、播放列三區。
///
/// 導覽依整個視窗的 `WindowClass` 換元件（ADR 0035 §決定 2；ADR 否決了 `flutter_adaptive_scaffold`）：
///
/// - compact：底部 `NavigationBar`，播放列在它上面；
/// - medium 以上：左側舊版的可展開側欄（[LegacySideRail]，收合 72dp、展開 256dp，各寬度同一個）。
///
/// 後者的播放列在內容區（與右側面板）下方、橫跨兩者（ADR 的「依內容區寬度」）。
/// 整個視窗 >= 840 時內容區右邊是「正在播放」面板與拖曳把手（[NowPlayingPanelSide]），
/// 頁面與播放列各自有 `WindowClassScope`，頁面讀到的是扣掉面板後的寬度等級。
///
/// 內容區頂端是全域離線提示（`OfflineBanner`，ADR 0016 §決定 7），換頁時
/// 留著。
///
/// 每個目的地有自己的巢狀 `Navigator`（ADR 0033 §決定 5）：內頁（歷史，之後的歌單詳情、
/// 探索）在內容區裡開，導覽與播放列留著。返回鍵與 Esc 先退出目前目的地的內頁；再點一次
/// 目前的導覽項回到那個目的地的根。全螢幕的頁（播放頁、Debug 頁、網頁登入、錯誤詳細）與
/// 對話框照舊開在根 Navigator 上，蓋住整個外殼。
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
  var _destination = ShellDestination.values.first;
  final _settingsBack = SettingsBack();

  /// 每個目的地的巢狀 Navigator，與它的觀察者（內頁開關時重建外殼：返回鍵的
  /// `PopScope.canPop` 要跟上）。
  final _navigators = {
    for (final destination in ShellDestination.values)
      destination: GlobalKey<NavigatorState>(
        debugLabel: 'Shell ${destination.name}',
      ),
  };
  late final _observers = {
    for (final destination in ShellDestination.values)
      destination: _StackObserver(_stackChanged),
  };

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
  void initState() {
    super.initState();
    // 歌單詳情的「登入」（design §5.3）：帳號區塊每個音源一張卡，整個區塊就看得到。
    ref.read(openAccountsProvider).handler = (_) => _openAccounts();
    // 播放頁開著時的 Ctrl+Q：播放頁關掉之後請外殼切到佇列。
    ref.read(openQueueProvider).handler = _openQueue;
    // 空狀態的「去搜尋」（佇列頁、巢狀導覽裡的歷史頁）。
    ref.read(openSearchProvider).handler = _openSearch;
    // 首次啟動匯入舊版資料之後，第一幀之後顯示一次結果（M5 design §7.3）。
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        showLegacyImportResult(
          context,
          ref,
          onInstallSources: () {
            // 首頁沒有音源時就是首次引導。
            ref.read(onboardingProvider.notifier).reopen();
            _select(ShellDestination.home);
          },
        ),
      );
    });
  }

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

  /// 換到 [destination]；已經在那裡時退回它的根（Material 導覽列再點一次目前項目的慣例）。
  /// 退到不放行的內頁（`PopScope(canPop: false)`：匯入預覽）就停下並交給它（`maybePop`，
  /// 它會先確認），不直接把它關掉。
  void _select(ShellDestination destination) {
    if (destination == _destination) {
      final navigator = _navigators[destination]!.currentState;
      if (navigator == null) return;
      Route<dynamic>? guarded;
      navigator.popUntil((route) {
        if (route.isFirst) return true;
        if (route.popDisposition != RoutePopDisposition.doNotPop) return false;
        guarded = route;
        return true;
      });
      // 只在停在不放行的內頁時才 `maybePop`：停在根頁時不動，根頁上的 `LocalHistoryEntry`（搜尋頁的多選）
      // 照舊留著。
      if (guarded != null) unawaited(navigator.maybePop());
    } else {
      setState(() => _destination = destination);
    }
  }

  /// 內頁開或關了：重建，讓 `PopScope.canPop` 跟上。根頁在建構中加入時也會通知，那時
  /// 不能 setState，排到這一幀之後。
  void _stackChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  /// 目前目的地的巢狀 Navigator 有內頁可以退。
  bool _canPopInner() =>
      _navigators[_destination]!.currentState?.canPop() ?? false;

  /// 退出目前目的地最上面的內頁；在根時回傳 `false`。
  bool _popInner() {
    final navigator = _navigators[_destination]!.currentState;
    if (navigator == null || !navigator.canPop()) return false;
    unawaited(navigator.maybePop());
    return true;
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

  /// 切到佇列目的地，焦點進內容區（Ctrl+Q；播放頁的 Ctrl+Q 也經這裡）。播放頁的那一條等
  /// 關閉轉場結束才呼叫，那時外殼可能已經拆了（[openQueueProvider] 還留著這個 handler）。
  void _openQueue() {
    if (!mounted) return;
    _selectAndFocus(ShellDestination.queue, () => focusInto(_content));
  }

  /// 空狀態的「去搜尋」：切到搜尋目的地。handler 留在 [openSearchProvider] 上，外殼拆了之後
  /// 才按到時什麼都不做。
  void _openSearch() {
    if (!mounted) return;
    _select(ShellDestination.search);
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
      // 同一個失敗接著以錯誤提示送來（搜尋、播放）時由 Toaster 去重，留下這則。
      ref
          .read(toasterProvider)
          .credentialInvalidated(
            value.pluginId,
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
    if (!hasNowPlaying(ref.read(playbackQueueProvider).value)) return;
    unawaited(openPlayerPage(context, entry: entry));
  }

  // ---- 播放的提示 -------------------------------------------------------------

  /// 因音源停用或未安裝而播不了時的原因。解析器對這種情況丟的 [Unsupported] 只有通用
  /// 訊息（「發生錯誤」），使用者要看到的是音源已停用／未安裝。
  String? _unavailableReason(AppError error) {
    final pluginId = error is Unsupported ? error.pluginId : null;
    return pluginId == null
        ? null
        : ref.read(sourceUnavailableProvider(pluginId));
  }

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
          final unavailable = _unavailableReason(error);
          toaster.error(
            error,
            operation: 'Track skipped',
            tag: 'playback',
            sentence: (reason) => t.trackSkipped(
              title: track.displayTitle,
              reason: unavailable ?? reason,
            ),
          );
        // 只有這一首播不了：說是哪一首、為什麼。
        case PlaybackStopped(:final error, :final track, failedInARow: 1):
          final unavailable = _unavailableReason(error);
          toaster.error(
            error,
            operation: 'Playback stopped',
            tag: 'playback',
            sentence: (reason) => t.cannotPlay(
              title: track.displayTitle,
              reason: unavailable ?? reason,
            ),
          );
        // 連續跳過到上限：每一首的原因已經在跳過時提示過（同類的被去重），
        // 這裡說停下來了。錯誤仍寫進錯誤歷史。
        case PlaybackStopped(:final error, :final failedInARow):
          ref
              .read(logProvider)
              .report('Playback stopped', error, tag: 'playback');
          toaster.warning(t.stoppedAfterFailures(count: failedInARow));
        case PreviewPlaying(:final track):
          toaster.info(t.previewPlaying(title: track.displayTitle));
        // 已經暫停（不跳過）；原因（mpv 的那一行）已由播放模組寫進 log。選過的
        // 裝置失敗時已改用系統預設；失敗的本來就是系統預設時只說已暫停。
        case OutputDeviceFailed(:final fellBack):
          toaster.warning(
            fellBack ? t.outputDeviceFellBack : t.outputDeviceFailed,
          );
      }
    }
  }

  /// 目的地的根頁（巢狀 Navigator 的第一頁）。
  Widget _rootPage(ShellDestination destination) => switch (destination) {
    ShellDestination.home => HomePage(
      onOpenPlugins: _openPlugins,
      onOpenLibrary: () => _select(ShellDestination.library),
      onOpenRadio: () => _select(ShellDestination.radio),
    ),
    ShellDestination.search => SearchPage(
      fieldFocusNode: _searchField,
      onOpenPlugins: _openPlugins,
    ),
    ShellDestination.library => const LibraryPage(),
    ShellDestination.queue => QueuePage(
      visible: _destination == ShellDestination.queue,
    ),
    ShellDestination.radio => const RadioPage(),
    ShellDestination.settings => SettingsPage(
      visible: _destination == ShellDestination.settings,
      back: _settingsBack,
    ),
  };

  @override
  Widget build(BuildContext context) {
    ref.listen(playbackEventsProvider, _onPlaybackEvent);
    ref.listen(accountInvalidationsProvider, _onAccountInvalidated);
    ref.listen(playerPageOpenProvider, _onPlayerPageOpen);
    // 記住的版面狀態先讀好，播放頁一開就是上次的分頁。
    ref.listen(layoutStateProvider, (_, _) {});
    final t = ref.watch(translationsProvider).shell;
    // 收聽直播時沒有曲目（`current` 是 `null`），播放列照樣在（直播版）。
    final hasTrack = ref.watch(
      playbackQueueProvider.select((queue) => hasNowPlaying(queue.value)),
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
                for (final destination in ShellDestination.values)
                  // 自己的語意容器：route 的 ModalBarrier 會擋掉同一個容器裡先畫的節點，不包的話
                  // 擋到的是導覽元件與離線提示，不只是下面那一頁。
                  Semantics(
                    container: true,
                    child: Navigator(
                      key: _navigators[destination],
                      observers: [_observers[destination]!],
                      // pages API：外殼重建時根頁跟著換成新的設定（設定頁的 `visible`）。
                      pages: [
                        MaterialPage<void>(
                          key: ValueKey(destination),
                          // 每一頁自己的 Material 與捲動觀察者（理由見 [PageSurface]）。推上來的內頁
                          // （`openPlaylist`、`openHistory`）同樣包。
                          child: PageSurface(child: _rootPage(destination)),
                        ),
                      ],
                      // 根頁不會被退掉：外殼的 PopScope 與 Esc 只在有內頁時才 pop。
                      onDidRemovePage: (_) {},
                    ),
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
    final destinations = [
      for (final destination in ShellDestination.values)
        _destinationLabel(destination, t),
    ];

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
                    for (final item in destinations)
                      NavigationDestination(
                        icon: Icon(item.icon),
                        selectedIcon: Icon(item.selectedIcon),
                        label: item.label,
                        tooltip: item.tooltip,
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
            navigation(
              LegacySideRail(
                selectedIndex: index,
                onSelected: onSelected,
                destinations: destinations,
              ),
            ),
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

    // 返回鍵（design §9.1、ADR 0033 §決定 5）：先退出目前目的地的內頁；在根時，窄版設定頁
    // 點進某一組時先回到分組清單；否則不在第一個目的地時回到第一個，在第一個時放行
    // （根 route 沒得 pop，Android 端把 App 退到背景，見 MainActivity）。播放頁、
    // 面板與對話框是根 Navigator 上更上層的 route，Navigator 先關它們。內頁的 route
    // 在巢狀 Navigator 裡、不在根 Navigator 上，所以返回鍵一定先到這裡。
    return PopScope(
      canPop: _destination == ShellDestination.values.first && !_canPopInner(),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _popInner() || _settingsBack.release()) return;
        _select(ShellDestination.values.first);
      },
      child: PlaybackShortcuts(
        child: Shortcuts(
          shortcuts: navigationShortcuts,
          child: Actions(
            actions: {
              FocusSearchIntent: CallbackAction<FocusSearchIntent>(
                onInvoke: (_) {
                  // 搜尋框在搜尋目的地的根頁：有內頁時先退回根。多選時選取列蓋住了搜尋框
                  // （ADR 0035 §決定 2），根頁還能退（選取模式的 LocalHistoryEntry）就先退出它。
                  final navigator =
                      _navigators[ShellDestination.search]!.currentState;
                  navigator?.popUntil((route) => route.isFirst);
                  if (navigator?.canPop() ?? false) {
                    unawaited(navigator!.maybePop());
                  }
                  _selectAndFocus(
                    ShellDestination.search,
                    _searchField.requestFocus,
                  );
                  return null;
                },
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
              EscapeIntent: _EscapeAction(
                onBack: _popInner,
                canBack: _canPopInner,
              ),
              // 播放頁沒開時 Ctrl+L 先開播放頁（佇列不空才開）；開著時是頁面自己的 Actions
              // 在處理（切分頁）。
              ShowLyricsIntent: TextInputAwareAction<ShowLyricsIntent>(
                onInvoke: (_) => _openPlayer(PlayerPageEntry.lyrics),
              ),
              // Ctrl+Q：切到佇列目的地（ADR 0035 §決定 7），焦點進內容區。
              ShowQueueIntent: TextInputAwareAction<ShowQueueIntent>(
                onInvoke: (_) => _openQueue(),
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

/// Esc：焦點在輸入框時離開它；不在輸入框時退出目前目的地的內頁；兩者都不是就不處理
/// （讓按鍵往上走）。
final class _EscapeAction extends Action<EscapeIntent> {
  _EscapeAction({required this.onBack, required this.canBack});

  final bool Function() onBack;
  final bool Function() canBack;

  @override
  bool isEnabled(EscapeIntent intent) => focusInTextInput() || canBack();

  @override
  void invoke(EscapeIntent intent) {
    if (focusInTextInput()) {
      FocusManager.instance.primaryFocus?.unfocus();
    } else {
      onBack();
    }
  }
}

ShellDestinationLabel _destinationLabel(
  ShellDestination destination,
  Translations$shell$zh_TW t,
) => switch (destination) {
  ShellDestination.home => (
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: t.home,
    tooltip: null,
  ),
  ShellDestination.search => (
    icon: Icons.search_outlined,
    selectedIcon: Icons.search,
    label: t.search,
    tooltip: t.searchTooltip,
  ),
  ShellDestination.library => (
    icon: Icons.library_music_outlined,
    selectedIcon: Icons.library_music,
    label: t.library,
    tooltip: null,
  ),
  ShellDestination.queue => (
    icon: Icons.queue_music_outlined,
    selectedIcon: Icons.queue_music,
    label: t.queue,
    tooltip: t.queueTooltip,
  ),
  ShellDestination.radio => (
    icon: Icons.radio_outlined,
    selectedIcon: Icons.radio,
    label: t.radio,
    tooltip: null,
  ),
  ShellDestination.settings => (
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: t.settings,
    tooltip: t.settingsTooltip,
  ),
};

/// 巢狀 Navigator 的內頁有增減時通知外殼。
final class _StackObserver extends NavigatorObserver {
  _StackObserver(this._changed);

  final VoidCallback _changed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _changed();
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
