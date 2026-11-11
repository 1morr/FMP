import 'package:flutter/widgets.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/data/database.dart';
import 'package:fmp/platform/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LocaleSettings.useDeviceLocaleSync();

  final database = AppDatabase.open(await databaseFile());
  // 查一次讓資料庫真的開起來；開不了就在啟動時失敗，不要等到第一次用。
  final version = await database.storedSchemaVersion();
  debugPrint('database opened, schema version $version');

  runApp(
    buildRoot(overrides: [appDatabaseProvider.overrideWithValue(database)]),
  );
}
