import 'package:fmp/core/endpoints.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/repository/plugin_index.dart';

/// 能力在介面上的名稱（ADR 0030 §決定 8 的「翻譯過的能力」）。exhaustive：加能力時
/// 編譯器會指出這裡。
String capabilityName(Translations t, PluginCapability capability) {
  final names = t.plugins.capabilityNames;
  return switch (capability) {
    PluginCapability.search => names.search,
    PluginCapability.resolveStream => names.resolveStream,
    PluginCapability.trackDetail => names.trackDetail,
    PluginCapability.multiPart => names.multiPart,
    PluginCapability.importPlaylist => names.importPlaylist,
    PluginCapability.libraryRead => names.libraryRead,
    PluginCapability.libraryWrite => names.libraryWrite,
    PluginCapability.charts => names.charts,
    PluginCapability.live => names.live,
    PluginCapability.mix => names.mix,
    PluginCapability.lyrics => names.lyrics,
    PluginCapability.login => names.login,
  };
}

/// 一組能力的名稱，依 [PluginCapability] 的宣告順序。
List<String> capabilityNames(
  Translations t,
  Iterable<PluginCapability> capabilities,
) => [
  for (final capability in PluginCapability.values)
    if (capabilities.contains(capability)) capabilityName(t, capability),
];

/// 插件來自哪裡：官方插件庫、某個自訂插件庫，或檔案與網址（`null`）。
String sourceLabel(Translations t, String? indexUrl) => switch (indexUrl) {
  null => t.plugins.sourceLocal,
  officialPluginIndexUrl => t.plugins.sourceOfficial,
  final url => t.plugins.sourceCustom(url: url),
};

/// 預期內的拒絕（ADR 0030 §決定 1、4、8）的提示。
String rejectionMessage(Translations t, PluginRejection reason) =>
    switch (reason) {
      PluginRejection.hashMismatch => t.plugins.hashMismatch,
      PluginRejection.manifestMismatch => t.plugins.manifestMismatch,
      PluginRejection.appUpdateRequired => t.plugins.appUpdateRequired,
    };
