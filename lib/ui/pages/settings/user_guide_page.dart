import 'package:flutter/material.dart';

/// 使用说明页面
class UserGuidePage extends StatelessWidget {
  const UserGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('使用说明'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 快速开始卡片
          _buildSectionCard(
            context,
            title: '快速开始',
            icon: Icons.rocket_outlined,
            iconColor: colorScheme.primary,
            children: [
              _buildStepItem(
                context,
                stepNumber: 1,
                title: '导入歌单',
                description:
                    '音乐库右上角点击导入，支持 Bilibili/YouTube 链接导入，也支持从网易云、QQ音乐、Spotify 导入歌单',
                icon: Icons.library_add,
              ),
              _buildStepItem(
                context,
                stepNumber: 2,
                title: '添加到队列',
                description: '打开歌单，点击「添加所有」将歌曲加入播放队列',
                icon: Icons.queue_music,
              ),
              _buildStepItem(
                context,
                stepNumber: 3,
                title: '开始播放',
                description: '点击任意歌曲即可播放，或使用底部播放器控制',
                icon: Icons.play_circle,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 外部歌单导入卡片
          _buildSectionCard(
            context,
            title: '外部歌单导入',
            icon: Icons.playlist_add_circle_outlined,
            iconColor: colorScheme.primary,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.music_note,
                title: '支持平台',
                description: '网易云音乐、QQ音乐、Spotify',
              ),
              _buildInfoItem(
                context,
                icon: Icons.auto_fix_high,
                title: '智能匹配',
                description: '自动在 Bilibili/YouTube 搜索匹配对应歌曲',
              ),
              _buildInfoItem(
                context,
                icon: Icons.tune,
                title: '预览调整',
                description: '导入前可预览匹配结果，手动选择备选项或排除不需要的歌曲',
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 播放控制卡片
          _buildSectionCard(
            context,
            title: '播放控制',
            icon: Icons.play_circle_outline,
            iconColor: colorScheme.tertiary,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.shuffle,
                title: '随机播放',
                description: '点击随机按钮打乱播放顺序',
              ),
              _buildInfoItem(
                context,
                icon: Icons.repeat,
                title: '循环模式',
                description: '支持列表循环、单曲循环、不循环',
              ),
              _buildInfoItem(
                context,
                icon: Icons.speed,
                title: '播放速度',
                description: '全屏播放器中可调节播放速度',
              ),
              _buildInfoItem(
                context,
                icon: Icons.bookmark_outline,
                title: '位置记忆',
                description: '长视频（>10分钟）自动记忆播放位置，下次播放自动恢复',
              ),
              _buildInfoItem(
                context,
                icon: Icons.skip_next,
                title: '临时播放',
                description: '搜索或歌单中点击歌曲临时播放，完成后自动恢复原队列',
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 搜索功能卡片
          _buildSectionCard(
            context,
            title: '搜索功能',
            icon: Icons.search,
            iconColor: colorScheme.primary,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.video_library,
                title: '支持音源',
                description: 'Bilibili、YouTube 双源搜索',
              ),
              _buildInfoItem(
                context,
                icon: Icons.sort,
                title: '排序筛选',
                description: '支持按综合、播放量、最新、弹幕数排序',
              ),
              _buildInfoItem(
                context,
                icon: Icons.live_tv,
                title: '直播间筛选',
                description: 'Bilibili 搜索支持筛选直播间（全部/未开播/已开播）',
              ),
              _buildInfoItem(
                context,
                icon: Icons.view_list,
                title: '多P展开',
                description: '多P视频自动检测，可展开查看各分P',
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 直播与电台卡片
          _buildSectionCard(
            context,
            title: '直播与电台',
            icon: Icons.radio,
            iconColor: colorScheme.error,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.live_tv,
                title: 'Bilibili 直播',
                description: '搜索直播间，收听直播音频',
              ),
              _buildInfoItem(
                context,
                icon: Icons.refresh,
                title: '自动刷新',
                description: '直播流地址过期时自动刷新，保持持续播放',
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 下载音乐卡片
          _buildSectionCard(
            context,
            title: '下载音乐',
            icon: Icons.download,
            iconColor: colorScheme.secondary,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.folder_outlined,
                title: '设置下载路径',
                description: '在设置 → 存储中配置下载目录',
              ),
              _buildInfoItem(
                context,
                icon: Icons.download_done,
                title: '下载歌曲',
                description: '歌单详情页点击「下载全部」或单个歌曲菜单下载',
              ),
              _buildInfoItem(
                context,
                icon: Icons.library_music_outlined,
                title: '离线播放',
                description: '下载后在「已下载」中按歌单分类浏览和播放',
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 探索页面卡片
          _buildSectionCard(
            context,
            title: '探索页面',
            icon: Icons.explore,
            iconColor: colorScheme.tertiary,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.trending_up,
                title: '热门排行榜',
                description: '查看 Bilibili 和 YouTube 音乐热门排行',
              ),
              _buildInfoItem(
                context,
                icon: Icons.refresh,
                title: '自动更新',
                description: '排行榜每小时自动后台刷新，打开即看无需等待',
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 播放历史卡片
          _buildSectionCard(
            context,
            title: '播放历史',
            icon: Icons.history,
            iconColor: colorScheme.secondary,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.timeline,
                title: '时间轴',
                description: '按时间顺序查看所有播放记录',
              ),
              _buildInfoItem(
                context,
                icon: Icons.bar_chart,
                title: '统计信息',
                description: '查看播放次数等统计数据',
              ),
              _buildInfoItem(
                context,
                icon: Icons.filter_list,
                title: '筛选排序',
                description: '支持筛选和排序，快速找到想听的歌曲',
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 音频设置卡片
          _buildSectionCard(
            context,
            title: '音频设置',
            icon: Icons.equalizer,
            iconColor: colorScheme.primary,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.high_quality,
                title: '音质等级',
                description: '支持高/中/低三档，适用于所有音源',
              ),
              _buildInfoItem(
                context,
                icon: Icons.audio_file,
                title: '格式优先级',
                description: 'YouTube 支持选择 Opus 或 AAC 格式',
              ),
              _buildInfoItem(
                context,
                icon: Icons.stream,
                title: '流类型优先级',
                description: '可选纯音频流（省流量）或混合流（兼容性好）',
              ),
            ],
          ),

          const SizedBox(height: 16),

          // YouTube Mix 卡片
          _buildSectionCard(
            context,
            title: 'YouTube Mix',
            icon: Icons.all_inclusive,
            iconColor: colorScheme.tertiary,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.playlist_play,
                title: '动态播放列表',
                description: '导入 YouTube Mix/Radio 播放列表，自动加载更多歌曲',
              ),
              _buildInfoItem(
                context,
                icon: Icons.autorenew,
                title: '无限播放',
                description: '播放接近队列末尾时自动获取新歌曲，持续不断',
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 应用更新卡片
          _buildSectionCard(
            context,
            title: '应用更新',
            icon: Icons.system_update,
            iconColor: colorScheme.secondary,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.update,
                title: '检查更新',
                description: '设置 → 关于 → 检查更新，自动从 GitHub 获取最新版本',
              ),
              _buildInfoItem(
                context,
                icon: Icons.install_mobile,
                title: '自动安装',
                description: 'Android 下载 APK 后自动安装，Windows 下载后自动替换更新',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildStepItem(
    BuildContext context, {
    required int stepNumber,
    required String title,
    required String description,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Center(
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$stepNumber',
                    style: TextStyle(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 36,
            child: Center(
              child: Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
