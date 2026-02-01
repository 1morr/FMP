import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logger.dart';
import '../../data/models/radio_station.dart';
import '../../data/models/track.dart'; // for SourceType
import '../../data/repositories/radio_repository.dart';
import '../../providers/database_provider.dart';
import '../audio/media_kit_audio_service.dart';
import '../audio/audio_types.dart';
import '../audio/audio_provider.dart';
import 'radio_source.dart';

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
  final MediaKitAudioService _audioService;

  // 定時器
  Timer? _playDurationTimer;
  Timer? _infoRefreshTimer;

  // 播放請求 ID（用於取消過期請求）
  int _playRequestId = 0;

  // 訂閱
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _stationsSubscription;

  // 重連配置
  static const int _maxReconnectAttempts = 3;
  static const List<Duration> _reconnectDelays = [
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 10),
  ];

  // 播放開始時間（用於計算已播放時長）
  DateTime? _playStartTime;

  // 當前流地址（用於重連）
  LiveStreamInfo? _currentStreamInfo;

  RadioController(
    this._ref,
    this._repository,
    this._radioSource,
    this._audioService,
  ) : super(const RadioState()) {
    _initialize();
    _setupMutualExclusion();
  }

  Future<void> _initialize() async {
    // 載入電台列表
    await _loadStations();

    // 監聽電台列表變化
    _stationsSubscription = _repository.watchAll().listen((stations) {
      state = state.copyWith(stations: stations);
    });

    // 監聽播放器狀態
    _playerStateSubscription = _audioService.playerStateStream.listen(
      _onPlayerStateChanged,
    );
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
    } catch (e) {
      // AudioController 可能尚未初始化
    }
  }

  /// 載入電台列表
  Future<void> _loadStations() async {
    final stations = await _repository.getAll();
    state = state.copyWith(stations: stations);
  }

  /// 檢查請求是否已被取代
  bool _isSuperseded(int requestId) => requestId != _playRequestId;

  /// 播放電台
  Future<void> play(RadioStation station) async {
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
              error: '直播間尚未開播',
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
    } catch (e) {
      if (_isSuperseded(requestId)) return;
      logError('Failed to play radio station: $e');
      state = state.copyWith(
        isLoading: false,
        clearLoadingStationId: true,
        error: '播放失敗: $e',
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
  }

  /// 恢復播放當前電台
  Future<void> resume() async {
    if (state.currentStation == null) return;
    await play(state.currentStation!);
  }

  /// 添加電台
  Future<RadioStation?> addStation(String url) async {
    try {
      // 解析 URL
      final parseResult = _radioSource.parseUrl(url);
      if (parseResult == null) {
        throw Exception('無法解析此 URL，請確認是有效的直播間連結');
      }

      // 檢查是否已存在（目前只支持 Bilibili）
      if (await _repository.exists(
          SourceType.bilibili, parseResult.sourceId)) {
        throw Exception('此電台已存在');
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

  /// 刷新所有電台的直播狀態
  Future<void> refreshAllLiveStatus() async {
    if (state.stations.isEmpty || state.isRefreshingStatus) return;

    state = state.copyWith(isRefreshingStatus: true);

    final newStatus = <int, bool>{};

    for (final station in state.stations) {
      try {
        final isLive = await _radioSource.isLive(station);
        newStatus[station.id] = isLive;
      } catch (e) {
        logWarning('Failed to check live status for ${station.title}: $e');
        newStatus[station.id] = false;
      }
    }

    state = state.copyWith(
      liveStatus: newStatus,
      isRefreshingStatus: false,
    );
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
  void _onPlayerStateChanged(MediaKitPlayerState playerState) {
    // 只在電台播放模式下處理
    if (state.currentStation == null) return;

    state = state.copyWith(
      isPlaying: playerState.playing,
      isBuffering: playerState.processingState == FmpAudioProcessingState.buffering,
    );

    // 處理播放結束（可能是斷流）
    if (playerState.processingState == FmpAudioProcessingState.completed) {
      _handleStreamEnd();
    }
  }

  /// 處理流結束（嘗試重連）
  Future<void> _handleStreamEnd() async {
    if (state.currentStation == null || _currentStreamInfo == null) return;

    final attempts = state.reconnectAttempts;
    if (attempts >= _maxReconnectAttempts) {
      state = state.copyWith(
        isPlaying: false,
        error: '連線失敗，請稍後重試',
        clearReconnectMessage: true,
      );
      return;
    }

    final delay = _reconnectDelays[attempts];
    state = state.copyWith(
      reconnectAttempts: attempts + 1,
      reconnectMessage: '連線中斷，${delay.inSeconds}秒後重試...',
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

  @override
  void dispose() {
    _stopTimers();
    _playerStateSubscription?.cancel();
    _stationsSubscription?.cancel();
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
final radioRepositoryProvider = Provider<RadioRepository>((ref) {
  final isar = ref.watch(databaseProvider).requireValue;
  return RadioRepository(isar);
});

/// RadioController Provider
final radioControllerProvider =
    StateNotifierProvider<RadioController, RadioState>((ref) {
  final repository = ref.watch(radioRepositoryProvider);
  final radioSource = ref.watch(radioSourceProvider);
  final audioService = ref.watch(audioServiceProvider);

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
