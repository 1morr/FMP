import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/settings/appearance_controls.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 設定頁（ADR 0024 §決定 6、ADR 0011 §決定 7 的分組）。M1 只有外觀一組。
///
/// expanded 以上是 M3 canonical layout 的 list-detail：左邊分組清單、右邊那一組
/// 的內容；更窄時只有一欄，各組的標題與內容依序排下來（只有一組時，點進去再
/// 看內容只是多一步）。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).settings;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final title = Padding(
      padding: EdgeInsets.fromLTRB(spacing.x4, spacing.x4, spacing.x4, 0),
      child: Semantics(
        header: true,
        child: Text(t.title, style: theme.textTheme.headlineSmall),
      ),
    );
    final groupTitle = Semantics(
      header: true,
      child: Text(t.appearance, style: theme.textTheme.titleLarge),
    );
    final detail = SingleChildScrollView(
      padding: EdgeInsets.all(spacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          groupTitle,
          SizedBox(height: spacing.x4),
          const AppearanceControls(),
        ],
      ),
    );
    return switch (WindowClass.of(context)) {
      WindowClass.compact || WindowClass.medium => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          Expanded(child: detail),
        ],
      ),
      WindowClass.expanded ||
      WindowClass.large ||
      WindowClass.extraLarge => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: AppLayout.settingsListWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                SizedBox(height: spacing.x2),
                // 只有一組，永遠是選取的那一組；有第二組時才需要可以點。
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: Text(t.appearance),
                  selected: true,
                ),
              ],
            ),
          ),
          const VerticalDivider(),
          Expanded(child: detail),
        ],
      ),
    };
  }
}
