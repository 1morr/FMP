Map<String, String>? parseSetCookieHeaders(
  List<String>? setCookieHeaders, {
  void Function(String cookie, Object error)? onParseError,
}) {
  if (setCookieHeaders == null || setCookieHeaders.isEmpty) return null;

  final cookies = <String, String>{};
  for (final cookie in setCookieHeaders) {
    try {
      final firstPart = cookie.split(';').first;
      final separator = firstPart.indexOf('=');
      if (separator <= 0) continue;

      final key = firstPart.substring(0, separator).trim();
      final value = firstPart.substring(separator + 1).trim();
      if (key.isNotEmpty) {
        cookies[key] = value;
      }
    } catch (e) {
      onParseError?.call(cookie, e);
    }
  }
  return cookies.isEmpty ? null : cookies;
}
