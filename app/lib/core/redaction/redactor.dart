import 'package:fmp/core/redaction/redaction_lists.dart';

/// 遮蔽後留下的字串。
const redactedValue = '***';

/// 全 App 唯一的遮蔽函式（ADR 0011 §決定 3）。
///
/// 所有會展示或匯出請求內容的地方（log、Toast 詳細、Debug 頁、診斷包）都經過
/// 同一個實例。依序套用：
///
/// 1. header 名單：`Name: 值` 的值整段換掉；`Bearer`、`Basic`、`SAPISIDHASH` 這類
///    授權值單獨出現時也換掉。
/// 2. 鍵名名單：`鍵=值`、`"鍵": "值"`（含跳脫過的 JSON、編碼過的 `%3D`）。
/// 3. 網址：任何主機的 userinfo 換掉；已知媒體 CDN 的網址（含整段百分比
///    編碼、JSON 跳脫斜線的寫法）去除簽名參數，路徑帶簽章的換掉路徑段。
/// 4. 已知憑證值：逐字換掉（帳號層登記目前的實際值，Finamp 的做法）。
///
/// 名單從 `redaction_lists.dart` 起算，插件以 [addRules] 追加。
final class Redactor {
  Redactor() {
    _headerNames.addAll(builtInHeaderNames);
    _keyNames.addAll(builtInKeyNames);
    _mediaCdns.addAll(builtInMediaCdns);
    _compile();
  }

  /// 登記的憑證值至少要這麼長：太短的值逐字替換會把一般文字切碎。
  static const minimumSecretLength = 4;

  final _headerNames = <String>{};
  final _keyNames = <String>{};
  final _mediaCdns = <MediaCdn>[];
  final _secrets = <String>{};

  /// 依長度由長到短，讓較長的憑證先被換掉。
  List<String> _secretsLongestFirst = const [];

  late RegExp _headerPattern;
  late RegExp _keyPattern;

  /// 單獨出現的授權值（不帶 header 名稱，例如被包進錯誤訊息）：scheme 不分
  /// 大小寫，值是至少 [_minimumAuthorizationValueLength] 個 token68 字元
  /// （RFC 9110 §11.2）。一般英文（`bearer of bad news`、`basic
  /// information`）由 [_redactAuthorizationValue] 放過。
  static final _authorizationValuePattern = RegExp(
    r'\b(Bearer|Basic|SAPISIDHASH|SAPISID1PHASH|SAPISID3PHASH)[ \t]+'
    '([A-Za-z0-9._~+/-]{$_minimumAuthorizationValueLength,}=*)',
    caseSensitive: false,
  );

  static const _minimumAuthorizationValueLength = 8;

  /// 全是英文字母、又短於這個長度的值當成一般文字：真的 token（JWT、
  /// base64、SAPISIDHASH 的 `時間_雜湊`）幾乎都含數字或符號，而且更長。
  static const _minimumAlphabeticAuthorizationValueLength = 20;

  static final _alphabetic = RegExp(r'^[A-Za-z]+$');

  static String _redactAuthorizationValue(Match m) {
    final value = m[2]!;
    if (value.length < _minimumAlphabeticAuthorizationValueLength &&
        _alphabetic.hasMatch(value)) {
      return m[0]!;
    }
    return '${m[1]} $redactedValue';
  }

  /// 文字裡的網址；只為了找出媒體 CDN 的網址與 userinfo，所以不求完整。
  /// JSON 跳脫過的 `https:\/\/host\/…` 也算。
  static final _urlPattern = RegExp(
    // 最後一個字元不是反斜線：跳脫過的 JSON 裡網址後面緊接 `\"`。
    r'https?:\\?/\\?/[^\s"'
    "'"
    r'<>`]*[^\s"'
    "'"
    r'<>`\\]',
    caseSensitive: false,
  );

  /// 整段百分比編碼過的網址（例如被當成另一個網址的參數）。
  static final _encodedUrlPattern = RegExp(
    r"https?%3A%2F%2F[\w.~%!$'()*+,;=:@/-]+",
    caseSensitive: false,
  );

  /// 網址裡的 userinfo（`https://user:password@host`），任何主機都遮。
  static final _userInfoPattern = RegExp(
    r'''(https?:\\?/\\?/)[^\s/\\?#@"'<>`]+@''',
    caseSensitive: false,
  );

  /// 追加遮蔽名單（音源插件用）。名單只增不減：多遮一項的代價遠小於漏遮。
  void addRules({
    Iterable<String> headerNames = const [],
    Iterable<String> keyNames = const [],
    Iterable<MediaCdn> mediaCdns = const [],
  }) {
    _headerNames.addAll(headerNames.where((name) => name.isNotEmpty));
    _keyNames.addAll(keyNames.where((name) => name.isNotEmpty));
    _mediaCdns.addAll(mediaCdns);
    _compile();
  }

  /// 登記一個已知的憑證值；之後任何輸出裡出現它都換成 [redactedValue]。
  /// 同時登記它的 URL 編碼形式（cookie 值放進 query 或 header 時常被編碼）。
  ///
  /// 短於 [minimumSecretLength] 的值拋 [ArgumentError]，不默默略過。
  void registerSecret(String value) {
    if (value.length < minimumSecretLength) {
      throw ArgumentError.value(
        '<${value.length} characters>',
        'value',
        'secrets shorter than $minimumSecretLength characters are not accepted',
      );
    }
    _secrets.addAll(_forms(value));
    _sortSecrets();
  }

  /// 取消登記（登出、換帳號時）。沒登記過的值直接略過。
  void unregisterSecret(String value) {
    _secrets.removeAll(_forms(value));
    _sortSecrets();
  }

  /// 遮蔽一段文字。
  String redact(String text) {
    var result = text
        .replaceAllMapped(_headerPattern, _keepNameAndOpening)
        .replaceAllMapped(_authorizationValuePattern, _redactAuthorizationValue)
        .replaceAllMapped(_keyPattern, _keepNameAndOpening)
        .replaceAllMapped(_userInfoPattern, (m) => '${m[1]}$redactedValue@')
        .replaceAllMapped(_urlPattern, (m) => _redactMediaUrl(m[0]!))
        .replaceAllMapped(_encodedUrlPattern, (m) => _redactEncodedUrl(m[0]!));
    for (final secret in _secretsLongestFirst) {
      result = result.replaceAll(secret, redactedValue);
    }
    return result;
  }

  /// 遮蔽任意物件的字串形式（例如 error）。`toString()` 本身拋錯時改用型別名，
  /// log 不因此失敗。
  String redactObject(Object value) => redact(_describe(value));

  /// 遞迴遮蔽結構化欄位，結果只含 JSON 能表示的值（`null`、`bool`、有限的
  /// `num`、`String`、`List`、`Map<String, Object?>`）；其他物件取遮蔽過的字串。
  ///
  /// Map 的鍵在 header 或鍵名名單上時，值整個換成 [redactedValue]。
  Object? redactValue(Object? value) => _redactValue(value, 0);

  static const _maximumDepth = 32;

  Object? _redactValue(Object? value, int depth) {
    if (depth > _maximumDepth) return '<nested too deep>';
    return switch (value) {
      null || bool() => value,
      double() when !value.isFinite => '$value',
      num() => _secrets.contains('$value') ? redactedValue : value,
      String() => redact(value),
      Map() => {
        for (final MapEntry(:key, value: entry) in value.entries)
          if (_describe(key) case final name)
            redact(name): entry != null && _isSensitiveName(name)
                ? redactedValue
                : _redactValue(entry, depth + 1),
      },
      Iterable() => [for (final item in value) _redactValue(item, depth + 1)],
      _ => redactObject(value),
    };
  }

  bool _isSensitiveName(String name) {
    final lower = name.toLowerCase();
    return _headerNames.any((header) => header.toLowerCase() == lower) ||
        _keyNames.any((key) => lower.endsWith(key.toLowerCase()));
  }

  /// 名稱與分隔符照留，值（不含引號與括號）換成 [redactedValue]。第 3 組起
  /// 每兩組是一種值的寫法（開頭、內容），見 [_valueAlternatives]。
  static String _keepNameAndOpening(Match m) {
    var opening = '';
    for (var group = 3; group <= m.groupCount; group += 2) {
      if (m[group] case final matched?) {
        opening = matched;
        break;
      }
    }
    return '${m[1]}${m[2]}$opening$redactedValue';
  }

  /// 百分比編碼過的網址：解碼、照一般網址處理，有變動才重新編碼。
  ///
  /// 只解 ASCII 的跳脫（網址結構 `/?&=` 都在這個範圍），其餘照留：
  /// `Uri.decodeComponent` 遇到不合法的編碼或 UTF-8 會拋錯，那樣整段就
  /// 遮不到了。
  String _redactEncodedUrl(String text) {
    final decoded = text.replaceAllMapped(
      _asciiEscape,
      (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
    );
    final redacted = _redactMediaUrl(decoded);
    return redacted == decoded ? text : Uri.encodeComponent(redacted);
  }

  static final _asciiEscape = RegExp('%([0-7][0-9A-F])', caseSensitive: false);

  String _redactMediaUrl(String matched) {
    // JSON 跳脫的斜線還原後再解析；結果不再跳脫。
    final text = matched.replaceAll(r'\/', '/');
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasAuthority) return matched;
    final cdn = _mediaCdns.where((cdn) => cdn.matches(uri.host)).firstOrNull;
    if (cdn == null) return matched;

    final signed = {
      for (final name in cdn.signedQueryParameters) name.toLowerCase(),
    };
    final query = [
      for (final part in uri.query.split('&'))
        if (part.isNotEmpty && !signed.contains(_queryName(part).toLowerCase()))
          part,
    ].join('&');
    // 保留原本的編碼：切原始路徑，不用解碼過的 pathSegments。第一段是空字串。
    final segments = uri.path.split('/');
    final path = cdn.signedPath && segments.length > 2
        ? [
            '',
            for (var i = 2; i < segments.length; i++) redactedValue,
            segments.last,
          ].join('/')
        : uri.path;
    return '${uri.scheme}://${uri.authority}$path'
        '${query.isEmpty ? '' : '?$query'}'
        '${uri.hasFragment ? '#${uri.fragment}' : ''}';
  }

  static String _queryName(String part) {
    final name = part.split('=').first;
    try {
      return Uri.decodeQueryComponent(name);
    } on Object {
      // 不合法的百分比編碼：照原樣比對。
      return name;
    }
  }

  /// 原值與它的 URL 編碼形式；編碼的十六進位大小寫都算（RFC 3986 視為相同，
  /// 有的實作輸出小寫）。
  static Set<String> _forms(String value) => {
    for (final form in {
      value,
      Uri.encodeQueryComponent(value),
      Uri.encodeComponent(value),
    }) ...{
      form,
      form.replaceAllMapped(_percentEscape, (m) => m[0]!.toLowerCase()),
    },
  };

  static final _percentEscape = RegExp('%[0-9A-F]{2}');

  void _sortSecrets() {
    _secretsLongestFirst = _secrets.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
  }

  void _compile() {
    // 名稱之前不設邊界：`token` 也要遮到 `access_token=`，和結構化欄位的
    // 「以名稱結尾」一致。header 名稱另外要求前面不是字元或 `-`，免得
    // `Cookie` 吃掉 `Set-Cookie` 的名稱。
    _headerPattern = RegExp(
      '(?<![\\w-])(${_alternation(_headerNames)})$_separator'
      '${_valueAlternatives(_headerBareValue)}',
      caseSensitive: false,
    );
    _keyPattern = RegExp(
      '(${_alternation(_keyNames)})$_separator'
      '${_valueAlternatives(_keyBareValue)}',
      caseSensitive: false,
    );
  }

  /// 名稱之後到值之前：名稱的結尾引號（可能是 JSON 跳脫過的 `\"`）、`:` 或
  /// `=`。`=` 也認百分比編碼（`%3D`、雙重編碼的 `%253D`）：網址被當成另一個
  /// 網址的參數時，`access_key%3D值` 也要遮。
  static const _separator = r'''(\\?["']?[ \t]*(?:[:=]|%(?:25)?3D)[ \t]*)''';

  /// 值的各種寫法，每種是（開頭、內容）兩組，開頭照留、內容換掉
  /// （[_keepNameAndOpening]）：JSON 跳脫過的引號（`\"值\"`，整段 JSON 在
  /// 另一個字串裡）、雙引號、單引號（內容可含最多 [_maximumEscapes] 個跳脫
  /// 字元，遮到結尾引號）、`[` 開頭的清單（多值的 header），以及沒有引號的
  /// [bareValue]。沒有結尾引號或 `]` 時遮到行尾。
  ///
  /// 重複的部分只用單一字元類別或有上限的次數：irregexp 的「分組 + `+`」每
  /// 一輪都佔一格回溯堆疊，1MB 的值就會 Stack Overflow（`redactor_test.dart`
  /// 的 `very long input` 守著）。
  static String _valueAlternatives(String bareValue) =>
      r'''(?:(\\["'])([^\\\r\n]*)'''
      '|(")(${_quotedContent('"')})'
      "|(')(${_quotedContent("'")})"
      r'''|(\[)([^\]\r\n]*)'''
      '|()($bareValue))';

  static const _maximumEscapes = 32;

  static String _quotedContent(String quote) =>
      '[^$quote\\\\\\r\\n]*'
      '(?:\\\\.[^$quote\\\\\\r\\n]*){0,$_maximumEscapes}';

  /// 沒有引號的 header 值：到行尾、反斜線，或到包住它的 `}`／`]`。
  static const _headerBareValue = r'''[^\r\n}\]\\]+''';

  /// 沒有引號的鍵值：到下一個分隔符（`&`、`;`、空白、括號、引號、反斜線）
  /// 為止。逗號與 `%` 算在值裡（B 站 `SESSDATA` 的值含逗號，編碼後含
  /// `%2C`）；編碼過的 `&`（`%26`）因此也會被吃進去，多遮不漏。
  static const _keyBareValue = r'''[^"'&;\s}\])\\]+''';

  static String _alternation(Iterable<String> names) =>
      (names.toList()..sort((a, b) => b.length.compareTo(a.length)))
          .map(RegExp.escape)
          .join('|');

  static String _describe(Object? value) {
    try {
      return '$value';
    } on Object catch (error) {
      return '<${value.runtimeType}.toString() threw ${error.runtimeType}>';
    }
  }
}
