import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/domain/audio_stream.dart';
import 'package:fmp/domain/track.dart';
import 'package:fmp/playback/audio_backend.dart';
import 'package:fmp/plugins/plugins.dart';

/// App 的音訊後端。`main` 用 `platform/audio_backend.dart` 依平台建好再
/// override 進來；測試換成假的。
final audioBackendProvider = Provider<AudioBackend>(
  (ref) => throw StateError('audioBackendProvider is overridden in main()'),
);

/// 一直緩衝多久要寫一筆警告（事實 W4：長度為零的串流不報錯、一直
/// buffering）。M0 只記錄；完整的看門狗（重試、跳下一首）在 M1。
final stallWarningAfterProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 15),
);

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

/// 前景播放一首曲目（M0 的 tracer bullet）：用提供它的插件解析串流、交給
/// 音訊後端播放，並把後端的狀態轉成 [PlaybackState]。錯誤轉成錯誤分類並
/// 寫 log。佇列與臨時播放在 `queue_controller.dart`；過期重新解析在 M1。
class Playback extends Notifier<PlaybackState?> {
  AudioBackend? _backendOrNull;
  StreamSubscription<AudioBackendState>? _subscription;
  int _generation = 0;

  /// 後端已經載入完成的那一次 [play]；之前後端報的長度可能是上一首的。
  int _loadedGeneration = -1;
  Timer? _stallTimer;
  bool _stallLogged = false;
  bool _zeroDurationLogged = false;

  Log get _log => ref.read(logProvider);

  @override
  PlaybackState? build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _stallTimer?.cancel();
    });
    return null;
  }

  /// 第一次播放時才建音訊後端：沒播過就不開原生播放器。
  AudioBackend get _backend {
    if (_backendOrNull case final backend?) return backend;
    final backend = ref.read(audioBackendProvider);
    _subscription = backend.states.listen(_onBackendState);
    return _backendOrNull = backend;
  }

  /// 播放 [track]，取代正在播的；給了 [from] 就從那裡開始（載入後先跳過去
  /// 再播，不會先從開頭出聲）。連點時只有最後一首會播。
  Future<void> play(Track track, {Duration from = Duration.zero}) async {
    final generation = ++_generation;
    _stallTimer?.cancel();
    _stallLogged = false;
    _zeroDurationLogged = false;
    state = PlaybackState(track: track, status: PlaybackStatus.resolving);

    final AudioStream stream;
    try {
      final host = await ref.read(pluginHostProvider.future);
      final plugin = host.pluginFor(track.ref);
      if (plugin == null) throw const Unsupported();
      stream = await plugin.resolveStream(track.ref);
    } catch (error, stackTrace) {
      if (!_isCurrent(generation)) return;
      _fail(track, null, error, stackTrace, 'Resolving a stream failed');
      return;
    }
    if (!_isCurrent(generation)) return;
    state = PlaybackState(
      track: track,
      stream: stream,
      status: PlaybackStatus.loading,
    );

    try {
      await _backend.load(stream);
    } catch (error, stackTrace) {
      if (!_isCurrent(generation)) return;
      _fail(track, stream, error, stackTrace, 'Loading a stream failed');
      return;
    }
    if (!_isCurrent(generation)) return;
    _loadedGeneration = generation;
    _onBackendState(_backend.state);
    if (from > Duration.zero) {
      try {
        await _backend.seek(from);
      } catch (error, stackTrace) {
        if (!_isCurrent(generation)) return;
        _fail(track, stream, error, stackTrace, 'Seeking failed');
        return;
      }
      if (!_isCurrent(generation)) return;
    }
    try {
      await _backend.play();
    } catch (error, stackTrace) {
      if (!_isCurrent(generation)) return;
      _fail(track, stream, error, stackTrace, 'Starting playback failed');
    }
  }

  /// 跳到 [position]；播放中就從那裡接著播。這一首還沒載入完（或還沒播過）
  /// 時什麼都不做。
  Future<void> seek(Duration position) async {
    if (state == null || _loadedGeneration != _generation) return;
    final generation = _generation;
    final current = state!;
    try {
      await _backend.seek(position);
    } catch (error, stackTrace) {
      if (!_isCurrent(generation)) return;
      _fail(current.track, current.stream, error, stackTrace, 'Seeking failed');
    }
  }

  /// 停止：暫停後端、沒有正在播的曲目（狀態回到 null）。解析或載入到一半
  /// 的那首不會再開始播。
  Future<void> stop() async {
    ++_generation;
    _stallTimer?.cancel();
    _stallTimer = null;
    state = null;
    await _backendOrNull?.pause();
  }

  /// 沒播過時什麼都不做。
  Future<void> pause() async => _backendOrNull?.pause();

  /// 沒播過時什麼都不做。
  Future<void> resume() async => _backendOrNull?.play();

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

  void _fail(
    Track track,
    AudioStream? stream,
    Object error,
    StackTrace stackTrace,
    String programErrorMessage,
  ) {
    _stallTimer?.cancel();
    _stallTimer = null;
    // 後端出錯時會先發 failed 再丟錯；先到的那一邊已經記過、改過狀態。
    if (error is AudioBackendError && state?.status == PlaybackStatus.failed) {
      return;
    }
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
        backend.playing ? PlaybackStatus.playing : PlaybackStatus.paused,
      AudioBackendStatus.completed => PlaybackStatus.completed,
      AudioBackendStatus.failed => PlaybackStatus.failed,
    };
    if (backend.status == AudioBackendStatus.failed) {
      if (backend.error case final error?) {
        _logBackendError(error, current.track, current.stream);
      }
    }
    _watchForStall(backend);
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

  /// 事實 W4：一直 buffering 的串流不會報錯，至少要留下紀錄。
  void _watchForStall(AudioBackendState backend) {
    final stalled =
        backend.status == AudioBackendStatus.buffering ||
        backend.status == AudioBackendStatus.loading;
    if (!stalled) {
      _stallTimer?.cancel();
      _stallTimer = null;
      return;
    }
    if (_stallTimer != null || _stallLogged) return;
    final after = ref.read(stallWarningAfterProvider);
    _stallTimer = Timer(after, () {
      _stallTimer = null;
      final current = state;
      if (current == null) return;
      _stallLogged = true;
      _log.warning(
        'Playback stalled: buffering for over ${after.inMilliseconds} ms: '
        '${current.track.ref.logId}',
      );
    });
  }
}
