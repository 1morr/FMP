import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/platform/window_chrome.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/ui/now_playing/now_playing.dart';
import 'package:fmp/ui/shell/destination.dart';
import 'package:fmp/ui/track_info/track_info.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// 播放的快捷鍵（`docs/design/DESIGN.md`〈無障礙〉的鍵盤）：Space 播放／暫停、
/// ←／→ 倒退、快轉 [seekStep]、⌘←／⌘→（Windows 用 Ctrl）上一首、下一首、
/// ⌘I（Windows 用 Ctrl+I）打開目前曲目的曲目資訊；也管 ⌘,（Windows 用
/// Ctrl+,）打開設定，沒有目前曲目時也有作用。掛在
/// App 的根，任何頁面都有作用，不看焦點在哪；焦點在輸入框裡（字要打得進去、
/// 游標要能移）或在對話框與選單裡（那裡 Enter 確認）時不攔。
///
/// Space 一律是播放／暫停（照 Spotify、Apple Music 桌面版），所以鍵盤選到的
/// 按鈕要用 Enter 按下（`ShellButton.focusRadius`）。
class PlaybackShortcuts extends ConsumerStatefulWidget {
  const PlaybackShortcuts({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  /// App 的根 navigator（路由的）：[child] 在它外面，曲目資訊從這裡打開。
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<PlaybackShortcuts> createState() => _PlaybackShortcutsState();
}

class _PlaybackShortcutsState extends ConsumerState<PlaybackShortcuts> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent || !mounted) return false;
    final keyboard = HardwareKeyboard.instance;
    final repeat = event is KeyRepeatEvent;
    if (!repeat &&
        WindowChrome.shortcut(LogicalKeyboardKey.comma)
            .accepts(event, keyboard)) {
      return _openSettings();
    }
    VoidCallback? action;
    if (!repeat && _plain(LogicalKeyboardKey.space).accepts(event, keyboard)) {
      action = _playPause;
    } else if (_plain(LogicalKeyboardKey.arrowLeft).accepts(event, keyboard)) {
      action = () => _seekBy(-seekStep);
    } else if (_plain(LogicalKeyboardKey.arrowRight).accepts(event, keyboard)) {
      action = () => _seekBy(seekStep);
    } else if (!repeat &&
        WindowChrome.shortcut(LogicalKeyboardKey.arrowLeft)
            .accepts(event, keyboard)) {
      action = _previous;
    } else if (!repeat &&
        WindowChrome.shortcut(LogicalKeyboardKey.arrowRight)
            .accepts(event, keyboard)) {
      action = _next;
    } else if (!repeat &&
        WindowChrome.shortcut(LogicalKeyboardKey.keyI)
            .accepts(event, keyboard)) {
      action = _trackInfo;
    }
    if (action == null || _focusWantsKeys()) return false;
    if (ref.read(playbackProvider) == null) return false;
    action();
    return true;
  }

  /// 沒有修飾鍵的 [key]。
  static SingleActivator _plain(LogicalKeyboardKey key) =>
      SingleActivator(key, includeRepeats: true);

  /// 焦點在輸入框、對話框或選單裡：鍵留給它們。
  static bool _focusWantsKeys() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null || !context.mounted) return false;
    if (context.widget is EditableText ||
        context.findAncestorStateOfType<EditableTextState>() != null) {
      return true;
    }
    return ModalRoute.of(context) is PopupRoute;
  }

  /// 打開設定（`docs/design/DESIGN.md`〈無障礙〉的 ⌘,）：從播放頁也換過去。
  /// 輸入框裡照樣有作用（⌘, 在輸入框沒有別的意思）；對話框與選單開著時不攔。
  bool _openSettings() {
    final context = widget.navigatorKey.currentContext;
    final focus = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    if (focus != null && focus.mounted && ModalRoute.of(focus) is PopupRoute) {
      return false;
    }
    GoRouter.of(context).go(Destination.settings.path);
    return true;
  }

  void _trackInfo() {
    final track = ref.read(playbackProvider)?.track;
    final context = widget.navigatorKey.currentContext;
    if (track == null || context == null) return;
    showTrackInfo(context, track);
  }

  void _playPause() => ref.read(playbackProvider.notifier).playPause();

  void _seekBy(Duration delta) {
    final state = ref.read(playbackProvider);
    if (state == null) return;
    ref
        .read(playbackProvider.notifier)
        .seek(clampPosition(state.position + delta, state.effectiveDuration));
  }

  void _previous() {
    if (!ref.read(skipAvailableProvider).previous) return;
    ref.read(queueProvider.notifier).previous();
  }

  void _next() {
    if (!ref.read(skipAvailableProvider).next) return;
    ref.read(queueProvider.notifier).next();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
