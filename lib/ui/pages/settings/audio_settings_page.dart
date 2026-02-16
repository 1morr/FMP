import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/settings.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/audio_settings_provider.dart';

/// 音频质量设置页面
class AudioSettingsPage extends ConsumerWidget {
  const AudioSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioSettings = ref.watch(audioSettingsProvider);

    if (audioSettings.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(t.audioSettings.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.audioSettings.title),
      ),
      body: ListView(
        children: [
          // 音质等级
          _QualityLevelSection(
            currentLevel: audioSettings.qualityLevel,
            onChanged: (level) {
              ref.read(audioSettingsProvider.notifier).setQualityLevel(level);
            },
          ),
          const Divider(),
          // 格式优先级
          _FormatPrioritySection(
            formatPriority: audioSettings.formatPriority,
            onReorder: (newPriority) {
              ref.read(audioSettingsProvider.notifier).setFormatPriority(newPriority);
            },
          ),
          const Divider(),
          // YouTube 流优先级
          _StreamPrioritySection(
            title: t.audioSettings.streamPriority.youtubeTitle,
            streamPriority: audioSettings.youtubeStreamPriority,
            availableTypes: const [StreamType.audioOnly, StreamType.muxed, StreamType.hls],
            onReorder: (newPriority) {
              ref.read(audioSettingsProvider.notifier).setYoutubeStreamPriority(newPriority);
            },
          ),
          const Divider(),
          // Bilibili 流优先级
          _StreamPrioritySection(
            title: t.audioSettings.streamPriority.bilibiliTitle,
            streamPriority: audioSettings.bilibiliStreamPriority,
            availableTypes: const [StreamType.audioOnly, StreamType.muxed],
            onReorder: (newPriority) {
              ref.read(audioSettingsProvider.notifier).setBilibiliStreamPriority(newPriority);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// 音质等级选择区块
class _QualityLevelSection extends StatelessWidget {
  final AudioQualityLevel currentLevel;
  final ValueChanged<AudioQualityLevel> onChanged;

  const _QualityLevelSection({
    required this.currentLevel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            t.audioSettings.qualityLevel.title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            t.audioSettings.qualityLevel.subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        RadioGroup<AudioQualityLevel>(
          groupValue: currentLevel,
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
          child: Column(
            children: [
              RadioListTile<AudioQualityLevel>(
                title: Text(t.audioSettings.qualityLevel.high),
                subtitle: Text(t.audioSettings.qualityLevel.highDescription),
                value: AudioQualityLevel.high,
              ),
              RadioListTile<AudioQualityLevel>(
                title: Text(t.audioSettings.qualityLevel.medium),
                subtitle: Text(t.audioSettings.qualityLevel.mediumDescription),
                value: AudioQualityLevel.medium,
              ),
              RadioListTile<AudioQualityLevel>(
                title: Text(t.audioSettings.qualityLevel.low),
                subtitle: Text(t.audioSettings.qualityLevel.lowDescription),
                value: AudioQualityLevel.low,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 格式优先级区块（可拖拽排序）
class _FormatPrioritySection extends StatelessWidget {
  final List<AudioFormat> formatPriority;
  final ValueChanged<List<AudioFormat>> onReorder;

  const _FormatPrioritySection({
    required this.formatPriority,
    required this.onReorder,
  });

  String _getFormatName(AudioFormat format) {
    switch (format) {
      case AudioFormat.opus:
        return t.audioSettings.formatPriority.opusName;
      case AudioFormat.aac:
        return t.audioSettings.formatPriority.aacName;
    }
  }

  String _getFormatDescription(AudioFormat format) {
    switch (format) {
      case AudioFormat.opus:
        return t.audioSettings.formatPriority.opusDescription;
      case AudioFormat.aac:
        return t.audioSettings.formatPriority.aacDescription;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            t.audioSettings.formatPriority.title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            t.audioSettings.formatPriority.subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        const SizedBox(height: 8),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: formatPriority.length,
          onReorder: (oldIndex, newIndex) {
            final newList = List<AudioFormat>.from(formatPriority);
            if (newIndex > oldIndex) newIndex--;
            final item = newList.removeAt(oldIndex);
            newList.insert(newIndex, item);
            onReorder(newList);
          },
          itemBuilder: (context, index) {
            final format = formatPriority[index];
            return ListTile(
              key: ValueKey(format),
              leading: ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle),
              ),
              title: Text('${index + 1}. ${_getFormatName(format)}'),
              subtitle: Text(_getFormatDescription(format)),
            );
          },
        ),
      ],
    );
  }
}

/// 流类型优先级区块（可拖拽排序）
class _StreamPrioritySection extends StatelessWidget {
  final String title;
  final List<StreamType> streamPriority;
  final List<StreamType> availableTypes;
  final ValueChanged<List<StreamType>> onReorder;

  const _StreamPrioritySection({
    required this.title,
    required this.streamPriority,
    required this.availableTypes,
    required this.onReorder,
  });

  String _getStreamTypeName(StreamType type) {
    switch (type) {
      case StreamType.audioOnly:
        return t.audioSettings.streamPriority.audioOnly;
      case StreamType.muxed:
        return t.audioSettings.streamPriority.muxed;
      case StreamType.hls:
        return t.audioSettings.streamPriority.hls;
    }
  }

  String _getStreamTypeDescription(StreamType type) {
    switch (type) {
      case StreamType.audioOnly:
        return t.audioSettings.streamPriority.audioOnlyDescription;
      case StreamType.muxed:
        return t.audioSettings.streamPriority.muxedDescription;
      case StreamType.hls:
        return t.audioSettings.streamPriority.hlsDescription;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 只显示可用的流类型
    final displayList = streamPriority.where((t) => availableTypes.contains(t)).toList();
    // 添加缺失的可用类型到末尾
    for (final type in availableTypes) {
      if (!displayList.contains(type)) {
        displayList.add(type);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: displayList.length,
          onReorder: (oldIndex, newIndex) {
            final newList = List<StreamType>.from(displayList);
            if (newIndex > oldIndex) newIndex--;
            final item = newList.removeAt(oldIndex);
            newList.insert(newIndex, item);
            onReorder(newList);
          },
          itemBuilder: (context, index) {
            final type = displayList[index];
            return ListTile(
              key: ValueKey(type),
              leading: ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle),
              ),
              title: Text('${index + 1}. ${_getStreamTypeName(type)}'),
              subtitle: Text(_getStreamTypeDescription(type)),
            );
          },
        ),
      ],
    );
  }
}
