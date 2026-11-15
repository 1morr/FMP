import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/app/icons/fmp_icons.dart';
import 'package:fmp/app/theme/theme.dart';
import 'package:fmp/ui/shell/shell_page.dart';
import 'package:material_ui/material_ui.dart';

/// 音樂庫：歌單在 M3 才有，現在是空狀態（`docs/design/library.html` 的
/// 〈空狀態〉）。新建與匯入還沒有，所以只留圖示與標題，不放說明與按鈕。
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.fmpColors;
    return ShellPage(
      title: context.t.shell.nav.library,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 120 - FmpSpace.s4),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: colors.fill,
                  borderRadius: BorderRadius.circular(22),
                ),
                alignment: Alignment.center,
                child: FmpIcon(
                  FmpIcons.library,
                  size: 34,
                  color: colors.label2,
                ),
              ),
              const SizedBox(height: FmpSpace.s2),
              Text(
                context.t.shell.library.empty,
                style: context.fmpText.title2,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
