import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/domain/appearance.dart';
import 'package:fmp/settings/appearance_settings.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 外觀設定的主題與語言（ADR 0011 §決定 7）。「跟隨系統」寫回 `null`（沒設定
/// 過），不是存一個值。
///
/// M1 放在身分頁供實機切換；12b 的設定頁沿用。
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
        // 舊資料或之後的設定頁可能存了明確的 system；兩者都顯示為跟隨系統，
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
