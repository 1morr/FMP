import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/platform/log_directory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LocaleSettings.useDeviceLocaleSync();
  final log = await Log.open(
    await logDirectory(),
    minimumLevel: minimumLogLevel(release: kReleaseMode),
    console: kDebugMode,
  );
  log.info('App started');
  runApp(buildRoot());
}
