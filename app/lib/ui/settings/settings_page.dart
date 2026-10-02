import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/settings/appearance_controls.dart';
import 'package:fmp/ui/settings/network_controls.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 設定的分組（ADR 0011 §決定 7）。「播放」組在有第一列設定的 PR 才加。
enum SettingsGroup {
  appearance(Icons.palette_outlined),
  network(Icons.public);

  const SettingsGroup(this.icon);

  final IconData icon;
}

/// 設定頁（ADR 0024 §決定 6、ADR 0011 §決定 7 的分組）。
///
/// expanded 以上是 M3 canonical layout 的 list-detail：左邊分組清單、右邊那一組
/// 的內容，預設選第一組。更窄時一次只有一欄：先是分組清單，點進去看那一組的
/// 內容，系統返回鍵與標題旁的返回鈕回到清單。選了哪一組由頁面記著，視窗寬度
/// 跨過斷點時不丟。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, required this.visible});

  /// 外殼目前顯示的是不是這一頁。外殼以 `IndexedStack` 留著沒選的頁面，看不到時
  /// 不攔系統返回鍵，返回鍵照常交給外殼與系統。
  final bool visible;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  /// 使用者點進去的那一組；`null` 是還沒選（窄版顯示清單，寬版用第一組）。
  SettingsGroup? _selected;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).settings;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    String name(SettingsGroup group) => switch (group) {
      SettingsGroup.appearance => t.appearance,
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
                SettingsGroup.network => const NetworkControls(),
              },
            ],
          ),
        );
    return switch (WindowClass.of(context)) {
      WindowClass.compact || WindowClass.medium => switch (_selected) {
        null => list(null),
        final group => PopScope(
          canPop: !widget.visible,
          // 看不到時 `canPop` 為真，返回鍵不歸這一頁，選的那一組留著。
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && widget.visible) setState(() => _selected = null);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header(
                IconButton(
                  icon: Icon(Icons.arrow_back, semanticLabel: t.back),
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
