import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:material_ui/material_ui.dart';

/// 封面圖的磁碟快取（ARCHITECTURE〈快取〉）：套件只能限檔數與多久沒用，
/// 所以上限是 1000 個檔、30 天沒用就刪。請求不經插件宿主的網路層。
final _covers = CacheManager(
  Config(
    'fmpCovers',
    stalePeriod: const Duration(days: 30),
    maxNrOfCacheObjects: 1000,
  ),
);

/// 插件給的封面網址 [url] 的圖，先找磁碟快取。
ImageProvider coverImage(String url) =>
    CachedNetworkImageProvider(url, cacheManager: _covers);
