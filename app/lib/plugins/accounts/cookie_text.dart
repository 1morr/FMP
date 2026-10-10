/// 「貼上 cookie」的輸入解析成 cookie 表（名稱 → 值，ADR 0029 §決定 10）。接受兩種格式，
/// 可以混在一起，逐行判斷：
///
/// - 瀏覽器開發者工具複製的 `Cookie` 標頭：`name=value; name2=value2`（前面可以有
///   `Cookie:`），一行或多行。
/// - Netscape `cookies.txt`（瀏覽器擴充功能匯出的格式）：每行 7 欄以 tab 分隔（複製時 tab
///   變成空白的也接受），名稱與值是最後兩欄。`#` 開頭的是註解，但 `#HttpOnly_` 開頭的是
///   HttpOnly 的 cookie（curl 的寫法）。
///
/// 看不懂的行或片段略過（沒有 `=`、名稱是空的或含空白、欄數不對）。同名的以後面的為準。
/// 值原樣保留（不去引號、不解碼），送出時就是使用者貼的那樣。輸入是秘密：這裡不記 log，
/// 錯誤也不帶內容。
Map<String, String> parseCookieText(String text) {
  final cookies = <String, String>{};
  for (final raw in text.split(RegExp(r'\r\n|\r|\n'))) {
    var line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith(_httpOnlyPrefix)) {
      line = line.substring(_httpOnlyPrefix.length);
    } else if (line.startsWith('#')) {
      continue;
    }
    if (_netscapeFields(line) case (final name, final value)?) {
      cookies[name] = value;
      continue;
    }
    _parseHeader(line, cookies);
  }
  return cookies;
}

const _httpOnlyPrefix = '#HttpOnly_';

final _cookieHeaderPrefix = RegExp(r'^cookie\s*:', caseSensitive: false);
final _whitespace = RegExp(r'\s');
final _whitespaceRun = RegExp(r'\s+');
final _netscapeFlag = RegExp(r'^(TRUE|FALSE)$', caseSensitive: false);

/// Netscape 的一行：domain、include subdomains、path、secure、expires、name、value。
/// 以 tab 分隔；沒有 tab 時以空白分隔（tab 被換成空白的複製）。`Cookie` 標頭的一行不會剛好
/// 是 7 欄、第 2 與第 4 欄是 `TRUE`／`FALSE`、第 5 欄是整數，所以兩種格式分得開。
(String, String)? _netscapeFields(String line) {
  final fields = line.contains('\t')
      ? line.split('\t')
      : line.split(_whitespaceRun);
  if (fields.length != 7 ||
      !_netscapeFlag.hasMatch(fields[1]) ||
      !_netscapeFlag.hasMatch(fields[3]) ||
      int.tryParse(fields[4]) == null) {
    return null;
  }
  final name = fields[5].trim();
  if (name.isEmpty || name.contains(_whitespace)) return null;
  return (name, fields[6].trim());
}

/// `name=value; name2=value2` 的一行。
void _parseHeader(String line, Map<String, String> cookies) {
  final body = line.replaceFirst(_cookieHeaderPrefix, '');
  for (final part in body.split(';')) {
    final equals = part.indexOf('=');
    if (equals < 0) continue;
    final name = part.substring(0, equals).trim();
    if (name.isEmpty || name.contains(_whitespace)) continue;
    cookies[name] = part.substring(equals + 1).trim();
  }
}
