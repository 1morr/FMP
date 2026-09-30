/// 舊版（v1.x）App 內更新器的挑檔與校驗規則，移植自舊專案
/// `lib/services/update/update_service.dart`（以 v1.11.0 的內容為準，行號是那個
/// 檔案的）。ADR 0022 §決定 4：舊版使用者要能在 App 內直接升上新 App，所以
/// 發版的 verify job 以這裡的規則跑本次產物（`verify_release_assets.dart`）。
///
/// 舊專案會在切換 PR 刪除，舊版 App 卻會一直留在使用者手上，所以規則複製到
/// 這裡、不 import 舊專案（ADR 0008 §決定 1）。行為照抄，連舊版的怪處也照抄
/// （別名與版本化檔落在同一格、只比三段版本號），不要「修」它：要對得上的是
/// 已經發出去的程式。
library;

import 'package:path/path.dart' as p;

/// 最後一個舊版。舊版更新器拿自己的版本跟 `releases/latest` 比，新 App 的
/// 版本必須被它判斷成比較新。1.x 的緊急修正都小於 2.0.0，不必跟著改。
const lastLegacyVersion = '1.11.0';

/// 舊版認得的裝置 ABI（`getDeviceAbi`，:70）；其他 ABI 一律當 `universal`。
const legacyDeviceAbis = ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'universal'];

/// 舊版的 Windows 安裝類型（`isInstalledVersion`，:54-58：程式目錄有
/// `unins000.exe` 是安裝版）。
enum LegacyWindowsInstall { installer, portable }

/// `_isNewerVersion`（:689-712）：只比三段，缺的補 0，解析不了的段當 0。
bool legacyIsNewerVersion(String current, String latest) {
  final currentParts = current
      .split('.')
      .map((e) => int.tryParse(e) ?? 0)
      .toList();
  final latestParts = latest
      .split('.')
      .map((e) => int.tryParse(e) ?? 0)
      .toList();
  while (currentParts.length < 3) {
    currentParts.add(0);
  }
  while (latestParts.length < 3) {
    latestParts.add(0);
  }
  for (var i = 0; i < 3; i++) {
    if (latestParts[i] > currentParts[i]) return true;
    if (latestParts[i] < currentParts[i]) return false;
  }
  return false;
}

/// `checkForUpdate` 把 `tag_name` 去掉開頭的 `v` 當成最新版本（:406-409）。
String legacyVersionOfTag(String tagName) =>
    tagName.startsWith('v') ? tagName.substring(1) : tagName;

/// `checkForUpdate` 依檔名把 release 的 asset 分進各格（:432-465）。
///
/// 舊版逐一走過 asset、後面的蓋掉前面的，所以最後下載的是哪一個取決於 API
/// 回傳的順序。這裡不猜順序：每一格列出所有可能落進去的檔名。
final class LegacyAssetSlots {
  LegacyAssetSlots._(
    this.apk,
    this.windowsInstaller,
    this.windowsZip,
    this.checksums,
  );

  /// ABI → 可能被當成該 ABI 下載的 APK。
  final Map<String, List<String>> apk;
  final List<String> windowsInstaller;
  final List<String> windowsZip;
  final List<String> checksums;

  factory LegacyAssetSlots.collect(Iterable<String> assetNames) {
    final apk = <String, List<String>>{};
    final installer = <String>[];
    final zip = <String>[];
    final checksums = <String>[];
    // :433，`.+` 是貪婪的，會退回到最後一個 `-android-`。
    final abiPattern = RegExp(r'fmp-.+-android-(.+)\.apk$');
    for (final name in assetNames) {
      if (name.endsWith('.apk')) {
        final match = abiPattern.firstMatch(name);
        // :447-450：對不上的 APK（最早的單一 APK 檔名）當成 universal。
        final abi = match?.group(1) ?? 'universal';
        (apk[abi] ??= []).add(name);
      } else if (name.endsWith('-windows-installer.exe')) {
        installer.add(name);
      } else if (name.endsWith('-windows.zip')) {
        zip.add(name);
      } else if (name.endsWith('-checksums.sha256')) {
        checksums.add(name);
      }
    }
    return LegacyAssetSlots._(apk, installer, zip, checksums);
  }
}

/// 舊版挑中的格子與它拿去 checksums 查的檔名。
typedef LegacySelection = ({List<String> candidates, String fileName});

/// `UpdateAssetSelection.android`（:151-173）：裝置 ABI 沒有就退 `universal`，
/// 兩者都沒有回 `null`（舊版丟 `UpdateAssetUnavailableException`）。查
/// checksums 用的檔名一律由 tag 組出來（:165；`info.version` 是 `tag_name`，
/// :482），不是實際下載的 asset 名稱。
LegacySelection? legacySelectAndroid(
  LegacyAssetSlots slots, {
  required String tagName,
  required String deviceAbi,
}) {
  final abi = slots.apk.containsKey(deviceAbi)
      ? deviceAbi
      : slots.apk.containsKey('universal')
      ? 'universal'
      : null;
  if (abi == null) return null;
  return (
    candidates: slots.apk[abi]!,
    fileName: 'fmp-$tagName-android-$abi.apk',
  );
}

/// `UpdateAssetSelection.windows`（:175-197）。
LegacySelection? legacySelectWindows(
  LegacyAssetSlots slots, {
  required String tagName,
  required LegacyWindowsInstall install,
}) {
  final candidates = switch (install) {
    LegacyWindowsInstall.installer => slots.windowsInstaller,
    LegacyWindowsInstall.portable => slots.windowsZip,
  };
  if (candidates.isEmpty) return null;
  return (
    candidates: candidates,
    fileName: switch (install) {
      LegacyWindowsInstall.installer => 'fmp-$tagName-windows-installer.exe',
      LegacyWindowsInstall.portable => 'fmp-$tagName-windows.zip',
    },
  );
}

/// `_parseSha256Manifest`（:785-798）：`<64 位 hex><空白>[*]<檔名>`，檔名取
/// basename、hash 轉小寫；空行、`#` 開頭與對不上的行略過。
Map<String, String> legacyParseSha256Manifest(String content) {
  final checksums = <String, String>{};
  final linePattern = RegExp(r'^([a-fA-F0-9]{64})\s+\*?(.+)$');
  for (final rawLine in content.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final match = linePattern.firstMatch(line);
    if (match == null) continue;
    checksums[p.basename(match.group(2)!.trim())] = match
        .group(1)!
        .toLowerCase();
  }
  return checksums;
}

/// `_safeZipEntryDestination`（:359-385）：免安裝版解壓每個 entry 前的檢查，
/// 不安全就丟 `FormatException`（整次更新失敗）。舊版只在 Windows 跑，所以用
/// Windows 的路徑規則。
String legacySafeZipEntryDestination(String extractDir, String entryName) {
  final path = p.windows;
  final normalizedName = entryName.replaceAll('\\', '/');
  final parts = p.posix.split(normalizedName);
  final hasDrivePrefix = RegExp(r'^[A-Za-z]:').hasMatch(entryName);

  if (normalizedName.startsWith('/') ||
      normalizedName.startsWith('\\') ||
      hasDrivePrefix ||
      parts.any((part) => part == '..')) {
    throw FormatException('Unsafe ZIP entry path: $entryName');
  }

  final normalizedExtractDir = path.normalize(extractDir);
  final destination = path.normalize(
    path.joinAll([normalizedExtractDir, ...parts]),
  );
  final extractWithSeparator = normalizedExtractDir.endsWith(path.separator)
      ? normalizedExtractDir
      : '$normalizedExtractDir${path.separator}';

  if (destination != normalizedExtractDir &&
      !destination.startsWith(extractWithSeparator)) {
    throw FormatException('Unsafe ZIP entry path: $entryName');
  }

  return destination;
}

/// 以舊版更新器的規則走一遍本次 release，回傳它會失敗的地方；空清單代表舊版
/// 在每種裝置與安裝類型上都挑得到檔、查得到 checksum、下載的位元組對得上。
///
/// - [assetNames]：release 的所有 asset 名稱。
/// - [checksumsContent]：checksums asset 的內容；沒有該檔時為 `null`。
/// - [sha256Of]：asset 的實際 SHA-256（小寫 hex）。
/// - [zipEntries]：免安裝版 zip 的 entry 名稱；讀不到時為 `null`。
List<String> legacyUpdaterProblems({
  required String tagName,
  required Iterable<String> assetNames,
  required String? checksumsContent,
  required String? Function(String assetName) sha256Of,
  required List<String>? zipEntries,
}) {
  final problems = <String>[];
  final version = legacyVersionOfTag(tagName);
  if (!legacyIsNewerVersion(lastLegacyVersion, version)) {
    problems.add(
      'legacy updater: $version is not newer than $lastLegacyVersion',
    );
  }

  final slots = LegacyAssetSlots.collect(assetNames);
  // :467-470：沒有 checksums asset 時舊版只比大小（B8），新 App 的發版不允許。
  if (slots.checksums.isEmpty || checksumsContent == null) {
    problems.add('legacy updater: no *-checksums.sha256 asset');
    return problems;
  }
  final manifest = legacyParseSha256Manifest(checksumsContent);
  // :768-772
  if (manifest.isEmpty) {
    problems.add('legacy updater: the checksum manifest has no valid entries');
    return problems;
  }

  void check(String target, LegacySelection? selection) {
    if (selection == null) {
      problems.add('legacy updater ($target): no asset to download');
      return;
    }
    // `_requiredOrAvailableChecksum`（:776-783）：有 checksums 檔就一定要列出。
    final expected = manifest[selection.fileName];
    if (expected == null || expected.isEmpty) {
      problems.add(
        'legacy updater ($target): checksum missing for ${selection.fileName}',
      );
      return;
    }
    // `_validateDownloadedAsset`（:800-828）拿下載到的位元組比對。
    for (final candidate in selection.candidates) {
      if (sha256Of(candidate) != expected) {
        problems.add(
          'legacy updater ($target): may download $candidate, whose sha256 '
          'is not the one listed for ${selection.fileName}',
        );
      }
    }
  }

  for (final abi in legacyDeviceAbis) {
    check(
      'Android $abi',
      legacySelectAndroid(slots, tagName: tagName, deviceAbi: abi),
    );
  }
  for (final install in LegacyWindowsInstall.values) {
    check(
      'Windows ${install.name}',
      legacySelectWindows(slots, tagName: tagName, install: install),
    );
  }

  // `_downloadAndExtractZip`（:624-686）：每個 entry 過 zip-slip 檢查、解到暫存
  // 目錄，再以 robocopy /E 蓋到程式目錄並啟動原本的執行檔（:830-875）。
  if (zipEntries == null) {
    problems.add('legacy updater: could not list the portable zip');
  } else {
    for (final entry in zipEntries) {
      try {
        legacySafeZipEntryDestination(r'C:\fmp_update', entry);
      } on FormatException {
        problems.add('legacy updater: unsafe zip entry $entry');
      }
    }
  }
  return problems;
}
