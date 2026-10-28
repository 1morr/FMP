import 'package:fmp/platform/audio/audio.dart';

/// macOS：`just_audio`（AVPlayer）。
///
/// AVPlayer 不播 WebM，所以沒有 `webm/opus`：只給 AAC（Bilibili）、MP3、FLAC、WAV。
/// 直播：AVPlayer 也不播 FLV，宣告 `hls/aac`，插件的 `resolveLive` 看到它就給 HLS（B 站插件 1.12.0
/// 起改要 h5 的 `.m3u8`，ADR 0036 §決定 7）。輸出裝置跟著系統，不能在 App 內選。
const macosPlaybackSupport = PlaybackSupport(
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
