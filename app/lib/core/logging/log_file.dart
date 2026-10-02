import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:path/path.dart' as p;

/// 資料目錄下放 log 檔的子目錄名（ADR 0011 §決定 2）。
const logDirectoryName = 'logs';

/// log 檔的保留期限（ADR 0025 §決定 3）。不做設定項。
const logRetention = Duration(days: 7);

/// 輪替的 JSON Lines log 檔（ADR 0011 §決定 2、ADR 0025 §決定 3）。
///
/// 目前寫入的是 `fmp.jsonl`，超過 [maxBytes] 就改名成 `fmp.1.jsonl`、舊的
/// 往後推成 `fmp.2.jsonl`，總共保留 [keptFiles] 個（含目前這個）；
/// [deleteExpired] 另外刪掉過期的輪替檔。
///
/// [write] 只把一行排進佇列就返回；佇列在背景依序寫入，同一輪事件迴圈內的
/// 多行合成一次 append，UI isolate 不等 I/O。寫入失敗不拋出、也不影響 App：
/// 那一批行丟掉，失敗記在 [failureCount] 與 [lastFailure]，診斷包與
/// Debug 頁（M3）從這裡讀。
final class LogFile {
  LogFile(this.directory, {this.maxBytes = 2 * 1024 * 1024, this.keptFiles = 3})
    : assert(maxBytes > 0),
      assert(keptFiles >= 1);

  static const _baseName = 'fmp';
  static const _extension = '.jsonl';
  static final _rotatedName = RegExp(r'^fmp\.\d+\.jsonl$');

  final Directory directory;

  /// 單檔上限（位元組）。只有單獨一行就超過上限時，那個檔會超過它。
  final int maxBytes;

  /// 保留幾個檔，含目前寫入的那個。
  final int keptFiles;

  /// 目前寫入的檔案。
  File get currentFile => _file(0);

  /// 寫入失敗的次數（每批一次）。
  int get failureCount => _failureCount;
  int _failureCount = 0;

  /// 最近一次寫入失敗的錯誤。
  Object? get lastFailure => _lastFailure;
  Object? _lastFailure;

  final _pending = <String>[];
  var _drainScheduled = false;
  Future<void> _queue = Future.value();

  /// 目前檔案的大小；`null` 表示還沒讀過或上次寫入失敗，下次寫入前重讀。
  int? _currentBytes;

  /// 排入一行（不含換行）。不等待、不拋出。
  void write(String line) {
    _pending.add(line);
    if (_drainScheduled) return;
    _drainScheduled = true;
    _queue = _queue.then((_) => _drain());
  }

  /// 等到目前排入的行都處理完（寫入或記為失敗）。匯出 log 前用。
  Future<void> flush() => _queue;

  /// 刪掉最後修改超過 [logRetention] 的輪替檔（`fmp.N.jsonl`，不限
  /// [keptFiles]），回傳刪了幾個。目前寫入的 `fmp.jsonl` 不動；大小輪替照舊，
  /// 兩個限制先到先刪。排在寫入佇列裡，不和輪替的改名交錯。只動 [directory]
  /// 這一層，目錄不存在就什麼都不做。
  Future<int> deleteExpired() {
    final result = _queue.then((_) => _deleteExpired());
    // 佇列只管先後：錯誤經 result 交給呼叫端，之後的寫入照常排。
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<int> _deleteExpired() async {
    if (!await directory.exists()) return 0;
    final cutoff = clock.now().subtract(logRetention);
    var deleted = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !_rotatedName.hasMatch(p.basename(entity.path))) {
        continue;
      }
      if ((await entity.lastModified()).isBefore(cutoff)) {
        await entity.delete();
        deleted++;
      }
    }
    return deleted;
  }

  Future<void> _drain() async {
    _drainScheduled = false;
    final lines = List.of(_pending);
    _pending.clear();
    try {
      await directory.create(recursive: true);
      var size = _currentBytes ??= await _sizeOf(currentFile);
      final chunk = BytesBuilder(copy: false);
      for (final line in lines) {
        final bytes = utf8.encode('$line\n');
        final chunkSize = size + chunk.length;
        if (chunkSize > 0 && chunkSize + bytes.length > maxBytes) {
          await _append(chunk.takeBytes());
          await _rotate();
          size = 0;
        }
        chunk.add(bytes);
      }
      size += chunk.length;
      await _append(chunk.takeBytes());
      _currentBytes = size;
    } on Object catch (error) {
      _failureCount++;
      _lastFailure = error;
      _currentBytes = null;
    }
  }

  Future<void> _append(Uint8List bytes) async {
    if (bytes.isEmpty) return;
    await currentFile.writeAsBytes(bytes, mode: FileMode.append);
  }

  /// `fmp.jsonl` → `fmp.1.jsonl` → …；超出 [keptFiles] 的那個刪掉。
  Future<void> _rotate() async {
    final oldest = _file(keptFiles - 1);
    if (await oldest.exists()) await oldest.delete();
    for (var index = keptFiles - 2; index >= 0; index--) {
      final file = _file(index);
      if (await file.exists()) await file.rename(_file(index + 1).path);
    }
  }

  File _file(int index) => File(
    p.join(
      directory.path,
      index == 0 ? '$_baseName$_extension' : '$_baseName.$index$_extension',
    ),
  );

  static Future<int> _sizeOf(File file) async =>
      await file.exists() ? await file.length() : 0;
}
