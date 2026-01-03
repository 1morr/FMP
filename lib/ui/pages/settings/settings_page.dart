import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('缓存目录'),
                subtitle: const Text('默认'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // TODO: 实现缓存目录选择
                },
              ),
              ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: const Text('缓存上限'),
                subtitle: const Text('2 GB'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  _showCacheLimitDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('清除缓存'),
                subtitle: const Text('清除所有临时缓存文件'),
                onTap: () {
                  _showClearCacheDialog(context);
                },
              ),
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

  void _showCacheLimitDialog(BuildContext context) {
    int selectedValue = 2048;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('缓存上限'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<int>(
                title: const Text('1 GB'),
                value: 1024,
                groupValue: selectedValue,
                onChanged: (value) {
                  setDialogState(() => selectedValue = value!);
                  Navigator.pop(context);
                },
              ),
              RadioListTile<int>(
                title: const Text('2 GB'),
                value: 2048,
                groupValue: selectedValue,
                onChanged: (value) {
                  setDialogState(() => selectedValue = value!);
                  Navigator.pop(context);
                },
              ),
              RadioListTile<int>(
                title: const Text('4 GB'),
                value: 4096,
                groupValue: selectedValue,
                onChanged: (value) {
                  setDialogState(() => selectedValue = value!);
                  Navigator.pop(context);
                },
              ),
              RadioListTile<int>(
                title: const Text('无限制'),
                value: -1,
                groupValue: selectedValue,
                onChanged: (value) {
                  setDialogState(() => selectedValue = value!);
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
      ),
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('确定要清除所有缓存文件吗？这不会影响已下载的歌曲。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('缓存已清除')),
              );
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
