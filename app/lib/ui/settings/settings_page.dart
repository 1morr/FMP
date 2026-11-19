import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/platform/form_factor.dart';
import 'package:fmp/ui/settings/settings_sections.dart';
import 'package:fmp/ui/shell/shell_controls.dart';
import 'package:fmp/ui/shell/shell_page.dart';
import 'package:material_ui/material_ui.dart';

/// 桌面與中寬度選中的分類：這次開 App 期間記住，換頁回來還在。
final settingsCategoryProvider =
    NotifierProvider<SettingsCategorySelection, SettingsCategory>(
      SettingsCategorySelection.new,
    );

class SettingsCategorySelection extends Notifier<SettingsCategory> {
  @override
  SettingsCategory build() => SettingsCategory.values.first;

  void select(SettingsCategory category) => state = category;
}

/// 設定（`docs/design/settings.html`）：手機是 iOS 的群組列表，桌面與中寬度
/// 是 macOS 系統設定式的分類欄加內容窗格。M1 只有外觀與播放。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final form = FormFactor.of(context);
    return switch (form.widthClass) {
      WidthClass.narrow => const _PhoneSettings(),
      _ => _SplitSettings(touch: form.density == Density.touch),
    };
  }
}

// ---------------------------------------------------------------- 手機

class _PhoneSettings extends StatefulWidget {
  const _PhoneSettings();

  @override
  State<_PhoneSettings> createState() => _PhoneSettingsState();
}

class _PhoneSettingsState extends State<_PhoneSettings> {
  /// 大標題捲出去之後，頂列淡入小標題（同首頁）。
  static const _titleGoneOffset = 40.0;

  final _scroll = ScrollController();
  final _scrolled = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(
      () => _scrolled.value = _scroll.offset > _titleGoneOffset,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    _scrolled.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final insets = ShellInsets.of(context);
    final bar = ShellInsets.topBarOf(context);
    final title = context.t.shell.nav.settings;
    return ColoredBox(
      // 群組列表襯在群組底色上（`.phone.st-grp`）。
      color: colors.bgGrouped,
      child: Stack(
        children: [
          Positioned.fill(
            child: ListView(
              controller: _scroll,
              padding: EdgeInsets.only(top: insets.top, bottom: insets.bottom),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Semantics(
                    header: true,
                    child: Text(title, style: context.fmpText.large),
                  ),
                ),
                // `.lt` 的下內距 10 加上第一個 `.ghead` 的上外距 28 已在
                // SettingsHead 裡。
                const SizedBox(height: 10),
                const PhoneAppearanceGroup(),
                const PhonePlaybackGroup(),
                const SizedBox(height: 24),
              ],
            ),
          ),
          // `.edge-top`：捲動後頂列底下淡出內容，小標題不壓在列上。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: bar.top + bar.height + 24,
            child: IgnorePointer(
              child: _WhenScrolled(
                scrolled: _scrolled,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colors.bgGrouped,
                        colors.bgGrouped,
                        colors.bgGrouped.withValues(alpha: 0),
                      ],
                      stops: const [0, .7, 1],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: bar.top,
            left: bar.left,
            right: bar.right,
            height: bar.height,
            child: IgnorePointer(
              child: _WhenScrolled(
                scrolled: _scrolled,
                child: Center(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                      color: colors.label,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 捲動後才淡入的東西；沒捲動時螢幕閱讀器也略過。
class _WhenScrolled extends StatelessWidget {
  const _WhenScrolled({required this.scrolled, required this.child});

  final ValueListenable<bool> scrolled;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: scrolled,
    builder: (context, scrolled, child) => ExcludeSemantics(
      excluding: !scrolled,
      child: AnimatedOpacity(
        opacity: scrolled ? 1 : 0,
        duration: FmpMotion.mid,
        child: child,
      ),
    ),
    child: child,
  );
}

// ---------------------------------------------------------------- 桌面、中寬度

/// 分類欄加內容窗格（`.sx`）：從內容區左緣起，分類欄桌面 212、平板 260
/// 寬，右邊一條細線；窗格一次只顯示一類。頂列左端寫「設定」（`.sx-wt`）。
class _SplitSettings extends ConsumerWidget {
  const _SplitSettings({required this.touch});

  final bool touch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.fmpColors;
    final insets = ShellInsets.of(context);
    final bar = ShellInsets.topBarOf(context);
    final category = ref.watch(settingsCategoryProvider);
    // 外殼給的頂部內距：桌面 66、平板 62（都加上狀態列）。窗格從 62 起、
    // 分類欄桌面從 64、平板從 68 起（`.sx-pane`、`.sx-cats`）。
    final top = insets.top - (touch ? 0 : 4);
    final pane = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(36, top, 36, insets.bottom),
      child: AnimatedSwitcher(
        key: const Key('settings-pane'),
        // 換分類只淡入淡出，減少動態效果時也一樣（`DESIGN.md`〈動態〉）。
        duration: FmpMotion.fast,
        switchInCurve: FmpMotion.outCurve,
        switchOutCurve: FmpMotion.outCurve,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topLeft,
          children: [...previous, ?current],
        ),
        child: KeyedSubtree(
          key: ValueKey(category),
          child: switch (category) {
            SettingsCategory.appearance => AppearancePane(touch: touch),
            SettingsCategory.playback => PlaybackPane(touch: touch),
          },
        ),
      ),
    );
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          // 桌面離右緣 16，平板貼齊（`.sx`、`.tablet .sx`）。
          right: touch ? 0 : 16,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: touch ? 260 : 212,
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(color: colors.sep, width: .5),
                  ),
                ),
                child: _CategoryList(
                  touch: touch,
                  top: touch ? insets.top + 6 : insets.top - 2,
                  bottom: insets.bottom,
                ),
              ),
              Expanded(child: pane),
            ],
          ),
        ),
        Positioned(
          top: bar.top,
          left: bar.left,
          height: bar.height,
          child: Center(
            child: Text(
              context.t.shell.nav.settings,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                color: colors.label,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 分類欄（`.sx-cats`）：選中的是強調色實心底，和側欄的灰色選取分開「App
/// 導覽」與「設定分類」兩層。
class _CategoryList extends ConsumerWidget {
  const _CategoryList({
    required this.touch,
    required this.top,
    required this.bottom,
  });

  final bool touch;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final current = ref.watch(settingsCategoryProvider);
    return Semantics(
      label: t.settings.categories,
      container: true,
      explicitChildNodes: true,
      child: FocusTraversalGroup(
        child: ListView(
          padding: touch
              ? EdgeInsets.fromLTRB(8, top, 14, bottom)
              : EdgeInsets.fromLTRB(2, top, 12, bottom),
          children: [
            for (final category in SettingsCategory.values)
              Padding(
                padding: EdgeInsets.only(bottom: touch ? 2 : 1),
                child: _CategoryItem(
                  category: category,
                  selected: category == current,
                  touch: touch,
                  onTap: () => ref
                      .read(settingsCategoryProvider.notifier)
                      .select(category),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryItem extends StatelessWidget {
  const _CategoryItem({
    required this.category,
    required this.selected,
    required this.touch,
    required this.onTap,
  });

  final SettingsCategory category;
  final bool selected;
  final bool touch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    final ink = selected ? colors.accentInk : colors.label;
    final radius = touch ? 12.0 : 8.0;
    return ShellButton(
      onTap: onTap,
      selected: selected,
      focusRadius: radius,
      builder: (context, hovered) => AnimatedContainer(
        duration: FmpMotion.fast,
        height: touch ? 44 : 32,
        padding: touch
            ? const EdgeInsets.fromLTRB(8, 0, 10, 0)
            : const EdgeInsets.fromLTRB(6, 0, 8, 0),
        decoration: BoxDecoration(
          color: selected
              ? colors.accentFill
              : hovered
              ? colors.fill
              : null,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Row(
          children: [
            Container(
              width: touch ? 30 : 22,
              height: touch ? 30 : 22,
              decoration: BoxDecoration(
                color: selected
                    ? colors.accentInk.withValues(alpha: .22)
                    : colors.fill2,
                borderRadius: BorderRadius.circular(touch ? 8 : 6),
              ),
              alignment: Alignment.center,
              child: FmpIcon(category.icon, size: touch ? 18 : 14, color: ink),
            ),
            SizedBox(width: touch ? 12 : 9),
            Expanded(
              child: Text(
                category.label(context.t),
                style: TextStyle(
                  fontSize: touch ? 16 : 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                  color: ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
