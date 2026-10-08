/// 一個插件可以連的網域（manifest 的允許網域，ADR 0014 §決定 3）。
///
/// 網址的 host 與清單項目相同，或是它的子網域（以 `.` 為界）才算；
/// `evil-bilibili.com` 不是 `bilibili.com` 的子網域。scheme 只准 `https`。
/// 比對不分大小寫、忽略結尾的 `.`（舊版 `SourceUrlPolicy.normalizeHost`）；
/// 帶百分比編碼的 host 一律不准。
final class AllowedHosts {
  AllowedHosts(Iterable<String> hosts, {this.exact = false})
    : _hosts = {
        for (final host in hosts)
          if (_normalize(host) case final normalized when normalized.isNotEmpty)
            normalized,
      };

  final Set<String> _hosts;

  /// 只准清單的項目本身、不含子網域（宿主自己的請求：轉址不得換 host）。
  final bool exact;

  /// [url] 可不可以連。
  bool allows(Uri url) => url.scheme == 'https' && allowsHost(url.host);

  /// [host] 是清單的項目或它的子網域。cookie 的 `Domain` 屬性也用它檢查，
  /// `Domain=com` 這種比清單還寬的網域因此存不進去。
  bool allowsHost(String host) {
    final normalized = _normalize(host);
    // Uri 把非 ASCII 與保留字元留成百分比編碼（`evil.com%2F.bilibili.com`）。
    // 插件的網域都是 ASCII（IDN 寫 punycode），這種 host 一律不准，不去賭
    // 下游會不會把它解碼成別的 host。
    if (normalized.isEmpty || normalized.contains('%')) return false;
    return exact
        ? _hosts.contains(normalized)
        : _hosts.any((allowed) => isSameOrSubdomain(normalized, allowed));
  }

  /// [host] 等於 [domain] 或是它的子網域（以 `.` 為界；RFC 6265 §5.1.3 的
  /// domain-match）。
  static bool isSameOrSubdomain(String host, String domain) {
    final h = _normalize(host);
    final d = _normalize(domain);
    return d.isNotEmpty && (h == d || h.endsWith('.$d'));
  }

  /// [a] 與 [b] 是不是同一個 host（轉址時判斷是否跨網域）。
  static bool sameHost(Uri a, Uri b) =>
      _normalize(a.host) == _normalize(b.host);

  static String _normalize(String host) {
    var normalized = host.trim().toLowerCase();
    while (normalized.endsWith('.')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}
