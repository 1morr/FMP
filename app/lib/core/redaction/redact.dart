/// 遮蔽後的值。
const mask = '***';

/// App 唯一的遮蔽函式（brief〈錯誤、log 與診斷〉）：log 寫入前一律經過它，之後的 fixture
/// 錄製與匯出診斷也用它。
///
/// 只用通用的命名慣例判斷，不列音源專屬的名稱或網域（ADR 0038：宿主不含
/// 音源專屬的邏輯）；Cookie 整段遮，所以音源的 cookie 名稱不必列。寧可多遮
/// 也不漏：解析不了的地方往多遮的方向走。對已遮過的文字再呼叫一次結果不變。
String redact(String text) {
  return _redactJsonMembers(text)
      .replaceAllMapped(_url, (m) => _redactSignedUrl(m[0]!))
      .replaceAllMapped(_colonPair, (m) => '${m[1]}${m[2]}$mask')
      .replaceAllMapped(_keyValue, (m) {
        final quote = m[3]!.startsWith(RegExp('["\']')) ? m[3]![0] : '';
        return '${m[1]}${m[2]}$quote$mask$quote';
      })
      .replaceAllMapped(_bearer, (m) => '${m[1]}$mask');
}

/// 名稱以這些字結尾（不分大小寫）就視為敏感：`token` 涵蓋 `access_token`、
/// `X-Csrf-Token`，`cookie` 涵蓋 `Set-Cookie`，`sid` 涵蓋 `SAPISID`。不放
/// `sign`：`design`、`assign` 這類一般英文也以它結尾（網址的簽名參數另外看
/// [_signatureNameEndings]）。
const _sensitiveNameEndings = [
  'token',
  'secret',
  'password',
  'passwd',
  'apikey',
  'api_key',
  'api-key',
  'access_key',
  'accesskey',
  'csrf',
  'cookie',
  'cookies',
  'authorization',
  'auth',
  'session',
  'sessionid',
  'sessid',
  'sid',
  'hmac',
  'sig',
  'signature',
];

/// [_sensitiveNameEndings] 合成的樣式片段，給只比對敏感名稱的 regex 用。
/// 樣式只比對敏感名稱，不敏感的 `名稱:`、`鍵=值` 就不會吃掉後面的文字。
final _sensitiveName =
    '[\\w.-]*(?:${_sensitiveNameEndings.map(RegExp.escape).join('|')})';

bool _isSensitiveName(String name) {
  final lower = name.toLowerCase();
  return _sensitiveNameEndings.any(lower.endsWith);
}

/// 敏感名稱的 `名稱: 值`：header 行，或印出來的 Map（`{a: 1, b: 2}`，鍵可以帶
/// 單引號）。雙引號的鍵是 JSON，由 [_redactJsonMembers] 處理。值到
/// 行尾為止；Map 裡到下一個 `, 鍵:` 或右括號為止。
final _colonPair = RegExp(
  '(?<![\\w-])($_sensitiveName)(?![\\w.-])'
  r"""('?[ \t]*:[ \t]*)[^\r\n]*?(?=, '?[\w-]+'?: |[)\]}]|\r|\n|$)""",
  caseSensitive: false,
);

/// 敏感名稱的 `鍵=值`：query、form body、cookie 字串，等號兩側可以有空白。
/// 帶引號的值到收尾的引號；沒引號的值到 `&`、`;`、`#`、反斜線（JSON 跳脫的
/// `\u0026`）、空白、引號、逗號或右括號為止。
final _keyValue = RegExp(
  '(?<![\\w.-])($_sensitiveName)(?![\\w.-])'
  r'''(\s*=\s*)("[^"\r\n]*"|'[^'\r\n]*'|[^&;#\\\s"'<>,)\]}]+)''',
  caseSensitive: false,
);

/// 沒有 header 名稱的 bearer token。少於 8 個字元的不算，避免吃掉一般英文。
final _bearer = RegExp(r'\b(bearer\s+)[\w.~+/=-]{8,}', caseSensitive: false);

/// JSON 成員的鍵與冒號；值由 [_jsonValueEnd] 手動掃，跳脫的引號才不會提早
/// 結束（用「分組＋重複」的樣式，很長的值會讓 regex 堆疊溢位）。
final _jsonKey = RegExp(r'"([^"\\\r\n]{1,128})"\s*:\s*');

String _redactJsonMembers(String text) {
  final out = StringBuffer();
  var copied = 0;
  for (final m in _jsonKey.allMatches(text)) {
    if (m.start < copied || !_isSensitiveName(m[1]!)) continue;
    final end = _jsonValueEnd(text, m.end);
    if (end == m.end) continue;
    // 不論原本是什麼型別都寫成字串，遮過的 JSON 仍然可以解析。
    out
      ..write(text.substring(copied, m.end))
      ..write('"$mask"');
    copied = end;
  }
  if (copied == 0) return text;
  return (out..write(text.substring(copied))).toString();
}

const _quote = 0x22;
const _backslash = 0x5c;

/// 從 [start] 起的 JSON 值在哪裡結束：字串到沒被跳脫的引號之後，陣列與物件
/// 到對應的右括號之後（略過字串裡的括號），其他值到 `,`、`}`、`]` 或空白。
/// 沒有收尾就到結尾，往多遮的方向走。
int _jsonValueEnd(String text, int start) {
  if (start >= text.length) return start;
  final first = text[start];
  if (first != '"' && first != '[' && first != '{') {
    var i = start;
    while (i < text.length && !',}] \t\r\n'.contains(text[i])) {
      i++;
    }
    return i;
  }
  var depth = 0;
  var inString = false;
  for (var i = start; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (inString) {
      if (c == _backslash) {
        i++;
      } else if (c == _quote) {
        inString = false;
        if (depth == 0) return i + 1;
      }
    } else if (c == _quote) {
      inString = true;
    } else if (text[i] == '[' || text[i] == '{') {
      depth++;
    } else if (text[i] == ']' || text[i] == '}') {
      depth--;
      if (depth == 0) return i + 1;
    }
  }
  return text.length;
}

/// 網址，含 JSON 跳脫的 `https:\/\/`。結尾的標點（句點、逗號、右括號）
/// 不算網址的一部分，反斜線也不算：JSON 字串裡再包的 JSON（例如 fixture 的
/// 回應內文）中，網址後面緊接跳脫引號的 `\`。
final _url = RegExp(
  r'''https?:(?:\\?/){2}[^\s"'<>]*[^\s"'<>.,;:!?)\]}\\]''',
  caseSensitive: false,
);

/// 網址的帳密（`//帳號:密碼@主機`）。
final _userInfo = RegExp(
  r'^(https?:(?:\\?/){2})[^/\\?#@]+@',
  caseSensitive: false,
);

/// query 的分隔：`&`、HTML 的 `&amp;`、JSON 跳脫的 `&`。
final _querySeparator = RegExp(r'&amp;|&|\\u0026', caseSensitive: false);

/// 任一參數名稱以這些字結尾，就是帶簽名的網址。
const _signatureNameEndings = ['sig', 'sign', 'signature', 'hmac'];

/// 帶簽名的網址裡照原樣留下的有效期參數（名稱完全相同，不分大小寫）：值
/// 只是時間，不是憑證（擁有者 2026-11-12）。插件要從遮過的 fixture 讀得到
/// 有效期，契約測試才驗得到。
const _expiryNames = {'deadline', 'expire', 'expires', 'expiry'};

/// 純時間戳：unix 秒（10 位數）或毫秒（13 位數）。其他形式的值照樣遮。
final _timestamp = RegExp(r'^\d{10}(?:\d{3})?$');

bool _isExpiry(String name, String value) =>
    _expiryNames.contains(name.toLowerCase()) && _timestamp.hasMatch(value);

/// 遮掉網址的帳密；帶簽名的網址再把 query 的值全部遮掉、只留參數名稱：同一個網址裡的使用者
/// id、由 IP 算出的值各音源叫法不同，宿主不列音源專屬的名單，所以整段遮。
/// 例外是純時間戳的有效期參數（[_isExpiry]）。沒有簽名參數的網址原樣留著。
String _redactSignedUrl(String rawUrl) {
  final url = rawUrl.replaceFirstMapped(_userInfo, (m) => '${m[1]}$mask@');
  final queryStart = url.indexOf('?');
  if (queryStart < 0) return url;
  final hash = url.indexOf('#', queryStart);
  final queryEnd = hash < 0 ? url.length : hash;
  final query = url.substring(queryStart + 1, queryEnd);

  final parts = <String>[];
  final separators = <String>[];
  var last = 0;
  for (final m in _querySeparator.allMatches(query)) {
    parts.add(query.substring(last, m.start));
    separators.add(m[0]!);
    last = m.end;
  }
  parts.add(query.substring(last));

  final signed = parts.any((part) {
    final name = part.split('=').first.toLowerCase();
    return _signatureNameEndings.any(name.endsWith);
  });
  if (!signed) return url;

  final out = StringBuffer(url.substring(0, queryStart + 1));
  for (final (i, part) in parts.indexed) {
    final eq = part.indexOf('=');
    if (eq < 0 || _isExpiry(part.substring(0, eq), part.substring(eq + 1))) {
      out.write(part);
    } else {
      out.write('${part.substring(0, eq)}=$mask');
    }
    if (i < separators.length) out.write(separators[i]);
  }
  return (out..write(url.substring(queryEnd))).toString();
}
