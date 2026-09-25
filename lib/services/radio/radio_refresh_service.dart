import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:fmp/core/logger.dart';
import 'package:fmp/data/models/radio_station.dart';
import 'package:fmp/data/repositories/radio_repository.dart';
import 'package:fmp/data/sources/source_exception.dart';
import 'package:fmp/services/radio/radio_source.dart';

/// 電台刷新服務
///
/// 主動後台刷新模式：
/// - 應用啟動時立即獲取直播狀態
/// - 按設定的間隔自動後台刷新（預設 5 分鐘）；設成關閉時兩者都不做，只剩
///   電台頁的下拉刷新
/// - 用戶進入任何頁面時直接顯示緩存，無需等待
/// - 緩存直播狀態和電台資訊（封面、標題、主播名）
///
/// 這是 App 裡唯一「開著就永遠在打 Bilibili」的流量，所以它也是最容易把
/// 匿名使用者推進風控的地方（#95）。兩條煞車：
/// - 被風控的那一輪立刻停，下一輪推遲 `interval × 2^n`，上限 30 分鐘；
///   乾淨跑完一輪就歸零。以前是下一個 tick 原速再來，等於在風控期間持續施壓。
/// - App 進背景時停止輪詢。沒有人在看電台列表，輪詢只是在替風控計數。
///   使用者手動觸發的 [refreshAll] 與 [refreshStation] 不受這兩條限制。
class RadioRefreshService with Logging {
  /// 全局單例實例
  static late final RadioRefreshService instance;

  /// 退避上限。再長就等於「這一天不刷新」，使用者會以為壞了。
  static const maxBackoff = Duration(minutes: 30);

  static const defaultRefreshInterval = Duration(minutes: 5);

  /// 設定裡代表「關閉」的分鐘數。沿用同一個欄位而不是另開一個布林：Isar 對
  /// 舊列的 int 補的是負數，不會撞上 0（AntennaPod 的更新間隔也是 0 = 關閉）。
  static const offMinutes = 0;

  /// 設定裡存的分鐘數換成輪詢間隔，null 代表關閉。讀不到的、非法的（還沒寫過
  /// 這個欄位的舊列讀出來是負數，而這時遷移還沒把它修好）照預設。
  static Duration? intervalFromMinutes(int? minutes) => switch (minutes) {
    offMinutes => null,
    final int m when m > 0 => Duration(minutes: m),
    _ => defaultRefreshInterval,
  };

  RadioRepository? _repository;
  final RadioSource _radioSource;
  final DateTime Function() _now;

  /// null = 使用者關掉了自動刷新。
  Duration? _refreshInterval;
  bool _started = false;

  Timer? _refreshTimer;
  Future<void>? _activeRefreshAll;
  int _refreshAllGeneration = 0;

  int _rateLimitedRounds = 0;
  DateTime? _backoffUntil;
  DateTime? _lastCleanRoundAt;
  bool _paused = false;

  // 緩存數據
  final Map<int, bool> _liveStatus = {};

  // 狀態變更通知
  final _stateController = StreamController<void>.broadcast();

  RadioRefreshService({
    RadioSource? radioSource,
    Duration? refreshInterval = defaultRefreshInterval,
    DateTime Function()? now,
  }) : _radioSource = radioSource ?? RadioSource(),
       _refreshInterval = refreshInterval,
       _now = now ?? DateTime.now;

  /// 緩存的直播狀態
  Map<int, bool> get liveStatus => _liveStatus;

  /// 狀態變更流
  Stream<void> get stateChanges => _stateController.stream;

  /// 下一輪定時刷新最早會在什麼時候跑；沒有退避時為 null。
  DateTime? get backoffUntil => _backoffUntil;

  /// 檢查電台是否正在直播
  bool isStationLive(int stationId) => _liveStatus[stationId] ?? false;

  /// 設置 Repository（由 RadioController 調用）
  void setRepository(RadioRepository repository) {
    _repository = repository;
    if (_started) return;
    _started = true;
    _startRefreshTimer();
    // 立即執行一次刷新；關閉時連這一次也不做，那同樣是沒人按的請求。
    if (_refreshInterval != null) refreshAll();
  }

  /// 啟動定時刷新；關閉時只停掉舊的。
  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    final interval = _refreshInterval;
    if (interval == null) return;
    _refreshTimer = Timer.periodic(interval, (_) => tick());
  }

  /// 更新刷新間隔（重啟定時器），null 代表關閉。
  void updateRefreshInterval(Duration? interval) {
    final wasOff = _refreshInterval == null;
    _refreshInterval = interval;
    // 僅在已經啟動時重啟（即 repository 已設置後）
    if (!_started) return;
    _startRefreshTimer();
    // 從關閉打開：列表上的狀態可能是很久以前的，照回前景的規則補一輪。
    if (wasOff) _refreshIfStale();
  }

  /// 定時器每一拍做的事。獨立成方法是為了讓測試不用等真實時間。
  @visibleForTesting
  void tick() {
    if (_paused || _refreshInterval == null) return;
    final backoffUntil = _backoffUntil;
    if (backoffUntil != null && _now().isBefore(backoffUntil)) {
      logDebug('[RadioRefresh] Backing off until $backoffUntil');
      return;
    }
    refreshAll();
  }

  /// App 進背景。定時器繼續跑，但 [tick] 不做事；這樣 [resume] 時不必重建定時器。
  void pause() {
    if (_paused) return;
    _paused = true;
    logDebug('[RadioRefresh] Paused (app in background)');
  }

  /// App 回到前景。距上一輪乾淨刷新已超過一個間隔就立刻補跑一輪，
  /// 否則等下一拍 —— 回前景那一瞬間不該變成額外的請求尖峰。
  void resume() {
    if (!_paused) return;
    _paused = false;
    _refreshIfStale();
  }

  void _refreshIfStale() {
    final interval = _refreshInterval;
    if (interval == null) return;
    final last = _lastCleanRoundAt;
    final stale = last == null || _now().difference(last) >= interval;
    logDebug('[RadioRefresh] Refreshing if stale (stale: $stale)');
    if (stale) tick();
  }

  /// 刷新所有電台的直播狀態
  Future<void> refreshAll() {
    final activeRefresh = _activeRefreshAll;
    if (activeRefresh != null) return activeRefresh;

    final generation = ++_refreshAllGeneration;
    final refresh = _refreshAll(generation);
    _activeRefreshAll = refresh;
    refresh.whenComplete(() {
      if (identical(_activeRefreshAll, refresh)) {
        _activeRefreshAll = null;
      }
    });
    return refresh;
  }

  Future<void> _refreshAll(int generation) async {
    final repository = _repository;
    if (repository == null) {
      logWarning('[RadioRefresh] Repository not set, skipping refresh');
      return;
    }

    final stations = await repository.getAll();
    if (!_isCurrentRefreshAll(generation)) return;
    if (stations.isEmpty) {
      // 沒有電台也算乾淨跑完一輪，否則每次回前景都會再讀一次資料庫。
      _lastCleanRoundAt = _now();
      return;
    }

    for (final station in stations) {
      try {
        // 獲取完整直播間資訊
        final info = await _radioSource.getLiveInfo(station);
        if (!_isCurrentRefreshAll(generation)) return;
        _liveStatus[station.id] = info.isLive;

        // 更新電台資訊（封面、標題、主播名）
        bool needsUpdate = false;
        if (info.thumbnailUrl != null &&
            info.thumbnailUrl != station.thumbnailUrl) {
          station.thumbnailUrl = info.thumbnailUrl;
          needsUpdate = true;
        }
        if (info.title.isNotEmpty && info.title != station.title) {
          station.title = info.title;
          needsUpdate = true;
        }
        if (info.hostName != null && info.hostName != station.hostName) {
          station.hostName = info.hostName;
          needsUpdate = true;
        }

        // 保存到數據庫
        if (needsUpdate) {
          await repository.save(station);
          if (!_isCurrentRefreshAll(generation)) return;
        }
      } on SourceApiException catch (e) {
        if (!_isCurrentRefreshAll(generation)) return;
        if (e.isRateLimited) {
          _enterBackoff(e);
          _notifyStateChange();
          return;
        }
        _markOffline(station, e);
      } catch (e) {
        if (!_isCurrentRefreshAll(generation)) return;
        _markOffline(station, e);
      }
    }

    if (!_isCurrentRefreshAll(generation)) return;
    _rateLimitedRounds = 0;
    _backoffUntil = null;
    _lastCleanRoundAt = _now();
    _notifyStateChange();
    logDebug('[RadioRefresh] 電台直播狀態已刷新: ${_liveStatus.length} 個電台');
  }

  /// 被風控的那一輪剩下的電台不再問，狀態保持上一輪的值 —— 風控不代表下播。
  void _enterBackoff(SourceApiException e) {
    _rateLimitedRounds++;
    final shift = math.min(_rateLimitedRounds, 10);
    // 關閉時被風控的是手動刷新；退避只擋定時那一拍，照預設間隔算就好。
    final delay = (_refreshInterval ?? defaultRefreshInterval) * (1 << shift);
    final capped = delay > maxBackoff ? maxBackoff : delay;
    _backoffUntil = _now().add(capped);
    logWarning(
      '[RadioRefresh] Rate limited (${e.sourceType}), '
      'round $_rateLimitedRounds, next refresh after $capped',
    );
  }

  void _markOffline(RadioStation station, Object e) {
    logWarning(
      '[RadioRefresh] Failed to check live status for ${station.title}: $e',
    );
    _liveStatus[station.id] = false;
  }

  /// 刷新單個電台的直播狀態
  Future<bool> refreshStation(RadioStation station) async {
    try {
      final isLive = await _radioSource.isLive(station);
      _liveStatus[station.id] = isLive;
      _notifyStateChange();
      return isLive;
    } catch (e) {
      logWarning(
        '[RadioRefresh] Failed to refresh station ${station.title}: $e',
      );
      _liveStatus[station.id] = false;
      return false;
    }
  }

  /// 添加電台狀態到緩存
  void addStationStatus(int stationId, bool isLive) {
    _liveStatus[stationId] = isLive;
    _notifyStateChange();
  }

  /// 從緩存移除電台
  void removeStation(int stationId) {
    _liveStatus.remove(stationId);
    _notifyStateChange();
  }

  bool _isCurrentRefreshAll(int generation) {
    return generation == _refreshAllGeneration && !_stateController.isClosed;
  }

  void _notifyStateChange() {
    if (!_stateController.isClosed) {
      _stateController.add(null);
    }
  }

  /// 釋放資源
  void dispose() {
    _refreshAllGeneration++;
    _refreshTimer?.cancel();
    _stateController.close();
  }
}
