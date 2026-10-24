import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/appearance.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/settings/appearance_settings.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/settings/custom_color_dialog.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_theme.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/theme/theme_presets.dart';

/// 外觀設定的主題、主題色、字型與語言（ADR 0011 §決定 7、ADR 0035 §決定 5）。「跟隨
/// 系統」、預設主題色與系統預設字型都寫回 `null`（沒設定過），不是存一個值。設定頁
/// （`settings_page.dart`）的外觀組。
class AppearanceControls extends ConsumerWidget {
  const AppearanceControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stored = ref.watch(appearanceProvider).value?.stored;
    if (stored == null) return const SizedBox.shrink();
    final t = ref.watch(translationsProvider).appearance;
    final notifier = ref.read(appearanceProvider.notifier);
    final spacing = AppTokens.of(context).spacing;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.theme, style: textTheme.titleSmall),
        SizedBox(height: spacing.x2),
        // 舊資料可能存了明確的 system；兩者都顯示為跟隨系統，
        // 選它一律清回 null。
        SegmentedButton<ThemeModeSetting>(
          segments: [
            ButtonSegment(
              value: ThemeModeSetting.system,
              label: Text(t.themeSystem),
            ),
            ButtonSegment(
              value: ThemeModeSetting.light,
              label: Text(t.themeLight),
            ),
            ButtonSegment(
              value: ThemeModeSetting.dark,
              label: Text(t.themeDark),
            ),
          ],
          selected: {stored.themeMode ?? ThemeModeSetting.system},
          onSelectionChanged: (selection) => unawaited(
            notifier.setThemeMode(switch (selection.single) {
              ThemeModeSetting.system => null,
              final mode => mode,
            }),
          ),
        ),
        SizedBox(height: spacing.x4),
        Text(t.themeColor, style: textTheme.titleSmall),
        SizedBox(height: spacing.x2),
        _ThemeColorPicker(seed: stored.seedColor ?? appSeedColor),
        SizedBox(height: spacing.x4),
        Text(t.font, style: textTheme.titleSmall),
        _FontChoices(selected: ref.watch(appearanceProvider).value?.fontFamily),
        SizedBox(height: spacing.x4),
        Text(t.language, style: textTheme.titleSmall),
        // 值 null 是「跟隨系統」。
        RadioGroup<LocaleSetting?>(
          groupValue: stored.locale,
          onChanged: (locale) => unawaited(notifier.setLocale(locale)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<LocaleSetting?>(
                value: null,
                title: Text(t.languageSystem),
              ),
              for (final locale in LocaleSetting.values)
                RadioListTile<LocaleSetting?>(
                  value: locale,
                  // 名稱帶自己的 locale，繁簡中文的字形不隨介面語言變。寫在
                  // 樣式上：主題的樣式帶介面的 locale，會蓋過 Text.locale。
                  title: Text(
                    localeEndonym(locale),
                    style: TextStyle(locale: flutterLocaleOf(locale)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 9 個色塊（預設加 8 個 preset）加「自訂」。選預設色寫回 `null`。
class _ThemeColorPicker extends ConsumerWidget {
  const _ThemeColorPicker({required this.seed});

  final Color seed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).appearance;
    final notifier = ref.read(appearanceProvider.notifier);
    final current = themePresetOf(seed);
    return Wrap(
      children: [
        for (final preset in themePresets)
          _Swatch(
            color: preset.color,
            label: _presetName(t, preset.id),
            selected: preset == current,
            onTap: () => unawaited(
              notifier.setSeedColor(
                preset.color == appSeedColor ? null : preset.color,
              ),
            ),
          ),
        _Swatch(
          // 目前不是 preset 時，自訂色塊顯示那個顏色。
          color: current == null ? seed : null,
          label: t.themeColorCustom,
          selected: current == null,
          onTap: () async {
            final picked = await showCustomColorDialog(context, seed);
            if (picked != null) await notifier.setSeedColor(picked);
          },
        ),
      ],
    );
  }
}

String _presetName(Translations$appearance$zh_TW t, String id) => switch (id) {
  'defaultPurple' => t.presets.defaultPurple,
  'indigo' => t.presets.indigo,
  'blue' => t.presets.blue,
  'teal' => t.presets.teal,
  'green' => t.presets.green,
  'yellow' => t.presets.yellow,
  'orange' => t.presets.orange,
  'red' => t.presets.red,
  'pink' => t.presets.pink,
  _ => id,
};

/// 一個圓形色塊加名稱；[color] 為 `null` 是「自訂」的調色盤圖示。
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color? color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          AppTokens.of(context).radius.medium,
        ),
        child: SizedBox(
          width: AppLayout.themeSwatchCell,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: spacing.x2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: AppLayout.themeSwatch,
                  height: AppLayout.themeSwatch,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color ?? theme.colorScheme.surfaceContainerHighest,
                    border: selected
                        ? Border.all(color: theme.colorScheme.outline)
                        : null,
                  ),
                  child: Icon(
                    selected
                        ? Icons.check
                        : (color == null ? Icons.palette_outlined : null),
                    color: color == null
                        ? theme.colorScheme.onSurfaceVariant
                        : foregroundColorFor(color!),
                    // 名稱已經在旁邊的文字與整個色塊的語意裡。
                    semanticLabel: null,
                  ),
                ),
                SizedBox(height: spacing.x1),
                Text(
                  label,
                  style: theme.textTheme.labelSmall,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 平台給的固定字型清單加「系統預設」。值 `null` 是系統預設。
class _FontChoices extends ConsumerWidget {
  const _FontChoices({required this.selected});

  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).appearance;
    final choices = ref.watch(platformCapabilitiesProvider).fontChoices;
    return RadioGroup<String?>(
      groupValue: selected,
      onChanged: (family) => unawaited(
        ref.read(appearanceProvider.notifier).setFontFamily(family),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<String?>(value: null, title: Text(t.fontSystem)),
          for (final family in choices)
            RadioListTile<String?>(
              value: family,
              // 用自己的字型顯示，選之前就看得到樣子。
              title: Text(
                _fontName(t, family),
                style: TextStyle(fontFamily: family),
              ),
            ),
        ],
      ),
    );
  }
}

/// 有翻譯的字型顯示翻譯，其餘（日文字型）顯示 family 名稱。
String _fontName(Translations$appearance$zh_TW t, String family) =>
    switch (family) {
      'Microsoft JhengHei UI' => t.fonts.jhengHei,
      'Microsoft YaHei UI' => t.fonts.yaHei,
      'PMingLiU' => t.fonts.pmingliu,
      'DFKai-SB' => t.fonts.dfkai,
      'sans-serif' => t.fonts.sansSerif,
      'serif' => t.fonts.serif,
      'monospace' => t.fonts.monospace,
      _ => family,
    };
