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

  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();

  test('the launcher label reads the flavor app name', () {
    expect(manifest, contains('android:label="@string/app_name"'));
  });

  test('the main manifest requests INTERNET', () {
    // debug、profile 的 manifest 各有一份，只給 Flutter 工具連進 App；release
    // 只合併 main 這一份，少了它插件連不了網路。
    expect(usesPermissions(manifest), contains(internetPermission));
  });

  test('the Dart display name matches the Android app name', () {
    for (final flavor in AppFlavor.values) {
      expect(appName(flavor), flavor.displayName, reason: flavor.name);
    }
  });

  // 後端契約的 loopback 403 伺服器（integration_test/audio_backend_contract_test.dart）
  // 要明文 HTTP：只有 debug 建置、只對 127.0.0.1。release 只合併 main 與 flavor
  // 的 source set，所以設定只能在 debug 那一份。
  group('cleartext traffic', () {
    final sourceSets = {
      for (final directory in Directory(
        'android/app/src',
      ).listSync().whereType<Directory>())
        directory.uri.pathSegments.lastWhere((s) => s.isNotEmpty): directory,
    };

    test('only the debug manifest points at a network security config', () {
      for (final MapEntry(key: name, value: directory) in sourceSets.entries) {
        final file = File('${directory.path}/AndroidManifest.xml');
        if (!file.existsSync()) continue;
        expect(
          cleartextAttributes(file.readAsStringSync()),
          name == 'debug'
              ? {'networkSecurityConfig': '@xml/network_security_config'}
              : isEmpty,
          reason: name,
        );
      }
    });

    test('only the debug source set has a network security config', () {
      final configs = {
        for (final MapEntry(key: name, value: directory) in sourceSets.entries)
          if (Directory('${directory.path}/res/xml').existsSync())
            for (final file in Directory(
              '${directory.path}/res/xml',
            ).listSync().whereType<File>())
              if (file.readAsStringSync().contains('<network-security-config'))
                '$name/${file.uri.pathSegments.last}',
      };
      expect(configs, {'debug/network_security_config.xml'});
    });

    test('the debug config allows cleartext to 127.0.0.1 only', () {
      expect(cleartextDomains(debugNetworkConfig()), {'127.0.0.1'});
    });
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

    test('a removed or commented-out permission is not requested', () {
      const element =
          '<uses-permission android:name="android.permission.INTERNET"/>';
      expect(manifest, contains(element));
      for (final mutated in [
        manifest.replaceFirst(element, ''),
        manifest.replaceFirst(element, '<!-- $element -->'),
      ]) {
        expect(usesPermissions(mutated), isNot(contains(internetPermission)));
      }
    });

    test('attribute layout does not change the permissions', () {
      final reformatted = manifest.replaceFirst(
        '<uses-permission android:name="android.permission.INTERNET"/>',
        '<uses-permission\n        android:maxSdkVersion="99"\n'
            '        android:name = "android.permission.INTERNET" />',
      );
      expect(reformatted, isNot(manifest));
      expect(usesPermissions(reformatted), usesPermissions(manifest));
    });

    test(
      'cleartext settings anywhere are found, commented-out ones are not',
      () {
        const attribute = 'android:usesCleartextTraffic="true"';
        final mutated = manifest.replaceFirst(
          '<application',
          '<application\n'
              '        $attribute',
        );
        expect(mutated, isNot(manifest));
        expect(cleartextAttributes(mutated), {'usesCleartextTraffic': 'true'});
        expect(
          cleartextAttributes(
            manifest.replaceFirst(
              '<application',
              '<!-- <application $attribute> -->\n'
                  '    <application',
            ),
          ),
          isEmpty,
        );
      },
    );

    test('a wider cleartext config is found', () {
      final config = debugNetworkConfig();
      const domain = '<domain includeSubdomains="false">127.0.0.1</domain>';
      expect(config, contains(domain));
      expect(
        cleartextDomains(
          config.replaceFirst(domain, '$domain\n<domain>example.com</domain>'),
        ),
        {'127.0.0.1', 'example.com'},
      );
      expect(
        cleartextDomains(
          config.replaceFirst(
            '<network-security-config>',
            '<network-security-config>\n'
                '<base-config cleartextTrafficPermitted="true" />',
          ),
        ),
        contains('*'),
      );
      expect(
        cleartextDomains(
          config.replaceFirst(
            domain,
            '<domain includeSubdomains="true">127.0.0.1</domain>',
          ),
        ),
        contains('127.0.0.1 (and subdomains)'),
      );
    });

    test('layout and comments do not change the cleartext domains', () {
      final config = debugNetworkConfig();
      final reformatted = config
          .replaceFirst(
            '<domain-config cleartextTrafficPermitted="true">',
            '<!-- 註解 -->\n<domain-config\n    cleartextTrafficPermitted = "true" >',
          )
          .replaceFirst(
            '<domain includeSubdomains="false">',
            '<domain  includeSubdomains = "false" >',
          );
      expect(reformatted, isNot(config));
      expect(cleartextDomains(reformatted), cleartextDomains(config));
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

const internetPermission = 'android.permission.INTERNET';

/// manifest 裡 `<uses-permission>` 的 `android:name`；註解掉的不算。
Set<String> usesPermissions(String manifest) {
  final live = manifest.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  final name = RegExp(r'android:name\s*=\s*"([^"]*)"');
  return {
    for (final element in RegExp(
      r'<uses-permission(\s[^>]*)>',
    ).allMatches(live))
      if (name.firstMatch(element.group(1)!) case final match?) match.group(1)!,
  };
}

String debugNetworkConfig() =>
    File('android/app/src/debug/res/xml/network_security_config.xml')
        .readAsStringSync();

String _withoutComments(String xml) =>
    xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// manifest 裡放行明文的屬性（`networkSecurityConfig`、`usesCleartextTraffic`）
/// 與它的值；註解掉的不算。
Map<String, String> cleartextAttributes(String manifest) => {
  for (final match in RegExp(
    r'android:(networkSecurityConfig|usesCleartextTraffic)\s*=\s*"([^"]*)"',
  ).allMatches(_withoutComments(manifest)))
    match.group(1)!: match.group(2)!,
};

/// network security config 放行明文的網域。保守地算：檔案裡只要有放行，每個
/// `<domain>` 都算（巢狀的 domain-config 會繼承上層的放行）；`base-config` 放行
/// 就是 `*`。`includeSubdomains="true"`（預設是 `false`）的另外標出來。
Set<String> cleartextDomains(String config) {
  final live = _withoutComments(config);
  final permitted = RegExp(r'cleartextTrafficPermitted\s*=\s*"true"')
      .hasMatch(live);
  if (!permitted) return {};
  return {
    if (RegExp(r'<base-config\s[^>]*cleartextTrafficPermitted\s*=\s*"true"')
        .hasMatch(live))
      '*',
    for (final match in RegExp(
      r'<domain(\s[^>]*)?>\s*([^<\s]+)\s*</domain>',
    ).allMatches(live))
      RegExp(r'includeSubdomains\s*=\s*"true"').hasMatch(match.group(1) ?? '')
          ? '${match.group(2)!} (and subdomains)'
          : match.group(2)!,
  };
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
