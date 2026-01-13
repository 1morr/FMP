import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/playback_settings_provider.dart';
import '../../router.dart';

/// 开发者选项页面
class DeveloperOptionsPage extends ConsumerWidget {
  const DeveloperOptionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('开发者选项'),
      ),
      body: ListView(
        children: [
          // 调试工具
          _SettingsSection(
            title: '调试工具',
            children: [
              ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: const Text('数据库查看器'),
                subtitle: const Text('查看和浏览 Isar 数据库内容'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.pushNamed(RouteNames.databaseViewer),
              ),
            ],
          ),
          const Divider(),
          // 实验性功能
          _SettingsSection(
            title: '实验性功能',
            children: [
              _AutoScrollListTile(),
            ],
          ),
          const Divider(),
          // 信息
          _SettingsSection(
            title: '开发信息',
            children: [
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('调试模式'),
                subtitle: const Text('已启用'),
                trailing: Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 自动跳转到当前播放设置（从主设置页移动过来）
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

/// 设置区块（复用）
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
