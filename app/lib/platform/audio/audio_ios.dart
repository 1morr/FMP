import 'package:fmp/platform/audio/audio.dart';

/// iOS：`just_audio`（AVPlayer），格式同 macOS（ADR 0037 §決定 7）。
///
/// 沒有 `webm/opus`：AVPlayer 不播 WebM（模擬器實測 `-11828`）。也不宣告 `ogg/opus`：iOS 27 能播
/// Ogg Opus，但插件的 Opus 都是 WebM 容器，宣告了也沒有候選。直播宣告 `hls/aac`，插件看到它就給
/// HLS。輸出裝置跟著系統，不能在 App 內選。
const iosPlaybackSupport = PlaybackSupport(
  backend: AudioBackendKind.justAudio,
  formats: [
    PlayableFormat('mp4', 'aac'),
    PlayableFormat('mp3', 'mp3'),
    PlayableFormat('flac', 'flac'),
    PlayableFormat('wav', 'pcm_s16le'),
    PlayableFormat('hls', 'aac'),
  ],
  outputDeviceSelection: false,
);
