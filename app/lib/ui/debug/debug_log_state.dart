import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/logging/log_record.dart';

/// 記憶體歷史變動後多久才重發一次快照。log 一次寫很多筆（網路紀錄、debug 層級）時，每筆都
/// 複製最多 1,000 筆再重建清單太浪費，合併成一次。
const logHistoryRefreshDelay = Duration(milliseconds: 250);

/// 這次執行的記憶體歷史（由舊到新）。Debug 頁的 Log 與網路區塊共用；頁面關掉就停止監聽。
final logHistoryProvider = StreamProvider.autoDispose<List<LogRecord>>((ref) {
  final log = ref.watch(logProvider);
  final controller = StreamController<List<LogRecord>>();
  Timer? pending;
  void emit() {
    pending = null;
    if (!controller.isClosed) controller.add(log.history);
  }

  final subscription = log.changes.listen((_) {
    pending ??= Timer(logHistoryRefreshDelay, emit);
  });
  ref.onDispose(() {
    pending?.cancel();
    unawaited(subscription.cancel());
    unawaited(controller.close());
  });
  controller.add(log.history);
  return controller.stream;
});

/// log 檔裡的紀錄（「含之前的紀錄」，ADR 0025 §決定 3）。要用時才讀，在 isolate 解析；沒有
/// log 檔的平台是空的。Log 區塊清除之後 `invalidate` 它。
final storedLogRecordsProvider = FutureProvider.autoDispose<List<LogRecord>>(
  (ref) async =>
      await ref.watch(logProvider).file?.readStored() ?? const <LogRecord>[],
);

/// 把 log 檔的 [stored] 與記憶體歷史 [memory] 合成一份由舊到新的清單。這次執行寫的每一筆
/// 同時在兩邊，所以「同一筆」就是整行內容（時間到微秒、層級、tag、訊息、欄位）逐字相同的那
/// 一筆：log 檔的一行就是 [LogRecord.toJsonLine]，讀回來再寫出去不變。時間相同的維持原來的
/// 先後（檔案的在前）。
///
/// 兩邊都有的那筆留記憶體裡的物件：錯誤詳細頁以「是不是記憶體歷史裡的那個物件」判斷紀錄是不是
/// 這次執行的，才去對網路紀錄（`networkRecordId` 只在同一次執行唯一）。
List<LogRecord> mergeLogRecords(
  List<LogRecord> stored,
  List<LogRecord> memory,
) {
  final inMemory = {for (final record in memory) record.toJsonLine(): record};
  final seen = <String>{};
  final merged = <LogRecord>[];
  for (final record in [...stored, ...memory]) {
    final line = record.toJsonLine();
    if (seen.add(line)) merged.add(inMemory[line] ?? record);
  }
  final order = {for (var i = 0; i < merged.length; i++) merged[i]: i};
  merged.sort((a, b) {
    final byTime = a.time.compareTo(b.time);
    return byTime != 0 ? byTime : order[a]!.compareTo(order[b]!);
  });
  return merged;
}

/// 「錯誤歷史」：警告以上（ADR 0011 §決定 5：處理過的錯誤以 warning、error 寫入）。
bool isErrorRecord(LogRecord record) =>
    record.level.index >= LogLevel.warning.index;

/// Log 區塊的篩選。
@immutable
final class LogFilter {
  const LogFilter({
    this.level = LogLevel.debug,
    this.tag,
    this.text = '',
    this.errorsOnly = false,
  });

  /// 這個層級以上（含）。
  final LogLevel level;

  /// `null` 是所有 tag。
  final String? tag;

  /// 不分大小寫，比對整筆的文字（[formatLogRecord]：時間、層級、tag、訊息、欄位、錯誤）。
  final String text;
  final bool errorsOnly;

  bool matches(LogRecord record) {
    if (record.level.index < level.index) return false;
    if (errorsOnly && !isErrorRecord(record)) return false;
    if (tag != null && record.tag != tag) return false;
    if (text.isEmpty) return true;
    return formatLogRecord(record).toLowerCase().contains(text.toLowerCase());
  }

  LogFilter copyWith({
    LogLevel? level,
    String? Function()? tag,
    String? text,
    bool? errorsOnly,
  }) => LogFilter(
    level: level ?? this.level,
    tag: tag == null ? this.tag : tag(),
    text: text ?? this.text,
    errorsOnly: errorsOnly ?? this.errorsOnly,
  );
}

/// 一筆 log 的純文字（複製已篩選、文字篩選共用）。時間用 UTC ISO 8601，貼到別處沒有時區的
/// 歧義。內容在進門面時就遮蔽過了。
String formatLogRecord(LogRecord record) {
  final details = formatLogDetails(record);
  return '${record.time.toIso8601String()} ${record.level.wireName} '
      '[${record.tag}] ${record.message}'
      '${details.isEmpty ? '' : '\n$details'}';
}

/// [formatLogRecord] 在第一行之後的部分：欄位、error、stackTrace；都沒有就是空字串。
String formatLogDetails(LogRecord record) {
  final lines = [
    if (record.fields.isNotEmpty) '  fields: ${jsonEncode(record.fields)}',
    if (record.error case final error?) '  error: $error',
    if (record.stackTrace case final stackTrace?) '  stackTrace:\n$stackTrace',
  ];
  return lines.join('\n');
}

/// 清單上的時間：本地時間 `MM-dd HH:mm:ss.SSS`（技術用的固定格式，不跟語言）。
String formatLogTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final millis = local.millisecond.toString().padLeft(3, '0');
  return '${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}.$millis';
}
