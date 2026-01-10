import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/sources/source_provider.dart';
import '../../../providers/playlist_provider.dart';
import '../../../services/audio/audio_provider.dart';
import '../../router.dart';

/// 首页
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _urlController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _playFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = '请输入 URL');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final sourceManager = ref.read(sourceManagerProvider);
      final track = await sourceManager.parseUrl(url);

      if (track == null) {
        setState(() => _error = '无法解析此 URL，请检查是否为有效的 B站视频链接');
        return;
      }

      // 播放
      final controller = ref.read(audioControllerProvider.notifier);
      await controller.playSingle(track);

      _urlController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('正在播放: ${track.title}')),
        );
      }
    } catch (e) {
      setState(() => _error = '播放失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final playerState = ref.watch(audioControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('FMP'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go(RoutePaths.settings),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 快捷操作区域
            _buildQuickActions(context, colorScheme),

            // URL 播放卡片
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildUrlPlayCard(context, colorScheme),
            ),

            // 当前播放
            if (playerState.hasCurrentTrack)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildNowPlaying(context, playerState, colorScheme),
              ),

            // 最近播放歌单
            _buildRecentPlaylists(context, colorScheme),

            // 队列预览
            if (playerState.queue.isNotEmpty)
              _buildQueuePreview(context, playerState, colorScheme),

            const SizedBox(height: 100), // 为迷你播放器留出空间
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _QuickActionCard(
              icon: Icons.search,
              label: '搜索',
              color: colorScheme.primaryContainer,
              iconColor: colorScheme.onPrimaryContainer,
              onTap: () => context.go(RoutePaths.search),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _QuickActionCard(
              icon: Icons.library_music,
              label: '音乐库',
              color: colorScheme.secondaryContainer,
              iconColor: colorScheme.onSecondaryContainer,
              onTap: () => context.go(RoutePaths.library),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _QuickActionCard(
              icon: Icons.queue_music,
              label: '播放队列',
              color: colorScheme.tertiaryContainer,
              iconColor: colorScheme.onTertiaryContainer,
              onTap: () => context.go(RoutePaths.queue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUrlPlayCard(BuildContext context, ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.link,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '从 URL 播放',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: 'Bilibili 视频 URL',
                prefixIcon: const Icon(Icons.video_library),
                suffixIcon: _urlController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _urlController.clear();
                          setState(() => _error = null);
                        },
                      )
                    : null,
                errorText: _error,
                isDense: true,
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _playFromUrl(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isLoading ? null : _playFromUrl,
                icon: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_isLoading ? '加载中...' : '播放'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNowPlaying(
    BuildContext context,
    PlayerState playerState,
    ColorScheme colorScheme,
  ) {
    final track = playerState.currentTrack!;

    return Card(
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: InkWell(
        onTap: () => context.push(RoutePaths.player),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 封面
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: colorScheme.surfaceContainerHighest,
                ),
                clipBehavior: Clip.antiAlias,
                child: track.thumbnailUrl != null
                    ? Image.network(
                        track.thumbnailUrl!,
                        fit: BoxFit.cover,
                      )
                    : Icon(
                        Icons.music_note,
                        color: colorScheme.primary,
                      ),
              ),
              const SizedBox(width: 12),
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '正在播放',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colorScheme.primary,
                          ),
                    ),
                    Text(
                      track.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      track.artist ?? '未知艺术家',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // 控制按钮
              IconButton(
                icon: Icon(
                  playerState.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
                onPressed: () =>
                    ref.read(audioControllerProvider.notifier).togglePlayPause(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentPlaylists(BuildContext context, ColorScheme colorScheme) {
    final playlists = ref.watch(allPlaylistsProvider);

    return playlists.when(
      loading: () => const SizedBox.shrink(),
      error: (e, s) => const SizedBox.shrink(),
      data: (lists) {
        if (lists.isEmpty) return const SizedBox.shrink();

        // 只显示最近的3个歌单
        final recentLists = lists.take(3).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text(
                    '我的歌单',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => context.go(RoutePaths.library),
                    child: const Text('查看全部'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 152,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: recentLists.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final playlist = recentLists[index];
                  final coverAsync =
                      ref.watch(playlistCoverProvider(playlist.id));

                  return SizedBox(
                    width: 120,
                    child: InkWell(
                      onTap: () => context.go('/library/${playlist.id}'),
                      borderRadius: BorderRadius.circular(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 封面
                          AspectRatio(
                            aspectRatio: 1,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: colorScheme.surfaceContainerHighest,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: coverAsync.when(
                                data: (url) => url != null
                                    ? Image.network(
                        url,
                        fit: BoxFit.cover,
                      )
                                    : Icon(
                                        Icons.album,
                                        size: 40,
                                        color: colorScheme.outline,
                                      ),
                                loading: () => const Center(
                                  child: CircularProgressIndicator(),
                                ),
                                error: (e, s) => Icon(
                                  Icons.album,
                                  size: 40,
                                  color: colorScheme.outline,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 名称
                          Text(
                            playlist.name,
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQueuePreview(
    BuildContext context,
    PlayerState playerState,
    ColorScheme colorScheme,
  ) {
    // 使用 upcomingTracks 获取接下来要播放的歌曲（已考虑 shuffle 模式）
    final upNext = playerState.upcomingTracks.take(3).toList();
    if (upNext.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text(
                '接下来播放',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.go(RoutePaths.queue),
                child: const Text('查看队列'),
              ),
            ],
          ),
        ),
        ...upNext.map((track) => ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: colorScheme.surfaceContainerHighest,
                ),
                clipBehavior: Clip.antiAlias,
                child: track.thumbnailUrl != null
                    ? Image.network(
                        track.thumbnailUrl!,
                        fit: BoxFit.cover,
                      )
                    : Icon(
                        Icons.music_note,
                        color: colorScheme.outline,
                        size: 20,
                      ),
              ),
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                track.artist ?? '未知艺术家',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              dense: true,
              onTap: () {
                final trackIndex = playerState.queue.indexOf(track);
                if (trackIndex >= 0) {
                  ref.read(audioControllerProvider.notifier).playAt(trackIndex);
                }
              },
            )),
      ],
    );
  }
}

/// 快捷操作卡片
class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: iconColor,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
