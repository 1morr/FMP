/// 可攜版更新的解壓路徑。
///
/// 整包讀進記憶體再寫出去，在 200 MB 的 release ZIP 上會直接把應用打死；改回去
/// 不會有編譯錯誤，也不會讓任何行為測試變紅，因為測試用的 ZIP 只有幾 KB。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('portable ZIP extraction streams in a worker isolate', () {
    final source = File(
      'lib/services/update/update_service.dart',
    ).readAsStringSync();

    expect(source, contains('Isolate.run('));
    expect(source, contains('InputFileStream(zipPath)'));
    expect(source, contains('ZipDecoder().decodeStream('));
    expect(source, contains('OutputFileStream(filePath)'));
    expect(source, contains('file.writeContent(output)'));
    expect(source, isNot(contains('readAsBytesSync()')));
    expect(source, isNot(contains('writeAsBytesSync(file.content')));
  });
}
