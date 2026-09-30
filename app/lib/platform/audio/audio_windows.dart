import 'package:fmp/platform/audio/audio.dart';

/// Windows：`media_kit`（libmpv，內建 FFmpeg 解碼）。
///
/// 格式與 Android 相同：清單表達的是 M1 的音源會給的格式，不是 FFmpeg 能解的
/// 全部。直播的 FLV／HLS 在直播的里程碑加。
const windowsPlaybackSupport = PlaybackSupport(
  backend: AudioBackendKind.mediaKit,
  formats: [
    PlayableFormat('mp4', 'aac'),
    PlayableFormat('webm', 'opus'),
    PlayableFormat('mp3', 'mp3'),
    PlayableFormat('flac', 'flac'),
    PlayableFormat('wav', 'pcm_s16le'),
  ],
);
