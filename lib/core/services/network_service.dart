import 'dart:async';
import 'dart:io';

import '../logger.dart';

/// 网络连接状态
enum NetworkStatus {
  /// 在线
  online,
  
  /// 离线
  offline,
  
  /// 未知（检查中）
  unknown,
}

/// 网络状态服务
/// 
/// 提供网络连接状态监听和查询功能
class NetworkService with Logging {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();
  
  /// 网络状态流控制器
  final _statusController = StreamController<NetworkStatus>.broadcast();
  
  /// 当前网络状态
  NetworkStatus _currentStatus = NetworkStatus.unknown;
  
  /// 检查定时器
  Timer? _checkTimer;
  
  /// 检查间隔
  static const _checkInterval = Duration(seconds: 30);
  
  /// 测试主机列表
  static const _testHosts = [
    'www.bilibili.com',
    'api.bilibili.com',
    'www.baidu.com',
  ];
  
  /// 网络状态流
  Stream<NetworkStatus> get statusStream => _statusController.stream;
  
  /// 当前网络状态
  NetworkStatus get currentStatus => _currentStatus;
  
  /// 是否在线
  bool get isOnline => _currentStatus == NetworkStatus.online;
  
  /// 是否离线
  bool get isOffline => _currentStatus == NetworkStatus.offline;
  
  /// 初始化服务
  Future<void> initialize() async {
    logDebug('Initializing NetworkService');
    
    // 立即检查一次
    await checkConnectivity();
    
    // 启动周期检查
    _startPeriodicCheck();
    
    logDebug('NetworkService initialized, status: $_currentStatus');
  }
  
  /// 释放资源
  void dispose() {
    _checkTimer?.cancel();
    _statusController.close();
  }
  
  /// 启动周期检查
  void _startPeriodicCheck() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(_checkInterval, (_) {
      checkConnectivity();
    });
  }
  
  /// 检查网络连接
  Future<NetworkStatus> checkConnectivity() async {
    final previousStatus = _currentStatus;
    
    try {
      bool connected = false;
      
      // 尝试连接测试主机
      for (final host in _testHosts) {
        try {
          final result = await InternetAddress.lookup(host)
              .timeout(const Duration(seconds: 5));
          
          if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
            connected = true;
            break;
          }
        } catch (_) {
          // 继续尝试下一个主机
        }
      }
      
      _currentStatus = connected ? NetworkStatus.online : NetworkStatus.offline;
      
    } catch (e) {
      logDebug('Network check error: $e');
      _currentStatus = NetworkStatus.offline;
    }
    
    // 状态变化时通知
    if (previousStatus != _currentStatus) {
      logDebug('Network status changed: $previousStatus -> $_currentStatus');
      _statusController.add(_currentStatus);
    }
    
    return _currentStatus;
  }
  
  /// 强制重新检查
  Future<NetworkStatus> forceCheck() async {
    return await checkConnectivity();
  }
}

/// 全局网络服务实例
final networkService = NetworkService();
