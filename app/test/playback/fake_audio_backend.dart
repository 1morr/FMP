import 'dart:async';

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
    this.tick = const Duration(milliseconds: 50),
  });

  static Duration _twoSeconds(Uri url) => const Duration(seconds: 2);
  static bool _never(Uri url) => false;

  /// 每個網址的長度。
  final Duration Function(Uri url) durationOf;

  /// 開不起來的網址。
  final bool Function(Uri url) failsToOpen;

  /// 位置每次前進多少（也是位置回報的間隔）。
  final Duration tick;

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

  BackendSource? get current =>
      _index >= 0 && _index < _playlist.length ? _playlist[_index] : null;

  /// 目前清單裡的來源（目前＋前瞻）。
  List<BackendSource> get playlist => List.unmodifiable(_playlist);

  bool get playing => _playing;

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
        ),
      );
      return;
    }
    _loaded = true;
    _emitStatus(BackendPhase.ready);
    _emitProgress();
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
    _position += tick;
    if (_position < duration) {
      _emitProgress();
      return;
    }
    final end = classifyTrackEnd(position: duration, duration: duration);
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
