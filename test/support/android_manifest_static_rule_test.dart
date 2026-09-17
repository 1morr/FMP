/// `android:allowBackup` 必須是 false，而且這不是偏好。
///
/// Android 自動備份會把 shared preferences 還原到另一台裝置，那台的 keystore
/// 沒有原本的金鑰，`flutter_secure_storage` 解不開還原回來的憑證，之後每一次
/// 帳號讀取都拋 `PlatformException` —— issue #35 的永久載入態就是這樣來的。
/// 理由寫在 manifest 的註解裡；這條規則守的是有人把它改回 true 或整個拿掉。
/// 拿掉等於 true，因為那是 Android 的預設值。
///
/// 代價寫在 `docs/troubleshooting.md`：換手機時 FMP 的資料不會跟著系統備份走。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _manifestPath = 'android/app/src/main/AndroidManifest.xml';

/// `<application>` 標籤上 `android:allowBackup` 的值；沒寫就是 null。
///
/// 只看 `<application` 那一個開始標籤，註解裡提到這個屬性不算。
String? applicationAllowBackup(String manifest) {
  final withoutComments = manifest.replaceAll(
    RegExp(r'<!--.*?-->', dotAll: true),
    '',
  );
  final application = RegExp(
    r'<application\b[^>]*>',
    dotAll: true,
  ).firstMatch(withoutComments);
  if (application == null) return null;
  return RegExp(
    r'''android:allowBackup\s*=\s*["']([^"']*)["']''',
  ).firstMatch(application.group(0)!)?.group(1);
}

void main() {
  group('Android manifest backup policy', () {
    test('the application element turns auto-backup off', () {
      final manifest = File(_manifestPath).readAsStringSync();

      expect(
        applicationAllowBackup(manifest),
        'false',
        reason:
            'android:allowBackup must stay "false": a restore onto another '
            'keystore leaves credentials flutter_secure_storage cannot read '
            '(issue #35). Dropping the attribute means true.',
      );
    });

    test('the reader detects the attribute being flipped or dropped', () {
      expect(
        applicationAllowBackup('<application android:allowBackup="true">'),
        'true',
      );
      expect(
        applicationAllowBackup('<application android:label="FMP">'),
        isNull,
      );
    });

    test('the reader ignores comments, attribute order and other tags', () {
      const manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- android:allowBackup="true" used to be here -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <application
        android:label="FMP"
        android:icon="@mipmap/ic_launcher"
        android:allowBackup="false">
        <activity android:name=".MainActivity"/>
    </application>
</manifest>
''';

      expect(applicationAllowBackup(manifest), 'false');
    });
  });
}
