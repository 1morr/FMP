import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/app_flavor.dart';

/// Android 的 App 身分（app/AGENTS.md § App 身分）：prod 與舊版相同
/// （ADR 0008 §決定 3），dev 每一項都不同（ADR 0015 §決定 8）。
///
/// Gradle 在 CI 的 Linux 上跑太慢，這裡讀 `android/app/build.gradle.kts` 與各
/// flavor 的 `strings.xml` 算出每個 flavor 的值。讀原始碼的解析以最後一組
/// 變異案例驗證：違規會被算出來、無關的格式改動不影響結果。
void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  String appName(AppFlavor flavor) => parseAppName(
    File('android/app/src/${flavor.name}/res/values/strings.xml')
        .readAsStringSync(),
  );

  test('prod keeps the legacy identity', () {
    expect(parseNamespace(gradle), 'com.personal.fmp');
    expect(parseApplicationId(gradle, AppFlavor.prod), 'com.personal.fmp');
    expect(appName(AppFlavor.prod), 'FMP');
  });

  test('dev differs in every identity value', () {
    expect(parseApplicationId(gradle, AppFlavor.dev), 'com.personal.fmp.dev');
    expect(appName(AppFlavor.dev), 'FMP Dev');
  });

  test('the launcher label reads the flavor app name', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android:label="@string/app_name"'));
  });

  test('the Dart display name matches the Android app name', () {
    for (final flavor in AppFlavor.values) {
      expect(appName(flavor), flavor.displayName, reason: flavor.name);
    }
  });

  group('parser mutations', () {
    test('a removed dev suffix collapses dev onto the prod id', () {
      final mutated = gradle.replaceFirst('applicationIdSuffix = ".dev"', '');
      expect(mutated, isNot(gradle));
      expect(parseApplicationId(mutated, AppFlavor.dev), 'com.personal.fmp');
    });

    test('a flavor-level applicationId overrides the default', () {
      final mutated = gradle.replaceFirst(
        RegExp(r'create\("prod"\) \{'),
        'create("prod") {\n            applicationId = "com.other"',
      );
      expect(mutated, isNot(gradle));
      expect(parseApplicationId(mutated, AppFlavor.prod), 'com.other');
    });

    test('reformatting and comments leave the values unchanged', () {
      final reformatted = gradle
          .replaceAll('create("dev") {', 'create( "dev" )\n  {  // dev\n')
          .replaceAll(' = ', '=')
          .replaceAll('    ', '\t');
      expect(reformatted, isNot(gradle));
      for (final flavor in AppFlavor.values) {
        expect(
          parseApplicationId(reformatted, flavor),
          parseApplicationId(gradle, flavor),
        );
      }
      expect(parseNamespace(reformatted), parseNamespace(gradle));
    });

    test('app name parsing ignores other strings and layout', () {
      expect(
        parseAppName(
          '<resources>\n  <string name="other">x</string>\n'
          '  <string   name="app_name" >FMP Dev</string></resources>',
        ),
        'FMP Dev',
      );
    });
  });
}

String parseNamespace(String gradle) =>
    _single(RegExp(r'^\s*namespace\s*=\s*"([^"]+)"', multiLine: true), gradle);

/// defaultConfig 的 applicationId 加上該 flavor 的 applicationIdSuffix；
/// flavor 自己寫了 applicationId 就以它為準（Gradle 的規則）。
String parseApplicationId(String gradle, AppFlavor flavor) {
  final defaultConfig = _single(
    RegExp(r'defaultConfig\s*\{([^{}]*)\}'),
    gradle,
  );
  final flavorBlock = _single(
    RegExp('create\\(\\s*"${flavor.name}"\\s*\\)\\s*\\{([^{}]*)\\}'),
    gradle,
  );
  final id = RegExp(r'applicationId\s*=\s*"([^"]+)"');
  final suffix = RegExp(r'applicationIdSuffix\s*=\s*"([^"]*)"');
  final base =
      id.firstMatch(flavorBlock)?.group(1) ?? _single(id, defaultConfig);
  return base + (suffix.firstMatch(flavorBlock)?.group(1) ?? '');
}

String parseAppName(String stringsXml) => _single(
  RegExp(r'<string\s+name="app_name"\s*>([^<]*)</string>'),
  stringsXml,
);

String _single(RegExp pattern, String source) {
  final matches = pattern.allMatches(source).toList();
  if (matches.length != 1) {
    throw StateError(
      'expected one match of ${pattern.pattern}, got ${matches.length}',
    );
  }
  return matches.single.group(1)!;
}
