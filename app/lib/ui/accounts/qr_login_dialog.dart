import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/data/repositories/account_repository.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/plugins/accounts/account_service.dart';
import 'package:fmp/plugins/accounts/qr_login.dart';
import 'package:fmp/plugins/source_plugin.dart';
import 'package:fmp/ui/accounts/accounts_state.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/offline/offline.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 以 QR 碼登入 [plugin]（design §6.4）：一個對話框，QR 碼在上、進度在下。登入成功時
/// 關閉並回傳帳號；取消、Esc 或點外面是 `null`，離開時停止輪詢（[QrLogin.dispose]）。
///
/// 用對話框而不是全螢幕頁：內容只有一張 QR 碼與一行狀態，桌面上整頁太空；Esc 照
/// ADR 0024 §決定 8 關閉。
Future<Account?> showQrLogin(
  BuildContext context, {
  required SourcePlugin plugin,
  required String name,
}) => showDialog<Account>(
  context: context,
  builder: (context) => QrLoginDialog(plugin: plugin, name: name),
);

class QrLoginDialog extends ConsumerStatefulWidget {
  const QrLoginDialog({super.key, required this.plugin, required this.name});

  final SourcePlugin plugin;

  /// 插件的顯示名稱（manifest 的 `name`）。
  final String name;

  @override
  ConsumerState<QrLoginDialog> createState() => _QrLoginDialogState();
}

class _QrLoginDialogState extends ConsumerState<QrLoginDialog> {
  late final QrLogin _login;

  @override
  void initState() {
    super.initState();
    _login = QrLogin(
      plugin: widget.plugin,
      accounts: ref.read(accountServiceProvider),
      log: ref.read(logProvider),
    )..addListener(_onChanged);
    unawaited(_login.start());
  }

  void _onChanged() {
    if (_login.value case QrLoginDone(:final account) when mounted) {
      Navigator.of(context).pop(account);
    }
  }

  @override
  void dispose() {
    _login
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final a = t.accounts;
    final network = ref.watch(networkStatusProvider);
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    return ValueListenableBuilder<QrLoginState>(
      valueListenable: _login,
      builder: (context, state, _) {
        final status = switch (state) {
          QrLoginStarting() => a.qrStarting,
          QrLoginShowing(scanned: false) => a.qrWaiting,
          QrLoginShowing(scanned: true) => a.qrScanned,
          QrLoginExpired() => a.qrExpired,
          QrLoginVerifying() || QrLoginDone() => a.verifying,
          // 失敗的原因寫在上面那一塊。
          QrLoginFailed() => null,
        };
        return AlertDialog(
          title: Text(a.qrTitle(name: widget.name)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: AppLayout.qrCodeSize + spacing.x4 * 2,
                  child: _area(t, state, network),
                ),
                if (status != null) ...[
                  SizedBox(height: spacing.x4),
                  // 進度一變就念給螢幕閱讀器（已掃描、已過期）。
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      status,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(a.cancel),
            ),
            if (state case QrLoginExpired() || QrLoginFailed())
              FilledButton.tonal(
                onPressed: () => unawaited(_login.start()),
                child: Text(state is QrLoginExpired ? a.qrRegenerate : a.retry),
              ),
          ],
        );
      },
    );
  }

  Widget _area(Translations t, QrLoginState state, NetworkStatus network) =>
      switch (state) {
        QrLoginStarting() ||
        QrLoginVerifying() ||
        QrLoginDone() => const Center(child: CircularProgressIndicator()),
        QrLoginShowing(:final qrText) => _QrCode(
          text: qrText,
          label: t.accounts.qrImage,
        ),
        QrLoginExpired(:final qrText) => Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              child: _QrCode(text: qrText, label: t.accounts.qrImage),
            ),
            ColoredBox(
              color: AppLayout.qrBackground.withValues(
                alpha: AppLayout.qrExpiredScrimOpacity,
              ),
              child: const Center(
                child: Icon(
                  Icons.refresh,
                  size: AppLayout.emptyStateIcon,
                  color: AppLayout.qrForeground,
                ),
              ),
            ),
          ],
        ),
        // 送出了才知道連不上（ADR 0016 §決定 7）：失敗而不在 online 時是離線空狀態。
        QrLoginFailed() when network != NetworkStatus.online => OfflineMessage(
          status: network,
        ),
        QrLoginFailed(:final error) => EmptyState(
          icon: Icons.error_outline,
          title: loginErrorMessage(t, error, name: widget.name),
        ),
      };
}

/// 白底黑點的 QR 碼（不跟主題，[AppLayout.qrBackground]）。
class _QrCode extends StatelessWidget {
  const _QrCode({required this.text, required this.label});

  final String text;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // 自己一個語意節點（圖片加名稱）：套件的標籤沒有 container，會併進對話框裡別的字。
    return Semantics(
      container: true,
      image: true,
      label: label,
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(tokens.radius.medium),
          child: QrImageView(
            data: text,
            size: AppLayout.qrCodeSize + tokens.spacing.x4 * 2,
            padding: EdgeInsets.all(tokens.spacing.x4),
            backgroundColor: AppLayout.qrBackground,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: AppLayout.qrForeground,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: AppLayout.qrForeground,
            ),
            semanticsLabel: label,
            // 文字太長畫不成 QR 碼（插件的錯）：不留一塊空白。
            errorStateBuilder: (context, error) => const Center(
              child: Icon(Icons.error_outline, color: AppLayout.qrForeground),
            ),
          ),
        ),
      ),
    );
  }
}
