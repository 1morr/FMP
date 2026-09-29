import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter/widgets.dart';

import 'package:fmp/app/fmp_app.dart';
import 'package:fmp/app/unsupported_platform_app.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/platform.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final flavor = AppFlavor.parse(appFlavor);
  final platform = AppPlatform.current(flavor);
  // 沒有資料目錄的平台不啟動資料層（能力宣告 dataDirectory 為假）。
  switch (platform.dataDirectory) {
    case null:
      runApp(UnsupportedPlatformApp(flavor: flavor));
    case final dataDirectory:
      final directory = await dataDirectory.resolve();
      runApp(FmpApp(flavor: flavor, dataDirectoryPath: directory.path));
  }
}
