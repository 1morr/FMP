import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// 快取模組在平台快取目錄底下用的目錄名。多一層是為了不和同一個目錄裡的其他
/// 東西混在一起：Windows prod 的 ProductName 與舊版相同，舊版的歌詞快取也在
/// 同一個平台快取目錄（舊專案 `lyrics_cache_service.dart` 的 `lyrics/`）。
const cacheDirectoryName = 'fmp_cache';

/// 快取目錄（ADR 0016 §決定 2）：平台快取目錄（path_provider 的
/// `getApplicationCacheDirectory()`）底下的 [cacheDirectoryName]。
///
/// - Android 是 `Context.getCacheDir()`，系統空間不夠時可能整個清掉；
/// - Windows 是 `%LOCALAPPDATA%\<CompanyName>\<ProductName>`，dev 的
///   ProductName 是 `fmp-dev`（`windows/runner/app_identity.cmake`），自然和
///   prod 分開。
///
/// 只有快取模組（`lib/data/cache/`）與組裝點 import 這個檔案（lint
/// `fmp_layer_imports` 的 `restrictedImports`）：其他模組不自己拿快取目錄。
/// 兩個平台的差異都在 path_provider 的原生端，所以只有這一個實作，路徑由
/// 組裝點注入。
final class CacheDirectory {
  CacheDirectory({required this._applicationCachePath});

  final Future<String> Function() _applicationCachePath;

  /// 解析並建立目錄。
  Future<Directory> resolve() async =>
      Directory(p.join(await _applicationCachePath(), cacheDirectoryName))
          .create(recursive: true);
}

/// 平台的快取目錄。`main()` 以 `AppPlatform.cacheDirectory` override；沒
/// override 就讀會拋錯。解析與開啟交給快取模組（`cacheStoreProvider`），開不
/// 起來時 App 照常啟動，只是沒有磁碟快取（ADR 0016 §決定 1）。
final cacheDirectoryProvider = Provider<CacheDirectory>(
  (ref) => throw UnimplementedError(
    'cacheDirectoryProvider is overridden by main() with the platform '
    'cache directory',
  ),
);
