import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/platform/app_data_directory.dart';

/// 封面圖的磁碟快取（ARCHITECTURE〈快取〉）：套件只能限檔數與多久沒用，
/// 所以上限是 1000 個檔、30 天沒用就刪。請求不經插件宿主的網路層。檔案與
/// 索引放在套件預設的位置，除非 [keepCoverCacheIn] 換過。第一次用到才建
/// （套件建 Config 時就建一個 http client）。
CacheManager get coverCache => _covers ??= CacheManager(_config(_directory));

CacheManager? _covers;
Directory? _directory;

const _key = 'fmpCovers';
const _stalePeriod = Duration(days: 30);
const _maxFiles = 1000;

/// 封面快取的檔案與索引都改放 [data] 底下的 `cache/`：實跑與閘門用隔離的
/// 資料目錄時（[scratchDataName]），不碰套件預設位置裡 dev 版的快取。要在
/// 第一次顯示封面之前呼叫。
void keepCoverCacheIn(Directory data) {
  _directory = data;
  _covers = null;
}

Config _config(Directory? data) {
  if (data == null) {
    return Config(
      _key,
      stalePeriod: _stalePeriod,
      maxNrOfCacheObjects: _maxFiles,
    );
  }
  final cache = '${data.path}${Platform.pathSeparator}cache';
  return Config(
    _key,
    stalePeriod: _stalePeriod,
    maxNrOfCacheObjects: _maxFiles,
    repo: JsonCacheInfoRepository.withFile(
      File('$cache${Platform.pathSeparator}$_key.json'),
    ),
    // 套件把名稱接在系統暫存目錄後面（package:path 的 join）；給絕對路徑時
    // join 照文件丟掉前面那段，檔案就落在這裡。
    fileSystem: IOFileSystem('$cache${Platform.pathSeparator}$_key'),
  );
}

/// 插件給的封面網址 [url] 的圖，先找磁碟快取。
ImageProvider coverImage(String url) =>
    CachedNetworkImageProvider(url, cacheManager: coverCache);
