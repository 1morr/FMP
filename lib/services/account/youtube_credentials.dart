import 'dart:convert';

import 'package:crypto/crypto.dart';

/// YouTube 認證憑據（JSON 序列化存儲到 flutter_secure_storage）
///
/// YouTube 使用 Cookie + SAPISIDHASH 認證。
/// Cookie 有效期 ~2 年，無需刷新流程。
class YouTubeCredentials {
  final String sid;
  final String hsid;
  final String ssid;
  final String apisid;
  final String sapisid;
  final String secure1Psid;
  final String secure3Psid;
  final String secure1Papisid;
  final String secure3Papisid;
  final String loginInfo;
  final String? datasyncId;
  final DateTime savedAt;

  YouTubeCredentials({
    required this.sid,
    required this.hsid,
    required this.ssid,
    required this.apisid,
    required this.sapisid,
    required this.secure1Psid,
    required this.secure3Psid,
    required this.secure1Papisid,
    required this.secure3Papisid,
    required this.loginInfo,
    this.datasyncId,
    required this.savedAt,
  });

  factory YouTubeCredentials.fromJson(Map<String, dynamic> json) {
    return YouTubeCredentials(
      sid: json['sid'] as String? ?? '',
      hsid: json['hsid'] as String? ?? '',
      ssid: json['ssid'] as String? ?? '',
      apisid: json['apisid'] as String? ?? '',
      sapisid: json['sapisid'] as String? ?? '',
      secure1Psid: json['secure1Psid'] as String? ?? '',
      secure3Psid: json['secure3Psid'] as String? ?? '',
      secure1Papisid: json['secure1Papisid'] as String? ?? '',
      secure3Papisid: json['secure3Papisid'] as String? ?? '',
      loginInfo: json['loginInfo'] as String? ?? '',
      datasyncId: json['datasyncId'] as String?,
      savedAt: json['savedAt'] != null
          ? DateTime.parse(json['savedAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'sid': sid,
        'hsid': hsid,
        'ssid': ssid,
        'apisid': apisid,
        'sapisid': sapisid,
        'secure1Psid': secure1Psid,
        'secure3Psid': secure3Psid,
        'secure1Papisid': secure1Papisid,
        'secure3Papisid': secure3Papisid,
        'loginInfo': loginInfo,
        'datasyncId': datasyncId,
        'savedAt': savedAt.toIso8601String(),
      };

  /// 生成 Cookie 字符串（供 Dio 請求使用）
  String toCookieString() {
    final parts = <String>[
      'SID=$sid',
      'HSID=$hsid',
      'SSID=$ssid',
      'APISID=$apisid',
      'SAPISID=$sapisid',
      '__Secure-1PSID=$secure1Psid',
      '__Secure-3PSID=$secure3Psid',
      '__Secure-1PAPISID=$secure1Papisid',
      '__Secure-3PAPISID=$secure3Papisid',
      'LOGIN_INFO=$loginInfo',
    ];
    if (datasyncId != null && datasyncId!.isNotEmpty) {
      parts.add('DATASYNC_ID=$datasyncId');
    }
    return parts.join('; ');
  }

  /// 生成 SAPISIDHASH Authorization header 值
  ///
  /// 格式: SAPISIDHASH {timestamp}_{SHA1("{timestamp} {SAPISID} https://www.youtube.com")}
  String generateSapiSidHash() {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final input = '$timestamp $sapisid https://www.youtube.com';
    final hash = sha1.convert(utf8.encode(input)).toString();
    return 'SAPISIDHASH ${timestamp}_$hash';
  }

  /// 是否包含必要的認證 Cookie
  bool get isValid =>
      sapisid.isNotEmpty &&
      secure1Psid.isNotEmpty &&
      secure3Psid.isNotEmpty &&
      loginInfo.isNotEmpty;
}
