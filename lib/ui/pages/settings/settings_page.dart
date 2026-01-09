import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/cache_provider.dart';
import '../../../providers/theme_provider.dart';

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
          // 存储设置
          _SettingsSection(
            title: '存储',
            children: [
              _CacheSizeListTile(),
              _CacheLimitListTile(),
              _ClearCacheListTile(),
            ],
          ),
          const Divider(),
          // 播放设置
          _SettingsSection(
            title: '播放',
            children: [
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

/// 缓存大小显示
class _CacheSizeListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cacheStatsAsync = ref.watch(refreshableCacheStatsProvider);

    return cacheStatsAsync.when(
      data: (stats) => ListTile(
        leading: const Icon(Icons.storage_outlined),
        title: const Text('当前缓存'),
        subtitle: Text(
          '${stats.formattedImageCacheSize} (${stats.imageCacheCount} 张图片)',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (stats.maxCacheMB > 0) ...[
              SizedBox(
                width: 50,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${stats.usagePercent.toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: stats.usagePercent / 100,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(refreshableCacheStatsProvider),
              tooltip: '刷新',
            ),
          ],
        ),
      ),
      loading: () => const ListTile(
        leading: Icon(Icons.storage_outlined),
        title: Text('当前缓存'),
        subtitle: Text('计算中...'),
        trailing: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (error, stack) => ListTile(
        leading: const Icon(Icons.storage_outlined),
        title: const Text('当前缓存'),
        subtitle: Text('获取失败: $error'),
        trailing: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(refreshableCacheStatsProvider),
        ),
      ),
    );
  }
}

/// 缓存上限设置
class _CacheLimitListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cacheStatsAsync = ref.watch(refreshableCacheStatsProvider);

    return cacheStatsAsync.when(
      data: (stats) => ListTile(
        leading: const Icon(Icons.sd_storage_outlined),
        title: const Text('缓存上限'),
        subtitle: Text(stats.formattedMaxCache),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showCacheLimitDialog(context, ref, stats.maxCacheMB),
      ),
      loading: () => const ListTile(
        leading: Icon(Icons.sd_storage_outlined),
        title: Text('缓存上限'),
        subtitle: Text('加载中...'),
      ),
      error: (error, stack) => ListTile(
        leading: const Icon(Icons.sd_storage_outlined),
        title: const Text('缓存上限'),
        subtitle: const Text('128 MB'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showCacheLimitDialog(context, ref, 128),
      ),
    );
  }

  void _showCacheLimitDialog(BuildContext context, WidgetRef ref, int currentValue) {
    int selectedValue = currentValue;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('缓存上限'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<int>(
                title: const Text('64 MB'),
                value: 64,
                groupValue: selectedValue,
                onChanged: (value) {
                  setDialogState(() => selectedValue = value!);
                },
              ),
              RadioListTile<int>(
                title: const Text('128 MB'),
                value: 128,
                groupValue: selectedValue,
                onChanged: (value) {
                  setDialogState(() => selectedValue = value!);
                },
              ),
              RadioListTile<int>(
                title: const Text('256 MB'),
                value: 256,
                groupValue: selectedValue,
                onChanged: (value) {
                  setDialogState(() => selectedValue = value!);
                },
              ),
              RadioListTile<int>(
                title: const Text('512 MB'),
                value: 512,
                groupValue: selectedValue,
                onChanged: (value) {
                  setDialogState(() => selectedValue = value!);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                final cacheService = ref.read(cacheServiceProvider);
                await cacheService.updateMaxCacheSize(selectedValue);
                // 刷新缓存统计
                ref.invalidate(refreshableCacheStatsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('缓存上限已更新')),
                  );
                }
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 清除缓存
class _ClearCacheListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.delete_outline),
      title: const Text('清除缓存'),
      subtitle: const Text('清除所有图片缓存'),
      onTap: () => _showClearCacheDialog(context, ref),
    );
  }

  void _showClearCacheDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('确定要清除所有缓存文件吗？这不会影响已下载的歌曲和歌单数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);

              // 显示加载指示器
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(
                  child: CircularProgressIndicator(),
                ),
              );

              try {
                final cacheService = ref.read(cacheServiceProvider);
                await cacheService.clearAllCache();

                // 刷新缓存统计
                ref.invalidate(refreshableCacheStatsProvider);

                if (context.mounted) {
                  Navigator.pop(context); // 关闭加载指示器
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('缓存已清除')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context); // 关闭加载指示器
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('清除缓存失败: $e')),
                  );
                }
              }
            },
            child: const Text('清除'),
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
