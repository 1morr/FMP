/// 插件宿主的公開介面（ADR 0038）。`plugins/` 以外只 import 這個檔；
/// `plugins/src/` 是內部（依賴規則測試守著 `ui/`）。
library;

export 'src/bundled_plugins.dart' show loadBundledPlugins;
export 'src/manifest.dart'
    show MarkPath, PluginCapability, PluginManifest, SearchSort, SourceMark;
export 'src/plugin_host.dart'
    show Plugin, PluginBundle, PluginHost, SearchResults;
export 'src/providers.dart' show pluginHostProvider, pluginManifestProvider;
