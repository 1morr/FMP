import 'package:flutter/foundation.dart';

import 'package:fmp/core/logging/log_record.dart';
import 'package:fmp/core/network/network_log.dart';
import 'package:fmp/ui/debug/debug_log_state.dart';

/// 狀態碼類別（ADR 0025 §決定 4）。沒有狀態碼（沒送出、傳輸錯誤）是 [failed]。
enum StatusClass {
  success,
  redirect,
  clientError,
  serverError,
  failed;

  static StatusClass? of(int? status) => switch (status) {
    null => failed,
    >= 200 && < 300 => success,
    >= 300 && < 400 => redirect,
    >= 400 && < 500 => clientError,
    >= 500 && < 600 => serverError,
    // 1xx 與不合規的碼：只在「所有狀態」看得到。
    _ => null,
  };
}

/// 一筆網路紀錄（`network_log.dart` 的 `writeNetworkRecord` 寫的欄位）。
@immutable
final class NetworkEntry {
  const NetworkEntry._(this.record, this.fields);

  /// [record] 不是網路紀錄、或缺了清單必要的欄位（方法、主機、路徑）時回傳 `null`。
  static NetworkEntry? tryParse(LogRecord record) {
    if (record.tag != networkLogTag) return null;
    final fields = record.fields;
    if (fields['method'] is! String ||
        fields['host'] is! String ||
        fields['path'] is! String) {
      return null;
    }
    return NetworkEntry._(record, fields);
  }

  final LogRecord record;
  final Map<String, Object?> fields;

  DateTime get time => record.time;
  int? get id => fields['id'] as int?;
  String get method => fields['method']! as String;
  String get host => fields['host']! as String;
  String get path => fields['path']! as String;
  String? get query => fields['query'] as String?;
  int? get status => fields['status'] as int?;
  int? get ms => fields['ms'] as int?;
  int? get bytes => fields['bytes'] as int?;

  /// 錯誤類型（`error` 欄位）。
  String? get error => fields['error'] as String?;
  bool get credentials => fields['credentials'] == true;
  int get retry => fields['retry'] as int? ?? 0;
  String get client => fields['client'] as String? ?? '';

  /// 音源（插件 id）；宿主自己的請求是空字串。
  String get source => fields['pluginId'] as String? ?? '';

  StatusClass? get statusClass => StatusClass.of(status);
}

/// 歷史裡的網路紀錄，由舊到新。
List<NetworkEntry> networkEntries(List<LogRecord> history) => [
  for (final record in history) ?NetworkEntry.tryParse(record),
];

/// 網路區塊的篩選（ADR 0025 §決定 4）。
@immutable
final class NetworkFilter {
  const NetworkFilter({this.source, this.statusClass, this.text = ''});

  /// `null` 是所有音源；空字串是宿主自己的請求。
  final String? source;
  final StatusClass? statusClass;

  /// 不分大小寫，比對方法、主機、路徑、音源與狀態碼。
  final String text;

  bool matches(NetworkEntry entry) {
    if (source != null && entry.source != source) return false;
    if (statusClass != null && entry.statusClass != statusClass) return false;
    if (text.isEmpty) return true;
    final haystack =
        '${entry.method} ${entry.host}${entry.path} ${entry.source} '
                '${entry.status ?? ''}'
            .toLowerCase();
    return haystack.contains(text.toLowerCase());
  }

  NetworkFilter copyWith({
    String? Function()? source,
    StatusClass? Function()? statusClass,
    String? text,
  }) => NetworkFilter(
    source: source == null ? this.source : source(),
    statusClass: statusClass == null ? this.statusClass : statusClass(),
    text: text ?? this.text,
  );
}

/// [entry] 的對應錯誤紀錄：[history] 裡錯誤欄位 `networkRecordId` 等於它的 `id` 的紀錄
/// （`AppError.networkRecordId`）。id 只在同一次執行裡唯一，所以只拿這次執行的記憶體歷史。
List<LogRecord> matchingErrors(NetworkEntry entry, List<LogRecord> history) {
  final id = entry.id;
  if (id == null) return const [];
  return [
    for (final record in history)
      if (isErrorRecord(record) && record.fields['networkRecordId'] == id)
        record,
  ];
}
