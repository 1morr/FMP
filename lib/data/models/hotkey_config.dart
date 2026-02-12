import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../i18n/strings.g.dart';

/// 快捷键动作类型
enum HotkeyAction {
  playPause,
  next,
  previous,
  stop,
  volumeUp,
  volumeDown,
  mute,
  toggleWindow;

  /// 获取本地化标签
  String get label => switch (this) {
        HotkeyAction.playPause => t.settings.hotkeys.actions.playPause,
        HotkeyAction.next => t.settings.hotkeys.actions.next,
        HotkeyAction.previous => t.settings.hotkeys.actions.previous,
        HotkeyAction.stop => t.settings.hotkeys.actions.stop,
        HotkeyAction.volumeUp => t.settings.hotkeys.actions.volumeUp,
        HotkeyAction.volumeDown => t.settings.hotkeys.actions.volumeDown,
        HotkeyAction.mute => t.settings.hotkeys.actions.mute,
        HotkeyAction.toggleWindow => t.settings.hotkeys.actions.toggleWindow,
      };
}

/// 单个快捷键绑定配置
class HotkeyBinding {
  final HotkeyAction action;
  final LogicalKeyboardKey? key;
  final Set<HotKeyModifier> modifiers;

  const HotkeyBinding({
    required this.action,
    this.key,
    this.modifiers = const {},
  });

  /// 是否已配置
  bool get isConfigured => key != null;

  /// 是否与另一个绑定冲突
  bool conflictsWith(HotkeyBinding other) {
    if (!isConfigured || !other.isConfigured) return false;
    if (key != other.key) return false;
    if (modifiers.length != other.modifiers.length) return false;
    return modifiers.containsAll(other.modifiers);
  }

  /// 转换为显示字符串
  String toDisplayString() {
    if (!isConfigured) return t.general.notSet;

    final parts = <String>[];
    if (modifiers.contains(HotKeyModifier.control)) parts.add('Ctrl');
    if (modifiers.contains(HotKeyModifier.alt)) parts.add('Alt');
    if (modifiers.contains(HotKeyModifier.shift)) parts.add('Shift');
    if (modifiers.contains(HotKeyModifier.meta)) parts.add('Win');

    parts.add(_keyToString(key!));
    return parts.join(' + ');
  }

  /// 转换为 HotKey 对象
  HotKey? toHotKey() {
    if (!isConfigured) return null;
    return HotKey(
      key: key!,
      modifiers: modifiers.toList(),
      scope: HotKeyScope.system,
    );
  }

  /// 从 JSON 反序列化
  factory HotkeyBinding.fromJson(Map<String, dynamic> json) {
    final actionStr = json['action'] as String;
    final action = HotkeyAction.values.firstWhere(
      (a) => a.name == actionStr,
      orElse: () => HotkeyAction.playPause,
    );

    LogicalKeyboardKey? key;
    if (json['keyId'] != null) {
      key = LogicalKeyboardKey.findKeyByKeyId(json['keyId'] as int);
    }

    final modifiersList = (json['modifiers'] as List<dynamic>?) ?? [];
    final modifiers = modifiersList
        .map((m) => _stringToModifier(m as String))
        .whereType<HotKeyModifier>()
        .toSet();

    return HotkeyBinding(
      action: action,
      key: key,
      modifiers: modifiers,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        'action': action.name,
        'keyId': key?.keyId,
        'modifiers': modifiers.map((m) => _modifierToString(m)).toList(),
      };

  /// 创建副本并修改
  HotkeyBinding copyWith({
    HotkeyAction? action,
    LogicalKeyboardKey? key,
    Set<HotKeyModifier>? modifiers,
  }) {
    return HotkeyBinding(
      action: action ?? this.action,
      key: key ?? this.key,
      modifiers: modifiers ?? this.modifiers,
    );
  }

  /// 清除快捷键
  HotkeyBinding cleared() {
    return HotkeyBinding(
      action: action,
      key: null,
      modifiers: {},
    );
  }

  static String _keyToString(LogicalKeyboardKey key) {
    // 特殊键名映射
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

    // F1-F12
    if (key.keyId >= LogicalKeyboardKey.f1.keyId &&
        key.keyId <= LogicalKeyboardKey.f12.keyId) {
      final fNum = key.keyId - LogicalKeyboardKey.f1.keyId + 1;
      return 'F$fNum';
    }

    // 字母键
    final label = key.keyLabel;
    if (label.length == 1) {
      return label.toUpperCase();
    }

    return label;
  }

  static String _modifierToString(HotKeyModifier modifier) {
    switch (modifier) {
      case HotKeyModifier.control:
        return 'control';
      case HotKeyModifier.alt:
        return 'alt';
      case HotKeyModifier.shift:
        return 'shift';
      case HotKeyModifier.meta:
        return 'meta';
      default:
        return modifier.name;
    }
  }

  static HotKeyModifier? _stringToModifier(String str) {
    switch (str) {
      case 'control':
        return HotKeyModifier.control;
      case 'alt':
        return HotKeyModifier.alt;
      case 'shift':
        return HotKeyModifier.shift;
      case 'meta':
        return HotKeyModifier.meta;
      default:
        return null;
    }
  }
}

/// 快捷键配置集合
class HotkeyConfig {
  final Map<HotkeyAction, HotkeyBinding> bindings;

  HotkeyConfig({Map<HotkeyAction, HotkeyBinding>? bindings})
      : bindings = bindings ?? {};

  /// 默认配置
  factory HotkeyConfig.defaults() {
    return HotkeyConfig(bindings: {
      HotkeyAction.playPause: HotkeyBinding(
        action: HotkeyAction.playPause,
        key: LogicalKeyboardKey.space,
        modifiers: {HotKeyModifier.control, HotKeyModifier.alt},
      ),
      HotkeyAction.next: HotkeyBinding(
        action: HotkeyAction.next,
        key: LogicalKeyboardKey.arrowRight,
        modifiers: {HotKeyModifier.control, HotKeyModifier.alt},
      ),
      HotkeyAction.previous: HotkeyBinding(
        action: HotkeyAction.previous,
        key: LogicalKeyboardKey.arrowLeft,
        modifiers: {HotKeyModifier.control, HotKeyModifier.alt},
      ),
      HotkeyAction.stop: HotkeyBinding(
        action: HotkeyAction.stop,
        key: LogicalKeyboardKey.keyS,
        modifiers: {HotKeyModifier.control, HotKeyModifier.alt},
      ),
      HotkeyAction.volumeUp: HotkeyBinding(
        action: HotkeyAction.volumeUp,
        key: LogicalKeyboardKey.arrowUp,
        modifiers: {HotKeyModifier.control, HotKeyModifier.alt},
      ),
      HotkeyAction.volumeDown: HotkeyBinding(
        action: HotkeyAction.volumeDown,
        key: LogicalKeyboardKey.arrowDown,
        modifiers: {HotKeyModifier.control, HotKeyModifier.alt},
      ),
      HotkeyAction.mute: HotkeyBinding(
        action: HotkeyAction.mute,
        key: LogicalKeyboardKey.keyM,
        modifiers: {HotKeyModifier.control, HotKeyModifier.alt},
      ),
      HotkeyAction.toggleWindow: HotkeyBinding(
        action: HotkeyAction.toggleWindow,
        key: LogicalKeyboardKey.keyW,
        modifiers: {HotKeyModifier.control, HotKeyModifier.alt},
      ),
    });
  }

  /// 获取特定动作的绑定
  HotkeyBinding? getBinding(HotkeyAction action) => bindings[action];

  /// 更新绑定
  HotkeyConfig updateBinding(HotkeyBinding binding) {
    final newBindings = Map<HotkeyAction, HotkeyBinding>.from(bindings);
    newBindings[binding.action] = binding;
    return HotkeyConfig(bindings: newBindings);
  }

  /// 清除特定动作的绑定
  HotkeyConfig clearBinding(HotkeyAction action) {
    final newBindings = Map<HotkeyAction, HotkeyBinding>.from(bindings);
    if (newBindings.containsKey(action)) {
      newBindings[action] = newBindings[action]!.cleared();
    }
    return HotkeyConfig(bindings: newBindings);
  }

  /// 检查是否有冲突
  HotkeyAction? findConflict(HotkeyBinding newBinding) {
    for (final entry in bindings.entries) {
      if (entry.key != newBinding.action &&
          entry.value.conflictsWith(newBinding)) {
        return entry.key;
      }
    }
    return null;
  }

  /// 从 JSON 字符串反序列化
  factory HotkeyConfig.fromJsonString(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) {
      return HotkeyConfig.defaults();
    }
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return HotkeyConfig.fromJson(json);
    } catch (e) {
      return HotkeyConfig.defaults();
    }
  }

  /// 从 JSON 反序列化
  factory HotkeyConfig.fromJson(Map<String, dynamic> json) {
    final bindings = <HotkeyAction, HotkeyBinding>{};
    final bindingsList = json['bindings'] as List<dynamic>? ?? [];
    for (final item in bindingsList) {
      final binding = HotkeyBinding.fromJson(item as Map<String, dynamic>);
      bindings[binding.action] = binding;
    }

    // 确保所有动作都有绑定（使用默认值填充）
    final defaults = HotkeyConfig.defaults();
    for (final action in HotkeyAction.values) {
      bindings.putIfAbsent(action, () => defaults.getBinding(action)!);
    }

    return HotkeyConfig(bindings: bindings);
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
        'bindings': bindings.values.map((b) => b.toJson()).toList(),
      };

  /// 序列化为 JSON 字符串
  String toJsonString() => jsonEncode(toJson());
}
