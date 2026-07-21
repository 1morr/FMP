import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/services/toast_service.dart';
import '../../../data/models/track.dart';
import '../../../i18n/strings.g.dart';
import '../../../services/library/remote_playlist_edit_result.dart';
import '../images/playlist_cover_image.dart';
import '../images/track_thumbnail.dart';

class RemotePlaylistDialogHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;

  const RemotePlaylistDialogHeader({
    super.key,
    required this.title,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class RemotePlaylistTrackSummary extends StatelessWidget {
  final List<Track> tracks;

  const RemotePlaylistTrackSummary({
    super.key,
    required this.tracks,
  });

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.borderRadiusLg,
      ),
      child: tracks.length > 1
          ? Row(
              children: [
                Icon(Icons.music_note, color: colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  '${tracks.length} ${t.remote.tracksCount}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            )
          : Row(
              children: [
                TrackThumbnail(
                  track: tracks.first,
                  size: AppSizes.thumbnailMedium,
                  borderRadius: 4,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tracks.first.title,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        tracks.first.artist ?? '',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class RemotePlaylistCreateTile extends StatelessWidget {
  final String title;
  final VoidCallback? onTap;

  const RemotePlaylistCreateTile({
    super.key,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: AppRadius.borderRadiusMd,
          ),
          child: Icon(
            Icons.add,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(title),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderRadiusLg,
        ),
        onTap: onTap,
      ),
    );
  }
}

class RemotePlaylistListTile extends StatelessWidget {
  final String? imageUrl;
  final IconData fallbackIcon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final bool isPartial;
  final bool isChecking;
  final VoidCallback onTap;

  const RemotePlaylistListTile({
    super.key,
    required this.imageUrl,
    required this.fallbackIcon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.isPartial,
    required this.isChecking,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: AppRadius.borderRadiusMd,
          color: colorScheme.surfaceContainerHighest,
        ),
        clipBehavior: Clip.antiAlias,
        child: imageUrl != null
            ? PlaylistCoverImage(
                networkUrl: imageUrl,
                placeholder: Icon(fallbackIcon, color: colorScheme.outline),
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                variant: PlaylistCoverVariant.compact,
              )
            : Icon(fallbackIcon, color: colorScheme.outline),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: RemotePlaylistSelectionIndicator(
        isChecking: isChecking,
        isSelected: isSelected,
        isPartial: isPartial,
      ),
      selected: isSelected || isPartial,
      selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadiusLg,
      ),
      onTap: onTap,
    );
  }
}

/// 播放清單空態：本地與遠端「加入播放清單」對話框共用。
class RemotePlaylistEmptyState extends StatelessWidget {
  final String title;
  final String hint;

  const RemotePlaylistEmptyState({
    super.key,
    required this.title,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_music,
            size: 48,
            color: colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}

class RemotePlaylistSelectionIndicator extends StatelessWidget {
  final bool isChecking;
  final bool isSelected;
  final bool isPartial;

  const RemotePlaylistSelectionIndicator({
    super.key,
    required this.isChecking,
    required this.isSelected,
    required this.isPartial,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (isChecking) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (isSelected) {
      return Icon(Icons.check_circle, color: colorScheme.primary);
    }
    if (isPartial) {
      return Icon(Icons.remove_circle_outline, color: colorScheme.primary);
    }
    return Icon(Icons.circle_outlined, color: colorScheme.outline);
  }
}

/// Bilibili / NetEase 建立遠端播放清單共用的公開/私人兩段隱私選項。
/// YouTube 另有 UNLISTED 段，由呼叫端自行組裝 segments。
List<ButtonSegment<bool>> remotePlaylistPrivacySegments() => [
      ButtonSegment(
        value: false,
        label: Text(t.remote.privacyPublic),
        icon: const Icon(Icons.public, size: 18),
      ),
      ButtonSegment(
        value: true,
        label: Text(t.remote.privacyPrivate),
        icon: const Icon(Icons.lock, size: 18),
      ),
    ];

/// 三個遠端「加入播放清單」對話框共用的建立播放清單 AlertDialog。
///
/// 隱私選項以泛型 [T] 表示（Bilibili/NetEase 用 bool，YouTube 用
/// privacyStatus 字串），呼叫端提供 [privacySegments] 與 [initialPrivacy]。
/// 回傳輸入的名稱與所選隱私值；取消時回傳 null。
Future<({String name, T privacy})?> showCreateRemotePlaylistDialog<T>({
  required BuildContext context,
  required String title,
  required String hint,
  required T initialPrivacy,
  required List<ButtonSegment<T>> privacySegments,
}) async {
  final controller = TextEditingController();
  try {
    var privacy = initialPrivacy;
    return await showDialog<({String name, T privacy})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: hint,
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    Navigator.pop(
                      context,
                      (name: value.trim(), privacy: privacy),
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
              SegmentedButton<T>(
                segments: privacySegments,
                selected: {privacy},
                onSelectionChanged: (values) =>
                    setDialogState(() => privacy = values.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.general.cancel),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  Navigator.pop(context, (name: name, privacy: privacy));
                }
              },
              child: Text(t.general.confirm),
            ),
          ],
        ),
      ),
    );
  } finally {
    controller.dispose();
  }
}

/// 三個遠端「加入播放清單」對話框 `_submit` 共用的結果回報序列。
///
/// 部分成功（有遠端變更但也有失敗）必須先於完全成功提示；
/// [onSuccess] 在兩種成功路徑下呼叫（通常是 pop(true)）。
/// 失敗或無變更時只提示，不呼叫 [onSuccess]，由呼叫端重置提交狀態。
void reportRemotePlaylistEditResult(
  BuildContext context,
  RemotePlaylistEditResult result, {
  required VoidCallback onSuccess,
}) {
  if (result.changedRemote && result.hasFailures) {
    final summary = result.summary;
    final successCount = summary.addedTrackCount + summary.removedTrackCount;
    final totalCount = successCount + summary.failedTrackCount;
    ToastService.warning(
      context,
      t.addToPlaylistDialog.partiallyCompleted(
        success: successCount,
        total: totalCount,
      ),
    );
    onSuccess();
    return;
  }
  if (result.changedRemote) {
    ToastService.success(context, t.remote.updated);
    onSuccess();
    return;
  }
  if (result.hasFailures) {
    ToastService.error(context, result.failures.first.error.toString());
  } else {
    ToastService.show(context, t.remote.noChanges);
  }
}
