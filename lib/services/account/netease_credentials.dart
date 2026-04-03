/// 網易雲音樂認證憑據（JSON 序列化存儲到 flutter_secure_storage）
class NeteaseCredentials {
  final String musicU;
  final String csrf;
  final String? userId;
  final DateTime savedAt;

  NeteaseCredentials({
    required this.musicU,
    required this.csrf,
    this.userId,
    required this.savedAt,
  });

  factory NeteaseCredentials.fromJson(Map<String, dynamic> json) {
    final musicU = json['musicU'] as String? ?? '';
    if (musicU.isEmpty) {
      throw const FormatException('Invalid Netease credentials: missing musicU');
    }
    return NeteaseCredentials(
      musicU: musicU,
      csrf: json['csrf'] as String? ?? '',
      userId: json['userId'] as String?,
      savedAt: json['savedAt'] != null
          ? DateTime.parse(json['savedAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'musicU': musicU,
        'csrf': csrf,
        'userId': userId,
        'savedAt': savedAt.toIso8601String(),
      };

  /// 生成 Cookie 字符串（供 Dio 請求使用）
  /// 包含 os=pc 標識，讓 Netease CDN 返回桌面端可用的音頻 URL
  String toCookieString() {
    final cookies = <String, String>{
      'MUSIC_U': musicU,
      if (csrf.isNotEmpty) '__csrf': csrf,
      'os': 'pc',
      'deviceId': 'fmp',
    };

    return cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }
}
