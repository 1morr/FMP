import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simple_icons/simple_icons.dart';

import '../../../i18n/strings.g.dart';
import '../../../providers/audio_settings_provider.dart';

/// 歌词匹配源设置页面
///
/// 支持拖动排序歌词源优先级，以及启用/禁用单个歌词源。
class LyricsSourceSettingsPage extends ConsumerStatefulWidget {
  const LyricsSourceSettingsPage({super.key});

  @override
  ConsumerState<LyricsSourceSettingsPage> createState() =>
      _LyricsSourceSettingsPageState();
}

class _LyricsSourceSettingsPageState
    extends ConsumerState<LyricsSourceSettingsPage> {
  late List<String> _sourceOrder;
  late Set<String> _disabledSources;

  @override
  void initState() {
    super.initState();
    final audioSettings = ref.read(audioSettingsProvider);
    _sourceOrder = List.from(audioSettings.lyricsSourceOrder);
    _disabledSources = Set.from(audioSettings.disabledLyricsSources);
  }

  String _getSourceDisplayName(String source) {
    switch (source) {
      case 'netease':
        return t.settings.lyricsSourceSettings.sourceNetease;
      case 'qqmusic':
        return t.settings.lyricsSourceSettings.sourceQQMusic;
      case 'lrclib':
        return t.settings.lyricsSourceSettings.sourceLrclib;
      default:
        return source;
    }
  }

  IconData _getSourceIcon(String source) {
    switch (source) {
      case 'netease':
        return SimpleIcons.neteasecloudmusic;
      case 'qqmusic':
        return SimpleIcons.qq;
      case 'lrclib':
        return Icons.library_music_outlined;
      default:
        return Icons.source_outlined;
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _sourceOrder.removeAt(oldIndex);
      _sourceOrder.insert(newIndex, item);
    });
    ref.read(audioSettingsProvider.notifier).setLyricsSourceOrder(_sourceOrder);
  }

  void _onToggleSource(String source, bool enabled) {
    setState(() {
      if (enabled) {
        _disabledSources.remove(source);
      } else {
        _disabledSources.add(source);
      }
    });
    ref.read(audioSettingsProvider.notifier).toggleLyricsSource(source, enabled);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.settings.lyricsSourceSettings.title),
      ),
      body: Column(
        children: [
          // 提示信息
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.settings.lyricsSourceSettings.hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          // 可排序列表
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: _sourceOrder.length,
              onReorder: _onReorder,
              proxyDecorator: (child, index, animation) {
                final elevation = Tween<double>(begin: 0, end: 4)
                    .animate(CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeInOut,
                    ))
                    .value;
                return Material(
                  elevation: elevation,
                  borderRadius: BorderRadius.circular(12),
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final source = _sourceOrder[index];
                final isEnabled = !_disabledSources.contains(source);
                final displayName = _getSourceDisplayName(source);
                final icon = _getSourceIcon(source);

                return _LyricsSourceTile(
                  key: ValueKey(source),
                  index: index,
                  source: source,
                  displayName: displayName,
                  icon: icon,
                  isEnabled: isEnabled,
                  onToggle: (enabled) => _onToggleSource(source, enabled),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LyricsSourceTile extends StatelessWidget {
  final int index;
  final String source;
  final String displayName;
  final IconData icon;
  final bool isEnabled;
  final ValueChanged<bool> onToggle;

  const _LyricsSourceTile({
    super.key,
    required this.index,
    required this.source,
    required this.displayName,
    required this.icon,
    required this.isEnabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final disabledAlpha = 0.38;

    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Icon(
              Icons.drag_handle,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            icon,
            size: 20,
            color: isEnabled
                ? colorScheme.onSurface
                : colorScheme.onSurface.withValues(alpha: disabledAlpha),
          ),
        ],
      ),
      title: Text(
        displayName,
        style: TextStyle(
          color: isEnabled
              ? null
              : colorScheme.onSurface.withValues(alpha: disabledAlpha),
        ),
      ),
      subtitle: Text(
        isEnabled
            ? t.settings.lyricsSourceSettings.enabled
            : t.settings.lyricsSourceSettings.disabled,
        style: TextStyle(
          color: isEnabled
              ? colorScheme.primary
              : colorScheme.onSurface.withValues(alpha: disabledAlpha),
          fontSize: 12,
        ),
      ),
      trailing: Switch(
        value: isEnabled,
        onChanged: (value) => onToggle(value),
      ),
    );
  }
}
