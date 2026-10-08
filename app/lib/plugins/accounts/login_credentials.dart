import 'package:flutter/foundation.dart';

/// 登入憑證的形狀（`fmp-plugin.d.ts` 的 `FmpLoginCredentials`，ADR 0029 §決定 3）。
///
/// `cookies` 是 cookie 名稱對值；`extra` 給不是 cookie 的東西（B 站刷新用的
/// `refresh_token`）。值都是秘密：[toString] 不印內容。
@immutable
final class LoginCredentials {
  const LoginCredentials({required this.cookies, this.extra = const {}});

  /// 解碼 [json]（`CredentialStore` 存的、或 `login*` 匯出回傳的）。形狀不對丟
  /// [FormatException]，訊息不含值。
  factory LoginCredentials.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json.keys.any((key) => key != 'cookies' && key != 'extra')) {
      throw const FormatException('Credentials must be {cookies, extra?}');
    }
    return LoginCredentials(
      cookies: _strings(json['cookies'], 'cookies'),
      extra: json['extra'] == null
          ? const {}
          : _strings(json['extra'], 'extra'),
    );
  }

  final Map<String, String> cookies;
  final Map<String, String> extra;

  /// 沒有 `extra` 時不寫該鍵。
  Map<String, Object?> toJson() => {
    'cookies': cookies,
    if (extra.isNotEmpty) 'extra': extra,
  };

  /// 每個秘密值：cookie 值與 `extra` 值。
  Iterable<String> get values => [...cookies.values, ...extra.values];

  static Map<String, String> _strings(Object? value, String field) {
    if (value is! Map<String, Object?> ||
        value.values.any((entry) => entry is! String)) {
      throw FormatException('"$field" must be a string map');
    }
    return Map.unmodifiable({
      for (final MapEntry(:key, :value) in value.entries) key: value! as String,
    });
  }

  @override
  bool operator ==(Object other) =>
      other is LoginCredentials &&
      mapEquals(other.cookies, cookies) &&
      mapEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(cookies.entries.map((e) => (e.key, e.value))),
    Object.hashAllUnordered(extra.entries.map((e) => (e.key, e.value))),
  );

  @override
  String toString() =>
      'LoginCredentials(cookies: ${cookies.length}, extra: ${extra.length})';
}
