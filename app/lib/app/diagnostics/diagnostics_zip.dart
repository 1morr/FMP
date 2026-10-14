import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

/// zip 裡的一個檔案。
@immutable
final class ZipEntry {
  const ZipEntry(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

/// 把 [entries] 壓成一個 zip。壓縮在另一個 isolate（log 檔最多 6MB，UI isolate 不等它）。
Future<Uint8List> zipEntries(List<ZipEntry> entries) {
  // 只把名稱與位元組送進 isolate；`Isolate.run` 的閉包不帶 [ZipEntry] 以外的狀態。
  return Isolate.run(() => encodeZip(entries));
}

/// [zipEntries] 在 isolate 裡跑的部分（同步壓縮）。
Uint8List encodeZip(List<ZipEntry> entries) {
  final archive = Archive();
  for (final entry in entries) {
    archive.add(ArchiveFile.bytes(entry.name, entry.bytes));
  }
  return ZipEncoder().encodeBytes(archive);
}
