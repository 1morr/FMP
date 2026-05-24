import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../i18n/strings.g.dart';

/// 使用说明页面
class UserGuidePage extends StatelessWidget {
  const UserGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.settings.userGuide.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildExpandableSection(
            context,
            title: t.userGuide.quickStart.title,
            icon: Icons.rocket_outlined,
            iconColor: colorScheme.primary,
            initiallyExpanded: true,
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
          _buildExpandableSection(
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
              _buildInfoItem(
                context,
                icon: Icons.all_inclusive,
                title: t.userGuide.tips.youtubeMixShortcut,
                description: t.userGuide.tips.youtubeMixShortcutDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.autorenew,
                title: t.userGuide.ytMix.infinitePlay,
                description: t.userGuide.ytMix.infinitePlayDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.lock_open,
                title: t.userGuide.tips.authImport,
                description: t.userGuide.tips.authImportDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.update,
                title: t.userGuide.tips.importAutoRefresh,
                description: t.userGuide.tips.importAutoRefreshDesc,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildExpandableSection(
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
              _buildInfoItem(
                context,
                icon: Icons.radio,
                title: t.userGuide.liveRadio.title,
                description: t.userGuide.liveRadio.biliLiveDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.trending_up,
                title: t.userGuide.explore.title,
                description: t.userGuide.explore.homeSourcesDesc,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildExpandableSection(
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
              _buildInfoItem(
                context,
                icon: Icons.equalizer,
                title: t.userGuide.audioSettingsGuide.title,
                description: t.userGuide.tips.audioSettingsDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.verified_user_outlined,
                title: t.userGuide.tips.authForPlay,
                description: t.userGuide.tips.authForPlayDesc,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildExpandableSection(
            context,
            title: t.userGuide.tips.lyricsTitle,
            icon: Icons.lyrics_outlined,
            iconColor: colorScheme.secondary,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.auto_awesome,
                title: t.userGuide.tips.autoLyrics,
                description: t.userGuide.tips.autoLyricsDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.sort,
                title: t.userGuide.tips.lyricsSources,
                description: t.userGuide.tips.lyricsSourcesDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.smart_toy_outlined,
                title: t.userGuide.tips.lyricsAi,
                description: t.userGuide.tips.lyricsAiDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.desktop_windows_outlined,
                title: t.userGuide.tips.desktopLyrics,
                description: t.userGuide.tips.desktopLyricsDesc,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildExpandableSection(
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
              _buildInfoItem(
                context,
                icon: Icons.sync,
                title: t.userGuide.tips.downloadSync,
                description: t.userGuide.tips.downloadSyncDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.backup_outlined,
                title: t.userGuide.tips.backup,
                description: t.userGuide.tips.backupDesc,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildExpandableSection(
            context,
            title: t.userGuide.tips.desktopAndMaintenanceTitle,
            icon: Icons.settings_suggest_outlined,
            iconColor: colorScheme.error,
            children: [
              _buildInfoItem(
                context,
                icon: Icons.keyboard_outlined,
                title: t.userGuide.tips.desktopHotkeys,
                description: t.userGuide.tips.desktopHotkeysDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.web_asset_off_outlined,
                title: t.userGuide.tips.trayStartup,
                description: t.userGuide.tips.trayStartupDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.history,
                title: t.userGuide.history.title,
                description: t.userGuide.tips.historyDesc,
              ),
              _buildInfoItem(
                context,
                icon: Icons.system_update,
                title: t.userGuide.appUpdate.title,
                description: t.userGuide.appUpdate.checkUpdateDesc,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: AppRadius.borderRadiusMd,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 20,
            ),
          ),
          title: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        icon,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
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
          SizedBox(
            width: 36,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Center(
                child:
                    Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
              ),
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
