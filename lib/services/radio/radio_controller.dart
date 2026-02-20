import 'dart:async';
import 'dart:io';

import 'package:fmp/i18n/strings.g.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/radio_station.dart';
import '../../data/models/track.dart'; // for SourceType
import '../../data/repositories/radio_repository.dart';
import '../../main.dart' show audioHandler, windowsSmtcHandler;
import '../../providers/database_provider.dart';
import '../audio/audio_service.dart';
import '../audio/audio_types.dart';
import '../audio/audio_provider.dart';
import 'radio_source.dart';
import 'radio_refresh_service.dart';

/// 電台播放狀態
class RadioState {
  /// 所有電台列表
  final List<RadioStation> stations;

  /// 各電台的直播狀態 (stationId -> isLive)
  final Map<int, bool> liveStatus;

  /// 是否正在刷新直播狀態
  final bool isRefreshingStatus;

  /// 正在播放的電台
  final RadioStation? currentStation;

  /// 是否正在播放
  final bool isPlaying;

  /// 是否正在載入
  final bool isLoading;

  /// 正在載入的電台 ID（用於顯示正確的載入指示器）
  final int? loadingStationId;

  /// 是否正在緩衝
  final bool isBuffering;

  /// 錯誤訊息
  final String? error;

  /// 即時資訊：觀眾數
  final int? viewerCount;

  /// 即時資訊：開播時間
  final DateTime? liveStartTime;

  /// 已播放時長（從開始播放到現在）
  final Duration playDuration;

  /// 重連次數
  final int reconnectAttempts;

  /// 重連狀態訊息
  final String? reconnectMessage;

  /// 直播間簡介
  final String? description;

  /// 直播間標籤
  final String? tags;

  /// 主播公告
  final String? announcement;

  /// 分區名稱
  final String? areaName;

  const RadioState({
    this.stations = const [],
    this.liveStatus = const {},
    this.isRefreshingStatus = false,
    this.currentStation,
    this.isPlaying = false,
    this.isLoading = false,
    this.loadingStationId,
    this.isBuffering = false,
    this.error,
    this.viewerCount,
    this.liveStartTime,
    this.playDuration = Duration.zero,
    this.reconnectAttempts = 0,
    this.reconnectMessage,
    this.description,
    this.tags,
    this.announcement,
    this.areaName,
  });

  /// 是否有電台在播放
  bool get hasCurrentStation => currentStation != null;

  /// 是否正在重連
  bool get isReconnecting => reconnectAttempts > 0;

  /// 直播時長（從開播到現在）
  Duration? get liveDuration {
    if (liveStartTime == null) return null;
    return DateTime.now().difference(liveStartTime!);
  }

  /// 檢查電台是否正在直播
  bool isStationLive(int stationId) => liveStatus[stationId] ?? false;

  RadioState copyWith({
    List<RadioStation>? stations,
    Map<int, bool>? liveStatus,
    bool? isRefreshingStatus,
    RadioStation? currentStation,
    bool clearCurrentStation = false,
    bool? isPlaying,
    bool? isLoading,
    int? loadingStationId,
    bool clearLoadingStationId = false,
    bool? isBuffering,
    String? error,
    bool clearError = false,
    int? viewerCount,
    bool clearViewerCount = false,
    DateTime? liveStartTime,
    bool clearLiveStartTime = false,
    Duration? playDuration,
    int? reconnectAttempts,
    String? reconnectMessage,
    bool clearReconnectMessage = false,
    String? description,
    bool clearDescription = false,
    String? tags,
    bool clearTags = false,
    String? announcement,
    bool clearAnnouncement = false,
    String? areaName,
    bool clearAreaName = false,
  }) {
    return RadioState(
      stations: stations ?? this.stations,
      liveStatus: liveStatus ?? this.liveStatus,
      isRefreshingStatus: isRefreshingStatus ?? this.isRefreshingStatus,
      currentStation:
          clearCurrentStation ? null : (currentStation ?? this.currentStation),
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      loadingStationId: clearLoadingStationId
          ? null
          : (loadingStationId ?? this.loadingStationId),
      isBuffering: isBuffering ?? this.isBuffering,
      error: clearError ? null : (error ?? this.error),
      viewerCount:
          clearViewerCount ? null : (viewerCount ?? this.viewerCount),
      liveStartTime:
          clearLiveStartTime ? null : (liveStartTime ?? this.liveStartTime),
      playDuration: playDuration ?? this.playDuration,
      reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
      reconnectMessage: clearReconnectMessage
          ? null
          : (reconnectMessage ?? this.reconnectMessage),
      description:
          clearDescription ? null : (description ?? this.description),
      tags: clearTags ? null : (tags ?? this.tags),
      announcement:
          clearAnnouncement ? null : (announcement ?? this.announcement),
      areaName: clearAreaName ? null : (areaName ?? this.areaName),
    );
  }
}

/// 電台控制器
class RadioController extends StateNotifier<RadioState> with Logging {
  final Ref _ref;
  final RadioRepository _repository;
  final RadioSource _radioSource;
  final FmpAudioService _audioService;

  // 定時器
  Timer? _playDurationTimer;
  Timer? _infoRefreshTimer;

  // 播放請求 ID（用於取消過期請求）
  int _playRequestId = 0;

  // 訂閱
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _stationsSubscription;
  StreamSubscription? _refreshServiceSubscription;

  // 重連配置
  static const int _maxReconnectAttempts = RadioReconnectConfig.maxAttempts;
  static const List<Duration> _reconnectDelays = RadioReconnectConfig.delays;

  // 播放開始時間（用於計算已播放時長）
  DateTime? _playStartTime;

  // 當前流地址（用於重連）
  LiveStreamInfo? _currentStreamInfo;

  /// 正常構造函數
  RadioController(
    this._ref,
    this._repository,
    this._radioSource,
    this._audioService,
  ) : super(const RadioState()) {
    _initialize();
    _setupMutualExclusion();
  }

  /// 用於數據庫加載中的構造函數（返回空狀態）
  RadioController.forLoading()
      : _ref = _DummyRef(),
        _repository = _DummyRadioRepository(),
        _radioSource = RadioSource(),
        _audioService = _DummyAudioService(),
        super(const RadioState()) {
    // 不初始化，等待真正的 controller
  }

  Future<void> _initialize() async {
    // 設置 RadioRefreshService 的 Repository
    RadioRefreshService.instance.setRepository(_repository);

    // 載入電台列表
    await _loadStations();

    // 監聽電台列表變化
    _stationsSubscription = _repository.watchAll().listen((stations) {
      logInfo('watchAll 觸發: ${stations.length} 個電台');
      state = state.copyWith(stations: stations);
    });

    // 監聽播放器狀態
    _playerStateSubscription = _audioService.playerStateStream.listen(
      _onPlayerStateChanged,
    );

    // 監聽 RadioRefreshService 的狀態變化
    _refreshServiceSubscription = RadioRefreshService.instance.stateChanges.listen((_) {
      _syncLiveStatusFromRefreshService();
    });

    // 初始化時同步一次直播狀態
    _syncLiveStatusFromRefreshService();

    // 設置 SMTC 回調（僅 Windows）
    _setupSmtcCallbacks();
  }

  /// 設置 Windows SMTC 回調
  void _setupSmtcCallbacks() {
    if (!Platform.isWindows) return;

    // 注意：電台不需要上一首/下一首功能
    // 這些回調會在電台播放時覆蓋音樂播放的回調
  }

  /// 更新 Android 通知欄顯示當前電台
  void _updateAudioHandler(RadioStation station) {
    if (!Platform.isAndroid) return;

    audioHandler.onPlay = resume;
    audioHandler.onPause = pause;
    audioHandler.onStop = stop;
    audioHandler.onSkipToNext = null;
    audioHandler.onSkipToPrevious = null;
    audioHandler.onSeek = null;

    audioHandler.updateCurrentRadioStation(station);
    audioHandler.updatePlaybackState(
      isPlaying: true,
      position: Duration.zero,
      bufferedPosition: Duration.zero,
      processingState: FmpAudioProcessingState.ready,
    );
  }

  /// 清除 Android 通知欄狀態
  void _clearAudioHandler() {
    if (!Platform.isAndroid) return;

    audioHandler.updatePlaybackState(
      isPlaying: false,
      position: Duration.zero,
      bufferedPosition: Duration.zero,
      processingState: FmpAudioProcessingState.idle,
    );
  }

  /// 更新 SMTC 顯示當前電台（僅 Windows）
  void _updateSmtc(RadioStation station) {
    if (!Platform.isWindows) return;

    // 設置電台的 SMTC 回調
    windowsSmtcHandler.onPlay = resume;
    windowsSmtcHandler.onPause = pause;
    windowsSmtcHandler.onStop = stop;
    // 電台不需要上一首/下一首
    windowsSmtcHandler.onSkipToNext = null;
    windowsSmtcHandler.onSkipToPrevious = null;
    windowsSmtcHandler.onSeek = null;

    // 更新元數據和播放狀態
    windowsSmtcHandler.updateCurrentRadioStation(station);
    windowsSmtcHandler.updateRadioPlaybackState(isPlaying: true);
  }

  /// 清除 SMTC 狀態（僅 Windows）
  void _clearSmtc() {
    if (!Platform.isWindows) return;

    windowsSmtcHandler.setStoppedState();
  }

  /// 設置互斥機制：音樂播放時自動停止電台
  void _setupMutualExclusion() {
    try {
      final audioController = _ref.read(audioControllerProvider.notifier);
      audioController.onPlaybackStarting = () async {
        if (state.hasCurrentStation) {
          await stop();
        }
      };
      // 讓 AudioController 知道電台是否正在播放，避免電台斷流時誤觸發隊列播放
      audioController.isRadioPlaying = () => state.hasCurrentStation;
    } catch (e) {
      // AudioController 可能尚未初始化
    }
  }

  /// 載入電台列表
  Future<void> _loadStations() async {
    final stations = await _repository.getAll();
    logInfo('載入 ${stations.length} 個電台');
    state = state.copyWith(stations: stations);
  }

  /// 檢查請求是否已被取代
  bool _isSuperseded(int requestId) => requestId != _playRequestId;

  /// 播放電台（帶自動重試）
  Future<void> play(RadioStation station, {bool isRetry = false}) async {
    // 增加請求 ID，取消之前的請求
    final requestId = ++_playRequestId;

    // 立即更新 UI 顯示新電台（迷你播放器和詳情面板會立即切換）
    state = state.copyWith(
      currentStation: station,
      isLoading: true,
      loadingStationId: station.id,
      isPlaying: false,
      error: null,
      clearError: true,
      reconnectAttempts: 0,
      clearReconnectMessage: true,
      // 清除舊電台的資訊
      clearViewerCount: true,
      clearLiveStartTime: true,
      clearDescription: true,
      clearTags: true,
      clearAnnouncement: true,
      clearAreaName: true,
      playDuration: Duration.zero,
    );

    try {
      // 互斥：先停止音樂播放
      await _pauseMusicPlayback();
      if (_isSuperseded(requestId)) return;

      // 獲取流地址
      final streamInfo = await _radioSource.getStreamUrl(station);
      if (_isSuperseded(requestId)) return;
      _currentStreamInfo = streamInfo;

      // 獲取即時資訊
      LiveRoomInfo? liveInfo;
      try {
        liveInfo = await _radioSource.getLiveInfo(station);
        if (_isSuperseded(requestId)) return;
        if (!liveInfo.isLive) {
          if (!_isSuperseded(requestId)) {
            state = state.copyWith(
              isLoading: false,
              clearLoadingStationId: true,
              error: t.radio.notLive,
            );
          }
          return;
        }
      } catch (e) {
        logWarning('Failed to get live info, continuing anyway: $e');
        if (_isSuperseded(requestId)) return;
      }

      // 開始播放
      await _audioService.playUrl(
        streamInfo.url,
        headers: streamInfo.headers,
      );
      if (_isSuperseded(requestId)) return;

      // 獲取高能用戶數（作為觀眾數）
      int? viewerCount;
      try {
        viewerCount = await _radioSource.getHighEnergyUserCount(station);
      } catch (e) {
        logWarning('Failed to get initial viewer count: $e');
      }
      if (_isSuperseded(requestId)) return;

      // 更新狀態
      _playStartTime = DateTime.now();
      state = state.copyWith(
        currentStation: station,
        isLoading: false,
        clearLoadingStationId: true,
        isPlaying: true,
        playDuration: Duration.zero,
        viewerCount: viewerCount,
        liveStartTime: liveInfo?.liveStartTime,
        description: liveInfo?.description,
        tags: liveInfo?.tags,
        announcement: liveInfo?.announcement,
        areaName: liveInfo?.areaName != null
            ? '${liveInfo!.parentAreaName ?? ''} · ${liveInfo.areaName}'
            : null,
      );

      // 更新最後播放時間
      await _repository.updateLastPlayed(station.id);

      // 啟動定時器
      _startTimers();

      // 更新平台媒體控制
      _updateSmtc(station);
      _updateAudioHandler(station);
    } catch (e) {
      if (_isSuperseded(requestId)) return;

      // 如果是流打開失敗且不是重試，嘗試重新獲取流地址並重試
      final errorStr = e.toString();
      if (!isRetry && errorStr.contains('Stream failed to open')) {
        logWarning('Stream failed to open, retrying with fresh URL...');
        await play(station, isRetry: true);
        return;
      }

      logError('Failed to play radio station: $e');
      state = state.copyWith(
        isLoading: false,
        clearLoadingStationId: true,
        error: t.radio.playFailed(error: e.toString()),
      );
    }
  }

  /// 停止播放
  Future<void> stop() async {
    _stopTimers();
    await _audioService.stop();

    state = state.copyWith(
      clearCurrentStation: true,
      isPlaying: false,
      isLoading: false,
      clearLoadingStationId: true,
      isBuffering: false,
      playDuration: Duration.zero,
      clearViewerCount: true,
      clearLiveStartTime: true,
      reconnectAttempts: 0,
      clearReconnectMessage: true,
      clearDescription: true,
      clearTags: true,
      clearAnnouncement: true,
      clearAreaName: true,
    );

    _playStartTime = null;
    _currentStreamInfo = null;

    // 更新平台媒體控制為停止狀態
    _clearSmtc();
    _clearAudioHandler();
  }

  /// 暫停播放（保留電台資訊，可重新播放）
  Future<void> pause() async {
    _stopTimers();
    await _audioService.stop();

    state = state.copyWith(
      isPlaying: false,
      isLoading: false,
      clearLoadingStationId: true,
      isBuffering: false,
      reconnectAttempts: 0,
      clearReconnectMessage: true,
    );

    _playStartTime = null;
    // 保留 _currentStreamInfo 以便快速恢復

    // 更新平台媒體控制為暫停狀態
    if (Platform.isWindows && state.currentStation != null) {
      windowsSmtcHandler.updateRadioPlaybackState(isPlaying: false);
    }
    if (Platform.isAndroid) {
      audioHandler.updatePlaybackState(
        isPlaying: false,
        position: Duration.zero,
        bufferedPosition: Duration.zero,
        processingState: FmpAudioProcessingState.ready,
      );
    }
  }

  /// 恢復播放當前電台
  Future<void> resume() async {
    if (state.currentStation == null) return;
    await play(state.currentStation!);
  }

  /// 同步直播（嘗試跳到最新進度，若無法 seek 則重新連接）
  Future<void> sync() async {
    if (state.currentStation == null) return;
    if (!state.isPlaying) return;

    // 先嘗試 seek 到直播流末尾
    final success = await _audioService.seekToLive();
    if (success) {
      logInfo('Synced to live edge via seek');
      return;
    }

    // 無法 seek，重新連接流
    logInfo('Cannot seek, reconnecting stream');
    await play(state.currentStation!);
  }

  /// 刷新直播（重新連接流）
  Future<void> reload() async {
    if (state.currentStation == null) return;
    if (!state.isPlaying) return;

    logInfo('Reloading live stream');
    await play(state.currentStation!);
  }

  /// 添加電台
  Future<RadioStation?> addStation(String url) async {
    try {
      // 解析 URL
      final parseResult = _radioSource.parseUrl(url);
      if (parseResult == null) {
        throw Exception(t.radio.cannotParseUrl);
      }

      // 檢查是否已存在（目前只支持 Bilibili）
      if (await _repository.exists(
          SourceType.bilibili, parseResult.sourceId)) {
        throw Exception(t.radio.alreadyExists);
      }

      // 創建並獲取資訊
      final station = await _radioSource.createStationFromUrl(url);

      // 設置排序順序
      station.sortOrder = await _repository.getNextSortOrder();

      // 保存
      final id = await _repository.save(station);
      final savedStation = await _repository.getById(id);

      // 立即刷新新電台的直播狀態
      if (savedStation != null) {
        try {
          final isLive = await _radioSource.isLive(savedStation);
          state = state.copyWith(
            liveStatus: {...state.liveStatus, savedStation.id: isLive},
          );
        } catch (e) {
          logWarning('Failed to check live status for new station: $e');
          state = state.copyWith(
            liveStatus: {...state.liveStatus, savedStation.id: false},
          );
        }
      }

      return savedStation;
    } catch (e) {
      logError('Failed to add station: $e');
      rethrow;
    }
  }

  /// 刪除電台
  Future<void> deleteStation(int id) async {
    // 如果正在播放此電台，先停止
    if (state.currentStation?.id == id) {
      await stop();
    }
    await _repository.delete(id);
  }

  /// 更新電台資訊
  Future<void> updateStation(RadioStation station) async {
    await _repository.save(station);
  }

  /// 重新排序電台
  Future<void> reorderStations(List<int> newOrder) async {
    await _repository.reorder(newOrder);
  }

  /// 直接更新電台順序（不重新加載，避免閃爍）
  void updateStationsOrder(List<RadioStation> orderedStations) {
    state = state.copyWith(stations: orderedStations);
  }

  /// 切換收藏
  Future<void> toggleFavorite(int id) async {
    await _repository.toggleFavorite(id);
  }

  /// 刷新電台資訊（使用高能用戶數作為觀眾數）
  Future<void> refreshStationInfo() async {
    if (state.currentStation == null) return;

    try {
      // 使用高能用戶數 API（更準確的觀眾數據）
      final count = await _radioSource.getHighEnergyUserCount(state.currentStation!);
      if (count != null) {
        state = state.copyWith(viewerCount: count);
      }
    } catch (e) {
      logWarning('Failed to refresh station info: $e');
    }
  }

  /// 刷新所有電台的直播狀態和資訊（封面、標題、主播名）
  ///
  /// 注意：定時後台刷新由 RadioRefreshService 處理
  /// 此方法僅用於手動刷新（如用戶下拉刷新）
  Future<void> refreshAllLiveStatus() async {
    if (state.stations.isEmpty || state.isRefreshingStatus) return;

    state = state.copyWith(isRefreshingStatus: true);

    // 使用 RadioRefreshService 進行刷新
    await RadioRefreshService.instance.refreshAll();

    // 同步狀態
    _syncLiveStatusFromRefreshService();

    state = state.copyWith(isRefreshingStatus: false);
  }

  // ========== Private Methods ==========

  /// 暫停音樂播放（互斥機制）
  Future<void> _pauseMusicPlayback() async {
    try {
      final audioController = _ref.read(audioControllerProvider.notifier);
      await audioController.pause();
    } catch (e) {
      logWarning('Failed to pause music: $e');
    }
  }

  /// 處理播放器狀態變化
  void _onPlayerStateChanged(FmpPlayerState playerState) {
    // 只在電台播放模式下處理
    if (state.currentStation == null) return;

    final wasPlaying = state.isPlaying;
    state = state.copyWith(
      isPlaying: playerState.playing,
      isBuffering: playerState.processingState == FmpAudioProcessingState.buffering,
    );

    // 同步 SMTC 播放狀態（僅 Windows）
    if (Platform.isWindows && wasPlaying != playerState.playing) {
      windowsSmtcHandler.updateRadioPlaybackState(isPlaying: playerState.playing);
    }

    // 處理播放結束（可能是斷流）
    if (playerState.processingState == FmpAudioProcessingState.completed) {
      _handleStreamEnd();
    }
  }

  /// 處理流結束（區分直播結束 vs 短暫中斷）
  Future<void> _handleStreamEnd() async {
    final station = state.currentStation;
    if (station == null || _currentStreamInfo == null) return;

    // 先檢查直播狀態
    bool isLive = false;
    try {
      isLive = await _radioSource.isLive(station);
    } catch (e) {
      // API 失敗時假設是短暫中斷，走重連邏輯
      logWarning('Failed to check live status during stream end: $e');
      isLive = true;
    }

    if (!isLive) {
      // 直播已結束 → 暫停並監控
      _pauseAndWatchForResume(station);
      return;
    }

    // 仍在直播 → 現有重連邏輯
    final attempts = state.reconnectAttempts;
    if (attempts >= _maxReconnectAttempts) {
      state = state.copyWith(
        isPlaying: false,
        error: t.radio.connectionFailed,
        clearReconnectMessage: true,
      );
      return;
    }

    final delay = _reconnectDelays[attempts];
    state = state.copyWith(
      reconnectAttempts: attempts + 1,
      reconnectMessage: t.radio.reconnectingCountdown(seconds: delay.inSeconds.toString()),
    );

    await Future.delayed(delay);

    // 再次檢查是否還需要重連
    if (state.currentStation == null) return;

    try {
      // 刷新流地址並重新播放
      final streamInfo = await _radioSource.getStreamUrl(state.currentStation!);
      _currentStreamInfo = streamInfo;

      await _audioService.playUrl(
        streamInfo.url,
        headers: streamInfo.headers,
      );

      // 重連成功
      state = state.copyWith(
        isPlaying: true,
        reconnectAttempts: 0,
        clearReconnectMessage: true,
        clearError: true,
      );
    } catch (e) {
      logWarning('Reconnect attempt ${attempts + 1} failed: $e');
      // 繼續下一次重連嘗試
      _handleStreamEnd();
    }
  }

  /// 直播結束：暫停播放，等待 RadioRefreshService 檢測到重新開播後自動恢復
  void _pauseAndWatchForResume(RadioStation station) {
    _stopTimers();
    _audioService.stop();
    _playStartTime = null;

    state = state.copyWith(
      isPlaying: false,
      reconnectAttempts: 0,
      reconnectMessage: t.radio.streamEnded,
    );

    // 更新平台媒體控制
    if (Platform.isWindows) {
      windowsSmtcHandler.updateRadioPlaybackState(isPlaying: false);
    }
    if (Platform.isAndroid) {
      audioHandler.updatePlaybackState(
        isPlaying: false,
        position: Duration.zero,
        bufferedPosition: Duration.zero,
        processingState: FmpAudioProcessingState.ready,
      );
    }

    logInfo('Stream ended for ${station.title}, waiting for RadioRefreshService to detect resume');
  }

  /// 啟動定時器
  void _startTimers() {
    _stopTimers();

    // 每秒更新已播放時長
    _playDurationTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updatePlayDuration(),
    );

    // 每 1 分鐘刷新高能用戶數
    _infoRefreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => refreshStationInfo(),
    );
  }

  /// 停止定時器
  void _stopTimers() {
    _playDurationTimer?.cancel();
    _playDurationTimer = null;
    _infoRefreshTimer?.cancel();
    _infoRefreshTimer = null;
  }

  /// 更新已播放時長
  void _updatePlayDuration() {
    if (_playStartTime == null || !state.isPlaying) return;

    final duration = DateTime.now().difference(_playStartTime!);
    state = state.copyWith(playDuration: duration);
  }

  /// 從 RadioRefreshService 同步直播狀態
  void _syncLiveStatusFromRefreshService() {
    final refreshService = RadioRefreshService.instance;
    final serviceStatus = refreshService.liveStatus;

    logInfo('同步直播狀態: ${serviceStatus.length} 個電台');

    if (serviceStatus.isEmpty) return;

    // 合併服務的狀態到當前狀態
    state = state.copyWith(liveStatus: serviceStatus);

    // 檢查是否處於「等待重新開播」狀態，且主播已重新開播
    final station = state.currentStation;
    if (station != null &&
        !state.isPlaying &&
        state.reconnectMessage == t.radio.streamEnded &&
        serviceStatus[station.id] == true) {
      logInfo('Broadcaster is back live, auto-resuming: ${station.title}');
      state = state.copyWith(
        reconnectMessage: t.radio.autoResuming,
      );
      play(station);
    }
  }

  @override
  void dispose() {
    _stopTimers();
    _playerStateSubscription?.cancel();
    _stationsSubscription?.cancel();
    _refreshServiceSubscription?.cancel();
    super.dispose();
  }
}

// ========== Providers ==========

/// RadioSource Provider
final radioSourceProvider = Provider<RadioSource>((ref) {
  final source = RadioSource();
  ref.onDispose(() => source.dispose());
  return source;
});

/// RadioRepository Provider
final radioRepositoryProvider = Provider<RadioRepository?>((ref) {
  final isar = ref.watch(databaseProvider).valueOrNull;
  if (isar == null) return null;
  return RadioRepository(isar);
});

/// RadioController Provider
final radioControllerProvider =
    StateNotifierProvider<RadioController, RadioState>((ref) {
  final repository = ref.watch(radioRepositoryProvider);
  final radioSource = ref.watch(radioSourceProvider);
  final audioService = ref.watch(audioServiceProvider);

  // 如果数据库还没准备好，返回一个空的 controller
  if (repository == null) {
    return RadioController.forLoading();
  }

  return RadioController(ref, repository, radioSource, audioService);
});

/// 電台是否正在播放 Provider
final isRadioPlayingProvider = Provider<bool>((ref) {
  return ref.watch(radioControllerProvider).isPlaying;
});

/// 當前播放的電台 Provider
final currentRadioStationProvider = Provider<RadioStation?>((ref) {
  return ref.watch(radioControllerProvider).currentStation;
});

/// 電台列表 Provider
final radioStationsProvider = Provider<List<RadioStation>>((ref) {
  return ref.watch(radioControllerProvider).stations;
});

// ========== Dummy Classes for Loading State ==========

/// Dummy Ref for loading state
class _DummyRef implements Ref {
  @override
  T watch<T>(ProviderListenable<T> provider) => throw UnimplementedError('DummyRef should not be used');

  @override
  T read<T>(ProviderListenable<T> provider) => throw UnimplementedError('DummyRef should not be used');

  @override
  void invalidate(ProviderOrFamily provider) => throw UnimplementedError('DummyRef should not be used');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Dummy RadioRepository for loading state
class _DummyRadioRepository implements RadioRepository {
  @override
  Future<List<RadioStation>> getAll() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Dummy AudioService for loading state
class _DummyAudioService implements FmpAudioService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
