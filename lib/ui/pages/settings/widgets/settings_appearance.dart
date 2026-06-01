part of '../settings_page.dart';

/// 主题模式选择
class _ThemeModeListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final themeName = switch (themeMode) {
      ThemeMode.system => t.settings.theme.followSystem,
      ThemeMode.light => t.settings.theme.light,
      ThemeMode.dark => t.settings.theme.dark,
    };

    return ListTile(
      leading: Icon(
        switch (themeMode) {
          ThemeMode.system => Icons.brightness_auto,
          ThemeMode.light => Icons.light_mode,
          ThemeMode.dark => Icons.dark_mode,
        },
      ),
      title: Text(t.settings.theme.title),
      subtitle: Text(themeName),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showThemeModeDialog(context, ref, themeMode),
    );
  }

  void _showThemeModeDialog(
      BuildContext context, WidgetRef ref, ThemeMode currentMode) {
    final systemBrightness = MediaQuery.platformBrightnessOf(context);
    final systemThemeName = systemBrightness == Brightness.dark
        ? t.settings.theme.dark
        : t.settings.theme.light;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settings.theme.selectTitle),
        content: RadioGroup<ThemeMode>(
          groupValue: currentMode,
          onChanged: (value) {
            if (value != null) {
              ref.read(themeProvider.notifier).setThemeMode(value);
            }
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<ThemeMode>(
                title: Text.rich(
                  TextSpan(
                    text: t.settings.theme.followSystem,
                    children: [
                      TextSpan(
                        text: ' ($systemThemeName)',
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                secondary: const Icon(Icons.brightness_auto),
                value: ThemeMode.system,
              ),
              RadioListTile<ThemeMode>(
                title: Text(t.settings.theme.light),
                secondary: const Icon(Icons.light_mode),
                value: ThemeMode.light,
              ),
              RadioListTile<ThemeMode>(
                title: Text(t.settings.theme.dark),
                secondary: const Icon(Icons.dark_mode),
                value: ThemeMode.dark,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel),
          ),
        ],
      ),
    );
  }
}

/// 主题色选择
class _ThemeColorListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primaryColor = ref.watch(primaryColorProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final selectedPreset = themePresetColorFor(primaryColor);

    return ListTile(
      leading: const Icon(Icons.color_lens_outlined),
      title: Text(t.settings.themeColor.title),
      subtitle: Text(
        selectedPreset != null
            ? _themePresetColorName(selectedPreset)
            : t.general.custom,
      ),
      trailing: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: primaryColor ?? defaultThemePrimaryColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      onTap: () => _showColorPickerDialog(context, ref, primaryColor),
    );
  }

  String _themePresetColorName(ThemePresetColor preset) {
    return switch (preset.id) {
      'defaultPurple' => t.settings.themeColor.colors.defaultPurple,
      'indigo' => t.settings.themeColor.colors.indigo,
      'blue' => t.settings.themeColor.colors.blue,
      'teal' => t.settings.themeColor.colors.teal,
      'green' => t.settings.themeColor.colors.green,
      'yellow' => t.settings.themeColor.colors.yellow,
      'red' => t.settings.themeColor.colors.red,
      'pink' => t.settings.themeColor.colors.pink,
      'orange' => t.settings.themeColor.colors.orange,
      _ => preset.id,
    };
  }

  void _showColorPickerDialog(
    BuildContext context,
    WidgetRef ref,
    Color? currentColor,
  ) {
    showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, dialogRef, _) {
          final livePrimaryColor = dialogRef.watch(primaryColorProvider);
          final selectedPreset = themePresetColorFor(livePrimaryColor);

          return AlertDialog(
            title: Text(t.settings.themeColor.selectTitle),
            content: SizedBox(
              width: 240,
              child: Wrap(
                spacing: 10,
                runSpacing: 12,
                children: [
                  ...themePresetColors.map((preset) {
                    final isSelected = selectedPreset?.id == preset.id;
                    return _ThemeColorSwatchButton(
                      tooltip: _themePresetColorName(preset),
                      color: preset.color,
                      isSelected: isSelected,
                      onTap: () {
                        ref.read(themeProvider.notifier).setPrimaryColor(
                              preset.storesAsDefault ? null : preset.color,
                            );
                        Navigator.pop(context);
                      },
                    );
                  }),
                  _ThemeColorSwatchButton(
                    tooltip: t.settings.themeColor.customColor,
                    gradient: const SweepGradient(
                      colors: [
                        Colors.red,
                        Colors.yellow,
                        Colors.green,
                        Colors.cyan,
                        Colors.blue,
                        Colors.purple,
                        Colors.red,
                      ],
                    ),
                    isSelected: selectedPreset == null,
                    onTap: () => _showCustomColorPalette(
                      context,
                      ref,
                      livePrimaryColor ?? currentColor,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t.general.cancel),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCustomColorPalette(
    BuildContext context,
    WidgetRef ref,
    Color? currentColor,
  ) {
    ColorPaletteDialog.show(
      context: context,
      label: t.settings.themeColor.customColor,
      closeLabel: t.general.close,
      color: currentColor ?? defaultThemePrimaryColor,
      onChanged: (color) {
        ref.read(themeProvider.notifier).setPrimaryColor(
              color.withValues(alpha: 1),
            );
      },
    );
  }
}

class _ThemeColorSwatchButton extends StatelessWidget {
  final String tooltip;
  final Color? color;
  final Gradient? gradient;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeColorSwatchButton({
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
    this.color,
    this.gradient,
  }) : assert(color != null || gradient != null);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final swatchColor = color ?? colorScheme.primary;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.borderRadiusPill,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            gradient: gradient,
            shape: BoxShape.circle,
            border: isSelected
                ? Border.all(
                    color: colorScheme.onSurface,
                    width: 2,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: swatchColor.withValues(alpha: 0.4),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: isSelected
              ? Icon(
                  Icons.check,
                  color: color == null ||
                          ThemeData.estimateBrightnessForColor(color!) ==
                              Brightness.dark
                      ? Colors.white
                      : Colors.black,
                  size: 20,
                )
              : null,
        ),
      ),
    );
  }
}

/// 字体选择
class _FontFamilyListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontFamily = ref.watch(fontFamilyProvider);
    final fonts = AppTheme.availableFonts;
    final currentDisplay = fonts
            .where((f) => f.fontFamily == fontFamily)
            .map((f) => f.displayName)
            .firstOrNull ??
        fontFamily ??
        t.general.systemDefault;

    return ListTile(
      leading: const Icon(Icons.font_download_outlined),
      title: Text(t.settings.font.title),
      subtitle: Text(currentDisplay),
      onTap: () => _showFontDialog(context, ref, fontFamily),
    );
  }

  void _showFontDialog(
      BuildContext context, WidgetRef ref, String? currentFont) {
    final fonts = AppTheme.availableFonts;
    final systemFontName = Platform.isWindows ? 'Segoe UI' : 'Roboto';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settings.font.selectTitle),
        content: RadioGroup<String?>(
          groupValue: currentFont,
          onChanged: (value) {
            ref.read(themeProvider.notifier).setFontFamily(value);
            Navigator.pop(context);
          },
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: fonts.map((font) {
                return RadioListTile<String?>(
                  title: font.fontFamily == null
                      ? Text.rich(
                          TextSpan(
                            text: font.displayName,
                            children: [
                              TextSpan(
                                text: ' ($systemFontName)',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.5),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Text(
                          font.displayName,
                          style: TextStyle(fontFamily: font.fontFamily),
                        ),
                  subtitle: font.fontFamily != null
                      ? Text(font.fontFamily!,
                          style: Theme.of(context).textTheme.bodySmall)
                      : null,
                  value: font.fontFamily,
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel),
          ),
        ],
      ),
    );
  }
}

/// 语言选择
class _LanguageListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = ref.watch(localeDisplayNameProvider);

    return ListTile(
      leading: const Icon(Icons.language_outlined),
      title: Text(t.settings.language.title),
      subtitle: Text(displayName),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showLanguageDialog(context, ref),
    );
  }

  void _showLanguageDialog(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.read(localeProvider);

    // Detect system language
    final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
    String systemLanguageName;
    if (systemLocale.languageCode == 'zh') {
      final isTraditional = systemLocale.scriptCode == 'Hant' ||
          systemLocale.countryCode == 'TW' ||
          systemLocale.countryCode == 'HK' ||
          systemLocale.countryCode == 'MO';
      systemLanguageName = isTraditional
          ? t.settings.traditionalChinese
          : t.settings.simplifiedChinese;
    } else if (systemLocale.languageCode == 'en') {
      systemLanguageName = t.settings.english;
    } else {
      systemLanguageName = systemLocale.languageCode;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settings.language.selectTitle),
        content: RadioGroup<AppLocale?>(
          groupValue: currentLocale,
          onChanged: (value) {
            ref.read(localeProvider.notifier).setLocale(value);
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<AppLocale?>(
                title: Text.rich(
                  TextSpan(
                    text: t.settings.language.followSystem,
                    children: [
                      TextSpan(
                        text: ' ($systemLanguageName)',
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                value: null,
              ),
              RadioListTile<AppLocale?>(
                title: Text(t.settings.simplifiedChinese),
                value: AppLocale.zhCn,
              ),
              RadioListTile<AppLocale?>(
                title: Text(t.settings.traditionalChinese),
                value: AppLocale.zhTw,
              ),
              RadioListTile<AppLocale?>(
                title: Text(t.settings.english),
                value: AppLocale.en,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel),
          ),
        ],
      ),
    );
  }
}
