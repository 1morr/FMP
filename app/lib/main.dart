import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/data/database.dart';
import 'package:fmp/playback/playback.dart';
import 'package:fmp/platform/audio_backend.dart';
import 'package:fmp/platform/database_file.dart';
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

  final database = AppDatabase.open(await databaseFile());
  // 查一次讓資料庫真的開起來；開不了就在啟動時失敗，不要等到第一次用。
  final version = await database.storedSchemaVersion();
  log.info('Database opened, schema version $version');

  runApp(
    buildRoot(
      overrides: [
        logProvider.overrideWithValue(log),
        appDatabaseProvider.overrideWithValue(database),
        audioBackendProvider.overrideWith((ref) {
          final backend = createAudioBackend();
          ref.onDispose(backend.dispose);
          return backend;
        }),
      ],
    ),
  );
}
