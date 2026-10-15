import 'package:flutter/foundation.dart';

import 'package:fmp/core/matching/ts_characters.g.dart';

/// 登記不是由 pub 套件帶進來的第三方授權，`showLicensePage` 會列出（M4 design §8.2）。
/// `main()` 呼叫一次；pub 套件的授權由 Flutter 自己收。
///
/// - OpenCC（Apache-2.0）：匹配用的繁簡字表（`lib/core/matching/ts_characters.g.dart`）
///   由它的 `TSCharacters.txt` 產生。
void registerLicenses() {
  LicenseRegistry.addLicense(
    () => Stream.value(
      const LicenseEntryWithLineBreaks(['OpenCC'], openCcLicense),
    ),
  );
}
