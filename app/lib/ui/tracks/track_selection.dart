import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/library/add_to_playlist.dart';
import 'package:fmp/ui/shell/shell_shortcuts.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:fmp/ui/tracks/start_mix.dart';
import 'package:fmp/ui/tracks/track_row_menu.dart';

// 共用的多選（ADR 0033 §決定 10，M4 design §10.7）：歌單詳情、搜尋、歷史，之後的探索。
//
// 照 Android 的 contextual action mode（Gmail、Google 相簿、Files）：長按一列或選單的「選取」
// 進入；頂端換成選取列（取消、已選 n 首、全選、動作），點一列是勾選或取消，取消到一首都不剩、
// 做完一個動作、按取消、Esc 或返回鍵都離開。勾選框在列尾（M3 清單的 trailing checkbox），
// 取代「⋯」與拖曳把手：封面與分 P 的縮排不動。桌面另有 Ctrl+A 全選與 Shift＋點選的範圍
// （Gmail：起點是上一次點的那一列，範圍全部設成這一列點完的狀態）。
//
// 返回鍵與 Esc 不另放 `PopScope`：進入時在頁面的 route 加一個 `LocalHistoryEntry`
// （Flutter 給 Scaffold 抽屜用的機制），巢狀 Navigator 的 `canPop`／`maybePop` 先移除它，
// 外殼原本的處理（退內頁）就先離開選取模式，不用改。

/// 一頁的多選狀態：在不在選取模式、選了哪些（鍵 [K] 由頁面定，例如歌單項目的 id），
/// 範圍選取的起點。頁面的 State 建立、dispose，交給 [TrackSelectionScope]。
final class TrackSelection<K> extends ChangeNotifier {
  final _selected = <K>{};
  var _active = false;
  K? _anchor;

  /// 畫面上可選的鍵，依畫面順序；[TrackSelectionScope] 每次 build 時換成它的 `keys`。
  List<K> _order = const [];

  /// 在選取模式。
  bool get active => _active;

  /// 已選幾首。
  int get count => _selected.length;

  bool contains(K key) => _selected.contains(key);

  /// 畫面上可選的都選了。
  bool get allSelected => _order.isNotEmpty && _order.every(_selected.contains);

  /// 已選的鍵，依畫面順序（動作照這個順序加入）。
  List<K> get selected => [
    for (final key in _order)
      if (_selected.contains(key)) key,
  ];

  /// 進入選取模式，只選 [key]（長按、選單的「選取」）。
  void start(K key) {
    _active = true;
    _selected
      ..clear()
      ..add(key);
    _anchor = key;
    notifyListeners();
  }

  /// 選取模式裡點一列：切換 [key]。[range] 時（Shift＋點選）從上一次點的那一列到 [key] 都設成
  /// [key] 切換後的狀態。取消到一首都不剩就離開選取模式。
  void toggle(K key, {bool range = false}) {
    if (!_active) return;
    final select = !_selected.contains(key);
    final from = range && _anchor != null ? _order.indexOf(_anchor as K) : -1;
    final to = _order.indexOf(key);
    final keys = from < 0 || to < 0
        ? [key]
        : _order.sublist(from < to ? from : to, (from < to ? to : from) + 1);
    if (select) {
      _selected.addAll(keys);
    } else {
      _selected.removeAll(keys);
    }
    _anchor = key;
    if (_selected.isEmpty) return exit();
    notifyListeners();
  }

  /// 選畫面上可選的全部（Ctrl+A、選取列的「全選」）。
  void selectAll() {
    if (!_active || allSelected) return;
    _selected.addAll(_order);
    notifyListeners();
  }

  /// 離開選取模式（取消、Esc、返回鍵、做完一個動作）。
  void exit() {
    if (!_active) return;
    _active = false;
    _selected.clear();
    _anchor = null;
    notifyListeners();
  }

  /// 畫面上的列換了：不在 [keys] 裡的不再算選了；一首都不剩就離開選取模式。
  void _retain(List<K> keys) {
    if (!_active) return;
    final present = keys.toSet();
    final before = _selected.length;
    _selected.retainWhere(present.contains);
    if (_selected.isEmpty) return exit();
    if (_selected.length != before) notifyListeners();
  }
}

/// Ctrl+A：選取模式裡全選。
final class _SelectAllIntent extends Intent {
  const _SelectAllIntent();
}

/// Ctrl+A 只在選取模式內、焦點不在輸入框時作用；否則 `Shortcuts` 不處理，按鍵往上交給
/// 文字編輯（輸入框裡的全選）。
final class _SelectAllAction extends Action<_SelectAllIntent> {
  _SelectAllAction(this.selection);

  final TrackSelection<Object?> selection;

  @override
  bool isEnabled(_SelectAllIntent intent) =>
      selection.active && !focusInTextInput();

  @override
  void invoke(_SelectAllIntent intent) => selection.selectAll();
}

/// 包住一個有多選的頁面（標題列與清單都在裡面）：
///
/// - 把 [selection] 交給下面的 [TrackSelectionBar] 與 [SelectableTrackRow]；
/// - [keys] 是畫面上可選的列（依畫面順序），全選與範圍照它；列換了（刪掉、收起分 P）之後
///   不在裡面的不再算選了；
/// - 進入選取模式時在頁面的 route 加一個 `LocalHistoryEntry`：返回鍵與 Esc 經外殼的
///   「退出內頁」先移除它（離開選取模式），不另放 `PopScope`；
/// - Ctrl+A：選取模式時焦點要在頁面裡才收得到，所以進入與每次點選後，焦點不在頁面裡
///   （例如在播放列，或打開選單的「⋯」被換掉了）就移到頁面上一個不在 Tab 順序裡的節點；
///   焦點退到頁面外層（Esc 離開輸入框時 `unfocus` 退到 route 的焦點區）也放回這個節點。
///   列換了（[keys]）不是使用者點的，不搬焦點：上面可能開著對話框或播放頁。
class TrackSelectionScope<K> extends StatefulWidget {
  const TrackSelectionScope({
    super.key,
    required this.selection,
    required this.keys,
    required this.child,
  });

  final TrackSelection<K> selection;
  final List<K> keys;
  final Widget child;

  /// 最近的 [TrackSelectionScope] 的選取狀態；選取狀態變了就重建 [context]。
  static TrackSelection<K> of<K>(BuildContext context) {
    final selection = maybeOf<K>(context);
    assert(selection != null, 'No TrackSelectionScope<$K> above this widget');
    return selection!;
  }

  /// 同 [of]，不在 [TrackSelectionScope] 底下時是 `null`（拖曳中的列畫在 Overlay 裡）。
  static TrackSelection<K>? maybeOf<K>(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_SelectionInherited<K>>()
      ?.notifier;

  @override
  State<TrackSelectionScope<K>> createState() => _TrackSelectionScopeState<K>();
}

class _TrackSelectionScopeState<K> extends State<TrackSelectionScope<K>> {
  final _focus = FocusNode(debugLabel: 'Track selection', skipTraversal: true);
  ModalRoute<Object?>? _route;
  LocalHistoryEntry? _entry;

  /// 正在依新的 [TrackSelectionScope.keys] 剔除選取：這次通知不搬焦點。
  var _retaining = false;

  @override
  void initState() {
    super.initState();
    widget.selection.addListener(_changed);
    FocusManager.instance.addListener(_focusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void didUpdateWidget(TrackSelectionScope<K> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection) {
      oldWidget.selection.removeListener(_changed);
      widget.selection.addListener(_changed);
    }
    if (!listEquals(oldWidget.keys, widget.keys)) {
      // 不在 build 裡改選取狀態（它會通知別的 widget）：排到這一幀之後。
      final keys = widget.keys;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _retaining = true;
        try {
          widget.selection._retain(keys);
        } finally {
          _retaining = false;
        }
      });
    }
  }

  @override
  void dispose() {
    widget.selection.removeListener(_changed);
    FocusManager.instance.removeListener(_focusChanged);
    final entry = _entry;
    _entry = null;
    entry?.remove();
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    final selection = widget.selection;
    if (selection.active) {
      if (_entry == null) {
        final entry = LocalHistoryEntry(
          // 選取列取代了標題列（含返回鈕），頁面不必因此多一個返回鈕。
          impliesAppBarDismissal: false,
          onRemove: _removed,
        );
        _entry = entry;
        _route?.addLocalHistoryEntry(entry);
      }
      if (!_retaining) {
        SchedulerBinding.instance.addPostFrameCallback((_) => _focusInside());
      }
    } else {
      final entry = _entry;
      _entry = null;
      entry?.remove();
    }
  }

  /// 返回鍵或 Esc 移除了 route 上的那一筆：離開選取模式。
  void _removed() {
    if (_entry == null) return;
    _entry = null;
    widget.selection.exit();
  }

  void _focusInside() {
    if (!mounted || !widget.selection.active) return;
    final primary = FocusManager.instance.primaryFocus;
    if (primary == _focus || (primary?.ancestors.contains(_focus) ?? false)) {
      return;
    }
    _focus.requestFocus();
  }

  /// 選取模式裡焦點退到頁面的外層（Esc 離開搜尋框時 `unfocus` 把焦點交給 route 的焦點區）：
  /// 放回頁面，接著按 Ctrl+A 才收得到。退到別處（對話框、播放列、別的目的地）不管；頁面在
  /// `IndexedStack` 裡看不到時這個節點要不到焦點，`requestFocus` 什麼都不做。
  void _focusChanged() {
    if (!widget.selection.active) return;
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && _focus.ancestors.contains(primary)) {
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    widget.selection._order = widget.keys;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyA, control: true):
            _SelectAllIntent(),
      },
      child: Actions(
        actions: {_SelectAllIntent: _SelectAllAction(widget.selection)},
        child: Focus(
          focusNode: _focus,
          child: _SelectionInherited<K>(
            notifier: widget.selection,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _SelectionInherited<K> extends InheritedNotifier<TrackSelection<K>> {
  const _SelectionInherited({
    super.key,
    required super.notifier,
    required super.child,
  });
}

/// 選取列的一個頁面自己的動作（本機歌單詳情的「從歌單移除」；之後的遠端動作）。
@immutable
final class TrackSelectionAction<K> {
  const TrackSelectionAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;

  /// 也是按鈕的語意名稱。
  final String tooltip;

  /// 對已選的鍵（依畫面順序）做；回傳 `true` 時離開選取模式（做完了），`false` 留著（取消、
  /// 失敗）。
  final Future<bool> Function(List<K> keys) onPressed;
}

/// 頁面的標題列，選取模式時換成選取列（M3 的 contextual top app bar）：取消（Esc）、已選 n 首、
/// 全選（Ctrl+A）、加入佇列、加入歌單…，再接頁面自己的 [actions]。動作在進行中時其他鈕停用。
///
/// - 加入佇列：Mix 中停用並寫明原因（ADR 0031 §決定 9）；超過佇列上限時控制器整批拒絕、提示由
///   外殼接 `QueueFull`（ADR 0018 §決定 4），選取留著。
/// - 加入歌單…：開「加入歌單」對話框（PR 3），加入了才離開選取模式。
class TrackSelectionBar<K> extends ConsumerStatefulWidget {
  const TrackSelectionBar({
    super.key,
    required this.tracks,
    required this.child,
    this.actions = const [],
    this.padding,
  });

  /// 已選的鍵（依畫面順序）要加入的曲目；要先取東西的在這裡取（搜尋的多分 P 影片）。取不到
  /// 時自己提示並回 `null`，動作就不做、選取留著。
  final Future<List<TrackInfo>?> Function(List<K> keys) tracks;

  /// 不在選取模式時的標題列。
  final Widget child;

  final List<TrackSelectionAction<K>> actions;

  /// 選取列外面的間距；預設和頁面標題列一樣（上 16、下 8、左右 16）。
  final EdgeInsetsGeometry? padding;

  @override
  ConsumerState<TrackSelectionBar<K>> createState() =>
      _TrackSelectionBarState<K>();
}

class _TrackSelectionBarState<K> extends ConsumerState<TrackSelectionBar<K>> {
  /// 有動作在進行（取分 P、對話框、寫入）。
  var _running = false;

  Future<void> _run(
    TrackSelection<K> selection,
    Future<bool> Function(List<K> keys) action,
  ) async {
    setState(() => _running = true);
    try {
      if (await action(selection.selected)) selection.exit();
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<bool> _addToQueue(List<K> keys) async {
    final controller = ref.read(playbackControllerProvider);
    final toaster = ref.read(toasterProvider);
    final t = ref.read(translationsProvider).selection;
    final tracks = await widget.tracks(keys);
    if (tracks == null) return false;
    if (!controller.addToQueue(tracks)) return false;
    toaster.success(t.addedToQueue);
    return true;
  }

  Future<bool> _addToPlaylist(List<K> keys) async {
    final tracks = await widget.tracks(keys);
    if (tracks == null || !mounted) return false;
    return showAddToPlaylist(context, tracks);
  }

  @override
  Widget build(BuildContext context) {
    final selection = TrackSelectionScope.of<K>(context);
    if (!selection.active) return widget.child;
    final t = ref.watch(translationsProvider).selection;
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    final spacing = tokens.spacing;
    final colors = theme.colorScheme;
    final inMix = ref.watch(inMixProvider);
    final running = _running;

    VoidCallback? run(Future<bool> Function(List<K> keys) action) =>
        running ? null : () => unawaited(_run(selection, action));

    return Padding(
      padding:
          widget.padding ??
          EdgeInsets.fromLTRB(spacing.x4, spacing.x4, spacing.x4, spacing.x2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(tokens.radius.extraLarge),
        ),
        child: IconButtonTheme(
          data: IconButtonThemeData(
            style: IconButton.styleFrom(
              foregroundColor: colors.onSecondaryContainer,
            ),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: t.cancelTooltip,
                icon: const Icon(Icons.close),
                onPressed: selection.exit,
              ),
              SizedBox(width: spacing.x1),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    t.count(count: selection.count),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: t.selectAllTooltip,
                icon: const Icon(Icons.select_all),
                onPressed: running || selection.allSelected
                    ? null
                    : selection.selectAll,
              ),
              IconButton(
                tooltip: inMix ? t.addToQueueInMix : t.addToQueue,
                icon: const Icon(Icons.add_to_queue),
                onPressed: inMix ? null : run(_addToQueue),
              ),
              IconButton(
                tooltip: t.addToPlaylist,
                icon: const Icon(Icons.playlist_add),
                onPressed: run(_addToPlaylist),
              ),
              for (final action in widget.actions)
                IconButton(
                  tooltip: action.tooltip,
                  icon: Icon(action.icon),
                  onPressed: run(action.onPressed),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一列曲目在選取模式裡外的樣子，交給 [SelectableTrackRow.builder] 放進 `ListTile`。
@immutable
final class TrackRowSlots {
  const TrackRowSlots({
    required this.selecting,
    required this.selected,
    required this.trailing,
    required this.onTap,
    required this.onLongPress,
  });

  /// 在選取模式（列尾沒有「⋯」，拖曳把手之類的也不放）。
  final bool selecting;

  /// 這一列選了（給 `ListTile.selected`）。
  final bool selected;

  /// 放在列尾：平常是「⋯」，選取模式是勾選框。
  final Widget trailing;

  /// 選取模式是勾選或取消；平常是 `null`，列自己決定（臨時播放）。
  final VoidCallback? onTap;

  /// 平常是進入選取模式、選這一列；選取模式裡同點一下。
  final VoidCallback onLongPress;
}

/// 有多選的頁面裡的一列曲目。平常是 [TrackRowMenu]（右鍵與「⋯」開選單，選單最後多一項
/// 「選取」），長按進入選取模式；選取模式裡點一下（勾選框也一樣）是勾選或取消，Shift＋點選是
/// 範圍。選取模式的列是一個語意節點（`checked`），勾選框本身不另成節點、不在 Tab 順序裡。
/// 不在 [TrackSelectionScope] 底下時（`ReorderableListView` 拖著走的那一列畫在 Overlay 裡）
/// 是沒有「選取」的普通列。
class SelectableTrackRow<K> extends ConsumerWidget {
  const SelectableTrackRow({
    super.key,
    required this.selectionKey,
    required this.menuChildren,
    required this.moreTooltip,
    required this.builder,
  });

  final K selectionKey;

  /// 平常的選單項目；「選取」由這裡接在最後。
  final List<Widget> menuChildren;

  final String moreTooltip;

  /// 畫出一列（`ListTile`）：`trailing` 放 [TrackRowSlots.trailing]，`onTap` 是
  /// [TrackRowSlots.onTap]（空時用自己的），`onLongPress` 是 [TrackRowSlots.onLongPress]，
  /// `selected` 是 [TrackRowSlots.selected]。
  final Widget Function(BuildContext context, TrackRowSlots row) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = TrackSelectionScope.maybeOf<K>(context);
    final key = selectionKey;
    if (selection == null) {
      return TrackRowMenu(
        moreTooltip: moreTooltip,
        menuChildren: menuChildren,
        builder: (context, more, openMenu) => builder(
          context,
          TrackRowSlots(
            selecting: false,
            selected: false,
            trailing: more,
            onTap: null,
            onLongPress: openMenu,
          ),
        ),
      );
    }
    if (selection.active) {
      final selected = selection.contains(key);
      final colors = Theme.of(context).colorScheme;
      void toggle() => selection.toggle(
        key,
        range: HardwareKeyboard.instance.isShiftPressed,
      );
      return Semantics(
        container: true,
        checked: selected,
        child: ListTileTheme.merge(
          selectedColor: colors.onSecondaryContainer,
          selectedTileColor: colors.secondaryContainer,
          child: builder(
            context,
            TrackRowSlots(
              selecting: true,
              selected: selected,
              trailing: ExcludeFocus(
                child: ExcludeSemantics(
                  child: Checkbox(value: selected, onChanged: (_) => toggle()),
                ),
              ),
              onTap: toggle,
              onLongPress: toggle,
            ),
          ),
        ),
      );
    }
    void start() => selection.start(key);
    return TrackRowMenu(
      moreTooltip: moreTooltip,
      menuChildren: [
        ...menuChildren,
        MenuItemButton(
          leadingIcon: const Icon(Icons.check_box_outlined),
          onPressed: start,
          child: Text(ref.watch(translationsProvider).selection.select),
        ),
      ],
      builder: (context, more, openMenu) => builder(
        context,
        TrackRowSlots(
          selecting: false,
          selected: false,
          trailing: more,
          onTap: null,
          onLongPress: start,
        ),
      ),
    );
  }
}
