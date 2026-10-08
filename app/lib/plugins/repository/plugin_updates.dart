import 'package:pub_semver/pub_semver.dart';

import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/repository/plugin_index.dart';

/// 已安裝的插件相對於 index 那一筆的更新狀態。
enum PluginUpdateStatus {
  /// 沒有更新：index 的版本不比已安裝的高（semver 只升不降），或這份 index 不是
  /// 這個插件的來源。
  none,

  /// 有較新的版本，可以更新。
  available,

  /// 有較新的版本，但它的 `apiVersion` 宿主不支援：顯示「需要更新 FMP」，
  /// 不能更新。
  needsAppUpdate,
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
  if (Version.parse(entry.version) <= current) return PluginUpdateStatus.none;
  return entry.isCompatible
      ? PluginUpdateStatus.available
      : PluginUpdateStatus.needsAppUpdate;
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
