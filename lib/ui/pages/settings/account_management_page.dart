import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:simple_icons/simple_icons.dart';

import '../../../core/services/image_loading_service.dart';
import '../../../core/services/toast_service.dart';
import '../../../data/models/track.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/account_provider.dart';
import '../../router.dart';
import 'widgets/account_playlists_sheet.dart';
import 'widgets/account_radio_import_sheet.dart';

/// 帳號管理頁面
class AccountManagementPage extends ConsumerWidget {
  const AccountManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bilibiliAccount = ref.watch(bilibiliAccountProvider);
    final youtubeAccount = ref.watch(youtubeAccountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.account.title),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // Bilibili 卡片
          _PlatformCard(
            platformName: t.importPlatform.bilibili,
            icon: SimpleIcons.bilibili,
            iconColor: const Color(0xFFFF6699),
            isLoggedIn: bilibiliAccount?.isLoggedIn ?? false,
            userName: bilibiliAccount?.userName,
            avatarUrl: bilibiliAccount?.avatarUrl,
            onLogin: () => context.push(RoutePaths.bilibiliLogin),
            onLogout: () => _confirmLogout(context, ref, SourceType.bilibili),
            onManagePlaylists: () =>
                _showPlaylistSheet(context, SourceType.bilibili),
            onImportRadio: () => _showRadioImportSheet(context),
          ),
          const SizedBox(height: 12),
          // YouTube 卡片
          _PlatformCard(
            platformName: t.importPlatform.youtube,
            icon: SimpleIcons.youtube,
            iconColor: Colors.red,
            isLoggedIn: youtubeAccount?.isLoggedIn ?? false,
            userName: youtubeAccount?.userName,
            avatarUrl: youtubeAccount?.avatarUrl,
            onLogin: () => context.push(RoutePaths.youtubeLogin),
            onLogout: () => _confirmLogout(context, ref, SourceType.youtube),
            onManagePlaylists: () =>
                _showPlaylistSheet(context, SourceType.youtube),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(
    BuildContext context,
    WidgetRef ref,
    SourceType platform,
  ) async {
    final platformName = platform == SourceType.bilibili
        ? t.importPlatform.bilibili
        : t.importPlatform.youtube;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.account.logout),
        content: Text(t.account.logoutConfirm(platform: platformName)),
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
      switch (platform) {
        case SourceType.bilibili:
          await ref.read(bilibiliAccountServiceProvider).logout();
        case SourceType.youtube:
          await ref.read(youtubeAccountServiceProvider).logout();
        case SourceType.netease:
          break; // TODO: Netease logout (Phase 2)
      }
      if (context.mounted) {
        ToastService.show(context, t.account.logoutSuccess);
      }
    }
  }

  void _showPlaylistSheet(BuildContext context, SourceType platform) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AccountPlaylistsSheet(platform: platform),
    );
  }

  void _showRadioImportSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const AccountRadioImportSheet(),
    );
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
  final VoidCallback? onManagePlaylists;
  final VoidCallback? onImportRadio;

  const _PlatformCard({
    required this.platformName,
    required this.icon,
    required this.iconColor,
    required this.isLoggedIn,
    this.userName,
    this.avatarUrl,
    this.onLogin,
    this.onLogout,
    this.onManagePlaylists,
    this.onImportRadio,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final avatar = isLoggedIn && avatarUrl != null
        ? ImageLoadingService.loadAvatar(
            networkUrl: avatarUrl,
            size: 48,
          )
        : CircleAvatar(
            radius: 24,
            backgroundColor: iconColor.withValues(alpha: 0.1),
            child: Icon(icon, color: iconColor, size: 28),
          );
    final accountText =
        isLoggedIn ? userName ?? t.account.loggedIn : t.account.notLoggedIn;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final shouldStackActions =
                  isLoggedIn && constraints.maxWidth < 520;

              final info = Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      platformName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      accountText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              );

              final actionButtons = <Widget>[
                OutlinedButton(
                  onPressed: onManagePlaylists,
                  child: Text(t.account.playlists),
                ),
                if (onImportRadio != null)
                  OutlinedButton(
                    onPressed: onImportRadio,
                    child: Text(t.account.radioStations),
                  ),
                OutlinedButton(
                  onPressed: onLogout,
                  child: Text(t.account.logout),
                ),
              ];

              if (shouldStackActions) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        avatar,
                        const SizedBox(width: 16),
                        info,
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: actionButtons,
                      ),
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  avatar,
                  const SizedBox(width: 16),
                  info,
                  if (isLoggedIn)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < actionButtons.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          actionButtons[i],
                        ],
                      ],
                    )
                  else
                    FilledButton(
                      onPressed: onLogin,
                      child: Text(t.account.login),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
