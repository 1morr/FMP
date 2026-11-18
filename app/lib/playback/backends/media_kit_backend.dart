import 'dart:async';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/playback/audio_backend.dart';
import 'package:fmp/playback/backends/backend_items.dart';
import 'package:fmp/playback/backends/backend_states.dart';
import 'package:media_kit/media_kit.dart' as mk;

/// Windows 的音訊後端（brief〈播放〉、事實 K1）：media_kit（libmpv）。header 由
/// `Media.httpHeaders` 轉成 mpv 的 `http-header-fields`（事實 K4）。
///
/// media_kit 的 `open()` 開不了也不會丟錯，錯誤只出現在 mpv 的 log
/// （事實 W4），所以 [load] 等到長度出現、出錯或逾時才回來。
///
/// 建好時設 [mpvOptions]（事實 K4）；設完呼叫 [onMpvOptions]（失敗時帶著
/// 錯誤，照預設設定繼續播）。介面規定後端不寫 log，由組裝的平台層記。
///
/// 預載的那條是 mpv playlist 的第二項（`loadfile append`）：mpv 在目前這條
/// 整個讀完後先開它（`prefetch-playlist`，事實 K33），目前這條播完就自己
/// 接過去（media_kit 的 `keep-open=yes` 只在最後一項停）；[load] 它時跳
/// 過去、不重開。換過去之後把播過的那項移掉，清單最多兩項。
class MediaKitBackend implements AudioBackend {
  MediaKitBackend({
    this.loadTimeout = const Duration(seconds: 20),
    this.onMpvOptions,
  }) {
    mk.MediaKit.ensureInitialized();
    _player = mk.Player();
    _options = _setMpvOptions();
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
      stream.playlist.listen((playlist) => _onIndex(playlist.index)),
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

  /// 開啟串流最多等多久；逾時就當成一直在緩衝（交給呼叫端的看門狗）。
  final Duration loadTimeout;

  final void Function(Object? error)? onMpvOptions;

  /// 只播音訊時的 mpv 設定（事實 K4）：`vid=no` 不解碼影片軌（B 站的串流
  /// 只有音訊，YouTube 退到 muxed 時省 200–400 MB），`prefetch-playlist=yes`
  /// 讓 mpv playlist 的下一項先開（預載下一首用）。
  static const mpvOptions = {'vid': 'no', 'prefetch-playlist': 'yes'};

  late final Future<void> _options;

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

  final _items = BackendItems();

  /// 改清單（預載、換到預載的那項）一次一個，照呼叫的順序。
  final _edits = SerialEdits();

  @override
  AudioBackendState get state => _states.current;

  @override
  Stream<AudioBackendState> get states => _states.stream;

  Future<void> _setMpvOptions() async {
    try {
      final native = _player.platform! as mk.NativePlayer;
      for (final MapEntry(:key, :value) in mpvOptions.entries) {
        await native.setProperty(key, value);
      }
      onMpvOptions?.call(null);
    } catch (error) {
      onMpvOptions?.call(error);
    }
  }

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
    await _options;
    if (generation != _generation) return;
    final plan = _items.planLoad(stream);
    if (plan is AlreadyCurrent) return;
    if (_loaded case final previous? when !previous.isCompleted) {
      previous.complete(false);
    }
    _opened = false;
    _states.reset(stream);
    final loaded = _loaded = Completer<bool>();
    // 先接上等待，mpv 在 open 期間就報錯時才不會成為沒人處理的錯誤。
    final waiting = loaded.future.timeout(loadTimeout, onTimeout: () => true)
      ..ignore();
    try {
      if (plan case SwitchTo(:final index)) {
        await _edits.run(() async {
          if (generation != _generation) return;
          _items.moveTo(index);
          // media_kit 的 jump 會先 play()（事實 K33）；呼叫端換到預載的那條
          // 都是要接著播的。
          await _player.jump(index);
          await _dropPlayed();
        });
      } else {
        _items.clear();
        await _player.open(
          mk.Media(stream.url.toString(), httpHeaders: stream.headers),
          play: false,
        );
      }
      if (!await waiting || generation != _generation) return;
    } on AudioBackendError catch (error) {
      if (generation != _generation) return;
      _states.fail(error);
      rethrow;
    } finally {
      if (identical(_loaded, loaded)) _loaded = null;
    }
    if (plan is Reopen) _items.opened(stream);
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
  Future<void> preload(AudioStream? stream) => _edits.run(() async {
    final onTopOf = _items.current;
    if (onTopOf == null) return;
    final edit = _items.preload(stream);
    if (edit == null) return;
    for (final index in edit.remove) {
      await _player.remove(index);
    }
    final next = edit.append;
    if (next == null) return;
    await _player.add(mk.Media(next.url.toString(), httpHeaders: next.headers));
    if (!_items.appended(next, onTopOf: onTopOf)) {
      // 加的期間清單被新的載入換掉了：open 已經換掉整個清單，加的那項若
      // 接在後面就移掉。
      final medias = _player.state.playlist.medias;
      if (medias.length > 1 && medias.last.uri == next.url.toString()) {
        await _player.remove(medias.length - 1);
      }
    }
  });

  /// mpv 的位置變了：是自己接到預載的那項，就報播完並從它的開頭報起，再
  /// 移掉播過的。載入中（[_loaded]）的位置變化歸 [load]。
  void _onIndex(int index) {
    if (_loaded != null) return;
    final next = _items.moveTo(index);
    if (next == null) return;
    _states.advancedTo(next);
    unawaited(_edits.run(_dropPlayed));
  }

  Future<void> _dropPlayed() async {
    for (final index in _items.dropPlayed()) {
      await _player.remove(index);
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

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
/// - `cplayer`：只有讓這首播不下去的才算（事實 W13）：認不得格式、開不了
///   音訊裝置、沒有可播的軌是不支援，其他 `fatal` 是解析失敗；其餘 error
///   （例如「不能 seek」）聲音照常，不算。
AppError? classifyMpvLog(String prefix, String level, String text) {
  if (level != 'error' && level != 'fatal') return null;
  return switch (prefix) {
    'ffmpeg' when text.startsWith('tcp:') => const NetworkError(),
    'stream' || 'file' => const NetworkError(),
    'ao' || 'ad' || 'vd' => const Unsupported(),
    'cplayer' when _fatalPlayerErrors.any(text.startsWith) =>
      const Unsupported(),
    'cplayer' when level == 'fatal' => const ParseFailure(),
    _ => null,
  };
}

/// mpv 0.36 的 `cplayer` 在 error 級寫、但這首就播不下去的訊息開頭（事實
/// W13；`No video or audio streams selected` 是 fatal 級）。
const _fatalPlayerErrors = [
  'Failed to recognize file format',
  'Could not open/initialize audio device',
  'No video or audio streams selected',
];
