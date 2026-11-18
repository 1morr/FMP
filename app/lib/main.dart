import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/audio_backend_lifecycle.dart';
import 'package:fmp/app/storage.dart';
import 'package:fmp/app/storage_notice.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/data/database.dart';
import 'package:fmp/platform/app_data_directory.dart';
import 'package:fmp/platform/audio_backend.dart';
import 'package:fmp/platform/cover_image.dart';
import 'package:fmp/platform/database_file.dart';
import 'package:fmp/platform/log_directory.dart';
import 'package:fmp/platform/orientation.dart';
import 'package:fmp/playback/queue_saver.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LocaleSettings.useDeviceLocaleSync();
  await lockPhoneToPortrait();
  final data = await appDataDirectory();
  if (scratchDataName.isNotEmpty) keepCoverCacheIn(data);
  final log = await Log.open(
    logDirectory(data),
    minimumLevel: minimumLogLevel(release: kReleaseMode),
    console: kDebugMode,
  );
  log.info('App started');

  // 開不了或讀不回來時照常能搜尋、播放，啟動時提示一次（openStorage）。
  final storage = await openStorage(await databaseFile(data), log);

  runApp(
    buildRoot(
      overrides: [
        logProvider.overrideWithValue(log),
        appDatabaseProvider.overrideWithValue(storage.database),
        savedQueueProvider.overrideWithValue(storage.saved),
        storageNoticeProvider.overrideWithValue(storage.notice),
        audioBackendOverride(() => createAudioBackend(log)),
      ],
    ),
  );
}
