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
                description: '点击音乐库右上角的「从 URL 导入」，粘贴 Bilibili 或 YouTube 歌单链接',
                icon: Icons.link,
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
                description: '歌单详情页点击「下载全部」或单个歌曲菜单',
              ),
              _buildInfoItem(
                context,
                icon: Icons.sync,
                title: '同步本地文件',
                description: '在「已下载」页面点击同步按钮，扫描本地文件更新数据库',
              ),
              _buildInfoItem(
                context,
                icon: Icons.library_music_outlined,
                title: '离线播放',
                description: '下载后在「已下载」中查看和播放',
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
                description: 'Bilibili、YouTube',
              ),
              _buildInfoItem(
                context,
                icon: Icons.playlist_add,
                title: '临时播放',
                description: '搜索结果点击歌曲临时播放，完成后恢复原队列',
              ),
              _buildInfoItem(
                context,
                icon: Icons.add_circle_outline,
                title: '添加到队列',
                description: '长按歌曲可选择添加方式',
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
                description: '排行榜每小时自动后台刷新',
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
          Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
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
