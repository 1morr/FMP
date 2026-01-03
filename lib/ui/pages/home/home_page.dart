import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/sources/source_provider.dart';
import '../../../services/audio/audio_provider.dart';

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
        title: const Text('首页'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 欢迎信息
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.music_note,
                      size: 64,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '欢迎使用 FMP',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Flutter Music Player - Phase 2: 核心播放',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // URL 播放区域
            Card(
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
                    const SizedBox(height: 16),
                    TextField(
                      controller: _urlController,
                      decoration: InputDecoration(
                        hintText: '输入 Bilibili 视频 URL (如: https://www.bilibili.com/video/BVxxxxxxxx)',
                        prefixIcon: const Icon(Icons.video_library),
                        suffixIcon: _urlController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _urlController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        errorText: _error,
                      ),
                      onChanged: (_) => setState(() => _error = null),
                      onSubmitted: (_) => _playFromUrl(),
                    ),
                    const SizedBox(height: 16),
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
            ),
            const SizedBox(height: 24),

            // 当前播放状态
            if (playerState.hasCurrentTrack)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.queue_music,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '当前播放',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        leading: Icon(
                          playerState.isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          size: 48,
                          color: colorScheme.primary,
                        ),
                        title: Text(
                          playerState.currentTrack?.title ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          playerState.currentTrack?.artist ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            playerState.isPlaying ? Icons.pause : Icons.play_arrow,
                          ),
                          onPressed: () {
                            ref.read(audioControllerProvider.notifier).togglePlayPause();
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: playerState.progress.clamp(0.0, 1.0),
                      ),
                    ],
                  ),
                ),
              ),

            // 测试提示
            const SizedBox(height: 24),
            Card(
              color: colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '提示: 输入 B站视频链接（BV号格式）来测试播放功能',
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
