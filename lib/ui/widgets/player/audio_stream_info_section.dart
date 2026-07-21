import 'package:flutter/material.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../data/models/settings.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/audio/audio_player_selectors.dart';

/// 音频技术信息区块（码率 / 封装格式 / 编码 / 流类型）。
///
/// 全屏播放器資訊彈窗與桌面 Detail Panel 共用。播放器彈窗自帶前置
/// Divider（[showLeadingDivider] 預設 true）；面板在呼叫處已有分隔線，
/// 傳 false 關閉。
class AudioStreamInfoSection extends StatelessWidget {
  final CurrentStreamMetadata metadata;

  /// 是否在區塊前渲染間距 + Divider。
  final bool showLeadingDivider;

  const AudioStreamInfoSection({
    super.key,
    required this.metadata,
    this.showLeadingDivider = true,
  });

  // 格式化码率显示
  static String? formatBitrate(int? bitrate) {
    if (bitrate == null) return null;
    if (bitrate >= 1000) {
      return '${(bitrate / 1000).toStringAsFixed(0)} kbps';
    }
    return '$bitrate bps';
  }

  // 格式化流类型显示
  static String? formatStreamType(StreamType? type) {
    if (type == null) return null;
    switch (type) {
      case StreamType.audioOnly:
        return t.player.audioOnly;
      case StreamType.muxed:
        return t.player.muxedStream;
      case StreamType.hls:
        return 'HLS';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final bitrate = formatBitrate(metadata.bitrate);
    final container = metadata.container?.toUpperCase();
    final codec = metadata.codec?.toUpperCase();
    final streamType = formatStreamType(metadata.streamType);

    // 如果没有任何信息，不显示此部分
    if (bitrate == null &&
        container == null &&
        codec == null &&
        streamType == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLeadingDivider) ...[
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 16),
        ],

        // 标题
        Row(
          children: [
            Icon(
              Icons.graphic_eq,
              size: 18,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              t.player.audioInfo,
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 信息标签
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (bitrate != null) _buildInfoChip(context, Icons.speed, bitrate),
            if (container != null)
              _buildInfoChip(context, Icons.folder_outlined, container),
            if (codec != null)
              _buildInfoChip(context, Icons.audiotrack_outlined, codec),
            if (streamType != null)
              _buildInfoChip(context, Icons.stream, streamType),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoChip(BuildContext context, IconData icon, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.borderRadiusXl,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
