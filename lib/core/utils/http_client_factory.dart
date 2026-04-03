import 'package:dio/dio.dart';

import '../constants/app_constants.dart';

/// 统一的 HTTP 客户端工厂
///
/// 消除各音源 Dio 初始化中的重复配置（超时、User-Agent 等）
class HttpClientFactory {
  HttpClientFactory._();

  /// 通用 User-Agent（Chrome on Windows）
  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  /// 创建 Dio 实例，使用统一的超时配置
  ///
  /// [headers] - 额外的请求头（会合并到默认 User-Agent 之上）
  static Dio create({
    Map<String, dynamic>? headers,
    String? userAgent,
    Duration? connectTimeout,
    Duration? receiveTimeout,
  }) {
    final mergedHeaders = <String, dynamic>{
      'User-Agent': userAgent ?? defaultUserAgent,
      ...?headers,
    };

    return Dio(BaseOptions(
      headers: mergedHeaders,
      connectTimeout: connectTimeout ?? AppConstants.networkConnectTimeout,
      receiveTimeout: receiveTimeout ?? AppConstants.networkReceiveTimeout,
    ));
  }
}
