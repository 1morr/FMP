import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/release/verify_release_assets.dart';

/// `verify` job 是 Release 對外之前唯一看過產物的東西（docs/adr/0006），這裡用
/// 假產物證明它擋得住該擋的，也不會被無關的差異擋下。
void main() {
  const tag = 'v1.2.3';
  const versionCode = 1002003;
  late Directory dir;
  late Map<String, ApkVersion> apkVersions;

  Future<List<String>> verify() => verifyReleaseAssets(
    dir: dir,
    tag: tag,
    versionCode: versionCode,
    readApkVersion: (apk) async => apkVersions[p.basename(apk.path)],
  );

  File asset(String name) => File(p.join(dir.path, name));

  void writeManifest([Iterable<String>? names]) {
    final lines = [
      for (final name in names ?? versionedAssets(tag))
        '${sha256.convert(asset(name).readAsBytesSync())}  $name',
    ];
    asset(checksumsAssetName(tag)).writeAsStringSync('${lines.join('\n')}\n');
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('release_assets_');
    apkVersions = {};
    for (final name in versionedAssets(tag)) {
      if (name.endsWith('-windows-installer.exe')) {
        asset(name).writeAsBytesSync(_minimalPe());
      } else {
        asset(name).writeAsStringSync('contents of $name');
      }
      if (name.endsWith('.apk')) {
        apkVersions[name] = (name: '1.2.3', code: versionCode);
      }
    }
    for (final suffix in latestAliasSuffixes) {
      asset('fmp-$tag-$suffix').copySync(asset('fmp-latest-$suffix').path);
    }
    writeManifest();
  });

  tearDown(() => dir.deleteSync(recursive: true));

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
  });

  group('red on', () {
    test('a missing alias', () async {
      asset('fmp-latest-android-arm64-v8a.apk').deleteSync();
      expect(await verify(), [
        'missing asset: fmp-latest-android-arm64-v8a.apk',
      ]);
    });

    test('a file nobody expects', () async {
      asset('fmp-$tag-android.apk').writeAsStringSync('legacy name');
      expect(await verify(), ['unexpected asset: fmp-$tag-android.apk']);
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
      ]);
    });

    test('an alias that is not a copy', () async {
      asset(
        'fmp-latest-android-universal.apk',
      ).writeAsStringSync('an older build');
      expect(await verify(), [
        'fmp-latest-android-universal.apk is not a copy of '
            'fmp-$tag-android-universal.apk',
      ]);
    });

    test('an APK built from an unrewritten pubspec', () async {
      apkVersions['fmp-$tag-android-armeabi-v7a.apk'] = (
        name: '1.2.2',
        code: 1002002,
      );
      expect(await verify(), [
        'fmp-$tag-android-armeabi-v7a.apk: versionName is 1.2.2, '
            'expected 1.2.3',
        'fmp-$tag-android-armeabi-v7a.apk: versionCode is 1002002, '
            'expected $versionCode',
      ]);
    });

    test('an APK whose version cannot be read', () async {
      apkVersions.remove('fmp-$tag-android-x86_64.apk');
      expect(await verify(), [
        'fmp-$tag-android-x86_64.apk: could not read versionName and '
            'versionCode',
      ]);
    });

    for (final (label, bytes) in [
      ('an empty installer', <int>[]),
      ('an installer that is a zip', 'PK\x03\x04${'x' * 100}'.codeUnits),
      ('a PE header pointing past the end', _minimalPe(peOffset: 0x1000)),
    ]) {
      test(label, () async {
        for (final name in [
          'fmp-$tag-windows-installer.exe',
          'fmp-latest-windows-installer.exe',
        ]) {
          asset(name).writeAsBytesSync(bytes);
        }
        writeManifest();
        expect(await verify(), [
          'fmp-$tag-windows-installer.exe is not a Windows executable',
        ]);
      });
    }
  });

  group('parseBadging', () {
    test('reads the package line of aapt2 dump badging', () {
      expect(
        parseBadging(
          "package: name='com.personal.fmp' versionCode='1010002' "
          "versionName='1.10.2' platformBuildVersionName='16'\n"
          "sdkVersion:'24'\n",
        ),
        (name: '1.10.2', code: 1010002),
      );
    });

    test('returns null when the package line has no version', () {
      expect(parseBadging("package: name='com.personal.fmp'\n"), isNull);
      expect(parseBadging('ERROR: dump failed'), isNull);
    });
  });
}

/// 最小的 PE：`MZ`、`e_lfanew`，以及它指向的 `PE\0\0`。
List<int> _minimalPe({int peOffset = 0x80}) {
  final bytes = List<int>.filled(0x100, 0);
  bytes[0] = 0x4D;
  bytes[1] = 0x5A;
  for (var i = 0; i < 4; i++) {
    bytes[0x3C + i] = (peOffset >> (8 * i)) & 0xFF;
  }
  if (peOffset + 4 <= bytes.length) {
    bytes.setRange(peOffset, peOffset + 4, [0x50, 0x45, 0, 0]);
  }
  return bytes;
}
