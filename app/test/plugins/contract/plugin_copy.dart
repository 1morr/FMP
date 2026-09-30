import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// 契約執行器的測試用：在 test/fixtures/plugins/ 的副本上做變異。

/// 把測試插件 [name] 複製到暫存目錄。
Directory copyPlugin(String name) {
  final target = Directory.systemTemp.createTempSync('fmp_contract_');
  addTearDown(() => target.deleteSync(recursive: true));
  final source = Directory(p.join('test', 'fixtures', 'plugins', name));
  for (final entry in source.listSync(recursive: true)) {
    final relative = p.relative(entry.path, from: source.path);
    if (entry is Directory) {
      Directory(p.join(target.path, relative)).createSync(recursive: true);
    } else if (entry is File) {
      final copy = File(p.join(target.path, relative));
      copy.parent.createSync(recursive: true);
      entry.copySync(copy.path);
    }
  }
  return target;
}

/// 把 [directory] 裡 [relative] 的第一個 [from] 換成 [to]；沒換到就讓測試失敗
/// （變異沒生效的測試什麼也沒證明）。
void edit(Directory directory, String relative, String from, String to) {
  final file = File(p.join(directory.path, relative));
  final before = file.readAsStringSync();
  final after = before.replaceFirst(from, to);
  expect(after, isNot(before), reason: '"$from" is not in $relative');
  file.writeAsStringSync(after);
}
