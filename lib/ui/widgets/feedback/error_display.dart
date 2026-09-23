import 'package:flutter/material.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/core/constants/ui_constants.dart';

/// 错误类型枚举
enum ErrorType {
  /// 网络错误
  network,

  /// 服务器错误
  server,

  /// 未找到
  notFound,

  /// 权限错误
  permission,

  /// 通用错误
  general,

  /// 空状态（无数据）
  empty,
}

/// 统一的错误显示组件
///
/// 支持多种错误类型，提供一致的视觉风格和操作
class ErrorDisplay extends StatelessWidget {
  /// 错误类型
  final ErrorType type;

  /// 错误消息
  final String? message;

  /// 重试回调
  final VoidCallback? onRetry;

  /// 自定义图标
  final IconData? icon;

  /// 自定义标题
  final String? title;

  /// 自定义操作按钮（用于空状态等场景）
  final Widget? action;

  /// 是否紧凑模式
  final bool compact;

  const ErrorDisplay({
    super.key,
    this.type = ErrorType.general,
    this.message,
    this.onRetry,
    this.icon,
    this.title,
    this.action,
    this.compact = false,
  });

  /// 网络错误
  const ErrorDisplay.network({
    super.key,
    this.message,
    this.onRetry,
    this.compact = false,
  }) : type = ErrorType.network,
       icon = null,
       title = null,
       action = null;

  /// 服务器错误
  const ErrorDisplay.server({
    super.key,
    this.message,
    this.onRetry,
    this.compact = false,
  }) : type = ErrorType.server,
       icon = null,
       title = null,
       action = null;

  /// 未找到
  const ErrorDisplay.notFound({
    super.key,
    this.message,
    this.onRetry,
    this.compact = false,
  }) : type = ErrorType.notFound,
       icon = null,
       title = null,
       action = null;

  /// 权限错误
  const ErrorDisplay.permission({
    super.key,
    this.message,
    this.onRetry,
    this.compact = false,
  }) : type = ErrorType.permission,
       icon = null,
       title = null,
       action = null;

  /// 空状态
  const ErrorDisplay.empty({
    super.key,
    this.message,
    this.onRetry,
    this.icon,
    this.title,
    this.action,
    this.compact = false,
  }) : type = ErrorType.empty;

  /// 根据错误类型获取默认图标
  IconData _getIcon() {
    if (icon != null) return icon!;
    switch (type) {
      case ErrorType.network:
        return Icons.wifi_off_rounded;
      case ErrorType.server:
        return Icons.cloud_off_rounded;
      case ErrorType.notFound:
        return Icons.search_off_rounded;
      case ErrorType.permission:
        return Icons.lock_rounded;
      case ErrorType.empty:
        return Icons.inbox_rounded;
      case ErrorType.general:
        return Icons.error_outline_rounded;
    }
  }

  /// 根据错误类型获取默认标题
  String _getTitle() {
    if (title != null) return title!;
    switch (type) {
      case ErrorType.network:
        return t.error.networkError;
      case ErrorType.server:
        return t.error.serverErrorTitle;
      case ErrorType.notFound:
        return t.error.notFound;
      case ErrorType.permission:
        return t.error.insufficientPermission;
      case ErrorType.empty:
        return t.error.emptyContent;
      case ErrorType.general:
        return t.error.genericError;
    }
  }

  /// 根据错误类型获取默认消息
  String _getDefaultMessage() {
    switch (type) {
      case ErrorType.network:
        return t.error.networkErrorSubtitle;
      case ErrorType.server:
        return t.error.serverErrorSubtitle;
      case ErrorType.notFound:
        return t.error.notFoundSubtitle;
      case ErrorType.permission:
        return t.error.permissionSubtitle;
      case ErrorType.empty:
        return t.error.emptySubtitle;
      case ErrorType.general:
        return t.error.genericSubtitle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final displayMessage = message ?? _getDefaultMessage();

    if (compact) {
      return _buildCompact(context, colorScheme, textTheme, displayMessage);
    }

    return _buildFull(context, colorScheme, textTheme, displayMessage);
  }

  Widget _buildCompact(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
    String displayMessage,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: type == ErrorType.empty
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: AppRadius.borderRadiusLg,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getIcon(),
            size: 20,
            color: type == ErrorType.empty
                ? colorScheme.onSurfaceVariant
                : colorScheme.error,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              displayMessage,
              style: textTheme.bodyMedium?.copyWith(
                color: type == ErrorType.empty
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.onErrorContainer,
              ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 12),
            IconButton(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              tooltip: t.error.retry,
            ),
          ],
        ],
      ),
    );
  }

  /// 可用高度低於這個值就改用緊湊間距。完整版面固定約 300dp，而橫向手機扣掉
  /// 狀態列、工具列與迷你播放器後只剩約 267dp。
  static const double _shortHeight = 400;

  Widget _buildFull(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
    String displayMessage,
  ) {
    // 空狀態與錯誤狀態共用這一個版面，約 24 個呼叫點。垂直預算以前全是固定
    // 值，在橫向手機溢出 41px，被裁掉的正好是最底下的「重試」或建立按鈕。
    // 矮視窗先縮間距與圖示，字級放大仍放不下時可以捲動。
    return LayoutBuilder(
      builder: (context, constraints) {
        final isShort = constraints.maxHeight < _shortHeight;
        final content = _buildFullContent(
          colorScheme,
          textTheme,
          displayMessage,
          isShort: isShort,
        );
        // 放在沒有高度上限的地方（例如捲動清單裡）時，沒有「剩餘高度」可以
        // 置中，也不需要自己捲動。
        if (!constraints.hasBoundedHeight) return Center(child: content);
        return SingleChildScrollView(
          // 不接 PrimaryScrollController：呼叫點常常已經在一個用它的捲動
          // 視圖裡（例如 SliverFillRemaining）。
          primary: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: content),
          ),
        );
      },
    );
  }

  Widget _buildFullContent(
    ColorScheme colorScheme,
    TextTheme textTheme,
    String displayMessage, {
    required bool isShort,
  }) {
    final actionGap = SizedBox(height: isShort ? 16 : 32);
    return Padding(
      padding: EdgeInsets.all(isShort ? 16 : 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getIcon(),
            size: isShort ? 48 : 80,
            color: type == ErrorType.empty
                ? colorScheme.outline
                : colorScheme.error,
          ),
          SizedBox(height: isShort ? 12 : 24),
          Text(
            _getTitle(),
            style: textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            displayMessage,
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.outline),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[
            actionGap,
            action!,
          ] else if (onRetry != null) ...[
            actionGap,
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(t.error.retry),
            ),
          ],
        ],
      ),
    );
  }
}

/// 加载状态 Widget
class LoadingPlaceholder extends StatelessWidget {
  /// 加载提示文字
  final String? message;

  /// 是否紧凑模式
  final bool compact;

  const LoadingPlaceholder({super.key, this.message, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          ),
          if (message != null) ...[
            const SizedBox(width: 12),
            Text(
              message!,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: colorScheme.primary),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
