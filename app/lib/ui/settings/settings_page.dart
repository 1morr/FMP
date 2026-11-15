import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/ui/shell/shell_page.dart';
import 'package:material_ui/material_ui.dart';

/// 設定：外殼的一個分頁。內容在之後的票，現在只有大標題。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      ShellPage(title: context.t.shell.nav.settings);
}
