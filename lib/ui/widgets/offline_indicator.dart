import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/network_service.dart';
import '../../providers/network_provider.dart';

/// 离线状态横幅
/// 
/// 当网络离线时显示在页面顶部的提示横幅
class OfflineBanner extends ConsumerWidget {
  /// 是否显示重试按钮
  final bool showRetryButton;
  
  const OfflineBanner({
    super.key,
    this.showRetryButton = true,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(isOfflineProvider);
    
    if (!isOffline) {
      return const SizedBox.shrink();
    }
    
    final colorScheme = Theme.of(context).colorScheme;
    
    return Material(
      color: colorScheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 18,
                color: colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '当前处于离线状态，部分功能可能不可用',
                  style: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontSize: 13,
                  ),
                ),
              ),
              if (showRetryButton) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    ref.read(networkStatusProvider.notifier).forceCheck();
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 32),
                    foregroundColor: colorScheme.onErrorContainer,
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

/// 离线状态指示器图标
/// 
/// 在 AppBar 或其他位置显示的小型离线指示器
class OfflineIndicator extends ConsumerWidget {
  /// 图标大小
  final double size;
  
  /// 是否显示工具提示
  final bool showTooltip;
  
  const OfflineIndicator({
    super.key,
    this.size = 20,
    this.showTooltip = true,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(isOfflineProvider);
    
    if (!isOffline) {
      return const SizedBox.shrink();
    }
    
    final colorScheme = Theme.of(context).colorScheme;
    
    final icon = Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.cloud_off_rounded,
        size: size,
        color: colorScheme.onErrorContainer,
      ),
    );
    
    if (showTooltip) {
      return Tooltip(
        message: '离线状态',
        child: icon,
      );
    }
    
    return icon;
  }
}

/// 网络状态徽章
/// 
/// 显示当前网络状态的圆形徽章
class NetworkStatusBadge extends ConsumerWidget {
  /// 徽章大小
  final double size;
  
  const NetworkStatusBadge({
    super.key,
    this.size = 10,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(networkStatusProvider);
    final colorScheme = Theme.of(context).colorScheme;
    
    final color = switch (status) {
      NetworkStatus.online => Colors.green,
      NetworkStatus.offline => colorScheme.error,
      NetworkStatus.unknown => Colors.orange,
    };
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: colorScheme.surface,
          width: 1,
        ),
      ),
    );
  }
}

/// 离线内容提示
/// 
/// 当内容不可用时显示的离线提示
class OfflineContentPlaceholder extends ConsumerWidget {
  /// 提示消息
  final String message;
  
  /// 重试回调
  final VoidCallback? onRetry;
  
  const OfflineContentPlaceholder({
    super.key,
    this.message = '无法加载内容，请检查网络连接',
    this.onRetry,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: () {
                  ref.read(networkStatusProvider.notifier).forceCheck();
                  onRetry?.call();
                },
                child: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
