import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/platform/audio_service_controls.dart';
import 'package:fmp/platform/cover_image.dart';
import 'package:fmp/platform/windows_media_controls.dart';
import 'package:fmp/playback/media_controls.dart';

/// 依平台建系統媒體控制（brief〈播放〉）：Android、iOS、macOS 用
/// audio_service（事實 K18），Windows 用 runner 裡自己接的 SMTC（事實 W7）。
/// 一個行程只建一次（audio_service 只能初始化一次），之後回傳同一個。
/// 建不起來時寫 warning、回傳 null，App 照常播放，只是沒有系統媒體控制。
///
/// audio_service 的封面用 App 的封面快取下載（[coverCache]），和畫面上的
/// 封面共用檔案。[notificationChannelName] 是 Android 系統設定裡這個通知
/// 頻道的名字。
Future<MediaControls?> createMediaControls(
  Log log, {
  required String notificationChannelName,
}) => _created ??= _create(log, notificationChannelName);

Future<MediaControls?>? _created;

Future<MediaControls?> _create(Log log, String channelName) async {
  if (Platform.isWindows) return WindowsMediaControls.start(log);
  if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) return null;
  try {
    final mediaKeys = Platform.isAndroid ? MediaKeyFix(log) : null;
    final controls = await AudioService.init(
      builder: () => AudioServiceControls(mediaKeys: mediaKeys),
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.personal.fmp.playback',
        androidNotificationChannelName: channelName,
      ),
      cacheManager: coverCache,
    );
    // 服務在 init 時已建好；之後重建時 AudioServiceControls 會再裝。
    await mediaKeys?.install();
    log.info('Media controls ready');
    return controls;
  } catch (error, stackTrace) {
    log.warning(
      'Starting the media controls failed',
      error: error,
      stackTrace: stackTrace,
    );
    return null;
  }
}
