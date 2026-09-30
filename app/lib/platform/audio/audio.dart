import 'package:flutter/foundation.dart';

/// 播放後端的兩個實作（ADR 0018 §決定 3）。平台層只宣告用哪一個，實作在
/// `lib/playback/backends/`（`just_audio`、`media_kit` 只准在那裡 import）。
enum AudioBackendKind {
  /// `just_audio`：Android（之後 iOS、macOS）。
  justAudio,

  /// `media_kit`（libmpv）：Windows（之後 Linux）。
  mediaKit,
}

/// 平台能播的一種格式（ADR 0009 §決定 2、ADR 0018 §決定 6）。值是小寫的慣用
/// 名稱，與插件 DTO 的 `StreamFormat` 同一套（容器 `mp4`、`webm`，編碼
/// `aac`、`opus`）；播放模組把它轉成 `StreamFormat` 交給插件。
@immutable
final class PlayableFormat {
  const PlayableFormat(this.container, this.codec);

  final String container;
  final String codec;

  @override
  bool operator ==(Object other) =>
      other is PlayableFormat &&
      other.container == container &&
      other.codec == codec;

  @override
  int get hashCode => Object.hash(container, codec);

  @override
  String toString() => '$container/$codec';
}

/// 平台的播放能力：用哪個後端、能播哪些格式。
@immutable
final class PlaybackSupport {
  const PlaybackSupport({required this.backend, required this.formats});

  final AudioBackendKind backend;

  /// 能播的格式，依偏好排序；插件依它挑候選串流。
  final List<PlayableFormat> formats;
}
