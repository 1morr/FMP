import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/app/licenses.dart';

/// 第三方授權的登記（M4 design §8.2）：`showLicensePage` 讀的就是 `LicenseRegistry`。
void main() {
  // 測試 binding 自己登記的 NOTICES 讀不到 asset；只看這裡登記的。
  setUp(LicenseRegistry.reset);
  tearDown(LicenseRegistry.reset);

  test('registers OpenCC under the Apache License', () async {
    registerLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final openCc = entries.where((entry) => entry.packages.contains('OpenCC'));
    expect(openCc, hasLength(1));
    final text = openCc.single.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('Apache License'));
    expect(text, contains('END OF TERMS AND CONDITIONS'));
  });
}
