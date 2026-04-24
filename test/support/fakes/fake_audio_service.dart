import 'dart:async';

import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/audio/audio_service.dart';
import 'package:fmp/services/audio/audio_types.dart';

class AudioUrlCall {
  AudioUrlCall({required this.url, this.headers, this.track});

  final String url;
  final Map<String, String>? headers;
  final Track? track;
}

class AudioFileCall {
  AudioFileCall({required this.filePath, this.track});

  final String filePath;
  final Track? track;
}

class FakeAudioService implements FmpAudioService {
  final _playerStateController = StreamController<FmpPlayerState>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _processingStateController =
      StreamController<FmpAudioProcessingState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _bufferedPositionController = StreamController<Duration>.broadcast();
  final _speedController = StreamController<double>.broadcast();
  final _completedController = StreamController<void>.broadcast();
  final _audioDevicesController =
      StreamController<List<FmpAudioDevice>>.broadcast();
  final _audioDeviceController = StreamController<FmpAudioDevice?>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  final List<AudioUrlCall> playUrlCalls = [];
  final List<AudioUrlCall> setUrlCalls = [];
  final List<AudioFileCall> playFileCalls = [];
  final List<AudioFileCall> setFileCalls = [];
  final List<Duration> seekCalls = [];
  int stopCallCount = 0;

  final List<Completer<void>> _pendingPlayUrl = [];
  final List<Completer<void>> _pendingSetUrl = [];
  final List<Completer<void>> _pendingSeek = [];
  final List<Object> _stopErrors = [];
  final List<Object> _playUrlErrors = [];
  final List<_CountWaiter> _playUrlWaiters = [];
  final List<_CountWaiter> _setUrlWaiters = [];
  final List<_CountWaiter> _seekWaiters = [];

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  Duration _bufferedPosition = Duration.zero;
  double _speed = 1.0;
  double _volume = 1.0;
  FmpAudioProcessingState _processingState = FmpAudioProcessingState.idle;
  List<FmpAudioDevice> _audioDevices = const [];
  FmpAudioDevice? _audioDevice;

  Completer<void> enqueuePendingPlayUrl() {
    final completer = Completer<void>();
    _pendingPlayUrl.add(completer);
    return completer;
  }

  Completer<void> enqueuePendingSetUrl() {
    final completer = Completer<void>();
    _pendingSetUrl.add(completer);
    return completer;
  }

  Completer<void> enqueuePendingSeek() {
    final completer = Completer<void>();
    _pendingSeek.add(completer);
    return completer;
  }

  void enqueueStopError(Object error) {
    _stopErrors.add(error);
  }

  void enqueuePlayUrlError(Object error) {
    _playUrlErrors.add(error);
  }

  Future<void> waitForPlayUrlCallCount(int count) {
    if (playUrlCalls.length >= count) return Future.value();
    final completer = Completer<void>();
    _playUrlWaiters.add(_CountWaiter(count, completer));
    return completer.future;
  }

  Future<void> waitForSetUrlCallCount(int count) {
    if (setUrlCalls.length >= count) return Future.value();
    final completer = Completer<void>();
    _setUrlWaiters.add(_CountWaiter(count, completer));
    return completer.future;
  }

  Future<void> waitForSeekCallCount(int count) {
    if (seekCalls.length >= count) return Future.value();
    final completer = Completer<void>();
    _seekWaiters.add(_CountWaiter(count, completer));
    return completer.future;
  }

  void setPositionValue(Duration position) {
    _position = position;
  }

  void setPlayingValue(bool isPlaying) {
    _isPlaying = isPlaying;
  }

  void emitCompleted() {
    _completedController.add(null);
  }

  void emitError(String error) {
    _errorController.add(error);
  }

  void emitPosition(Duration position) {
    _position = position;
    _positionController.add(position);
  }

  void _notifyPlayUrlWaiters() {
    for (final waiter in List<_CountWaiter>.from(_playUrlWaiters)) {
      if (playUrlCalls.length >= waiter.target &&
          !waiter.completer.isCompleted) {
        waiter.completer.complete();
        _playUrlWaiters.remove(waiter);
      }
    }
  }

  void _notifySetUrlWaiters() {
    for (final waiter in List<_CountWaiter>.from(_setUrlWaiters)) {
      if (setUrlCalls.length >= waiter.target &&
          !waiter.completer.isCompleted) {
        waiter.completer.complete();
        _setUrlWaiters.remove(waiter);
      }
    }
  }

  void _notifySeekWaiters() {
    for (final waiter in List<_CountWaiter>.from(_seekWaiters)) {
      if (seekCalls.length >= waiter.target && !waiter.completer.isCompleted) {
        waiter.completer.complete();
        _seekWaiters.remove(waiter);
      }
    }
  }

  Future<void> _awaitPending(List<Completer<void>> pending) async {
    if (pending.isEmpty) return;
    await pending.removeAt(0).future;
  }

  void _emitState() {
    final playerState = FmpPlayerState(
      playing: _isPlaying,
      processingState: _processingState,
    );
    _playerStateController.add(playerState);
    _playingController.add(_isPlaying);
    _processingStateController.add(_processingState);
    _positionController.add(_position);
    _durationController.add(_duration);
    _bufferedPositionController.add(_bufferedPosition);
    _speedController.add(_speed);
    _audioDevicesController.add(_audioDevices);
    _audioDeviceController.add(_audioDevice);
  }

  @override
  Stream<FmpPlayerState> get playerStateStream => _playerStateController.stream;
  @override
  Stream<bool> get playingStream => _playingController.stream;
  @override
  Stream<FmpAudioProcessingState> get processingStateStream =>
      _processingStateController.stream;
  @override
  Stream<Duration> get positionStream => _positionController.stream;
  @override
  Stream<Duration?> get durationStream => _durationController.stream;
  @override
  Stream<Duration> get bufferedPositionStream =>
      _bufferedPositionController.stream;
  @override
  Stream<double> get speedStream => _speedController.stream;
  @override
  Stream<void> get completedStream => _completedController.stream;
  @override
  Stream<List<FmpAudioDevice>> get audioDevicesStream =>
      _audioDevicesController.stream;
  @override
  Stream<FmpAudioDevice?> get audioDeviceStream =>
      _audioDeviceController.stream;
  @override
  Stream<String> get errorStream => _errorController.stream;

  @override
  bool get isPlaying => _isPlaying;
  @override
  Duration get position => _position;
  @override
  Duration? get duration => _duration;
  @override
  Duration get bufferedPosition => _bufferedPosition;
  @override
  double get speed => _speed;
  @override
  double get volume => _volume;
  @override
  FmpAudioProcessingState get processingState => _processingState;
  @override
  List<FmpAudioDevice> get audioDevices => _audioDevices;
  @override
  FmpAudioDevice? get audioDevice => _audioDevice;

  @override
  Future<void> initialize() async => _emitState();
  @override
  Future<void> dispose() async {
    await _playerStateController.close();
    await _playingController.close();
    await _processingStateController.close();
    await _positionController.close();
    await _durationController.close();
    await _bufferedPositionController.close();
    await _speedController.close();
    await _completedController.close();
    await _audioDevicesController.close();
    await _audioDeviceController.close();
    await _errorController.close();
  }

  @override
  Future<void> play() async {
    _isPlaying = true;
    _processingState = FmpAudioProcessingState.ready;
    _emitState();
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    _emitState();
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
    if (_stopErrors.isNotEmpty) {
      throw _stopErrors.removeAt(0);
    }
    _isPlaying = false;
    _processingState = FmpAudioProcessingState.idle;
    _emitState();
  }

  @override
  Future<void> togglePlayPause() => _isPlaying ? pause() : play();
  @override
  Future<void> seekTo(Duration position) async {
    seekCalls.add(position);
    _notifySeekWaiters();
    await _awaitPending(_pendingSeek);
    _position = position;
    _emitState();
  }

  @override
  Future<void> seekForward([Duration? duration]) async =>
      seekTo(_position + (duration ?? const Duration(seconds: 10)));
  @override
  Future<void> seekBackward([Duration? duration]) async =>
      seekTo(_position - (duration ?? const Duration(seconds: 10)));
  @override
  Future<bool> seekToLive() async => false;
  @override
  Future<void> setSpeed(double speed) async => _speed = speed;
  @override
  Future<void> resetSpeed() async => _speed = 1.0;
  @override
  Future<void> setVolume(double volume) async => _volume = volume;
  @override
  Future<void> setAudioDevice(FmpAudioDevice device) async =>
      _audioDevice = device;
  @override
  Future<void> setAudioDeviceAuto() async => _audioDevice = null;

  @override
  Future<Duration?> playUrl(String url,
      {Map<String, String>? headers, Track? track}) async {
    playUrlCalls.add(AudioUrlCall(url: url, headers: headers, track: track));
    _notifyPlayUrlWaiters();
    await _awaitPending(_pendingPlayUrl);
    if (_playUrlErrors.isNotEmpty) {
      throw _playUrlErrors.removeAt(0);
    }
    _isPlaying = true;
    _processingState = FmpAudioProcessingState.ready;
    _emitState();
    return _duration;
  }

  @override
  Future<Duration?> setUrl(String url,
      {Map<String, String>? headers, Track? track}) async {
    setUrlCalls.add(AudioUrlCall(url: url, headers: headers, track: track));
    _notifySetUrlWaiters();
    await _awaitPending(_pendingSetUrl);
    _processingState = FmpAudioProcessingState.ready;
    _emitState();
    return _duration;
  }

  @override
  Future<Duration?> playFile(String filePath, {Track? track}) async {
    playFileCalls.add(AudioFileCall(filePath: filePath, track: track));
    _isPlaying = true;
    _processingState = FmpAudioProcessingState.ready;
    _emitState();
    return _duration;
  }

  @override
  Future<Duration?> setFile(String filePath, {Track? track}) async {
    setFileCalls.add(AudioFileCall(filePath: filePath, track: track));
    _processingState = FmpAudioProcessingState.ready;
    _emitState();
    return _duration;
  }
}

class _CountWaiter {
  _CountWaiter(this.target, this.completer);

  final int target;
  final Completer<void> completer;
}
