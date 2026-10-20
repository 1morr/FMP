import 'package:material_ui/material_ui.dart';

import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

// 遠端寫入結果的「詳細」（M4 design §7.1、§7.2，ADR 0013 §決定 5 的部分成功列出失敗項）。

/// 「詳細」裡的一列：[title] 是歌單或曲目的名稱，[reason] 是已翻譯的原因。
typedef RemoteFailureRow = ({String title, String reason});

/// 在 [navigator] 上開失敗清單（提示的「詳細」按下時，原本的對話框與頁面可能已經關掉，
/// 所以走根 Navigator，同 `openErrorDetail`）。
Future<void> showRemoteFailureDetails(
  NavigatorState navigator,
  Translations translations, {
  required List<RemoteFailureRow> rows,
}) {
  final t = translations.library;
  return navigator.push(
    DialogRoute<void>(
      context: navigator.context,
      builder: (context) => AlertDialog(
        title: Text(t.remoteDetailsTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final row in rows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(row.title),
                  subtitle: Text(
                    row.reason,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.remoteClose),
          ),
        ],
        insetPadding: EdgeInsets.all(AppTokens.of(context).spacing.x4),
      ),
    ),
  );
}
