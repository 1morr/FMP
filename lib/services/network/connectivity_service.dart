import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';

/// 网络连接状态
class ConnectivityState {
  const ConnectivityState({
    required this.isConnected,
    required this.isInitialized,
  });

  /// 是否已连接网络（通过 DNS 解析验证真实可达性）
  final bool isConnected;

  /// 是否已初始化
  final bool isInitialized;

  /// 初始状态
  static const initial = ConnectivityState(
    isConnected: true, // 默认假设有网络
    isInitialized: false,
  );

  ConnectivityState copyWith({
    bool? isConnected,
    bool? isInitialized,
  }) {
    return ConnectivityState(
      isConnected: isConnected ?? this.isConnected,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

/// 网络连接服务（基于 DNS 解析检测真实网络可达性）
///
/// 通过尝试 DNS 解析来判断是否有真实的互联网连接，
/// 而不是仅检查网络接口状态。这样即使 WiFi 已连接但无互联网，
/// 也能正确检测到断网。
class ConnectivityNotifier extends StateNotifier<ConnectivityState>
    with Logging {
  ConnectivityNotifier() : super(ConnectivityState.initial) {
    _initialize();
  }

  Timer? _pollingTimer;

  /// DNS 检测目标（使用多个可靠的公共 DNS 主机）
  static const _dnsTargets = [
    'dns.google', // Google Public DNS
    'one.one.one.one', // Cloudflare DNS
    'dns.alidns.com', // 阿里 DNS（中国大陆友好）
  ];

  /// 网络恢复事件控制器
  final _networkRecoveredController = StreamController<void>.broadcast();

  /// 网络恢复事件流
  Stream<void> get onNetworkRecovered => _networkRecoveredController.stream;

  Future<void> _initialize() async {
    logDebug('Initializing ConnectivityNotifier (DNS-based)...');

    final isConnected = await _checkConnectivity();
    logDebug('Initial connectivity check: isConnected=$isConnected');

    state = state.copyWith(
      isConnected: isConnected,
      isInitialized: true,
    );

    // 启动定时轮询
    _pollingTimer = Timer.periodic(AppConstants.connectivityPollingInterval, (_) => _poll());
    logDebug('DNS polling started (interval: ${AppConstants.connectivityPollingInterval.inSeconds}s)');
  }

  Future<void> _poll() async {
    final wasConnected = state.isConnected;
    final isConnected = await _checkConnectivity();

    if (wasConnected != isConnected) {
      logInfo(
          'Connectivity changed: wasConnected=$wasConnected, isConnected=$isConnected');
      state = state.copyWith(isConnected: isConnected);

      if (!wasConnected && isConnected) {
        logInfo('Network recovered! Broadcasting recovery event...');
        _networkRecoveredController.add(null);
      }
    }
  }

  /// 通过 DNS 解析检测网络可达性
  ///
  /// 尝试解析多个目标中的任意一个成功即视为有网络
  Future<bool> _checkConnectivity() async {
    for (final target in _dnsTargets) {
      try {
        final result = await InternetAddress.lookup(target)
            .timeout(AppConstants.dnsTimeout);
        if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
          return true;
        }
      } catch (_) {
        // 当前目标失败，尝试下一个
      }
    }
    return false;
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
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
