import 'package:fmp/platform/audio/audio.dart';

/// macOS：`just_audio`（AVPlayer）。
///
/// AVPlayer 不播 WebM，所以沒有 `webm/opus`：只給 AAC（Bilibili）、MP3、FLAC、WAV。
/// HLS 等直播的里程碑再加。輸出裝置跟著系統，不能在 App 內選。
const macosPlaybackSupport = PlaybackSupport(
  backend: AudioBackendKind.justAudio,
  formats: [
    PlayableFormat('mp4', 'aac'),
    PlayableFormat('mp3', 'mp3'),
    PlayableFormat('flac', 'flac'),
    PlayableFormat('wav', 'pcm_s16le'),
  ],
  outputDeviceSelection: false,
);
