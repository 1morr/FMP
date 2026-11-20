import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/ui/common/empty_state.dart';
import 'package:fmp/ui/shell/shell_page.dart';
import 'package:material_ui/material_ui.dart';

/// 音樂庫：歌單在 M3 才有，現在是空狀態（`docs/design/library.html` 的
/// 〈空狀態〉）。新建與匯入還沒有，所以只留圖示與標題，不放說明與按鈕。
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ShellPage(
      title: context.t.shell.nav.library,
      empty: EmptyState(
        icon: FmpIcons.library,
        title: context.t.shell.library.empty,
        titleStyle: context.fmpText.title2,
      ),
    );
  }
}
