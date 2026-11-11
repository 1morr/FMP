/// 遮蔽後的值。
const mask = '***';

/// App 唯一的遮蔽函式（brief §13）：log 寫入前一律經過它，之後的 fixture
/// 錄製與匯出診斷也用它。
///
/// 只用通用的命名慣例判斷，不列音源專屬的名稱或網域（ADR 0038：宿主不含
/// 音源專屬的邏輯）；Cookie 整段遮，所以音源的 cookie 名稱不必列。寧可多遮
/// 也不漏：解析不了的地方往多遮的方向走。對已遮過的文字再呼叫一次結果不變。
String redact(String text) {
  return _redactJsonMembers(text)
      .replaceAllMapped(_url, (m) => _redactSignedUrl(m[0]!))
      .replaceAllMapped(_colonPair, (m) => '${m[1]}${m[2]}$mask')
      .replaceAllMapped(
        _keyValue,
        (m) => _isSensitiveName(m[1]!) ? '${m[1]}=$mask' : m[0]!,
      )
      .replaceAllMapped(_bearer, (m) => '${m[1]}$mask');
}

/// 名稱以這些字結尾（不分大小寫）就視為敏感：`token` 涵蓋 `access_token`、
/// `X-Csrf-Token`，`cookie` 涵蓋 `Set-Cookie`，`sid` 涵蓋 `SAPISID`。
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
  'sign',
  'signature',
];

bool _isSensitiveName(String name) {
  final lower = name.toLowerCase();
  return _sensitiveNameEndings.any(lower.endsWith);
}

/// 敏感名稱的 `名稱: 值`：header 行，或印出來的 Map（`{a: 1, b: 2}`）。值到
/// 行尾為止；Map 裡到下一個 `, 鍵:` 或結尾的 `}` 為止。名稱的結尾寫進樣式
/// 裡，不敏感的 `名稱:`（例如 `failed:`、時間的 `12:`）才不會吃掉後面的文字。
final _colonPair = RegExp(
  '(?<![\\w-])([\\w-]*(?:${_sensitiveNameEndings.join('|')}))(?![\\w-])'
  r'([ \t]*:[ \t]*)[^\r\n]*?(?=, [\w-]+: |\}|\r|\n|$)',
  caseSensitive: false,
);

/// `鍵=值`：query、form body、cookie 字串。值到 `&`、`;`、`#`、空白、引號、
/// 逗號或右括號為止。
final _keyValue = RegExp(r'''(?<![\w.-])([\w.-]+)=([^&;\s"'<>,#)\]}]+)''');

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
    final quoted = text.codeUnitAt(m.end) == _quote;
    out
      ..write(text.substring(copied, m.end))
      ..write(quoted ? '"$mask"' : mask);
    copied = end;
  }
  if (copied == 0) return text;
  return (out..write(text.substring(copied))).toString();
}

const _quote = 0x22;
const _backslash = 0x5c;

/// 從 [start] 起的 JSON 值在哪裡結束：字串到沒被跳脫的引號之後（沒有收尾就
/// 到結尾），其他值到 `,`、`}`、`]` 或空白。
int _jsonValueEnd(String text, int start) {
  if (start >= text.length) return start;
  if (text.codeUnitAt(start) == _quote) {
    for (var i = start + 1; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c == _backslash) {
        i++;
      } else if (c == _quote) {
        return i + 1;
      }
    }
    return text.length;
  }
  var i = start;
  while (i < text.length && !',}] \t\r\n'.contains(text[i])) {
    i++;
  }
  return i;
}

/// 網址，含 JSON 跳脫的 `https:\/\/`。
final _url = RegExp(r'''https?:(?:\\?/){2}[^\s"'<>]+''', caseSensitive: false);

/// query 的分隔：`&`、HTML 的 `&amp;`、JSON 跳脫的 `&`。
final _querySeparator = RegExp(r'&amp;|&|\\u0026', caseSensitive: false);

/// 任一參數名稱以這些字結尾，就是帶簽名的網址。
const _signatureNameEndings = ['sig', 'sign', 'signature', 'hmac'];

/// 帶簽名的網址把 query 的值全部遮掉、只留參數名稱：同一個網址裡的使用者
/// id、由 IP 算出的值各音源叫法不同，宿主不列音源專屬的名單，所以整段遮。
/// 沒有簽名參數的網址原樣留著。
String _redactSignedUrl(String url) {
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
    out.write(eq < 0 ? part : '${part.substring(0, eq)}=$mask');
    if (i < separators.length) out.write(separators[i]);
  }
  return (out..write(url.substring(queryEnd))).toString();
}
