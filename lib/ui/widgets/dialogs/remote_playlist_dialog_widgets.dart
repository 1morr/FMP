import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/services/image_loading_service.dart';
import '../../../data/models/track.dart';
import '../../../i18n/strings.g.dart';
import '../track_thumbnail.dart';

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
            ? ImageLoadingService.loadImage(
                networkUrl: imageUrl,
                placeholder: Icon(fallbackIcon, color: colorScheme.outline),
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                targetDisplaySize: 40,
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
