import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:simple_icons/simple_icons.dart';

import 'package:fmp/core/services/toast_service.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/providers/account/account_provider.dart';
import 'package:fmp/ui/router.dart';
import 'package:fmp/ui/widgets/images/avatar_image.dart';
import 'package:fmp/ui/pages/settings/widgets/account_playlists_sheet.dart';
import 'package:fmp/ui/pages/settings/widgets/account_radio_import_sheet.dart';

/// 平台品牌色（帳號卡片圖示用）
const Color kBrandBilibili = Color(0xFFFF6699);
const Color kBrandYoutube = Color(0xFFFF0000);
const Color kBrandNetease = Color(0xFFE60026);

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
            iconColor: kBrandBilibili,
            isLoggedIn: bilibiliAccount?.isLoggedIn ?? false,
            sessionExpired: bilibiliAccount?.sessionExpired ?? false,
            userName: bilibiliAccount?.userName,
            avatarUrl: bilibiliAccount?.avatarUrl,
            isVip: bilibiliAccount?.isLoggedIn == true
                ? bilibiliAccount?.isVip
                : null,
            vipTooltip: bilibiliAccount?.isVip == true
                ? t.account.bilibiliVip
                : t.account.bilibiliNotVip,
            vipIcon: Icons.verified_outlined,
            onLogin: () => context.push(RoutePaths.bilibiliLogin),
            onLogout: () => _confirmLogout(SourceIds.bilibili),
            onManagePlaylists: () =>
                _showPlaylistSheet(context, SourceIds.bilibili),
            onImportRadio: () => _showRadioImportSheet(context),
          ),
          const SizedBox(height: 12),
          // YouTube 卡片
          _PlatformCard(
            platformName: t.importPlatform.youtube,
            icon: SimpleIcons.youtube,
            iconColor: kBrandYoutube,
            isLoggedIn: youtubeAccount?.isLoggedIn ?? false,
            sessionExpired: youtubeAccount?.sessionExpired ?? false,
            userName: youtubeAccount?.userName,
            avatarUrl: youtubeAccount?.avatarUrl,
            isVip: youtubeAccount?.isLoggedIn == true
                ? youtubeAccount?.isVip
                : null,
            vipTooltip: youtubeAccount?.isVip == true
                ? t.account.youtubeVip
                : t.account.youtubeNotVip,
            vipIcon: Icons.workspace_premium_outlined,
            onLogin: () => context.push(RoutePaths.youtubeLogin),
            onLogout: () => _confirmLogout(SourceIds.youtube),
            onManagePlaylists: () =>
                _showPlaylistSheet(context, SourceIds.youtube),
          ),
          const SizedBox(height: 12),
          // 網易雲卡片
          _PlatformCard(
            platformName: t.importPlatform.netease,
            icon: SimpleIcons.neteasecloudmusic,
            iconColor: kBrandNetease,
            isLoggedIn: neteaseAccount?.isLoggedIn ?? false,
            sessionExpired: neteaseAccount?.sessionExpired ?? false,
            userName: neteaseAccount?.userName,
            avatarUrl: neteaseAccount?.avatarUrl,
            isVip: neteaseAccount?.isLoggedIn == true
                ? neteaseAccount?.isVip
                : null,
            vipTooltip: neteaseAccount?.isVip == true
                ? t.account.neteaseVip
                : t.account.neteaseNotVip,
            onLogin: () => context.push(RoutePaths.neteaseLogin),
            onLogout: () => _confirmLogout(SourceIds.netease),
            onManagePlaylists: () =>
                _showPlaylistSheet(context, SourceIds.netease),
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

      final services = ref.read(accountServicesProvider).values.toList();

      final result = await verifyAllAccountStatuses(
        services,
        toastService,
        sessionExpiry: ref.read(sessionExpiryNotifierProvider),
      );
      if (result.hasFailures) {
        final platforms = result.failedPlatforms
            .map((platform) => SourceIds.displayNameFor(platform))
            .join(', ');
        toastService.showWarning(
          t.account.accountsVerifiedWithFailures(platforms: platforms),
        );
      } else {
        toastService.showSuccess(t.account.accountsVerified);
      }
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  Future<void> _confirmLogout(String platform) async {
    final platformName = SourceIds.displayNameFor(platform);
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
      await ref.read(accountServicesProvider)[platform]?.logout();
      if (mounted) {
        ToastService.show(context, t.account.logoutSuccess);
      }
    }
  }

  void _showPlaylistSheet(BuildContext context, String platform) {
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
  final bool sessionExpired;
  final String? userName;
  final String? avatarUrl;
  final bool? isVip;
  final String? vipTooltip;
  final IconData vipIcon;
  final VoidCallback? onLogin;
  final VoidCallback? onLogout;
  final VoidCallback? onManagePlaylists;
  final VoidCallback? onImportRadio;

  const _PlatformCard({
    required this.platformName,
    required this.icon,
    required this.iconColor,
    required this.isLoggedIn,
    this.sessionExpired = false,
    this.userName,
    this.avatarUrl,
    this.isVip,
    this.vipTooltip,
    this.vipIcon = Icons.diamond_outlined,
    this.onLogin,
    this.onLogout,
    this.onManagePlaylists,
    this.onImportRadio,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final colorScheme = Theme.of(context).colorScheme;
    // 失效態保留頭像與暱稱：使用者要認得出這是「我那個帳號」過期了，
    // 而不是從沒登入過。
    final isExpired = sessionExpired && !isLoggedIn;
    final avatar = (isLoggedIn || isExpired) && avatarUrl != null
        ? AvatarImage(networkUrl: avatarUrl, size: 48)
        : CircleAvatar(
            radius: 24,
            backgroundColor: iconColor.withValues(alpha: 0.1),
            child: Icon(icon, color: iconColor, size: 28),
          );
    final String accountText;
    if (isLoggedIn) {
      accountText = userName ?? t.account.loggedIn;
    } else if (isExpired) {
      accountText = userName == null
          ? t.account.sessionExpiredShort
          : '$userName · ${t.account.sessionExpiredShort}';
    } else {
      accountText = t.account.notLoggedIn;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
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
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: isExpired
                                      ? colorScheme.error
                                      : colorScheme.onSurfaceVariant,
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

              // 三態各自的尾端按鈕：已登入、登入失效、未登入。
              // 失效態的主按鈕走的是同一條登入流程，次按鈕把整列清掉。
              final actionButtons = isLoggedIn
                  ? <Widget>[
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
                    ]
                  : isExpired
                  ? <Widget>[
                      FilledButton(
                        onPressed: onLogin,
                        child: Text(t.account.relogin),
                      ),
                      OutlinedButton(
                        onPressed: onLogout,
                        child: Text(t.account.logout),
                      ),
                    ]
                  : <Widget>[
                      FilledButton(
                        onPressed: onLogin,
                        child: Text(t.account.login),
                      ),
                    ];

              // 單顆按鈕永遠排得下，多顆才需要在窄卡片上換行。
              final shouldStackActions =
                  actionButtons.length > 1 && constraints.maxWidth < 520;

              if (shouldStackActions) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [avatar, const SizedBox(width: 16), info]),
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < actionButtons.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        actionButtons[i],
                      ],
                    ],
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
