import 'package:fmp/platform/cache_sizes/cache_sizes.dart';

/// Android：磁碟快取預設 128 MiB（ADR 0016 §決定 3 的行動平台）。
///
/// 記憶體 `ImageCache` 100 張／50 MiB 沿用舊版（舊專案 `lib/main.dart:156-164`）：
/// 首頁加探索頁同時看得到約 50 張縮圖，太小會反覆淘汰、重新解碼。
const androidCacheSizes = CacheSizes(
  defaultLimitMebibytes: 128,
  memoryImages: 100,
  memoryImageMebibytes: 50,
);
