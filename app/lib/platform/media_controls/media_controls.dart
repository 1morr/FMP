import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 平台提供的系統媒體控制（通知、鎖定畫面、媒體鍵；ADR 0018 §決定 8、
/// design §8.1）。
///
/// 轉接器只做兩件事：把 [NowPlaying] 推給系統，把系統按鍵變成 [commands]。
/// 推什麼、何時推由 `NowPlayingPublisher` 決定；按鍵做什麼由
/// `PlaybackController` 決定。實作只有 Android（`media_controls_android.dart`），
/// 由 `platform.dart` 組裝。
abstract interface class SystemMediaControls {
  /// 把目前的播放內容推給系統。呼叫端保證依序、不重疊（等上一次完成才推下
  /// 一次）。
  Future<void> publish(NowPlaying nowPlaying);

  /// 系統按鍵（通知按鈕、鎖定畫面、耳機與藍牙的媒體鍵）。
  Stream<MediaCommand> get commands;

  Future<void> dispose();
}

/// 平台宣告的系統媒體控制能力（`PlatformCapabilities.mediaControls`）。
@immutable
final class MediaControlsSupport {
  const MediaControlsSupport({required this.supportsSeek});

  /// 系統的進度條可以拖（Android 真；Windows 的 SMTC 不支援）。
  final bool supportsSeek;
}

/// 通知上的按鈕。播放與暫停是同一個位置，依 [NowPlaying.playing] 擇一出現。
enum MediaControl { previous, play, pause, next }

/// 系統送來的指令。
sealed class MediaCommand {
  const MediaCommand();
}

final class MediaPlay extends MediaCommand {
  const MediaPlay();
}

final class MediaPause extends MediaCommand {
  const MediaPause();
}

final class MediaPrevious extends MediaCommand {
  const MediaPrevious();
}

final class MediaNext extends MediaCommand {
  const MediaNext();
}

final class MediaSeek extends MediaCommand {
  const MediaSeek(this.position);

  final Duration position;
}

final class MediaStop extends MediaCommand {
  const MediaStop();
}

/// 系統看到的播放階段。[idle] 時系統不顯示通知、不佔前景。
enum MediaPhase { idle, loading, buffering, ready }

/// 推給系統的一份播放內容（不可變）。
@immutable
final class NowPlaying {
  const NowPlaying({
    required this.id,
    required this.title,
    this.uploader,
    this.duration,
    this.artworkFile,
    required this.phase,
    required this.playing,
    required this.position,
    this.speed = 1.0,
    this.controls = const [],
  });

  /// 沒有曲目：[MediaPhase.idle]，沒有按鈕。
  static const nothing = NowPlaying(
    id: '',
    title: '',
    phase: MediaPhase.idle,
    playing: false,
    position: Duration.zero,
  );

  /// 曲目鍵；換了首系統才當作新的媒體項目。
  final String id;
  final String title;
  final String? uploader;
  final Duration? duration;

  /// 封面的本機檔（已經過統一快取庫）；拿不到時為 `null`。
  final Uri? artworkFile;
  final MediaPhase phase;

  /// 是否在播：系統的播放鍵據此顯示成播放或暫停。
  final bool playing;

  /// 這次推送當下的位置；系統依 [speed] 自己往後推算。
  final Duration position;
  final double speed;
  final List<MediaControl> controls;

  bool get hasTrack => id.isNotEmpty;

  NowPlaying copyWith({Duration? position, Uri? artworkFile}) => NowPlaying(
    id: id,
    title: title,
    uploader: uploader,
    duration: duration,
    artworkFile: artworkFile ?? this.artworkFile,
    phase: phase,
    playing: playing,
    position: position ?? this.position,
    speed: speed,
    controls: controls,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NowPlaying &&
          other.id == id &&
          other.title == title &&
          other.uploader == uploader &&
          other.duration == duration &&
          other.artworkFile == artworkFile &&
          other.phase == phase &&
          other.playing == playing &&
          other.position == position &&
          other.speed == speed &&
          listEquals(other.controls, controls);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    uploader,
    duration,
    artworkFile,
    phase,
    playing,
    position,
    speed,
    Object.hashAll(controls),
  );
}

/// 平台的系統媒體控制實作；沒有這個能力（或初始化失敗）時為 `null`。`main()` 以
/// `AppPlatform.mediaControls` override；沒 override 就讀會拋錯。
final systemMediaControlsProvider = Provider<SystemMediaControls?>(
  (ref) => throw UnimplementedError(
    'systemMediaControlsProvider is overridden by main() with the platform '
    'implementation',
  ),
);
