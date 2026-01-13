import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/network_service.dart';

/// 网络状态 Provider
final networkStatusProvider = StateNotifierProvider<NetworkStatusNotifier, NetworkStatus>((ref) {
  return NetworkStatusNotifier();
});

/// 网络状态 Notifier
class NetworkStatusNotifier extends StateNotifier<NetworkStatus> {
  StreamSubscription<NetworkStatus>? _subscription;
  
  NetworkStatusNotifier() : super(networkService.currentStatus) {
    _subscription = networkService.statusStream.listen((status) {
      state = status;
    });
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
  
  /// 强制检查网络状态
  Future<void> forceCheck() async {
    await networkService.forceCheck();
    state = networkService.currentStatus;
  }
}

/// 是否在线
final isOnlineProvider = Provider<bool>((ref) {
  final status = ref.watch(networkStatusProvider);
  return status == NetworkStatus.online;
});

/// 是否离线
final isOfflineProvider = Provider<bool>((ref) {
  final status = ref.watch(networkStatusProvider);
  return status == NetworkStatus.offline;
});
