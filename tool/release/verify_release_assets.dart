/// 發布前檢查 release job 要上傳的產物，由 `release.yml` 的 `verify` job 執行：
///
///     AAPT2=<aapt2 路徑> dart run tool/release/verify_release_assets.dart \
///         <產物目錄> <tag> <versionCode>
///
/// Release 不再建成草稿等人按 publish（`docs/adr/0006`），發布前看過產物的只有
/// 這支腳本。它只擋結構性錯誤：缺檔或多檔、checksums 對不上、APK 的版本不是 tag
/// 的版本、Windows 安裝檔不是執行檔。執行期才會壞的 build 它看不到。
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// 穩定下載別名的後綴，完整檔名是 `fmp-latest-<後綴>`。README 的
/// `releases/latest/download/...` 連結指向它們；每個都對應一個同後綴的版本化檔。
const latestAliasSuffixes = [
  'android-arm64-v8a.apk',
  'android-universal.apk',
  'windows.zip',
  'windows-installer.exe',
];

const _abis = ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'universal'];

/// 帶版本號的產物。checksums 只涵蓋這些，刻意不含別名。
List<String> versionedAssets(String tag) => [
  for (final abi in _abis) 'fmp-$tag-android-$abi.apk',
  'fmp-$tag-windows.zip',
  'fmp-$tag-windows-installer.exe',
];

String checksumsAssetName(String tag) => 'fmp-$tag-checksums.sha256';

/// 一個 Release 該有、也只該有的檔案。
Set<String> expectedAssets(String tag) => {
  ...versionedAssets(tag),
  for (final suffix in latestAliasSuffixes) 'fmp-latest-$suffix',
  checksumsAssetName(tag),
};

typedef ApkVersion = ({String name, int code});

/// 讀不出版本時回傳 null。
typedef ApkVersionReader = Future<ApkVersion?> Function(File apk);

/// 回傳所有找到的問題；空清單代表可以發布。一次列完，不在第一個問題就停。
Future<List<String>> verifyReleaseAssets({
  required Directory dir,
  required String tag,
  required int versionCode,
  required ApkVersionReader readApkVersion,
}) async {
  final problems = <String>[];
  final present = {
    for (final entity in dir.listSync()) p.basename(entity.path),
  };
  final expected = expectedAssets(tag);
  for (final name in expected.difference(present).toList()..sort()) {
    problems.add('missing asset: $name');
  }
  for (final name in present.difference(expected).toList()..sort()) {
    problems.add('unexpected asset: $name');
  }

  File file(String name) => File(p.join(dir.path, name));
  final hashes = <String, String>{};
  Future<String?> hashOf(String name) async {
    if (!present.contains(name)) return null;
    return hashes[name] ??= (await sha256.bind(file(name).openRead()).first)
        .toString();
  }

  final manifest = checksumsAssetName(tag);
  if (present.contains(manifest)) {
    final versioned = versionedAssets(tag).toSet();
    final listed = <String, String>{};
    for (final line in await file(manifest).readAsLines()) {
      if (line.trim().isEmpty) continue;
      // sha256sum 的格式：hash、一個空格、再一個空格（文字模式）或 `*`（二進位模式）。
      final match = RegExp(
        r'^([0-9a-fA-F]{64}) [ *](.+)$',
      ).firstMatch(line.trim());
      if (match == null) {
        problems.add('$manifest: unreadable line: $line');
        continue;
      }
      listed[match.group(2)!] = match.group(1)!.toLowerCase();
    }
    for (final name in versioned.difference(listed.keys.toSet())) {
      problems.add('$manifest does not list $name');
    }
    for (final name in listed.keys.toSet().difference(versioned)) {
      problems.add('$manifest lists $name, which is not a versioned asset');
    }
    for (final MapEntry(key: name, value: hash) in listed.entries) {
      if (!versioned.contains(name)) continue;
      final actual = await hashOf(name);
      if (actual != null && actual != hash) {
        problems.add('$manifest: the sha256 of $name does not match');
      }
    }
  }

  // App 內更新依 ABI 或平台收集下載網址時，別名與版本化檔落在同一格，實際下載
  // 的可能是別名，但 hash 一律拿版本化檔名去 checksums 查（update_service.dart）。
  // 兩者不是同一份位元組，更新就會以校驗失敗收場。
  for (final suffix in latestAliasSuffixes) {
    final alias = 'fmp-latest-$suffix';
    final versioned = 'fmp-$tag-$suffix';
    final aliasHash = await hashOf(alias);
    final versionedHash = await hashOf(versioned);
    if (aliasHash != null &&
        versionedHash != null &&
        aliasHash != versionedHash) {
      problems.add('$alias is not a copy of $versioned');
    }
  }

  // 建置時由 tag 改寫 pubspec 的版本；這裡守的是那一步沒有悄悄失效。
  final versionName = tag.substring(1);
  for (final abi in _abis) {
    final apk = 'fmp-$tag-android-$abi.apk';
    if (!present.contains(apk)) continue;
    final version = await readApkVersion(file(apk));
    if (version == null) {
      problems.add('$apk: could not read versionName and versionCode');
      continue;
    }
    if (version.name != versionName) {
      problems.add(
        '$apk: versionName is ${version.name}, expected $versionName',
      );
    }
    if (version.code != versionCode) {
      problems.add(
        '$apk: versionCode is ${version.code}, expected $versionCode',
      );
    }
  }

  final installer = 'fmp-$tag-windows-installer.exe';
  if (present.contains(installer) &&
      !isWindowsExecutable(await file(installer).readAsBytes())) {
    problems.add('$installer is not a Windows executable');
  }

  return problems;
}

/// 檢查 DOS 標頭的 `MZ`，以及 `e_lfanew` 指向的 `PE\0\0` 簽章。0 位元組的檔案、
/// 錯誤頁、被放錯的壓縮檔都過不了；尾端被截斷的安裝檔過得了，這裡不檢查。
bool isWindowsExecutable(List<int> bytes) {
  if (bytes.length < 0x40 || bytes[0] != 0x4D || bytes[1] != 0x5A) {
    return false;
  }
  final offset =
      bytes[0x3C] | bytes[0x3D] << 8 | bytes[0x3E] << 16 | bytes[0x3F] << 24;
  if (offset + 4 > bytes.length) return false;
  return bytes[offset] == 0x50 &&
      bytes[offset + 1] == 0x45 &&
      bytes[offset + 2] == 0 &&
      bytes[offset + 3] == 0;
}

/// 從 `aapt2 dump badging` 的輸出讀 `package:` 那一行的版本。
ApkVersion? parseBadging(String output) {
  final line = output
      .split('\n')
      .firstWhere((line) => line.startsWith('package:'), orElse: () => '');
  final code = RegExp(r"versionCode='(\d+)'").firstMatch(line);
  final name = RegExp(r"versionName='([^']*)'").firstMatch(line);
  if (code == null || name == null) return null;
  return (name: name.group(1)!, code: int.parse(code.group(1)!));
}

Future<void> main(List<String> args) async {
  final aapt2 = Platform.environment['AAPT2'] ?? '';
  final versionCode = args.length == 3 ? int.tryParse(args[2]) : null;
  if (versionCode == null || aapt2.isEmpty) {
    stderr.writeln(
      'usage: AAPT2=<path> dart run tool/release/verify_release_assets.dart '
      '<dir> <tag> <versionCode>',
    );
    exitCode = 64;
    return;
  }

  final tag = args[1];
  final problems = await verifyReleaseAssets(
    dir: Directory(args[0]),
    tag: tag,
    versionCode: versionCode,
    readApkVersion: (apk) async {
      final result = await Process.run(aapt2, ['dump', 'badging', apk.path]);
      if (result.exitCode != 0) return null;
      return parseBadging(result.stdout as String);
    },
  );
  if (problems.isEmpty) {
    stdout.writeln(
      'Verified all ${expectedAssets(tag).length} assets of $tag.',
    );
    return;
  }
  for (final problem in problems) {
    stdout.writeln('::error::$problem');
  }
  exitCode = 1;
}
