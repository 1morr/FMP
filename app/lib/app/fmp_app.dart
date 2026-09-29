import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';

/// App 根元件。目前只顯示 App 名稱、flavor 與資料目錄，供實機確認身分；
/// 正式的外殼在 M1 PR 12。
class FmpApp extends StatelessWidget {
  const FmpApp({super.key, required this.flavor});

  final AppFlavor flavor;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: flavor.displayName,
      home: _IdentityPage(flavor: flavor),
    );
  }
}

class _IdentityPage extends ConsumerWidget {
  const _IdentityPage({required this.flavor});

  final AppFlavor flavor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            SelectableText(ref.watch(dataDirectoryProvider).path),
          ],
        ),
      ),
    );
  }
}
