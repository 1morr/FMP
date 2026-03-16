import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/toast_service.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/account_provider.dart';
import '../../router.dart';

/// 帳號管理頁面
class AccountManagementPage extends ConsumerWidget {
  const AccountManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bilibiliAccount = ref.watch(bilibiliAccountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.account.title),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // Bilibili 卡片
          _PlatformCard(
            platformName: 'Bilibili',
            icon: Icons.play_circle_outline,
            iconColor: const Color(0xFFFF6699),
            isLoggedIn: bilibiliAccount?.isLoggedIn ?? false,
            userName: bilibiliAccount?.userName,
            avatarUrl: bilibiliAccount?.avatarUrl,
            onLogin: () => context.push(RoutePaths.bilibiliLogin),
            onLogout: () => _confirmLogout(context, ref, 'Bilibili'),
          ),
          const SizedBox(height: 12),
          // YouTube 卡片（暫不可操作）
          _PlatformCard(
            platformName: 'YouTube',
            icon: Icons.smart_display_outlined,
            iconColor: Colors.red,
            isLoggedIn: false,
            enabled: false,
            disabledHint: t.account.comingSoon,
          ),
        ],
      ),
    );
  }
  Future<void> _confirmLogout(
    BuildContext context,
    WidgetRef ref,
    String platform,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.account.logout),
        content: Text(t.account.logoutConfirm(platform: platform)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.account.logout),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(bilibiliAccountServiceProvider).logout();
      if (context.mounted) {
        ToastService.show(context, t.account.logoutSuccess);
      }
    }
  }
}

/// 平台帳號卡片
class _PlatformCard extends StatelessWidget {
  final String platformName;
  final IconData icon;
  final Color iconColor;
  final bool isLoggedIn;
  final String? userName;
  final String? avatarUrl;
  final VoidCallback? onLogin;
  final VoidCallback? onLogout;
  final bool enabled;
  final String? disabledHint;

  const _PlatformCard({
    required this.platformName,
    required this.icon,
    required this.iconColor,
    required this.isLoggedIn,
    this.userName,
    this.avatarUrl,
    this.onLogin,
    this.onLogout,
    this.enabled = true,
    this.disabledHint,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.5,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // 平台圖標或頭像
                if (isLoggedIn && avatarUrl != null)
                  CircleAvatar(
                    radius: 24,
                    backgroundImage: NetworkImage(avatarUrl!),
                  )
                else
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: iconColor.withValues(alpha: 0.1),
                    child: Icon(icon, color: iconColor, size: 28),
                  ),
                const SizedBox(width: 16),
                // 信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        platformName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isLoggedIn
                            ? userName ?? t.account.loggedIn
                            : disabledHint ?? t.account.notLoggedIn,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                // 操作按鈕
                if (enabled)
                  isLoggedIn
                      ? OutlinedButton(
                          onPressed: onLogout,
                          child: Text(t.account.logout),
                        )
                      : FilledButton(
                          onPressed: onLogin,
                          child: Text(t.account.login),
                        ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
