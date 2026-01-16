import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/image_loading_service.dart';
import '../../../core/services/network_image_cache_service.dart';
import '../../../data/models/settings.dart';
import '../../../providers/theme_provider.dart';
import '../../../providers/download_provider.dart';
import '../../../providers/download_settings_provider.dart';
import '../../../providers/developer_options_provider.dart';
import '../../../providers/playback_settings_provider.dart';
import '../../router.dart';

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
          // 关于
          _SettingsSection(
            title: '关于',
            children: [
              _VersionListTile(),
              ListTile(
                leading: const Icon(Icons.code_outlined),
                title: const Text('开源许可'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  showLicensePage(
                    context: context,
                    applicationName: 'FMP',
                    applicationVersion: '1.0.0',
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

    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: const Text('版本'),
      subtitle: const Text('1.0.0 (Phase 4)'),
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
    final dirInfoAsync = ref.watch(downloadDirInfoProvider);

    return dirInfoAsync.when(
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
      data: (info) => ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: const Text('下载路径'),
        subtitle: Text(info.path),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showPathDialog(context, info.path),
      ),
    );
  }

  void _showPathDialog(BuildContext context, String currentPath) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('下载路径'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前路径:', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                currentPath,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '提示：修改下载路径功能即将推出',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
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
    final options = [64, 128, 256, 512];

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
