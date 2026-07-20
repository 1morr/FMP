part of '../settings_page.dart';

/// 开机自启动设置
class _LaunchAtStartupTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startupState = ref.watch(launchAtStartupProvider);

    return ListTile(
      leading: const Icon(Icons.power_settings_new_outlined),
      title: Text(t.settings.launchAtStartup.title),
      subtitle: Text(
        startupState.enabled
            ? (startupState.minimized
                ? t.settings.launchAtStartup.minimizedMode
                : t.settings.launchAtStartup.normalMode)
            : t.settings.launchAtStartup.subtitle,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (startupState.enabled)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: t.settings.launchAtStartup.launchMode,
              onPressed: () => _showLaunchModeDialog(context, ref),
            ),
          Switch(
            value: startupState.enabled,
            onChanged: (_) =>
                ref.read(launchAtStartupProvider.notifier).toggleEnabled(),
          ),
        ],
      ),
      onTap: startupState.enabled
          ? () => _showLaunchModeDialog(context, ref)
          : () => ref.read(launchAtStartupProvider.notifier).toggleEnabled(),
    );
  }

  void _showLaunchModeDialog(BuildContext context, WidgetRef ref) {
    final startupState = ref.read(launchAtStartupProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settings.launchAtStartup.launchMode),
        content: RadioGroup<bool>(
          groupValue: startupState.minimized,
          onChanged: (value) {
            if (value == null) return;
            ref.read(launchAtStartupProvider.notifier).setMinimized(value);
            Navigator.of(context).pop();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<bool>(
                title: Text(t.settings.launchAtStartup.normalMode),
                subtitle: Text(t.settings.launchAtStartup.normalModeDesc),
                value: false,
              ),
              RadioListTile<bool>(
                title: Text(t.settings.launchAtStartup.minimizedMode),
                subtitle: Text(t.settings.launchAtStartup.minimizedModeDesc),
                value: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 最小化到托盘设置
class _MinimizeToTrayTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(minimizeToTrayProvider);

    return SwitchListTile(
      secondary: const Icon(Icons.dock_outlined),
      title: Text(t.settings.tray.title),
      subtitle: Text(t.settings.tray.subtitle),
      value: enabled,
      onChanged: (_) => ref.read(minimizeToTrayProvider.notifier).toggle(),
    );
  }
}

/// 全局快捷键设置
class _GlobalHotkeysTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(globalHotkeysEnabledProvider);

    return ListTile(
      leading: const Icon(Icons.keyboard_outlined),
      title: Text(t.settings.hotkeys.title),
      subtitle: Text(enabled ? t.general.enabled : t.general.disabled),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: t.settings.hotkeys.configHotkey,
            onPressed: () => _showHotkeyConfigDialog(context, ref),
          ),
          Switch(
            value: enabled,
            onChanged: (_) =>
                ref.read(globalHotkeysEnabledProvider.notifier).toggle(),
          ),
        ],
      ),
      onTap: () => _showHotkeyConfigDialog(context, ref),
    );
  }

  void _showHotkeyConfigDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => const _HotkeyConfigDialog(),
    );
  }
}

/// 快捷键配置对话框
class _HotkeyConfigDialog extends ConsumerStatefulWidget {
  const _HotkeyConfigDialog();

  @override
  ConsumerState<_HotkeyConfigDialog> createState() =>
      _HotkeyConfigDialogState();
}

class _HotkeyConfigDialogState extends ConsumerState<_HotkeyConfigDialog> {
  HotkeyAction? _editingAction;
  Set<HotKeyModifier> _currentModifiers = {};
  LogicalKeyboardKey? _currentKey;
  bool _isRecording = false;

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(hotkeyConfigProvider);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.keyboard_outlined),
          const SizedBox(width: 8),
          Text(t.settings.hotkeys.configTitle),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.restore, size: 18),
            label: Text(t.settings.hotkeys.resetDefault),
            onPressed: () {
              ref.read(hotkeyConfigProvider.notifier).resetToDefaults();
            },
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.settings.hotkeys.hint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 16),
            ...HotkeyAction.values.map(
              (action) => _buildHotkeyRow(context, action, config),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.general.close),
        ),
      ],
    );
  }

  Widget _buildHotkeyRow(
      BuildContext context, HotkeyAction action, HotkeyConfig config) {
    final binding = config.getBinding(action);
    final isEditing = _editingAction == action;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              action.label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => _startRecording(action),
              borderRadius: AppRadius.borderRadiusMd,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isEditing
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadius.borderRadiusMd,
                  border: isEditing
                      ? Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        )
                      : null,
                ),
                child: isEditing
                    ? _buildRecordingDisplay(context)
                    : Text(
                        binding?.toDisplayString() ?? t.general.notSet,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: binding?.isConfigured == true
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.outline,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.clear, size: 20),
            tooltip: t.settings.hotkeys.clear,
            onPressed: binding?.isConfigured == true
                ? () {
                    ref
                        .read(hotkeyConfigProvider.notifier)
                        .clearBinding(action);
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingDisplay(BuildContext context) {
    if (!_isRecording) {
      return Text(
        t.settings.hotkeys.recording,
        style: const TextStyle(fontStyle: FontStyle.italic),
      );
    }

    final parts = <String>[];
    if (_currentModifiers.contains(HotKeyModifier.control)) parts.add('Ctrl');
    if (_currentModifiers.contains(HotKeyModifier.alt)) parts.add('Alt');
    if (_currentModifiers.contains(HotKeyModifier.shift)) parts.add('Shift');
    if (_currentModifiers.contains(HotKeyModifier.meta)) parts.add('Win');

    if (_currentKey != null) {
      parts.add(_keyToString(_currentKey!));
    }

    if (parts.isEmpty) {
      return Text(
        t.settings.hotkeys.recording,
        style: const TextStyle(fontStyle: FontStyle.italic),
      );
    }

    return Text(
      parts.join(' + '),
      style: const TextStyle(fontFamily: 'monospace'),
    );
  }

  void _startRecording(HotkeyAction action) {
    setState(() {
      _editingAction = action;
      _currentModifiers = {};
      _currentKey = null;
      _isRecording = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _HotkeyRecordingDialog(
        action: action,
        onRecorded: (key, modifiers) {
          Navigator.pop(dialogContext);
          _saveHotkey(action, key, modifiers);
        },
        onCancel: () {
          Navigator.pop(dialogContext);
          setState(() {
            _editingAction = null;
            _isRecording = false;
          });
        },
      ),
    );
  }

  void _saveHotkey(HotkeyAction action, LogicalKeyboardKey key,
      Set<HotKeyModifier> modifiers) {
    final newBinding = HotkeyBinding(
      action: action,
      key: key,
      modifiers: modifiers,
    );

    ref.read(hotkeyConfigProvider.notifier).updateBinding(newBinding);

    setState(() {
      _editingAction = null;
      _isRecording = false;
    });
  }

  String _keyToString(LogicalKeyboardKey key) {
    final specialKeys = {
      LogicalKeyboardKey.space: 'Space',
      LogicalKeyboardKey.arrowLeft: '←',
      LogicalKeyboardKey.arrowRight: '→',
      LogicalKeyboardKey.arrowUp: '↑',
      LogicalKeyboardKey.arrowDown: '↓',
      LogicalKeyboardKey.enter: 'Enter',
      LogicalKeyboardKey.escape: 'Esc',
      LogicalKeyboardKey.backspace: 'Backspace',
      LogicalKeyboardKey.delete: 'Delete',
    };

    if (specialKeys.containsKey(key)) {
      return specialKeys[key]!;
    }

    final label = key.keyLabel;
    if (label.length == 1) {
      return label.toUpperCase();
    }

    return label;
  }
}

/// 快捷键录制对话框
class _HotkeyRecordingDialog extends StatefulWidget {
  final HotkeyAction action;
  final void Function(LogicalKeyboardKey key, Set<HotKeyModifier> modifiers)
      onRecorded;
  final VoidCallback onCancel;

  const _HotkeyRecordingDialog({
    required this.action,
    required this.onRecorded,
    required this.onCancel,
  });

  @override
  State<_HotkeyRecordingDialog> createState() => _HotkeyRecordingDialogState();
}

class _HotkeyRecordingDialogState extends State<_HotkeyRecordingDialog> {
  final FocusNode _focusNode = FocusNode();
  final Set<HotKeyModifier> _modifiers = {};
  LogicalKeyboardKey? _key;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.settings.hotkeys.setHotkey(action: widget.action.label)),
      content: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Container(
          width: 300,
          height: 100,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: AppRadius.borderRadiusLg,
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
          child: Center(
            child: Text(
              _buildDisplayText(),
              style: const TextStyle(
                fontSize: 18,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: Text(t.general.cancel),
        ),
      ],
    );
  }

  String _buildDisplayText() {
    final parts = <String>[];
    if (_modifiers.contains(HotKeyModifier.control)) parts.add('Ctrl');
    if (_modifiers.contains(HotKeyModifier.alt)) parts.add('Alt');
    if (_modifiers.contains(HotKeyModifier.shift)) parts.add('Shift');
    if (_modifiers.contains(HotKeyModifier.meta)) parts.add('Win');

    if (_key != null) {
      parts.add(_keyToString(_key!));
    }

    if (parts.isEmpty) {
      return t.settings.hotkeys.pressCombo;
    }

    return parts.join(' + ');
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;

      if (key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight) {
        setState(() => _modifiers.add(HotKeyModifier.control));
        return;
      }
      if (key == LogicalKeyboardKey.altLeft ||
          key == LogicalKeyboardKey.altRight) {
        setState(() => _modifiers.add(HotKeyModifier.alt));
        return;
      }
      if (key == LogicalKeyboardKey.shiftLeft ||
          key == LogicalKeyboardKey.shiftRight) {
        setState(() => _modifiers.add(HotKeyModifier.shift));
        return;
      }
      if (key == LogicalKeyboardKey.metaLeft ||
          key == LogicalKeyboardKey.metaRight) {
        setState(() => _modifiers.add(HotKeyModifier.meta));
        return;
      }

      if (key == LogicalKeyboardKey.escape) {
        widget.onCancel();
        return;
      }

      if (_modifiers.isNotEmpty) {
        setState(() => _key = key);
        widget.onRecorded(key, _modifiers);
      }
    } else if (event is KeyUpEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight) {
        setState(() => _modifiers.remove(HotKeyModifier.control));
      }
      if (key == LogicalKeyboardKey.altLeft ||
          key == LogicalKeyboardKey.altRight) {
        setState(() => _modifiers.remove(HotKeyModifier.alt));
      }
      if (key == LogicalKeyboardKey.shiftLeft ||
          key == LogicalKeyboardKey.shiftRight) {
        setState(() => _modifiers.remove(HotKeyModifier.shift));
      }
      if (key == LogicalKeyboardKey.metaLeft ||
          key == LogicalKeyboardKey.metaRight) {
        setState(() => _modifiers.remove(HotKeyModifier.meta));
      }
    }
  }

  String _keyToString(LogicalKeyboardKey key) {
    final specialKeys = {
      LogicalKeyboardKey.space: 'Space',
      LogicalKeyboardKey.arrowLeft: '←',
      LogicalKeyboardKey.arrowRight: '→',
      LogicalKeyboardKey.arrowUp: '↑',
      LogicalKeyboardKey.arrowDown: '↓',
      LogicalKeyboardKey.enter: 'Enter',
      LogicalKeyboardKey.escape: 'Esc',
      LogicalKeyboardKey.backspace: 'Backspace',
      LogicalKeyboardKey.delete: 'Delete',
      LogicalKeyboardKey.home: 'Home',
      LogicalKeyboardKey.end: 'End',
      LogicalKeyboardKey.pageUp: 'PageUp',
      LogicalKeyboardKey.pageDown: 'PageDown',
      LogicalKeyboardKey.tab: 'Tab',
    };

    if (specialKeys.containsKey(key)) {
      return specialKeys[key]!;
    }

    if (key.keyId >= LogicalKeyboardKey.f1.keyId &&
        key.keyId <= LogicalKeyboardKey.f12.keyId) {
      final fNum = key.keyId - LogicalKeyboardKey.f1.keyId + 1;
      return 'F$fNum';
    }

    final label = key.keyLabel;
    if (label.length == 1) {
      return label.toUpperCase();
    }

    return label;
  }
}
