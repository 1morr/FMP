import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio;
import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:fmp/core/logging/log.dart';
import 'package:fmp/platform/media_controls/media_controls.dart';
import 'package:fmp/platform/media_controls/media_controls_audio_service.dart';

/// Android 的系統媒體控制（design §8.3）：以 `audio_service` 顯示通知與鎖定
/// 畫面、接媒體鍵。
///
/// 播放仍由 `JustAudioBackend` 負責，`audio_service` 只當作「媒體工作階段」：
/// 通知上的按鈕、進度條與媒體鍵經 [commands] 回到控制器。
final class AndroidSystemMediaControls implements SystemMediaControls {
  AndroidSystemMediaControls._(this._handler, Log log, this._mediaKeyFix) {
    // audio_service 在背景做的事失敗時（例如前景服務被拒絕）只進這個 stream，
    // 不聽就沒有人知道。只記 log，不提示使用者。
    _asyncErrors = reportAsyncErrors(audio.AudioService.asyncError, log);
  }

  /// 初始化 `audio_service`（要在 `runApp` 前、開好資料庫後呼叫；失敗時丟出，
  /// 由 `AppPlatform.withMediaControls` 改宣告為沒有）。[log] 記初始化之後
  /// `audio_service` 回報的非同步錯誤。
  static Future<AndroidSystemMediaControls> init(Log log) async {
    final handler = await audio.AudioService.init(
      builder: AudioServiceCommandHandler.new,
      config: const audio.AudioServiceConfig(
        // 使用者在系統設定看得到的通知頻道名稱。
        androidNotificationChannelId: 'com.personal.fmp.playback',
        androidNotificationChannelName: 'FMP',
        // 暫停時放掉前景服務，通知可以滑掉（舊版也是這樣）。因中斷而暫停的期間
        // 例外：那時對 audio_service 回報還在播放（MediaPhase.interrupted），
        // 前景服務不放；中斷結束續播時 App 在背景，audio_service 的
        // startForegroundService 會被 Android 12 起拒絕，服務不在前景就約一分
        // 鐘後被停、再約一分半後被凍結，音樂就停了。
        androidStopForegroundOnPause: true,
      ),
    );
    final controls = AndroidSystemMediaControls._(
      handler,
      log,
      MediaKeyFix(log),
    );
    // 服務在 init 時已建好；之後服務被系統重建，publish 會再裝一次。
    await controls._mediaKeyFix.install();
    return controls;
  }

  /// 測試用：不初始化 `audio_service`，只建 handler 與媒體鍵修正。
  @visibleForTesting
  AndroidSystemMediaControls.forTest(Log log, MediaKeyFix mediaKeyFix)
    : this._(AudioServiceCommandHandler(), log, mediaKeyFix);

  final AudioServiceCommandHandler _handler;
  final MediaKeyFix _mediaKeyFix;
  late final StreamSubscription<Object> _asyncErrors;

  @override
  Stream<MediaCommand> get commands => _handler.commands;

  @override
  Future<void> publish(NowPlaying nowPlaying) async {
    final handler = _handler;
    if (nowPlaying.hasTrack) {
      handler.mediaItem.add(audioServiceMediaItemOf(nowPlaying));
    }
    handler.playbackState.add(audioServicePlaybackStateOf(nowPlaying));
    // 有曲目才會有（重建的）服務；便宜且可重複，不等結果。
    if (nowPlaying.phase != MediaPhase.idle) unawaited(_mediaKeyFix.install());
  }

  /// 只有重啟流程（`AndroidAppRestarter`）在結束行程前呼叫。先等平台收掉前景服務、通知與
  /// media session：`audio_service` 自己是在 `playbackState` 的監聽裡非同步呼叫
  /// `stopService`，緊接著 `exit(0)` 時平台還沒收到，`NO_CLEAR` 的媒體通知會殘留（2026-10-14
  /// Android 模擬器實測）。
  @override
  Future<void> dispose() async {
    await AudioServicePlatform.instance.stopService(const StopServiceRequest());
    await _asyncErrors.cancel();
    await _handler.close();
  }
}

/// 修正 Android 媒體鍵（#233）：`audio_service` 把真正的「播放」「暫停」鍵都當成切換，
/// 已暫停時收到「暫停」鍵會開始播放。原生端（`MediaKeyFix.java`）用反射把服務的
/// media session callback 換成會改寫鍵碼的版本，這裡只負責在服務建好後呼叫。
/// 失敗（服務還沒建好、反射失敗、頻道不在）都只記 debug log，不影響播放。
class MediaKeyFix {
  MediaKeyFix(this._log, {MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('fmp/media_keys');

  final Log _log;
  final MethodChannel _channel;

  /// 回傳原生端有沒有裝好；任何失敗都是 `false`，不丟例外。
  Future<bool> install() async {
    try {
      final installed = await _channel.invokeMethod<bool>('install') ?? false;
      if (!installed) {
        _log.debug(
          'The media key fix was not installed',
          tag: 'media-controls',
        );
      }
      return installed;
    } on Object catch (error) {
      // MissingPluginException（沒有 Activity 的引擎）與 PlatformException 都不該動到播放。
      _log.debug(
        'The media key fix failed',
        tag: 'media-controls',
        error: error,
      );
      return false;
    }
  }
}
