import 'package:flutter/foundation.dart';

/// 一 MiB。
const _mebibyte = 1024 * 1024;

/// 平台宣告的快取大小（ADR 0016 §決定 3–4）：磁碟快取上限的預設與 Flutter
/// 記憶體 `ImageCache` 的大小。
///
/// 和 `cache_directory/` 分開放：那個目錄只准快取模組 import，這些值設定頁
/// （「快取上限」的預設）與 `main()`（`ImageCache`）也要讀。
@immutable
final class CacheSizes {
  const CacheSizes({
    required this.defaultLimitMebibytes,
    required this.memoryImages,
    required this.memoryImageMebibytes,
  });

  /// 使用者沒設定「快取上限」時的上限（MiB）。
  final int defaultLimitMebibytes;

  /// `ImageCache.maximumSize`：記憶體裡最多幾張解碼好的圖。
  final int memoryImages;

  /// `ImageCache.maximumSizeBytes`（MiB）。
  final int memoryImageMebibytes;

  int get defaultLimitBytes => defaultLimitMebibytes * _mebibyte;

  int get memoryImageBytes => memoryImageMebibytes * _mebibyte;
}
