import 'package:fmp/platform/cache_sizes/cache_sizes.dart';

/// iOS：行動平台的值（ADR 0016 §決定 3），同 Android：磁碟 128 MiB，記憶體 `ImageCache`
/// 100 張／50 MiB。
const iosCacheSizes = CacheSizes(
  defaultLimitMebibytes: 128,
  memoryImages: 100,
  memoryImageMebibytes: 50,
);
