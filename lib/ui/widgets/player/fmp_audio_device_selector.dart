import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/audio/audio_player_selectors.dart';
import '../../../services/audio/audio_provider.dart';
import '../../../services/audio/audio_types.dart';

/// 音訊輸出設備選擇器（AppBar 用，僅桌面端），音樂/電台全螢幕播放器共用。
///
/// 兩個播放器頁面原本各自維護一份逐字相同的實作（含裝置名稱格式化）；
/// 抽出為單一元件以保證一致。是否顯示由呼叫端以
/// `DesktopAudioDeviceState.hasSelectableDevices` 判斷。
class FmpAudioDeviceSelector extends StatelessWidget {
  final DesktopAudioDeviceState state;
  final AudioController controller;
  final ColorScheme colorScheme;

  const FmpAudioDeviceSelector({
    super.key,
    required this.state,
    required this.controller,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final currentDevice = state.currentAudioDevice;
    final devices = state.audioDevices;

    // 計算選單寬度以便置中對齊。
    const menuWidth = 220.0;

    return MenuAnchor(
      consumeOutsideTap: true,
      // 向左偏移使選單置中於圖示，向下偏移使選單顯示在圖示下方。
      alignmentOffset: const Offset(-menuWidth / 2 + 20, 8),
      builder: (context, menuController, child) {
        return IconButton(
          icon: const Icon(Icons.speaker, size: 20),
          visualDensity: VisualDensity.compact,
          tooltip: t.player.audioDevice,
          onPressed: () {
            if (menuController.isOpen) {
              menuController.close();
            } else {
              menuController.open();
            }
          },
        );
      },
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: const WidgetStatePropertyAll(Size(menuWidth, 0)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusLg),
        ),
      ),
      menuChildren: [
        // 自動選項（跟隨系統預設）。
        MenuItemButton(
          onPressed: () => controller.setAudioDeviceAuto(),
          leadingIcon: currentDevice == null || currentDevice.name == 'auto'
              ? Icon(Icons.check, size: 18, color: colorScheme.primary)
              : const SizedBox(width: 18),
          child: Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Text(t.player.audioDeviceAuto),
          ),
        ),
        const Divider(height: 1),
        // 裝置列表。
        ...devices
            .where((d) => d.name != 'auto' && d.name != 'openal')
            .map((device) {
          final isSelected = currentDevice?.name == device.name;
          return MenuItemButton(
            onPressed: () => controller.setAudioDevice(device),
            leadingIcon: isSelected
                ? Icon(Icons.check, size: 18, color: colorScheme.primary)
                : const SizedBox(width: 18),
            child: Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Text(
                formatDeviceName(device),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        }),
      ],
    );
  }

  /// 格式化裝置名稱：優先 description，並去除 Windows「喇叭 (...)」外層。
  ///
  /// 優先使用 description（人類可讀名稱），若為空則使用 name。Windows 裝置
  /// 名稱通常為「喇叭 (裝置名稱)」，此處取出括號內的實際裝置名；英文格式為
  /// 「Speakers (Device Name)」同理處理。
  static String formatDeviceName(FmpAudioDevice device) {
    final displayName =
        device.description.isNotEmpty ? device.description : device.name;

    final match = RegExp(r'喇叭\s*\((.+)\)$').firstMatch(displayName);
    if (match != null) {
      return match.group(1) ?? displayName;
    }

    final matchEn = RegExp(r'Speakers?\s*\((.+)\)$', caseSensitive: false)
        .firstMatch(displayName);
    if (matchEn != null) {
      return matchEn.group(1) ?? displayName;
    }

    return displayName;
  }
}
