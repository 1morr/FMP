import 'dart:async';

import 'package:fmp/data/models/track.dart';
import 'package:fmp/core/constants/app_constants.dart';
import 'package:fmp/services/audio/audio_service.dart';
import 'package:fmp/services/audio/audio_types.dart';
import 'package:fmp/services/audio/playback_media.dart';

import 'count_waiters.dart';

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

class AudioMediaCall {
  AudioMediaCall({required this.media});

  final PreparedPlaybackMedia media;
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
  final _audioDevicesController =
      StreamController<List<FmpAudioDevice>>.broadcast();
  final _audioDeviceController = StreamController<FmpAudioDevice?>.broadcast();
  final _endReasonController = StreamController<PlaybackEndReason>.broadcast();
  final _advancedToNextController =
      StreamController<PreparedPlaybackMedia>.broadcast();

  final List<AudioUrlCall> playUrlCalls = [];
  final List<AudioUrlCall> setUrlCalls = [];
  final List<AudioFileCall> playFileCalls = [];
  final List<AudioFileCall> setFileCalls = [];
  final List<AudioMediaCall> playMediaCalls = [];
  final List<AudioMediaCall> setMediaCalls = [];

  /// 每一次 `setNextMedia` 的參數，包含清除用的 null。
  ///
  /// arm / disarm 的條件表就是靠逐條斷言這個清單來釘住的。
  final List<PreparedPlaybackMedia?> setNextMediaCalls = [];
  final List<Duration> seekCalls = [];
  int stopCallCount = 0;
  int pauseCallCount = 0;

  final List<Completer<void>> _pendingPlayUrl = [];
  final List<Completer<void>> _pendingSetUrl = [];
  final List<Completer<void>> _pendingSeek = [];
  final List<Completer<void>> _pendingStop = [];
  final List<Completer<void>> _pendingPlay = [];
  final List<Object> _stopErrors = [];
  final List<Object> _playUrlErrors = [];
  late final _playUrlWaiters = CountWaiters(() => playUrlCalls.length);
  late final _setUrlWaiters = CountWaiters(() => setUrlCalls.length);
  late final _seekWaiters = CountWaiters(() => seekCalls.length);

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  final Duration _bufferedPosition = Duration.zero;
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

  Completer<void> enqueuePendingStop() {
    final completer = Completer<void>();
    _pendingStop.add(completer);
    return completer;
  }

  Completer<void> enqueuePendingPlay() {
    final completer = Completer<void>();
    _pendingPlay.add(completer);
    return completer;
  }

  void enqueueStopError(Object error) {
    _stopErrors.add(error);
  }

  void enqueuePlayUrlError(Object error) {
    _playUrlErrors.add(error);
  }

  Future<void> waitForPlayUrlCallCount(int count) =>
      _playUrlWaiters.waitFor(count);

  Future<void> waitForSetUrlCallCount(int count) =>
      _setUrlWaiters.waitFor(count);

  Future<void> waitForSeekCallCount(int count) => _seekWaiters.waitFor(count);

  void setPositionValue(Duration position) {
    _position = position;
  }

  void setDurationValue(Duration? duration) {
    _duration = duration;
  }

  void setPlayingValue(bool isPlaying) {
    _isPlaying = isPlaying;
  }

  void emitProcessingState(FmpAudioProcessingState processingState) {
    _processingState = processingState;
    _emitState();
  }

  /// 模擬後端宣告播放完成。
  ///
  /// 與真實後端一樣，由 fake 自己依 position/duration 判斷是「播完」還是「提前
  /// 結束」—— 這正是 `PlaybackEndReason` 把責任放在後端的意思。
  void emitCompleted() {
    _endReasonController.add(_classifyCompletion());
  }

  /// 明確表示「這首歌正常播完了」，不依賴 fake 的 position/duration。
  void emitNaturalCompletion() {
    _endReasonController.add(const EndedNaturally());
  }

  PlaybackEndReason _classifyCompletion() {
    final duration = _duration;
    if (duration == null || duration.inMilliseconds <= 0) {
      return EndedPrematurely(at: _position, expected: null);
    }
    if (duration - _position > AppConstants.completionTolerance) {
      return EndedPrematurely(at: _position, expected: duration);
    }
    return const EndedNaturally();
  }

  /// 媒體本身開不起來（URL 過期、404、格式不支援）。
  void emitMediaOpenError(String raw) {
    _endReasonController.add(MediaUnopenable(raw: raw));
  }

  /// 音訊輸出裝置失敗 —— 與媒體無關（issue #41）。
  void emitOutputDeviceFailure(String raw) {
    _endReasonController.add(OutputDeviceFailed(raw: raw));
  }

  void emitEndReason(PlaybackEndReason reason) {
    _endReasonController.add(reason);
  }

  /// 模擬傳輸層失敗（連線中斷／逾時），讓測試不必自己建構型別。
  void emitTransportFailure(String error) {
    _endReasonController.add(
      TransportFailed(kind: TransportFailureKind.unknown, raw: error),
    );
  }

  void emitPosition(Duration position) {
    _position = position;
    _positionController.add(position);
  }

  void emitAudioDevices(List<FmpAudioDevice> devices) {
    _audioDevices = devices;
    _audioDevicesController.add(devices);
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
  Stream<List<FmpAudioDevice>> get audioDevicesStream =>
      _audioDevicesController.stream;
  @override
  Stream<FmpAudioDevice?> get audioDeviceStream =>
      _audioDeviceController.stream;
  @override
  Stream<PlaybackEndReason> get endReasons => _endReasonController.stream;
  @override
  Stream<PreparedPlaybackMedia> get advancedToNext =>
      _advancedToNextController.stream;

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
    await _audioDevicesController.close();
    await _audioDeviceController.close();
    await _endReasonController.close();
    await _advancedToNextController.close();
  }

  @override
  Future<void> play() async {
    await _awaitPending(_pendingPlay);
    _isPlaying = true;
    _processingState = FmpAudioProcessingState.ready;
    _emitState();
  }

  @override
  Future<void> pause() async {
    pauseCallCount++;
    _isPlaying = false;
    _emitState();
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
    await _awaitPending(_pendingStop);
    if (_stopErrors.isNotEmpty) {
      throw _stopErrors.removeAt(0);
    }
    await _awaitPending(_pendingStop);
    _isPlaying = false;
    _processingState = FmpAudioProcessingState.idle;
    _emitState();
  }

  @override
  Future<void> togglePlayPause() => _isPlaying ? pause() : play();
  @override
  Future<void> seekTo(Duration position) async {
    seekCalls.add(position);
    _seekWaiters.notify();
    await _awaitPending(_pendingSeek);
    _position = position;
    _emitState();
  }

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
  Future<void> setNextMedia(PreparedPlaybackMedia? media) async {
    setNextMediaCalls.add(media);
  }

  /// 假裝後端自己接上了前瞻媒體。
  ///
  /// 真的後端是靠播放清單索引往前走發現這件事的；這裡直接給事件，測試才不必
  /// 去模擬 ExoPlayer / mpv 的清單行為。
  void emitAdvancedToNext(PreparedPlaybackMedia media) {
    _position = Duration.zero;
    _isPlaying = true;
    _advancedToNextController.add(media);
  }

  @override
  Future<Duration?> playMedia(PreparedPlaybackMedia media) {
    playMediaCalls.add(AudioMediaCall(media: media));
    return switch (media) {
      LocalPlaybackMedia(:final path, :final track) => playFile(
        path,
        track: track,
      ),
      RemotePlaybackMedia(:final url, :final headers, :final track) => playUrl(
        url.toString(),
        headers: headers,
        track: track,
      ),
    };
  }

  @override
  Future<Duration?> setMedia(PreparedPlaybackMedia media) {
    setMediaCalls.add(AudioMediaCall(media: media));
    return switch (media) {
      LocalPlaybackMedia(:final path, :final track) => setFile(
        path,
        track: track,
      ),
      RemotePlaybackMedia(:final url, :final headers, :final track) => setUrl(
        url.toString(),
        headers: headers,
        track: track,
      ),
    };
  }

  @override
  Future<Duration?> playUrl(
    String url, {
    Map<String, String>? headers,
    Track? track,
  }) async {
    playUrlCalls.add(AudioUrlCall(url: url, headers: headers, track: track));
    _playUrlWaiters.notify();
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
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Track? track,
  }) async {
    setUrlCalls.add(AudioUrlCall(url: url, headers: headers, track: track));
    _setUrlWaiters.notify();
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
