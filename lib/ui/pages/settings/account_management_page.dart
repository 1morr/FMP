import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:simple_icons/simple_icons.dart';

import '../../../core/services/image_loading_service.dart';
import '../../../core/services/toast_service.dart';
import '../../../data/models/track.dart';
import '../../../i18n/strings.g.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/repository_providers.dart';
import '../../../services/account/account_service.dart';
import '../../router.dart';
import 'widgets/account_playlists_sheet.dart';
import 'widgets/account_radio_import_sheet.dart';

/// 帳號管理頁面
class AccountManagementPage extends ConsumerStatefulWidget {
  const AccountManagementPage({super.key});

  @override
  ConsumerState<AccountManagementPage> createState() =>
      _AccountManagementPageState();
}

class _AccountManagementPageState extends ConsumerState<AccountManagementPage> {
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    // Ensure DB settings match hardcoded UI state (fire-and-forget)
    _ensureAuthSettings();
  }

  Future<void> _ensureAuthSettings() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    await settingsRepo.update((s) {
      s.setUseAuthForPlay(SourceType.bilibili, false);
      s.setUseAuthForPlay(SourceType.youtube, false);
      s.setUseAuthForPlay(SourceType.netease, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bilibiliAccount = ref.watch(bilibiliAccountProvider);
    final youtubeAccount = ref.watch(youtubeAccountProvider);
    final neteaseAccount = ref.watch(neteaseAccountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.account.title),
        actions: [
          IconButton(
            icon: _isVerifying
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: t.account.checkingAccounts,
            onPressed: _isVerifying ? null : _verifyAllAccounts,
          ),
          const SizedBox(width: 8),
        ],
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
            isVip: bilibiliAccount?.isLoggedIn == true
                ? bilibiliAccount?.isVip
                : null,
            vipTooltip: bilibiliAccount?.isVip == true
                ? t.account.bilibiliVip
                : t.account.bilibiliNotVip,
            vipIcon: Icons.verified_outlined,
            useAuthForPlay: false,
            authInteractive: false,
            authTooltip: t.account.authNotSupported,
            onLogin: () => context.push(RoutePaths.bilibiliLogin),
            onLogout: () => _confirmLogout(SourceType.bilibili),
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
            isVip: youtubeAccount?.isLoggedIn == true
                ? youtubeAccount?.isVip
                : null,
            vipTooltip: youtubeAccount?.isVip == true
                ? t.account.youtubeVip
                : t.account.youtubeNotVip,
            vipIcon: Icons.workspace_premium_outlined,
            useAuthForPlay: false,
            authInteractive: false,
            authTooltip: t.account.authNotSupported,
            onLogin: () => context.push(RoutePaths.youtubeLogin),
            onLogout: () => _confirmLogout(SourceType.youtube),
            onManagePlaylists: () =>
                _showPlaylistSheet(context, SourceType.youtube),
          ),
          const SizedBox(height: 12),
          // 網易雲卡片
          _PlatformCard(
            platformName: t.importPlatform.netease,
            icon: SimpleIcons.neteasecloudmusic,
            iconColor: const Color(0xFFE60026),
            isLoggedIn: neteaseAccount?.isLoggedIn ?? false,
            userName: neteaseAccount?.userName,
            avatarUrl: neteaseAccount?.avatarUrl,
            isVip: neteaseAccount?.isLoggedIn == true
                ? neteaseAccount?.isVip
                : null,
            vipTooltip: neteaseAccount?.isVip == true
                ? t.account.neteaseVip
                : t.account.neteaseNotVip,
            useAuthForPlay: true,
            authInteractive: false,
            authTooltip: t.account.authRequired,
            onLogin: () => context.push(RoutePaths.neteaseLogin),
            onLogout: () => _confirmLogout(SourceType.netease),
            onManagePlaylists: () =>
                _showPlaylistSheet(context, SourceType.netease),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyAllAccounts() async {
    setState(() => _isVerifying = true);

    try {
      final toastService = ref.read(toastServiceProvider);
      toastService.showInfo(t.account.checkingAccounts);

      final services = <AccountService>[
        ref.read(bilibiliAccountServiceProvider),
        ref.read(youtubeAccountServiceProvider),
        ref.read(neteaseAccountServiceProvider),
      ];

      await verifyAllAccountStatuses(services, toastService);
      toastService.showSuccess(t.account.accountsVerified);
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  Future<void> _confirmLogout(SourceType platform) async {
    final platformName = platform.displayName;
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
          await ref.read(neteaseAccountServiceProvider).logout();
      }
      if (mounted) {
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
  final bool? isVip;
  final String? vipTooltip;
  final IconData vipIcon;
  final bool? useAuthForPlay;
  final bool authInteractive;
  final String? authTooltip;
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
    this.isVip,
    this.vipTooltip,
    this.vipIcon = Icons.diamond_outlined,
    this.useAuthForPlay,
    this.authInteractive = true,
    this.authTooltip,
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            accountText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                          ),
                        ),
                        if (isLoggedIn && isVip == true) ...[
                          const SizedBox(width: 4),
                          Tooltip(
                            message: vipTooltip ?? '',
                            child: Icon(
                              vipIcon,
                              size: 14,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );

              // 登入狀態播放按鈕：啟用時高亮 (FilledButton.tonal)，停用時中空 (OutlinedButton)
              Widget? authButton;
              if (useAuthForPlay != null) {
                final button = useAuthForPlay!
                    ? FilledButton.tonal(
                        onPressed: authInteractive ? () {} : null,
                        child: Text(t.account.useAuth),
                      )
                    : OutlinedButton(
                        onPressed: authInteractive ? () {} : null,
                        child: Text(t.account.useAuth),
                      );
                if (authTooltip != null) {
                  // Wrap disabled button in ExcludeSemantics to avoid
                  // Flutter accessibility tree errors with Tooltip
                  authButton = Tooltip(
                    message: authTooltip!,
                    child: ExcludeSemantics(child: button),
                  );
                } else {
                  authButton = button;
                }
              }

              final actionButtons = <Widget>[
                if (authButton != null) authButton,
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
