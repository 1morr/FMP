import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/audio/audio_settings_provider.dart';

/// 音频质量设置页面
class AudioSettingsPage extends ConsumerWidget {
  const AudioSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioSettings = ref.watch(audioSettingsProvider);
    final sources = ref.watch(registeredSourceTypesProvider);

    if (audioSettings.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(t.audioSettings.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(t.audioSettings.title)),
      body: ListView(
        children: [
          // 憑證儲存讀不到時本頁仍然載入完成（#89），但要說明為什麼 —— 沉默
          // 降級會讓使用者以為金鑰被清掉了。
          if (audioSettings.secureStorageUnavailable)
            const _SecureStorageUnavailableNotice(),
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
              ref
                  .read(audioSettingsProvider.notifier)
                  .setFormatPriority(newPriority);
            },
          ),
          const Divider(),
          // 每個音源一段串流優先序，可選的類型就是它預設優先序裡的那幾種
          for (final source in sources) ...[
            _StreamPrioritySection(
              title:
                  _perSourceText(
                    'audioSettings.streamPriority.${source}Title',
                  ) ??
                  SourceIds.displayNameFor(source),
              streamPriority: audioSettings.streamPriorityFor(source),
              availableTypes: defaultStreamPriorityFor(source),
              onReorder: (newPriority) {
                ref
                    .read(audioSettingsProvider.notifier)
                    .setStreamPriority(source, newPriority);
              },
            ),
            const Divider(),
          ],
          _AuthForPlaySection(
            sources: sources,
            authForPlay: audioSettings.authForPlay,
            onChanged: (sourceType, enabled) {
              ref
                  .read(audioSettingsProvider.notifier)
                  .setAuthForPlay(sourceType, enabled);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// 憑證儲存這次讀不出來的提示。
///
/// 說「讀不到」而不是「沒有設定」：Android Keystore 在裝置還原後、Windows
/// DPAPI 在使用者設定檔重建後都會解不開既有密文，金鑰其實還在（#89）。
class _SecureStorageUnavailableNotice extends StatelessWidget {
  const _SecureStorageUnavailableNotice();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.lock_outline, color: colorScheme.error),
      title: Text(
        t.audioSettings.secureStorageUnavailable.title,
        style: TextStyle(color: colorScheme.error),
      ),
      subtitle: Text(t.audioSettings.secureStorageUnavailable.description),
      isThreeLine: true,
    );
  }
}

/// 依音源 id 組出來的翻譯鍵；這個音源沒有專屬文案時回 null。
String? _perSourceText(String key) {
  final value = t[key];
  return value is String ? value : null;
}

class _AuthForPlaySection extends StatelessWidget {
  final List<String> sources;
  final bool Function(String sourceType) authForPlay;
  final void Function(String sourceType, bool enabled) onChanged;

  const _AuthForPlaySection({
    required this.sources,
    required this.authForPlay,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            t.audioSettings.authForPlay.title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: colorScheme.primary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            t.audioSettings.authForPlay.subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final source in sources)
          SwitchListTile(
            title: Text(SourceIds.displayNameFor(source)),
            subtitle: switch (_perSourceText(
              'audioSettings.authForPlay.${source}Description',
            )) {
              final description? => Text(description),
              null => null,
            },
            value: authForPlay(source),
            onChanged: (enabled) => onChanged(source, enabled),
          ),
      ],
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
          onReorderItem: (oldIndex, newIndex) {
            final newList = List<AudioFormat>.from(formatPriority);
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
    final displayList = streamPriority
        .where((t) => availableTypes.contains(t))
        .toList();
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
          onReorderItem: (oldIndex, newIndex) {
            final newList = List<StreamType>.from(displayList);
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
