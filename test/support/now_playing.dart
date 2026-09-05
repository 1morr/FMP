import 'package:fmp/services/audio/audio_handler.dart';
import 'package:fmp/services/audio/audio_runtime_platform.dart';
import 'package:fmp/services/audio/now_playing_publisher.dart';
import 'package:fmp/services/audio/windows_smtc_handler.dart';

/// 測試用的 [NowPlayingPublisher]。
///
/// 兩個 handler 都用真的實例，不是替身：
///
/// - [FmpAudioHandler] 繼承 `BaseAudioHandler`，`playbackState` / `mediaItem`
///   是真的 `BehaviorSubject`，純單元測試裡可以直接斷言。
/// - [WindowsSmtcHandler] 只建構、不 `initialize()`，所以 `_smtc` 恆為 null，
///   每個方法都自己早退 —— **即使在 Windows 開發機上跑也安全**。
///
/// 因此這裡不需要（也刻意不加）任何只為了被測而存在的介面或 spy。
NowPlayingPublisher testNowPlayingPublisher({
  AudioRuntimePlatform platform = AudioRuntimePlatform.desktop,
  FmpAudioHandler? audioHandler,
  WindowsSmtcHandler? smtcHandler,
}) {
  return NowPlayingPublisher(
    audioHandler: audioHandler ?? FmpAudioHandler(),
    smtcHandler: smtcHandler ?? WindowsSmtcHandler(),
    platform: platform,
  );
}
