part of '../settings_page.dart';

/// 导出数据
class _ExportDataListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.upload_outlined),
      title: Text(t.settings.backup.export.title),
      subtitle: Text(t.settings.backup.export.subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _exportData(context, ref),
    );
  }

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    try {
      final backupService = ref.read(backupServiceProvider);
      final path = await backupService.exportData();

      if (path != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.settings.backup.export.success(path: path)),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.settings.backup.export.failed(error: e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

/// 导入数据
class _ImportDataListTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.download_outlined),
      title: Text(t.settings.backup.import.title),
      subtitle: Text(t.settings.backup.import.subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _importData(context, ref),
    );
  }

  Future<void> _importData(BuildContext context, WidgetRef ref) async {
    try {
      final backupService = ref.read(backupServiceProvider);
      final backupData = await backupService.pickAndParseBackupFile();

      if (backupData == null) return;

      if (!context.mounted) return;

      // 显示导入预览对话框
      final result = await showDialog<ImportResult>(
        context: context,
        builder: (context) => _ImportPreviewDialog(
          backupData: backupData,
          backupService: backupService,
        ),
      );

      if (result != null && context.mounted) {
        // 显示导入结果
        showDialog(
          context: context,
          builder: (context) => _ImportResultDialog(result: result),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.settings.backup.import.failed(error: e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

/// 导入预览对话框
class _ImportPreviewDialog extends ConsumerStatefulWidget {
  final BackupData backupData;
  final BackupService backupService;

  const _ImportPreviewDialog({
    required this.backupData,
    required this.backupService,
  });

  @override
  ConsumerState<_ImportPreviewDialog> createState() =>
      _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends ConsumerState<_ImportPreviewDialog> {
  bool _importPlaylists = true;
  bool _importPlayHistory = true;
  bool _importSearchHistory = true;
  bool _importRadioStations = true;
  bool _importLyricsMatches = true;
  bool _importSettings = true;
  bool _isImporting = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.backupData;
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(t.settings.backup.import.preview),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.settings.backup.import.previewSubtitle,
                style: TextStyle(color: colorScheme.outline, fontSize: 12),
              ),
              const SizedBox(height: 16),

              // 备份信息
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadius.borderRadiusMd,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow(
                      t.settings.backup.exportedAt,
                      _formatDateTime(data.exportedAt),
                    ),
                    _buildInfoRow(
                      t.settings.backup.appVersion,
                      data.appVersion,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 选择要导入的数据
              if (data.playlists.isNotEmpty)
                _buildCheckableRow(
                  Icons.queue_music,
                  t.settings.backup.import.playlists,
                  data.playlists.length,
                  _importPlaylists,
                  (value) => setState(() => _importPlaylists = value ?? true),
                ),
              if (data.playHistory.isNotEmpty)
                _buildCheckableRow(
                  Icons.history,
                  t.settings.backup.import.playHistory,
                  data.playHistory.length,
                  _importPlayHistory,
                  (value) => setState(() => _importPlayHistory = value ?? true),
                ),
              if (data.searchHistory.isNotEmpty)
                _buildCheckableRow(
                  Icons.search,
                  t.settings.backup.import.searchHistory,
                  data.searchHistory.length,
                  _importSearchHistory,
                  (value) =>
                      setState(() => _importSearchHistory = value ?? true),
                ),
              if (data.radioStations.isNotEmpty)
                _buildCheckableRow(
                  Icons.radio,
                  t.settings.backup.import.radioStations,
                  data.radioStations.length,
                  _importRadioStations,
                  (value) =>
                      setState(() => _importRadioStations = value ?? true),
                ),
              if (data.lyricsMatches.isNotEmpty)
                _buildCheckableRow(
                  Icons.lyrics,
                  t.settings.backup.import.lyricsMatches,
                  data.lyricsMatches.length,
                  _importLyricsMatches,
                  (value) =>
                      setState(() => _importLyricsMatches = value ?? true),
                ),
              if (data.settings != null)
                _buildCheckableRow(
                  Icons.settings,
                  t.settings.backup.import.importSettings,
                  null,
                  _importSettings,
                  (value) => setState(() => _importSettings = value ?? true),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.pop(context),
          child: Text(t.general.cancel),
        ),
        FilledButton(
          onPressed: _isImporting ? null : _doImport,
          child: _isImporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t.settings.backup.import.confirm),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(value, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildCheckableRow(
    IconData icon,
    String label,
    int? count,
    bool value,
    ValueChanged<bool?> onChanged,
  ) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      secondary: Icon(icon, size: 20),
      title: Row(
        children: [
          Expanded(child: Text(label)),
          if (count != null)
            Text(
              count.toString(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
        ],
      ),
      value: value,
      onChanged: _isImporting ? null : onChanged,
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _doImport() async {
    setState(() => _isImporting = true);

    try {
      final result = await widget.backupService.importData(
        widget.backupData,
        importPlaylists: _importPlaylists,
        importPlayHistory: _importPlayHistory,
        importSearchHistory: _importSearchHistory,
        importRadioStations: _importRadioStations,
        importLyricsMatches: _importLyricsMatches,
        importSettings: _importSettings,
      );

      // 按勾选分类刷新对应的 Provider
      if (_importPlaylists) {
        ref.read(libraryInvalidationCoordinatorProvider).playlistsChanged(
          const [],
          tracksChanged: false,
          coverChanged: false,
        );
      }

      if (_importSettings && result.settingsImported) {
        ref.invalidate(themeProvider);
        ref.invalidate(localeProvider);
        ref.invalidate(playbackSettingsProvider);
        ref.invalidate(downloadSettingsProvider);
        ref.invalidate(downloadPathProvider);
        ref.invalidate(audioSettingsProvider);
        ref.invalidate(lyricsDisplayModeProvider);
        ref.invalidate(lyricsWindowStyleProvider);
        if (Platform.isWindows) {
          ref.invalidate(hotkeyConfigProvider);
          ref.invalidate(minimizeToTrayProvider);
          ref.invalidate(globalHotkeysEnabledProvider);
          ref.invalidate(launchAtStartupProvider);
        }
      }

      if (mounted) {
        Navigator.pop(context, result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isImporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.settings.backup.import.failed(error: e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

/// 导入结果对话框
class _ImportResultDialog extends StatelessWidget {
  final ImportResult result;

  const _ImportResultDialog({required this.result});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            result.errors.isEmpty ? Icons.check_circle : Icons.warning,
            color: result.errors.isEmpty ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          Text(t.settings.backup.import.success),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildResultRow(
                t.settings.backup.import.result.playlistsImported(
                  imported: result.playlistsImported,
                  skipped: result.playlistsSkipped,
                ),
              ),
              _buildResultRow(
                t.settings.backup.import.result.tracksImported(
                  imported: result.tracksImported,
                  skipped: result.tracksSkipped,
                ),
              ),
              _buildResultRow(
                t.settings.backup.import.result.playHistoryImported(
                  imported: result.playHistoryImported,
                  skipped: result.playHistorySkipped,
                ),
              ),
              _buildResultRow(
                t.settings.backup.import.result.searchHistoryImported(
                  imported: result.searchHistoryImported,
                  skipped: result.searchHistorySkipped,
                ),
              ),
              _buildResultRow(
                t.settings.backup.import.result.radioStationsImported(
                  imported: result.radioStationsImported,
                  skipped: result.radioStationsSkipped,
                ),
              ),
              _buildResultRow(
                t.settings.backup.import.result.lyricsMatchesImported(
                  imported: result.lyricsMatchesImported,
                  skipped: result.lyricsMatchesSkipped,
                ),
              ),
              _buildResultRow(
                result.settingsImported
                    ? t.settings.backup.import.result.settingsImported
                    : t.settings.backup.import.result.settingsSkipped,
              ),
              if (result.errors.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  t.settings.backup.import.result.errors,
                  style: TextStyle(
                    color: colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: AppRadius.borderRadiusMd,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: result.errors
                        .take(5)
                        .map((e) => Text(
                              e,
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onErrorContainer,
                              ),
                            ))
                        .toList(),
                  ),
                ),
                if (result.errors.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '... ${result.errors.length - 5} more errors',
                      style:
                          TextStyle(fontSize: 12, color: colorScheme.outline),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.general.confirm),
        ),
      ],
    );
  }

  Widget _buildResultRow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(text, style: const TextStyle(fontSize: 13)),
    );
  }
}
