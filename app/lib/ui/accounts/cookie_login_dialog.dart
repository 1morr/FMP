import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/plugins/accounts/account_service.dart';
import 'package:fmp/plugins/accounts/cookie_text.dart';
import 'package:fmp/plugins/accounts/login_credentials.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:fmp/ui/errors/error_message.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/plugins/plugin_dialogs.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 貼上 cookie 登入 [plugin]（design §6.4，ADR 0029 §決定 10）：一個對話框，多行輸入框、
/// 「如何取得」的通用步驟（不指名音源）與「cookie 等同登入」的警告。按「登入」解析
/// （[parseCookieText]）後交 `AccountService.login`（`loginVerify` 通過才寫入）；成功時
/// 關閉並回傳帳號，取消、Esc 或點外面是 `null`。
///
/// 驗證失敗留在對話框、輸入不清掉，錯誤寫在輸入框下（使用者通常是貼錯了，改了再按）。
/// 輸入的內容不進 log、不進錯誤報告：這裡只記驗證的錯誤本身，`loginVerify` 之前宿主已把
/// 值登記到遮蔽函式。輸入框關掉個人化學習，鍵盤不記住它。
///
/// 用對話框（同 QR 登入、從網址安裝）：一個輸入框加說明，桌面上整頁太空。
Future<Account?> showCookieLogin(
  BuildContext context, {
  required SourcePlugin plugin,
  required String name,
}) => showDialog<Account>(
  context: context,
  builder: (context) => CookieLoginDialog(plugin: plugin, name: name),
);

class CookieLoginDialog extends ConsumerStatefulWidget {
  const CookieLoginDialog({
    super.key,
    required this.plugin,
    required this.name,
  });

  final SourcePlugin plugin;

  /// 插件的顯示名稱（manifest 的 `name`）。
  final String name;

  @override
  ConsumerState<CookieLoginDialog> createState() => _CookieLoginDialogState();
}

class _CookieLoginDialogState extends ConsumerState<CookieLoginDialog> {
  final _text = TextEditingController();
  var _verifying = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = ref.read(translationsProvider);
    final cookies = parseCookieText(_text.text);
    if (cookies.isEmpty) {
      setState(() => _error = t.accounts.cookieEmpty);
      return;
    }
    final accounts = ref.read(accountServiceProvider);
    final log = ref.read(logProvider);
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final account = await accounts.login(
        widget.plugin,
        LoginCredentials(cookies: cookies),
      );
      if (mounted) Navigator.of(context).pop(account);
    } on Object catch (error, stackTrace) {
      final appError = AppError.wrap(
        error,
        stackTrace,
        pluginId: widget.plugin.manifest.id,
      );
      log.report('Cookie login failed', appError, tag: 'accounts');
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = _failure(t, appError, ref.read(networkStatusProvider));
      });
    }
  }

  /// 失敗而不在 online 時寫離線的原因（ADR 0016 §決定 7）；輸入要留著，所以不換成整塊的
  /// 離線空狀態。
  String _failure(Translations t, AppError error, NetworkStatus network) =>
      switch (network) {
        NetworkStatus.noInterface => t.offline.noInterface,
        NetworkStatus.unreachable => t.offline.unreachable,
        NetworkStatus.online => errorMessage(t, error, sourceName: widget.name),
      };

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final a = t.accounts;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final steps = [a.cookieStep1, a.cookieStep2, a.cookieStep3];
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return AlertDialog(
      title: Text(a.cookieTitle(name: widget.name)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _text,
              autofocus: true,
              enabled: !_verifying,
              minLines: 4,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              decoration: InputDecoration(
                labelText: a.cookieLabel,
                hintText: a.cookieHint,
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
                errorText: _error,
                errorMaxLines: 3,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            if (_verifying) ...[
              SizedBox(height: spacing.x2),
              LinearProgressIndicator(semanticsLabel: a.verifying),
            ],
            SizedBox(height: spacing.x4),
            Text(a.cookieHelpTitle, style: theme.textTheme.titleSmall),
            SizedBox(height: spacing.x2),
            for (final (index, step) in steps.indexed)
              Padding(
                padding: EdgeInsets.only(bottom: spacing.x1),
                child: Text('${index + 1}. $step', style: muted),
              ),
            SizedBox(height: spacing.x1),
            Text(a.cookieFile, style: muted),
            SizedBox(height: spacing.x4),
            WarningNote(text: a.cookieWarning),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(a.cancel),
        ),
        FilledButton(
          onPressed: _verifying ? null : () => unawaited(_submit()),
          child: Text(a.signIn),
        ),
      ],
    );
  }
}
