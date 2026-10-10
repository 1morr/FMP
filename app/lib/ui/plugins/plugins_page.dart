import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/endpoints.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/plugin_repository.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/platform/files/files.dart';
import 'package:fmp/platform/platform_capabilities.dart';
import 'package:fmp/plugins/install/plugin_installer.dart';
import 'package:fmp/plugins/manifest/plugin_file.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/repository/plugin_downloader.dart';
import 'package:fmp/plugins/repository/plugin_index.dart';
import 'package:fmp/plugins/repository/plugin_updates.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/offline/offline.dart';
import 'package:fmp/ui/player/player_controls.dart';
import 'package:fmp/ui/plugins/plugin_dialogs.dart';
import 'package:fmp/ui/plugins/plugin_text.dart';
import 'package:fmp/ui/plugins/plugins_state.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';

const _tag = 'plugins';

/// 插件頁（ADR 0030 §決定 11，design §7.5）：設定頁的「插件」區塊。
///
/// 上方是工具列（檢查更新、全部更新，「⋯」裡是從檔案安裝、從網址安裝、管理插件庫），
/// 下面是「已安裝｜可安裝」兩個分頁（VS Code Extensions 的分法）。已安裝的每個插件
/// 一張卡：名稱、版本與作者、標記、啟用開關（Obsidian 的開關常駐在列上），更新、
/// 詳細資料（能力、網域、來源）與移除。可安裝依插件庫分段列出，已裝的標「已安裝」。
///
/// 任何一個動作在等網路或資料庫時，頁面頂端顯示進度條、其他動作停用：一次只做一件事，
/// 不會同時更新與移除同一個插件。對話框開著時不算在內。
class PluginsPage extends ConsumerStatefulWidget {
  const PluginsPage({super.key});

  @override
  ConsumerState<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends ConsumerState<PluginsPage> {
  int _working = 0;
  final _expanded = <String>{};

  bool get _busy => _working > 0;

  /// 跑 [body] 的期間頁面是「處理中」。
  Future<T> _work<T>(Future<T> Function() body) async {
    setState(() => _working++);
    try {
      return await body();
    } finally {
      if (mounted) setState(() => _working--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final p = t.plugins;
    final spacing = AppTokens.of(context).spacing;
    final installed = ref.watch(installedPluginsProvider);
    final urls = ref.watch(indexUrlsProvider);
    final outcomes = {
      for (final url in urls) url: ref.watch(indexOutcomeProvider(url)),
    };
    final registry = ref.watch(pluginRegistryProvider).value ?? const {};
    final files = ref.watch(platformCapabilitiesProvider).files;
    final list = installed.value ?? const <InstalledPlugin>[];
    final updates = {
      for (final plugin in list)
        plugin.id: ?updateOf(plugin, urls, (url) => outcomes[url]?.value),
    };
    final updatable = [
      for (final plugin in list)
        if (updates[plugin.id]?.status == PluginUpdateStatus.available) plugin,
    ];
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.x4,
              spacing.x2,
              spacing.x2,
              spacing.x2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: spacing.x2,
                    runSpacing: spacing.x2,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _checkUpdates(urls),
                        icon: const Icon(Icons.refresh),
                        label: Text(p.checkUpdates),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _busy || updatable.isEmpty
                            ? null
                            : () => _updateAll(updatable, updates),
                        icon: const Icon(Icons.system_update_alt),
                        label: Text(p.updateAll),
                      ),
                    ],
                  ),
                ),
                IconMenu(
                  tooltip: p.more,
                  icon: const Icon(Icons.more_vert),
                  menuChildren: [
                    if (files)
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.file_open_outlined),
                        onPressed: _busy ? null : _installFromFile,
                        child: Text(p.installFromFile),
                      ),
                    MenuItemButton(
                      leadingIcon: const Icon(Icons.link),
                      onPressed: _busy ? null : _installFromUrl,
                      child: Text(p.installFromUrl),
                    ),
                    MenuItemButton(
                      leadingIcon: const Icon(Icons.dns_outlined),
                      onPressed: _manageIndexes,
                      child: Text(p.manageIndexes),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 不忙時是透明的空條（value 0，不動）：出現與消失不改變下方的位置。
          Opacity(
            opacity: _busy ? 1 : 0,
            child: LinearProgressIndicator(
              value: _busy ? null : 0,
              semanticsLabel: p.working,
            ),
          ),
          TabBar(
            tabs: [
              Tab(text: p.tabInstalled),
              Tab(text: p.tabAvailable),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _installedTab(t, installed, registry, updates),
                _availableTab(t, urls, outcomes, list),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _installedTab(
    Translations t,
    AsyncValue<List<InstalledPlugin>> installed,
    Map<String, SourcePlugin> registry,
    Map<String, PluginUpdate> updates,
  ) {
    final p = t.plugins;
    final spacing = AppTokens.of(context).spacing;
    return switch (installed) {
      AsyncData(:final value) when value.isEmpty => EmptyState(
        icon: Icons.extension_outlined,
        title: p.noneInstalled,
        body: p.noneInstalledHint,
      ),
      AsyncData(:final value) => ListView.separated(
        padding: EdgeInsets.all(spacing.x4),
        itemCount: value.length,
        separatorBuilder: (_, _) => SizedBox(height: spacing.x3),
        itemBuilder: (context, i) {
          final plugin = value[i];
          final manifest = manifestOf(plugin);
          final name = manifest?.name ?? plugin.id;
          final update = updates[plugin.id];
          return _InstalledCard(
            key: ValueKey(plugin.id),
            plugin: plugin,
            manifest: manifest,
            unresponsive:
                registry[plugin.id]?.health == PluginHealth.unresponsive,
            update: update,
            expanded: _expanded.contains(plugin.id),
            busy: _busy,
            onExpand: () => setState(() {
              if (!_expanded.remove(plugin.id)) _expanded.add(plugin.id);
            }),
            onEnabled: (enabled) => _setEnabled(plugin.id, name, enabled),
            onUpdate: update == null
                ? null
                : () => unawaited(_update(plugin, update)),
            onRemove: () => _remove(plugin.id, name),
          );
        },
      ),
      // 讀本機資料庫失敗：不是網路問題，照一般的失敗顯示。
      AsyncError() => EmptyState(
        icon: Icons.error_outline,
        title: t.errors.unexpected,
      ),
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
    };
  }

  Widget _availableTab(
    Translations t,
    List<String> urls,
    Map<String, AsyncValue<IndexOutcome>> outcomes,
    List<InstalledPlugin> installed,
  ) {
    final p = t.plugins;
    final spacing = AppTokens.of(context).spacing;
    final network = ref.watch(networkStatusProvider);
    void retryAll() => ref.invalidate(indexOutcomeProvider);
    final retry = FilledButton.tonal(onPressed: retryAll, child: Text(p.retry));
    final allFailed = urls.every((url) => outcomes[url]?.value is IndexFailed);
    if (allFailed) {
      // 一份都讀不到：不在 online 時是共用的離線空狀態（ADR 0016 §決定 7）。
      return network == NetworkStatus.online
          ? EmptyState(
              icon: Icons.error_outline,
              title: p.allFailed,
              action: retry,
            )
          : OfflineMessage(status: network, action: retry);
    }
    final installedIds = {for (final plugin in installed) plugin.id};
    return ListView(
      padding: EdgeInsets.all(spacing.x4),
      children: [
        for (final url in urls) ...[
          _SectionHeader(text: sourceLabel(t, url)),
          ...switch (outcomes[url]) {
            AsyncData(value: IndexLoaded(:final index))
                when index.plugins.isEmpty =>
              [_Notice(text: p.indexEmpty)],
            AsyncData(value: IndexLoaded(:final index)) => [
              for (final entry in index.plugins) ...[
                _EntryCard(
                  key: ValueKey('$url ${entry.id}'),
                  entry: entry,
                  installed: installedIds.contains(entry.id),
                  busy: _busy,
                  onInstall: () => _install(entry, url),
                ),
                SizedBox(height: spacing.x3),
              ],
            ],
            AsyncData(value: IndexTooNew()) => [
              _Notice(text: p.indexNeedsAppUpdate),
            ],
            AsyncData(value: IndexFailed()) || AsyncError() => [
              _Notice(
                text: p.indexLoadFailed,
                action: TextButton(
                  onPressed: () => ref.invalidate(indexOutcomeProvider(url)),
                  child: Text(p.retry),
                ),
              ),
            ],
            AsyncLoading() || null => [
              Padding(
                padding: EdgeInsets.all(spacing.x4),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ],
          },
        ],
      ],
    );
  }

  // 下面的動作：要用的東西在第一個 await 之前讀好。對話框開著時視窗跨過斷點，設定頁
  // 會換位置重建這一頁（State 被丟掉），之後就不能再用 `ref`。

  Translations get _t => ref.read(translationsProvider);

  /// 失敗的提示：[sentence] 把依類別翻譯好的錯誤訊息放進一句話。
  void _failed(
    AppError error,
    String operation,
    String Function(String reason) sentence,
  ) => ref
      .read(toasterProvider)
      .error(error, operation: operation, tag: _tag, sentence: sentence);

  /// [rejection] 的提示，並記一筆 warning（預期內的拒絕，不是錯誤）。
  void _rejected(String pluginId, PluginRejection rejection) {
    ref
        .read(logProvider)
        .warning(
          'A plugin was refused',
          tag: _tag,
          fields: {'pluginId': pluginId, 'reason': rejection.name},
        );
    ref.read(toasterProvider).warning(rejectionMessage(_t, rejection));
  }

  Future<void> _install(PluginIndexEntry entry, String indexUrl) async {
    final t = _t;
    final repository = ref.read(pluginRepositoryProvider);
    final downloader = ref.read(pluginDownloaderProvider);
    final installer = ref.read(pluginInstallerProvider);
    final toaster = ref.read(toasterProvider);
    String failed(String reason) =>
        t.plugins.installFailed(name: entry.name, reason: reason);
    final PrepareResult result;
    try {
      result = await _work(
        () async => downloader.prepare(
          entry,
          indexUrl: Uri.parse(indexUrl),
          current: await repository.byId(entry.id),
        ),
      );
    } on AppError catch (error) {
      if (mounted) _failed(error, 'Failed to download a plugin', failed);
      return;
    }
    if (!mounted) return;
    final PreparedPlugin prepared;
    switch (result) {
      case PrepareRejected(:final reason):
        _rejected(entry.id, reason);
        return;
      case Prepared(:final plugin):
        prepared = plugin;
    }
    final manifest = prepared.file.manifest;
    final confirmed = await confirmInstall(
      context,
      t,
      InstallConfirmation(
        manifest: manifest,
        isUpdate: prepared.isUpdate,
        capabilities: prepared.isUpdate
            ? prepared.addedCapabilities
            : manifest.capabilities,
        hosts: prepared.isUpdate
            ? prepared.addedHosts
            : manifest.allowedHosts.toSet(),
        unofficial: indexUrl != officialPluginIndexUrl,
      ),
    );
    if (!confirmed || !mounted) return;
    try {
      await _work(() => installer.installPrepared(prepared, confirmed: true));
      toaster.success(t.plugins.installed(name: manifest.name));
    } on AppError catch (error) {
      if (mounted) _failed(error, 'Failed to install a plugin', failed);
    }
  }

  /// 更新 [plugin]；更新了回傳 `true`。[quiet] 時成功不跳提示（「全部更新」最後一起報）。
  Future<bool> _update(
    InstalledPlugin plugin,
    PluginUpdate update, {
    bool quiet = false,
  }) async {
    final t = _t;
    final downloader = ref.read(pluginDownloaderProvider);
    final installer = ref.read(pluginInstallerProvider);
    final toaster = ref.read(toasterProvider);
    final name = manifestOf(plugin)?.name ?? plugin.id;
    String failed(String reason) =>
        t.plugins.updateFailed(name: name, reason: reason);
    final PrepareResult result;
    try {
      result = await _work(
        () => downloader.prepare(
          update.entry,
          indexUrl: Uri.parse(update.indexUrl),
          current: plugin,
        ),
      );
    } on AppError catch (error) {
      if (mounted) _failed(error, 'Failed to download a plugin update', failed);
      return false;
    }
    if (!mounted) return false;
    final PreparedPlugin prepared;
    switch (result) {
      case PrepareRejected(:final reason):
        _rejected(plugin.id, reason);
        return false;
      case Prepared(plugin: final ready):
        prepared = ready;
    }
    // 能力或網域增加時先列出新增的部分，等使用者確認（ADR 0030 §決定 9）。
    var confirmed = false;
    if (prepared.needsConfirmation) {
      confirmed = await confirmInstall(
        context,
        t,
        InstallConfirmation(
          manifest: prepared.file.manifest,
          isUpdate: true,
          capabilities: prepared.addedCapabilities,
          hosts: prepared.addedHosts,
          unofficial: update.indexUrl != officialPluginIndexUrl,
        ),
      );
      if (!confirmed || !mounted) return false;
    }
    try {
      await _work(
        () => installer.installPrepared(prepared, confirmed: confirmed),
      );
    } on AppError catch (error) {
      if (mounted) _failed(error, 'Failed to update a plugin', failed);
      return false;
    }
    if (!quiet) {
      toaster.success(
        t.plugins.updated(name: name, version: prepared.file.manifest.version),
      );
    }
    return true;
  }

  /// 依序更新 [plugins]：能力或網域增加的逐個詢問，其餘直接更新（ADR 0030 §決定 9）。
  Future<void> _updateAll(
    List<InstalledPlugin> plugins,
    Map<String, PluginUpdate> updates,
  ) async {
    final t = _t;
    final toaster = ref.read(toasterProvider);
    var count = 0;
    for (final plugin in plugins) {
      if (!mounted) break;
      if (await _update(plugin, updates[plugin.id]!, quiet: true)) count++;
    }
    if (count > 0) toaster.success(t.plugins.updatedCount(count: count));
  }

  Future<void> _checkUpdates(List<String> urls) async {
    final t = _t;
    final toaster = ref.read(toasterProvider);
    ref.invalidate(indexOutcomeProvider);
    final outcomes = await _work(
      () => Future.wait([
        for (final url in urls) ref.read(indexOutcomeProvider(url).future),
      ]),
    );
    if (!mounted) return;
    final installed =
        ref.read(installedPluginsProvider).value ?? const <InstalledPlugin>[];
    final byUrl = {for (final (i, url) in urls.indexed) url: outcomes[i]};
    final count = installed
        .where(
          (plugin) =>
              updateOf(plugin, urls, (url) => byUrl[url])?.status ==
              PluginUpdateStatus.available,
        )
        .length;
    if (outcomes.any((outcome) => outcome is IndexFailed)) {
      toaster.warning(t.plugins.checkFailed);
    } else if (count > 0) {
      toaster.info(t.plugins.updatesFound(count: count));
    } else {
      toaster.success(t.plugins.upToDate);
    }
  }

  Future<void> _setEnabled(String pluginId, String name, bool enabled) async {
    final t = _t;
    final registry = ref.read(pluginRegistryProvider.notifier);
    try {
      await _work(() => registry.setEnabled(pluginId, enabled: enabled));
    } on Object catch (error, stackTrace) {
      if (!mounted) return;
      _failed(
        AppError.wrap(error, stackTrace, pluginId: pluginId),
        enabled ? 'Failed to enable a plugin' : 'Failed to disable a plugin',
        (reason) => enabled
            ? t.plugins.enableFailed(name: name, reason: reason)
            : t.plugins.disableFailed(name: name, reason: reason),
      );
    }
  }

  Future<void> _remove(String pluginId, String name) async {
    final t = _t;
    final installer = ref.read(pluginInstallerProvider);
    final toaster = ref.read(toasterProvider);
    if (!await confirmRemove(context, t, name) || !mounted) return;
    try {
      await _work(() => installer.remove(pluginId));
      _expanded.remove(pluginId);
      toaster.success(t.plugins.removed(name: name));
    } on AppError catch (error) {
      // 每一步都可重複：再按一次移除從頭跑完（ADR 0030 §決定 10）。
      if (mounted) {
        _failed(
          error,
          'Failed to remove a plugin',
          (reason) => t.plugins.removeFailed(name: name, reason: reason),
        );
      }
    }
  }

  Future<void> _installFromFile() async {
    final t = _t;
    final dialogs = ref.read(fileDialogsProvider);
    if (dialogs == null) return;
    String failed(String reason) => t.plugins.installFileFailed(reason: reason);
    final PickedFile? picked;
    try {
      picked = await dialogs.pickFile(extension: 'js');
    } on Object catch (error, stackTrace) {
      if (mounted) {
        _failed(
          AppError.wrap(error, stackTrace),
          'Failed to pick a plugin file',
          failed,
        );
      }
      return;
    }
    if (picked == null || !mounted) return;
    final PluginFile file;
    try {
      file = PluginFile.decode(picked.bytes);
    } on AppError catch (error) {
      _failed(error, 'Failed to read a plugin file', failed);
      return;
    }
    await _confirmFile(file);
  }

  Future<void> _installFromUrl() async {
    final t = _t;
    final downloader = ref.read(pluginDownloaderProvider);
    final url = await askHttpsUrl(
      context,
      t,
      title: t.plugins.installFromUrl,
      label: t.plugins.urlLabel,
      confirm: t.plugins.download,
    );
    if (url == null || !mounted) return;
    final PluginFile file;
    try {
      file = await _work(() => downloader.downloadFile(url));
    } on AppError catch (error) {
      if (mounted) {
        _failed(
          error,
          'Failed to download a plugin file',
          (reason) => t.plugins.installFileFailed(reason: reason),
        );
      }
      return;
    }
    if (mounted) await _confirmFile(file);
  }

  /// 從檔案或網址來的 [file]：確認（全部的能力與網域、「非官方來源」）後安裝。沒有來源
  /// index，之後不會有更新（ADR 0030 §決定 6）。
  Future<void> _confirmFile(PluginFile file) async {
    final t = _t;
    final repository = ref.read(pluginRepositoryProvider);
    final installer = ref.read(pluginInstallerProvider);
    final toaster = ref.read(toasterProvider);
    final manifest = file.manifest;
    final current = await _work(() => repository.byId(manifest.id));
    if (!mounted) return;
    final confirmed = await confirmInstall(
      context,
      t,
      InstallConfirmation(
        manifest: manifest,
        isUpdate: false,
        capabilities: manifest.capabilities,
        hosts: manifest.allowedHosts.toSet(),
        unofficial: true,
        replacesVersion: current?.version,
      ),
    );
    if (!confirmed || !mounted) return;
    try {
      await _work(() => installer.installSource(file.source));
      toaster.success(t.plugins.installed(name: manifest.name));
    } on AppError catch (error) {
      if (mounted) {
        _failed(
          error,
          'Failed to install a plugin',
          (reason) =>
              t.plugins.installFailed(name: manifest.name, reason: reason),
        );
      }
    }
  }

  Future<void> _manageIndexes() => showDialog<void>(
    context: context,
    builder: (context) => const _IndexesDialog(),
  );
}

/// 一個已安裝的插件。
class _InstalledCard extends ConsumerWidget {
  const _InstalledCard({
    super.key,
    required this.plugin,
    required this.manifest,
    required this.unresponsive,
    required this.update,
    required this.expanded,
    required this.busy,
    required this.onExpand,
    required this.onEnabled,
    required this.onUpdate,
    required this.onRemove,
  });

  final InstalledPlugin plugin;
  final PluginManifest? manifest;
  final bool unresponsive;
  final PluginUpdate? update;
  final bool expanded;
  final bool busy;
  final VoidCallback onExpand;
  final ValueChanged<bool> onEnabled;
  final VoidCallback? onUpdate;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final p = t.plugins;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final manifest = this.manifest;
    final name = manifest?.name ?? plugin.id;
    final description = manifest?.description ?? '';
    final status = update?.status ?? PluginUpdateStatus.none;
    final tags = [
      if (!plugin.enabled) _Tag(text: p.tagDisabled),
      if (plugin.enabled && unresponsive)
        _Tag(text: p.tagUnresponsive, tone: _TagTone.error),
      if (status != PluginUpdateStatus.none)
        _Tag(text: p.tagUpdate, tone: _TagTone.primary),
    ];
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.x4,
          spacing.x3,
          spacing.x2,
          spacing.x2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Heading(
                    name: name,
                    byline: p.versionAuthor(
                      version: plugin.version,
                      author: manifest?.author ?? '',
                    ),
                    description: description,
                    tags: tags,
                  ),
                ),
                // 自己一個語意節點：不然開關的狀態併進卡片那一節點，名稱變成卡片
                // 上所有的字。
                Semantics(
                  container: true,
                  label: p.enable(name: name),
                  child: Switch(
                    value: plugin.enabled,
                    onChanged: busy ? null : onEnabled,
                  ),
                ),
              ],
            ),
            if (expanded && manifest != null)
              Padding(
                padding: EdgeInsets.only(top: spacing.x3, right: spacing.x2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Detail(
                      label: p.capabilities,
                      value: capabilityNames(
                        t,
                        manifest.capabilities,
                      ).join(p.listSeparator),
                    ),
                    _Detail(
                      label: p.hosts,
                      value: manifest.allowedHosts.join(p.listSeparator),
                    ),
                    _Detail(
                      label: p.source,
                      value: sourceLabel(t, plugin.sourceIndexUrl),
                    ),
                  ],
                ),
              ),
            SizedBox(height: spacing.x2),
            Wrap(
              spacing: spacing.x2,
              runSpacing: spacing.x1,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (status == PluginUpdateStatus.available)
                  FilledButton.tonal(
                    onPressed: busy ? null : onUpdate,
                    child: Text(p.updateTo(version: update!.entry.version)),
                  ),
                // apiVersion 不相容：有新版本但這個 FMP 裝不了（ADR 0030 §決定 4）。
                if (status == PluginUpdateStatus.needsAppUpdate)
                  FilledButton.tonal(
                    onPressed: null,
                    child: Text(p.needsAppUpdate),
                  ),
                TextButton.icon(
                  onPressed: onExpand,
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  label: Text(expanded ? p.hideDetails : p.showDetails),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: busy ? null : onRemove,
                  child: Text(p.remove),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 可安裝清單的一個插件。
class _EntryCard extends ConsumerWidget {
  const _EntryCard({
    super.key,
    required this.entry,
    required this.installed,
    required this.busy,
    required this.onInstall,
  });

  final PluginIndexEntry entry;

  /// 同 id 的插件已經裝了（不論來自哪裡）：不能再裝一個，要換來源先移除。
  final bool installed;
  final bool busy;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(translationsProvider).plugins;
    final spacing = AppTokens.of(context).spacing;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(spacing.x4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Heading(
                name: entry.name,
                byline: p.versionAuthor(
                  version: entry.version,
                  author: entry.author,
                ),
                description: entry.description,
                tags: [if (installed) _Tag(text: p.tagInstalled)],
              ),
            ),
            SizedBox(width: spacing.x3),
            if (!installed)
              FilledButton.tonal(
                onPressed: busy || !entry.isCompatible ? null : onInstall,
                child: Text(entry.isCompatible ? p.install : p.needsAppUpdate),
              ),
          ],
        ),
      ),
    );
  }
}

/// 卡片的名稱、版本與作者、說明與標記。
class _Heading extends StatelessWidget {
  const _Heading({
    required this.name,
    required this.byline,
    required this.description,
    required this.tags,
  });

  final String name;
  final String byline;
  final String description;
  final List<Widget> tags;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: theme.textTheme.titleMedium),
        Text(
          byline,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (description.isNotEmpty) ...[
          SizedBox(height: spacing.x1),
          Text(description, style: theme.textTheme.bodyMedium),
        ],
        if (tags.isNotEmpty) ...[
          SizedBox(height: spacing.x2),
          Wrap(spacing: spacing.x2, runSpacing: spacing.x1, children: tags),
        ],
      ],
    );
  }
}

enum _TagTone { neutral, primary, error }

/// 小標記（已停用、沒有回應、有更新、已安裝）：只是文字，不能點。
class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.tone = _TagTone.neutral});

  final String text;
  final _TagTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      _TagTone.neutral => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      _TagTone.primary => (scheme.primaryContainer, scheme.onPrimaryContainer),
      _TagTone.error => (scheme.errorContainer, scheme.onErrorContainer),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(tokens.radius.small),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.x2,
          vertical: tokens.spacing.x1,
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: foreground),
        ),
      ),
    );
  }
}

/// 詳細資料的一項：標籤在上、內容在下。
class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.x2),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// 某一份插件庫的狀態（沒有插件、讀不到、需要更新 FMP），可附一個動作。
class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final action = this.action;
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.x4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// 管理插件庫（ADR 0030 §決定 6）：官方的一列（不能刪）、自訂的每個一列與刪除鈕、
/// 「加入插件庫」（先提示「非官方來源」）。
class _IndexesDialog extends ConsumerWidget {
  const _IndexesDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final p = t.plugins;
    final custom = ref.watch(customIndexesProvider).value ?? const [];
    return AlertDialog(
      title: Text(p.indexesTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(p.sourceOfficial),
              subtitle: const Text(officialPluginIndexUrl),
            ),
            for (final record in custom)
              ListTile(
                key: ValueKey(record.url),
                contentPadding: EdgeInsets.zero,
                title: Text(p.customIndex),
                subtitle: Text(record.url),
                trailing: IconButton(
                  tooltip: p.removeIndex,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _remove(ref, record.url),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _add(context, ref, custom),
          child: Text(p.addIndex),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(p.close),
        ),
      ],
    );
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    List<PluginIndexRecord> custom,
  ) async {
    final t = ref.read(translationsProvider);
    final repository = ref.read(pluginIndexRepositoryProvider);
    final toaster = ref.read(toasterProvider);
    final url = await askHttpsUrl(
      context,
      t,
      title: t.plugins.addIndex,
      label: t.plugins.indexUrlLabel,
      confirm: t.plugins.add,
      warning: t.plugins.indexWarning,
    );
    if (url == null) return;
    final text = url.toString();
    if (text == officialPluginIndexUrl ||
        custom.any((record) => record.url == text)) {
      toaster.info(t.plugins.indexExists);
      return;
    }
    try {
      await repository.add(text, clock.now().toUtc());
      toaster.success(t.plugins.indexAdded);
    } on Object catch (error, stackTrace) {
      toaster.error(
        AppError.wrap(error, stackTrace),
        operation: 'Failed to add a plugin index',
        tag: _tag,
      );
    }
  }

  Future<void> _remove(WidgetRef ref, String url) async {
    final t = ref.read(translationsProvider);
    final repository = ref.read(pluginIndexRepositoryProvider);
    final toaster = ref.read(toasterProvider);
    try {
      await repository.remove(url);
      toaster.success(t.plugins.indexRemoved);
    } on Object catch (error, stackTrace) {
      toaster.error(
        AppError.wrap(error, stackTrace),
        operation: 'Failed to remove a plugin index',
        tag: _tag,
      );
    }
  }
}
