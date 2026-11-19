import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/theme/accent.dart';
import 'package:fmp/data/settings_store.dart';
import 'package:material_ui/material_ui.dart';

/// 設定「外觀 › 主題」：跟隨系統（預設）、淺色、深色。跟隨系統時系統切換
/// 深淺色，App 即時跟著換（`MaterialApp.themeMode`）。
final themeModeProvider = NotifierProvider<ThemeModeSetting, ThemeMode>(
  ThemeModeSetting.new,
);

class ThemeModeSetting extends EnumSetting<ThemeMode> {
  @override
  String get key => 'appearance.theme';

  @override
  ThemeMode get fallback => ThemeMode.system;

  @override
  List<ThemeMode> get values => ThemeMode.values;

  @override
  String encode(ThemeMode value) => switch (value) {
    ThemeMode.system => 'system',
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
  };
}

/// 設定「外觀 › 強調色」：預設無（`docs/design/DESIGN.md`〈強調色〉）。
final accentProvider = NotifierProvider<AccentSetting, Accent>(
  AccentSetting.new,
);

class AccentSetting extends EnumSetting<Accent> {
  @override
  String get key => 'appearance.accent';

  @override
  Accent get fallback => Accent.none;

  @override
  List<Accent> get values => Accent.values;

  @override
  String encode(Accent value) => switch (value) {
    Accent.none => 'none',
    Accent.violet => 'violet',
    Accent.indigo => 'indigo',
    Accent.teal => 'teal',
  };
}
