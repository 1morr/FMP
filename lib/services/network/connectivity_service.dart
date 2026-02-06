import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logger.dart';

/// 网络连接状态
class ConnectivityState {
  const ConnectivityState({
    required this.isConnected,
    required this.connectionTypes,
    required this.isInitialized,
  });

  /// 是否已连接网络
  final bool isConnected;

  /// 当前连接类型列表
  final List<ConnectivityResult> connectionTypes;

  /// 是否已初始化
  final bool isInitialized;

  /// 初始状态
  static const initial = ConnectivityState(
    isConnected: true, // 默认假设有网络
    connectionTypes: [],
    isInitialized: false,
  );

  ConnectivityState copyWith({
    bool? isConnected,
    List<ConnectivityResult>? connectionTypes,
    bool? isInitialized,
  }) {
    return ConnectivityState(
      isConnected: isConnected ?? this.isConnected,
      connectionTypes: connectionTypes ?? this.connectionTypes,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

/// 网络连接服务
class ConnectivityNotifier extends StateNotifier<ConnectivityState> with Logging {
  ConnectivityNotifier() : super(ConnectivityState.initial) {
    _initialize();
  }

  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// 网络恢复事件控制器
  final _networkRecoveredController = StreamController<void>.broadcast();

  /// 网络恢复事件流
  Stream<void> get onNetworkRecovered => _networkRecoveredController.stream;

  Future<void> _initialize() async {
    logDebug('Initializing ConnectivityNotifier...');
    // 获取当前连接状态
    final results = await _connectivity.checkConnectivity();
    final isConnected = _isConnectedFromResults(results);
    logDebug('Initial connectivity: $results, isConnected: $isConnected');
    state = state.copyWith(
      isConnected: isConnected,
      connectionTypes: results,
      isInitialized: true,
    );

    // 监听连接变化
    _subscription = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    logDebug('Connectivity listener registered');
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final wasConnected = state.isConnected;
    final isConnected = _isConnectedFromResults(results);
    
    logInfo('Connectivity changed: $results, wasConnected: $wasConnected, isConnected: $isConnected');

    state = state.copyWith(
      isConnected: isConnected,
      connectionTypes: results,
    );

    // 网络恢复时发送事件
    if (!wasConnected && isConnected) {
      logInfo('Network recovered! Broadcasting recovery event...');
      _networkRecoveredController.add(null);
    }
  }

  bool _isConnectedFromResults(List<ConnectivityResult> results) {
    // 没有任何连接类型或只有 none 类型表示断网
    if (results.isEmpty) return false;
    if (results.length == 1 && results.first == ConnectivityResult.none) {
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _networkRecoveredController.close();
    super.dispose();
  }
}

/// 网络连接状态 Provider
final connectivityProvider =
    StateNotifierProvider<ConnectivityNotifier, ConnectivityState>((ref) {
  return ConnectivityNotifier();
});

/// 是否已连接网络 Provider
final isConnectedProvider = Provider<bool>((ref) {
  return ref.watch(connectivityProvider).isConnected;
});

/// 网络恢复事件流 Provider
final networkRecoveredStreamProvider = StreamProvider<void>((ref) {
  final notifier = ref.watch(connectivityProvider.notifier);
  return notifier.onNetworkRecovered;
});
