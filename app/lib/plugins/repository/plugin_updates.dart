import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:pub_semver/pub_semver.dart';

import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/repository/plugin_index.dart';

/// 已安裝的插件相對於 index 那一筆的更新狀態。
enum PluginUpdateStatus {
  /// 沒有更新：index 的版本與已安裝的相同且腳本一致，或這份 index 不是這個插件的
  /// 來源。
  none,

  /// 有較新的版本，可以更新。
  available,

  /// 有較新的版本，但它的 `apiVersion` 宿主不支援：顯示「需要更新 FMP」，
  /// 不能更新。
  needsAppUpdate,

  /// 已安裝的插件與它的來源 index 不一致：版本比 index 那一筆高，或版本相同但腳本
  /// 的 SHA-256 不同。以 index 為準，可以「從插件庫重新安裝」（允許降版）。
  mismatch,
}

/// [installed] 在 [indexUrl] 的 [entry] 之下的更新狀態（ADR 0030 §決定 4、6）。
///
/// 插件只從安裝時的來源 index 更新：[InstalledPlugin.sourceIndexUrl] 不等於
/// [indexUrl]（含從檔案或網址安裝的，它是 `null`）、或 id 不同，都是
/// [PluginUpdateStatus.none]。已安裝的版本不是合法 semver（開發中的腳本）時當成
/// 最低的版本。
PluginUpdateStatus updateStatus(
  InstalledPlugin installed,
  String indexUrl,
  PluginIndexEntry entry,
) {
  if (installed.id != entry.id || installed.sourceIndexUrl != indexUrl) {
    return PluginUpdateStatus.none;
  }
  final current = _parse(installed.version) ?? Version.none;
  final indexed = Version.parse(entry.version);
  if (current > indexed) return PluginUpdateStatus.mismatch;
  if (indexed == current) {
    return _scriptMatches(installed.script, entry.sha256)
        ? PluginUpdateStatus.none
        : PluginUpdateStatus.mismatch;
  }
  return entry.isCompatible
      ? PluginUpdateStatus.available
      : PluginUpdateStatus.needsAppUpdate;
}

/// 已安裝的腳本與 index 的 SHA-256 一致。`PluginFile` 在存進 `script` 前去掉 BOM，
/// 而 index 的雜湊針對含 BOM 的原檔，所以兩種都算一致（內容仍須等於發布的檔案）。
bool _scriptMatches(String script, String expected) {
  final bytes = utf8.encode(script);
  return sha256.convert(bytes).toString() == expected ||
      sha256.convert([0xEF, 0xBB, 0xBF, ...bytes]).toString() == expected;
}

/// [version] 比 [other] 舊（semver）。任一個不是合法 semver 時不算舊（無從比較）。
bool isOlderVersion(String version, String other) {
  final a = _parse(version);
  final b = _parse(other);
  return a != null && b != null && a < b;
}

Version? _parse(String text) {
  try {
    return Version.parse(text);
  } on FormatException {
    return null;
  }
}

/// [next] 比 [current] 多出來的能力與網域，更新前要讓使用者確認（ADR 0030
/// §決定 9）。[current] 是 `null`（新安裝）時全部都算新增。
({Set<PluginCapability> capabilities, Set<String> hosts}) addedAccess(
  PluginManifest? current,
  PluginManifest next,
) => (
  capabilities: next.capabilities.difference(current?.capabilities ?? const {}),
  hosts: next.allowedHosts.toSet().difference(
    current?.allowedHosts.toSet() ?? const {},
  ),
);
