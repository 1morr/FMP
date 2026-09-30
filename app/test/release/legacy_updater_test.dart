import 'package:flutter_test/flutter_test.dart';

import '../../tool/release/legacy_updater.dart';

/// 移植的舊版更新器規則（`tool/release/legacy_updater.dart`）對著舊版的已知案例：
/// 舊專案 `test/services/update/update_service_zip_test.dart` 的案例，以及實際發出
/// 去的 v1.11.0 release（asset 名稱、checksums 內容、GitHub 的 digest）。
void main() {
  group('the v1.11.0 release', () {
    test('passes every device and install type', () {
      expect(
        legacyUpdaterProblems(
          tagName: 'v1.11.0',
          assetNames: _v1110Digests.keys,
          checksumsContent: _v1110Checksums,
          sha256Of: (name) => _v1110Digests[name],
          zipEntries: const ['fmp.exe', 'data/app.so', r'data\icudtl.dat'],
        ),
        // 它不比 1.11.0 新，其他都過。
        ['legacy updater: 1.11.0 is not newer than 1.11.0'],
      );
    });

    test('fills the slots the way the old app does', () {
      final slots = LegacyAssetSlots.collect(_v1110Digests.keys);
      expect(slots.apk.keys, unorderedEquals(legacyDeviceAbis));
      // 別名與版本化檔落在同一格。
      expect(slots.apk['arm64-v8a'], [
        'fmp-latest-android-arm64-v8a.apk',
        'fmp-v1.11.0-android-arm64-v8a.apk',
      ]);
      expect(slots.apk['armeabi-v7a'], ['fmp-v1.11.0-android-armeabi-v7a.apk']);
      expect(slots.windowsInstaller, [
        'fmp-latest-windows-installer.exe',
        'fmp-v1.11.0-windows-installer.exe',
      ]);
      expect(slots.windowsZip, [
        'fmp-latest-windows.zip',
        'fmp-v1.11.0-windows.zip',
      ]);
      expect(slots.checksums, ['fmp-v1.11.0-checksums.sha256']);
    });

    test('looks checksums up by the versioned name', () {
      final slots = LegacyAssetSlots.collect(_v1110Digests.keys);
      expect(
        legacySelectAndroid(
          slots,
          tagName: 'v1.11.0',
          deviceAbi: 'x86_64',
        )?.fileName,
        'fmp-v1.11.0-android-x86_64.apk',
      );
      expect(
        legacySelectWindows(
          slots,
          tagName: 'v1.11.0',
          install: LegacyWindowsInstall.portable,
        )?.fileName,
        'fmp-v1.11.0-windows.zip',
      );
    });
  });

  group('asset names', () {
    test('the greedy pattern takes the last -android- segment', () {
      final slots = LegacyAssetSlots.collect([
        'fmp-v1.2.0-android-arm64-v8a.apk',
        'fmp-v1.2.0-android-x-android-x86_64.apk',
      ]);
      expect(slots.apk.keys, unorderedEquals(['arm64-v8a', 'x86_64']));
    });

    test('an APK without an ABI is universal', () {
      final slots = LegacyAssetSlots.collect(['fmp-v1.2.0-android.apk']);
      expect(slots.apk, {
        'universal': ['fmp-v1.2.0-android.apk'],
      });
    });

    test('other files land in no slot', () {
      final slots = LegacyAssetSlots.collect([
        'fmp-v1.2.0-linux-x86_64.AppImage',
        'fmp-v1.2.0-macos.zip',
        'notes.txt',
      ]);
      expect(slots.apk, isEmpty);
      expect(slots.windowsInstaller, isEmpty);
      expect(slots.windowsZip, isEmpty);
      expect(slots.checksums, isEmpty);
    });
  });

  group('selection', () {
    test('falls back to universal and its checksum name', () {
      // 舊版案例 `uses universal checksum when ABI-specific APK falls back`。
      final slots = LegacyAssetSlots.collect([
        'fmp-v1.2.0-android-universal.apk',
      ]);
      final selection = legacySelectAndroid(
        slots,
        tagName: 'v1.2.0',
        deviceAbi: 'arm64-v8a',
      );
      expect(selection?.fileName, 'fmp-v1.2.0-android-universal.apk');
      expect(selection?.candidates, ['fmp-v1.2.0-android-universal.apk']);
    });

    test('has nothing without the ABI or universal', () {
      final slots = LegacyAssetSlots.collect(['fmp-v1.2.0-android-x86_64.apk']);
      expect(
        legacySelectAndroid(slots, tagName: 'v1.2.0', deviceAbi: 'arm64-v8a'),
        isNull,
      );
      expect(
        legacySelectWindows(
          slots,
          tagName: 'v1.2.0',
          install: LegacyWindowsInstall.installer,
        ),
        isNull,
      );
    });
  });

  group('checksum manifest', () {
    test('parses by release asset filename', () {
      // 舊版案例 `parses sha256 manifest by release asset filename`。
      final checksums = legacyParseSha256Manifest('''
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  fmp-v1.2.0-android-arm64-v8a.apk
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb *fmp-v1.2.0-windows.zip
not-a-valid-line
''');
      expect(checksums, {
        'fmp-v1.2.0-android-arm64-v8a.apk': 'a' * 64,
        'fmp-v1.2.0-windows.zip': 'b' * 64,
      });
    });

    test('skips comments, takes basenames, lower-cases and reads CRLF', () {
      expect(
        legacyParseSha256Manifest(
          '# generated\r\n${'C' * 64}  dist/fmp-v1.2.0-windows.zip\r\n',
        ),
        {'fmp-v1.2.0-windows.zip': 'c' * 64},
      );
    });

    test('a missing entry fails although the manifest exists', () {
      // 舊版案例 `requires checksum entries when a checksum manifest exists`。
      final names = ['fmp-v2.0.0-android-arm64-v8a.apk', ..._otherV200Assets];
      final problems = legacyUpdaterProblems(
        tagName: 'v2.0.0',
        assetNames: names,
        checksumsContent: _manifestOf(
          names.where((name) => !name.contains('arm64')),
        ),
        sha256Of: _fakeSha,
        zipEntries: const ['fmp.exe'],
      );
      expect(problems, [
        'legacy updater (Android arm64-v8a): checksum missing for '
            'fmp-v2.0.0-android-arm64-v8a.apk',
      ]);
    });

    test('no manifest at all fails', () {
      expect(
        legacyUpdaterProblems(
          tagName: 'v2.0.0',
          assetNames: const ['fmp-v2.0.0-windows.zip'],
          checksumsContent: null,
          sha256Of: _fakeSha,
          zipEntries: const [],
        ),
        ['legacy updater: no *-checksums.sha256 asset'],
      );
    });

    test('a manifest without valid lines fails', () {
      expect(
        legacyUpdaterProblems(
          tagName: 'v2.0.0',
          assetNames: const ['fmp-v2.0.0-checksums.sha256'],
          checksumsContent: 'not a checksum\n',
          sha256Of: _fakeSha,
          zipEntries: const [],
        ),
        ['legacy updater: the checksum manifest has no valid entries'],
      );
    });
  });

  group('downloaded bytes', () {
    test('an alias that differs from the versioned file fails', () {
      final names = [
        'fmp-v2.0.0-android-arm64-v8a.apk',
        'fmp-latest-android-arm64-v8a.apk',
        ..._otherV200Assets,
      ];
      final problems = legacyUpdaterProblems(
        tagName: 'v2.0.0',
        assetNames: names,
        checksumsContent: _manifestOf(
          names.where((name) => !name.contains('latest')),
        ),
        sha256Of: _fakeSha,
        zipEntries: const ['fmp.exe'],
      );
      expect(problems, [
        'legacy updater (Android arm64-v8a): may download '
            'fmp-latest-android-arm64-v8a.apk, whose sha256 is not the one '
            'listed for fmp-v2.0.0-android-arm64-v8a.apk',
      ]);
    });
  });

  group('zip entries', () {
    // 舊版案例 `UpdateService ZIP extraction path safety`。
    test('allows normal nested relative entries', () {
      expect(
        legacySafeZipEntryDestination(
          r'C:\Temp\fmp_update',
          'FMP/data/app.dll',
        ),
        r'C:\Temp\fmp_update\FMP\data\app.dll',
      );
    });

    for (final entry in ['../evil.txt', '/evil.txt', r'C:\evil.txt']) {
      test('rejects $entry', () {
        expect(
          () => legacySafeZipEntryDestination(r'C:\Temp\fmp_update', entry),
          throwsFormatException,
        );
      });
    }

    test('an unsafe entry in the release zip is a problem', () {
      final names = [..._otherV200Assets];
      expect(
        legacyUpdaterProblems(
          tagName: 'v2.0.0',
          assetNames: names,
          checksumsContent: _manifestOf(names),
          sha256Of: _fakeSha,
          zipEntries: const ['fmp.exe', r'data\..\..\evil.dll'],
        ),
        [r'legacy updater: unsafe zip entry data\..\..\evil.dll'],
      );
    });
  });

  group('version comparison', () {
    test('compares three numeric parts', () {
      expect(legacyIsNewerVersion('1.11.0', '2.0.0'), isTrue);
      expect(legacyIsNewerVersion('1.9.1', '1.10.0'), isTrue);
      expect(legacyIsNewerVersion('1.11.0', '1.9.9'), isFalse);
      expect(legacyIsNewerVersion('1.11.0', '1.11.0'), isFalse);
      // 第四段與 build number 不比。
      expect(legacyIsNewerVersion('1.11.0', '1.11.0.1'), isFalse);
      expect(legacyIsNewerVersion('1.11', '1.11.1'), isTrue);
    });

    test('strips the v of the tag', () {
      expect(legacyVersionOfTag('v2.0.0'), '2.0.0');
      expect(legacyVersionOfTag('2.0.0'), '2.0.0');
    });
  });
}

/// v1.11.0 的 asset 與 GitHub 回報的 digest（`gh release view v1.11.0 --json assets`）。
const _v1110Digests = {
  'fmp-latest-android-arm64-v8a.apk':
      'f25b7b23ddf88e94603e8289916f31f01ab630817b68c7b6ccc6d09aa1092d0b',
  'fmp-latest-android-universal.apk':
      'ce701b6f32d207b6185a8162e09db9e04113c160c6c87baf83bf5cb82dd72acc',
  'fmp-latest-windows-installer.exe':
      '583f1e0171b7e396668732b772cee1ac9067b092a03033aa4f54adc029ea628f',
  'fmp-latest-windows.zip':
      '926f4bae122da377629826be3e2a2efa6fd1db9371524217d6dd77ca2f6c2923',
  'fmp-v1.11.0-android-arm64-v8a.apk':
      'f25b7b23ddf88e94603e8289916f31f01ab630817b68c7b6ccc6d09aa1092d0b',
  'fmp-v1.11.0-android-armeabi-v7a.apk':
      'efe4626b862d1be1f48a8584b79aa8986e60c5cd886c4ac857b01f0e0931744c',
  'fmp-v1.11.0-android-universal.apk':
      'ce701b6f32d207b6185a8162e09db9e04113c160c6c87baf83bf5cb82dd72acc',
  'fmp-v1.11.0-android-x86_64.apk':
      '21b7827c99c7c6d7f6b57ece68f94ff67c9c0c30769e73254ad33e7c63dd2ca9',
  'fmp-v1.11.0-checksums.sha256':
      '7f5b4d20763b3a95d1b78110f351974248839657c3ba336809a0ae3753732193',
  'fmp-v1.11.0-windows-installer.exe':
      '583f1e0171b7e396668732b772cee1ac9067b092a03033aa4f54adc029ea628f',
  'fmp-v1.11.0-windows.zip':
      '926f4bae122da377629826be3e2a2efa6fd1db9371524217d6dd77ca2f6c2923',
};

/// v1.11.0 的 `fmp-v1.11.0-checksums.sha256` 原文。
const _v1110Checksums = '''
f25b7b23ddf88e94603e8289916f31f01ab630817b68c7b6ccc6d09aa1092d0b  fmp-v1.11.0-android-arm64-v8a.apk
efe4626b862d1be1f48a8584b79aa8986e60c5cd886c4ac857b01f0e0931744c  fmp-v1.11.0-android-armeabi-v7a.apk
ce701b6f32d207b6185a8162e09db9e04113c160c6c87baf83bf5cb82dd72acc  fmp-v1.11.0-android-universal.apk
21b7827c99c7c6d7f6b57ece68f94ff67c9c0c30769e73254ad33e7c63dd2ca9  fmp-v1.11.0-android-x86_64.apk
926f4bae122da377629826be3e2a2efa6fd1db9371524217d6dd77ca2f6c2923  fmp-v1.11.0-windows.zip
583f1e0171b7e396668732b772cee1ac9067b092a03033aa4f54adc029ea628f  fmp-v1.11.0-windows-installer.exe
''';

/// universal、Windows 兩個與 checksums：舊版每種裝置都挑得到檔的最小組合。
const _otherV200Assets = [
  'fmp-v2.0.0-android-universal.apk',
  'fmp-v2.0.0-windows-installer.exe',
  'fmp-v2.0.0-windows.zip',
  'fmp-v2.0.0-checksums.sha256',
];

/// 每個檔名一個不同的假 hash。
String _fakeSha(String name) => name.codeUnits
    .fold(0, (a, b) => (a * 31 + b) & 0xffffff)
    .toRadixString(16)
    .padLeft(64, '0');

String _manifestOf(Iterable<String> names) => [
  for (final name in names)
    if (!name.endsWith('.sha256')) '${_fakeSha(name)}  $name',
].join('\n');
