import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/ui/plugins/plugin_text.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

// 插件頁的對話框：安裝與更新前的確認（ADR 0014 §決定 6、ADR 0030 §決定 8、9）、移除的
// 確認（§決定 10）、輸入網址（從網址安裝、加入自訂插件庫）。

/// 安裝或更新前要讓使用者看的內容。
@immutable
final class InstallConfirmation {
  const InstallConfirmation({
    required this.manifest,
    required this.isUpdate,
    required this.capabilities,
    required this.hosts,
    required this.unofficial,
    this.replacesVersion,
  });

  /// 要裝的那一份 manifest：從 index 裝的是下載並驗過 SHA-256 的 `.js` 標頭，不是
  /// index 那一筆（ADR 0030 §決定 8）。
  final PluginManifest manifest;

  /// 更新：[capabilities]、[hosts] 只是新增的部分（§決定 9）。新安裝時是全部。
  final bool isUpdate;
  final Set<PluginCapability> capabilities;
  final Set<String> hosts;

  /// 不是官方插件庫來的（自訂插件庫、檔案、網址）：多一則「非官方來源」。
  final bool unofficial;

  /// 從檔案或網址裝、而同 id 已經安裝時，被取代的版本。
  final String? replacesVersion;
}

/// 顯示安裝或更新的確認；使用者按了安裝或更新才是 `true`。
Future<bool> confirmInstall(
  BuildContext context,
  Translations t,
  InstallConfirmation confirmation,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => _InstallDialog(t: t, confirmation: confirmation),
    ) ??
    false;

class _InstallDialog extends StatelessWidget {
  const _InstallDialog({required this.t, required this.confirmation});

  final Translations t;
  final InstallConfirmation confirmation;

  @override
  Widget build(BuildContext context) {
    final p = t.plugins;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final manifest = confirmation.manifest;
    final description = manifest.description;
    final hosts = confirmation.hosts.toList()..sort();
    final capabilities = capabilityNames(t, confirmation.capabilities);
    Widget heading(String text) => Padding(
      padding: EdgeInsets.only(top: spacing.x4, bottom: spacing.x1),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    return AlertDialog(
      title: Text(
        confirmation.isUpdate
            ? p.updateTitle(name: manifest.name)
            : p.installTitle(name: manifest.name),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p.byline(author: manifest.author, version: manifest.version),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (description.isNotEmpty) ...[
              SizedBox(height: spacing.x2),
              Text(description, style: theme.textTheme.bodyMedium),
            ],
            if (confirmation.isUpdate) ...[
              SizedBox(height: spacing.x4),
              Text(p.addedAccess, style: theme.textTheme.bodyMedium),
            ],
            if (capabilities.isNotEmpty) ...[
              heading(
                confirmation.isUpdate ? p.addedCapabilities : p.capabilities,
              ),
              Text(
                capabilities.join(p.listSeparator),
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (hosts.isNotEmpty) ...[
              heading(confirmation.isUpdate ? p.addedHosts : p.hosts),
              for (final host in hosts)
                Text(host, style: theme.textTheme.bodyMedium),
            ],
            if (confirmation.replacesVersion case final version?) ...[
              SizedBox(height: spacing.x4),
              Text(
                p.replaces(version: version),
                style: theme.textTheme.bodyMedium,
              ),
            ],
            SizedBox(height: spacing.x4),
            WarningNote(text: p.loginWarning),
            if (confirmation.unofficial) ...[
              SizedBox(height: spacing.x2),
              WarningNote(text: p.unofficial),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(p.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            confirmation.isUpdate ? p.confirmUpdate : p.confirmInstall,
          ),
        ),
      ],
    );
  }
}

/// 首次啟動引導的確認（ADR 0030 §決定 12）：一次列出 [plugins] 每一個的能力與網域，
/// 下面一則共同的警告；使用者按了安裝才是 `true`。
Future<bool> confirmInstallAll(
  BuildContext context,
  Translations t,
  List<InstallConfirmation> plugins,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => _InstallAllDialog(t: t, plugins: plugins),
    ) ??
    false;

class _InstallAllDialog extends StatelessWidget {
  const _InstallAllDialog({required this.t, required this.plugins});

  final Translations t;
  final List<InstallConfirmation> plugins;

  @override
  Widget build(BuildContext context) {
    final p = t.plugins;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    return AlertDialog(
      title: Text(p.installAllTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final plugin in plugins) ...[
              Text(plugin.manifest.name, style: theme.textTheme.titleSmall),
              Text(
                p.byline(
                  author: plugin.manifest.author,
                  version: plugin.manifest.version,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: spacing.x1),
              Text(
                '${p.capabilities}: ${capabilityNames(t, plugin.capabilities).join(p.listSeparator)}',
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                '${p.hosts}: ${(plugin.hosts.toList()..sort()).join(p.listSeparator)}',
                style: theme.textTheme.bodyMedium,
              ),
              SizedBox(height: spacing.x3),
            ],
            WarningNote(text: p.loginWarning),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(p.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(p.confirmInstall),
        ),
      ],
    );
  }
}

/// 移除 [name] 的確認；使用者按了移除才是 `true`。
Future<bool> confirmRemove(
  BuildContext context,
  Translations t,
  String name,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.plugins.removeTitle(name: name)),
        content: Text(t.plugins.removeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.plugins.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.plugins.confirmRemove),
          ),
        ],
      ),
    ) ??
    false;

/// 問一個 `https` 網址；取消是 `null`。[warning] 顯示在輸入框下方（加入自訂插件庫的
/// 「非官方來源」）。
Future<Uri?> askHttpsUrl(
  BuildContext context,
  Translations t, {
  required String title,
  required String label,
  required String confirm,
  String? warning,
}) => showDialog<Uri>(
  context: context,
  builder: (context) => _UrlDialog(
    t: t,
    title: title,
    label: label,
    confirm: confirm,
    warning: warning,
  ),
);

/// 使用者輸入的 `https` 網址；不是就是 `null`（有主機、沒有 user info）。
Uri? parseHttpsUrl(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

class _UrlDialog extends StatefulWidget {
  const _UrlDialog({
    required this.t,
    required this.title,
    required this.label,
    required this.confirm,
    required this.warning,
  });

  final Translations t;
  final String title;
  final String label;
  final String confirm;
  final String? warning;

  @override
  State<_UrlDialog> createState() => _UrlDialogState();
}

class _UrlDialogState extends State<_UrlDialog> {
  final _text = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final uri = parseHttpsUrl(_text.text);
    if (uri == null) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(uri);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.t.plugins;
    final spacing = AppTokens.of(context).spacing;
    final warning = widget.warning;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _text,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              inputFormatters: [
                FilteringTextInputFormatter.singleLineFormatter,
              ],
              decoration: InputDecoration(
                labelText: widget.label,
                errorText: _invalid ? p.urlInvalid : null,
              ),
              onChanged: (_) {
                if (_invalid) setState(() => _invalid = false);
              },
              onSubmitted: (_) => _submit(),
            ),
            if (warning != null) ...[
              SizedBox(height: spacing.x4),
              WarningNote(text: warning),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(p.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirm)),
      ],
    );
  }
}

/// 對話框裡的警告：語意色的「警告」底、圖示與一句話。
class WarningNote extends StatelessWidget {
  const WarningNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final colors = tokens.warning;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.container,
        borderRadius: BorderRadius.circular(tokens.radius.small),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.x3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: colors.onContainer),
            SizedBox(width: tokens.spacing.x3),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colors.onContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
