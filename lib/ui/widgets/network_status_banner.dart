import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/i18n/strings.g.dart';

import '../../services/audio/audio_provider.dart';
import '../../core/constants/ui_constants.dart';
import '../../services/network/connectivity_service.dart';

/// Banner 是否显示的 Provider
/// 供其他页面查询以决定是否需要自己提供 SafeArea top padding
final networkBannerVisibleProvider = Provider<bool>((ref) {
  final connectivityState = ref.watch(connectivityProvider);
  final playerState = ref.watch(audioControllerProvider);
  return !connectivityState.isConnected || playerState.isNetworkError;
});

/// 网络状态 Banner
///
/// 显示在应用顶部，用于提示用户当前网络状态（灰色背景，显示"无网络"）
/// 此组件始终提供 SafeArea top padding，即使 banner 内容不显示
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
      duration: AnimationDurations.normal,
      vsync: this,
    );
    _slideAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
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

    final colorScheme = Theme.of(context).colorScheme;
    final showRetryButton = playerState.isNetworkError && !playerState.isRetrying;

    // banner 内容根据动画显示/隐藏
    // SafeArea 由 app.dart 统一提供，此处不再处理
    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) {
        final progress = _slideAnimation.value;
        if (progress == 0.0 && !shouldShow) {
          return const SizedBox.shrink();
        }
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: progress,
            child: child,
          ),
        );
      },
      child: Material(
        color: colorScheme.surfaceContainerHigh,
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
                t.networkStatus.noNetwork,
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
                  child: Text(t.networkStatus.retry),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
