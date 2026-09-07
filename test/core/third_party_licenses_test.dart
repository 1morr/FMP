import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/third_party_licenses.dart';

/// `showLicensePage()` 只收得到 pub 套件目錄裡的 `LICENSE`，收不到建置時才
/// 下載的 `libmpv-2.dll`。這條測試釘住補回去的那幾筆 —— 它們掉了不會有任何
/// 執行期訊號，只會安靜地少一份 LGPL 揭露。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the protocol research notice is listed on every platform', () async {
    final entries = await thirdPartyLicenses().toList();

    final protocol = entries.firstWhere(
      (entry) => entry.packages.contains('Protocol research'),
    );
    final text = protocol.paragraphs.map((p) => p.text).join(' ');

    expect(text, contains('bilibili-API-collect'));
    // NC 條款是這一則存在的理由之一，不能只留一個連結。
    expect(text, contains('CC BY-NC 4.0'));
    expect(text, contains('netease-cloud-music'));
  });

  test('the lgpl texts are listed on windows and only there', () async {
    final entries = await thirdPartyLicenses().toList();
    final mpv = entries
        .where((entry) => entry.packages.contains('libmpv / FFmpeg'))
        .toList();

    if (!Platform.isWindows) {
      // Android 與 Linux 的包裡沒有 libmpv，列出它會是假的。
      expect(mpv, isEmpty);
      return;
    }

    // LGPL-2.1、LGPL-3.0，以及 LGPL-3.0 依賴的 GPL-3.0。
    expect(mpv, hasLength(3));

    final texts = mpv
        .map((entry) => entry.paragraphs.map((p) => p.text).join(' '))
        .toList();

    expect(texts.first, contains('-Dgpl=false'));
    expect(texts.first, contains('--disable-gpl'));
    expect(texts.first, contains('GNU LESSER GENERAL PUBLIC LICENSE'));
    expect(texts[1], contains('GNU LESSER GENERAL PUBLIC LICENSE'));
    expect(texts[2], contains('GNU GENERAL PUBLIC LICENSE'));
  });

  test('the licence texts are shipped as assets, not inlined', () {
    // `licenses/` 同時是 repo 檔案與 app 資源；少了 pubspec 的那一行，
    // rootBundle 會在使用者打開授權頁時才拋，測試不會提前發現。
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- licenses/'));

    for (final name in ['LGPL-2.1', 'LGPL-3.0', 'GPL-3.0']) {
      final file = File('licenses/$name.txt');
      expect(file.existsSync(), isTrue, reason: '$name.txt is missing');
      expect(file.lengthSync(), greaterThan(5000));
    }
  });

  test('main registers the collector before runApp', () {
    // 收集器是惰性的，忘記登記不會有任何錯誤 —— 授權頁只會少幾筆。
    final source = File('lib/main.dart').readAsStringSync();
    // 用縮排錨定真正的呼叫；`runApp()` 這個字串在註解裡也出現過。
    final call = RegExp(r'^\s+runApp\(', multiLine: true).firstMatch(source);
    expect(call, isNotNull);
    expect(
      source.substring(0, call!.start),
      contains('registerThirdPartyLicenses()'),
    );
  });
}
