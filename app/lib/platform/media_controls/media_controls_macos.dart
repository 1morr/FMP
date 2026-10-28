import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio;
import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/core/logging/log.dart';
import 'package:fmp/platform/media_controls/media_controls.dart';
import 'package:fmp/platform/media_controls/media_controls_audio_service.dart';

/// macOS 的系統媒體控制（ADR 0036 §決定 8）：以 `audio_service` 的 darwin 實作
/// 驅動 `MPNowPlayingInfoCenter` 與 `MPRemoteCommandCenter`（控制中心與選單列的
/// 「正在播放」、媒體鍵）。
///
/// 播放仍由 `JustAudioBackend` 負責，`audio_service` 只當作「媒體工作階段」：
/// 系統的按鍵與進度條經 [commands] 回到控制器。
final class MacosSystemMediaControls implements SystemMediaControls {
  MacosSystemMediaControls._(this._handler, Log log) {
    _asyncErrors = reportAsyncErrors(audio.AudioService.asyncError, log);
  }

  /// 初始化 `audio_service`（要在 `runApp` 前呼叫；失敗時丟出，由
  /// `AppPlatform.withMediaControls` 改宣告為沒有）。darwin 端沒有通知頻道或前景
  /// 服務，用預設設定即可。
  static Future<MacosSystemMediaControls> init(Log log) async {
    final handler = await audio.AudioService.init(
      builder: AudioServiceCommandHandler.new,
    );
    return MacosSystemMediaControls._(handler, log);
  }

  /// 測試用：不初始化 `audio_service`，只建 handler。
  @visibleForTesting
  MacosSystemMediaControls.forTest(Log log)
    : this._(AudioServiceCommandHandler(), log);

  final AudioServiceCommandHandler _handler;
  late final StreamSubscription<Object> _asyncErrors;

  @visibleForTesting
  AudioServiceCommandHandler get handlerForTest => _handler;

  @override
  Stream<MediaCommand> get commands => _handler.commands;

  @override
  Future<void> publish(NowPlaying nowPlaying) async {
    if (nowPlaying.hasTrack) {
      _handler.mediaItem.add(audioServiceMediaItemOf(nowPlaying));
    }
    _handler.playbackState.add(audioServicePlaybackStateOf(nowPlaying));
  }

  /// 清掉「正在播放」與遠端指令；重啟流程（`MacosAppRestarter`）在結束行程前呼叫。
  /// 先等平台收掉，否則緊接著 `exit` 時舊行程的資訊可能殘留。
  @override
  Future<void> dispose() async {
    await AudioServicePlatform.instance.stopService(const StopServiceRequest());
    await _asyncErrors.cancel();
    await _handler.close();
  }
}
