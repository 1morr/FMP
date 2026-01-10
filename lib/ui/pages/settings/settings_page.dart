import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/settings.dart';
import '../../../providers/playback_settings_provider.dart';
import '../../../providers/theme_provider.dart';
import '../../../providers/download_provider.dart';
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
              _AutoScrollListTile(),
              SwitchListTile(
                secondary: const Icon(Icons.skip_next_outlined),
                title: const Text('自动播放下一首'),
                subtitle: const Text('当前歌曲结束后自动播放下一首'),
                value: true,
                onChanged: (value) {
                  // TODO: 实现
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.history_outlined),
                title: const Text('记住播放位置'),
                subtitle: const Text('应用重启后从上次位置继续播放'),
                value: true,
                onChanged: (value) {
                  // TODO: 实现
                },
              ),
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
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('版本'),
                subtitle: const Text('1.0.0 (Phase 4)'),
              ),
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('跟随系统'),
              secondary: const Icon(Icons.brightness_auto),
              value: ThemeMode.system,
              groupValue: currentMode,
              onChanged: (value) {
                ref.read(themeProvider.notifier).setThemeMode(value!);
                Navigator.pop(context);
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('浅色'),
              secondary: const Icon(Icons.light_mode),
              value: ThemeMode.light,
              groupValue: currentMode,
              onChanged: (value) {
                ref.read(themeProvider.notifier).setThemeMode(value!);
                Navigator.pop(context);
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('深色'),
              secondary: const Icon(Icons.dark_mode),
              value: ThemeMode.dark,
              groupValue: currentMode,
              onChanged: (value) {
                ref.read(themeProvider.notifier).setThemeMode(value!);
                Navigator.pop(context);
              },
            ),
          ],
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

/// 自动跳转到当前播放设置
class _AutoScrollListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackSettings = ref.watch(playbackSettingsProvider);

    return SwitchListTile(
      secondary: const Icon(Icons.my_location_outlined),
      title: const Text('切歌时自动定位'),
      subtitle: const Text('切换歌曲时自动跳转到队列页面并定位当前播放'),
      value: playbackSettings.autoScrollToCurrentTrack,
      onChanged: playbackSettings.isLoading
          ? null
          : (value) {
              ref.read(playbackSettingsProvider.notifier).setAutoScrollToCurrentTrack(value);
            },
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
    // TODO: 从设置中获取
    const maxConcurrent = 3;

    return ListTile(
      leading: const Icon(Icons.speed_outlined),
      title: const Text('同时下载数量'),
      subtitle: const Text('最多同时下载 $maxConcurrent 个文件'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showConcurrentDialog(context, maxConcurrent),
    );
  }

  void _showConcurrentDialog(BuildContext context, int current) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('同时下载数量'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (index) {
            final value = index + 1;
            return RadioListTile<int>(
              title: Text('$value 个'),
              value: value,
              groupValue: current,
              onChanged: (value) {
                // TODO: 保存设置
                Navigator.pop(context);
              },
            );
          }),
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
    // TODO: 从设置中获取
    const option = DownloadImageOption.coverOnly;
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
      onTap: () => _showImageOptionDialog(context, option),
    );
  }

  void _showImageOptionDialog(BuildContext context, DownloadImageOption current) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('下载图片'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<DownloadImageOption>(
              title: const Text('关闭'),
              subtitle: const Text('不下载任何图片'),
              value: DownloadImageOption.none,
              groupValue: current,
              onChanged: (value) {
                // TODO: 保存设置
                Navigator.pop(context);
              },
            ),
            RadioListTile<DownloadImageOption>(
              title: const Text('仅封面'),
              subtitle: const Text('下载视频封面'),
              value: DownloadImageOption.coverOnly,
              groupValue: current,
              onChanged: (value) {
                // TODO: 保存设置
                Navigator.pop(context);
              },
            ),
            RadioListTile<DownloadImageOption>(
              title: const Text('封面和头像'),
              subtitle: const Text('下载视频封面和UP主头像'),
              value: DownloadImageOption.coverAndAvatar,
              groupValue: current,
              onChanged: (value) {
                // TODO: 保存设置
                Navigator.pop(context);
              },
            ),
          ],
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
