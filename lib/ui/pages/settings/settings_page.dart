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
import '../../../providers/theme_provider.dart';
import '../../../providers/download_settings_provider.dart';
import '../../../providers/developer_options_provider.dart';
import '../../../providers/playback_settings_provider.dart';
import '../../../providers/desktop_settings_provider.dart';
import '../../../providers/hotkey_config_provider.dart';
import '../../../providers/download_path_provider.dart';
import '../../../providers/update_provider.dart';
import '../../router.dart';
import '../../widgets/change_download_path_dialog.dart';
import '../../widgets/update_dialog.dart';

/// 设置页
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          // 外观设置
          _SettingsSection(
            title: '外观',
            children: [
              _ThemeModeListTile(),
              _ThemeColorListTile(),
            ],
          ),
          const Divider(),
          // 播放设置
          _SettingsSection(
            title: '播放',
            children: [
              ListTile(
                leading: const Icon(Icons.graphic_eq),
                title: const Text('音频质量'),
                subtitle: const Text('码率、格式、流优先级'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(RoutePaths.audioSettings),
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('播放历史'),
                subtitle: const Text('查看和管理播放记录'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(RoutePaths.history),
              ),
              _RememberPlaybackPositionTile(),
            ],
          ),
          const Divider(),
          // 缓存设置
          _SettingsSection(
            title: '缓存',
            children: [
              _ImageCacheSizeListTile(),
              _ClearImageCacheListTile(),
            ],
          ),
          const Divider(),
          // 存储设置
          _SettingsSection(
            title: '存储',
            children: [
              _DownloadManagerListTile(),
              _DownloadPathListTile(),
              _ConcurrentDownloadsListTile(),
              _DownloadImageOptionListTile(),
            ],
          ),
          const Divider(),
          // 桌面设置（仅 Windows）
          if (Platform.isWindows)
            _SettingsSection(
              title: '桌面',
              children: [
                _MinimizeToTrayTile(),
                _GlobalHotkeysTile(),
              ],
            ),
          if (Platform.isWindows) const Divider(),
          // 关于
          _SettingsSection(
            title: '关于',
            children: [
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('使用说明'),
                subtitle: const Text('快速入门、功能介绍、使用提示'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(RoutePaths.userGuide),
              ),
              _VersionListTile(),
              _CheckUpdateListTile(),
              ListTile(
                leading: const Icon(Icons.code_outlined),
                title: const Text('开源许可'),
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
      ThemeMode.system => '跟随系统',
      ThemeMode.light => '浅色',
      ThemeMode.dark => '深色',
    };

    return ListTile(
      leading: Icon(
        switch (themeMode) {
          ThemeMode.system => Icons.brightness_auto,
          ThemeMode.light => Icons.light_mode,
          ThemeMode.dark => Icons.dark_mode,
        },
      ),
      title: const Text('主题'),
      subtitle: Text(themeName),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showThemeModeDialog(context, ref, themeMode),
    );
  }

  void _showThemeModeDialog(BuildContext context, WidgetRef ref, ThemeMode currentMode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择主题'),
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
                title: const Text('跟随系统'),
                secondary: const Icon(Icons.brightness_auto),
                value: ThemeMode.system,
              ),
              RadioListTile<ThemeMode>(
                title: const Text('浅色'),
                secondary: const Icon(Icons.light_mode),
                value: ThemeMode.light,
              ),
              RadioListTile<ThemeMode>(
                title: const Text('深色'),
                secondary: const Icon(Icons.dark_mode),
                value: ThemeMode.dark,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
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
      title: const Text('主题色'),
      subtitle: Text(primaryColor == null ? '默认' : '自定义'),
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
        title: const Text('选择主题色'),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 默认选项
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
                title: const Text('默认'),
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
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}

/// 记住播放位置开关
class _RememberPlaybackPositionTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(playbackSettingsProvider);

    return SwitchListTile(
      secondary: const Icon(Icons.history_outlined),
      title: const Text('记住播放位置'),
      subtitle: const Text('应用重启后从上次位置继续播放'),
      value: settings.isLoading ? true : settings.rememberPlaybackPosition,
      onChanged: settings.isLoading
          ? null
          : (value) {
              ref.read(playbackSettingsProvider.notifier).setRememberPlaybackPosition(value);
            },
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
          title: const Text('版本'),
          subtitle: Text(versionText),
          onTap: () {
            notifier.onVersionTap();

            if (!devOptions.isEnabled) {
              final remaining = notifier.remainingTaps;
              if (remaining <= 4 && remaining > 0) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('再点击 $remaining 次启用开发者选项'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              } else if (remaining == 0) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('开发者选项已启用'),
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
      title: const Text('检查更新'),
      subtitle: Text(
        switch (updateState.status) {
          UpdateStatus.checking => '正在检查...',
          UpdateStatus.upToDate => '已是最新版本',
          UpdateStatus.updateAvailable => '有新版本: ${updateState.updateInfo?.version ?? ""}',
          UpdateStatus.error => '检查失败，点击重试',
          _ => '检查 GitHub 上的新版本',
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
                  const SnackBar(
                    content: Text('已是最新版本'),
                    duration: Duration(seconds: 2),
                  ),
                );
              } else if (state.status == UpdateStatus.error) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.errorMessage ?? '检查更新失败'),
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
          title: '开发者选项',
          children: [
            ListTile(
              leading: const Icon(Icons.developer_mode_outlined),
              title: const Text('开发者选项'),
              subtitle: const Text('调试工具和实验性功能'),
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
      title: const Text('下载管理'),
      subtitle: const Text('管理下载队列和进度'),
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
      loading: () => const ListTile(
        leading: Icon(Icons.folder_outlined),
        title: Text('下载路径'),
        subtitle: Text('加载中...'),
      ),
      error: (e, _) => ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: const Text('下载路径'),
        subtitle: Text('加载失败: $e'),
      ),
      data: (downloadPath) => ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: const Text('下载路径'),
        subtitle: Text(
          downloadPath ?? '未设置',
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
                  title: const Text('更改下载路径'),
                  onTap: () {
                    Navigator.pop(context);
                    _changeDownloadPath(context, ref);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('当前路径信息'),
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
        title: const Text('下载路径信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                downloadPath ?? '未设置',
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
                      '修改路径将清空数据库中的下载路径记录',
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
            child: const Text('确定'),
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
      title: const Text('同时下载数量'),
      subtitle: Text('最多同时下载 $maxConcurrent 个文件'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showConcurrentDialog(context, ref, maxConcurrent),
    );
  }

  void _showConcurrentDialog(BuildContext context, WidgetRef ref, int current) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('同时下载数量'),
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
                title: Text('$value 个'),
                value: value,
              );
            }),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
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
      DownloadImageOption.none => '关闭',
      DownloadImageOption.coverOnly => '仅封面',
      DownloadImageOption.coverAndAvatar => '封面和头像',
    };

    return ListTile(
      leading: const Icon(Icons.image_outlined),
      title: const Text('下载图片'),
      subtitle: Text(optionText),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showImageOptionDialog(context, ref, option),
    );
  }

  void _showImageOptionDialog(BuildContext context, WidgetRef ref, DownloadImageOption current) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('下载图片'),
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
                title: const Text('关闭'),
                subtitle: const Text('不下载任何图片'),
                value: DownloadImageOption.none,
              ),
              RadioListTile<DownloadImageOption>(
                title: const Text('仅封面'),
                subtitle: const Text('下载视频封面'),
                value: DownloadImageOption.coverOnly,
              ),
              RadioListTile<DownloadImageOption>(
                title: const Text('封面和头像'),
                subtitle: const Text('下载视频封面和UP主头像'),
                value: DownloadImageOption.coverAndAvatar,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
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
      title: const Text('图片缓存大小'),
      subtitle: Text('最大 $cacheText'),
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
        title: const Text('图片缓存大小'),
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
            child: const Text('取消'),
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
        ? '当前缓存: ${_formatSize(_cacheSizeMB!)}'
        : '正在计算...';

    return ListTile(
      leading: const Icon(Icons.delete_outline),
      title: const Text('清除图片缓存'),
      subtitle: Text(subtitle),
      onTap: () => _showClearCacheDialog(context),
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    final sizeText = _cacheSizeMB != null
        ? '\n\n当前缓存大小: ${_formatSize(_cacheSizeMB!)}'
        : '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除图片缓存'),
        content: Text('确定要清除所有缓存的图片吗？这不会影响已下载的本地图片。$sizeText'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await ImageLoadingService.clearNetworkCache();
              // 重新加载缓存大小
              await _loadCacheSize();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('图片缓存已清除')),
                );
              }
            },
            child: const Text('确定'),
          ),
        ],
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
      title: const Text('最小化到托盘'),
      subtitle: const Text('关闭窗口时最小化到系统托盘'),
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
      title: const Text('全局快捷键'),
      subtitle: Text(enabled ? '已启用' : '已禁用'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '配置快捷键',
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
          const Text('配置快捷键'),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.restore, size: 18),
            label: const Text('恢复默认'),
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
            const Text(
              '点击快捷键区域后按下新的组合键进行设置',
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
          child: const Text('关闭'),
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
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isEditing
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
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
                        binding?.toDisplayString() ?? '未设置',
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
            tooltip: '清除',
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
      return const Text(
        '按下新的快捷键...',
        style: TextStyle(fontStyle: FontStyle.italic),
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
      return const Text(
        '按下新的快捷键...',
        style: TextStyle(fontStyle: FontStyle.italic),
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
      title: Text('设置 ${widget.action.label} 快捷键'),
      content: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Container(
          width: 300,
          height: 100,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
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
          child: const Text('取消'),
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
      return '请按下快捷键组合\n\n(需要至少一个修饰键)';
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