import 'dart:async';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/playback/audio_backend.dart';
import 'package:fmp/playback/backends/backend_states.dart';
import 'package:fmp/playback/backends/hls/hls_packager.dart';
import 'package:just_audio/just_audio.dart' as ja;

/// Android、iOS、macOS 的音訊後端（brief〈播放〉、事實 K1）。
///
/// header 由原生播放器直接帶（ExoPlayer 的 default request properties、
/// AVPlayer 的 `AVURLAssetHTTPHeaderFieldsKey`），不用 just_audio 預設的
/// 本機 proxy：proxy 在 Dart 裡另開 HTTP 連線，繞過宿主的網路層，在 Android
/// 與 Apple 平台還要放行明文 HTTP（brief 事實 K25）。
///
/// 給了 [hls] 時（Apple 平台，`platform/audio_backend.dart` 決定），有
/// [AudioStream.segmentBase] 的串流改播 [HlsPackager] 產生的清單：AVPlayer
/// 直接播單檔 fragmented MP4 時，CDN 中途斷線會讓它把長度截短、提早播完
/// （ADR 0040）。包不了就照舊直接播網址，並呼叫 [onHlsUnavailable]。
class JustAudioBackend implements AudioBackend {
  JustAudioBackend({this.hls, this.onHlsUnavailable}) {
    _subscriptions = [
      _player.playerStateStream.listen(
        (s) => _states.update(
          (state) => state.copyWith(
            status: _status(s.processingState),
            playing: s.playing,
          ),
        ),
      ),
      _player.positionStream.listen((p) {
        // 載入中報的可能還是上一條的位置。
        if (_pendingLoads == 0) {
          _states.update((state) => state.copyWith(position: p));
        }
      }),
      _player.durationStream.listen(
        (d) => _states.update((state) => state.copyWith(duration: () => d)),
      ),
      _player.errorStream.listen((e) {
        // 載入中的錯誤由 setAudioSource 丟出，交給 load 處理。
        if (_pendingLoads == 0) _states.fail(_error(e));
      }),
    ];
  }

  final HlsPackager? hls;

  /// HLS 包裝失敗、改直接播網址時呼叫；介面規定後端不寫 log，由組裝的
  /// 平台層記。
  final void Function(HlsUnavailable reason)? onHlsUnavailable;

  final _player = ja.AudioPlayer(useProxyForRequestHeaders: false);
  final _states = BackendStates();
  late final List<StreamSubscription<Object?>> _subscriptions;

  /// 每次 [load] 加一；載入完時不是自己的就表示被取代了。
  int _generation = 0;

  /// 還沒回來的 [load] 數。
  int _pendingLoads = 0;

  @override
  AudioBackendState get state => _states.current;

  @override
  Stream<AudioBackendState> get states => _states.stream;

  @override
  Future<void> load(AudioStream stream) async {
    final generation = ++_generation;
    _states.reset();
    _pendingLoads++;
    try {
      final url = await _playableUrl(stream);
      if (generation != _generation) return;
      final duration = await _player.setAudioSource(
        ja.AudioSource.uri(
          url,
          headers: stream.headers.isEmpty ? null : stream.headers,
        ),
      );
      if (generation != _generation) return;
      _states.update((s) => s.copyWith(duration: () => duration));
    } on ja.PlayerException catch (e) {
      if (generation != _generation) return;
      final error = _error(e);
      _states.fail(error);
      throw error;
    } on ja.PlayerInterruptedException {
      // 被下一次載入取代（介面的約定：直接回來）。
      return;
    } finally {
      _pendingLoads--;
    }
  }

  /// 有 [hls] 與索引位置時是本機的 HLS 清單，否則是串流的網址。
  Future<Uri> _playableUrl(AudioStream stream) async {
    final packager = hls;
    if (packager == null || stream.segmentBase == null) return stream.url;
    try {
      return await packager.playlistFor(stream);
    } on HlsUnavailable catch (reason) {
      onHlsUnavailable?.call(reason);
      return stream.url;
    }
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> play() async {
    // just_audio 的 play() 要到暫停或播完才完成，這裡不等（事實 K25）。
    // 播放中的錯誤另從 errorStream 來，這裡只接住免得成為沒人處理的錯誤。
    unawaited(_player.play().catchError((Object _) {}));
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> dispose() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await _player.dispose();
    await hls?.close();
    await _states.close();
  }

  static AudioBackendStatus _status(ja.ProcessingState s) => switch (s) {
    ja.ProcessingState.idle => AudioBackendStatus.idle,
    ja.ProcessingState.loading => AudioBackendStatus.loading,
    ja.ProcessingState.buffering => AudioBackendStatus.buffering,
    ja.ProcessingState.ready => AudioBackendStatus.ready,
    ja.ProcessingState.completed => AudioBackendStatus.completed,
  };

  static AudioBackendError _error(ja.PlayerException e) => AudioBackendError(
    classifyJustAudioError(e.code),
    'code ${e.code}: ${e.message}',
  );
}

/// just_audio 的 `PlayerException.code` 轉成錯誤分類。Android 是
/// `ExoPlaybackException.type`（0 起的小整數），Apple 平台是 `NSError.code`
/// （負數），兩邊的範圍不重疊，所以不必知道是哪個平台。
///
/// - ExoPlayer 把幾乎所有網路問題都壓成 type 0（source，事實 K3），remote（3）
///   也算網路；renderer（1）是解不了碼。
/// - `NSURLErrorDomain` 的代碼在 -1000 到 -3999 之間。
/// - AVFoundation 的 -11828（`AVErrorFileFormatNotRecognized`，事實 M5 的
///   WebM／Opus）、-11821（`AVErrorDecodeFailed`）是格式不支援。
/// - 其他的不知道是什麼，當成解析失敗。
AppError classifyJustAudioError(int code) => switch (code) {
  0 || 3 => const NetworkError(),
  1 || -11828 || -11821 => const Unsupported(),
  <= -1000 && >= -3999 => const NetworkError(),
  _ => const ParseFailure(),
};
