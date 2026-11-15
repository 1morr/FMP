import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/ui/shell/shell_page.dart';
import 'package:material_ui/material_ui.dart';

/// 佇列：外殼的一個分頁。內容在之後的票，現在只有大標題。
class QueuePage extends StatelessWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context) =>
      ShellPage(title: context.t.shell.nav.queue);
}
