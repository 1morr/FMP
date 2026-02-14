import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../core/constants/ui_constants.dart';

/// 使用说明页面
class UserGuidePage extends StatelessWidget {
  const UserGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.settings.userGuide.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 快速开始卡片
          _buildSectionCard(
            context,
            title: t.userGuide.quickStart.title,
            icon: Icons.rocket_outlined,
            iconColor: colorScheme.primary,
            children: [
              _buildStepItem(
                context,
                stepNumber: 1,
                title: t.userGuide.quickStart.importPlaylist,
                description: t.userGuide.quickStart.importPlaylistDesc,
                icon: Icons.library_add,
              ),
              _buildStepItem(
                context,
                stepNumber: 2,
                title: t.userGuide.quickStart.addToQueue,
                description: t.userGuide.quickStart.addToQueueDesc,
                icon: Icons.queue_music,
              ),
              _buildStepItem(
                context,
                stepNumber: 3,
                title: t.userGuide.quickStart.startPlayback,
                description: t.userGuide.quickStart.startPlaybackDesc,
                icon: Icons.play_circle,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 外部歌单导入卡片
          _buildSectionCard(
            context,
            title: t.userGuide.externalImport.title,
            icon: Icons.playlist_add_circle_outlined,
            iconColor: colorScheme.primary,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.music_note,
                title: t.userGuide.externalImport.platforms,
                description: t.userGuide.externalImport.platformsDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.auto_fix_high,
                title: t.userGuide.externalImport.smartMatch,
                description: t.userGuide.externalImport.smartMatchDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.tune,
                title: t.userGuide.externalImport.preview,
                description: t.userGuide.externalImport.previewDesc,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 播放控制卡片
          _buildSectionCard(
            context,
            title: t.userGuide.playbackControl.title,
            icon: Icons.play_circle_outline,
            iconColor: colorScheme.tertiary,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.shuffle,
                title: t.userGuide.playbackControl.shuffle,
                description: t.userGuide.playbackControl.shuffleDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.repeat,
                title: t.userGuide.playbackControl.loopMode,
                description: t.userGuide.playbackControl.loopModeDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.speed,
                title: t.userGuide.playbackControl.speed,
                description: t.userGuide.playbackControl.speedDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.bookmark_outline,
                title: t.userGuide.playbackControl.positionMemory,
                description: t.userGuide.playbackControl.positionMemoryDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.skip_next,
                title: t.userGuide.playbackControl.tempPlay,
                description: t.userGuide.playbackControl.tempPlayDesc,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 搜索功能卡片
          _buildSectionCard(
            context,
            title: t.userGuide.search.title,
            icon: Icons.search,
            iconColor: colorScheme.primary,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.video_library,
                title: t.userGuide.search.sources,
                description: t.userGuide.search.sourcesDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.sort,
                title: t.userGuide.search.sortFilter,
                description: t.userGuide.search.sortFilterDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.live_tv,
                title: t.userGuide.search.liveFilter,
                description: t.userGuide.search.liveFilterDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.view_list,
                title: t.userGuide.search.multiP,
                description: t.userGuide.search.multiPDesc,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 直播与电台卡片
          _buildSectionCard(
            context,
            title: t.userGuide.liveRadio.title,
            icon: Icons.radio,
            iconColor: colorScheme.error,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.live_tv,
                title: t.userGuide.liveRadio.biliLive,
                description: t.userGuide.liveRadio.biliLiveDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.refresh,
                title: t.userGuide.liveRadio.autoRefresh,
                description: t.userGuide.liveRadio.autoRefreshDesc,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 下载音乐卡片
          _buildSectionCard(
            context,
            title: t.userGuide.download.title,
            icon: Icons.download,
            iconColor: colorScheme.secondary,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.folder_outlined,
                title: t.userGuide.download.setPath,
                description: t.userGuide.download.setPathDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.download_done,
                title: t.userGuide.download.downloadSong,
                description: t.userGuide.download.downloadSongDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.library_music_outlined,
                title: t.userGuide.download.offline,
                description: t.userGuide.download.offlineDesc,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 探索页面卡片
          _buildSectionCard(
            context,
            title: t.userGuide.explore.title,
            icon: Icons.explore,
            iconColor: colorScheme.tertiary,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.trending_up,
                title: t.userGuide.explore.ranking,
                description: t.userGuide.explore.rankingDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.refresh,
                title: t.userGuide.explore.autoUpdate,
                description: t.userGuide.explore.autoUpdateDesc,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 播放历史卡片
          _buildSectionCard(
            context,
            title: t.userGuide.history.title,
            icon: Icons.history,
            iconColor: colorScheme.secondary,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.timeline,
                title: t.userGuide.history.timeline,
                description: t.userGuide.history.timelineDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.bar_chart,
                title: t.userGuide.history.stats,
                description: t.userGuide.history.statsDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.filter_list,
                title: t.userGuide.history.filter,
                description: t.userGuide.history.filterDesc,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 音频设置卡片
          _buildSectionCard(
            context,
            title: t.userGuide.audioSettingsGuide.title,
            icon: Icons.equalizer,
            iconColor: colorScheme.primary,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.high_quality,
                title: t.userGuide.audioSettingsGuide.qualityLevel,
                description: t.userGuide.audioSettingsGuide.qualityLevelDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.audio_file,
                title: t.userGuide.audioSettingsGuide.formatPriority,
                description: t.userGuide.audioSettingsGuide.formatPriorityDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.stream,
                title: t.userGuide.audioSettingsGuide.streamPriority,
                description: t.userGuide.audioSettingsGuide.streamPriorityDesc,
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
                title: t.userGuide.ytMix.dynamicPlaylist,
                description: t.userGuide.ytMix.dynamicPlaylistDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.autorenew,
                title: t.userGuide.ytMix.infinitePlay,
                description: t.userGuide.ytMix.infinitePlayDesc,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 应用更新卡片
          _buildSectionCard(
            context,
            title: t.userGuide.appUpdate.title,
            icon: Icons.system_update,
            iconColor: colorScheme.secondary,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.update,
                title: t.userGuide.appUpdate.checkUpdate,
                description: t.userGuide.appUpdate.checkUpdateDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.install_mobile,
                title: t.userGuide.appUpdate.autoInstall,
                description: t.userGuide.appUpdate.autoInstallDesc,
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
                    borderRadius: AppRadius.borderRadiusLg,
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
