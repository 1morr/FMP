import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:fmp/core/log/log.dart';

/// 把 App 的 audio session 設定成音樂 App（Android 的媒體用途與音訊焦點、
/// iOS 的 playback 類別）。just_audio 播放時啟用它，並照它處理中斷與拔
/// 耳機（事實 K30）；Windows 的 media_kit 不用它，audio_session 也沒有 Windows 實作。
/// 設不成功時寫一筆 warning，照預設播。
Future<void> configureAudioSession(Log log) async {
  if (Platform.isWindows) return;
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    log.info('Audio session configured for music');
  } catch (error, stackTrace) {
    log.warning(
      'Configuring the audio session failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
