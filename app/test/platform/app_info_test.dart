import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/platform/app_info/app_info.dart';
import 'package:fmp/platform/app_info/package_info_app_info.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  // 版本號取 package_info_plus 的 version（pubspec 的版本，不含 build number）；平台名稱與
  // 家目錄是組裝點給的。
  test('reads the version and keeps the platform and home directory', () async {
    PackageInfo.setMockInitialValues(
      appName: 'FMP Dev',
      packageName: 'com.personal.fmp.dev',
      version: '2.0.0',
      buildNumber: '2000000',
      buildSignature: '',
    );

    expect(
      await const PackageInfoAppInfo(
        platform: 'Windows',
        homeDirectory: r'C:\Users\tester',
      ).read(),
      const AppInfo(
        version: '2.0.0',
        platform: 'Windows',
        homeDirectory: r'C:\Users\tester',
      ),
    );
  });
}
