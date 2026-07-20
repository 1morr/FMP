import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/services/image_loading_service.dart';
import '../../../core/services/network_image_cache_service.dart';
import '../../../core/services/toast_service.dart';
import '../../../services/lyrics/lyrics_cache_service.dart';
import '../../../providers/lyrics/lyrics_window_style_provider.dart';
import '../../../providers/lyrics/lyrics_provider.dart';
import '../../../data/models/hotkey_config.dart';
import '../../../data/models/settings.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/audio/audio_settings_provider.dart';
import '../../../providers/settings/locale_provider.dart';
import '../../../providers/settings/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_preset_colors.dart';
import '../../../providers/download/download_settings_provider.dart';
import '../../../providers/settings/developer_options_provider.dart';
import '../../../providers/audio/playback_settings_provider.dart';
import '../../../providers/settings/refresh_settings_provider.dart';
import '../../../providers/settings/desktop_settings_provider.dart';
import '../../../providers/settings/hotkey_config_provider.dart';
import '../../../providers/library/library_invalidation_coordinator.dart';
import '../../../providers/download/download_path_provider.dart';
import '../../../providers/system/update_provider.dart';
import '../../../providers/system/backup_provider.dart';
import '../../../services/backup/backup_service.dart';
import '../../../services/backup/backup_data.dart';
import '../../router.dart';
import '../../widgets/dialogs/change_download_path_dialog.dart';
import '../../widgets/controls/color_palette_button.dart';
import '../../widgets/dialogs/update_dialog.dart';
import '../../../core/constants/ui_constants.dart';

part 'widgets/settings_appearance.dart';
part 'widgets/settings_playback.dart';
part 'widgets/settings_about.dart';
part 'widgets/settings_storage.dart';
part 'widgets/settings_cache.dart';
part 'widgets/settings_desktop.dart';
part 'widgets/settings_backup.dart';

/// 设置页
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 监听 locale 变化，确保切换语言时整个页面重建
    ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.settings.title),
      ),
      body: ListView(
        children: [
          // 帳號管理
          _SettingsSection(
            title: t.settings.account,
            children: [
              ListTile(
                leading: const Icon(Icons.manage_accounts),
                title: Text(t.settings.accountManagement.title),
                subtitle: Text(t.settings.accountManagement.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(RoutePaths.accountManagement),
              ),
            ],
          ),
          const Divider(),
          // 外观设置
          _SettingsSection(
            title: t.settings.appearance,
            children: [
              _ThemeModeListTile(),
              _ThemeColorListTile(),
              _FontFamilyListTile(),
              _LanguageListTile(),
            ],
          ),
          const Divider(),
          // 播放设置
          _SettingsSection(
            title: t.settings.playback,
            children: [
              ListTile(
                leading: const Icon(Icons.graphic_eq),
                title: Text(t.settings.audioQuality.title),
                subtitle: Text(t.settings.audioQuality.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(RoutePaths.audioSettings),
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(t.settings.playHistory.title),
                subtitle: Text(t.settings.playHistory.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(RoutePaths.history),
              ),
              _AutoScrollToPlayingTile(),
              _RememberPlaybackPositionTile(),
              _AutoMatchLyricsTile(),
            ],
          ),
          const Divider(),
          // 缓存设置
          _SettingsSection(
            title: t.settings.cache,
            children: [
              _ImageCacheSizeListTile(),
              _LyricsCacheSizeListTile(),
              ListTile(
                leading: const Icon(Icons.view_column_outlined),
                title: Text(t.settings.homeRankingSettings.title),
                subtitle: Text(t.settings.homeRankingSettings.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(RoutePaths.homeRankingSettings),
              ),
              _RankingRefreshIntervalListTile(),
              _RadioRefreshIntervalListTile(),
            ],
          ),
          const Divider(),
          // 存储设置
          _SettingsSection(
            title: t.settings.storage,
            children: [
              _DownloadManagerListTile(),
              _DownloadPathListTile(),
              _ConcurrentDownloadsListTile(),
              _DownloadImageOptionListTile(),
            ],
          ),
          const Divider(),
          // 数据备份
          _SettingsSection(
            title: t.settings.backup.title,
            children: [
              _ExportDataListTile(),
              _ImportDataListTile(),
            ],
          ),
          const Divider(),
          // 桌面设置（仅 Windows）
          if (Platform.isWindows)
            _SettingsSection(
              title: t.settings.desktop,
              children: [
                _LaunchAtStartupTile(),
                _MinimizeToTrayTile(),
                _GlobalHotkeysTile(),
              ],
            ),
          if (Platform.isWindows) const Divider(),
          // 关于
          _SettingsSection(
            title: t.settings.about,
            children: [
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(t.settings.userGuide.title),
                subtitle: Text(t.settings.userGuide.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(RoutePaths.userGuide),
              ),
              _CheckUpdateListTile(),
              _VersionListTile(),
              ListTile(
                leading: const Icon(Icons.code_outlined),
                title: Text(t.settings.openSource.title),
                subtitle: Text(t.settings.openSource.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final info = await PackageInfo.fromPlatform();
                  if (!context.mounted) return;
                  showLicensePage(
                    context: context,
                    applicationName: 'FMP',
                    applicationVersion: info.version,
                  );
                },
              ),
            ],
          ),
          // 开发者选项（隐藏入口，需要点击版本号7次解锁）
          _DeveloperOptionsSection(),
        ],
      ),
    );
  }
}

/// 设置区块
class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        ...children,
      ],
    );
  }
}
