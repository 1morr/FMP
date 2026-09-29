import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/app_flavor.dart';

/// App 根元件。目前只顯示 App 名稱、flavor 與資料目錄，供實機確認身分；
/// 正式的外殼在 M1 PR 12。
class FmpApp extends StatelessWidget {
  const FmpApp({
    super.key,
    required this.flavor,
    required this.dataDirectoryPath,
  });

  final AppFlavor flavor;
  final String dataDirectoryPath;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: flavor.displayName,
      home: _IdentityPage(flavor: flavor, dataDirectoryPath: dataDirectoryPath),
    );
  }
}

class _IdentityPage extends StatelessWidget {
  const _IdentityPage({required this.flavor, required this.dataDirectoryPath});

  final AppFlavor flavor;
  final String dataDirectoryPath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              flavor.displayName,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(flavor.name),
            SelectableText(dataDirectoryPath),
          ],
        ),
      ),
    );
  }
}
