part of 'cache_store.dart';

/// 封面的大小上限（design §4.1）。
const artworkMaxBytes = 10 * 1024 * 1024;

/// 沒有 `Cache-Control` 時一份圖片有效多久；和 flutter_cache_manager 的
/// `HttpGetResponse` 相同。
const _defaultFreshness = Duration(days: 7);

/// 一個插件的圖片 cache manager（ADR 0016 §決定 4、design §4.3）：
/// `flutter_cache_manager` 的三個介面換成統一快取庫與媒體 client。
///
/// - 索引（`CacheInfoRepository`）：`cache.db` 裡 `category = image`、
///   `plugin_id` 是這個插件的列。`flutter_cache_manager` 自己的淘汰
///   （`getObjectsOverCapacity`、`getOldObjects`）一律回空：淘汰只有
///   [CacheStore] 依位元組做，不讓兩套規則並存。它每次從索引讀一列之後排的 10 秒
///   清理計時器因此什麼都不刪。
/// - 檔案（`FileSystem`）：`fmp_cache/files/`。`flutter_cache_manager` 每次從
///   索引或記憶體拿到一列都先看檔案還在不在，不在就當未命中、刪掉那一列
///   （3.4.5 `cache_store.dart` 的 `retrieveCacheData`），所以 [CacheStore]
///   從背後刪檔不會讓它交出不存在的檔案。
/// - 下載（`FileService`）：這個插件的媒體 client（每跳檢查允許網域、不帶憑證、
///   大小上限 [artworkMaxBytes]、逾時）。內容先完整下載到 `staging/` 底下
///   每次不同的檔案、讀進記憶體再交出去：同一個目的地不會同時下載兩次（媒體
///   client 的 `.part` 不共用），而交給 `flutter_cache_manager` 寫檔的串流
///   不會中途出錯（它的 `WebHelper` 串流出錯時不刪寫一半的檔）。寫檔本身失敗
///   留下的檔案不在索引裡，下次開啟時的對帳會刪掉。
final class FmpImageCacheManager extends CacheManager {
  FmpImageCacheManager({
    required CacheStore store,
    required String pluginId,
    required MediaHttpClient media,
  }) : super(
         Config(
           // 只有預設的索引與檔案位置會用到它；三個介面都換掉了。
           'fmp-image-$pluginId',
           repo: _ImageIndex(store, pluginId),
           fileSystem: _CacheFiles(store),
           fileService: _MediaFileService(store, media),
         ),
       );
}

/// `cache_entries` 裡一個插件的圖片。
final class _ImageIndex extends CacheInfoRepository {
  _ImageIndex(this._store, this._pluginId);

  final CacheStore _store;
  final String _pluginId;

  CacheDatabase get _database => _store._database;

  $CacheEntriesTableTable get _entries => _store._entries;

  // 索引的開關屬於 CacheStore：每個 cache manager 都不開也不關它。
  @override
  Future<bool> exists() async => true;

  @override
  Future<bool> open() async => true;

  @override
  Future<bool> close() async => true;

  @override
  Future<void> deleteDataFile() async {}

  @override
  Future<CacheObject?> get(String key) async {
    final row =
        await (_database.select(_entries)..where(
              (t) =>
                  t.category.equalsValue(CacheCategory.image) &
                  t.pluginId.equals(_pluginId) &
                  t.key.equals(key),
            ))
            .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<List<CacheObject>> getAllObjects() async {
    final rows =
        await (_database.select(_entries)..where(
              (t) =>
                  t.category.equalsValue(CacheCategory.image) &
                  t.pluginId.equals(_pluginId),
            ))
            .get();
    return [for (final row in rows) _fromRow(row)];
  }

  @override
  Future<CacheObject> insert(
    CacheObject cacheObject, {
    bool setTouchedToNow = true,
  }) => _upsert(cacheObject, setTouchedToNow: setTouchedToNow);

  @override
  Future<int> update(
    CacheObject cacheObject, {
    bool setTouchedToNow = true,
  }) async {
    await _upsert(cacheObject, setTouchedToNow: setTouchedToNow);
    return 1;
  }

  @override
  Future<CacheObject> updateOrInsert(CacheObject cacheObject) =>
      _upsert(cacheObject, setTouchedToNow: true);

  /// 以鍵寫入（有就更新），不看 [CacheObject.id]：`flutter_cache_manager` 記憶體
  /// 裡的物件可能帶著 [CacheStore] 已經刪掉的那一列的 id，照 id 更新會什麼都
  /// 沒寫到、檔案從此不在索引裡。寫完超過上限就淘汰。
  ///
  /// 大小以磁碟上的檔案為準（`CacheManager.putFile` 對已有的鍵沿用舊物件的
  /// `length`）。檔案已經不在就不寫：`flutter_cache_manager` 看過檔案還在之後
  /// 才排一次不等的寫入，清除或淘汰可能插在中間，寫進去就是一列沒有檔案的
  /// 索引。從看檔案、寫入到淘汰，和清除、淘汰、移除插件排在同一條隊伍
  /// （`CacheStore._serially`），中間不會被刪。
  Future<CacheObject> _upsert(
    CacheObject cacheObject, {
    required bool setTouchedToNow,
  }) => _store._serially(() async {
    final file = File(p.join(_store._files.path, cacheObject.relativePath));
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) return cacheObject;
    final lastAccess = setTouchedToNow
        ? clock.now()
        : cacheObject.touched ?? clock.now();
    final entry = CacheEntriesTableCompanion.insert(
      key: cacheObject.key,
      category: CacheCategory.image,
      pluginId: Value(_pluginId),
      relativePath: cacheObject.relativePath,
      sizeBytes: stat.size,
      lastAccess: lastAccess,
      validUntil: cacheObject.validTill,
      etag: Value(cacheObject.eTag),
    );
    final row = await _database
        .into(_entries)
        .insertReturning(
          entry,
          onConflict: DoUpdate(
            (_) => entry,
            target: [_entries.category, _entries.pluginId, _entries.key],
          ),
        );
    await _store._evict();
    return _fromRow(row);
  });

  @override
  Future<int> delete(int id) =>
      (_database.delete(_entries)..where((t) => t.id.equals(id))).go();

  @override
  Future<int> deleteAll(Iterable<int> ids) async {
    // 清理計時器每次都以空清單呼叫（淘汰只由 CacheStore 做）。
    if (ids.isEmpty) return 0;
    return (_database.delete(_entries)..where((t) => t.id.isIn(ids))).go();
  }

  @override
  Future<List<CacheObject>> getObjectsOverCapacity(int capacity) async =>
      const [];

  @override
  Future<List<CacheObject>> getOldObjects(Duration maxAge) async => const [];

  CacheObject _fromRow(CacheEntryRow row) => CacheObject(
    // 圖片的鍵就是實際請求的網址（ADR 0016 §決定 4）。
    row.key,
    key: row.key,
    id: row.id,
    relativePath: row.relativePath,
    validTill: row.validUntil,
    eTag: row.etag,
    length: row.sizeBytes,
    touched: row.lastAccess,
  );
}

/// `fmp_cache/files/`。目錄被系統清掉時重建。
final class _CacheFiles implements FileSystem {
  _CacheFiles(this._store);

  final CacheStore _store;

  @override
  Future<fs.File> createFile(String name) async {
    final directory = await _store._files.create(recursive: true);
    return const LocalFileSystem().file(p.join(directory.path, name));
  }
}

/// 經插件的媒體 client 下載。
final class _MediaFileService extends FileService {
  _MediaFileService(this._store, this._media);

  final CacheStore _store;
  final MediaHttpClient _media;

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final staging = await _store._stagingFile();
    try {
      // headers 是 WebHelper 加的 If-None-Match 與呼叫端的 header；媒體 client
      // 只留 mediaRequestHeaders 的那幾個。
      final download = await _media.download(
        Uri.parse(url),
        destination: staging,
        maxBytes: artworkMaxBytes,
        headers: headers ?? const {},
      );
      return _DownloadedImage(
        await staging.readAsBytes(),
        download.headers,
        receivedAt: clock.now(),
      );
    } on AppError catch (error) {
      _store._log.report(
        'Failed to download an image',
        error,
        tag: cacheLogTag,
      );
      rethrow;
    } finally {
      await _store._deleteFile(staging);
    }
  }
}

/// 已經完整下載的圖片。
final class _DownloadedImage implements FileServiceResponse {
  _DownloadedImage(this._bytes, this._headers, {required DateTime receivedAt})
    : validTill = receivedAt.add(_freshness(_headers));

  final Uint8List _bytes;
  final Map<String, List<String>> _headers;

  @override
  Stream<List<int>> get content => Stream.value(_bytes);

  @override
  int get contentLength => _bytes.length;

  /// 內容已經完整收到；媒體 client 的其他 2xx 也當成新檔案（WebHelper 只收
  /// 200、202）。
  @override
  int get statusCode => HttpStatus.ok;

  @override
  final DateTime validTill;

  @override
  String? get eTag => _headers[HttpHeaders.etagHeader]?.first;

  /// 只給認得的圖片類型副檔名，其他沒有：檔名不由伺服器的字串組成。
  @override
  String get fileExtension => switch (_headers[HttpHeaders.contentTypeHeader]
      ?.first
      .split(';')
      .first
      .trim()
      .toLowerCase()) {
    'image/jpeg' => '.jpg',
    'image/png' => '.png',
    'image/webp' => '.webp',
    'image/gif' => '.gif',
    'image/avif' => '.avif',
    _ => '',
  };

  /// `Cache-Control` 的 `max-age`（大於 0 才算）與 `no-cache`，規則同
  /// flutter_cache_manager 的 `HttpGetResponse`；沒有就是 [_defaultFreshness]。
  static Duration _freshness(Map<String, List<String>> headers) {
    var freshness = _defaultFreshness;
    for (final value in headers[HttpHeaders.cacheControlHeader] ?? const []) {
      for (final directive in value.split(',')) {
        final setting = directive.trim().toLowerCase();
        if (setting == 'no-cache') freshness = Duration.zero;
        if (setting.startsWith('max-age=')) {
          final seconds = int.tryParse(setting.substring('max-age='.length));
          if (seconds != null && seconds > 0) {
            freshness = Duration(seconds: seconds);
          }
        }
      }
    }
    return freshness;
  }
}
