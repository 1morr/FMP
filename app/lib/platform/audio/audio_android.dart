import 'package:fmp/platform/audio/audio.dart';

/// Android：`just_audio`（ExoPlayer）。
///
/// 格式只列 M1 的音源會給的：B 站的 DASH 音訊（fMP4／AAC）與 FLAC、YouTube
/// 的 AAC 與 Opus、網易的 MP3 與 FLAC，以及測試插件的 WAV。ExoPlayer 的支援表：
/// https://developer.android.com/media/media3/exoplayer/supported-formats
const androidPlaybackSupport = PlaybackSupport(
  backend: AudioBackendKind.justAudio,
  formats: [
    PlayableFormat('mp4', 'aac'),
    PlayableFormat('webm', 'opus'),
    PlayableFormat('mp3', 'mp3'),
    PlayableFormat('flac', 'flac'),
    PlayableFormat('wav', 'pcm_s16le'),
  ],
);
