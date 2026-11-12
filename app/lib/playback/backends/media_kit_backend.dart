import 'dart:async';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/playback/audio_backend.dart';
import 'package:fmp/playback/backends/backend_states.dart';
import 'package:media_kit/media_kit.dart' as mk;

/// Windows 的音訊後端（brief §6、事實 K1）：media_kit（libmpv）。header 由
/// `Media.httpHeaders` 轉成 mpv 的 `http-header-fields`（事實 K4）。
///
/// media_kit 的 `open()` 開不了也不會丟錯，錯誤只出現在 mpv 的 log
/// （事實 W4），所以 [load] 等到長度出現、出錯或逾時才回來。
class MediaKitBackend implements AudioBackend {
  MediaKitBackend({this.loadTimeout = const Duration(seconds: 20)}) {
    mk.MediaKit.ensureInitialized();
    _player = mk.Player();
    final stream = _player.stream;
    _subscriptions = [
      // 事實 K4：先看 buffering 再看 playing。
      stream.buffering.listen((buffering) => _states.update(_withStatus)),
      stream.playing.listen(
        (playing) =>
            _states.update((s) => _withStatus(s.copyWith(playing: playing))),
      ),
      stream.completed.listen((_) => _states.update(_withStatus)),
      stream.position.listen((p) {
        // 開好之前報的可能還是上一條的位置。
        if (_opened) _states.update((s) => s.copyWith(position: p));
      }),
      stream.duration.listen((d) {
        if (_loaded case final loaded? when d > Duration.zero) {
          if (!loaded.isCompleted) loaded.complete(true);
        }
        if (_loaded == null) {
          _states.update((s) => s.copyWith(duration: () => d));
        }
      }),
      stream.log.listen((log) {
        final category = classifyMpvLog(log.prefix, log.level, log.text);
        if (category == null) return;
        final error = AudioBackendError(category, '${log.prefix}: ${log.text}');
        if (_loaded case final loaded? when !loaded.isCompleted) {
          loaded.completeError(error);
        } else {
          _states.fail(error);
        }
      }),
    ];
  }

  /// 開啟串流最多等多久；逾時就當成一直在緩衝（交給呼叫端的記錄）。
  final Duration loadTimeout;

  late final mk.Player _player;
  final _states = BackendStates();
  late final List<StreamSubscription<Object?>> _subscriptions;

  /// 載入中時，長度出現就以 true 完成、被下一次載入取代就以 false 完成、
  /// mpv 報錯就失敗。
  Completer<bool>? _loaded;

  /// 每次 [load] 加一；載入完時不是自己的就表示被取代了。
  int _generation = 0;

  /// 載入完成之後才把 mpv 的狀態當真；之前 mpv 報的是上一條或還沒開好。
  bool _opened = false;

  @override
  AudioBackendState get state => _states.current;

  @override
  Stream<AudioBackendState> get states => _states.stream;

  AudioBackendState _withStatus(AudioBackendState s) {
    if (!_opened) return s;
    final mpv = _player.state;
    return s.copyWith(
      status: mpv.completed
          ? AudioBackendStatus.completed
          : mpv.buffering
          ? AudioBackendStatus.buffering
          : AudioBackendStatus.ready,
    );
  }

  @override
  Future<void> load(AudioStream stream) async {
    final generation = ++_generation;
    if (_loaded case final previous? when !previous.isCompleted) {
      previous.complete(false);
    }
    _opened = false;
    _states.reset();
    final loaded = _loaded = Completer<bool>();
    // 先接上等待，mpv 在 open 期間就報錯時才不會成為沒人處理的錯誤。
    final waiting = loaded.future.timeout(loadTimeout, onTimeout: () => true)
      ..ignore();
    try {
      await _player.open(
        mk.Media(stream.url.toString(), httpHeaders: stream.headers),
        play: false,
      );
      if (!await waiting || generation != _generation) return;
    } on AudioBackendError catch (error) {
      if (generation != _generation) return;
      _states.fail(error);
      rethrow;
    } finally {
      if (identical(_loaded, loaded)) _loaded = null;
    }
    _opened = true;
    final duration = _player.state.duration;
    _states.update((s) {
      final next = _withStatus(
        s.copyWith(duration: () => duration, position: _player.state.position),
      );
      // 逾時時長度還是 0：當成一直在緩衝（事實 W4），交給呼叫端記錄。
      return duration == Duration.zero
          ? next.copyWith(status: AudioBackendStatus.buffering)
          : next;
    });
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> dispose() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    // 事實 W5：同時 dispose 多個 player 會原生崩潰；App 只有這一個。
    await _player.dispose();
    await _states.close();
  }
}

/// mpv 的一筆 log 是不是播放失敗，是的話轉成錯誤分類；不是就回 null。
///
/// 照 media_kit 1.2.6 轉發到 `stream.error` 的那幾種（`real.dart`），再加上
/// 它不轉發的 `ao`（音訊輸出裝置失敗，事實 W4）：
/// - `ffmpeg` 的 `tcp:`、`stream`、`file`：開不了網址，算網路。
/// - `ao`、`ad`、`vd`：輸出或解碼失敗，算不支援。
/// - `cplayer` 等其他的：不知道是什麼，算解析失敗。
AppError? classifyMpvLog(String prefix, String level, String text) {
  if (level != 'error' && level != 'fatal') return null;
  return switch (prefix) {
    'ffmpeg' when text.startsWith('tcp:') => const NetworkError(),
    'stream' || 'file' => const NetworkError(),
    'ao' || 'ad' || 'vd' => const Unsupported(),
    'cplayer' => const ParseFailure(),
    _ => null,
  };
}
