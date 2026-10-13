import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:path/path.dart' as p;

import 'package:fmp/core/logging/log_record.dart';

/// 資料目錄下放 log 檔的子目錄名（ADR 0011 §決定 2）。
const logDirectoryName = 'logs';

/// log 檔的保留期限（ADR 0025 §決定 3）。不做設定項。
const logRetention = Duration(days: 7);

/// Debug 頁「含之前的紀錄」讀回 log 檔的位元組上限（ADR 0025 §決定 3）：剛好是預設的
/// 3 個 2MB 檔。
const logReadLimitBytes = 6 * 1024 * 1024;

/// 輪替的 JSON Lines log 檔（ADR 0011 §決定 2、ADR 0025 §決定 3）。
///
/// 目前寫入的是 `fmp.jsonl`，超過 [maxBytes] 就改名成 `fmp.1.jsonl`、舊的
/// 往後推成 `fmp.2.jsonl`，總共保留 [keptFiles] 個（含目前這個）；
/// [deleteExpired] 另外刪掉過期的輪替檔，[clear] 刪掉全部，[readStored] 讀回。
///
/// [write] 只把一行排進佇列就返回；佇列在背景依序寫入，同一輪事件迴圈內的
/// 多行合成一次 append，UI isolate 不等 I/O。刪檔、讀檔都排在同一條佇列上，
/// 不和寫入、輪替的改名交錯。寫入失敗不拋出、也不影響 App：
/// 那一批行丟掉，失敗記在 [failureCount] 與 [lastFailure]，診斷包與
/// Debug 頁（M3）從這裡讀。
final class LogFile {
  LogFile(this.directory, {this.maxBytes = 2 * 1024 * 1024, this.keptFiles = 3})
    : assert(maxBytes > 0),
      assert(keptFiles >= 1);

  static const _baseName = 'fmp';
  static const _extension = '.jsonl';
  static final _rotatedName = RegExp(r'^fmp\.\d+\.jsonl$');
  static final _anyName = RegExp(r'^fmp(\.\d+)?\.jsonl$');

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

  /// 還沒排進佇列處理的那一批；`null` 表示下一行要開新的一批。[clear] 把它封起來，之後寫入的
  /// 行才不會和清除之前的行落在同一批（同一批在清除之前寫完，隨即被刪掉）。
  List<String>? _openBatch;
  Future<void> _queue = Future.value();

  /// 目前檔案的大小；`null` 表示還沒讀過或上次寫入失敗，下次寫入前重讀。
  int? _currentBytes;

  /// 排入一行（不含換行）。不等待、不拋出。
  void write(String line) {
    if (_openBatch case final open?) {
      open.add(line);
      return;
    }
    final batch = _openBatch = [line];
    _queue = _queue.then((_) {
      if (identical(_openBatch, batch)) _openBatch = null;
      return _drain(batch);
    });
  }

  /// 等到目前排入的行都處理完（寫入或記為失敗）。匯出 log 前用。
  Future<void> flush() => _queue;

  /// 刪掉最後修改超過 [logRetention] 的輪替檔（`fmp.N.jsonl`，不限
  /// [keptFiles]），回傳刪了幾個。目前寫入的 `fmp.jsonl` 不動；大小輪替照舊，
  /// 兩個限制先到先刪。排在寫入佇列裡，不和輪替的改名交錯。只動 [directory]
  /// 這一層，目錄不存在就什麼都不做。
  Future<int> deleteExpired() => _exclusive(_deleteExpired);

  /// 刪掉 [directory] 裡全部的 log 檔（目前的與輪替的）。排在寫入佇列裡：清除之前排入的行
  /// 先寫完再刪，清除之後寫入的行不受影響，也不會和輪替的改名交錯。Debug 頁的「清除 log」
  /// （ADR 0025 §決定 3）。
  Future<void> clear() {
    _openBatch = null;
    return _exclusive(_clear);
  }

  /// 讀回 log 檔的紀錄，由舊到新，總共最多 [maxBytes] 位元組：從最新的檔案往回讀，放不下的
  /// 那個檔只取尾端（被切開的頭一行解析不出來，當壞行略過）。壞行略過（[parseLogLines]）。排在寫入佇列裡，
  /// 所以排入的行都已寫入；解析在另一個 isolate，UI isolate 不等 I/O。
  Future<List<LogRecord>> readStored({int maxBytes = logReadLimitBytes}) {
    final path = directory.path;
    return _exclusive(
      () => Isolate.run(() => _readStoredFiles(path, maxBytes)),
    );
  }

  /// 排進寫入佇列。佇列只管先後：錯誤經回傳的 future 交給呼叫端，之後的寫入照常排。
  Future<T> _exclusive<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _clear() async {
    _currentBytes = null;
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && _anyName.hasMatch(p.basename(entity.path))) {
        await entity.delete();
      }
    }
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

  Future<void> _drain(List<String> lines) async {
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

/// [LogFile.readStored] 在 isolate 裡跑的部分：只用路徑與數字，不碰 [LogFile] 本身。
List<LogRecord> _readStoredFiles(String directoryPath, int maxBytes) {
  final directory = Directory(directoryPath);
  if (!directory.existsSync()) return const [];
  final rotated = RegExp(r'^fmp(?:\.(\d+))?\.jsonl$');
  final files = <(int, File)>[];
  for (final entity in directory.listSync(followLinks: false)) {
    if (entity is! File) continue;
    final match = rotated.firstMatch(p.basename(entity.path));
    if (match == null) continue;
    files.add((int.parse(match.group(1) ?? '0'), entity));
  }
  // 編號小的較新。
  files.sort((a, b) => a.$1.compareTo(b.$1));
  var remaining = maxBytes;
  final newestFirst = <List<LogRecord>>[];
  for (final (_, file) in files) {
    if (remaining <= 0) break;
    final length = file.lengthSync();
    final String text;
    if (length <= remaining) {
      text = utf8.decode(file.readAsBytesSync(), allowMalformed: true);
      remaining -= length;
    } else {
      final handle = file.openSync();
      final List<int> tail;
      try {
        handle.setPositionSync(length - remaining);
        tail = handle.readSync(remaining);
      } finally {
        handle.closeSync();
      }
      // 被切開的頭一行是半截 JSON，解析不出來，跟壞行一樣略過；切在行界上時那一行是完整的。
      text = utf8.decode(tail, allowMalformed: true);
      remaining = 0;
    }
    newestFirst.add(parseLogLines(text));
  }
  return [for (final records in newestFirst.reversed) ...records];
}
