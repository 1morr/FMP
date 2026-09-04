import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 單檔輪替的 log 落盤。
///
/// 庫裡沒有現成的輪替工具可以沿用 —— `lyrics_cache_service` 的 `_evictOldest`
/// 是「多個獨立快取檔按存取時間淘汰」，跟「一個持續長大的檔案超過上限就換一個」
/// 是不同的形狀。
///
/// 寫入是非同步且串接的：呼叫 [write] 只把一行排進佇列就返回，任何 I/O 失敗都
/// 被吞掉。log 落盤不能成為 app 的失敗來源 —— 寫不進去時記憶體緩衝仍然有值。
class LogFileSink {
  LogFileSink({
    required this.directory,
    this.fileName = 'fmp.log',
    this.maxBytes = 2 * 1024 * 1024,
    this.keptFiles = 3,
  }) : assert(keptFiles >= 1);

  /// 路徑沿用 `resolveFmpDatabaseDirectory()` 的做法：app documents 底下的
  /// `FMP/` 子目錄，再開一層 `logs/`。
  static Future<LogFileSink> inAppDocuments() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'FMP', 'logs'));
    return LogFileSink(directory: directory);
  }

  final Directory directory;
  final String fileName;

  /// 單檔上限。
  final int maxBytes;

  /// 保留幾個檔（含當前檔）。
  final int keptFiles;

  File get _current => File(p.join(directory.path, fileName));

  int _currentBytes = 0;
  bool _isOpen = false;

  /// 串接所有寫入，避免輪替跟 append 交錯。
  Future<void> _queue = Future<void>.value();

  bool get isOpen => _isOpen;

  Future<void> open() async {
    if (_isOpen) return;
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      _currentBytes = await _current.exists() ? await _current.length() : 0;
      _isOpen = true;
    } catch (_) {
      // 開不起來就維持關閉，`write` 之後都是 no-op。
      _isOpen = false;
    }
  }

  /// 把一行排進寫入佇列。不等待，也不會拋。
  void write(String line) {
    if (!_isOpen) return;
    _queue = _queue.then((_) => _append(line)).catchError((_) {});
  }

  /// 等待目前排隊的寫入完成。給測試與匯出前用。
  Future<void> flush() => _queue;

  Future<void> _append(String line) async {
    final bytes = '$line\n';
    final length = bytes.length;
    if (_currentBytes > 0 && _currentBytes + length > maxBytes) {
      await _rotate();
    }
    await _current.writeAsString(bytes, mode: FileMode.append, flush: false);
    _currentBytes += length;
  }

  /// `fmp.log` → `fmp.1.log` → … → 超出 [keptFiles] 的那個被刪掉。
  Future<void> _rotate() async {
    final oldest = _rotatedFile(keptFiles - 1);
    if (await oldest.exists()) {
      await oldest.delete();
    }
    for (var index = keptFiles - 2; index >= 1; index--) {
      final file = _rotatedFile(index);
      if (await file.exists()) {
        await file.rename(_rotatedFile(index + 1).path);
      }
    }
    if (await _current.exists()) {
      await _current.rename(_rotatedFile(1).path);
    }
    _currentBytes = 0;
  }

  File _rotatedFile(int index) {
    final base = p.basenameWithoutExtension(fileName);
    final extension = p.extension(fileName);
    return File(p.join(directory.path, '$base.$index$extension'));
  }

  /// 現存的 log 檔，由舊到新。匯出時照這個順序串接才是時間順序。
  Future<List<File>> filesOldestFirst() async {
    final files = <File>[];
    for (var index = keptFiles - 1; index >= 1; index--) {
      final file = _rotatedFile(index);
      if (await file.exists()) files.add(file);
    }
    if (await _current.exists()) files.add(_current);
    return files;
  }

  /// 所有 log 串成一份，給「匯出 log 檔」用。
  Future<String> readAll() async {
    await flush();
    final buffer = StringBuffer();
    for (final file in await filesOldestFirst()) {
      buffer.write(await file.readAsString());
    }
    return buffer.toString();
  }
}
