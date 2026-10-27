import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/playback_speed.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/playback/live_play.dart';
import 'package:fmp/playback/playback_providers.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/layout_state.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/library/add_to_playlist.dart';
import 'package:fmp/ui/player/audio_controls.dart';
import 'package:fmp/ui/player/player_controls.dart';
import 'package:fmp/ui/shell/now_playing_panel.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 播放頁的頂列（ADR 0035 §決定 3，P-01）：左邊收合，右邊依序是加入歌單、輸出裝置與音量
/// （平台能選輸出裝置時，也就是桌面）、資訊、「⋯」。直播沒有加入歌單。
class PlayerTopBar extends ConsumerWidget {
  const PlayerTopBar({
    super.key,
    required this.track,
    required this.live,
    required this.onClose,
    required this.onInfo,
    required this.infoOpen,
  });

  /// 目前的曲目（收聽直播時為 `null`）與直播資訊（沒在收聽為 `null`）。
  final TrackInfo? track;
  final LiveInfo? live;
  final VoidCallback onClose;

  /// 資訊鈕：窄版開底部面板，寬版開／關右側面板。
  final VoidCallback onInfo;

  /// 右側的詳細面板開著（資訊鈕顯示成選取）。
  final bool infoOpen;

  /// 收合（關閉）鈕與資訊鈕；測試與外殼以它找。
  static const closeKey = ValueKey('player-page-close');
  static const infoKey = ValueKey('player-page-info');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final spacing = AppTokens.of(context).spacing;
    final current = track;
    final selectsDevice = ref.watch(outputDeviceSelectionProvider);
    return Padding(
      padding: EdgeInsets.all(spacing.x2),
      child: Row(
        children: [
          IconButton(
            key: closeKey,
            tooltip: t.playerPage.closeTooltip,
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: onClose,
          ),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (current != null)
                    IconButton(
                      tooltip: t.shell.panelAddToPlaylistTooltip,
                      icon: const Icon(Icons.playlist_add),
                      onPressed: () =>
                          unawaited(showAddToPlaylist(context, [current])),
                    ),
                  if (selectsDevice) ...[
                    const OutputDeviceButton(),
                    const MuteButton(),
                    // 放不下時滑桿先縮短。
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppLayout.volumeSliderWidth,
                        ),
                        child: const VolumeSlider(),
                      ),
                    ),
                  ],
                  IconButton(
                    key: infoKey,
                    tooltip: t.playerPage.infoTooltip,
                    isSelected: infoOpen,
                    icon: const Icon(Icons.info_outline),
                    selectedIcon: const Icon(Icons.info),
                    onPressed: onInfo,
                  ),
                  PlayerMoreMenu(live: live != null),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「⋯」：播放速度（不持久化，重啟回到 1.0；design §7.6），以及 expanded 以上的
/// 「正在播放面板」勾選項（design §9.3；compact、medium 沒有面板）。直播（[live]）只有
/// 面板的勾選項：直播跟著實際時間，沒有播放速度；沒有項目時整顆鈕不放。
class PlayerMoreMenu extends ConsumerWidget {
  const PlayerMoreMenu({super.key, this.live = false});

  final bool live;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final speed = ref.watch(playbackSpeedProvider).value ?? 1.0;
    // 播放頁在根 Navigator 上，讀到的是整個視窗的等級。
    final hasPanel = hasNowPlayingPanel(WindowClass.of(context));
    if (live && !hasPanel) return const SizedBox.shrink();
    final panelExpanded = ref.watch(panelExpandedProvider);
    return IconMenu(
      tooltip: t.player.more,
      icon: const Icon(Icons.more_vert),
      menuChildren: [
        if (hasPanel)
          CheckboxMenuButton(
            value: panelExpanded,
            onChanged: (_) => rememberPanel(ref, expanded: !panelExpanded),
            child: Text(t.shell.panelMenuItem),
          ),
        if (!live)
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
