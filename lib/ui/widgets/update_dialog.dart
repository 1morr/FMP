import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/strings.g.dart';
import '../../core/constants/ui_constants.dart';
import '../../providers/update_provider.dart';
import '../../services/update/update_service.dart';

/// 更新对话框
class UpdateDialog extends ConsumerWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({super.key, required this.updateInfo});

  /// 显示更新对话框
  static Future<void> show(BuildContext context, UpdateInfo info) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => UpdateDialog(updateInfo: info),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(updateProvider);
    final theme = Theme.of(context);
    final isDownloading = updateState.status == UpdateStatus.downloading;
    final isInstalling = updateState.status == UpdateStatus.installing;
    final hasError = updateState.status == UpdateStatus.error;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(t.updateDialog.title)),
          // 关闭按钮
          if (!isDownloading && !isInstalling)
            IconButton(
              onPressed: () {
                ref.read(updateProvider.notifier).reset();
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.close),
              tooltip: t.general.close,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              iconSize: 20,
            ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 版本信息
            Row(
              children: [
                Text(
                  updateInfo.version,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                if (updateInfo.assetSize != null)
                  Text(
                    _formatSize(updateInfo.assetSize!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Release Notes
            if (updateInfo.releaseNotes.isNotEmpty) ...[
              Text(
                t.updateDialog.releaseNotes,
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(
                    updateInfo.releaseNotes,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Full Changelog 链接
            if (updateInfo.htmlUrl != null)
              InkWell(
                onTap: () async {
                  final uri = Uri.parse(updateInfo.htmlUrl!);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.open_in_new,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      t.updateDialog.viewChangelog,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            // 下载进度
            if (isDownloading) ...[
              LinearProgressIndicator(
                value: updateState.downloadProgress,
                borderRadius: AppRadius.borderRadiusSm,
              ),
              const SizedBox(height: 4),
              Text(
                t.updateDialog.downloading(percent: (updateState.downloadProgress * 100).toStringAsFixed(0)),
                style: theme.textTheme.bodySmall,
              ),
            ],

            // 安装中
            if (isInstalling) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              Text(
                Platform.isWindows ? t.updateDialog.installingRestart : t.updateDialog.installingOpening,
                style: theme.textTheme.bodySmall,
              ),
            ],

            // 错误信息
            if (hasError && updateState.errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: AppRadius.borderRadiusLg,
                ),
                child: Text(
                  updateState.errorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        // 关闭/取消按钮
        if (!isDownloading && !isInstalling)
          TextButton(
            onPressed: () {
              ref.read(updateProvider.notifier).reset();
              Navigator.of(context).pop();
            },
            child: Text(t.updateDialog.later),
          ),

        // 下载/重试按钮
        if (!isDownloading && !isInstalling)
          FilledButton.icon(
            onPressed: updateInfo.downloadUrl == null
                ? null
                : () => ref.read(updateProvider.notifier).downloadAndInstall(),
            icon: Icon(hasError ? Icons.refresh : Icons.download),
            label: Text(hasError ? t.updateDialog.retry : t.updateDialog.updateNow),
          ),
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
