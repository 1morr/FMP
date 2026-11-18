import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/audio_backend.dart';
import 'package:fmp/playback/queue_saver.dart';
import 'package:fmp/plugins/plugins.dart';

/// App 的音訊後端。`main` 用 `platform/audio_backend.dart` 依平台建好再
/// override 進來；測試換成假的。
final audioBackendProvider = Provider<AudioBackend>(
  (ref) => throw StateError('audioBackendProvider is overridden in main()'),
);

/// 看門狗的兩個門檻（事實 W4：長度為零的串流不報錯、一直 buffering）。
/// 超過就當成串流壞掉，和後端報錯走同一條路（重新解析一次，再不行就失敗）。
class StallTimeouts {
  const StallTimeouts({required this.starting, required this.playing});

  /// 開始載入到出聲：後端開始載入起，還沒出過聲、一直沒有聲音多久算卡住。
  final Duration starting;

  /// 播放中途：出過聲之後，要播卻一直緩衝多久算卡住。
  final Duration playing;
}

/// 看門狗的門檻；數字照四平台量到的出聲時間（事實 F25）。
final stallTimeoutsProvider = Provider<StallTimeouts>(
  (ref) => const StallTimeouts(
    starting: Duration(seconds: 20),
    playing: Duration(seconds: 15),
  ),
);

/// 現在幾點；過期前重新解析看它。測試換成假的時鐘。
final playbackClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// 要用串流網址前（暫停後繼續、seek）離過期不到這麼久，就先重新解析
/// （architecture〈快取〉）。
const refreshBeforeExpiry = Duration(minutes: 2);

/// 正在播的曲目與它的播放狀態；還沒播過是 null。
final playbackProvider = NotifierProvider<Playback, PlaybackState?>(
  Playback.new,
);

enum PlaybackStatus {
  /// 插件正在解析串流。
  resolving,

  /// 音訊後端正在開啟串流。
  loading,

  /// 要播，但在等資料。
  buffering,
  playing,
  paused,

  /// 播到結尾。
  completed,

  /// 解析或播放失敗，原因在 [PlaybackState.error]。
  failed,
}

class PlaybackState {
  const PlaybackState({
    required this.track,
    required this.status,
    this.stream,
    this.position = Duration.zero,
    this.duration,
    this.error,
  });

  final Track track;
  final PlaybackStatus status;

  /// 解析到的串流；解析完之前是 null。
  final AudioStream? stream;

  final Duration position;

  /// 音訊後端為這一首回報的長度；這一首載入完成之前、或還不知道時是 null。
  /// 畫面用 [effectiveDuration]。
  final Duration? duration;

  /// [status] 是 [PlaybackStatus.failed] 時的錯誤分類；錯誤分類以外的例外
  /// （程式錯誤）是 null，細節在 log。
  final AppError? error;

  /// 畫面顯示的長度：後端回報的長度可信就用它（比插件給的整數秒準），否則用
  /// 曲目自己的時長。可信是大於 0、而且和曲目的時長差在 3 秒或 1%（取大的）
  /// 內；曲目沒有時長時，大於 0 就用。AVPlayer 遇到 CDN 中途斷線會把長度截短
  /// （事實 M14），還不知道時報 0（事實 I4）。
  Duration? get effectiveDuration {
    final reported = duration;
    final own = track.duration;
    if (reported == null || reported <= Duration.zero) return own;
    if (own == null) return reported;
    return (reported - own).abs() <= _durationTolerance(own) ? reported : own;
  }

  /// 後端的長度和曲目時長最多差多少還算同一個：3 秒或 1%，取大的。
  static Duration _durationTolerance(Duration own) {
    final percent = own ~/ 100;
    const floor = Duration(seconds: 3);
    return percent > floor ? percent : floor;
  }

  /// 要播或正在播：播放鈕顯示暫停。
  bool get playing => switch (status) {
    PlaybackStatus.resolving ||
    PlaybackStatus.loading ||
    PlaybackStatus.buffering ||
    PlaybackStatus.playing => true,
    PlaybackStatus.paused ||
    PlaybackStatus.completed ||
    PlaybackStatus.failed => false,
  };

  @override
  String toString() =>
      'PlaybackState(${track.ref.logId}, ${status.name}, '
      '$position / $duration, $error)';
}

/// 前景播放一首曲目：用提供它的插件解析串流、交給音訊後端播放，並把後端的
/// 狀態轉成 [PlaybackState]。錯誤轉成錯誤分類並寫 log。佇列、臨時播放與
/// 失敗後跳下一首在 `queue_controller.dart`。
///
/// 串流壞掉（後端開不了、播放中出錯、看門狗）時先重新解析一次、從原本的
/// 位置接著播，這一首再壞才報 [PlaybackStatus.failed]；插件解析本身失敗
/// 已經過網路層的重試，直接報。串流離過期不到 [refreshBeforeExpiry] 時，
/// 暫停後繼續與 seek 先重新解析（architecture〈快取〉）。
///
/// 預載下一首（brief〈播放〉）：佇列用 [preloadNext] 說下一首是哪首，這一首
/// 開始出聲後先解析它、交給後端排在後面（[AudioBackend.preload]）。播它時
/// 用預載的串流，不再解析；後端已經自己接過去時聲音不斷。預載的串流離過期
/// 不到 [refreshBeforeExpiry] 時不用它，等著的預載在那之前重新解析。
class Playback extends Notifier<PlaybackState?> {
  AudioBackend? _backendOrNull;
  StreamSubscription<AudioBackendState>? _subscription;
  int _generation = 0;

  /// 後端已經載入完成的那一次 [play]；之前後端報的長度可能是上一首的。
  int _loadedGeneration = -1;

  /// 正在開始播的那一次 [play]：叫後端播之前（載入、跳到開始位置）一律算
  /// 載入中，不報成停在開頭的暫停。
  int? _startingGeneration;

  /// 重啟後還原的那首要從哪裡開始。播它（播放鈕、Toast 的重試、佇列接回
  /// 它）都從這裡開始，直到真的開始播了（任何一首）才丟掉：第一次播失敗時
  /// 再按播放仍從這裡開始。
  ({Track track, Duration position})? _resumeFrom;

  /// 這一次 [play] 已經為壞掉的串流重新解析過；再壞就是失敗。重新解析後
  /// 順利播了 [_healthyAfter]，額度就還回來。
  bool _resolvedAgain = false;

  /// 播了這麼久沒出事，壞掉的串流又可以重新解析一次：長片播了一小時才
  /// 過期或斷線時還救得回來，播一下就壞的串流也不會一直重來。
  static const _healthyAfter = Duration(seconds: 30);

  /// 這一次開始播（[_start]）從哪裡開始、要不要接著播。
  Duration _startedFrom = Duration.zero;
  bool _startAutoplay = true;

  /// 這一次開始播（[_start]）已經出過聲；看門狗用哪個門檻看它。
  bool _sounded = false;
  Timer? _stallTimer;
  bool _zeroDurationLogged = false;

  /// 佇列說的下一首（[preloadNext]）；沒有是 null。
  Track? _wantedNext;

  /// 解析好的下一首；播它時用這條串流（[_takePreload]），被新的取代、或
  /// 播了就丟掉。
  ({Track track, AudioStream stream})? _preload;

  /// [_preload] 交給後端時是第幾代：這一代重開過（換了一首）就要再交一次。
  int? _preloadHandedInGeneration;

  /// 正在解析的下一首與它的序號；序號換了，解析完的結果就不要了。
  Track? _preloading;
  int _preloadToken = 0;

  /// 等著的預載在過期前 [refreshBeforeExpiry] 重新解析。
  Timer? _preloadRefresh;

  /// [_syncPreload] 已經排進 microtask。
  bool _preloadSyncScheduled = false;

  Log get _log => ref.read(logProvider);

  @override
  PlaybackState? build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _stallTimer?.cancel();
      _preloadRefresh?.cancel();
    });
    // 重啟後停在上次的那首與位置、不自動播（brief〈播放〉）：後端還沒載入，
    // 按播放才解析並從這個位置開始。
    final saved = ref.read(savedQueueProvider);
    if (saved?.queue.current case final entry?) {
      _resumeFrom = (track: entry.track, position: saved!.position);
      return PlaybackState(
        track: entry.track,
        status: PlaybackStatus.paused,
        position: saved.position,
      );
    }
    return null;
  }

  /// 後端載入的是現在這一首；重啟後還原的那首還沒載入。
  bool get _loaded => _loadedGeneration == _generation;

  /// 第一次播放時才建音訊後端：沒播過就不開原生播放器。
  AudioBackend get _backend {
    if (_backendOrNull case final backend?) return backend;
    final backend = ref.read(audioBackendProvider);
    _subscription = backend.states.listen(_onBackendState);
    return _backendOrNull = backend;
  }

  /// 播放 [track]，取代正在播的；給了 [from] 就從那裡開始（載入後先跳過去
  /// 再播，不會先從開頭出聲），沒給而它是重啟後還原的那首就從保存的位置
  /// 開始（[_resumeFrom]）。連點時只有最後一首會播。
  Future<void> play(Track track, {Duration from = Duration.zero}) {
    if (from == Duration.zero && _resumeFrom?.track == track) {
      from = _resumeFrom!.position;
    }
    _resolvedAgain = false;
    return _start(
      track,
      from: from,
      autoplay: true,
      preloaded: _takePreload(track),
    );
  }

  /// 解析 [track] 的串流（給了 [preloaded] 就用它、不解析）、交給後端開、
  /// 跳到 [from]；[autoplay] 時接著播，否則停在那裡暫停。每次呼叫是新的
  /// 一代，舊的一代做到一半就放手。
  Future<void> _start(
    Track track, {
    required Duration from,
    required bool autoplay,
    AudioStream? preloaded,
  }) async {
    final generation = ++_generation;
    _startingGeneration = generation;
    _startedFrom = from;
    _startAutoplay = autoplay;
    _sounded = false;
    _cancelWatchdog();
    _zeroDurationLogged = false;

    final AudioStream stream;
    if (preloaded != null) {
      stream = preloaded;
      _log.info('Playing the preloaded stream: ${track.ref.logId}');
    } else {
      state = PlaybackState(
        track: track,
        status: PlaybackStatus.resolving,
        position: from,
      );
      try {
        stream = await _resolve(track);
      } catch (error, stackTrace) {
        if (!_isCurrent(generation)) return;
        _fail(track, null, error, stackTrace, 'Resolving a stream failed');
        return;
      }
      if (!_isCurrent(generation)) return;
    }
    state = PlaybackState(
      track: track,
      stream: stream,
      status: PlaybackStatus.loading,
      position: from,
    );

    /// 這一步失敗了：串流壞掉就重新解析一次（等它做完），否則報失敗。
    Future<void> retryOrFail(
      Object error,
      StackTrace stackTrace,
      String message,
    ) => _retryOrFail(
      generation,
      track,
      stream,
      error,
      stackTrace,
      message,
      at: from,
      autoplay: autoplay,
    );

    try {
      await _backend.load(stream);
    } catch (error, stackTrace) {
      return retryOrFail(error, stackTrace, 'Loading a stream failed');
    }
    if (!_isCurrent(generation)) return;
    _loadedGeneration = generation;
    _onBackendState(_backend.state);
    // 載入回來之前就出聲的（just_audio 的 playing 跨來源保留），那時還不能
    // 預載，現在補。
    if (_sounded) _syncPreload();
    if (from > Duration.zero) {
      try {
        await _backend.seek(from);
      } catch (error, stackTrace) {
        return retryOrFail(error, stackTrace, 'Seeking failed');
      }
      if (!_isCurrent(generation)) return;
    }
    // 開始播之前後端報的失敗不經 [_onBackendState]（載入失敗時它也會丟錯），
    // 在這裡接。
    if (_backend.state case AudioBackendState(
      status: AudioBackendStatus.failed,
      :final error?,
    )) {
      return retryOrFail(error, StackTrace.current, 'Loading a stream failed');
    }
    _startingGeneration = null;
    if (!autoplay) {
      _onBackendState(_backend.state);
      return;
    }
    try {
      await _backend.play();
    } catch (error, stackTrace) {
      return retryOrFail(error, stackTrace, 'Starting playback failed');
    }
    if (_isCurrent(generation)) _resumeFrom = null;
  }

  /// 用提供 [track] 的插件解析它的串流。
  Future<AudioStream> _resolve(Track track) async {
    final host = await ref.read(pluginHostProvider.future);
    final plugin = host.pluginFor(track.ref);
    if (plugin == null) throw const Unsupported();
    return plugin.resolveStream(track.ref);
  }

  /// 佇列的下一首換成 [track]（null 是沒有下一首）。這一首出聲後才解析
  /// 它、交給後端；換了就換掉預載。同一輪事件裡接著播的那首（例如按下一首
  /// 時佇列先換再播）照舊用原本的預載：真的改動排到 microtask 才做。
  void preloadNext(Track? track) {
    if (track == _wantedNext) return;
    _wantedNext = track;
    if (_preloadSyncScheduled) return;
    _preloadSyncScheduled = true;
    scheduleMicrotask(() {
      _preloadSyncScheduled = false;
      if (ref.mounted) _syncPreload();
    });
  }

  /// 這一首已經出聲時，讓後端排著的預載對上佇列的下一首：要的已經解析好
  /// 而且沒快過期就交給後端，否則解析它；沒有下一首就清掉。
  void _syncPreload() {
    if (!_sounded || !_loaded) return;
    final wanted = _wantedNext;
    if (wanted == null) {
      if (_preloadHandedInGeneration == _generation) {
        _preloadHandedInGeneration = null;
        _handToBackend(null);
      }
      return;
    }
    if (_preload case final p?
        when p.track == wanted && !_expiresSoon(p.stream)) {
      if (_preloadHandedInGeneration != _generation) {
        _preloadHandedInGeneration = _generation;
        _log.info('Preloaded the next track: ${wanted.ref.logId}');
        _handToBackend(p.stream);
      }
      return;
    }
    if (_preloading == wanted) return;
    if (_preloadHandedInGeneration == _generation) {
      // 後端排著的是別首（或快過期的）：先撤掉，解析期間這一首播完也不會
      // 接到它；解析失敗就不預載。
      _preloadHandedInGeneration = null;
      _handToBackend(null);
    }
    unawaited(_resolvePreload(wanted));
  }

  Future<void> _resolvePreload(Track track) async {
    final token = ++_preloadToken;
    _preloading = track;
    final AudioStream stream;
    try {
      stream = await _resolve(track);
    } catch (error) {
      if (token != _preloadToken || !ref.mounted) return;
      _preloading = null;
      // 插件宿主已經記過它的錯誤；播到它時照常解析。
      _log.warning('Preloading the next track failed: ${track.ref.logId}');
      return;
    }
    if (token != _preloadToken || !ref.mounted) return;
    _preloading = null;
    _preload = (track: track, stream: stream);
    _preloadHandedInGeneration = null;
    _scheduleRefresh(track, stream);
    _syncPreload();
  }

  /// 預載的 [stream] 在過期前 [refreshBeforeExpiry] 重新解析（architecture
  /// 〈快取〉）；插件沒給有效期、或已經在那之內時不排。
  void _scheduleRefresh(Track track, AudioStream stream) {
    _preloadRefresh?.cancel();
    _preloadRefresh = null;
    final expiresAt = stream.expiresAt;
    if (expiresAt == null) return;
    final delay = expiresAt
        .subtract(refreshBeforeExpiry)
        .difference(ref.read(playbackClockProvider)());
    if (delay <= Duration.zero) return;
    _preloadRefresh = Timer(delay, () {
      _preloadRefresh = null;
      if (!ref.mounted || !identical(_preload?.stream, stream)) return;
      if (_wantedNext != track) return;
      _log.info(
        'Resolving the preloaded stream again before it expires: '
        '${track.ref.logId}',
      );
      unawaited(_resolvePreload(track));
    });
  }

  void _handToBackend(AudioStream? stream) => unawaited(
    _backend.preload(stream).catchError((Object error, StackTrace stackTrace) {
      _log.warning(
        'Handing the preload to the audio backend failed',
        error: error,
        stackTrace: stackTrace,
      );
    }),
  );

  /// 播 [track] 時能用的預載串流；用了就不再是預載。離過期不到
  /// [refreshBeforeExpiry] 的不用（architecture〈快取〉），照常解析。
  AudioStream? _takePreload(Track track) {
    final preload = _preload;
    if (preload == null || preload.track != track) return null;
    _preload = null;
    _preloadHandedInGeneration = null;
    _preloadRefresh?.cancel();
    _preloadRefresh = null;
    if (_expiresSoon(preload.stream)) {
      _log.info(
        'Resolving the stream again before it expires: ${track.ref.logId}',
      );
      return null;
    }
    return preload.stream;
  }

  bool _expiresSoon(AudioStream stream) {
    final expiresAt = stream.expiresAt;
    if (expiresAt == null) return false;
    final now = ref.read(playbackClockProvider)();
    return expiresAt.difference(now) < refreshBeforeExpiry;
  }

  /// 跳到 [position]；播放中就從那裡接著播。這一首還沒載入完（或還沒播過）
  /// 時什麼都不做。
  Future<void> seek(Duration position) async {
    final current = state;
    if (current == null) return;
    if (!_loaded) {
      // 重啟後還原、還沒載入的那首：只改開始播的位置。
      if (current.status == PlaybackStatus.paused) {
        if (_resumeFrom?.track == current.track) {
          _resumeFrom = (track: current.track, position: position);
        }
        state = PlaybackState(
          track: current.track,
          status: current.status,
          position: position,
        );
      }
      return;
    }
    if (_refreshBeforeExpiry(current)) {
      return _start(current.track, from: position, autoplay: current.playing);
    }
    final generation = _generation;
    try {
      await _backend.seek(position);
    } catch (error, stackTrace) {
      await _retryOrFail(
        generation,
        current.track,
        current.stream,
        error,
        stackTrace,
        'Seeking failed',
        at: position,
        autoplay: current.playing,
      );
    }
  }

  /// [current] 的串流離過期不到 [refreshBeforeExpiry]：寫一筆 log，呼叫端
  /// 要先重新解析。插件沒給有效期的不預先解析，壞了才重新解析。
  bool _refreshBeforeExpiry(PlaybackState current) {
    final expiresAt = current.stream?.expiresAt;
    if (expiresAt == null) return false;
    final now = ref.read(playbackClockProvider)();
    if (expiresAt.difference(now) >= refreshBeforeExpiry) return false;
    _log.info(
      'Resolving the stream again before it expires: '
      '${current.track.ref.logId}',
    );
    return true;
  }

  /// 停止：暫停後端、沒有正在播的曲目（狀態回到 null）。解析或載入到一半
  /// 的那首不會再開始播。
  Future<void> stop() async {
    ++_generation;
    _sounded = false;
    _cancelWatchdog();
    state = null;
    await _backendOrNull?.pause();
  }

  /// 沒播過時什麼都不做。
  Future<void> pause() async => _backendOrNull?.pause();

  /// 沒播過時什麼都不做；重啟後還原的那首從還原的位置開始播。
  Future<void> resume() async {
    final current = state;
    if (current != null &&
        current.status == PlaybackStatus.paused &&
        !_loaded) {
      return play(current.track);
    }
    if (current != null &&
        current.status == PlaybackStatus.paused &&
        _refreshBeforeExpiry(current)) {
      return _start(current.track, from: current.position, autoplay: true);
    }
    await _backendOrNull?.play();
  }

  /// 迷你播放器與播放膠囊的播放鈕：正在播就暫停、暫停中就繼續，播完或
  /// 失敗的那首從頭再播一次；解析與載入中、還沒播過時什麼都不做。
  Future<void> playPause() async {
    final current = state;
    if (current == null) return;
    switch (current.status) {
      case PlaybackStatus.playing || PlaybackStatus.buffering:
        await pause();
      case PlaybackStatus.paused:
        await resume();
      case PlaybackStatus.completed || PlaybackStatus.failed:
        await play(current.track);
      case PlaybackStatus.resolving || PlaybackStatus.loading:
        break;
    }
  }

  bool _isCurrent(int generation) => ref.mounted && generation == _generation;

  /// 第 [generation] 代的一步失敗了。串流壞掉（後端的錯誤、看門狗）而這次
  /// [play] 還沒重新解析過，就重新解析、從 [at] 接著（[autoplay] 時接著
  /// 播）；否則報失敗。
  Future<void> _retryOrFail(
    int generation,
    Track track,
    AudioStream? stream,
    Object error,
    StackTrace stackTrace,
    String programErrorMessage, {
    required Duration at,
    required bool autoplay,
  }) {
    if (!_isCurrent(generation)) return Future.value();
    if (error is AudioBackendError && !_resolvedAgain) {
      _logBackendError(error, track, stream);
      _resolvedAgain = true;
      _log.info('Resolving the stream again: ${track.ref.logId}');
      return _start(track, from: at, autoplay: autoplay);
    }
    _fail(track, stream, error, stackTrace, programErrorMessage);
    return Future.value();
  }

  /// 這一首播不了：寫 log、報 [PlaybackStatus.failed]。
  void _fail(
    Track track,
    AudioStream? stream,
    Object error,
    StackTrace stackTrace,
    String programErrorMessage,
  ) {
    _cancelWatchdog();
    final AppError? category;
    switch (error) {
      case AudioBackendError():
        _logBackendError(error, track, stream);
        category = error.category;
      case AppError():
        // 插件宿主已經記過它的錯誤。
        category = error;
      default:
        _log.error(programErrorMessage, error: error, stackTrace: stackTrace);
        category = null;
    }
    state = PlaybackState(
      track: track,
      stream: stream,
      status: PlaybackStatus.failed,
      error: category,
    );
  }

  /// 只記 CDN 的主機，不記簽名網址。
  void _logBackendError(
    AudioBackendError error,
    Track track,
    AudioStream? stream,
  ) => _log.error(
    'Playback failed: ${error.category} (${error.detail}) '
    'for ${track.ref.logId} from ${stream?.url.host}',
  );

  void _onBackendState(AudioBackendState backend) {
    final current = state;
    if (current == null ||
        current.status == PlaybackStatus.resolving ||
        current.status == PlaybackStatus.failed) {
      // 解析中收到的是上一首的狀態；失敗後要等下一次 play。
      return;
    }
    if (backend.stream case final other?
        when current.stream != null && !identical(other, current.stream)) {
      // 別條串流的狀態：上一首遲到的，或後端已經自己接到預載的那條、
      // 還沒輪到播它。
      return;
    }
    if (current.status == PlaybackStatus.loading &&
        backend.status == AudioBackendStatus.completed) {
      // 剛開始載入的串流不會已經播完，是上一首遲到的狀態；收下的話佇列
      // 會再接一次下一首。
      return;
    }
    final status = switch (backend.status) {
      AudioBackendStatus.idle ||
      AudioBackendStatus.loading => PlaybackStatus.loading,
      AudioBackendStatus.buffering =>
        backend.playing ? PlaybackStatus.buffering : PlaybackStatus.loading,
      AudioBackendStatus.ready =>
        backend.playing
            ? PlaybackStatus.playing
            : _startingGeneration == _generation
            ? PlaybackStatus.loading
            : PlaybackStatus.paused,
      AudioBackendStatus.completed => PlaybackStatus.completed,
      AudioBackendStatus.failed => PlaybackStatus.failed,
    };
    if (backend.status == AudioBackendStatus.failed) {
      // 開始播之前的失敗由 [_start] 接（後端多半同時丟錯）。
      if (_startingGeneration == _generation) return;
      unawaited(
        _retryOrFail(
          _generation,
          current.track,
          current.stream,
          backend.error ?? const AudioBackendError(ParseFailure(), 'failed'),
          StackTrace.current,
          'Playback failed',
          at: current.position,
          // 暫停中出錯就停在那裡，不自己開始播。
          autoplay: current.playing,
        ),
      );
      return;
    }
    if (backend.status == AudioBackendStatus.ready &&
        backend.playing &&
        !_sounded) {
      _sounded = true;
      _syncPreload();
    }
    if (backend.status == AudioBackendStatus.ready && backend.playing) {
      if (_resolvedAgain && backend.position - _startedFrom >= _healthyAfter) {
        _resolvedAgain = false;
      }
    }
    _watchdog(backend);
    if (backend.status == AudioBackendStatus.ready &&
        backend.duration == Duration.zero &&
        !_zeroDurationLogged) {
      _zeroDurationLogged = true;
      // 事實 I4（AVPlayer 把載入失敗的項目報成 ready、長度 0）、W4。
      _log.warning(
        'Stream reported a zero duration: ${current.track.ref.logId}',
      );
    }
    state = PlaybackState(
      track: current.track,
      stream: current.stream,
      status: status,
      position: backend.position,
      // 這一首載入完成之前，後端報的可能還是上一首的長度。
      duration: _loadedGeneration == _generation ? backend.duration : null,
      error: backend.error?.category,
    );
  }

  /// 看門狗（事實 W4：一直 buffering 的串流不會報錯）：要出聲（正在開始播，
  /// 或按了播放）卻一直沒有聲音，超過 [StallTimeouts] 的門檻就當成串流壞掉。
  /// 還沒出過聲用 [StallTimeouts.starting]，出過聲用 [StallTimeouts.playing]。
  void _watchdog(AudioBackendState backend) {
    final wantsSound = _startingGeneration == _generation || backend.playing;
    final silent = switch (backend.status) {
      AudioBackendStatus.idle ||
      AudioBackendStatus.loading ||
      AudioBackendStatus.buffering => true,
      AudioBackendStatus.ready ||
      AudioBackendStatus.completed ||
      AudioBackendStatus.failed => false,
    };
    if (!wantsSound || !silent) {
      _cancelWatchdog();
      return;
    }
    if (_stallTimer != null) return;
    final timeouts = ref.read(stallTimeoutsProvider);
    final (phase, after) = _sounded
        ? ('buffering', timeouts.playing)
        : ('starting', timeouts.starting);
    final generation = _generation;
    _stallTimer = Timer(after, () {
      _stallTimer = null;
      final current = state;
      if (current == null || !_isCurrent(generation)) return;
      final logId = current.track.ref.logId;
      _log.warning(
        'Playback stalled: $phase for over ${after.inMilliseconds} ms: $logId',
      );
      if (_resolvedAgain) {
        // 卡住的串流之後可能自己出聲；失敗了就別讓它播。
        unawaited(_backendOrNull?.pause());
      }
      unawaited(
        _retryOrFail(
          generation,
          current.track,
          current.stream,
          AudioBackendError(const NetworkError(), 'stalled while $phase'),
          StackTrace.current,
          'Playback stalled',
          at: current.position,
          // 正在開始播的照原本要不要播；播放中卡住的接著播。
          autoplay: _startingGeneration == generation ? _startAutoplay : true,
        ),
      );
    });
  }

  void _cancelWatchdog() {
    _stallTimer?.cancel();
    _stallTimer = null;
  }
}
