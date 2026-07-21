import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../i18n/strings.g.dart';

/// QR 登入卡：白底圓角卡片 + QR 圖 + 過期遮罩，下方為狀態文字與
/// 過期時的「重新整理」按鈕。
///
/// Bilibili / NetEase 登入頁共用。[qrWidget] 由呼叫端構建
/// （QrImageView，不經 ImageLoadingService），以保留各平台的
/// QR 資料來源差異。
class QrLoginCard extends StatelessWidget {
  /// QR 圖本體（通常為 200x200 的 QrImageView）。
  final Widget qrWidget;

  /// QR 是否已過期（顯示白底 0.85 遮罩 + 刷新圖示 + [expiredText]）。
  final bool isExpired;

  /// 卡片下方的登入狀態文字。
  final String statusText;

  /// 過期遮罩上的提示文字。
  final String expiredText;

  /// 「重新整理」按鈕回調；null 或 [isExpired] 為 false 時不顯示按鈕。
  final VoidCallback? onRefresh;

  /// QR 圖與過期遮罩的邊長。
  final double size;

  const QrLoginCard({
    super.key,
    required this.qrWidget,
    required this.isExpired,
    required this.statusText,
    required this.expiredText,
    this.onRefresh,
    this.size = 200,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // QR 碼（白底讓深色模式下仍可掃描）
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.borderRadiusLg,
          ),
          padding: const EdgeInsets.all(16),
          child: Stack(
            alignment: Alignment.center,
            children: [
              qrWidget,
              if (isExpired)
                Container(
                  width: size,
                  height: size,
                  color: Colors.white.withValues(alpha: 0.85),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh,
                            size: 40, color: colorScheme.primary),
                        const SizedBox(height: 8),
                        Text(expiredText,
                            style:
                                TextStyle(color: colorScheme.onSurface)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // 狀態文字
        Text(
          statusText,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
        // 重新生成按鈕
        if (isExpired && onRefresh != null) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: Text(t.account.qrRefresh),
          ),
        ],
      ],
    );
  }
}
