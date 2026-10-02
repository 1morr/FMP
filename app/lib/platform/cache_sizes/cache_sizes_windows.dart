import 'package:fmp/platform/cache_sizes/cache_sizes.dart';

/// Windows：磁碟快取預設 256 MiB（ADR 0016 §決定 3 的桌面平台）。
///
/// 記憶體 `ImageCache` 200 張／80 MiB 沿用舊版（舊專案 `lib/main.dart:156-164`）：
/// 桌面的多欄版面同時看得到更多縮圖。
const windowsCacheSizes = CacheSizes(
  defaultLimitMebibytes: 256,
  memoryImages: 200,
  memoryImageMebibytes: 80,
);
