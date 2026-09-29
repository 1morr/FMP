import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/app_flavor.dart';

/// 資料庫開不起來時的畫面（ADR 0010 §決定 3）：App 不在半開的資料庫上啟動，
/// 只顯示錯誤。重試、匯出診斷等選項隨舊資料匯入（M5）與 log（ADR 0025）再加。
class DatabaseErrorApp extends StatelessWidget {
  const DatabaseErrorApp({
    super.key,
    required this.flavor,
    required this.error,
  });

  final AppFlavor flavor;

  /// 開啟時拋出的錯誤，原樣顯示供回報問題。
  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: flavor.displayName,
      // 先寫死繁中；slang 在 M1 PR 12 接上後改用翻譯字串。
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '無法開啟資料庫',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              SelectableText('$error'),
            ],
          ),
        ),
      ),
    );
  }
}
