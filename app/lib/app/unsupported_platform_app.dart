import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/app_flavor.dart';

/// 平台沒有資料目錄實作時的畫面（Linux、macOS、iOS 驗證前，ADR 0009
/// §決定 4）。不啟動資料層，只告訴使用者這個平台還不能用。
class UnsupportedPlatformApp extends StatelessWidget {
  const UnsupportedPlatformApp({super.key, required this.flavor});

  final AppFlavor flavor;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: flavor.displayName,
      // 先寫死繁中；slang 在 M1 PR 12 接上後改用翻譯字串。
      home: const Scaffold(body: Center(child: Text('此平台尚未支援'))),
    );
  }
}
