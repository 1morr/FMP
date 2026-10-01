/// 發布前檢查要上傳的 release asset，由 `.github/workflows/app-release.yml` 的
/// `verify` job 在 app/ 執行：
///
///     AAPT2=<aapt2> APKSIGNER=<apksigner> \
///       dart run tool/release/verify_release_assets.dart <asset 目錄> <tag>
///
/// release-please 建的是草稿，這支通過後 `publish` job 才把 asset 傳上去並轉成
/// 正式發布（ADR 0022 §決定 1），所以對外之前看過產物的只有它。它只擋結構性的
/// 錯：缺檔多檔、checksums 或別名對不上、APK 的身分與版本不是這個 tag、APK 用
/// debug 金鑰簽、Windows 檔不是完整程式目錄或不是執行檔、舊版更新器接不上
/// （`legacy_updater.dart`）。執行期才會壞的東西它看不到。
///
/// APK 以 Android build-tools 的 aapt2、apksigner 讀，zip 以 `unzip -Z1` 列
/// entry（ubuntu runner 都內建）。
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'legacy_updater.dart';

/// prod 的 applicationId（ADR 0008 §決定 3，app/AGENTS.md § App 身分）。
const applicationId = 'com.personal.fmp';

const androidAbis = ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'universal'];

/// 穩定下載別名 `fmp-latest-<後綴>`，與舊版的四個相同：根目錄 README 以
/// `releases/latest/download/fmp-latest-…` 連到它們，2.0.0 成為 latest 之後仍要
/// 下載得到。每個都對應一個同後綴的版本化檔，位元組必須相同。
const latestAliasSuffixes = [
  'android-arm64-v8a.apk',
  'android-universal.apk',
  'windows.zip',
  'windows-installer.exe',
];

/// 免安裝版 zip 根目錄一定要有的檔案：zip 的內容就是完整程式目錄（ADR 0022
/// §決定 4）。舊版更新器解壓後啟動程式目錄的 `fmp.exe`；VC++ runtime 由
/// workflow 放進程式目錄，因為安裝檔會先清空 `{app}`（舊版安裝檔的
/// `[InstallDelete]`），舊版附的那一份也會被刪掉。
const windowsProgramFiles = [
  'fmp.exe',
  'flutter_windows.dll',
  'data/app.so',
  'msvcp140.dll',
  'vcruntime140.dll',
  'vcruntime140_1.dll',
];

/// 帶版本號的產物（ADR 0022 §決定 3）。checksums 只涵蓋這些，不含別名。
List<String> versionedAssets(String tag) => [
  for (final abi in androidAbis) 'fmp-$tag-android-$abi.apk',
  'fmp-$tag-windows-installer.exe',
  'fmp-$tag-windows.zip',
];

String checksumsAssetName(String tag) => 'fmp-$tag-checksums.sha256';

/// 一個 release 該有、也只該有的檔案。
Set<String> expectedAssets(String tag) => {
  ...versionedAssets(tag),
  for (final suffix in latestAliasSuffixes) 'fmp-latest-$suffix',
  checksumsAssetName(tag),
};

/// `vMAJOR.MINOR.PATCH` 的 versionCode：`major*1000000 + minor*1000 + patch`
/// （ADR 0022 §決定 1，沿用舊版）。minor、patch 超過 999 會撞到上一段，回 `null`。
int? versionCodeOfTag(String tag) {
  final match = RegExp(r'^v(\d+)\.(\d+)\.(\d+)$').firstMatch(tag);
  if (match == null) return null;
  final [major, minor, patch] = [
    for (var i = 1; i <= 3; i++) int.parse(match.group(i)!),
  ];
  if (minor > 999 || patch > 999) return null;
  return major * 1000000 + minor * 1000 + patch;
}

typedef ApkBadging = ({
  String packageName,
  String versionName,
  int versionCode,
});
typedef ApkSigner = ({String dn, String sha256});

/// 讀不出時回傳 `null`。
typedef ApkBadgingReader = Future<ApkBadging?> Function(File apk);

/// 簽章驗證失敗或讀不出時回傳 `null`。
typedef ApkSignerReader = Future<List<ApkSigner>?> Function(File apk);

/// 列不出時回傳 `null`。
typedef ZipLister = Future<List<String>?> Function(File zip);

/// 回傳所有找到的問題；空清單代表可以發布。一次列完，不在第一個問題就停。
Future<List<String>> verifyReleaseAssets({
  required Directory dir,
  required String tag,
  required ApkBadgingReader readBadging,
  required ApkSignerReader readSigners,
  required ZipLister listZip,
}) async {
  final problems = <String>[];
  final versionCode = versionCodeOfTag(tag);
  if (versionCode == null) {
    return [
      'tag $tag is not vMAJOR.MINOR.PATCH with MINOR and PATCH below 1000',
    ];
  }

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
  for (final name in present) {
    // 多出來的目錄已經算 unexpected，這裡只算檔案。
    if (!file(name).existsSync()) continue;
    hashes[name] = (await sha256.bind(file(name).openRead()).first).toString();
  }

  final manifestName = checksumsAssetName(tag);
  final manifestContent = present.contains(manifestName)
      ? await file(manifestName).readAsString()
      : null;
  if (manifestContent != null) {
    final versioned = versionedAssets(tag).toSet();
    final listed = <String, String>{};
    for (final line in manifestContent.split(RegExp(r'\r?\n'))) {
      if (line.trim().isEmpty) continue;
      // sha256sum 的格式：hash、一個空格、再一個空格（文字模式）或 `*`（二進位模式）。
      final match = RegExp(r'^([0-9a-fA-F]{64}) [ *](.+)$')
          .firstMatch(line.trim());
      if (match == null) {
        problems.add('$manifestName: unreadable line: $line');
        continue;
      }
      listed[match.group(2)!] = match.group(1)!.toLowerCase();
    }
    for (final name
        in versioned.difference(listed.keys.toSet()).toList()..sort()) {
      problems.add('$manifestName does not list $name');
    }
    for (final MapEntry(key: name, value: hash) in listed.entries) {
      if (!versioned.contains(name)) {
        problems.add(
          '$manifestName lists $name, which is not a versioned asset',
        );
      } else if (hashes[name] != null && hashes[name] != hash) {
        problems.add('$manifestName: the sha256 of $name does not match');
      }
    }
  }

  // 舊版更新器把別名與版本化檔分進同一格，下載的可能是別名，hash 卻一律拿
  // 版本化檔名去 checksums 查；兩者不是同一份位元組，更新就以校驗失敗收場。
  for (final suffix in latestAliasSuffixes) {
    final alias = 'fmp-latest-$suffix';
    final versioned = 'fmp-$tag-$suffix';
    if (hashes[alias] != null &&
        hashes[versioned] != null &&
        hashes[alias] != hashes[versioned]) {
      problems.add('$alias is not a copy of $versioned');
    }
  }

  final signers = <String, String>{};
  for (final abi in androidAbis) {
    final apk = 'fmp-$tag-android-$abi.apk';
    if (!present.contains(apk)) continue;
    final badging = await readBadging(file(apk));
    if (badging == null) {
      problems.add('$apk: could not read the package badging');
    } else {
      if (badging.packageName != applicationId) {
        problems.add(
          '$apk: package is ${badging.packageName}, expected $applicationId',
        );
      }
      if (badging.versionName != tag.substring(1)) {
        problems.add(
          '$apk: versionName is ${badging.versionName}, '
          'expected ${tag.substring(1)}',
        );
      }
      if (badging.versionCode != versionCode) {
        problems.add(
          '$apk: versionCode is ${badging.versionCode}, expected $versionCode',
        );
      }
    }
    final apkSigners = await readSigners(file(apk));
    if (apkSigners == null || apkSigners.length != 1) {
      problems.add(
        '$apk: expected one verified signer, got '
        '${apkSigners?.length ?? 'none'}',
      );
      continue;
    }
    // build.gradle.kts 在沒有 key.properties 時退回 debug 簽名；發出去的 APK
    // 用 debug 金鑰，舊版使用者就裝不上（簽名不同）。
    if (apkSigners.single.dn.contains('CN=Android Debug')) {
      problems.add('$apk: signed with the Android debug key');
    }
    signers[apk] = apkSigners.single.sha256;
  }
  if (signers.values.toSet().length > 1) {
    problems.add('the APKs are not signed with the same certificate');
  }

  final installer = 'fmp-$tag-windows-installer.exe';
  if (present.contains(installer) &&
      !isWindowsExecutable(await file(installer).readAsBytes())) {
    problems.add('$installer is not a Windows executable');
  }

  final zip = 'fmp-$tag-windows.zip';
  List<String>? zipEntries;
  if (present.contains(zip)) {
    zipEntries = await listZip(file(zip));
    if (zipEntries == null) {
      problems.add('$zip: could not list its entries');
    } else {
      final names = {for (final e in zipEntries) e.replaceAll('\\', '/')};
      for (final required in windowsProgramFiles) {
        if (!names.contains(required)) {
          problems.add(
            '$zip: $required is not at the root of the program '
            'directory',
          );
        }
      }
    }
  }

  problems.addAll(
    legacyUpdaterProblems(
      tagName: tag,
      assetNames: present,
      checksumsContent: manifestContent,
      sha256Of: (name) => hashes[name],
      zipEntries: zipEntries,
    ),
  );
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

/// 從 `aapt2 dump badging` 的輸出讀 `package:` 那一行。
ApkBadging? parseBadging(String output) {
  final line = output
      .split('\n')
      .firstWhere((line) => line.startsWith('package:'), orElse: () => '');
  final name = RegExp(r"\bname='([^']*)'").firstMatch(line);
  final code = RegExp(r"versionCode='(\d+)'").firstMatch(line);
  final version = RegExp(r"versionName='([^']*)'").firstMatch(line);
  if (name == null || code == null || version == null) return null;
  return (
    packageName: name.group(1)!,
    versionName: version.group(1)!,
    versionCode: int.parse(code.group(1)!),
  );
}

/// 從 `apksigner verify --print-certs` 的輸出讀每張簽名憑證的 DN 與
/// SHA-256，同一張憑證只算一次。
///
/// 每列的開頭是 signer 的標籤：build-tools 36 是 `Signer #1`，37 改成依簽名
/// 方案列出 `V2 Signer:`、`V3 Signer:`（runner 映像換版時在 sandbox 抓到的）。
/// 各方案用同一把金鑰簽時是同一張憑證，所以依憑證去重；出現第二張不同的
/// 憑證（例如金鑰輪替）就會多一筆，由呼叫端擋下。
List<ApkSigner> parseSigners(String output) {
  final dn = <String, String>{};
  final digest = <String, String>{};
  for (final line in output.split(RegExp(r'\r?\n'))) {
    final match = RegExp(r'^(.+?):? certificate (DN|SHA-256 digest): (.*)$')
        .firstMatch(line.trim());
    if (match == null) continue;
    final target = match.group(2) == 'DN' ? dn : digest;
    target[match.group(1)!] = match.group(3)!.trim();
  }
  final byCertificate = <String, ApkSigner>{};
  for (final signer in dn.keys) {
    if (digest[signer] case final sha256?) {
      byCertificate.putIfAbsent(
        sha256.toLowerCase(),
        () => (dn: dn[signer]!, sha256: sha256.toLowerCase()),
      );
    }
  }
  return byCertificate.values.toList();
}

Future<void> main(List<String> args) async {
  final aapt2 = Platform.environment['AAPT2'] ?? '';
  final apksigner = Platform.environment['APKSIGNER'] ?? '';
  if (args.length != 2 || aapt2.isEmpty || apksigner.isEmpty) {
    stderr.writeln(
      'usage: AAPT2=<path> APKSIGNER=<path> '
      'dart run tool/release/verify_release_assets.dart <dir> <tag>',
    );
    exitCode = 64;
    return;
  }

  final tag = args[1];
  final problems = await verifyReleaseAssets(
    dir: Directory(args[0]),
    tag: tag,
    readBadging: (apk) async {
      final result = await Process.run(aapt2, ['dump', 'badging', apk.path]);
      if (result.exitCode != 0) return null;
      return parseBadging(result.stdout as String);
    },
    readSigners: (apk) async {
      final result = await Process.run(apksigner, [
        'verify',
        '--print-certs',
        apk.path,
      ]);
      if (result.exitCode != 0) return null;
      return parseSigners(result.stdout as String);
    },
    listZip: (zip) async {
      final result = await Process.run('unzip', ['-Z1', zip.path]);
      if (result.exitCode != 0) return null;
      return [
        for (final line in (result.stdout as String).split('\n'))
          if (line.trimRight().isNotEmpty) line.trimRight(),
      ];
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
