import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/theme/accent.dart';
import 'package:fmp/data/settings_store.dart';
import 'package:material_ui/material_ui.dart';

/// 設定「外觀 › 主題」：跟隨系統（預設）、淺色、深色。跟隨系統時系統切換
/// 深淺色，App 即時跟著換（`MaterialApp.themeMode`）。
final themeModeProvider = NotifierProvider<ThemeModeSetting, ThemeMode>(
  ThemeModeSetting.new,
);

class ThemeModeSetting extends SavedSetting<ThemeMode> {
  @override
  String get key => 'appearance.theme';

  @override
  ThemeMode get fallback => ThemeMode.system;

  @override
  ThemeMode? decode(String raw) =>
      ThemeMode.values.where((m) => m.name == raw).firstOrNull;

  @override
  String encode(ThemeMode value) => value.name;
}

/// 設定「外觀 › 強調色」：預設無（`docs/design/DESIGN.md`〈強調色〉）。
final accentProvider = NotifierProvider<AccentSetting, Accent>(
  AccentSetting.new,
);

class AccentSetting extends SavedSetting<Accent> {
  @override
  String get key => 'appearance.accent';

  @override
  Accent get fallback => Accent.none;

  @override
  Accent? decode(String raw) =>
      Accent.values.where((a) => a.name == raw).firstOrNull;

  @override
  String encode(Accent value) => value.name;
}
