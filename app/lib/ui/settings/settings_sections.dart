import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/glass/glass_effect.dart';
import 'package:fmp/app/i18n/language.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/appearance.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/playback/queue_controller.dart';
import 'package:fmp/ui/common/glass_menu.dart';
import 'package:fmp/ui/settings/settings_controls.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:material_ui/material_ui.dart';

/// 設定的分類。M1 只有外觀與播放（還沒有的功能不出現入口，spec〈共同規則〉）；
/// 照 `settings.html` 分類欄的順序。
enum SettingsCategory {
  appearance(FmpIcons.appearance),
  playback(FmpIcons.wave);

  const SettingsCategory(this.icon);

  final FmpIcons icon;

  String label(Translations t) => switch (this) {
    appearance => t.settings.appearance,
    playback => t.settings.playback,
  };
}

// ---------------------------------------------------------------- 名字

String themeLabel(Translations t, ThemeMode mode) => switch (mode) {
  ThemeMode.system => t.settings.themeSystem,
  ThemeMode.light => t.settings.themeLight,
  ThemeMode.dark => t.settings.themeDark,
};

String accentLabel(Translations t, Accent accent) => switch (accent) {
  Accent.none => t.settings.accentNone,
  Accent.violet => t.settings.accentViolet,
  Accent.indigo => t.settings.accentIndigo,
  Accent.teal => t.settings.accentTeal,
};

/// 每個語言用它自己的寫法（`settings.html`：繁體中文、简体中文、English），
/// 不跟介面語言翻譯。
String languageName(AppLocale locale) => switch (locale) {
  AppLocale.zhTw => '繁體中文',
  AppLocale.zhCn => '简体中文',
  AppLocale.en => 'English',
};

/// 設定「玻璃效果」的三個選項，由高到低（完整、輕量、關閉）。
const glassChoices = [GlassTier.refract, GlassTier.standard, GlassTier.minimal];

String glassLabel(Translations t, GlassTier tier) => switch (tier) {
  GlassTier.refract => t.settings.glassFull,
  GlassTier.standard => t.settings.glassLite,
  GlassTier.minimal => t.settings.glassOff,
};

/// 選項下方說明實際效果的一行（`docs/design/DESIGN.md`〈三級與平台〉）。
String glassHint(Translations t, GlassTier tier) => switch (tier) {
  GlassTier.refract => t.settings.glassFullHint,
  GlassTier.standard => t.settings.glassLiteHint,
  GlassTier.minimal => t.settings.glassOffHint,
};

String rewindLabel(Translations t, Duration rewind) => rewind == Duration.zero
    ? t.settings.rewindNone
    : t.settings.rewindSeconds(seconds: rewind.inSeconds);

// ---------------------------------------------------------------- 選單

/// 在 [anchor] 下方、右緣對齊它打開選單（手機的主題選單，`settings.html`）。
Future<T?> _menuBelow<T>(
  BuildContext anchor,
  List<GlassMenuEntry<T>> entries, {
  required bool touch,
}) {
  final box = anchor.findRenderObject()! as RenderBox;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  return showGlassMenu<T>(
    context: anchor,
    at: Offset(
      rect.right - glassMenuWidth(touch: touch),
      rect.bottom + (touch ? 2 : 4),
    ),
    entries: entries,
  );
}

Future<void> _pickTheme(BuildContext anchor, WidgetRef ref, bool touch) async {
  final t = anchor.t;
  final current = ref.read(themeModeProvider);
  final mode = await _menuBelow<ThemeMode>(anchor, [
    for (final mode in ThemeMode.values)
      GlassMenuItem(
        value: mode,
        label: themeLabel(t, mode),
        checked: mode == current,
      ),
  ], touch: touch);
  if (mode != null) await ref.read(themeModeProvider.notifier).set(mode);
}

/// 語言選單的值：`system` 或語言的 tag（選單回 null 是沒選）。
Future<void> _pickLanguage(
  BuildContext anchor,
  WidgetRef ref,
  bool touch,
) async {
  final t = anchor.t;
  final current = ref.read(languageProvider);
  const system = 'system';
  final tag = await _menuBelow<String>(anchor, [
    GlassMenuItem(
      value: system,
      label: t.settings.languageSystem,
      checked: current == null,
    ),
    for (final locale in AppLocale.values)
      GlassMenuItem(
        value: locale.languageTag,
        label: languageName(locale),
        checked: locale == current,
      ),
  ], touch: touch);
  if (tag == null) return;
  await ref
      .read(languageProvider.notifier)
      .set(AppLocale.values.where((l) => l.languageTag == tag).firstOrNull);
}

Future<void> _pickGlass(BuildContext anchor, WidgetRef ref, bool touch) async {
  final t = anchor.t;
  final current = ref.read(glassEffectProvider);
  final tier = await _menuBelow<GlassTier>(anchor, [
    for (final tier in glassChoices)
      GlassMenuItem(
        value: tier,
        label: glassLabel(t, tier),
        detail: glassHint(t, tier),
        checked: tier == current,
      ),
  ], touch: touch);
  if (tier != null) await ref.read(glassEffectProvider.notifier).set(tier);
}

Future<void> _pickRewind(BuildContext anchor, WidgetRef ref, bool touch) async {
  final t = anchor.t;
  final current = ref.read(temporaryPlayRewindProvider);
  final rewind = await _menuBelow<Duration>(anchor, [
    for (final option in TemporaryPlayRewind.options)
      GlassMenuItem(
        value: option,
        label: rewindLabel(t, option),
        checked: option == current,
      ),
  ], touch: touch);
  if (rewind != null) {
    await ref.read(temporaryPlayRewindProvider.notifier).set(rewind);
  }
}

/// 一列，點了在這列下面打開 [pick] 的選單。
Widget _menuCell({
  required SettingsStyle style,
  required FmpIcons icon,
  required String title,
  required String value,
  required Future<void> Function(BuildContext anchor) pick,
}) => Builder(
  builder: (anchor) => SettingsCell(
    style: style,
    icon: icon,
    title: title,
    trailing: SettingsValue(value, style: style),
    onTap: () => pick(anchor),
  ),
);

// ---------------------------------------------------------------- 手機

/// 手機設定首頁的「外觀」：主題、強調色、語言、玻璃效果；只有一個值、選項
/// 少的就地彈出選單（`settings.html` 的規則）。
class PhoneAppearanceGroup extends ConsumerWidget {
  const PhoneAppearanceGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final style = SettingsStyle.of(touch: true);
    final accent = ref.watch(accentProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsHead(t.settings.appearance, style: style),
        SettingsGroup(
          style: style,
          separatorInset: SettingsGroup.iconInset(style),
          children: [
            _menuCell(
              style: style,
              icon: FmpIcons.appearance,
              title: t.settings.theme,
              value: themeLabel(t, ref.watch(themeModeProvider)),
              pick: (anchor) => _pickTheme(anchor, ref, true),
            ),
            SettingsCell(
              style: style,
              icon: FmpIcons.select,
              title: t.settings.accent,
              subtitle: accentLabel(t, accent),
              trailing: const AccentSwatches(touch: true, labels: false),
            ),
            _menuCell(
              style: style,
              icon: FmpIcons.language,
              title: t.settings.language,
              value: switch (ref.watch(languageProvider)) {
                null => t.settings.languageSystem,
                final locale => languageName(locale),
              },
              pick: (anchor) => _pickLanguage(anchor, ref, true),
            ),
            _menuCell(
              style: style,
              icon: FmpIcons.layers,
              title: t.settings.glass,
              value: glassLabel(t, ref.watch(glassEffectProvider)),
              pick: (anchor) => _pickGlass(anchor, ref, true),
            ),
          ],
        ),
        SettingsFoot(t.settings.accentFooterTouch, style: style),
      ],
    );
  }
}

/// 手機設定首頁的「播放」：臨時播放結束後倒退。
class PhonePlaybackGroup extends ConsumerWidget {
  const PhonePlaybackGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final style = SettingsStyle.of(touch: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsHead(t.settings.playback, style: style),
        SettingsGroup(
          style: style,
          separatorInset: SettingsGroup.iconInset(style),
          children: [
            _menuCell(
              style: style,
              icon: FmpIcons.history,
              title: t.settings.rewind,
              value: rewindLabel(t, ref.watch(temporaryPlayRewindProvider)),
              pick: (anchor) => _pickRewind(anchor, ref, true),
            ),
          ],
        ),
        SettingsFoot(t.settings.rewindFooter, style: style),
      ],
    );
  }
}

// ---------------------------------------------------------------- 窗格

/// 桌面與中寬度窗格的開頭（`.sx-h` 與 `.sx-lead`）：分類名與一句說明。
class _PaneHeader extends StatelessWidget {
  const _PaneHeader({required this.title, required this.lead});

  final String title;
  final String lead;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(header: true, child: Text(title, style: context.fmpText.large)),
      const SizedBox(height: 8),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Text(
          lead,
          style: TextStyle(
            fontSize: 13,
            height: 19 / 13,
            letterSpacing: 0,
            color: context.fmpColors.label2,
          ),
        ),
      ),
    ],
  );
}

/// 桌面與中寬度的「外觀」窗格：主題用三張預覽圖、強調色一排色點、語言的
/// 彈出選單、玻璃效果三列單選（`settings.html` 的桌面外觀；玻璃效果稿上沒畫，
/// 照擁有者 2026-11-20 同意的做法）。[touch] 是平板：元件換觸控密度。
class AppearancePane extends ConsumerWidget {
  const AppearancePane({super.key, required this.touch});

  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final style = SettingsStyle.of(touch: touch);
    final glass = ref.watch(glassEffectProvider);
    final language = ref.watch(languageProvider);
    final languageValue = switch (language) {
      null => t.settings.languageSystemWith(
        language: languageName(appLocaleFor(systemLocale())),
      ),
      final locale => languageName(locale),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PaneHeader(
          title: t.settings.appearance,
          lead: t.settings.appearanceLead,
        ),
        SettingsHead(t.settings.theme, style: style),
        SettingsGroup(
          style: style,
          children: [ThemeTiles(touch: touch)],
        ),
        SettingsFoot(t.settings.themeFooter, style: style),
        SettingsHead(t.settings.accent, style: style),
        SettingsGroup(
          style: style,
          children: [AccentSwatches(touch: touch, labels: true)],
        ),
        SettingsFoot(t.settings.accentFooter, style: style),
        SettingsHead(t.settings.language, style: style),
        SettingsGroup(
          style: style,
          children: [
            SettingsCell(
              style: style,
              title: t.settings.interfaceLanguage,
              subtitle: t.settings.languageHint,
              trailing: Builder(
                builder: (anchor) => SettingsPopupButton(
                  label: languageValue,
                  semanticsLabel:
                      '${t.settings.interfaceLanguage}, $languageValue',
                  touch: touch,
                  onTap: () => _pickLanguage(anchor, ref, touch),
                ),
              ),
            ),
          ],
        ),
        SettingsFoot(t.settings.languageFooter, style: style),
        SettingsHead(t.settings.glass, style: style),
        SettingsGroup(
          style: style,
          children: [
            for (final tier in glassChoices)
              SettingsCell(
                style: style,
                title: glassLabel(t, tier),
                subtitle: glassHint(t, tier),
                selected: tier == glass,
                onTap: () => ref.read(glassEffectProvider.notifier).set(tier),
              ),
          ],
        ),
      ],
    );
  }
}

/// 桌面與中寬度的「播放」窗格：進度的「臨時播放結束後倒退」用步進器
/// （`settings.html` 的桌面播放；音質等 M2 才有，說明只留佇列與進度那句）。
class PlaybackPane extends ConsumerWidget {
  const PlaybackPane({super.key, required this.touch});

  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final style = SettingsStyle.of(touch: touch);
    final rewind = ref.watch(temporaryPlayRewindProvider);
    const options = TemporaryPlayRewind.options;
    final index = options.indexOf(rewind);
    void step(int by) =>
        ref.read(temporaryPlayRewindProvider.notifier).set(options[index + by]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PaneHeader(title: t.settings.playback, lead: t.settings.playbackLead),
        SettingsHead(t.settings.progress, style: style),
        SettingsGroup(
          style: style,
          children: [
            SettingsCell(
              style: style,
              title: t.settings.rewind,
              subtitle: t.settings.rewindHint,
              trailing: SettingsStepper(
                value: rewindLabel(t, rewind),
                decreaseLabel: t.settings.decrease,
                increaseLabel: t.settings.increase,
                touch: touch,
                onDecrease: index > 0 ? () => step(-1) : null,
                onIncrease: index < options.length - 1 ? () => step(1) : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 共用

/// 強調色的四個色點（`.st-accs`）：無是字色，選中的有一圈環。[labels] 時每個
/// 色點下面寫名字（桌面與平板）。
class AccentSwatches extends ConsumerWidget {
  const AccentSwatches({super.key, required this.touch, required this.labels});

  final bool touch;
  final bool labels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final colors = context.fmpColors;
    final current = ref.watch(accentProvider);
    // 手機列尾 26、gap 10；桌面 22、gap 14；平板 26、gap 14（`settings.html`）。
    final size = touch ? 26.0 : 22.0;
    // 色點的框（含選取環）比色點大 8；觸控時點擊區補到 44，間距扣掉補的。
    // 觸控時稿的間距（色點中心差 36、40）放不下 44 的點擊區，點擊區相鄰、
    // 不重疊，看起來色點之間是 18（`DESIGN.md`〈無障礙〉）。
    final box = touch ? context.fmpMetrics.minTarget : size + 8;
    final gap = math.max(0.0, (labels ? 14.0 : 10.0) - (box - size));
    final swatches = [
      for (final accent in Accent.values)
        AccentSwatch(
          color: accent == Accent.none ? colors.label : accent.tone500,
          label: accentLabel(t, accent),
          labelBelow: labels
              ? accent == Accent.none
                    ? t.settings.accentNoneDefault
                    : accentLabel(t, accent)
              : null,
          selected: accent == current,
          size: size,
          touch: touch,
          onTap: () => ref.read(accentProvider.notifier).set(accent),
        ),
    ];
    final row = Semantics(
      label: t.settings.accent,
      container: true,
      explicitChildNodes: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, swatch) in swatches.indexed) ...[
            if (i > 0) SizedBox(width: gap),
            swatch,
          ],
        ],
      ),
    );
    if (!labels) return row;
    final pad = (box - size) / 2;
    return Padding(
      padding: touch
          ? EdgeInsets.fromLTRB(12 - pad, 14 - pad, 12, 12)
          : EdgeInsets.fromLTRB(12 - pad, 12 - pad, 12, 10),
      child: Align(alignment: Alignment.centerLeft, child: row),
    );
  }
}

/// 主題的三張預覽圖（`.st-tiles`）：跟隨系統是淺深各半，預覽圖本身用那一套
/// token 畫。桌面每張 112×72，平板三張平分寬度。
class ThemeTiles extends ConsumerWidget {
  const ThemeTiles({super.key, required this.touch});

  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final current = ref.watch(themeModeProvider);
    final accent = ref.watch(accentProvider);
    final tiles = [
      for (final mode in ThemeMode.values)
        _ThemeTile(
          mode: mode,
          accent: accent,
          label: themeLabel(t, mode),
          selected: mode == current,
          fill: touch,
          onTap: () => ref.read(themeModeProvider.notifier).set(mode),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Row(
        children: [
          for (final (i, tile) in tiles.indexed) ...[
            if (i > 0) SizedBox(width: touch ? 10 : 16),
            if (touch) Expanded(child: tile) else tile,
          ],
        ],
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.mode,
    required this.accent,
    required this.label,
    required this.selected,
    required this.fill,
    required this.onTap,
  });

  final ThemeMode mode;
  final Accent accent;
  final String label;
  final bool selected;

  /// 平板：預覽圖撐滿分到的寬度；桌面固定 112。
  final bool fill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final halves = switch (mode) {
      ThemeMode.system => [Brightness.light, Brightness.dark],
      ThemeMode.light => [Brightness.light],
      ThemeMode.dark => [Brightness.dark],
    };
    return ShellButton(
      onTap: onTap,
      label: label,
      selected: selected,
      focusRadius: 9,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: FmpMotion.fast,
            curve: FmpMotion.outCurve,
            width: fill ? double.infinity : 112,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              // 選中的是 3 寬的強調色環，沒選的是 0.5 的細框（box-shadow）。
              boxShadow: [
                BoxShadow(
                  color: selected ? colors.accent : colors.sepStrong,
                  spreadRadius: selected ? 3 : .5,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Row(
                children: [
                  for (final brightness in halves)
                    Expanded(
                      child: _ThemePreviewHalf(
                        colors: FmpColors.of(brightness, accent),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          ExcludeSemantics(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                letterSpacing: 0,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: colors.label,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 預覽圖的一半（`.st-tile .half`）：側欄、一條標題、兩個封面與一顆強調色
/// 按鈕，位置照稿的絕對座標，超出這半的裁掉。
class _ThemePreviewHalf extends StatelessWidget {
  const _ThemePreviewHalf({required this.colors});

  final FmpColors colors;

  @override
  Widget build(BuildContext context) {
    Widget block(
      double left,
      double top,
      double w,
      double h,
      Color c,
      double r,
    ) => Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(r),
        ),
      ),
    );
    return ClipRect(
      child: ColoredBox(
        color: colors.bg,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: 5,
              top: 5,
              bottom: 5,
              width: 28,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.fill2,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            block(40, 9, 40, 5, colors.label4, 3),
            block(40, 24, 14, 14, colors.label4, 3),
            block(58, 24, 14, 14, colors.label4, 3),
            block(40, 46, 22, 9, colors.accentFill, 5),
          ],
        ),
      ),
    );
  }
}
