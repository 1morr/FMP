part of '../settings_page.dart';

/// 下载管理入口
class _DownloadManagerListTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.download_outlined),
      title: Text(t.settings.downloadManager.title),
      subtitle: Text(t.settings.downloadManager.subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.pushNamed(RouteNames.downloadManager),
    );
  }
}

/// 下载路径设置
class _DownloadPathListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadPathAsync = ref.watch(downloadPathProvider);

    return downloadPathAsync.when(
      loading: () => ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text(t.settings.downloadPath.title),
        subtitle: Text(t.general.loading),
      ),
      error: (e, _) => ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text(t.settings.downloadPath.title),
        subtitle: Text(t.settings.downloadPath.loadFailed(error: e.toString())),
      ),
      data: (downloadPath) => ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text(t.settings.downloadPath.title),
        subtitle: Text(downloadPath ?? t.general.notSet),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showDownloadPathOptions(context, ref),
      ),
    );
  }

  void _showDownloadPathOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!Platform.isAndroid)
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: Text(t.settings.downloadPath.changePath),
                  onTap: () {
                    Navigator.pop(context);
                    _changeDownloadPath(context, ref);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(t.settings.downloadPath.pathInfo),
                onTap: () {
                  Navigator.pop(context);
                  _showPathInfo(context, ref);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changeDownloadPath(BuildContext context, WidgetRef ref) async {
    await ChangeDownloadPathDialog.show(context);
  }

  void _showPathInfo(BuildContext context, WidgetRef ref) {
    final downloadPath = ref.read(downloadPathProvider).value;
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.folder_outlined,
          color: colorScheme.primary,
          size: 32,
        ),
        title: Text(t.settings.downloadPath.pathInfoTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: AppRadius.borderRadiusMd,
              ),
              child: SelectableText(
                downloadPath ?? t.general.notSet,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (downloadPath != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.settings.downloadPath.pathChangeWarning,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.confirm),
          ),
        ],
      ),
    );
  }
}

/// 并发下载数设置
class _ConcurrentDownloadsListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(downloadSettingsProvider);
    final maxConcurrent = settings.maxConcurrentDownloads;

    return ListTile(
      leading: const Icon(Icons.speed_outlined),
      title: Text(t.settings.concurrentDownloads.title),
      subtitle: Text(t.settings.concurrentDownloads.subtitle(n: maxConcurrent)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showConcurrentDialog(context, ref, maxConcurrent),
    );
  }

  void _showConcurrentDialog(BuildContext context, WidgetRef ref, int current) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settings.concurrentDownloads.title),
        content: RadioGroup<int>(
          groupValue: current,
          onChanged: (value) {
            if (value != null) {
              ref
                  .read(downloadSettingsProvider.notifier)
                  .setMaxConcurrentDownloads(value);
            }
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(5, (index) {
              final value = index + 1;
              return RadioListTile<int>(
                title: Text(t.settings.concurrentDownloads.unit(n: value)),
                value: value,
              );
            }),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel),
          ),
        ],
      ),
    );
  }
}

/// 下载图片选项设置
class _DownloadImageOptionListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(downloadSettingsProvider);
    final option = settings.downloadImageOption;
    final optionText = switch (option) {
      DownloadImageOption.none => t.settings.downloadImage.off,
      DownloadImageOption.coverOnly => t.settings.downloadImage.coverOnly,
      DownloadImageOption.coverAndAvatar =>
        t.settings.downloadImage.coverAndAvatar,
    };

    return ListTile(
      leading: const Icon(Icons.image_outlined),
      title: Text(t.settings.downloadImage.title),
      subtitle: Text(optionText),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showImageOptionDialog(context, ref, option),
    );
  }

  void _showImageOptionDialog(
      BuildContext context, WidgetRef ref, DownloadImageOption current) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settings.downloadImage.title),
        content: RadioGroup<DownloadImageOption>(
          groupValue: current,
          onChanged: (value) {
            if (value != null) {
              ref
                  .read(downloadSettingsProvider.notifier)
                  .setDownloadImageOption(value);
            }
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<DownloadImageOption>(
                title: Text(t.settings.downloadImage.off),
                subtitle: Text(t.settings.downloadImage.offDescription),
                value: DownloadImageOption.none,
              ),
              RadioListTile<DownloadImageOption>(
                title: Text(t.settings.downloadImage.coverOnly),
                subtitle: Text(t.settings.downloadImage.coverOnlyDescription),
                value: DownloadImageOption.coverOnly,
              ),
              RadioListTile<DownloadImageOption>(
                title: Text(t.settings.downloadImage.coverAndAvatar),
                subtitle:
                    Text(t.settings.downloadImage.coverAndAvatarDescription),
                value: DownloadImageOption.coverAndAvatar,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.general.cancel),
          ),
        ],
      ),
    );
  }
}
