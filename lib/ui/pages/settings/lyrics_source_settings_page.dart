import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simple_icons/simple_icons.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/services/toast_service.dart';
import '../../../data/models/settings.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/audio_settings_provider.dart';
import '../../../providers/repository_providers.dart';

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
  late final TextEditingController _endpointController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late final TextEditingController _timeoutController;

  @override
  void initState() {
    super.initState();
    final audioSettings = ref.read(audioSettingsProvider);
    _sourceOrder = List.from(audioSettings.lyricsSourceOrder);
    _disabledSources = Set.from(audioSettings.disabledLyricsSources);
    _endpointController =
        TextEditingController(text: audioSettings.lyricsAiEndpoint);
    _apiKeyController = TextEditingController();
    _modelController = TextEditingController(text: audioSettings.lyricsAiModel);
    _timeoutController = TextEditingController(
      text: audioSettings.lyricsAiTimeoutSeconds.toString(),
    );
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _timeoutController.dispose();
    super.dispose();
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
    ref
        .read(audioSettingsProvider.notifier)
        .toggleLyricsSource(source, enabled);
  }

  void _syncControllers(AudioSettingsState audioSettings) {
    if (!_endpointController.selection.isValid &&
        _endpointController.text != audioSettings.lyricsAiEndpoint) {
      _endpointController.text = audioSettings.lyricsAiEndpoint;
    }
    if (!_modelController.selection.isValid &&
        _modelController.text != audioSettings.lyricsAiModel) {
      _modelController.text = audioSettings.lyricsAiModel;
    }
    final timeoutText = audioSettings.lyricsAiTimeoutSeconds.toString();
    if (!_timeoutController.selection.isValid &&
        _timeoutController.text != timeoutText) {
      _timeoutController.text = timeoutText;
    }
  }

  String _getModeLabel(LyricsAiTitleParsingMode mode) {
    switch (mode) {
      case LyricsAiTitleParsingMode.off:
        return t.settings.lyricsSourceSettings.aiModeOff;
      case LyricsAiTitleParsingMode.fallbackAfterRules:
        return t.settings.lyricsSourceSettings.aiModeFallback;
      case LyricsAiTitleParsingMode.alwaysForVideoSources:
        return t.settings.lyricsSourceSettings.aiModeAlways;
    }
  }

  Future<void> _clearAiParseCache() async {
    await ref.read(lyricsTitleParseCacheRepositoryProvider).clear();
    if (mounted) {
      ToastService.show(
        context,
        t.settings.lyricsSourceSettings.aiClearCacheDone,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final audioSettings = ref.watch(audioSettingsProvider);
    _syncControllers(audioSettings);

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
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverReorderableList(
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
                      borderRadius: AppRadius.borderRadiusLg,
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
                SliverToBoxAdapter(
                  child: _AiTitleParsingSection(
                    audioSettings: audioSettings,
                    endpointController: _endpointController,
                    apiKeyController: _apiKeyController,
                    modelController: _modelController,
                    timeoutController: _timeoutController,
                    modeLabelBuilder: _getModeLabel,
                    onModeChanged: (mode) => ref
                        .read(audioSettingsProvider.notifier)
                        .setLyricsAiTitleParsingMode(mode),
                    onEndpointSubmitted: (value) => ref
                        .read(audioSettingsProvider.notifier)
                        .setLyricsAiEndpoint(value),
                    onApiKeySubmitted: (value) async {
                      if (value.trim().isEmpty) return;
                      await ref
                          .read(audioSettingsProvider.notifier)
                          .setLyricsAiApiKey(value);
                      _apiKeyController.clear();
                    },
                    onModelSubmitted: (value) => ref
                        .read(audioSettingsProvider.notifier)
                        .setLyricsAiModel(value),
                    onTimeoutChanged: (seconds) => ref
                        .read(audioSettingsProvider.notifier)
                        .setLyricsAiTimeoutSeconds(seconds),
                    onClearCache: _clearAiParseCache,
                  ),
                ),
              ],
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
    const disabledAlpha = 0.38;

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

class _AiTitleParsingSection extends StatelessWidget {
  final AudioSettingsState audioSettings;
  final TextEditingController endpointController;
  final TextEditingController apiKeyController;
  final TextEditingController modelController;
  final TextEditingController timeoutController;
  final String Function(LyricsAiTitleParsingMode mode) modeLabelBuilder;
  final ValueChanged<LyricsAiTitleParsingMode> onModeChanged;
  final ValueChanged<String> onEndpointSubmitted;
  final Future<void> Function(String value) onApiKeySubmitted;
  final ValueChanged<String> onModelSubmitted;
  final ValueChanged<int> onTimeoutChanged;
  final Future<void> Function() onClearCache;

  const _AiTitleParsingSection({
    required this.audioSettings,
    required this.endpointController,
    required this.apiKeyController,
    required this.modelController,
    required this.timeoutController,
    required this.modeLabelBuilder,
    required this.onModeChanged,
    required this.onEndpointSubmitted,
    required this.onApiKeySubmitted,
    required this.onModelSubmitted,
    required this.onTimeoutChanged,
    required this.onClearCache,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.settings.lyricsSourceSettings.aiSectionTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                t.settings.lyricsSourceSettings.aiPrivacyHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<LyricsAiTitleParsingMode>(
                initialValue: audioSettings.lyricsAiTitleParsingMode,
                decoration: InputDecoration(
                  labelText: t.settings.lyricsSourceSettings.aiMode,
                  border: const OutlineInputBorder(),
                ),
                items: LyricsAiTitleParsingMode.values
                    .map(
                      (mode) => DropdownMenuItem(
                        value: mode,
                        child: Text(modeLabelBuilder(mode)),
                      ),
                    )
                    .toList(),
                onChanged: (mode) {
                  if (mode != null) onModeChanged(mode);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: endpointController,
                decoration: InputDecoration(
                  labelText: t.settings.lyricsSourceSettings.aiEndpoint,
                  hintText: t.settings.lyricsSourceSettings.aiEndpointHint,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onSubmitted: onEndpointSubmitted,
                onTapOutside: (_) =>
                    onEndpointSubmitted(endpointController.text),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: apiKeyController,
                decoration: InputDecoration(
                  labelText: t.settings.lyricsSourceSettings.aiApiKey,
                  helperText: audioSettings.lyricsAiApiKeyConfigured
                      ? t.settings.lyricsSourceSettings.aiApiKeyConfigured
                      : t.settings.lyricsSourceSettings.aiApiKeyEmpty,
                  border: const OutlineInputBorder(),
                ),
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                onSubmitted: onApiKeySubmitted,
                onTapOutside: (_) => onApiKeySubmitted(apiKeyController.text),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: modelController,
                decoration: InputDecoration(
                  labelText: t.settings.lyricsSourceSettings.aiModel,
                  hintText: t.settings.lyricsSourceSettings.aiModelHint,
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: onModelSubmitted,
                onTapOutside: (_) => onModelSubmitted(modelController.text),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: timeoutController,
                decoration: InputDecoration(
                  labelText: t.settings.lyricsSourceSettings.aiTimeout,
                  suffixText: t.settings.lyricsSourceSettings.aiTimeoutUnit,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.done,
                onSubmitted: (value) => onTimeoutChanged(
                  int.tryParse(value) ?? audioSettings.lyricsAiTimeoutSeconds,
                ),
                onTapOutside: (_) => onTimeoutChanged(
                  int.tryParse(timeoutController.text) ??
                      audioSettings.lyricsAiTimeoutSeconds,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: onClearCache,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: Text(t.settings.lyricsSourceSettings.aiClearCache),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
