import 'dart:async';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/playback/audio_backend.dart';
import 'package:fmp/playback/backends/backend_playlist.dart';
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
///
/// 預載的那條是 just_audio 清單的第二項：原生播放器自己決定什麼時候緩衝它
/// （事實 K31），目前這條播完就自己接過去；[load] 它時用 `seek(index:)`
/// 跳過去、不重開（事實 I4）。換過去之後把播過的那項移掉，清單最多兩項。
class JustAudioBackend implements AudioBackend {
  JustAudioBackend({this.hls, this.onHlsUnavailable}) {
    _subscriptions = [
      _player.playerStateStream.listen((s) {
        _playerState = s;
        _states.update(_withPlayerState);
      }),
      _player.positionStream.listen((p) {
        // 載入中報的可能還是上一條的位置。
        if (_pendingLoads == 0) {
          _states.update((state) => state.copyWith(position: p));
        }
      }),
      _player.durationStream.listen(
        (d) => _states.update(
          (state) => _withPlayerState(state.copyWith(duration: () => d)),
        ),
      ),
      _player.currentIndexStream.listen(_onIndex),
      _player.errorStream.listen((e) {
        // 載入中的錯誤由 setAudioSource 丟出，交給 load 處理。
        if (_pendingLoads == 0) _states.fail(_error(e));
      }),
    ];
  }

  /// 由這個後端擁有：[dispose] 時一起關掉。
  final HlsPackager? hls;

  /// HLS 包裝失敗、改直接播網址時呼叫；介面規定後端不寫 log，由組裝的
  /// 平台層記。
  final void Function(HlsUnavailable failure)? onHlsUnavailable;

  final _player = ja.AudioPlayer(useProxyForRequestHeaders: false);
  final _states = BackendStates();
  late final List<StreamSubscription<Object?>> _subscriptions;

  /// 每次 [load] 加一；載入完時不是自己的就表示被取代了。
  int _generation = 0;

  /// 還沒回來的 [load] 數。
  int _pendingLoads = 0;

  final _playlist = BackendPlaylist();

  /// 改清單（預載、換到預載的那項）一次一個，照呼叫的順序。
  Future<void> _edits = Future.value();

  ja.PlayerState? _playerState;

  /// 目前這條是從預載換過來的：AVPlayer 預載失敗時會吞掉錯誤，換過去後把
  /// 它報成 ready、長度 0（事實 I4），所以長度還不知道或是 0 時算緩衝中。
  bool _fromPreload = false;

  @override
  AudioBackendState get state => _states.current;

  @override
  Stream<AudioBackendState> get states => _states.stream;

  @override
  Future<void> load(AudioStream stream) async {
    final generation = ++_generation;
    switch (_playlist.planLoad(stream)) {
      case AlreadyCurrent():
        return;
      case SwitchTo(:final index):
        return _switchTo(stream, index, generation);
      case Reopen():
        break;
    }
    // 不等改到一半的清單：卡住的預載不能擋住新的載入（事實 I4）。
    _playlist.clear();
    _fromPreload = false;
    _states.reset(stream);
    _pendingLoads++;
    try {
      final url = await _playableUrl(stream);
      if (generation != _generation) return;
      final duration = await _player.setAudioSource(_source(url, stream));
      if (generation != _generation) return;
      _playlist.opened(stream);
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

  /// 換到預載的那項（清單的第 [index] 項）：跳過去、移掉播過的，停在開頭。
  Future<void> _switchTo(AudioStream stream, int index, int generation) async {
    // 不算進 [_pendingLoads]：換過去那一項開不了的錯誤從 errorStream 來
    // （AVPlayer 輪到它才報，事實 I4），要照常變成失敗。
    _states.reset(stream);
    try {
      await _edit(() async {
        if (generation != _generation) return;
        _playlist.moved(index);
        _fromPreload = true;
        await _player.seek(Duration.zero, index: index);
        await _dropPlayed();
      });
    } on ja.PlayerException catch (e) {
      if (generation != _generation) return;
      final error = _error(e);
      _states.fail(error);
      throw error;
    }
    if (generation != _generation) return;
    _states.update(
      (s) => _withPlayerState(
        s.copyWith(
          duration: () => _player.duration,
          position: _player.position,
        ),
      ),
    );
  }

  @override
  Future<void> preload(AudioStream? stream) => _edit(() async {
    final edit = _playlist.preload(stream);
    if (edit == null) return;
    for (final index in edit.remove) {
      await _player.removeAudioSourceAt(index);
    }
    final next = edit.append;
    if (next == null) return;
    // 包 HLS 要抓一次索引，預載時就先做好。
    final url = await _playableUrl(next);
    // 等的期間整個清單被新的載入換掉了。
    if (!identical(_playlist.preloaded, next)) return;
    await _player.addAudioSource(_source(url, next));
  });

  /// 原生的位置變了：是自己接到預載的那項，就報播完並從它的開頭報起，
  /// 再移掉播過的。
  void _onIndex(int? index) {
    if (index == null) return;
    final next = _playlist.moved(index);
    if (next == null) return;
    _fromPreload = true;
    _states
      ..advancedTo(next)
      // 這一項的長度和上一項一樣時 durationStream 不會再發，直接讀。
      ..update(
        (s) => _withPlayerState(s.copyWith(duration: () => _player.duration)),
      );
    unawaited(_edit(_dropPlayed));
  }

  Future<void> _dropPlayed() async {
    for (final index in _playlist.dropPlayed()) {
      await _player.removeAudioSourceAt(index);
    }
  }

  /// 排在前一個清單修改之後做 [change]；失敗不影響之後的修改。
  Future<void> _edit(Future<void> Function() change) {
    final done = _edits.then((_) => change());
    _edits = done.then<void>((_) {}, onError: (Object _) {});
    return done;
  }

  ja.AudioSource _source(Uri url, AudioStream stream) => ja.AudioSource.uri(
    url,
    headers: stream.headers.isEmpty ? null : stream.headers,
  );

  /// 套上原生最近一次的播放狀態。從預載換過來的那條長度還不知道或是 0
  /// 時，ready 算緩衝中（事實 I4）。
  AudioBackendState _withPlayerState(AudioBackendState state) {
    final player = _playerState;
    if (player == null) return state;
    var status = _status(player.processingState);
    if (_fromPreload &&
        status == AudioBackendStatus.ready &&
        (state.duration ?? Duration.zero) <= Duration.zero) {
      status = AudioBackendStatus.buffering;
    }
    return state.copyWith(status: status, playing: player.playing);
  }

  /// 有 [hls] 與索引位置時是本機的 HLS 清單，否則是串流的網址。
  Future<Uri> _playableUrl(AudioStream stream) async {
    final packager = hls;
    if (packager == null || stream.segmentBase == null) return stream.url;
    try {
      return await packager.playlistFor(stream);
    } on HlsUnavailable catch (failure) {
      onHlsUnavailable?.call(failure);
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
