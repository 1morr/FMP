import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/radio_station.dart';
import '../../data/repositories/radio_repository.dart';
import 'radio_source.dart';

/// 電台刷新服務
///
/// 主動後台刷新模式：
/// - 應用啟動時立即獲取直播狀態
/// - 每 5 分鐘自動後台刷新
/// - 用戶進入任何頁面時直接顯示緩存，無需等待
/// - 緩存直播狀態和電台資訊（封面、標題、主播名）
class RadioRefreshService {
  /// 全局單例實例
  static late final RadioRefreshService instance;

  RadioRepository? _repository;
  final RadioSource _radioSource;
  Duration _refreshInterval;

  Timer? _refreshTimer;

  // 緩存數據
  // ignore: prefer_final_fields
  Map<int, bool> _liveStatus = {};

  // 狀態變更通知
  final _stateController = StreamController<void>.broadcast();

  RadioRefreshService({
    RadioSource? radioSource,
    Duration? refreshInterval,
  })  : _radioSource = radioSource ?? RadioSource(),
        _refreshInterval = refreshInterval ?? const Duration(minutes: 5);

  /// 緩存的直播狀態
  Map<int, bool> get liveStatus => _liveStatus;

  /// 狀態變更流
  Stream<void> get stateChanges => _stateController.stream;

  /// 檢查電台是否正在直播
  bool isStationLive(int stationId) => _liveStatus[stationId] ?? false;

  /// 設置 Repository（由 RadioController 調用）
  void setRepository(RadioRepository repository) {
    _repository = repository;
    // 如果已設置 repository 且尚未啟動定時器，啟動刷新
    if (_refreshTimer == null) {
      _startRefreshTimer();
      // 立即執行一次刷新
      refreshAll();
    }
  }

  /// 啟動定時刷新
  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      refreshAll();
    });
  }

  /// 更新刷新間隔（重啟定時器）
  void updateRefreshInterval(Duration interval) {
    _refreshInterval = interval;
    // 僅在定時器已啟動時重啟（即 repository 已設置後）
    if (_refreshTimer != null) {
      _refreshTimer!.cancel();
      _refreshTimer = Timer.periodic(interval, (_) => refreshAll());
    }
  }

  /// 刷新所有電台的直播狀態
  Future<void> refreshAll() async {
    final repository = _repository;
    if (repository == null) {
      debugPrint('[RadioRefresh] Repository not set, skipping refresh');
      return;
    }

    final stations = await repository.getAll();
    if (stations.isEmpty) return;

    for (final station in stations) {
      try {
        // 獲取完整直播間資訊
        final info = await _radioSource.getLiveInfo(station);
        _liveStatus[station.id] = info.isLive;

        // 更新電台資訊（封面、標題、主播名）
        bool needsUpdate = false;
        if (info.thumbnailUrl != null && info.thumbnailUrl != station.thumbnailUrl) {
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
          repository.save(station);
        }
      } catch (e) {
        debugPrint('[RadioRefresh] Failed to check live status for ${station.title}: $e');
        _liveStatus[station.id] = false;
      }
    }

    _notifyStateChange();
    debugPrint('[RadioRefresh] 電台直播狀態已刷新: ${_liveStatus.length} 個電台');
  }

  /// 刷新單個電台的直播狀態
  Future<bool> refreshStation(RadioStation station) async {
    try {
      final isLive = await _radioSource.isLive(station);
      _liveStatus[station.id] = isLive;
      _notifyStateChange();
      return isLive;
    } catch (e) {
      debugPrint('[RadioRefresh] Failed to refresh station ${station.title}: $e');
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

  void _notifyStateChange() {
    if (!_stateController.isClosed) {
      _stateController.add(null);
    }
  }

  /// 釋放資源
  void dispose() {
    _refreshTimer?.cancel();
    _stateController.close();
  }
}

/// RadioRefreshService Provider（用於訪問單例）
/// 
/// 注意：此 Provider 不需要 dispose，因為：
/// 1. RadioRefreshService.instance 是全局單例，生命週期與應用相同
/// 2. 單例的 dispose() 由應用退出時統一處理
/// 3. Provider 僅作為訪問入口，不擁有資源所有權
final radioRefreshServiceProvider = Provider<RadioRefreshService>((ref) {
  return RadioRefreshService.instance;
});
