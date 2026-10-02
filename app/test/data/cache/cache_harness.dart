import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/media_http_client.dart';
import 'package:fmp/core/redaction/redactor.dart';
import 'package:fmp/data/cache/cache_store.dart';
import 'package:fmp/platform/cache_directory/cache_directory.dart';
import 'package:path/path.dart' as p;

import '../../support/fake_http_adapter.dart';
import '../../support/pump_until.dart';

/// 快取庫的測試環境：暫存目錄當平台快取目錄、debug 層級的 log、不聯網的假
/// adapter（每個插件一個媒體 client，網域是 `example.test`、`cdn.example`）。
/// 開啟的快取庫在測試結束時關閉，暫存目錄接著刪掉（也證明檔案沒被佔住）。
final class CacheHarness {
  CacheHarness({
    FutureOr<ResponseBody> Function(RequestOptions options)? handler,
  }) : adapter = FakeHttpAdapter(handler ?? (_) => image(4)) {
    platformCache = Directory.systemTemp.createTempSync('fmp_cache_test_');
    addTearDown(() => platformCache.deleteSync(recursive: true));
    log = Log(redactor: Redactor(), minimumLevel: LogLevel.debug);
    media = MediaHttpClientFactory(log: log, createAdapter: () => adapter);
  }

  final FakeHttpAdapter adapter;
  late final Directory platformCache;
  late final Log log;
  late final MediaHttpClientFactory media;

  CacheDirectory get directory =>
      CacheDirectory(applicationCachePath: () async => platformCache.path);

  /// `fmp_cache/`。
  Directory get root => Directory(p.join(platformCache.path, 'fmp_cache'));

  Directory get files => Directory(p.join(root.path, 'files'));

  Directory get staging => Directory(p.join(root.path, 'staging'));

  File get databaseFile => File(p.join(root.path, 'cache.db'));

  /// `files/` 裡的檔名。
  Set<String> fileNames() => files.existsSync()
      ? {
          for (final entity in files.listSync())
            if (entity is File) p.basename(entity.path),
        }
      : const {};

  /// `staging/` 裡的東西（不存在就是空的）。
  List<FileSystemEntity> stagingEntries() =>
      staging.existsSync() ? staging.listSync() : const [];

  Future<CacheStore> open({int limitBytes = 1 << 20}) async {
    final store = await openCacheStore(
      directory,
      limitBytes: limitBytes,
      log: log,
    );
    addTearDown(store.close);
    return store;
  }

  /// [pluginId] 的圖片 cache manager。
  FmpImageCacheManager manager(CacheStore store, {String pluginId = 'a'}) =>
      FmpImageCacheManager(
        store: store,
        pluginId: pluginId,
        media: media.create(
          pluginId: pluginId,
          allowedHosts: const ['example.test', 'cdn.example'],
        ),
      );

  /// tag 是 [tag] 的 log。
  List<LogRecord> records(String tag) => [
    for (final record in log.history)
      if (record.tag == tag) record,
  ];
}

/// 一張 [size] 位元組的「圖片」（內容不重要，cache manager 不解碼）。
ResponseBody image(
  int size, {
  String contentType = 'image/png',
  Map<String, String> headers = const {},
}) => ResponseBody.fromBytes(
  Uint8List(size),
  200,
  headers: {
    'content-type': [contentType],
    'content-length': ['$size'],
    for (final MapEntry(:key, :value) in headers.entries)
      key.toLowerCase(): [value],
  },
);

/// 以 [manager] 放一個 [size] 位元組的檔案進快取（不經網路）。
Future<void> put(FmpImageCacheManager manager, String url, int size) =>
    manager.putFile(url, Uint8List(size), fileExtension: 'jpg');

/// 第 [minute] 分鐘（固定時間）：最後存取以它排序。
T at<T>(int minute, T Function() body) =>
    withClock(Clock.fixed(DateTime.utc(2026, 10, 2, 12, minute)), body);

/// 第 [minute] 分鐘以 [manager] 從索引（不看它記憶體裡的那份）讀 [url]，並等它把
/// 最後存取寫成那個時間：flutter_cache_manager 讀到之後才寫，而且不等那次寫入。
Future<FileInfo?> read(
  FmpImageCacheManager manager,
  String url, {
  required int minute,
}) => at(minute, () async {
  final info = await manager.getFileFromCache(url, ignoreMemCache: true);
  if (info != null) {
    final now = clock.now();
    await eventually(
      () async => (await manager.config.repo.get(url))?.touched == now,
      reason: 'last access of $url was not updated',
    );
  }
  return info;
});

/// 等 [check] 成立（索引的寫入在 drift 的背景 isolate，有些是
/// flutter_cache_manager 沒等的寫入）。
Future<void> eventually(
  Future<bool> Function() check, {
  String reason = 'condition never became true',
}) async {
  for (var round = 0; round < 50; round++) {
    if (await check()) return;
    await settle();
  }
  fail(reason);
}
