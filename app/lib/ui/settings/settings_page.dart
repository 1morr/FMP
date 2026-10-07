import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/settings/appearance_controls.dart';
import 'package:fmp/ui/settings/network_controls.dart';
import 'package:fmp/ui/settings/playback_controls.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 設定的分組（ADR 0011 §決定 7），依 design §9.8 的順序：外觀、播放、網路。
enum SettingsGroup {
  appearance(Icons.palette_outlined),
  playback(Icons.play_circle_outline),
  network(Icons.public);

  const SettingsGroup(this.icon);

  final IconData icon;
}

/// 設定頁要不要接住系統返回鍵：窄版點進某一組時，返回鍵先回到分組清單。
///
/// 返回鍵只有外殼的 `PopScope` 一個（design §9.1）：它先問這裡，接住了就不
/// 換頁。兩邊各有一個 `PopScope` 的話，同一次返回兩邊的 callback 都會執行，
/// 回到清單的同時外殼也跳回第一頁。
final class SettingsBack {
  bool Function() _release = () => false;

  /// 設定頁在返回鍵該回到分組清單時回到清單並回傳 `true`；否則什麼都不做、回傳 `false`。
  bool release() => _release();
}

/// 設定頁（ADR 0024 §決定 6、ADR 0011 §決定 7 的分組）。
///
/// expanded 以上是 M3 canonical layout 的 list-detail：左邊分組清單、右邊那一組
/// 的內容，預設選第一組。更窄時一次只有一欄：先是分組清單，點進去看那一組的
/// 內容，系統返回鍵與標題旁的返回鈕回到清單。選了哪一組由頁面記著，視窗寬度
/// 跨過斷點時不丟。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, required this.visible, required this.back});

  /// 外殼目前顯示的是不是這一頁。外殼以 `IndexedStack` 留著沒選的頁面，看不到時
  /// 不接住返回鍵，選的那一組留著。
  final bool visible;

  /// 外殼的返回鍵先問它（[SettingsBack]）。
  final SettingsBack back;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  /// 使用者點進去的那一組；`null` 是還沒選（窄版顯示清單，寬版用第一組）。
  SettingsGroup? _selected;

  @override
  void initState() {
    super.initState();
    widget.back._release = _releaseGroup;
  }

  @override
  void didUpdateWidget(SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.back._release = _releaseGroup;
  }

  bool _releaseGroup() {
    final narrow = switch (WindowClass.of(context)) {
      WindowClass.compact || WindowClass.medium => true,
      _ => false,
    };
    if (!widget.visible || !narrow || _selected == null) return false;
    setState(() => _selected = null);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).settings;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    String name(SettingsGroup group) => switch (group) {
      SettingsGroup.appearance => t.appearance,
      SettingsGroup.playback => t.playback,
      SettingsGroup.network => t.network,
    };
    Widget header(Widget? leading, String text, TextStyle? style) => Padding(
      padding: EdgeInsets.fromLTRB(spacing.x4, spacing.x4, spacing.x4, 0),
      child: Row(
        children: [
          ?leading,
          Expanded(
            child: Semantics(header: true, child: Text(text, style: style)),
          ),
        ],
      ),
    );
    final title = header(null, t.title, theme.textTheme.headlineSmall);
    Widget list(SettingsGroup? selected) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title,
        SizedBox(height: spacing.x2),
        for (final group in SettingsGroup.values)
          ListTile(
            leading: Icon(group.icon),
            title: Text(name(group)),
            selected: group == selected,
            onTap: () => setState(() => _selected = group),
          ),
      ],
    );
    Widget detail(SettingsGroup group, {required bool heading}) =>
        SingleChildScrollView(
          padding: EdgeInsets.all(spacing.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (heading) ...[
                Semantics(
                  header: true,
                  child: Text(name(group), style: theme.textTheme.titleLarge),
                ),
                SizedBox(height: spacing.x4),
              ],
              switch (group) {
                SettingsGroup.appearance => const AppearanceControls(),
                SettingsGroup.playback => const PlaybackControls(),
                SettingsGroup.network => const NetworkControls(),
              },
            ],
          ),
        );
    return switch (WindowClass.of(context)) {
      WindowClass.compact || WindowClass.medium => switch (_selected) {
        null => list(null),
        final group => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header(
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: t.back,
                onPressed: () => setState(() => _selected = null),
              ),
              name(group),
              theme.textTheme.headlineSmall,
            ),
            // 標題已經在上面那一列。
            Expanded(child: detail(group, heading: false)),
          ],
        ),
      },
      WindowClass.expanded ||
      WindowClass.large ||
      WindowClass.extraLarge => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: AppLayout.settingsListWidth,
            child: list(_selected ?? SettingsGroup.values.first),
          ),
          const VerticalDivider(),
          Expanded(
            child: detail(
              _selected ?? SettingsGroup.values.first,
              heading: true,
            ),
          ),
        ],
      ),
    };
  }
}
