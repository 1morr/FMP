import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `android/app/src/main/java/com/personal/fmp/dev/MediaKeyFix.java` 用反射讀
/// audio_service 的私有欄位（`instance`、`mediaSession`、`mediaSessionCallback`）與
/// 內部類別 `MediaSessionCallback`，並假設真正的 PLAY / PAUSE 鍵走 `onClick`、
/// BYPASS 鍵走 `onPlay` / `onPause`（事實 A6）。這些都不是套件的公開介面，改名或改
/// 行為時反射會失敗（只記 warning，媒體鍵回到會切換的舊行為），沒人會發現。
/// 升級 audio_service 時：對照新版的 `AudioService.java` 確認這幾個名稱與
/// `onMediaButtonEvent` 的行為，同步 `MediaKeyFix.java`、`proguard-rules.pro` 與
/// `build.gradle.kts` 的 `androidx.media` 版本，再改下面的版本。
const reviewedAudioServiceVersion = '0.18.19';

void main() {
  test('audio_service is the version MediaKeyFix.java was written against', () {
    final lock = File('pubspec.lock').readAsStringSync();
    final entry = RegExp(
      r'^  audio_service:\n(?:    .*\n)*?    version: "([^"]+)"',
      multiLine: true,
    ).firstMatch(lock);

    expect(
      entry?.group(1),
      reviewedAudioServiceVersion,
      reason:
          'audio_service changed. Re-check the private fields instance, '
          'mediaSession, mediaSessionCallback and the onMediaButtonEvent key '
          'handling in AudioService.java against MediaKeyFix.java, '
          'proguard-rules.pro and androidx.media in build.gradle.kts, then '
          'update reviewedAudioServiceVersion.',
    );
  });
}
