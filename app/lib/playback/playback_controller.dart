import 'dart:async';

import 'package:clock/clock.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/domain/loop_mode.dart';
import 'package:fmp/domain/output_device.dart';
import 'package:fmp/domain/playback_speed.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/playback/playback_event_router.dart';
import 'package:fmp/playback/playback_events.dart';
import 'package:fmp/playback/playback_session.dart';
import 'package:fmp/playback/playback_state.dart';
import 'package:fmp/playback/queue_model.dart';
import 'package:fmp/playback/recovery_policy.dart';
import 'package:fmp/playback/stream_resolver.dart';

/// 臨時播放回到佇列時要的兩個設定值（「播放」設定組），在回到佇列的當下讀。
typedef TemporaryReturnSettings = ({bool rememberPosition, Duration rewind});

/// 算一次播放的一首歌（播放歷史，design §7.8）：[track] 在 [at] 開始被聽。
typedef CountedPlay = ({TrackInfo track, DateTime at});

/// 輸出裝置的清單（不含系統預設）與目前選的；`selected` 為 `null` 是系統預設。
typedef OutputDeviceState = ({
  List<OutputDevice> devices,
  OutputDevice? selected,
});

/// UI 唯一的播放入口（ADR 0018 §決定 1），也是 [PlaybackState] 唯一的寫入者。
///
/// 協作者只回報：[QueueModel] 保管佇列；[PlaybackSession] 解析、開流、前瞻，
/// 並把後端的回報過濾成 [SessionEvent]；[routePlaybackEvent] 決定事件要做什麼；
/// [decideRecovery] 決定失敗後怎麼辦。狀態只在這裡依它們的結果改。
///
/// 音訊中斷、拔耳機與輸出裝置失敗由後端回報、[routePlaybackEvent] 決定，暫停與
/// 續播只在這裡做（design §7.6）：只有因中斷而暫停的才在中斷結束時續播，使用者
/// 在中斷期間按過播放或暫停就不再續播。音量、靜音與速度交給後端，換歌後由後端
/// 維持。
///
/// 佇列的每個編輯都重新指定前瞻（[PlaybackSession.retargetLookAhead]），引擎接上
/// 的一定是佇列當下的下一首。臨時播放中不準備佇列的前瞻：臨時曲目播完回到的那
/// 一首要從快照的位置開始，不能由引擎從頭接上（舊版「臨時播放不預取」）。單曲
/// 循環的前瞻是目前這首的同一份解析結果，接上時佇列不動。
///
/// 每個非同步步驟回來時以 [PlaybackSession.generation] 比對，代不同就丟掉結果。
///
/// 失敗由 [decideRecovery] 決定怎麼辦（ADR 0018 §決定 7、design §7.5）；計數
/// （重試、重新解析、換候選、連續跳過）只在這裡改。網路狀態不是 `online` 時停在
/// 這首等網路，回到 `online` 立刻從原位置重試（design §5.3）。緩衝飢餓以一次性
/// 計時器量，進 [Buffering] 開、離開取消；重試計數以位置前進累計
/// [retryResetAfter] 後歸零，不開計時器。
final class PlaybackController {
  /// [session] 由控制器擁有，[dispose] 時一起釋放。[temporaryReturnSettings]
  /// 在臨時播放回到佇列時讀，[skipPreviewClips] 在遇到試聽片段時讀，
  /// [networkStatus] 在失敗時讀；[networkStatusChanges] 是之後的每次改變。
  /// [preferredOutputDevice] 在輸出裝置清單第一次就緒時讀（記住的裝置 id），
  /// [saveOutputDevice] 在使用者選裝置時寫。
  PlaybackController({
    required this._session,
    required this._log,
    required this._temporaryReturnSettings,
    required this._skipPreviewClips,
    required this._networkStatus,
    required Stream<NetworkStatus> networkStatusChanges,
    required this._preferredOutputDevice,
    required this._saveOutputDevice,
  }) {
    _sessionEvents = _session.events.listen(_onSessionEvent);
    _progressEvents = _session.progress.listen(_onProgress);
    _networkChanges = networkStatusChanges.listen(_onNetworkStatus);
    _outputDeviceLists = _session.outputDeviceLists?.listen(_onOutputDevices);
  }

  static const _tag = 'playback';

  /// 兩次位置回報之間算「正常前進」的上限（後端每 50–200 毫秒回報一次）；
  /// 跳得更遠的是 seek。
  static const _maxProgressStep = Duration(seconds: 2);

  final PlaybackSession _session;
  final Log _log;
  final TemporaryReturnSettings Function() _temporaryReturnSettings;
  final bool Function() _skipPreviewClips;
  final NetworkStatus Function() _networkStatus;
  final Future<String?> Function() _preferredOutputDevice;
  final Future<void> Function(OutputDevice? device) _saveOutputDevice;
  late final StreamSubscription<SessionEvent> _sessionEvents;
  late final StreamSubscription<PlaybackProgress> _progressEvents;
  late final StreamSubscription<NetworkStatus> _networkChanges;
  StreamSubscription<List<OutputDevice>>? _outputDeviceLists;

  final _queue = QueueModel();
  final _states = StreamController<PlaybackState>.broadcast();
  final _queueStates = StreamController<QueueState>.broadcast();
  final _events = StreamController<PlaybackEvent>.broadcast();
  final _previews = StreamController<bool>.broadcast();
  final _interruptionChanges = StreamController<bool>.broadcast();
  final _volumeChanges =
      StreamController<({double volume, bool muted})>.broadcast();
  final _outputDeviceStates = StreamController<OutputDeviceState>.broadcast();
  final _speedChanges = StreamController<double>.broadcast();
  final _seeks = StreamController<Duration>.broadcast();
  final _plays = StreamController<CountedPlay>.broadcast();

  PlaybackState _state = const Idle();

  /// 使用者要不要出聲：暫停中開始的一首載入後停在暫停。
  bool _playWhenReady = true;

  /// 等重試或暫停時，下次從哪裡開始。
  Duration _resumeAt = Duration.zero;
  Timer? _retryTimer;

  /// 在等網路時是那時的代；網路回來時代沒變才重試。
  int? _waitingForNetwork;

  /// 緩衝飢餓的計時：進 [Buffering] 開，離開取消。
  Timer? _stallTimer;

  /// 這次開流以來在 [Playing] 中前進的位置（重試計數歸零用）與上一次的位置。
  Duration _playedSinceLoad = Duration.zero;
  Duration? _lastPosition;

  /// 照播試聽片段的那一首；不是試聽時為 `null`。
  TrackKeyParts? _previewTrack;

  /// 臨時播放結束時要不要載入佇列那一首：進入臨時播放時那一首有載入（在播或
  /// 暫停）才載入；原本停著（`Idle`、`Failed`、佇列是空的）就停在 `Idle`。
  bool _returnLoadsQueueTrack = false;

  /// 目前的暫停是音訊中斷造成的：中斷結束時續播。使用者按播放或暫停、換一首
  /// 開始播、拔耳機、停下時清掉。
  bool _pausedByInterruption = false;

  /// 中斷結束的續播已經發出（[play]），但後端還沒報出來：這段期間 [_state] 仍是
  /// [Paused]，[pausedByInterruption] 要維持為真，系統媒體控制才不會在續播前一刻
  /// 先被放掉。狀態離開 [Paused]、使用者暫停、停下時清掉。
  bool _resumingFromInterruption = false;

  /// 最近一次發給 [pausedByInterruptionChanges] 的值。
  bool _interruptionAnnounced = false;

  /// 使用者的音量（0–1）；靜音時是取消靜音後回到的值。
  double _volume = 1;
  bool _muted = false;

  /// 播放速度（0.5–2.0）；不持久化，每次啟動是 1。
  double _speed = 1;

  /// 啟動恢復帶回來的位置（已扣掉重啟倒退秒數），按播放時從這裡開始；沒有恢復、
  /// 或已經開始播任何一首之後為 `null`。
  Duration? _restoredPosition;

  /// 恢復後還沒播就先臨時播放：[_restoredPosition] 被臨時曲目的開始清掉，先收在
  /// 這裡（連同它屬於的佇列曲目），臨時播放結束、佇列仍停著時放回去。佇列那一首
  /// 換了（跳到、移除、清空）就作廢。
  ({Duration position, TrackKeyParts key})? _keptRestored;

  /// 目前（最近一次）開始的這首是啟動恢復後的第一次播放。
  bool _startedFromRestore = false;

  /// 目前這次「開始一首」還沒算過一次播放：第一次出聲（`MarkReady` 且在播）時算，
  /// 之後同一次開始裡的重試、重新解析、換候選、暫停後繼續都不再算（design §7.8）。
  /// 啟動恢復後的第一次播放與臨時播放結束回到佇列的那首不算，開始時就是 `false`。
  bool _countPlayOnAudible = false;

  /// 輸出裝置清單已經就緒過（記住的裝置只在第一次套用），或使用者自己選過。
  bool _outputDeviceListSeen = false;
  bool _outputDeviceChosen = false;

  /// 後端列出的可選裝置，與目前選的（`null` 是系統預設），給播放列的選單看。
  List<OutputDevice> _outputDevices = const [];
  OutputDevice? _selectedOutputDevice;

  // RecoveryPolicy 的計數，只在這裡改。
  int _retries = 0;
  int _reResolves = 0;
  bool _candidateSwitched = false;
  int _consecutiveSkips = 0;

  PlaybackState get state => _state;

  /// 狀態的變化（只在改變時發出）。
  Stream<PlaybackState> get states => _states.stream;

  QueueState get queue => _queue.state;

  Stream<QueueState> get queueStates => _queueStates.stream;

  /// 目前這首的位置、時長與緩衝。
  Stream<PlaybackProgress> get progress => _session.progress;

  /// 使用者要知道的一次性事件（佇列滿了、跳過、停下、試聽，design §7.9）。
  Stream<PlaybackEvent> get events => _events.stream;

  /// 目前這首照播的是試聽片段（播放列標「試聽」）。
  bool get previewing => _previewTrack != null;

  /// [previewing] 的變化（只在改變時發出）。
  Stream<bool> get previewChanges => _previews.stream;

  /// 目前的暫停（或正要發生的暫停）是音訊中斷造成的，中斷結束會續播。使用者
  /// 按播放或暫停、拔耳機、停下就變回假；中斷結束的續播發出後到後端報出播放前
  /// 仍為真。`NowPlayingPublisher` 據此在這段期間讓系統媒體工作階段維持在播放。
  bool get pausedByInterruption =>
      _pausedByInterruption || _resumingFromInterruption;

  /// [pausedByInterruption] 的變化（只在改變時發出）。
  Stream<bool> get pausedByInterruptionChanges => _interruptionChanges.stream;

  /// 使用者的音量（0–1）；靜音時是取消靜音後回到的值。
  double get volume => _volume;

  bool get muted => _muted;

  /// 目前的播放速度（已夾到 0.5–2.0）。
  double get speed => _speed;

  /// [speed] 改變（[setSpeed]）。
  Stream<double> get speedChanges => _speedChanges.stream;

  /// 音量或靜音改變（[setVolume]、[toggleMute]；[restore] 不算），給持久化用。
  Stream<({double volume, bool muted})> get volumeChanges =>
      _volumeChanges.stream;

  /// 輸出裝置的清單與目前選的；平台不能選裝置時清單永遠是空的。
  OutputDeviceState get outputDeviceState =>
      (devices: _outputDevices, selected: _selectedOutputDevice);

  /// [outputDeviceState] 的變化：清單插拔、使用者選擇、記住的裝置套用、裝置
  /// 失敗改回系統預設。
  Stream<OutputDeviceState> get outputDeviceChanges =>
      _outputDeviceStates.stream;

  /// 使用者 seek 的目標位置，給持久化用。
  Stream<Duration> get seeks => _seeks.stream;

  /// 目前這首播到的位置：來源最後回報的；沒有來源（解析中、等重試、剛恢復）時是
  /// 下次開始的位置。
  Duration get position => _position;

  /// 啟動恢復後還沒播時，按播放要開始的位置（含恢復後先臨時播放、結束後停著的
  /// 情況）；已經開始播佇列的那一首、或那一首換掉了就是 `null`。播放列以它顯示
  /// 恢復的進度：進度 stream 留著上一個來源最後的回報。
  Duration? get restoredPosition => _restoredPosition;

  /// 目前（最近一次）開始的這首是啟動恢復後的第一次播放（播放歷史不記這一次，
  /// design §7.8）；之後換了別首就是 `false`。
  bool get startedFromRestore => _startedFromRestore;

  /// 每次「這一首算一次播放」（design §7.8）：換歌、臨時播放、前瞻接上、單曲循環的
  /// 每一圈，在它第一次出聲時發出。重試、換候選、暫停後繼續、seek、啟動恢復後的第一次
  /// 播放、臨時播放結束回到佇列的那首、「上一首」回到開頭都不發。給播放歷史的記錄者
  /// 聽，控制器不碰資料層。
  Stream<CountedPlay> get plays => _plays.stream;

  // ---- 佇列 -----------------------------------------------------------------

  /// 啟動時帶回上次的佇列、循環、隨機、音量與靜音（design §7.7）：狀態是
  /// `Idle`、不解析、不預取，按播放才開始，從 [position] 起。只在佇列還是空的、
  /// 什麼都還沒播時有作用，否則什麼都不做、回傳 `false`。
  bool restore({
    required List<TrackInfo> tracks,
    required int? currentIndex,
    required LoopMode loopMode,
    required bool shuffle,
    List<int>? shuffleOrder,
    required Duration position,
    required double volume,
    required bool muted,
  }) {
    final queue = _queue.state;
    if (queue.entries.isNotEmpty ||
        queue.temporary != null ||
        _state is! Idle) {
      return false;
    }
    _queue.restore(
      tracks: tracks,
      currentIndex: currentIndex,
      loopMode: loopMode,
      shuffle: shuffle,
      shuffleOrder: shuffleOrder,
    );
    _volume = volume.clamp(0, 1).toDouble();
    _muted = muted;
    unawaited(_session.setVolume(_muted ? 0 : _volume));
    _resumeAt = position;
    _restoredPosition = _queue.state.current == null ? null : position;
    _emitQueue();
    _log.info(
      'Playback restored',
      tag: _tag,
      fields: {
        'queueLength': tracks.length,
        'queueIndex': _queue.state.currentIndex,
        'positionMs': position.inMilliseconds,
        'loop': _queue.state.loopMode.name,
        'shuffle': _queue.state.shuffleEnabled,
        'muted': muted,
      },
    );
    return true;
  }

  /// 臨時播放 [track]（D1）：不放進佇列，播完或按上一首、下一首回到佇列進入
  /// 時的那一首。已經在臨時播放時只換曲目，回到的點不變。
  Future<void> playTemporary(TrackInfo track) {
    if (_queue.state.mode == QueueMode.queue) {
      _returnLoadsQueueTrack = switch (_state) {
        Idle() || Failed() => false,
        Loading() || Playing() || Paused() || Buffering() || Retrying() => true,
      };
    }
    final kept = switch ((_restoredPosition, _queue.state.current)) {
      (final position?, final current?)
          when _queue.state.mode == QueueMode.queue =>
        (position: position, key: current.key),
      _ => _keptRestored,
    };
    _queue.playTemporary(track, position: _position, playing: _wantsSound);
    _emitQueue();
    _consecutiveSkips = 0;
    _setPlayWhenReady(true);
    final started = _beginTrack();
    _keptRestored = kept;
    return started;
  }

  /// 加在佇列最後。會超過佇列上限就整批不加、發 [QueueFull]，回傳 `false`。
  /// 佇列原本是空的時第一首成為目前這首，但不開始播。
  bool addToQueue(List<TrackInfo> tracks) => _add(tracks, _queue.append);

  /// 下一首播放：排在目前這首（臨時播放中是回到的那一首）之後，接在之前連續
  /// 加入的後面。會超過上限就整批不加、發 [QueueFull]，回傳 `false`。
  bool playNext(List<TrackInfo> tracks) => _add(tracks, _queue.playNext);

  /// 從頭播佇列位置 [index] 的歌（在佇列中點選）；臨時播放就此結束。
  Future<void> jumpTo(int index) {
    final prepared = _session.takeLookAhead(index);
    _queue.jumpTo(index);
    _emitQueue();
    _consecutiveSkips = 0;
    _setPlayWhenReady(true);
    return _beginTrack(prepared: prepared);
  }

  /// 移除佇列位置 [index]。移除的是正在播的那一首時換到佇列的下一首，沒有下一
  /// 首就是前一首（`QueueModel.remove`；暫停中就載入後停著）；佇列因此空了就停
  /// 在 `Idle`。
  Future<void> removeAt(int index) {
    final before = _queue.state;
    final removesPlaying =
        before.mode == QueueMode.queue && index == before.currentIndex;
    _queue.remove(index);
    if (!removesPlaying) {
      _queueEdited();
      return Future.value();
    }
    _emitQueue();
    switch (_state) {
      case Idle() || Failed():
        _resumeAt = Duration.zero;
        return _stopWith(const Idle());
      case Loading() || Playing() || Paused() || Buffering() || Retrying():
        if (_queue.state.current == null) {
          _resumeAt = Duration.zero;
          return _stopWith(const Idle());
        }
        _consecutiveSkips = 0;
        return _beginTrack();
    }
  }

  /// 把佇列位置 [from] 的歌拖到 [to]。播的歌不變。
  void move(int from, int to) {
    _queue.move(from, to);
    _queueEdited();
  }

  /// 把佇列位置 [index] 的歌移到目前這首之後（接在連續「下一首播放」的後面），
  /// 隨機時下一首也是它（`QueueModel.moveToNext`）。目前這首不做事。
  void moveToNext(int index) {
    _queue.moveToNext(index);
    _queueEdited();
  }

  /// 清空佇列並停在 `Idle`（臨時播放也一起結束）。
  Future<void> clear() {
    _queue.clear();
    _emitQueue();
    _resumeAt = Duration.zero;
    return _stopWith(const Idle());
  }

  void setShuffle(bool enabled) {
    _queue.setShuffle(enabled);
    _queueEdited();
  }

  /// 循環依關閉 → 全部 → 單曲輪轉。
  void cycleLoopMode() {
    _queue.cycleLoopMode();
    _queueEdited();
  }

  // ---- 播放 -----------------------------------------------------------------

  Future<void> play() async {
    _setPlayWhenReady(true);
    switch (_state) {
      case Paused() || Loading() || Buffering():
        if (_session.hasSource) {
          await _session.play();
        } else if (_state is Paused) {
          // 等重試時被暫停：重新開始這一首。
          await _load(position: _resumeAt);
        }
      case Idle() || Failed():
        if (_queue.state.current == null) return;
        _consecutiveSkips = 0;
        // 啟動恢復後的第一次播放從恢復的位置開始，之後都從頭。
        final restored = _restoredPosition;
        await _beginTrack(
          position: restored ?? Duration.zero,
          fromRestore: restored != null,
        );
      case Playing() || Retrying():
        return;
    }
  }

  Future<void> pause() async {
    _setPlayWhenReady(false);
    switch (_state) {
      case Playing() || Buffering() || Loading():
        if (_session.hasSource) await _session.pause();
      case Retrying():
        _cancelRetry();
        _setState(const Paused());
      case Paused() || Idle() || Failed():
        return;
    }
  }

  /// 下一首（`QueueState.hasNext` 為假就不動）。臨時播放中是回到佇列；佇列
  /// 是空的時就此停在 `Idle`。
  Future<void> next() {
    if (!_queue.state.hasNext) return Future.value();
    _consecutiveSkips = 0;
    return _moveNext();
  }

  /// 上一首：播超過 3 秒（`QueueModel.restartThreshold`）回到這首的開頭，否則
  /// 往前一首；前面沒有歌也回到開頭。臨時播放中是回到佇列。
  Future<void> previous() {
    final step = _queue.movePrevious(position: _position);
    if (step is MovedToTrack || step is ReturnedToQueue) {
      _emitQueue();
      _consecutiveSkips = 0;
    }
    return _follow(step);
  }

  Future<void> seek(Duration position) async {
    if (!_seeks.isClosed) _seeks.add(position);
    if (!_session.hasSource) {
      _resumeAt = position;
      if (_restoredPosition != null) _restoredPosition = position;
      return;
    }
    await _session.seek(position);
  }

  // ---- 音量、速度、輸出裝置 ------------------------------------------------

  /// 設定音量（夾到 0–1），並取消靜音（舊版拖音量條就是取消靜音）。後端換歌
  /// 後維持。
  Future<void> setVolume(double volume) {
    _volume = volume.clamp(0, 1).toDouble();
    _muted = false;
    _emitVolume();
    return _session.setVolume(_volume);
  }

  /// 切換靜音：靜音時後端的音量是 0，[volume] 不變，取消靜音回到它（design
  /// §3.3）。
  Future<void> toggleMute() {
    _muted = !_muted;
    _emitVolume();
    return _session.setVolume(_muted ? 0 : _volume);
  }

  /// 設定速度：後端夾到 0.5–2.0，換歌後維持；不持久化（ADR 0018 §決定 10）。
  Future<void> setSpeed(double speed) {
    _speed = clampSpeed(speed);
    if (!_speedChanges.isClosed) _speedChanges.add(_speed);
    return _session.setSpeed(_speed);
  }

  /// 選音訊輸出裝置並記成偏好；`null` 是系統預設（清掉偏好）。不能選裝置的
  /// 平台（`PlaybackSupport.outputDeviceSelection` 為假）什麼都不做。
  Future<void> selectOutputDevice(OutputDevice? device) async {
    if (!_session.selectsOutputDevice) return;
    _outputDeviceChosen = true;
    _log.info(
      'Output device selected',
      tag: _tag,
      fields: {'device': device?.id ?? 'auto'},
    );
    _selectedOutputDevice = device;
    _emitOutputDevices();
    await _session.selectOutputDevice(device);
    await _saveOutputDevice(device);
  }

  /// 裝置清單第一次就緒時套用記住的裝置（舊版 `audio_provider.dart` 的
  /// `_restorePreferredAudioDevice`）：只套用這一次，之後插拔造成的清單變動不
  /// 蓋掉使用者當下的選擇；不在清單裡就用系統預設，偏好不清掉（插回來時還要
  /// 它）。
  Future<void> _onOutputDevices(List<OutputDevice> devices) async {
    _outputDevices = devices;
    _emitOutputDevices();
    if (_outputDeviceListSeen || devices.isEmpty) return;
    _outputDeviceListSeen = true;
    if (_outputDeviceChosen) return;
    final String? preferred;
    try {
      preferred = await _preferredOutputDevice();
    } on Object catch (error, stackTrace) {
      _log.warning(
        'Failed to read the preferred output device',
        tag: _tag,
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }
    // 讀設定的期間使用者自己選了：以使用者的為準。
    if (preferred == null || _outputDeviceChosen) return;
    final match = devices.where((device) => device.id == preferred);
    if (match.isEmpty) {
      _log.info(
        'Preferred output device is not connected',
        tag: _tag,
        fields: {'device': preferred},
      );
      return;
    }
    _log.info(
      'Preferred output device restored',
      tag: _tag,
      fields: {'device': preferred},
    );
    _selectedOutputDevice = match.first;
    _emitOutputDevices();
    await _session.selectOutputDevice(match.first);
  }

  Future<void> dispose() async {
    _cancelRetry();
    _stallTimer?.cancel();
    await _outputDeviceLists?.cancel();
    // dispose 的同步部分先換一代：還在進行的解析回來時不再開流或設定前瞻。
    await _session.dispose();
    await _sessionEvents.cancel();
    await _progressEvents.cancel();
    await _networkChanges.cancel();
    await _states.close();
    await _queueStates.close();
    await _events.close();
    await _previews.close();
    await _interruptionChanges.close();
    await _volumeChanges.close();
    await _speedChanges.close();
    await _outputDeviceStates.close();
    await _seeks.close();
    await _plays.close();
  }

  // ---- 換曲目 ---------------------------------------------------------------

  /// 往下一首（按下一首、播完、被跳過）：佇列的前瞻解析結果沿用。
  Future<void> _moveNext() {
    final next = _queue.next;
    final prepared = next == null ? null : _session.takeLookAhead(next.index);
    final step = _queue.moveNext();
    _emitQueue();
    return _follow(step, prepared: prepared);
  }

  /// 照佇列換曲目的結果開始播。
  Future<void> _follow(QueueStep step, {ResolvedStream? prepared}) =>
      switch (step) {
        MovedToTrack() => _beginTrack(prepared: prepared),
        RestartTrack() => seek(Duration.zero),
        ReturnedToQueue(:final snapshot) => _returnToQueue(snapshot),
        QueueUnchanged() => Future.value(),
      };

  /// 臨時播放結束、回到佇列的那一首（design §7.2）：「記住播放位置」開著時從
  /// 快照的位置倒退設定的秒數，否則從頭；原本在播才自動播。佇列是空的，或進入
  /// 時那一首沒有載入，就停在 `Idle`（播放列顯示那一首）。
  Future<void> _returnToQueue(QueueSnapshot snapshot) {
    final track = _queue.state.current;
    if (track == null || !_returnLoadsQueueTrack) {
      _log.info(
        'Temporary play ended; the queue stays idle',
        tag: _tag,
        fields: {'track': '${track?.key}'},
      );
      // 恢復後還沒播就臨時播放：佇列那一首仍是恢復的那一首時，按播放還是從恢復的
      // 位置開始。
      final kept = _keptRestored;
      _resumeAt = Duration.zero;
      final stopped = _stopWith(const Idle());
      if (kept != null && track != null && kept.key == track.key) {
        _restoredPosition = kept.position;
        _resumeAt = kept.position;
      }
      return stopped;
    }
    final settings = _temporaryReturnSettings();
    final position = snapshot.resumeAt(
      rememberPosition: settings.rememberPosition,
      rewind: settings.rewind,
    );
    _log.info(
      'Temporary play ended; returning to the queue',
      tag: _tag,
      fields: {
        'track': '${track.key}',
        'snapshotPositionMs': snapshot.position.inMilliseconds,
        'resumeAtMs': position.inMilliseconds,
        'play': snapshot.playing,
      },
    );
    _setPlayWhenReady(snapshot.playing);
    // 回到佇列是續播，不是新的一次播放。
    return _beginTrack(position: position, countsAsPlay: false);
  }

  bool _add(List<TrackInfo> tracks, bool Function(List<TrackInfo>) add) {
    if (!add(tracks)) {
      _log.info(
        'Queue full; nothing added',
        tag: _tag,
        fields: {
          'adding': tracks.length,
          'queueLength': _queue.state.entries.length,
        },
      );
      _emitEvent(QueueFull(limit: QueueModel.maxLength));
      return false;
    }
    _queueEdited();
    return true;
  }

  // ---- 開始一首 -------------------------------------------------------------

  /// 開始目前這首（[QueueState.current]），從 [position] 起：重設這首的恢復
  /// 計數。
  Future<void> _beginTrack({
    ResolvedStream? prepared,
    Duration position = Duration.zero,
    bool fromRestore = false,
    bool countsAsPlay = true,
  }) {
    _restoredPosition = null;
    _keptRestored = null;
    _startedFromRestore = fromRestore;
    _countPlayOnAudible = countsAsPlay && !fromRestore;
    _resetTrackCounters();
    return _load(prepared: prepared, position: position);
  }

  /// 換了一首：這首的重試、重新解析、換候選都從頭算。
  void _resetTrackCounters() {
    _retries = 0;
    _reResolves = 0;
    _candidateSwitched = false;
  }

  /// 解析（或用 [prepared]）並交給後端，從 [position] 開始。插件說只有試聽
  /// 片段時，依「跳過試聽片段」跳過或照播並標「試聽」。
  Future<void> _load({
    Duration position = Duration.zero,
    ResolvedStream? prepared,
  }) async {
    final track = _queue.state.current;
    if (track == null) return;
    final key = track.key;
    final generation = _session.beginRequest(key, position: position);
    _cancelRetry();
    _resumeAt = position;
    _playedSinceLoad = Duration.zero;
    _lastPosition = null;
    if (_previewTrack != key) _setPreview(null);
    _setState(const Loading());
    _log.info(
      'Track requested',
      tag: _tag,
      fields: {
        'track': '$key',
        'queueIndex': _queue.state.currentIndex,
        if (_queue.state.mode == QueueMode.temporary) 'temporary': true,
        if (_startedFromRestore) 'restored': true,
      },
    );

    final ResolvedStream stream;
    if (prepared != null && _session.isFresh(prepared)) {
      stream = prepared;
    } else {
      if (prepared != null) {
        _log.info(
          'Look-ahead expired; resolving again',
          tag: _tag,
          fields: {'track': '$key'},
        );
      }
      try {
        stream = await _session.resolve(key);
      } on AppError catch (error) {
        if (generation != _session.generation) return;
        _log.report('Stream resolution failed', error, tag: _tag);
        return _recover(ResolveFailed(error), error, position);
      }
      if (generation != _session.generation) return;
    }
    if (stream.previewOnly) {
      final error = Unavailable(
        reason: UnavailableReason.previewOnly,
        pluginId: key.sourceTypeId,
      );
      final action = _decide(const PreviewOnly(), error);
      if (action is! PlayAsPreview) return _apply(action, error, _resumeAt);
      // 同一首重播（單曲循環、重試、重新解析）不再提示。
      if (_previewTrack != key) _emitEvent(PreviewPlaying(track: track));
      _setPreview(key);
    } else {
      _setPreview(null);
    }
    // 解析期間的 seek 記在 _resumeAt。
    await _session.open(stream, position: _resumeAt, play: _playWhenReady);
  }

  // ---- 後端回報 -------------------------------------------------------------

  void _onSessionEvent(SessionEvent event) {
    final action = routePlaybackEvent(
      event,
      PlaybackSnapshot(
        generation: _session.generation,
        playWhenReady: _playWhenReady,
        hasNext: _queue.state.hasNext,
        repeatsTrack: _queue.state.loopMode == LoopMode.one,
        resumeAt: _resumeAt,
        wantsSound: _wantsSound,
        pausedByInterruption: _pausedByInterruption,
      ),
    );
    switch (action) {
      case IgnoreEvent():
        return;
      case PauseForInterruption():
        _log.info('Audio interrupted; pausing', tag: _tag);
        unawaited(pause());
        // pause 清掉了它（當成使用者的暫停）；這次是中斷造成的，結束時續播。
        _pausedByInterruption = true;
        _announceInterruption();
      case ResumeAfterInterruption():
        _log.info('Audio interruption ended; resuming', tag: _tag);
        // play() 清掉 _pausedByInterruption；後端報出播放之前仍算中斷。
        _resumingFromInterruption = true;
        unawaited(play());
      case PauseWithoutResuming():
        _log.info(switch (event) {
          HeadphonesUnplugged() => 'Headphones unplugged; pausing',
          AudioInterrupted() => 'Audio focus lost; pausing',
          _ => 'Audio interruption ended; staying paused',
        }, tag: _tag);
        unawaited(pause());
      case PauseForOutputFailure():
        _pauseForOutputFailure();
      case ShowState(:final state):
        _setState(state);
      case MarkReady(:final playing, :final first):
        _session.markReady();
        _setState(playing ? const Playing() : const Paused());
        if (playing) {
          _consecutiveSkips = 0;
          _countPlay();
        }
        if (first) unawaited(_session.prepareLookAhead(_nextTrack));
      case AdoptLookAhead():
        // 單曲循環的前瞻是同一首：佇列不動。佇列的前瞻一定是佇列當下的下一首
        // （每次編輯都重新指定），臨時播放中沒有佇列的前瞻。
        if (!_session.adoptLookAhead(action)) {
          _queue.moveNext();
          _emitQueue();
          // 試聽片段不當前瞻（PlaybackSession），接上的一定不是試聽。
          _setPreview(null);
        }
        _startedFromRestore = false;
        // 引擎接上時前一首已經出過聲，接上的這首（或單曲循環的下一圈）直接算。
        _countPlayOnAudible = true;
        _countPlay();
        _resetTrackCounters();
        _playedSinceLoad = Duration.zero;
        _lastPosition = null;
        unawaited(_session.prepareLookAhead(_nextTrack));
      case RepeatTrack():
        // 單曲循環而前瞻沒來得及接上：從頭再播，網址從快取拿。
        unawaited(_beginTrack());
      case PlayNextTrack():
        // 前瞻沒來得及接上（例如還在解析）：照一般的下一首開始；臨時播放中是
        // 回到佇列。路由器只在 hasNext 時給這個動作。
        unawaited(_moveNext());
      case FinishQueue():
        _log.info('Queue finished', tag: _tag);
        _session.release();
        _resumeAt = Duration.zero;
        _setPreview(null);
        _setState(const Idle());
      case Recover(:final failure, :final error, :final position):
        if (action.endedEarly) {
          _log.report('Stream ended early', error, tag: _tag);
        }
        // 串流本身失敗了：網址不再從快取拿，重試與之後再播都重新解析。
        _session.invalidateCurrentStream();
        unawaited(_recover(failure, error, position));
    }
  }

  /// 位置前進：在 [Playing] 中累計，到 [retryResetAfter] 時重試計數歸零（一首
  /// 正常播放 10 秒，ADR 0018 §決定 7）。不開計時器。
  void _onProgress(PlaybackProgress progress) {
    final last = _lastPosition;
    _lastPosition = progress.position;
    if (last == null || _state is! Playing || _retries == 0) return;
    final step = progress.position - last;
    if (step <= Duration.zero || step > _maxProgressStep) return;
    _playedSinceLoad += step;
    if (_playedSinceLoad < retryResetAfter) return;
    _log.info(
      'Retry count reset after normal playback',
      tag: _tag,
      fields: {'track': '${_queue.state.current?.key}', 'retries': _retries},
    );
    _retries = 0;
  }

  // ---- 恢復 -----------------------------------------------------------------

  Future<void> _recover(
    PlaybackFailure failure,
    AppError error,
    Duration position,
  ) => _apply(_decide(failure, error), error, position);

  /// 以目前的計數、網路狀態與設定問 [decideRecovery]，記一筆 log。
  RecoveryAction _decide(PlaybackFailure failure, AppError error) {
    final network = _networkStatus();
    final action = decideRecovery(
      failure,
      network: network,
      skipPreviewClips: _skipPreviewClips(),
      retries: _retries,
      reResolves: _reResolves,
      candidateSwitched: _candidateSwitched,
      hasOtherCandidate: _session.hasOtherCandidate,
      consecutiveSkips: _consecutiveSkips,
      // 臨時曲目不在佇列裡，但也是這一輪連著播不了的一首：不加它的話，佇列
      // 只有一首時臨時曲目一跳過就停下，回不到佇列。
      queueLength:
          _queue.state.entries.length +
          (_queue.state.mode == QueueMode.temporary ? 1 : 0),
    );
    _log.info(
      'Playback recovery',
      tag: _tag,
      fields: {
        'track': '${_queue.state.current?.key}',
        'failure': switch (failure) {
          ResolveFailed() => 'resolve',
          PreviewOnly() => 'previewOnly',
          StreamUnopenable() => 'open',
          StreamInterrupted() => 'interrupted',
          BufferingStalled() => 'bufferingStalled',
        },
        'error': error.typeName,
        if (failure case StreamUnopenable(:final httpStatus?))
          'httpStatus': httpStatus,
        if (network != NetworkStatus.online) 'network': network.name,
        'action': switch (action) {
          RetryAfter() => 'retry',
          WaitForNetwork() => 'waitForNetwork',
          ReResolve() => 'reResolve',
          TryNextCandidate() => 'nextCandidate',
          PlayAsPreview() => 'playAsPreview',
          SkipTrack() => 'skip',
          StopPlayback() => 'stop',
        },
      },
    );
    return action;
  }

  Future<void> _apply(
    RecoveryAction action,
    AppError error,
    Duration position,
  ) async {
    switch (action) {
      case RetryAfter(:final delay, :final attempt):
        _retries++;
        final generation = _session.newGeneration();
        _resumeAt = position;
        _setState(Retrying(error: error, attempt: attempt, delay: delay));
        _retryTimer = Timer(delay, () {
          _retryTimer = null;
          if (generation == _session.generation) {
            // 等待期間的 seek 記在 _resumeAt。
            unawaited(_load(position: _resumeAt));
          }
        });
      case WaitForNetwork():
        // 不計次數、不跳過、不提示（全域離線提示已經在畫面上，design §5.3）。
        final generation = _session.newGeneration();
        _resumeAt = position;
        _waitingForNetwork = generation;
        _setState(Retrying(error: error, attempt: 0, delay: null));
        await _session.stop();
      case ReResolve():
        // 網址快取裡的那一筆已經作廢（Recover、緩衝飢餓），_load 會再問插件。
        _reResolves++;
        await _load(position: position);
      case TryNextCandidate():
        _candidateSwitched = true;
        await _session.openNextCandidate(
          position: position,
          play: _playWhenReady,
        );
      case PlayAsPreview():
        // 只有 _load 遇到試聽片段時會得到它，照播在那裡。
        return;
      case SkipTrack():
        _consecutiveSkips++;
        final skipped = _queue.state.current;
        // 臨時播放中是回到佇列（佇列是空的時沒有可去的地方，停下）。
        if (_queue.next == null || skipped == null) {
          return _stopFailed(error, failedInARow: _consecutiveSkips);
        }
        _emitEvent(TrackSkipped(error: error, track: skipped));
        await _moveNext();
      case StopPlayback():
        await _stopFailed(error, failedInARow: _consecutiveSkips + 1);
    }
  }

  /// 輸出裝置開不起來（design §7.6）：暫停並提示，不跳過。來源放掉、記下位置
  /// （之後才到的提前結束、錯誤屬於舊的一代，丟掉；已經排好的重試也取消），按
  /// 播放時從這裡重新開流：mpv 在裝置失敗後不會自己再開輸出。停著（`Idle`、
  /// `Failed`）時只提示。
  ///
  /// 失敗的是選過的裝置時，這次執行改用系統預設輸出（擁有者 2026-10-07），按播放
  /// 才不會再撞同一個裝置；記住的偏好不清掉，下次啟動或裝置清單再出現它時照常
  /// 套用。
  void _pauseForOutputFailure() {
    final failedDevice = _session.selectsOutputDevice
        ? _selectedOutputDevice
        : null;
    _emitEvent(OutputDeviceFailed(fellBack: failedDevice != null));
    _clearInterruption();
    var stopped = Future<void>.value();
    switch (_state) {
      case Idle() || Failed():
        break;
      case Loading() || Playing() || Paused() || Buffering() || Retrying():
        final position = _position;
        _log.info(
          'Output device failed; pausing',
          tag: _tag,
          fields: {
            'track': '${_queue.state.current?.key}',
            'positionMs': position.inMilliseconds,
          },
        );
        _playWhenReady = false;
        _session.newGeneration();
        _cancelRetry();
        _resumeAt = position;
        _setState(const Paused());
        stopped = _session.stop();
    }
    if (failedDevice != null) {
      unawaited(_useSystemOutput(failedDevice, after: stopped));
    }
  }

  /// 來源停下之後把輸出改回系統預設（不寫偏好）。
  Future<void> _useSystemOutput(
    OutputDevice failed, {
    required Future<void> after,
  }) async {
    _selectedOutputDevice = null;
    _emitOutputDevices();
    try {
      await after;
      await _session.selectOutputDevice(null);
      _log.info(
        'Output device failed; using the system default',
        tag: _tag,
        fields: {'device': failed.id},
      );
    } on Object catch (error, stackTrace) {
      _log.warning(
        'Failed to switch to the system default output',
        tag: _tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 停在 [Failed] 並發 [PlaybackStopped]（外殼提示一次）。
  Future<void> _stopFailed(AppError error, {required int failedInARow}) {
    final track = _queue.state.current;
    if (track != null) {
      _emitEvent(
        PlaybackStopped(error: error, track: track, failedInARow: failedInARow),
      );
    }
    return _stopWith(Failed(error));
  }

  /// 網路回到 `online`：在等網路的那首立刻從原位置重試（重試計數不變）。
  void _onNetworkStatus(NetworkStatus status) {
    final waiting = _waitingForNetwork;
    if (status != NetworkStatus.online || waiting == null) return;
    _waitingForNetwork = null;
    if (waiting != _session.generation) return;
    _log.info(
      'Network is back; retrying',
      tag: _tag,
      fields: {'track': '${_queue.state.current?.key}'},
    );
    unawaited(_load(position: _resumeAt));
  }

  /// 緩衝飢餓（[bufferingStallTimeout]）：作廢網址、交給 [decideRecovery]。
  void _onBufferingStalled() {
    final track = _queue.state.current;
    if (track == null) return;
    _log.warning(
      'Buffering stalled',
      tag: _tag,
      fields: {
        'track': '${track.key}',
        'seconds': bufferingStallTimeout.inSeconds,
      },
    );
    final position = _position;
    _session.invalidateCurrentStream();
    unawaited(
      _recover(
        const BufferingStalled(),
        NetworkError(pluginId: track.sourceTypeId),
        position,
      ),
    );
  }

  Future<void> _stopWith(PlaybackState state) async {
    _restoredPosition = null;
    _keptRestored = null;
    _clearInterruption();
    _session.newGeneration();
    _cancelRetry();
    _countPlayOnAudible = false;
    _setPreview(null);
    _setState(state);
    await _session.stop();
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _waitingForNetwork = null;
  }

  // ---- 輸出 -----------------------------------------------------------------

  void _setState(PlaybackState state) {
    // 沒有欄位的狀態是 const 單例；Retrying、Failed 每次都是新的。
    if (identical(state, _state)) return;
    _state = state;
    if (state is! Paused && _resumingFromInterruption) {
      _resumingFromInterruption = false;
      _announceInterruption();
    }
    _watchBuffering(state);
    _log.debug(
      'Playback state',
      tag: _tag,
      fields: {
        'state': switch (state) {
          Idle() => 'idle',
          Loading() => 'loading',
          Playing() => 'playing',
          Paused() => 'paused',
          Buffering() => 'buffering',
          Retrying(waitingForNetwork: true) => 'waitingForNetwork',
          Retrying() => 'retrying',
          Failed() => 'failed',
        },
      },
    );
    if (!_states.isClosed) _states.add(state);
  }

  /// 進 [Buffering] 時開緩衝飢餓的計時，離開時取消。
  void _watchBuffering(PlaybackState state) {
    if (state is! Buffering) {
      _stallTimer?.cancel();
      _stallTimer = null;
      return;
    }
    if (_stallTimer != null) return;
    final generation = _session.generation;
    _stallTimer = Timer(bufferingStallTimeout, () {
      _stallTimer = null;
      if (generation == _session.generation && _state is Buffering) {
        _onBufferingStalled();
      }
    });
  }

  /// 使用者（或回到佇列的快照）決定要不要出聲：之後的暫停不再是中斷造成的。
  void _setPlayWhenReady(bool value) {
    _playWhenReady = value;
    _pausedByInterruption = false;
    // 中斷結束的續播（value 為真）要維持；使用者再暫停就不續了。
    if (!value) _resumingFromInterruption = false;
    _announceInterruption();
  }

  void _clearInterruption() {
    _pausedByInterruption = false;
    _resumingFromInterruption = false;
    _announceInterruption();
  }

  void _announceInterruption() {
    final now = pausedByInterruption;
    if (now == _interruptionAnnounced) return;
    _interruptionAnnounced = now;
    if (!_interruptionChanges.isClosed) _interruptionChanges.add(now);
  }

  void _setPreview(TrackKeyParts? track) {
    final was = previewing;
    _previewTrack = track;
    if (previewing != was && !_previews.isClosed) _previews.add(previewing);
  }

  void _emitOutputDevices() {
    if (!_outputDeviceStates.isClosed) {
      _outputDeviceStates.add(outputDeviceState);
    }
  }

  void _emitVolume() {
    if (!_volumeChanges.isClosed) {
      _volumeChanges.add((volume: _volume, muted: _muted));
    }
  }

  /// 這一次開始還沒算過、而且現在出聲了：發一次 [plays]。
  void _countPlay() {
    final track = _queue.state.current;
    if (!_countPlayOnAudible || track == null) return;
    _countPlayOnAudible = false;
    if (!_plays.isClosed) _plays.add((track: track, at: clock.now()));
  }

  void _emitEvent(PlaybackEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  /// 目前這首播到的位置：來源最後回報的；沒有來源（解析中、等重試）時是下次
  /// 開始的位置。
  Duration get _position => _session.position ?? _resumeAt;

  /// 使用者這時要的是出聲（在播、載入中、等重試，而且沒按暫停）。
  bool get _wantsSound =>
      _playWhenReady &&
      switch (_state) {
        Loading() || Playing() || Buffering() || Retrying() => true,
        Idle() || Paused() || Failed() => false,
      };

  /// 前瞻要接的曲目：單曲循環是目前這首（佇列不動），臨時播放中沒有，否則是
  /// 佇列的下一首。
  NextTrack? _nextTrack() {
    final queue = _queue.state;
    final current = queue.current;
    if (current == null) return null;
    if (queue.loopMode == LoopMode.one) {
      return (index: null, track: current.key);
    }
    if (queue.mode == QueueMode.temporary) return null;
    return switch (_queue.next) {
      (:final index, :final track)? => (index: index, track: track.key),
      null => null,
    };
  }

  /// 佇列編輯過：發出新的佇列，前瞻改指新的下一首。
  void _queueEdited() {
    _emitQueue();
    unawaited(_session.retargetLookAhead(_nextTrack));
  }

  void _emitQueue() {
    if (!_queueStates.isClosed) _queueStates.add(_queue.state);
  }
}
