import 'dart:io' show Platform;

/// 桌面平台（Windows/macOS/Linux）判斷。
///
/// UI 層統一使用此 helper，避免各頁面各自維護
/// `Platform.isWindows || Platform.isMacOS || Platform.isLinux` 的逐字判斷。
bool get isDesktopPlatform =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;
