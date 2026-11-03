/// iOS 的「家目錄」：App 容器。
///
/// iOS 上 Dart 的 `Platform.environment` 是空的，讀不到 `HOME`（2026-11-03 模擬器實測）；
/// `Directory.systemTemp.path` 是 `<容器>/tmp`，所以容器是它的上一層。[systemTempPath]
/// 結尾不是 `/tmp` 或 `/tmp/` 時回 `null`（不猜）。
String? iosHomeDirectory(String systemTempPath) {
  for (final suffix in const ['/tmp', '/tmp/']) {
    if (systemTempPath.endsWith(suffix) &&
        systemTempPath.length > suffix.length) {
      return systemTempPath.substring(0, systemTempPath.length - suffix.length);
    }
  }
  return null;
}
