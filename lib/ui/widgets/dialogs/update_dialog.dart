import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/core/constants/ui_constants.dart';
import 'package:fmp/providers/system/update_provider.dart';
import 'package:fmp/services/update/update_service.dart';

/// 把 GitHub release body 的 markdown 攤成純文字。
///
/// 這個對話框用的是 `Text`，不是 markdown 元件 —— body 由 `release.yml` 產生，
/// 形狀是我們自己決定的（標題 + 分段 + 條列），所以把它讀得懂比拉一個渲染器
/// 進來便宜。**沒有渲染的東西不要留下記號**：使用者看到字面的 `###` 與 `**`
/// 就是 issue #82。
///
/// 只處理實際會出現的：ATX 標題、無序清單、粗體、行內程式碼、連續空行。
///
/// 換行照 CommonMark 的軟換行規則走：body 是以約 76 欄硬換行寫的，逐行原樣
/// 輸出會讓手機再折一次，畫面上是參差的縮排（issue #145）。所以先逐行去記號，
/// 再把同一個區塊內的行用單一空白接起來 —— 空行分區塊，`• ` 開新項目，其餘
/// 縮排續行併回目前的項目或段落。標題要在去記號**之前**認出來，否則它會跟
/// 後面的段落黏成一行。
String plainTextReleaseNotes(String source) {
  final blocks = <_NotesBlock>[];
  _NotesBlock? open;

  for (final raw in source.replaceAll('\r\n', '\n').split('\n')) {
    // 去記號後 `## A` 和 `A` 長得一樣，所以標題身分只能在這裡判定。
    final isHeading = _headingPrefix.hasMatch(raw);
    final line = _stripInlineMarkers(raw);
    if (line.trim().isEmpty) {
      open = null;
      continue;
    }
    if (isHeading) {
      blocks.add(_NotesBlock(_NotesBlockKind.heading, line.trim()));
      open = null;
      continue;
    }
    if (line.trimLeft().startsWith('• ')) {
      open = _NotesBlock(_NotesBlockKind.listItem, line);
      blocks.add(open);
      continue;
    }
    if (open == null) {
      open = _NotesBlock(_NotesBlockKind.paragraph, line.trim());
      blocks.add(open);
    } else {
      open.text = '${open.text} ${line.trim()}';
    }
  }

  final buffer = StringBuffer();
  for (var i = 0; i < blocks.length; i++) {
    if (i > 0) {
      // 區塊之間空一行；條列之間只隔一個換行。空一行是為了段落之間不要空得
      // 像內容斷掉了，但同樣的空行用在清單上會把一份清單拆成好幾段。
      final compact =
          blocks[i].kind == _NotesBlockKind.listItem &&
          blocks[i - 1].kind == _NotesBlockKind.listItem;
      buffer.write(compact ? '\n' : '\n\n');
    }
    buffer.write(blocks[i].text.trimRight());
  }
  return buffer.toString();
}

final _headingPrefix = RegExp(r'^\s{0,3}#{1,6}\s+');
final _bulletPrefix = RegExp(r'^(\s*)[-*+]\s+');
final _boldSpan = RegExp(r'\*\*(.+?)\*\*');
final _codeSpan = RegExp('`(.+?)`');

/// 逐行去掉 markdown 記號，不動換行。
String _stripInlineMarkers(String raw) {
  var line = raw.trimRight();
  line = line.replaceFirst(_headingPrefix, '');
  line = line.replaceFirstMapped(_bulletPrefix, (m) => '${m[1]}• ');
  line = line.replaceAllMapped(_boldSpan, (m) => m[1]!);
  line = line.replaceAllMapped(_codeSpan, (m) => m[1]!);
  // 跨行的粗體（開頭在這一行、收尾在下一行）逐行對不上。實機在 v1.10.0 的
  // Upgrading 段撞到過。留一次無條件清除 —— 目標是畫面上沒有記號，不是解析
  // markdown。
  line = line.replaceAll('**', '');
  return line;
}

enum _NotesBlockKind { heading, listItem, paragraph }

class _NotesBlock {
  _NotesBlock(this.kind, this.text);

  final _NotesBlockKind kind;
  String text;
}

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
    final isReadyToInstall = updateState.status == UpdateStatus.readyToInstall;
    final needsInstallPermission =
        updateState.status == UpdateStatus.installPermissionRequired;
    final hasError = updateState.status == UpdateStatus.error;
    final isBusy = isDownloading || isInstalling;

    return AlertDialog(
      // 內容高度由 release notes 決定，橫向手機根本裝不下 —— 讓整個對話框
      // 捲動，而不是替 notes 框猜一個高度上限。
      scrollable: true,
      title: Row(
        children: [
          Icon(Icons.system_update, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(t.updateDialog.title)),
          // 关闭按钮
          if (!isBusy)
            IconButton(
              onPressed: () {
                ref.read(updateProvider.notifier).reset();
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.close),
              tooltip: t.general.close,
              visualDensity: VisualDensity.compact,
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
                if (Platform.isAndroid) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: AppRadius.borderRadiusSm,
                    ),
                    child: Text(
                      updateInfo.deviceAbiLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
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
              Text(
                plainTextReleaseNotes(updateInfo.releaseNotes),
                style: theme.textTheme.bodyMedium,
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
                t.updateDialog.downloading(
                  percent: (updateState.downloadProgress * 100).toStringAsFixed(
                    0,
                  ),
                ),
                style: theme.textTheme.bodySmall,
              ),
            ],

            // 安装中
            if (isInstalling) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              Text(
                Platform.isWindows
                    ? t.updateDialog.installingRestart
                    : t.updateDialog.installingOpening,
                style: theme.textTheme.bodySmall,
              ),
            ],

            // 安装包已就绪（下载完成或安装取消后返回）
            if (isReadyToInstall) ...[
              Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    t.updateDialog.readyToInstall,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],

            if (needsInstallPermission) ...[
              Row(
                children: [
                  Icon(
                    Icons.settings_applications_outlined,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      t.updateDialog.installPermissionRequired,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // 错误信息
            if (hasError && updateState.errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: AppRadius.borderRadiusMd,
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
        if (!isBusy)
          TextButton(
            onPressed: () {
              ref.read(updateProvider.notifier).reset();
              Navigator.of(context).pop();
            },
            child: Text(t.updateDialog.later),
          ),

        // 安装包已就绪 → 直接安装
        if (needsInstallPermission)
          FilledButton.icon(
            onPressed: () => ref
                .read(updateProvider.notifier)
                .openInstallPermissionSettings(),
            icon: const Icon(Icons.settings_outlined),
            label: Text(t.updateDialog.openInstallSettings),
          ),

        if (isReadyToInstall || needsInstallPermission)
          FilledButton.icon(
            onPressed: () => ref.read(updateProvider.notifier).retryInstall(),
            icon: const Icon(Icons.install_mobile),
            label: Text(t.updateDialog.installNow),
          ),

        // 下载/重试按钮（非 readyToInstall 时显示）
        if (!isBusy && !isReadyToInstall && !needsInstallPermission)
          FilledButton.icon(
            onPressed: updateInfo.downloadUrl == null
                ? null
                : () => ref.read(updateProvider.notifier).downloadAndInstall(),
            icon: Icon(hasError ? Icons.refresh : Icons.download),
            label: Text(
              hasError ? t.updateDialog.retry : t.updateDialog.updateNow,
            ),
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
