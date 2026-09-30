import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/release/verify_release_assets.dart';

/// verify job 是草稿轉正式之前唯一看過產物的東西（ADR 0022 §決定 1），這裡以假
/// 產物證明它擋得住該擋的，也不會被無關的差異擋下。
void main() {
  const tag = 'v2.0.0';
  const versionCode = 2000000;
  final releaseCert = 'ab' * 32;
  late Directory dir;
  late Map<String, ApkBadging?> badging;
  late Map<String, List<ApkSigner>?> signers;
  late List<String>? zipEntries;

  Future<List<String>> verify({String releaseTag = tag}) => verifyReleaseAssets(
    dir: dir,
    tag: releaseTag,
    readBadging: (apk) async => badging[p.basename(apk.path)],
    readSigners: (apk) async => signers[p.basename(apk.path)],
    listZip: (zip) async => zipEntries,
  );

  File asset(String name) => File(p.join(dir.path, name));

  void writeManifest([Iterable<String>? names]) {
    final lines = [
      for (final name in names ?? versionedAssets(tag))
        '${sha256.convert(asset(name).readAsBytesSync())}  $name',
    ];
    asset(checksumsAssetName(tag)).writeAsStringSync('${lines.join('\n')}\n');
  }

  void copyAliases() {
    for (final suffix in latestAliasSuffixes) {
      asset('fmp-$tag-$suffix').copySync(asset('fmp-latest-$suffix').path);
    }
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('app_release_assets_');
    badging = {};
    signers = {};
    for (final name in versionedAssets(tag)) {
      if (name.endsWith('.exe')) {
        asset(name).writeAsBytesSync(minimalPe());
      } else {
        asset(name).writeAsStringSync('contents of $name');
      }
      if (name.endsWith('.apk')) {
        badging[name] = (
          packageName: applicationId,
          versionName: '2.0.0',
          versionCode: versionCode,
        );
        signers[name] = [(dn: 'CN=FMP', sha256: releaseCert)];
      }
    }
    zipEntries = [
      ...windowsProgramFiles,
      'data/flutter_assets/AssetManifest.bin',
    ];
    copyAliases();
    writeManifest();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('the asset names are the ones ADR 0022 §決定 3 lists', () {
    expect(expectedAssets('v2.0.0'), {
      'fmp-v2.0.0-android-arm64-v8a.apk',
      'fmp-v2.0.0-android-armeabi-v7a.apk',
      'fmp-v2.0.0-android-x86_64.apk',
      'fmp-v2.0.0-android-universal.apk',
      'fmp-v2.0.0-windows-installer.exe',
      'fmp-v2.0.0-windows.zip',
      'fmp-v2.0.0-checksums.sha256',
      'fmp-latest-android-arm64-v8a.apk',
      'fmp-latest-android-universal.apk',
      'fmp-latest-windows.zip',
      'fmp-latest-windows-installer.exe',
    });
  });

  test('the version code follows the legacy formula', () {
    expect(versionCodeOfTag('v2.0.0'), 2000000);
    expect(versionCodeOfTag('v1.11.0'), 1011000);
    expect(versionCodeOfTag('v2.3.14'), 2003014);
    expect(versionCodeOfTag('v2.1000.0'), isNull);
    expect(versionCodeOfTag('v2.0.0-beta.1'), isNull);
    expect(versionCodeOfTag('2.0.0'), isNull);
  });

  test('a complete release passes', () async {
    expect(await verify(), isEmpty);
    expect(dir.listSync(), hasLength(expectedAssets(tag).length));
  });

  group('not red on differences that do not matter', () {
    test('manifest order, binary-mode markers and CRLF', () async {
      final lines = [
        for (final name in versionedAssets(tag).reversed)
          '${sha256.convert(asset(name).readAsBytesSync())} *$name',
      ];
      asset(checksumsAssetName(tag)).writeAsStringSync(lines.join('\r\n'));
      expect(await verify(), isEmpty);
    });

    test('upper-case hashes', () async {
      final manifest = asset(checksumsAssetName(tag));
      manifest.writeAsStringSync(
        manifest
            .readAsLinesSync()
            .map((line) {
              final [hash, name] = line.split('  ');
              return '${hash.toUpperCase()}  $name';
            })
            .join('\n'),
      );
      expect(await verify(), isEmpty);
    });

    test('zip entries with backslashes or directory entries', () async {
      zipEntries = [
        'data/',
        ...windowsProgramFiles.map((name) => name.replaceAll('/', r'\')),
      ];
      expect(await verify(), isEmpty);
    });
  });

  group('red on', () {
    test('a tag the version code cannot hold', () async {
      expect(await verify(releaseTag: 'v2.1000.0'), [
        'tag v2.1000.0 is not vMAJOR.MINOR.PATCH with MINOR and PATCH below '
            '1000',
      ]);
    });

    test('a missing alias', () async {
      asset('fmp-latest-android-arm64-v8a.apk').deleteSync();
      expect(await verify(), [
        'missing asset: fmp-latest-android-arm64-v8a.apk',
      ]);
    });

    test('a file nobody expects', () async {
      // Linux、macOS 的發佈物由各自的平台任務加進 expectedAssets。
      asset('fmp-$tag-linux-x86_64.AppImage').writeAsStringSync('later');
      expect(await verify(), [
        'unexpected asset: fmp-$tag-linux-x86_64.AppImage',
      ]);
    });

    test('a stray APK, which the legacy updater takes for universal', () async {
      asset('fmp-$tag-android.apk').writeAsStringSync('legacy name');
      expect(await verify(), [
        'unexpected asset: fmp-$tag-android.apk',
        'legacy updater (Android universal): may download '
            'fmp-$tag-android.apk, whose sha256 is not the one listed for '
            'fmp-$tag-android-universal.apk',
      ]);
    });

    test('a manifest hash that does not match', () async {
      asset('fmp-$tag-windows.zip').writeAsStringSync('rebuilt afterwards');
      expect(
        await verify(),
        containsAll([
          '${checksumsAssetName(tag)}: the sha256 of fmp-$tag-windows.zip '
              'does not match',
          'fmp-latest-windows.zip is not a copy of fmp-$tag-windows.zip',
        ]),
      );
    });

    test('a manifest that skips a versioned asset or lists an alias', () async {
      writeManifest([
        ...versionedAssets(tag).where((name) => !name.endsWith('x86_64.apk')),
        'fmp-latest-windows.zip',
      ]);
      expect(await verify(), [
        '${checksumsAssetName(tag)} does not list fmp-$tag-android-x86_64.apk',
        '${checksumsAssetName(tag)} lists fmp-latest-windows.zip, '
            'which is not a versioned asset',
        'legacy updater (Android x86_64): checksum missing for '
            'fmp-$tag-android-x86_64.apk',
      ]);
    });

    test('an alias that is not a copy', () async {
      asset('fmp-latest-android-universal.apk').writeAsStringSync('older');
      final problems = await verify();
      expect(
        problems.first,
        'fmp-latest-android-universal.apk is not a copy of '
        'fmp-$tag-android-universal.apk',
      );
      // 舊版更新器也會因此下載到對不上 checksum 的檔案。
      expect(
        problems.skip(1),
        everyElement(startsWith('legacy updater (Android')),
      );
    });

    test('an APK with another version or package', () async {
      badging['fmp-$tag-android-armeabi-v7a.apk'] = (
        packageName: 'com.personal.fmp.dev',
        versionName: '0.1.0',
        versionCode: 1,
      );
      expect(await verify(), [
        'fmp-$tag-android-armeabi-v7a.apk: package is com.personal.fmp.dev, '
            'expected $applicationId',
        'fmp-$tag-android-armeabi-v7a.apk: versionName is 0.1.0, '
            'expected 2.0.0',
        'fmp-$tag-android-armeabi-v7a.apk: versionCode is 1, '
            'expected $versionCode',
      ]);
    });

    test('an APK whose badging cannot be read', () async {
      badging['fmp-$tag-android-x86_64.apk'] = null;
      expect(await verify(), [
        'fmp-$tag-android-x86_64.apk: could not read the package badging',
      ]);
    });

    test('an APK signed with the debug key', () async {
      signers['fmp-$tag-android-universal.apk'] = [
        (dn: 'C=US, O=Android, CN=Android Debug', sha256: 'cd' * 32),
      ];
      expect(await verify(), [
        'fmp-$tag-android-universal.apk: signed with the Android debug key',
        'the APKs are not signed with the same certificate',
      ]);
    });

    test('an APK whose signature does not verify', () async {
      signers['fmp-$tag-android-arm64-v8a.apk'] = null;
      expect(await verify(), [
        'fmp-$tag-android-arm64-v8a.apk: expected one verified signer, '
            'got none',
      ]);
    });

    test('an installer that is not an executable', () async {
      asset('fmp-$tag-windows-installer.exe').writeAsStringSync('<html>');
      copyAliases();
      writeManifest();
      expect(await verify(), [
        'fmp-$tag-windows-installer.exe is not a Windows executable',
      ]);
    });

    test('a zip whose root is not the program directory', () async {
      zipEntries = [for (final name in windowsProgramFiles) 'Release/$name'];
      expect(await verify(), [
        for (final name in windowsProgramFiles)
          'fmp-$tag-windows.zip: $name is not at the root of the program '
              'directory',
      ]);
    });

    test('a zip that cannot be listed', () async {
      zipEntries = null;
      expect(await verify(), [
        'fmp-$tag-windows.zip: could not list its entries',
        'legacy updater: could not list the portable zip',
      ]);
    });
  });

  group('tool output parsing', () {
    test('aapt2 badging', () {
      expect(
        parseBadging(
          "package: name='com.personal.fmp' versionCode='2000000' "
          "versionName='2.0.0' platformBuildVersionName='16' "
          "compileSdkVersionCodename='16'\n"
          "application-label:'FMP'\n",
        ),
        (
          packageName: 'com.personal.fmp',
          versionName: '2.0.0',
          versionCode: 2000000,
        ),
      );
      expect(parseBadging("application-label:'FMP'\n"), isNull);
    });

    test('apksigner certificates', () {
      expect(
        parseSigners(
          'Verifies\r\n'
          'Verified using v2 scheme (APK Signature Scheme v2): true\r\n'
          'Signer #1 certificate DN: CN=Android Debug, O=Android, C=US\r\n'
          'Signer #1 certificate SHA-256 digest: ${'EF' * 32}\r\n'
          'Signer #1 certificate SHA-1 digest: ${'01' * 20}\r\n',
        ),
        [(dn: 'CN=Android Debug, O=Android, C=US', sha256: 'ef' * 32)],
      );
      expect(parseSigners('DOES NOT VERIFY\n'), isEmpty);
    });

    test('PE header', () {
      expect(isWindowsExecutable(minimalPe()), isTrue);
      expect(isWindowsExecutable([0x4D, 0x5A]), isFalse);
      expect(isWindowsExecutable('PK zip'.codeUnits), isFalse);
      final truncated = minimalPe()..[0x3C] = 0xF0;
      expect(isWindowsExecutable(truncated), isFalse);
    });
  });
}

/// 最小的 PE 開頭：`MZ`、`e_lfanew` = 0x40、`PE\0\0`。
List<int> minimalPe() => [
  0x4D,
  0x5A,
  ...List.filled(0x3A, 0),
  0x40,
  0,
  0,
  0,
  0x50,
  0x45,
  0,
  0,
];
