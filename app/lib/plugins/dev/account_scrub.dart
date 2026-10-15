import 'package:fmp/core/network/fixture/fixture.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/plugins/source_dto.dart';

// 錄 login 案例時的帳號換值（#254、design §5.4）：回應裡的帳號識別值，以 `loginVerify`
// 回傳的帳號本身為準換成 `***`，不靠 manifest 的鍵名（鍵名分不出自己和別人，會弄壞
// 別人的 id、頭像，也要重錄現有 fixture）。做法同 `ip_scrub`：在 `Redactor` 之後、
// 寫檔之前。

/// 名稱與 id 的比對：整個值相等，或（4 個字元以上時）包含它。短的值只比整個值，才不會
/// 在無關的字串裡誤中。全是數字的值只在數字邊界算（`aid=9123456780` 不含 id
/// `12345678`），同 `Redactor.registerSecret`。
final class _Value {
  _Value(this.text)
    : _pattern = RegExp(
        _digits.hasMatch(text)
            ? '(?<![0-9])${RegExp.escape(text)}(?![0-9])'
            : RegExp.escape(text),
      );

  static final _digits = RegExp(r'^[0-9]+$');

  final String text;
  final RegExp _pattern;

  bool isIn(String string) =>
      string == text || (text.length >= 4 && _pattern.hasMatch(string));

  String replaceIn(String string) {
    if (string == text) return redactedValue;
    return text.length >= 4
        ? string.replaceAll(_pattern, redactedValue)
        : string;
  }

  bool matchesNumber(num number) => '$number' == text;
}

/// 頭像網址的主機＋路徑（不看 scheme 與 query）：網易雲的頭像在回應裡是 `http://…jpg`，
/// 插件改寫成 `https://…jpg?param=…` 才回傳。路徑只有 `/` 的不算頭像，免得換掉整個主機。
final class _Avatars {
  _Avatars(LoginAccount account)
    : _keys = {for (final artwork in account.avatar) ?_key(artwork.url)};

  final Set<String> _keys;

  static final _url = RegExp(
    r'''https?://[^\s"'<>\\]+''',
    caseSensitive: false,
  );

  static String? _key(Uri uri) => uri.host.isEmpty || uri.path.length <= 1
      ? null
      : '${uri.host.toLowerCase()}${uri.path}';

  bool _isAvatar(Match match) {
    final uri = Uri.tryParse(match[0]!);
    return uri != null && _keys.contains(_key(uri));
  }

  bool isIn(String string) => _url.allMatches(string).any(_isAvatar);

  /// 頭像網址換成 `<scheme>://<主機>/***`：插件只看主機，重播時 `avatar` 仍然非空。
  String replaceIn(String string) => string.replaceAllMapped(_url, (match) {
    if (!_isAvatar(match)) return match[0]!;
    final uri = Uri.parse(match[0]!);
    return '${uri.scheme}://${uri.authority}/$redactedValue';
  });
}

bool _anyLeaf(
  Object? value,
  bool Function(String) onString,
  bool Function(num) onNumber,
) => switch (value) {
  final String string => onString(string),
  final num number => onNumber(number),
  final Map<Object?, Object?> map => map.entries.any(
    (entry) =>
        _anyLeaf(entry.key, onString, onNumber) ||
        _anyLeaf(entry.value, onString, onNumber),
  ),
  final Iterable<Object?> items => items.any(
    (item) => _anyLeaf(item, onString, onNumber),
  ),
  _ => false,
};

Object? _mapLeaves(
  Object? value,
  String Function(String) onString,
  Object? Function(num) onNumber,
) => switch (value) {
  final String string => onString(string),
  final num number => onNumber(number),
  final Map<Object?, Object?> map => {
    for (final entry in map.entries)
      onString('${entry.key}'): _mapLeaves(entry.value, onString, onNumber),
  },
  final Iterable<Object?> items => [
    for (final item in items) _mapLeaves(item, onString, onNumber),
  ],
  _ => value,
};

/// 把 [fixtures]（已遮蔽）裡 [account] 的 `userId`、`displayName` 換成 `***`，頭像網址換成
/// `<scheme>://<主機>/***`。請求方法、回應狀態碼與 meta 不動。
List<HttpFixture> scrubAccount(
  List<HttpFixture> fixtures,
  LoginAccount account,
) {
  final values = [
    for (final text in [account.userId, account.displayName])
      if (text.isNotEmpty) _Value(text),
  ];
  final avatars = _Avatars(account);
  String onString(String string) {
    var result = avatars.replaceIn(string);
    for (final value in values) {
      result = value.replaceIn(result);
    }
    return result;
  }

  Object? onNumber(num number) =>
      values.any((value) => value.matchesNumber(number))
      ? redactedValue
      : number;

  Object? scrub(Object? value) => _mapLeaves(value, onString, onNumber);

  HttpFixture scrubOne(HttpFixture fixture) {
    final json = fixture.toJson();
    final response = json['response']! as Map<String, Object?>;
    return HttpFixture.fromJson({
      ...json,
      'request': scrub(json['request']),
      'response': {
        for (final MapEntry(:key, :value) in response.entries)
          key: key == 'status' ? value : scrub(value),
      },
    });
  }

  return [for (final fixture in fixtures) scrubOne(fixture)];
}

/// [fixtures]（已遮蔽）裡仍看得到的 [account] 欄位名稱（`userId`、`displayName`、
/// `avatar`）。比對每個 JSON 值：名稱與 id 的規則見 [_Value]，數字的字面等於它；頭像比對
/// 網址的主機＋路徑。[scrubAccount] 之後的最後一道檢查。
List<String> accountLeaks(List<HttpFixture> fixtures, LoginAccount account) {
  final json = [for (final fixture in fixtures) fixture.toJson()];
  bool leaksValue(String text) {
    if (text.isEmpty) return false;
    final value = _Value(text);
    return _anyLeaf(json, value.isIn, value.matchesNumber);
  }

  return [
    if (leaksValue(account.userId)) 'userId',
    if (leaksValue(account.displayName)) 'displayName',
    if (_anyLeaf(json, _Avatars(account).isIn, (_) => false)) 'avatar',
  ];
}
