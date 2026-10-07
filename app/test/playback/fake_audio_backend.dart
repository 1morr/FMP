import 'dart:async';

import 'package:fmp/domain/output_device.dart';
import 'package:fmp/playback/backends/audio_backend.dart';
import 'package:fmp/playback/backends/backend_rules.dart';
import 'package:fmp/playback/playback_state.dart';

/// 不出聲的 [AudioBackend]：位置以計時器前進，所以在 `fakeAsync` 裡也照樣跑。
///
/// 清單的修改與結束的分類用和真後端同一份規則（`backend_rules.dart`），
/// `audio_backend_contract.dart` 以同一份斷言跑它與真後端。
final class FakeAudioBackend implements AudioBackend {
  FakeAudioBackend({
    this.durationOf = _twoSeconds,
    this.failsToOpen = _never,
    this.httpStatusOf = _noStatus,
    this.tick = const Duration(milliseconds: 50),
    this.outputDevices,
  });

  static Duration _twoSeconds(Uri url) => const Duration(seconds: 2);
  static bool _never(Uri url) => false;
  static int? _noStatus(Uri url) => null;

  /// 每個網址的長度。
  final Duration Function(Uri url) durationOf;

  /// 開不起來的網址。開成目前的來源時馬上失敗；當前瞻時像 ExoPlayer 一樣，到
  /// 交接時才失敗（先發失敗、再發目前這首的結束）。
  final bool Function(Uri url) failsToOpen;

  /// 開不起來的網址被 HTTP 拒絕時的狀態碼（[SourceFailed.httpStatus]）。
  final int? Function(Uri url) httpStatusOf;

  /// 位置每次前進多少（也是位置回報的間隔）。
  final Duration tick;

  /// 給了就像 Windows 一樣能選輸出裝置。
  @override
  final FakeOutputDevices? outputDevices;

  /// 每次 [open] 的來源與起點，依序。
  final opened = <BackendSource>[];
  final openedAt = <Duration>[];

  /// 每次 [setNext] 的參數，依序。
  final nextSources = <BackendSource?>[];

  final _status = StreamController<BackendStatus>.broadcast();
  final _progress = StreamController<SourceProgress>.broadcast();
  final _events = StreamController<BackendEvent>.broadcast();

  final _playlist = <BackendSource>[];
  int _index = -1;
  Duration _position = Duration.zero;
  bool _playing = false;
  bool _loaded = false;
  Timer? _ticker;
  double _volume = 1;
  double _speed = 1;

  BackendSource? get current =>
      _index >= 0 && _index < _playlist.length ? _playlist[_index] : null;

  /// 目前清單裡的來源（目前＋前瞻）。
  List<BackendSource> get playlist => List.unmodifiable(_playlist);

  bool get playing => _playing;

  @override
  double get volume => _volume;

  /// 位置以這個倍數前進（假時間裡的播放速度）。
  @override
  double get speed => _speed;

  @override
  Stream<BackendStatus> get status => _status.stream;

  @override
  Stream<SourceProgress> get progress => _progress.stream;

  @override
  Stream<BackendEvent> get events => _events.stream;

  @override
  Future<void> open(
    BackendSource source, {
    Duration start = Duration.zero,
    bool play = true,
  }) async {
    opened.add(source);
    openedAt.add(start);
    _ticker?.cancel();
    _playlist
      ..clear()
      ..add(source);
    _index = 0;
    _position = start;
    _playing = play;
    _loaded = false;
    _emitStatus(BackendPhase.buffering);
    if (failsToOpen(source.url)) {
      _playing = false;
      _events.add(
        SourceFailed(
          id: source.id,
          failure: BackendFailure.open,
          cause: 'unopenable',
          httpStatus: httpStatusOf(source.url),
        ),
      );
      return;
    }
    _loaded = true;
    _emitStatus(BackendPhase.ready);
    // 暫停中開的來源不回報位置，到播放或 seek 才有（just_audio 的形狀：它的
    // positionStream 只在播放中與引擎事件時發出，載入的事件在清單修改期間被
    // 丟掉）。契約只保證播放中與 seek 後回報。
    if (play) _emitProgress();
    _schedule();
  }

  /// 給了就在 [setNext] 套用之前等它：真後端的清單修改排隊執行，排隊期間引擎
  /// 可能已經接上舊的前瞻。
  Future<void>? setNextGate;

  @override
  Future<void> setNext(BackendSource? next) async {
    nextSources.add(next);
    if (setNextGate case final gate?) await gate;
    if (current == null) return;
    final edit = LookAheadEdit.of(
      itemCount: _playlist.length,
      currentIndex: _index,
      append: next != null,
    );
    _apply(edit, next);
  }

  @override
  Future<void> play() async {
    if (current == null) return;
    _playing = true;
    _emitStatus(BackendPhase.ready);
    _schedule();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _ticker?.cancel();
    if (current != null) _emitStatus(BackendPhase.ready);
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    _emitProgress();
  }

  @override
  Future<void> setVolume(double volume) async => _volume = clampVolume(volume);

  @override
  Future<void> setSpeed(double speed) async => _speed = clampSpeed(speed);

  @override
  Future<void> stop() async {
    _ticker?.cancel();
    _playlist.clear();
    _index = -1;
    _playing = false;
    _emitStatus(BackendPhase.idle);
  }

  @override
  Future<void> dispose() async {
    _ticker?.cancel();
    await _status.close();
    await _progress.close();
    await _events.close();
  }

  /// 目前的來源在這裡中斷（像 ExoPlayer 的連線錯誤），引擎的錯誤是 [cause]。
  void interrupt({Object cause = 'interrupted'}) {
    final source = current;
    if (source == null) return;
    _ticker?.cancel();
    _playing = false;
    _events.add(
      SourceFailed(
        id: source.id,
        failure: BackendFailure.interrupted,
        cause: cause,
      ),
    );
  }

  /// 目前的來源提前結束（像 mpv 的輸出裝置失敗時先送到的 `completed`）。
  void endEarly() {
    final source = current;
    if (source == null) return;
    _ticker?.cancel();
    _playing = false;
    endEarlyFor(source);
    _emitStatus(BackendPhase.ended);
  }

  /// 發出 [source] 提前結束的事件，不管它還是不是目前的來源（`stop` 之前就
  /// 送出、晚一點才到的那種）。
  void endEarlyFor(BackendSource source) =>
      _events.add(SourceEnded(id: source.id, end: TrackEndReason.endedEarly));

  /// 別的 App 拿走音訊焦點（Android 的暫停類中斷）。
  void audioInterrupted() => _events.add(const Interrupted());

  /// 中斷結束；[resume] 是暫停類的中斷結束。
  void audioInterruptionEnded({bool resume = true}) =>
      _events.add(InterruptionEnded(resume: resume));

  /// 拔耳機。
  void becameNoisy() => _events.add(const BecameNoisy());

  /// 輸出裝置開不起來（mpv 的 `[ao]` 錯誤）：像 mpv 一樣，目前的來源也停下。
  void failOutputDevice() {
    _ticker?.cancel();
    _events.add(const OutputDeviceFailed(cause: 'ao: no device'));
  }

  /// 目前的來源中途停下等資料（緩衝），到 [resume] 為止。
  void stall() {
    if (current == null) return;
    _ticker?.cancel();
    _emitStatus(BackendPhase.buffering);
  }

  /// [stall] 之後資料又來了。
  void resume() {
    if (current == null) return;
    _emitStatus(BackendPhase.ready);
    _schedule();
  }

  void _apply(LookAheadEdit edit, BackendSource? next) {
    for (final index in edit.removeIndices) {
      _playlist.removeAt(index);
      if (index < _index) _index--;
    }
    if (edit.append && next != null) _playlist.add(next);
  }

  void _schedule() {
    _ticker?.cancel();
    if (!_playing || current == null) return;
    _ticker = Timer.periodic(tick, (_) => _advanceTime());
  }

  void _advanceTime() {
    final source = current;
    if (source == null) return;
    final duration = durationOf(source.url);
    _position += tick * _speed;
    if (_position < duration) {
      _emitProgress();
      return;
    }
    final end = classifyTrackEnd(position: duration, duration: duration);
    if (_index + 1 < _playlist.length &&
        failsToOpen(_playlist[_index + 1].url)) {
      // 前瞻開不起來：不接上，目前這首就此結束。
      final next = _playlist.removeAt(_index + 1);
      _events.add(
        SourceFailed(
          id: next.id,
          failure: BackendFailure.open,
          cause: 'unopenable',
          httpStatus: httpStatusOf(next.url),
        ),
      );
    }
    if (_index + 1 < _playlist.length) {
      final next = _playlist[_index + 1];
      _index++;
      _position = Duration.zero;
      _events.add(SourceAdvanced(from: source.id, to: next.id, end: end));
      // 真後端一樣：接上後修剪播完的那一個。
      _apply(
        LookAheadEdit.of(
          itemCount: _playlist.length,
          currentIndex: _index,
          append: false,
        ),
        null,
      );
      _emitStatus(BackendPhase.ready);
      return;
    }
    _ticker?.cancel();
    _playing = false;
    _events.add(SourceEnded(id: source.id, end: end));
    _emitStatus(BackendPhase.ended);
  }

  void _emitStatus(BackendPhase phase) => _status.add(
    BackendStatus(sourceId: current?.id, playing: _playing, phase: phase),
  );

  void _emitProgress() {
    final source = current;
    if (source == null || !_loaded) return;
    _progress.add(
      SourceProgress(
        sourceId: source.id,
        progress: PlaybackProgress(
          position: _position,
          duration: durationOf(source.url),
        ),
      ),
    );
  }
}

/// 假的輸出裝置：清單由測試以 [list] 給，[select] 記下每次的選擇。
final class FakeOutputDevices implements OutputDevices {
  FakeOutputDevices([this._devices]);

  List<OutputDevice>? _devices;
  final _changes = StreamController<List<OutputDevice>>.broadcast();
  OutputDevice? _selected;

  /// 每次 [select] 的參數，依序。
  final selections = <OutputDevice?>[];

  /// 引擎列出（或插拔後重新列出）[devices]。
  void list(List<OutputDevice> devices) {
    _devices = devices;
    _changes.add(devices);
  }

  @override
  Stream<List<OutputDevice>> get available async* {
    if (_devices case final devices?) yield devices;
    yield* _changes.stream;
  }

  @override
  OutputDevice? get selected => _selected;

  @override
  Future<void> select(OutputDevice? device) async {
    selections.add(device);
    _selected = device;
  }
}
