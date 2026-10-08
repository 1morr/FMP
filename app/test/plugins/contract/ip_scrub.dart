import 'fixture.dart';

// 錄製者的公網 IP 不得留在 fixture 裡（repo 是公開的）。YouTube 的 `sw.js_data`
// （JSPB 陣列，位置式、沒有鍵名）、innertube 請求的 `context.client.remoteHost`、
// googlevideo 的 `/ip/<位址>/` 路徑段都會帶它，`Redactor` 的名單抓不到這些。
// 重播只比 method 與網址，位址的值不影響結果，所以錄製時整個換成文件用的位址
// （RFC 5737、RFC 3849）。政策與 `redaction_lists.dart` 一樣：寧可多遮也不漏，
// 例如 `Chrome/156.0.0.0` 也會被換掉。

/// 取代 IPv4 用的文件位址（RFC 5737 的 TEST-NET-3）。
const scrubbedIpv4 = '203.0.113.1';

/// 取代 IPv6 用的文件位址（RFC 3849）。
const scrubbedIpv6 = '2001:db8::1';

// 四個 0–255 的十進位段；前面不是數字或「數字加點」，後面不是數字或「點加數字」，
// 所以 `2.20260128.05.00`、`1.2.3.4.5` 的片段不會配上。
final _ipv4 = RegExp(
  r'(?<!\d)(?<!\d\.)'
  r'(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}'
  r'(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)'
  r'(?!\d)(?!\.\d)',
);

// 第一組是 2 或 3 開頭的四位十六進位（全球單播的樣子），之後 2–7 組，前後不連著
// 十六進位字元、冒號或點。是否是位址再由 [_isIpv6] 判斷。
final _ipv6 = RegExp(
  r'(?<![0-9A-Fa-f:.])'
  r'[23][0-9A-Fa-f]{3}(?::{1,2}[0-9A-Fa-f]{0,4}){2,7}'
  r'(?![0-9A-Fa-f:])',
);

bool _isDocumentationIpv4(String address) {
  final octets = address.split('.').map(int.parse).toList();
  return octets[0] == 127 ||
      // `N.0.0.0` 是網段位址、不會配給主機；Chrome 精簡過的 UA 版本號
      // （`Chrome/156.0.0.0`）正是這個樣子，換掉等於改 UA。
      (octets[1] == 0 && octets[2] == 0 && octets[3] == 0) ||
      (octets[0] == 192 && octets[1] == 0 && octets[2] == 2) ||
      (octets[0] == 198 && octets[1] == 51 && octets[2] == 100) ||
      (octets[0] == 203 && octets[1] == 0 && octets[2] == 113);
}

// 有 `::` 壓縮，或剛好八組；至少四個冒號分隔的段（`12:34:56` 這類時間不算）。
bool _isIpv6(String text) {
  final groups = text.split(':');
  if (groups.length < 4) return false;
  return text.contains('::') || groups.length == 8;
}

bool _isDocumentationIpv6(String address) {
  final lower = address.toLowerCase();
  return lower.startsWith('2001:db8:') || lower.startsWith('2001:0db8:');
}

/// 把 [text] 裡的 IP 位址換成文件用的位址（[scrubbedIpv4]、[scrubbedIpv6]）。
///
/// IPv4：四段十進位（0–255），前後不連著其他數字；文件位址段、127/8、
/// `N.0.0.0`（網段位址，也是 Chrome UA 的版本號樣子）不動。IPv6：全球單播樣子（第一組 2 或 3 開頭的四位十六進位），有
/// `::` 或剛好八組；`2001:db8::/32` 不動。
String scrubIpAddresses(String text) => text
    .replaceAllMapped(
      _ipv4,
      (match) => _isDocumentationIpv4(match[0]!) ? match[0]! : scrubbedIpv4,
    )
    .replaceAllMapped(
      _ipv6,
      (match) => !_isIpv6(match[0]!) || _isDocumentationIpv6(match[0]!)
          ? match[0]!
          : scrubbedIpv6,
    );

/// [text] 裡有 [scrubIpAddresses] 會換掉的位址。
bool hasIpAddress(String text) => scrubIpAddresses(text) != text;

/// [fixture] 的每個字串（網址、header、body、JSON 的值與鍵）都過
/// [scrubIpAddresses]。錄製在 `Redactor` 之後、寫檔之前呼叫。
HttpFixture scrubFixtureIps(HttpFixture fixture) =>
    HttpFixture.fromJson(_mapStrings(fixture.toJson(), scrubIpAddresses));

/// fixture 裡還有 IP 位址的地方，格式 `<name>: <路徑> has an IP address`。
/// 路徑只指出位置，不含位址本身。
List<String> ipProblems(String name, HttpFixture fixture) {
  final problems = <String>[];
  void walk(Object? value, String path) {
    switch (value) {
      case final Map<Object?, Object?> map:
        for (final MapEntry(:key, value: entry) in map.entries) {
          if (key is String && hasIpAddress(key)) {
            problems.add('$name: a key under $path has an IP address');
          }
          walk(entry, '$path.$key');
        }
      case final List<Object?> items:
        for (final (index, item) in items.indexed) {
          walk(item, '$path[$index]');
        }
      case final String text:
        if (hasIpAddress(text)) problems.add('$name: $path has an IP address');
    }
  }

  walk(fixture.toJson(), 'fixture');
  return problems;
}

Object? _mapStrings(Object? value, String Function(String) change) =>
    switch (value) {
      final Map<Object?, Object?> map => {
        for (final MapEntry(:key, value: entry) in map.entries)
          if (key is String) change(key): _mapStrings(entry, change),
      },
      final List<Object?> items => [
        for (final item in items) _mapStrings(item, change),
      ],
      final String text => change(text),
      _ => value,
    };
