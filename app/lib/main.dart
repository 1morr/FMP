import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:fmp/app/app.dart';
import 'package:fmp/app/audio_backend_lifecycle.dart';
import 'package:fmp/app/storage.dart';
import 'package:fmp/app/storage_notice.dart';
import 'package:fmp/app/uncaught_errors.dart';
import 'package:fmp/app/i18n/language.dart';
import 'package:fmp/app/i18n/strings.g.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/data/database.dart';
import 'package:fmp/data/settings_store.dart';
import 'package:fmp/platform/app_data_directory.dart';
import 'package:fmp/platform/audio_backend.dart';
import 'package:fmp/platform/audio_session.dart';
import 'package:fmp/platform/cover_image.dart';
import 'package:fmp/platform/database_file.dart';
import 'package:fmp/platform/media_controls.dart';
import 'package:fmp/platform/log_directory.dart';
import 'package:fmp/platform/orientation.dart';
import 'package:fmp/playback/audio_backend.dart';
import 'package:fmp/playback/media_controls.dart';
import 'package:fmp/playback/queue_saver.dart';

Future<void> main() => runFmp();

/// 開 App。[wrapAudioBackend] 只給實跑驅動（`integration_test/real_run/`）：
/// 包住這個平台的音訊後端，例如讓一次載入拿到壞掉的網址。
Future<void> runFmp({
  AudioBackend Function(AudioBackend backend)? wrapAudioBackend,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await lockPhoneToPortrait();
  final data = await appDataDirectory();
  if (scratchDataName.isNotEmpty) keepCoverCacheIn(data);
  final log = await Log.open(
    logDirectory(data),
    minimumLevel: minimumLogLevel(release: kReleaseMode),
    console: kDebugMode,
  );
  logUncaughtErrors(log);
  log.info('App started');
  await configureAudioSession(log);

  // 開不了或讀不回來時照常能搜尋、播放，啟動時提示一次（openStorage）。
  final storage = await openStorage(await databaseFile(data), log);
  // 第一個畫面就照存的語言（設定「外觀 › 語言」）。
  LanguageSetting.applySaved(storage.settings);
  // 系統媒體控制（brief〈播放〉）；建不起來時照常播放。
  final mediaControls = await createMediaControls(
    log,
    notificationChannelName: t.app.mediaNotificationChannel,
  );

  runApp(
    buildRoot(
      overrides: [
        logProvider.overrideWithValue(log),
        appDatabaseProvider.overrideWithValue(storage.database),
        savedQueueProvider.overrideWithValue(storage.saved),
        savedSettingsProvider.overrideWithValue(storage.settings),
        storageNoticeProvider.overrideWithValue(storage.notice),
        mediaControlsProvider.overrideWithValue(mediaControls),
        audioBackendOverride(() {
          final backend = createAudioBackend(log);
          return wrapAudioBackend?.call(backend) ?? backend;
        }),
      ],
    ),
  );
}
