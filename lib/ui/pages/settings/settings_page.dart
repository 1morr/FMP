import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/services/image_loading_service.dart';
import '../../../core/services/network_image_cache_service.dart';
import '../../../data/models/hotkey_config.dart';
import '../../../data/models/settings.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/locale_provider.dart';
import '../../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../../providers/download_settings_provider.dart';
import '../../../providers/developer_options_provider.dart';
import '../../../providers/playback_settings_provider.dart';
import '../../../providers/desktop_settings_provider.dart';
import '../../../providers/hotkey_config_provider.dart';
import '../../../providers/download_path_provider.dart';
import '../../../providers/update_provider.dart';
import '../../../providers/backup_provider.dart';
import '../../../providers/playlist_provider.dart';
import '../../../services/backup/backup_service.dart';
import '../../../services/backup/backup_data.dart';
import '../../router.dart';
import '../../widgets/change_download_path_dialog.dart';
import '../../widgets/update_dialog.dart';
import '../../../core/constants/ui_constants.dart';

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
            ],
          ),
          const Divider(),
          // 缓存设置
          _SettingsSection(
            title: t.settings.cache,
            children: [
              _ImageCacheSizeListTile(),
              _ClearImageCacheListTile(),
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
                _MinimizeToTrayTile(),
                _LaunchAtStartupTile(),
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

/// 主题模式选择
class _ThemeModeListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final themeName = switch (themeMode) {
      ThemeMode.system => t.settings.theme.followSystem,
      ThemeMode.light => t.settings.theme.light,
      ThemeMode.dark => t.settings.theme.dark,
    };

    return ListTile(
      leading: Icon(
        switch (themeMode) {
          ThemeMode.system => Icons.brightness_auto,
          ThemeMode.light => Icons.light_mode,
          ThemeMode.dark => Icons.dark_mode,
        },
      ),
      title: Text(t.settings.theme.title),
      subtitle: Text(themeName),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showThemeModeDialog(context, ref, themeMode),
    );
  }

  void _showThemeModeDialog(BuildContext context, WidgetRef ref, ThemeMode currentMode) {
    final systemBrightness = MediaQuery.platformBrightnessOf(context);
    final systemThemeName = systemBrightness == Brightness.dark
        ? t.settings.theme.dark
        : t.settings.theme.light;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settings.theme.selectTitle),
        content: RadioGroup<ThemeMode>(
          groupValue: currentMode,
          onChanged: (value) {
            if (value != null) {
              ref.read(themeProvider.notifier).setThemeMode(value);
            }
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<ThemeMode>(
                title: Text.rich(
                  TextSpan(
                    text: t.settings.theme.followSystem,
                    children: [
                      TextSpan(
                        text: ' ($systemThemeName)',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                secondary: const Icon(Icons.brightness_auto),
                value: ThemeMode.system,
              ),
              RadioListTile<ThemeMode>(
                title: Text(t.settings.theme.light),
                secondary: const Icon(Icons.light_mode),
                value: ThemeMode.light,
              ),
              RadioListTile<ThemeMode>(
                title: Text(t.settings.theme.dark),
                secondary: const Icon(Icons.dark_mode),
                value: ThemeMode.dark,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel),
          ),
        ],
      ),
    );
  }
}

/// 主题色选择
class _ThemeColorListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primaryColor = ref.watch(primaryColorProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: const Icon(Icons.color_lens_outlined),
      title: Text(t.settings.themeColor.title),
      subtitle: Text(primaryColor == null ? t.general.defaultLabel : t.general.custom),
      trailing: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: primaryColor ?? colorScheme.primary,
          shape: BoxShape.circle,
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      onTap: () => _showColorPickerDialog(context, ref, primaryColor),
    );
  }

  void _showColorPickerDialog(BuildContext context, WidgetRef ref, Color? currentColor) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settings.themeColor.selectTitle),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6750A4),
                    shape: BoxShape.circle,
                    border: currentColor == null
                        ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
                        : null,
                  ),
                ),
                title: Text(t.general.defaultLabel),
                selected: currentColor == null,
                onTap: () {
                  ref.read(themeProvider.notifier).setPrimaryColor(null);
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 16),
              // 预设颜色网格
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: presetColors.map((color) {
                  final isSelected = currentColor != null && currentColor.toARGB32() == color.toARGB32();
                  return InkWell(
                    onTap: () {
                      ref.read(themeProvider.notifier).setPrimaryColor(color);
                      Navigator.pop(context);
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(
                                color: Theme.of(context).colorScheme.onSurface,
                                width: 2,
                              )
                            : null,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.4),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: isSelected
                          ? Icon(
                              Icons.check,
                              color: ThemeData.estimateBrightnessForColor(color) == Brightness.dark
                                  ? Colors.white
                                  : Colors.black,
                              size: 20,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel),
          ),
        ],
      ),
    );
  }
}

/// 字体选择
class _FontFamilyListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontFamily = ref.watch(fontFamilyProvider);
    final fonts = AppTheme.availableFonts;
    final currentDisplay = fonts
        .where((f) => f.fontFamily == fontFamily)
        .map((f) => f.displayName)
        .firstOrNull ?? fontFamily ?? t.general.systemDefault;

    return ListTile(
      leading: const Icon(Icons.font_download_outlined),
      title: Text(t.settings.font.title),
      subtitle: Text(currentDisplay),
      onTap: () => _showFontDialog(context, ref, fontFamily),
    );
  }

  void _showFontDialog(BuildContext context, WidgetRef ref, String? currentFont) {
    final fonts = AppTheme.availableFonts;
    final systemFontName = Platform.isWindows ? 'Segoe UI' : 'Roboto';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settings.font.selectTitle),
        content: RadioGroup<String?>(
          groupValue: currentFont,
          onChanged: (value) {
            ref.read(themeProvider.notifier).setFontFamily(value);
            Navigator.pop(context);
          },
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: fonts.map((font) {
                return RadioListTile<String?>(
                  title: font.fontFamily == null
                      ? Text.rich(
                          TextSpan(
                            text: font.displayName,
                            children: [
                              TextSpan(
                                text: ' ($systemFontName)',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Text(
                          font.displayName,
                          style: TextStyle(fontFamily: font.fontFamily),
                        ),
                  subtitle: font.fontFamily != null
                      ? Text(font.fontFamily!, style: Theme.of(context).textTheme.bodySmall)
                      : null,
                  value: font.fontFamily,
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel),
          ),
        ],
      ),
    );
  }
}

/// 语言选择
class _LanguageListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = ref.watch(localeDisplayNameProvider);

    return ListTile(
      leading: const Icon(Icons.language_outlined),
      title: Text(t.settings.language.title),
      subtitle: Text(displayName),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showLanguageDialog(context, ref),
    );
  }

  void _showLanguageDialog(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.read(localeProvider);

    // Detect system language
    final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
    String systemLanguageName;
    if (systemLocale.languageCode == 'zh') {
      final isTraditional = systemLocale.scriptCode == 'Hant' ||
          systemLocale.countryCode == 'TW' ||
          systemLocale.countryCode == 'HK' ||
          systemLocale.countryCode == 'MO';
      systemLanguageName = isTraditional ? t.settings.traditionalChinese : t.settings.simplifiedChinese;
    } else if (systemLocale.languageCode == 'en') {
      systemLanguageName = t.settings.english;
    } else {
      systemLanguageName = systemLocale.languageCode;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settings.language.selectTitle),
        content: RadioGroup<AppLocale?>(
          groupValue: currentLocale,
          onChanged: (value) {
            ref.read(localeProvider.notifier).setLocale(value);
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<AppLocale?>(
                title: Text.rich(
                  TextSpan(
                    text: t.settings.language.followSystem,
                    children: [
                      TextSpan(
                        text: ' ($systemLanguageName)',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                value: null,
              ),
              RadioListTile<AppLocale?>(
                title: Text(t.settings.simplifiedChinese),
                value: AppLocale.zhCn,
              ),
              RadioListTile<AppLocale?>(
                title: Text(t.settings.traditionalChinese),
                value: AppLocale.zhTw,
              ),
              RadioListTile<AppLocale?>(
                title: Text(t.settings.english),
                value: AppLocale.en,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel),
          ),
        ],
      ),
    );
  }
}

/// 自动跳转到当前播放
class _AutoScrollToPlayingTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(playbackSettingsProvider);

    return SwitchListTile(
      secondary: const Icon(Icons.my_location_outlined),
      title: Text(t.settings.autoScrollToPlaying.title),
      subtitle: Text(t.settings.autoScrollToPlaying.subtitle),
      value: settings.autoScrollToCurrentTrack,
      onChanged: settings.isLoading
          ? null
          : (value) {
              ref.read(playbackSettingsProvider.notifier).setAutoScrollToCurrentTrack(value);
            },
    );
  }
}

/// 记住播放位置
class _RememberPlaybackPositionTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(playbackSettingsProvider);
    final isEnabled = settings.isLoading ? true : settings.rememberPlaybackPosition;

    return ListTile(
      leading: const Icon(Icons.history_outlined),
      title: Text(t.settings.rememberPosition.title),
      subtitle: Text(isEnabled ? t.general.enabled : t.general.disabled),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isEnabled && !settings.isLoading)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: t.settings.rememberPosition.configRewind,
              onPressed: () => showDialog(
                context: context,
                builder: (context) => const _RewindSettingsDialog(),
              ),
            ),
          Switch(
            value: isEnabled,
            onChanged: settings.isLoading
                ? null
                : (value) {
                    ref.read(playbackSettingsProvider.notifier).setRememberPlaybackPosition(value);
                  },
          ),
        ],
      ),
      onTap: isEnabled && !settings.isLoading
          ? () => showDialog(
                context: context,
                builder: (context) => const _RewindSettingsDialog(),
              )
          : null,
    );
  }
}

/// 回退时间配置弹窗
class _RewindSettingsDialog extends ConsumerWidget {
  const _RewindSettingsDialog();

  static const _rewindOptions = [0, 3, 5, 10, 15, 30];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(playbackSettingsProvider);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.history_outlined),
          const SizedBox(width: 8),
          Text(t.settings.rewindSettings.title),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.settings.rewindSettings.description,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            _buildRewindRow(
              context: context,
              label: t.settings.rewindSettings.restartRewind,
              subtitle: t.settings.rewindSettings.restartRewindSubtitle,
              value: settings.restartRewindSeconds,
              onChanged: (v) => ref.read(playbackSettingsProvider.notifier).setRestartRewindSeconds(v),
            ),
            const SizedBox(height: 16),
            _buildRewindRow(
              context: context,
              label: t.settings.rewindSettings.tempPlayRewind,
              subtitle: t.settings.rewindSettings.tempPlayRewindSubtitle,
              value: settings.tempPlayRewindSeconds,
              onChanged: (v) => ref.read(playbackSettingsProvider.notifier).setTempPlayRewindSeconds(v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.general.close),
        ),
      ],
    );
  }

  Widget _buildRewindRow({
    required BuildContext context,
    required String label,
    required String subtitle,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _rewindOptions.map((option) {
            final isSelected = option == value;
            return ChoiceChip(
              label: Text(option == 0 ? t.settings.rewindSettings.noRewind : t.settings.rewindSettings.seconds(n: option)),
              selected: isSelected,
              onSelected: (_) => onChanged(option),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// 版本号（点击7次解锁开发者选项）
class _VersionListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devOptions = ref.watch(developerOptionsProvider);
    final notifier = ref.read(developerOptionsProvider.notifier);

    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '...';
        final versionText = 'v$version';

        return ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(t.settings.version.title),
          subtitle: Text(versionText),
          onTap: () {
            notifier.onVersionTap();

            if (!devOptions.isEnabled) {
              final remaining = notifier.remainingTaps;
              if (remaining <= 4 && remaining > 0) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(t.settings.version.tapToEnableDev(n: remaining)),
                    duration: const Duration(seconds: 1),
                  ),
                );
              } else if (remaining == 0) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(t.settings.version.devEnabled),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            }
          },
        );
      },
    );
  }
}

/// 检查更新
class _CheckUpdateListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(updateProvider);
    final isChecking = updateState.status == UpdateStatus.checking;

    return ListTile(
      leading: const Icon(Icons.system_update_outlined),
      title: Text(t.settings.update.title),
      subtitle: Text(
        switch (updateState.status) {
          UpdateStatus.checking => t.settings.update.checking,
          UpdateStatus.upToDate => t.settings.update.upToDate,
          UpdateStatus.updateAvailable => t.settings.update.available(version: updateState.updateInfo?.version ?? ""),
          UpdateStatus.error => t.settings.update.error,
          _ => t.settings.update.checkGitHub,
        },
      ),
      trailing: isChecking
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: isChecking
          ? null
          : () async {
              await ref.read(updateProvider.notifier).checkForUpdate();
              final state = ref.read(updateProvider);
              if (!context.mounted) return;

              if (state.status == UpdateStatus.updateAvailable && state.updateInfo != null) {
                UpdateDialog.show(context, state.updateInfo!);
              } else if (state.status == UpdateStatus.upToDate) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(t.settings.update.upToDate),
                    duration: Duration(seconds: 2),
                  ),
                );
              } else if (state.status == UpdateStatus.error) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.errorMessage ?? t.settings.update.checkFailed),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
    );
  }
}

/// 开发者选项区域（隐藏，需要解锁）
class _DeveloperOptionsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devOptions = ref.watch(developerOptionsProvider);

    if (!devOptions.isEnabled) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        const Divider(),
        _SettingsSection(
          title: t.settings.developerOptions.title,
          children: [
            ListTile(
              leading: const Icon(Icons.developer_mode_outlined),
              title: Text(t.settings.developerOptions.title),
              subtitle: Text(t.settings.developerOptions.subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.pushNamed(RouteNames.developerOptions),
            ),
          ],
        ),
      ],
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

/// 下载管理入口
class _DownloadManagerListTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.download_outlined),
      title: Text(t.settings.downloadManager.title),
      subtitle: Text(t.settings.downloadManager.subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.pushNamed(RouteNames.downloadManager),
    );
  }
}

/// 下载路径设置
class _DownloadPathListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadPathAsync = ref.watch(downloadPathProvider);

    return downloadPathAsync.when(
      loading: () => ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text(t.settings.downloadPath.title),
        subtitle: Text(t.general.loading),
      ),
      error: (e, _) => ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text(t.settings.downloadPath.title),
        subtitle: Text(t.settings.downloadPath.loadFailed(error: e.toString())),
      ),
      data: (downloadPath) => ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text(t.settings.downloadPath.title),
        subtitle: Text(
          downloadPath ?? t.general.notSet,
          style: TextStyle(
            color: downloadPath == null
                ? Theme.of(context).colorScheme.error
                : null,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showDownloadPathOptions(context, ref),
      ),
    );
  }

  void _showDownloadPathOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!Platform.isAndroid)
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: Text(t.settings.downloadPath.changePath),
                  onTap: () {
                    Navigator.pop(context);
                    _changeDownloadPath(context, ref);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(t.settings.downloadPath.pathInfo),
                onTap: () {
                  Navigator.pop(context);
                  _showPathInfo(context, ref);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changeDownloadPath(BuildContext context, WidgetRef ref) async {
    await ChangeDownloadPathDialog.show(context);
  }

  void _showPathInfo(BuildContext context, WidgetRef ref) {
    final downloadPath = ref.read(downloadPathProvider).value;
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.folder_outlined,
          color: colorScheme.primary,
          size: 32,
        ),
        title: Text(t.settings.downloadPath.pathInfoTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: AppRadius.borderRadiusMd,
              ),
              child: SelectableText(
                downloadPath ?? t.general.notSet,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: downloadPath == null
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (downloadPath != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.settings.downloadPath.pathChangeWarning,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.confirm),
          ),
        ],
      ),
    );
  }
}

/// 并发下载数设置
class _ConcurrentDownloadsListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(downloadSettingsProvider);
    final maxConcurrent = settings.maxConcurrentDownloads;

    return ListTile(
      leading: const Icon(Icons.speed_outlined),
      title: Text(t.settings.concurrentDownloads.title),
      subtitle: Text(t.settings.concurrentDownloads.subtitle(n: maxConcurrent)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showConcurrentDialog(context, ref, maxConcurrent),
    );
  }

  void _showConcurrentDialog(BuildContext context, WidgetRef ref, int current) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settings.concurrentDownloads.title),
        content: RadioGroup<int>(
          groupValue: current,
          onChanged: (value) {
            if (value != null) {
              ref.read(downloadSettingsProvider.notifier).setMaxConcurrentDownloads(value);
            }
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(5, (index) {
              final value = index + 1;
              return RadioListTile<int>(
                title: Text(t.settings.concurrentDownloads.unit(n: value)),
                value: value,
              );
            }),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel),
          ),
        ],
      ),
    );
  }
}

/// 下载图片选项设置
class _DownloadImageOptionListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(downloadSettingsProvider);
    final option = settings.downloadImageOption;
    final optionText = switch (option) {
      DownloadImageOption.none => t.settings.downloadImage.off,
      DownloadImageOption.coverOnly => t.settings.downloadImage.coverOnly,
      DownloadImageOption.coverAndAvatar => t.settings.downloadImage.coverAndAvatar,
    };

    return ListTile(
      leading: const Icon(Icons.image_outlined),
      title: Text(t.settings.downloadImage.title),
      subtitle: Text(optionText),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showImageOptionDialog(context, ref, option),
    );
  }

  void _showImageOptionDialog(BuildContext context, WidgetRef ref, DownloadImageOption current) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settings.downloadImage.title),
        content: RadioGroup<DownloadImageOption>(
          groupValue: current,
          onChanged: (value) {
            if (value != null) {
              ref.read(downloadSettingsProvider.notifier).setDownloadImageOption(value);
            }
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<DownloadImageOption>(
                title: Text(t.settings.downloadImage.off),
                subtitle: Text(t.settings.downloadImage.offDescription),
                value: DownloadImageOption.none,
              ),
              RadioListTile<DownloadImageOption>(
                title: Text(t.settings.downloadImage.coverOnly),
                subtitle: Text(t.settings.downloadImage.coverOnlyDescription),
                value: DownloadImageOption.coverOnly,
              ),
              RadioListTile<DownloadImageOption>(
                title: Text(t.settings.downloadImage.coverAndAvatar),
                subtitle: Text(t.settings.downloadImage.coverAndAvatarDescription),
                value: DownloadImageOption.coverAndAvatar,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel),
          ),
        ],
      ),
    );
  }
}

/// 图片缓存大小设置
class _ImageCacheSizeListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(downloadSettingsProvider);
    final cacheSizeMB = settings.maxCacheSizeMB;
    final cacheText = _formatCacheSize(cacheSizeMB);

    return ListTile(
      leading: const Icon(Icons.storage_outlined),
      title: Text(t.settings.imageCache.title),
      subtitle: Text(t.settings.imageCache.maxSize(size: cacheText)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showCacheSizeDialog(context, ref, cacheSizeMB),
    );
  }

  String _formatCacheSize(int sizeMB) {
    if (sizeMB >= 1024) {
      return '${(sizeMB / 1024).toStringAsFixed(1)} GB';
    }
    return '$sizeMB MB';
  }

  void _showCacheSizeDialog(BuildContext context, WidgetRef ref, int current) {
    final options = [16, 32, 48, 64];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settings.imageCache.title),
        content: RadioGroup<int>(
          groupValue: current,
          onChanged: (value) {
            if (value != null) {
              ref.read(downloadSettingsProvider.notifier).setMaxCacheSizeMB(value);
            }
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((sizeMB) {
              return RadioListTile<int>(
                title: Text(_formatCacheSize(sizeMB)),
                value: sizeMB,
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel),
          ),
        ],
      ),
    );
  }
}

/// 清除图片缓存
class _ClearImageCacheListTile extends StatefulWidget {
  @override
  State<_ClearImageCacheListTile> createState() =>
      _ClearImageCacheListTileState();
}

class _ClearImageCacheListTileState extends State<_ClearImageCacheListTile> {
  double? _cacheSizeMB;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final sizeMB = await NetworkImageCacheService.getCacheSizeMB();
    if (mounted) {
      setState(() => _cacheSizeMB = sizeMB);
    }
  }

  String _formatSize(double mb) {
    if (mb < 1) {
      return '${(mb * 1024).toStringAsFixed(1)} KB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _cacheSizeMB != null
        ? t.settings.imageCache.currentCache(size: _formatSize(_cacheSizeMB!))
        : t.settings.imageCache.calculating;

    return ListTile(
      leading: const Icon(Icons.delete_outline),
      title: Text(t.settings.imageCache.clearTitle),
      subtitle: Text(subtitle),
      onTap: () => _showClearCacheDialog(context),
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    final sizeText = _cacheSizeMB != null
        ? '\n\n${t.settings.imageCache.currentCacheSize(size: _formatSize(_cacheSizeMB!))}'
        : '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settings.imageCache.clearTitle),
        content: Text('${t.settings.imageCache.clearConfirm}$sizeText'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await ImageLoadingService.clearNetworkCache();
              // 重新加载缓存大小
              await _loadCacheSize();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(t.settings.imageCache.cacheCleared)),
                );
              }
            },
            child: Text(t.general.confirm),
          ),
        ],
      ),
    );
  }
}

/// 开机自启动设置
class _LaunchAtStartupTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startupState = ref.watch(launchAtStartupProvider);

    return ListTile(
      leading: const Icon(Icons.power_settings_new_outlined),
      title: Text(t.settings.launchAtStartup.title),
      subtitle: Text(
        startupState.enabled
            ? (startupState.minimized
                ? t.settings.launchAtStartup.minimizedMode
                : t.settings.launchAtStartup.normalMode)
            : t.settings.launchAtStartup.subtitle,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (startupState.enabled)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: t.settings.launchAtStartup.launchMode,
              onPressed: () => _showLaunchModeDialog(context, ref),
            ),
          Switch(
            value: startupState.enabled,
            onChanged: (_) =>
                ref.read(launchAtStartupProvider.notifier).toggleEnabled(),
          ),
        ],
      ),
      onTap: startupState.enabled
          ? () => _showLaunchModeDialog(context, ref)
          : null,
    );
  }

  void _showLaunchModeDialog(BuildContext context, WidgetRef ref) {
    final startupState = ref.read(launchAtStartupProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settings.launchAtStartup.launchMode),
        content: RadioGroup<bool>(
          groupValue: startupState.minimized,
          onChanged: (value) {
            if (value == null) return;
            ref.read(launchAtStartupProvider.notifier).setMinimized(value);
            Navigator.of(context).pop();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<bool>(
                title: Text(t.settings.launchAtStartup.normalMode),
                subtitle: Text(t.settings.launchAtStartup.normalModeDesc),
                value: false,
              ),
              RadioListTile<bool>(
                title: Text(t.settings.launchAtStartup.minimizedMode),
                subtitle: Text(t.settings.launchAtStartup.minimizedModeDesc),
                value: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 最小化到托盘设置
class _MinimizeToTrayTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(minimizeToTrayProvider);

    return SwitchListTile(
      secondary: const Icon(Icons.dock_outlined),
      title: Text(t.settings.tray.title),
      subtitle: Text(t.settings.tray.subtitle),
      value: enabled,
      onChanged: (_) => ref.read(minimizeToTrayProvider.notifier).toggle(),
    );
  }
}

/// 全局快捷键设置
class _GlobalHotkeysTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(globalHotkeysEnabledProvider);

    return ListTile(
      leading: const Icon(Icons.keyboard_outlined),
      title: Text(t.settings.hotkeys.title),
      subtitle: Text(enabled ? t.general.enabled : t.general.disabled),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: t.settings.hotkeys.configHotkey,
            onPressed: () => _showHotkeyConfigDialog(context, ref),
          ),
          Switch(
            value: enabled,
            onChanged: (_) =>
                ref.read(globalHotkeysEnabledProvider.notifier).toggle(),
          ),
        ],
      ),
      onTap: () => _showHotkeyConfigDialog(context, ref),
    );
  }

  void _showHotkeyConfigDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => const _HotkeyConfigDialog(),
    );
  }
}

/// 快捷键配置对话框
class _HotkeyConfigDialog extends ConsumerStatefulWidget {
  const _HotkeyConfigDialog();

  @override
  ConsumerState<_HotkeyConfigDialog> createState() =>
      _HotkeyConfigDialogState();
}

class _HotkeyConfigDialogState extends ConsumerState<_HotkeyConfigDialog> {
  HotkeyAction? _editingAction;
  Set<HotKeyModifier> _currentModifiers = {};
  LogicalKeyboardKey? _currentKey;
  bool _isRecording = false;

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(hotkeyConfigProvider);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.keyboard_outlined),
          const SizedBox(width: 8),
          Text(t.settings.hotkeys.configTitle),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.restore, size: 18),
            label: Text(t.settings.hotkeys.resetDefault),
            onPressed: () {
              ref.read(hotkeyConfigProvider.notifier).resetToDefaults();
            },
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.settings.hotkeys.hint,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ...HotkeyAction.values.map(
              (action) => _buildHotkeyRow(context, action, config),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.general.close),
        ),
      ],
    );
  }

  Widget _buildHotkeyRow(
      BuildContext context, HotkeyAction action, HotkeyConfig config) {
    final binding = config.getBinding(action);
    final isEditing = _editingAction == action;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              action.label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => _startRecording(action),
              borderRadius: AppRadius.borderRadiusMd,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isEditing
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadius.borderRadiusMd,
                  border: isEditing
                      ? Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        )
                      : null,
                ),
                child: isEditing
                    ? _buildRecordingDisplay(context)
                    : Text(
                        binding?.toDisplayString() ?? t.general.notSet,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: binding?.isConfigured == true
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.grey,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.clear, size: 20),
            tooltip: t.settings.hotkeys.clear,
            onPressed: binding?.isConfigured == true
                ? () {
                    ref.read(hotkeyConfigProvider.notifier).clearBinding(action);
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingDisplay(BuildContext context) {
    if (!_isRecording) {
      return Text(
        t.settings.hotkeys.recording,
        style: const TextStyle(fontStyle: FontStyle.italic),
      );
    }

    final parts = <String>[];
    if (_currentModifiers.contains(HotKeyModifier.control)) parts.add('Ctrl');
    if (_currentModifiers.contains(HotKeyModifier.alt)) parts.add('Alt');
    if (_currentModifiers.contains(HotKeyModifier.shift)) parts.add('Shift');
    if (_currentModifiers.contains(HotKeyModifier.meta)) parts.add('Win');

    if (_currentKey != null) {
      parts.add(_keyToString(_currentKey!));
    }

    if (parts.isEmpty) {
      return Text(
        t.settings.hotkeys.recording,
        style: const TextStyle(fontStyle: FontStyle.italic),
      );
    }

    return Text(
      parts.join(' + '),
      style: const TextStyle(fontFamily: 'monospace'),
    );
  }

  void _startRecording(HotkeyAction action) {
    setState(() {
      _editingAction = action;
      _currentModifiers = {};
      _currentKey = null;
      _isRecording = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _HotkeyRecordingDialog(
        action: action,
        onRecorded: (key, modifiers) {
          Navigator.pop(dialogContext);
          _saveHotkey(action, key, modifiers);
        },
        onCancel: () {
          Navigator.pop(dialogContext);
          setState(() {
            _editingAction = null;
            _isRecording = false;
          });
        },
      ),
    );
  }

  void _saveHotkey(
      HotkeyAction action, LogicalKeyboardKey key, Set<HotKeyModifier> modifiers) {
    final newBinding = HotkeyBinding(
      action: action,
      key: key,
      modifiers: modifiers,
    );

    ref.read(hotkeyConfigProvider.notifier).updateBinding(newBinding);

    setState(() {
      _editingAction = null;
      _isRecording = false;
    });
  }

  String _keyToString(LogicalKeyboardKey key) {
    final specialKeys = {
      LogicalKeyboardKey.space: 'Space',
      LogicalKeyboardKey.arrowLeft: '←',
      LogicalKeyboardKey.arrowRight: '→',
      LogicalKeyboardKey.arrowUp: '↑',
      LogicalKeyboardKey.arrowDown: '↓',
      LogicalKeyboardKey.enter: 'Enter',
      LogicalKeyboardKey.escape: 'Esc',
      LogicalKeyboardKey.backspace: 'Backspace',
      LogicalKeyboardKey.delete: 'Delete',
    };

    if (specialKeys.containsKey(key)) {
      return specialKeys[key]!;
    }

    final label = key.keyLabel;
    if (label.length == 1) {
      return label.toUpperCase();
    }

    return label;
  }
}

/// 快捷键录制对话框
class _HotkeyRecordingDialog extends StatefulWidget {
  final HotkeyAction action;
  final void Function(LogicalKeyboardKey key, Set<HotKeyModifier> modifiers)
      onRecorded;
  final VoidCallback onCancel;

  const _HotkeyRecordingDialog({
    required this.action,
    required this.onRecorded,
    required this.onCancel,
  });

  @override
  State<_HotkeyRecordingDialog> createState() => _HotkeyRecordingDialogState();
}

class _HotkeyRecordingDialogState extends State<_HotkeyRecordingDialog> {
  final FocusNode _focusNode = FocusNode();
  final Set<HotKeyModifier> _modifiers = {};
  LogicalKeyboardKey? _key;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.settings.hotkeys.setHotkey(action: widget.action.label)),
      content: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Container(
          width: 300,
          height: 100,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: AppRadius.borderRadiusLg,
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
          child: Center(
            child: Text(
              _buildDisplayText(),
              style: const TextStyle(
                fontSize: 18,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: Text(t.general.cancel),
        ),
      ],
    );
  }

  String _buildDisplayText() {
    final parts = <String>[];
    if (_modifiers.contains(HotKeyModifier.control)) parts.add('Ctrl');
    if (_modifiers.contains(HotKeyModifier.alt)) parts.add('Alt');
    if (_modifiers.contains(HotKeyModifier.shift)) parts.add('Shift');
    if (_modifiers.contains(HotKeyModifier.meta)) parts.add('Win');

    if (_key != null) {
      parts.add(_keyToString(_key!));
    }

    if (parts.isEmpty) {
      return t.settings.hotkeys.pressCombo;
    }

    return parts.join(' + ');
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;

      if (key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight) {
        setState(() => _modifiers.add(HotKeyModifier.control));
        return;
      }
      if (key == LogicalKeyboardKey.altLeft ||
          key == LogicalKeyboardKey.altRight) {
        setState(() => _modifiers.add(HotKeyModifier.alt));
        return;
      }
      if (key == LogicalKeyboardKey.shiftLeft ||
          key == LogicalKeyboardKey.shiftRight) {
        setState(() => _modifiers.add(HotKeyModifier.shift));
        return;
      }
      if (key == LogicalKeyboardKey.metaLeft ||
          key == LogicalKeyboardKey.metaRight) {
        setState(() => _modifiers.add(HotKeyModifier.meta));
        return;
      }

      if (key == LogicalKeyboardKey.escape) {
        widget.onCancel();
        return;
      }

      if (_modifiers.isNotEmpty) {
        setState(() => _key = key);
        widget.onRecorded(key, _modifiers);
      }
    } else if (event is KeyUpEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight) {
        setState(() => _modifiers.remove(HotKeyModifier.control));
      }
      if (key == LogicalKeyboardKey.altLeft ||
          key == LogicalKeyboardKey.altRight) {
        setState(() => _modifiers.remove(HotKeyModifier.alt));
      }
      if (key == LogicalKeyboardKey.shiftLeft ||
          key == LogicalKeyboardKey.shiftRight) {
        setState(() => _modifiers.remove(HotKeyModifier.shift));
      }
      if (key == LogicalKeyboardKey.metaLeft ||
          key == LogicalKeyboardKey.metaRight) {
        setState(() => _modifiers.remove(HotKeyModifier.meta));
      }
    }
  }

  String _keyToString(LogicalKeyboardKey key) {
    final specialKeys = {
      LogicalKeyboardKey.space: 'Space',
      LogicalKeyboardKey.arrowLeft: '←',
      LogicalKeyboardKey.arrowRight: '→',
      LogicalKeyboardKey.arrowUp: '↑',
      LogicalKeyboardKey.arrowDown: '↓',
      LogicalKeyboardKey.enter: 'Enter',
      LogicalKeyboardKey.escape: 'Esc',
      LogicalKeyboardKey.backspace: 'Backspace',
      LogicalKeyboardKey.delete: 'Delete',
      LogicalKeyboardKey.home: 'Home',
      LogicalKeyboardKey.end: 'End',
      LogicalKeyboardKey.pageUp: 'PageUp',
      LogicalKeyboardKey.pageDown: 'PageDown',
      LogicalKeyboardKey.tab: 'Tab',
    };

    if (specialKeys.containsKey(key)) {
      return specialKeys[key]!;
    }

    if (key.keyId >= LogicalKeyboardKey.f1.keyId &&
        key.keyId <= LogicalKeyboardKey.f12.keyId) {
      final fNum = key.keyId - LogicalKeyboardKey.f1.keyId + 1;
      return 'F$fNum';
    }

    final label = key.keyLabel;
    if (label.length == 1) {
      return label.toUpperCase();
    }

    return label;
  }
}

/// 导出数据
class _ExportDataListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.upload_outlined),
      title: Text(t.settings.backup.export.title),
      subtitle: Text(t.settings.backup.export.subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _exportData(context, ref),
    );
  }

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    try {
      final backupService = ref.read(backupServiceProvider);
      final path = await backupService.exportData();
      
      if (path != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.settings.backup.export.success(path: path)),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.settings.backup.export.failed(error: e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

/// 导入数据
class _ImportDataListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.download_outlined),
      title: Text(t.settings.backup.import.title),
      subtitle: Text(t.settings.backup.import.subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _importData(context, ref),
    );
  }

  Future<void> _importData(BuildContext context, WidgetRef ref) async {
    try {
      final backupService = ref.read(backupServiceProvider);
      final backupData = await backupService.pickAndParseBackupFile();
      
      if (backupData == null) return;
      
      if (!context.mounted) return;
      
      // 显示导入预览对话框
      final result = await showDialog<ImportResult>(
        context: context,
        builder: (context) => _ImportPreviewDialog(
          backupData: backupData,
          backupService: backupService,
        ),
      );
      
      if (result != null && context.mounted) {
        // 显示导入结果
        showDialog(
          context: context,
          builder: (context) => _ImportResultDialog(result: result),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.settings.backup.import.failed(error: e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

/// 导入预览对话框
class _ImportPreviewDialog extends ConsumerStatefulWidget {
  final BackupData backupData;
  final BackupService backupService;

  const _ImportPreviewDialog({
    required this.backupData,
    required this.backupService,
  });

  @override
  ConsumerState<_ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends ConsumerState<_ImportPreviewDialog> {
  bool _importPlaylists = true;
  bool _importPlayHistory = true;
  bool _importSearchHistory = true;
  bool _importRadioStations = true;
  bool _importSettings = true;
  bool _isImporting = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.backupData;
    final colorScheme = Theme.of(context).colorScheme;
    
    return AlertDialog(
      title: Text(t.settings.backup.import.preview),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.settings.backup.import.previewSubtitle,
                style: TextStyle(color: colorScheme.outline, fontSize: 12),
              ),
              const SizedBox(height: 16),
              
              // 备份信息
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadius.borderRadiusMd,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow(
                      t.settings.backup.exportedAt,
                      _formatDateTime(data.exportedAt),
                    ),
                    _buildInfoRow(
                      t.settings.backup.appVersion,
                      data.appVersion,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // 选择要导入的数据
              if (data.playlists.isNotEmpty)
                _buildCheckableRow(
                  Icons.queue_music,
                  t.settings.backup.import.playlists,
                  data.playlists.length,
                  _importPlaylists,
                  (value) => setState(() => _importPlaylists = value ?? true),
                ),
              if (data.playHistory.isNotEmpty)
                _buildCheckableRow(
                  Icons.history,
                  t.settings.backup.import.playHistory,
                  data.playHistory.length,
                  _importPlayHistory,
                  (value) => setState(() => _importPlayHistory = value ?? true),
                ),
              if (data.searchHistory.isNotEmpty)
                _buildCheckableRow(
                  Icons.search,
                  t.settings.backup.import.searchHistory,
                  data.searchHistory.length,
                  _importSearchHistory,
                  (value) => setState(() => _importSearchHistory = value ?? true),
                ),
              if (data.radioStations.isNotEmpty)
                _buildCheckableRow(
                  Icons.radio,
                  t.settings.backup.import.radioStations,
                  data.radioStations.length,
                  _importRadioStations,
                  (value) => setState(() => _importRadioStations = value ?? true),
                ),
              if (data.settings != null)
                _buildCheckableRow(
                  Icons.settings,
                  t.settings.backup.import.importSettings,
                  null,
                  _importSettings,
                  (value) => setState(() => _importSettings = value ?? true),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.pop(context),
          child: Text(t.general.cancel),
        ),
        FilledButton(
          onPressed: _isImporting ? null : _doImport,
          child: _isImporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t.settings.backup.import.confirm),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(value, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildCheckableRow(
    IconData icon,
    String label,
    int? count,
    bool value,
    ValueChanged<bool?> onChanged,
  ) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      secondary: Icon(icon, size: 20),
      title: Row(
        children: [
          Expanded(child: Text(label)),
          if (count != null)
            Text(
              count.toString(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
        ],
      ),
      value: value,
      onChanged: _isImporting ? null : onChanged,
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _doImport() async {
    setState(() => _isImporting = true);

    try {
      final result = await widget.backupService.importData(
        widget.backupData,
        importPlaylists: _importPlaylists,
        importPlayHistory: _importPlayHistory,
        importSearchHistory: _importSearchHistory,
        importRadioStations: _importRadioStations,
        importSettings: _importSettings,
      );

      // 按勾选分类刷新对应的 Provider
      if (_importPlaylists) {
        ref.invalidate(allPlaylistsProvider);
      }

      if (_importSettings && result.settingsImported) {
        ref.invalidate(themeProvider);
        ref.invalidate(localeProvider);
        ref.invalidate(playbackSettingsProvider);
        ref.invalidate(downloadSettingsProvider);
        ref.invalidate(downloadPathProvider);
        ref.invalidate(hotkeyConfigProvider);
      }

      if (mounted) {
        Navigator.pop(context, result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isImporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.settings.backup.import.failed(error: e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

/// 导入结果对话框
class _ImportResultDialog extends StatelessWidget {
  final ImportResult result;

  const _ImportResultDialog({required this.result});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            result.errors.isEmpty ? Icons.check_circle : Icons.warning,
            color: result.errors.isEmpty ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          Text(t.settings.backup.import.success),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildResultRow(
                t.settings.backup.import.result.playlistsImported(
                  imported: result.playlistsImported,
                  skipped: result.playlistsSkipped,
                ),
              ),
              _buildResultRow(
                t.settings.backup.import.result.tracksImported(
                  imported: result.tracksImported,
                  skipped: result.tracksSkipped,
                ),
              ),
              _buildResultRow(
                t.settings.backup.import.result.playHistoryImported(
                  imported: result.playHistoryImported,
                  skipped: result.playHistorySkipped,
                ),
              ),
              _buildResultRow(
                t.settings.backup.import.result.searchHistoryImported(
                  imported: result.searchHistoryImported,
                  skipped: result.searchHistorySkipped,
                ),
              ),
              _buildResultRow(
                t.settings.backup.import.result.radioStationsImported(
                  imported: result.radioStationsImported,
                  skipped: result.radioStationsSkipped,
                ),
              ),
              _buildResultRow(
                result.settingsImported
                    ? t.settings.backup.import.result.settingsImported
                    : t.settings.backup.import.result.settingsSkipped,
              ),
              
              if (result.errors.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  t.settings.backup.import.result.errors,
                  style: TextStyle(
                    color: colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: AppRadius.borderRadiusMd,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: result.errors
                        .take(5)
                        .map((e) => Text(
                              e,
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onErrorContainer,
                              ),
                            ))
                        .toList(),
                  ),
                ),
                if (result.errors.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '... ${result.errors.length - 5} more errors',
                      style: TextStyle(fontSize: 12, color: colorScheme.outline),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.general.confirm),
        ),
      ],
    );
  }

  Widget _buildResultRow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(text, style: const TextStyle(fontSize: 13)),
    );
  }
}