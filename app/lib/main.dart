import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter/widgets.dart';

import 'package:fmp/app/fmp_app.dart';
import 'package:fmp/core/app_flavor.dart';
import 'package:fmp/platform/app_data_directory/app_data_directory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final flavor = AppFlavor.parse(appFlavor);
  final dataDirectory = await appDataDirectoryFor(flavor)?.resolve();
  runApp(FmpApp(flavor: flavor, dataDirectoryPath: dataDirectory?.path));
}
