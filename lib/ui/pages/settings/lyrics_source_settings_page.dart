import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simple_icons/simple_icons.dart';

import '../../../core/constants/ui_constants.dart';
import '../../../core/services/toast_service.dart';
import '../../../data/models/settings.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/audio_settings_provider.dart';
import '../../../providers/lyrics_provider.dart';

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
      case LyricsAiTitleParsingMode.alwaysAi:
        return t.settings.lyricsSourceSettings.aiModeAlways;
    }
  }

  Future<void> _saveLyricsAiEndpoint(String endpoint) async {
    final normalized = endpoint.trim();
    await ref
        .read(audioSettingsProvider.notifier)
        .setLyricsAiEndpoint(normalized);
    _endpointController.text = normalized;
  }

  Future<void> _saveLyricsAiModel(String model) async {
    final normalized = model.trim();
    await ref.read(audioSettingsProvider.notifier).setLyricsAiModel(normalized);
    _modelController.text = normalized;
  }

  Future<void> _saveLyricsAiTimeoutSeconds(int seconds) async {
    final normalized = seconds < 1 ? 10 : seconds;
    await ref
        .read(audioSettingsProvider.notifier)
        .setLyricsAiTimeoutSeconds(normalized);
    _timeoutController.text = normalized.toString();
  }

  Future<void> _saveLyricsAiApiKey(String apiKey) async {
    if (apiKey.trim().isEmpty) return;
    await ref.read(audioSettingsProvider.notifier).setLyricsAiApiKey(apiKey);
    _apiKeyController.clear();
  }

  Future<void> _clearLyricsAiApiKey() async {
    await ref.read(audioSettingsProvider.notifier).setLyricsAiApiKey('');
    _apiKeyController.clear();
  }

  Future<void> _testLyricsAiConnection() async {
    await _saveLyricsAiEndpoint(_endpointController.text);
    await _saveLyricsAiModel(_modelController.text);
    await _saveLyricsAiTimeoutSeconds(
      int.tryParse(_timeoutController.text) ??
          ref.read(audioSettingsProvider).lyricsAiTimeoutSeconds,
    );
    if (_apiKeyController.text.trim().isNotEmpty) {
      await _saveLyricsAiApiKey(_apiKeyController.text);
    }

    final config = await ref.read(lyricsAiConfigServiceProvider).loadConfig();
    if (config.endpoint.isEmpty ||
        config.apiKey.isEmpty ||
        config.model.isEmpty) {
      if (mounted) {
        ToastService.warning(
          context,
          t.settings.lyricsSourceSettings.aiTestMissingConfig,
        );
      }
      return;
    }

    final result = await ref.read(aiTitleParserProvider).parse(
          endpoint: config.endpoint,
          apiKey: config.apiKey,
          model: config.model,
          title: '【MV】YOASOBI「アイドル」Official Music Video',
          timeoutSeconds: config.timeoutSeconds,
        );

    if (!mounted) return;
    if (result == null) {
      ToastService.error(
        context,
        t.settings.lyricsSourceSettings.aiTestFailed,
      );
      return;
    }

    final artist = result.artistName;
    ToastService.success(
      context,
      artist == null || artist.isEmpty
          ? t.settings.lyricsSourceSettings.aiTestSuccess(
              track: result.trackName,
            )
          : t.settings.lyricsSourceSettings.aiTestSuccessWithArtist(
              track: result.trackName,
              artist: artist,
            ),
    );
  }

  Future<void> _showLyricsAiSettingsDialog() async {
    _syncControllers(ref.read(audioSettingsProvider));
    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final audioSettings = ref.watch(audioSettingsProvider);
          return _AiTitleParsingSettingsDialog(
            audioSettings: audioSettings,
            endpointController: _endpointController,
            apiKeyController: _apiKeyController,
            modelController: _modelController,
            timeoutController: _timeoutController,
            modeLabelBuilder: _getModeLabel,
            onModeChanged: (mode) => ref
                .read(audioSettingsProvider.notifier)
                .setLyricsAiTitleParsingMode(mode),
            onEndpointSubmitted: _saveLyricsAiEndpoint,
            onApiKeySubmitted: _saveLyricsAiApiKey,
            onClearApiKey: _clearLyricsAiApiKey,
            onModelSubmitted: _saveLyricsAiModel,
            onTimeoutChanged: _saveLyricsAiTimeoutSeconds,
            onTestAi: _testLyricsAiConnection,
          );
        },
      ),
    );
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
        actions: [
          IconButton(
            tooltip: t.settings.lyricsSourceSettings.aiSectionTitle,
            icon: const Icon(Icons.smart_toy_outlined),
            onPressed: _showLyricsAiSettingsDialog,
          ),
          const SizedBox(width: 8),
        ],
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

class _AiTitleParsingSettingsDialog extends StatefulWidget {
  final AudioSettingsState audioSettings;
  final TextEditingController endpointController;
  final TextEditingController apiKeyController;
  final TextEditingController modelController;
  final TextEditingController timeoutController;
  final String Function(LyricsAiTitleParsingMode mode) modeLabelBuilder;
  final ValueChanged<LyricsAiTitleParsingMode> onModeChanged;
  final Future<void> Function(String value) onEndpointSubmitted;
  final Future<void> Function(String value) onApiKeySubmitted;
  final Future<void> Function() onClearApiKey;
  final Future<void> Function(String value) onModelSubmitted;
  final Future<void> Function(int seconds) onTimeoutChanged;
  final Future<void> Function() onTestAi;

  const _AiTitleParsingSettingsDialog({
    required this.audioSettings,
    required this.endpointController,
    required this.apiKeyController,
    required this.modelController,
    required this.timeoutController,
    required this.modeLabelBuilder,
    required this.onModeChanged,
    required this.onEndpointSubmitted,
    required this.onApiKeySubmitted,
    required this.onClearApiKey,
    required this.onModelSubmitted,
    required this.onTimeoutChanged,
    required this.onTestAi,
  });

  @override
  State<_AiTitleParsingSettingsDialog> createState() =>
      _AiTitleParsingSettingsDialogState();
}

class _AiTitleParsingSettingsDialogState
    extends State<_AiTitleParsingSettingsDialog> {
  bool _isTesting = false;

  Future<void> _testAi() async {
    setState(() => _isTesting = true);
    try {
      await widget.onTestAi();
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.smart_toy_outlined, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(t.settings.lyricsSourceSettings.aiSectionTitle)),
          IconButton(
            onPressed: _isTesting ? null : () => Navigator.of(context).pop(),
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<LyricsAiTitleParsingMode>(
                initialValue: widget.audioSettings.lyricsAiTitleParsingMode,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t.settings.lyricsSourceSettings.aiMode,
                  prefixIcon: const Icon(Icons.tune_outlined),
                  border: const OutlineInputBorder(),
                ),
                items: LyricsAiTitleParsingMode.values
                    .map(
                      (mode) => DropdownMenuItem(
                        value: mode,
                        child: Text(widget.modeLabelBuilder(mode)),
                      ),
                    )
                    .toList(),
                onChanged: (mode) {
                  if (mode != null) widget.onModeChanged(mode);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: widget.endpointController,
                decoration: InputDecoration(
                  labelText: t.settings.lyricsSourceSettings.aiEndpoint,
                  hintText: t.settings.lyricsSourceSettings.aiEndpointHint,
                  prefixIcon: const Icon(Icons.link_outlined),
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onSubmitted: widget.onEndpointSubmitted,
                onTapOutside: (_) =>
                    widget.onEndpointSubmitted(widget.endpointController.text),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: widget.apiKeyController,
                decoration: InputDecoration(
                  labelText: t.settings.lyricsSourceSettings.aiApiKey,
                  helperText: widget.audioSettings.lyricsAiApiKeyConfigured
                      ? t.settings.lyricsSourceSettings.aiApiKeyConfigured
                      : t.settings.lyricsSourceSettings.aiApiKeyEmpty,
                  prefixIcon: const Icon(Icons.key_outlined),
                  border: const OutlineInputBorder(),
                ),
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                onSubmitted: widget.onApiKeySubmitted,
                onTapOutside: (_) =>
                    widget.onApiKeySubmitted(widget.apiKeyController.text),
              ),
              if (widget.audioSettings.lyricsAiApiKeyConfigured) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _isTesting ? null : widget.onClearApiKey,
                    icon: const Icon(Icons.key_off_outlined),
                    label: Text(t.settings.lyricsSourceSettings.aiClearApiKey),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: widget.modelController,
                decoration: InputDecoration(
                  labelText: t.settings.lyricsSourceSettings.aiModel,
                  hintText: t.settings.lyricsSourceSettings.aiModelHint,
                  prefixIcon: const Icon(Icons.memory_outlined),
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: widget.onModelSubmitted,
                onTapOutside: (_) =>
                    widget.onModelSubmitted(widget.modelController.text),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: widget.timeoutController,
                decoration: InputDecoration(
                  labelText: t.settings.lyricsSourceSettings.aiTimeout,
                  suffixText: t.settings.lyricsSourceSettings.aiTimeoutUnit,
                  prefixIcon: const Icon(Icons.timer_outlined),
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.done,
                onSubmitted: (value) => widget.onTimeoutChanged(
                  int.tryParse(value) ??
                      widget.audioSettings.lyricsAiTimeoutSeconds,
                ),
                onTapOutside: (_) => widget.onTimeoutChanged(
                  int.tryParse(widget.timeoutController.text) ??
                      widget.audioSettings.lyricsAiTimeoutSeconds,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isTesting ? null : () => Navigator.of(context).pop(),
          child: Text(t.general.close),
        ),
        FilledButton.icon(
          onPressed: _isTesting ? null : _testAi,
          icon: _isTesting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.network_check_outlined),
          label: Text(t.settings.lyricsSourceSettings.aiTest),
        ),
      ],
    );
  }
}
