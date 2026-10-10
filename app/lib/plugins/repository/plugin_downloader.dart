import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/network/host_fetch.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/repository/plugin_index.dart';
import 'package:fmp/plugins/repository/plugin_updates.dart';

/// 宿主自己的請求（index、插件檔、checks）：不帶憑證，寫網路紀錄（ADR 0030
/// §決定 5）。
final hostFetchProvider = Provider<HostFetch>(
  (ref) => HostFetch(
    log: ref.watch(logProvider),
    reportOutcome: ref.watch(networkStatusProvider.notifier).report,
    recordIds: ref.watch(networkRecordIdsProvider),
  ),
);

final pluginDownloaderProvider = Provider<PluginDownloader>(
  (ref) => PluginDownloader(
    fetch: ref.watch(hostFetchProvider).fetch,
    log: ref.watch(logProvider),
  ),
);

/// 下載並驗證好、還沒安裝的插件（ADR 0030 §決定 8、9）。確認對話框的內容取自
/// [file] 的 manifest，不是 index 那一筆。
final class PreparedPlugin {
  const PreparedPlugin({
    required this.file,
    required this.sourceIndexUrl,
    required this.checksJson,
    required this.isUpdate,
    required this.addedCapabilities,
    required this.addedHosts,
  });

  final PluginFile file;

  /// 來源 index 的網址（存進 `installed_plugins.source_index_url`）。
  final String sourceIndexUrl;

  /// 驗證過的 `checks.json` 原文；沒有、下載失敗或驗證不過都是 `null`。
  final String? checksJson;

  /// 已安裝同 id 的插件，這是更新。
  final bool isUpdate;

  /// 相對於目前版本多出來的能力與網域；新安裝時是全部。
  final Set<PluginCapability> addedCapabilities;
  final Set<String> addedHosts;

  /// 要先讓使用者確認才能裝：新安裝一律要，更新只在能力或網域增加時要。
  bool get needsConfirmation =>
      !isUpdate || addedCapabilities.isNotEmpty || addedHosts.isNotEmpty;
}

/// [PluginDownloader.prepare] 的結果：可以確認、安裝，或預期內的拒絕（資料有
/// 問題或太新，不是 bug；其他失敗仍是 [AppError]）。
sealed class PrepareResult {
  const PrepareResult();
}

final class Prepared extends PrepareResult {
  const Prepared(this.plugin);

  final PreparedPlugin plugin;
}

final class PrepareRejected extends PrepareResult {
  const PrepareRejected(this.reason, {required this.pluginId});

  final PluginRejection reason;
  final String pluginId;
}

/// 讀 index、下載並驗證插件檔（ADR 0030 §決定 1、5、8）。
final class PluginDownloader {
  PluginDownloader({required this._fetch, required this._log});

  final Future<Uint8List> Function(Uri url, {required int maxBytes}) _fetch;
  final Log _log;

  /// 讀 [url] 的 index。網路錯誤與解析錯誤是 [AppError]；`indexVersion` 不支援回
  /// [IndexRejected]。
  Future<IndexReadResult> readIndex(Uri url) async {
    final bytes = await _fetch(url, maxBytes: indexMaxBytes);
    return PluginIndex.parse(_utf8(bytes));
  }

  /// 從網址安裝（ADR 0030 §決定 8）：下載 [url] 的安裝檔並讀出標頭 manifest（不
  /// 執行腳本）。沒有 index 可比對，確認對話框的內容取自這個 manifest。上限同 index
  /// 的插件檔；網路、大小、格式的失敗都是 [AppError]。
  Future<PluginFile> downloadFile(Uri url) async =>
      PluginFile.decode(await _fetch(url, maxBytes: pluginFileMaxBytes));

  /// 下載 [entry]（來自 [indexUrl]）並驗證，回傳可以確認、安裝的內容。
  ///
  /// - `apiVersion` 宿主不支援：[PrepareRejected]（appUpdateRequired），不下載。
  /// - SHA-256 不符：[PrepareRejected]（hashMismatch）。
  /// - `.js` 標頭 manifest 的 id、版本、`apiVersion`、能力、網域與 [entry] 不同：
  ///   [PrepareRejected]（manifestMismatch）。
  /// - [current]（已安裝同 id 的）存在時比較新增的能力與網域；新版本不比已安裝的高
  ///   也不擋，由呼叫端先用 [updateStatus] 決定要不要更新。
  /// - `checks.json` 下載失敗或驗證不過：記 warning、`checksJson` 為 `null`，插件
  ///   照裝。
  Future<PrepareResult> prepare(
    PluginIndexEntry entry, {
    required Uri indexUrl,
    InstalledPlugin? current,
  }) async {
    if (!entry.isCompatible) {
      return PrepareRejected(
        PluginRejection.appUpdateRequired,
        pluginId: entry.id,
      );
    }
    final bytes = await _fetch(entry.url, maxBytes: pluginFileMaxBytes);
    if (_hash(bytes) != entry.sha256) {
      return PrepareRejected(PluginRejection.hashMismatch, pluginId: entry.id);
    }
    final file = PluginFile.decode(bytes);
    if (!_matches(entry, file.manifest)) {
      return PrepareRejected(
        PluginRejection.manifestMismatch,
        pluginId: entry.id,
      );
    }
    final added = addedAccess(
      current == null ? null : PluginManifest.parse(current.manifestJson),
      file.manifest,
    );
    return Prepared(
      PreparedPlugin(
        file: file,
        sourceIndexUrl: indexUrl.toString(),
        checksJson: await _checks(entry),
        isUpdate: current != null,
        addedCapabilities: added.capabilities,
        addedHosts: added.hosts,
      ),
    );
  }

  Future<String?> _checks(PluginIndexEntry entry) async {
    final url = entry.checksUrl;
    if (url == null) return null;
    try {
      final bytes = await _fetch(url, maxBytes: checksMaxBytes);
      if (_hash(bytes) != entry.checksSha256) {
        _log.warning(
          'Checks of a plugin do not match the index',
          tag: 'plugins',
          fields: {'pluginId': entry.id},
        );
        return null;
      }
      final text = _utf8(bytes);
      jsonDecode(text);
      return text;
    } on Object catch (error, stackTrace) {
      _log.warning(
        'Failed to download the checks of a plugin',
        tag: 'plugins',
        fields: {'pluginId': entry.id},
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  static bool _matches(PluginIndexEntry entry, PluginManifest manifest) =>
      manifest.id == entry.id &&
      manifest.version == entry.version &&
      entry.apiVersion == hostApiVersion &&
      _sameSet(manifest.capabilities, entry.capabilities) &&
      _sameSet(manifest.allowedHosts.toSet(), entry.allowedHosts.toSet());

  static bool _sameSet<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);

  static String _hash(Uint8List bytes) => sha256.convert(bytes).toString();

  static String _utf8(Uint8List bytes) {
    try {
      return const Utf8Decoder().convert(bytes);
    } on FormatException catch (error, stackTrace) {
      throw ParseError(cause: error, stackTrace: stackTrace);
    }
  }
}
