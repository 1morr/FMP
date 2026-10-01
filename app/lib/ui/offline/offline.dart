import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

// 離線的兩個呈現（ADR 0016 §決定 7、design §5.4）：外殼內容區頂端的全域提示，
// 以及頁面共用的離線空狀態。都不是 toast：狀態持續多久就顯示多久。

IconData _iconOf(NetworkStatus status) => switch (status) {
  NetworkStatus.noInterface => Icons.wifi_off,
  NetworkStatus.online || NetworkStatus.unreachable => Icons.cloud_off,
};

/// 外殼內容區頂端的全域離線提示；`online` 時不佔位置。
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(networkStatusProvider);
    final t = ref.watch(translationsProvider).offline;
    final text = switch (status) {
      NetworkStatus.online => null,
      NetworkStatus.noInterface => t.noInterface,
      NetworkStatus.unreachable => t.unreachable,
    };
    if (text == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    final colors = tokens.warning;
    // 狀態一出現就念給螢幕閱讀器（liveRegion），不必等使用者讀到這一區。
    return Semantics(
      container: true,
      liveRegion: true,
      child: ColoredBox(
        color: colors.container,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.x4,
            vertical: tokens.spacing.x2,
          ),
          child: Row(
            children: [
              Icon(_iconOf(status), color: colors.onContainer),
              SizedBox(width: tokens.spacing.x3),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 頁面共用的離線空狀態：這一頁的內容要網路，而現在 [status] 不是 `online`。
/// [action] 是頁面自己的動作（例如搜尋的「重試」）。
class OfflineMessage extends ConsumerWidget {
  const OfflineMessage({super.key, required this.status, this.action})
    : assert(status != NetworkStatus.online);

  final NetworkStatus status;
  final Widget? action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).offline;
    final (title, body) = switch (status) {
      NetworkStatus.online ||
      NetworkStatus.unreachable => (t.unreachable, t.unreachableHint),
      NetworkStatus.noInterface => (t.noInterface, t.noInterfaceHint),
    };
    return EmptyState(
      icon: _iconOf(status),
      title: title,
      body: body,
      action: action,
    );
  }
}
