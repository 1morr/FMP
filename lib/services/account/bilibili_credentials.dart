/// Bilibili 認證憑據（JSON 序列化存儲到 flutter_secure_storage）
class BilibiliCredentials {
  final String sessdata;
  final String biliJct; // CSRF token
  final String dedeUserId;
  final String dedeUserIdCkMd5;
  final String refreshToken;
  final DateTime savedAt;

  BilibiliCredentials({
    required this.sessdata,
    required this.biliJct,
    required this.dedeUserId,
    required this.dedeUserIdCkMd5,
    required this.refreshToken,
    required this.savedAt,
  });

  factory BilibiliCredentials.fromJson(Map<String, dynamic> json) {
    return BilibiliCredentials(
      sessdata: json['sessdata'] as String? ?? '',
      biliJct: json['biliJct'] as String? ?? '',
      dedeUserId: json['dedeUserId'] as String? ?? '',
      dedeUserIdCkMd5: json['dedeUserIdCkMd5'] as String? ?? '',
      refreshToken: json['refreshToken'] as String? ?? '',
      savedAt: json['savedAt'] != null
          ? DateTime.parse(json['savedAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'sessdata': sessdata,
    'biliJct': biliJct,
    'dedeUserId': dedeUserId,
    'dedeUserIdCkMd5': dedeUserIdCkMd5,
    'refreshToken': refreshToken,
    'savedAt': savedAt.toIso8601String(),
  };

  /// 生成 Cookie 字符串（供 Dio 請求使用）
  String toCookieString() {
    return 'SESSDATA=$sessdata; bili_jct=$biliJct; DedeUserID=$dedeUserId; DedeUserID__ckMd5=$dedeUserIdCkMd5';
  }
}
