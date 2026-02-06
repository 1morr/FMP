import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/audio/audio_provider.dart';
import '../../services/network/connectivity_service.dart';

/// 网络状态 Banner
/// 
/// 显示在应用顶部，用于提示用户当前网络状态（灰色背景，显示"无网络"）
class NetworkStatusBanner extends ConsumerStatefulWidget {
  const NetworkStatusBanner({super.key});

  @override
  ConsumerState<NetworkStatusBanner> createState() => _NetworkStatusBannerState();
}

class _NetworkStatusBannerState extends ConsumerState<NetworkStatusBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<double>(
      begin: -1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(audioControllerProvider);
    final connectivityState = ref.watch(connectivityProvider);

    // 确定是否显示 Banner
    final shouldShow = !connectivityState.isConnected || 
                       playerState.isNetworkError;

    // 控制动画
    if (shouldShow) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }

    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) {
        final offset = _slideAnimation.value;
        if (offset == -1.0 && !shouldShow) {
          return const SizedBox.shrink();
        }
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1.0 + offset,
            child: child,
          ),
        );
      },
      child: _buildBannerContent(context, playerState, connectivityState),
    );
  }

  Widget _buildBannerContent(
    BuildContext context,
    PlayerState playerState,
    ConnectivityState connectivityState,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final showRetryButton = playerState.isNetworkError && !playerState.isRetrying;

    return Material(
      color: colorScheme.surfaceContainerHigh,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.wifi_off,
                color: colorScheme.onSurfaceVariant,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                '无网络',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (showRetryButton) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    ref.read(audioControllerProvider.notifier).retryManually();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('重试'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
