import 'package:fmp/platform/cache_sizes/cache_sizes.dart';

/// macOS：和 Windows 同樣的桌面預設（ADR 0016 §決定 3）：磁碟快取 256 MiB，記憶體
/// `ImageCache` 200 張／80 MiB。
const macosCacheSizes = CacheSizes(
  defaultLimitMebibytes: 256,
  memoryImages: 200,
  memoryImageMebibytes: 80,
);
