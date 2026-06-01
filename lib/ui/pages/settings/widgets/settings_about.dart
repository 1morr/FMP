part of '../settings_page.dart';

/// 版本号（点击7次解锁开发者选项）
class _VersionListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devOptions = ref.watch(developerOptionsProvider);
    final notifier = ref.read(developerOptionsProvider.notifier);

    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '...';
        final versionText = 'v$version';

        return ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(t.settings.version.title),
          subtitle: Text(versionText),
          onTap: () {
            notifier.onVersionTap();

            if (!devOptions.isEnabled) {
              final remaining = notifier.remainingTaps;
              if (remaining <= 4 && remaining > 0) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text(t.settings.version.tapToEnableDev(n: remaining)),
                    duration: const Duration(seconds: 1),
                  ),
                );
              } else if (remaining == 0) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(t.settings.version.devEnabled),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            }
          },
        );
      },
    );
  }
}

/// 检查更新
class _CheckUpdateListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(updateProvider);
    final isChecking = updateState.status == UpdateStatus.checking;

    return ListTile(
      leading: const Icon(Icons.system_update_outlined),
      title: Text(t.settings.update.title),
      subtitle: Text(
        switch (updateState.status) {
          UpdateStatus.checking => t.settings.update.checking,
          UpdateStatus.upToDate => t.settings.update.upToDate,
          UpdateStatus.updateAvailable => t.settings.update
              .available(version: updateState.updateInfo?.version ?? ""),
          UpdateStatus.error => t.settings.update.error,
          _ => t.settings.update.checkGitHub,
        },
      ),
      trailing: isChecking
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: isChecking
          ? null
          : () async {
              await ref.read(updateProvider.notifier).checkForUpdate();
              final state = ref.read(updateProvider);
              if (!context.mounted) return;

              if (state.status == UpdateStatus.updateAvailable &&
                  state.updateInfo != null) {
                UpdateDialog.show(context, state.updateInfo!);
              } else if (state.status == UpdateStatus.upToDate) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(t.settings.update.upToDate),
                    duration: const Duration(seconds: 2),
                  ),
                );
              } else if (state.status == UpdateStatus.error) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        state.errorMessage ?? t.settings.update.checkFailed),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
    );
  }
}

/// 开发者选项区域（隐藏，需要解锁）
class _DeveloperOptionsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devOptions = ref.watch(developerOptionsProvider);

    if (!devOptions.isEnabled) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        const Divider(),
        _SettingsSection(
          title: t.settings.developerOptions.title,
          children: [
            ListTile(
              leading: const Icon(Icons.developer_mode_outlined),
              title: Text(t.settings.developerOptions.title),
              subtitle: Text(t.settings.developerOptions.subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.pushNamed(RouteNames.developerOptions),
            ),
          ],
        ),
      ],
    );
  }
}
