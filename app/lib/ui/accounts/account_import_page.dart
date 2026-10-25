import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/library/import_progress.dart';
import 'package:fmp/library/playlist_importer.dart';
import 'package:fmp/library/playlist_refresher.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/library/playlist_cover.dart';
import 'package:fmp/ui/library/playlist_detail_page.dart';
import 'package:fmp/ui/theme/app_layout.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// 帳號歌單匯入裡每一張的狀態。
enum ImportRowStatus { waiting, importing, done, failed, cancelled }

/// 帳號匯入的一列：一張要匯入的帳號歌單與它的進度。
@immutable
final class AccountImportRow {
  const AccountImportRow({
    required this.playlist,
    this.status = ImportRowStatus.waiting,
    this.progress,
    this.libraryId,
    this.failure,
  });

  final LibraryPlaylist playlist;
  final ImportRowStatus status;
  final ImportProgress? progress;

  /// 已經在音樂庫裡的那張歌單（完成，或取消時已寫過頁）；點了可以開詳情。
  final int? libraryId;

  /// 失敗的原因（已經是給使用者看的字）。
  final String? failure;

  AccountImportRow copyWith({
    ImportRowStatus? status,
    ImportProgress? progress,
    int? libraryId,
    String? failure,
  }) => AccountImportRow(
    playlist: playlist,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    libraryId: libraryId ?? this.libraryId,
    failure: failure ?? this.failure,
  );
}

/// 一次帳號匯入（ADR 0035 §決定 11、design §8）：逐張經 [PlaylistImporter.importPlaylistId]，
/// 每張的進度與狀態都在 [rows]。取消（[cancel]）讓目前這張停在已寫入的頁，其餘不再開始。
///
/// 不碰 `ref`：要用的東西由建構子給，頁面離開後仍能跑完（頁面在匯入期間不能離開，見
/// [AccountImportPage]）。
final class AccountImportRun extends ChangeNotifier {
  AccountImportRun({
    required this.pluginId,
    required List<LibraryPlaylist> playlists,
    required this.importer,
    required this.log,
    required this.translations,
    required this.failureReason,
  }) : _rows = [
         for (final playlist in playlists) AccountImportRow(playlist: playlist),
       ];

  final String pluginId;
  final PlaylistImporter importer;
  final Log log;
  final Translations translations;

  /// 把失敗轉成給使用者看的原因（離線時是離線的說法）。
  final String Function(AppError error) failureReason;

  List<AccountImportRow> _rows;
  final _cancel = ImportCancel();
  var _started = false;

  var _finished = false;

  List<AccountImportRow> get rows => _rows;

  bool get finished => _finished;

  bool get cancelRequested => _cancel.isCancelled;

  /// 已經處理完（完成、失敗或取消）的張數。
  int get settledCount => _rows
      .where(
        (row) =>
            row.status != ImportRowStatus.waiting &&
            row.status != ImportRowStatus.importing,
      )
      .length;

  int get importedCount =>
      _rows.where((row) => row.status == ImportRowStatus.done).length;

  int get failedCount =>
      _rows.where((row) => row.status == ImportRowStatus.failed).length;

  /// 失敗的列（`playlistId` → 原因）；帳號歌單頁用它在列上寫原因。
  Map<String, String> get failures => {
    for (final row in _rows)
      if (row.status == ImportRowStatus.failed && row.failure != null)
        row.playlist.playlistId: row.failure!,
  };

  /// 成功匯入的帳號歌單 id。
  Set<String> get importedIds => {
    for (final row in _rows)
      if (row.status == ImportRowStatus.done) row.playlist.playlistId,
  };

  void cancel() {
    if (_finished || _cancel.isCancelled) return;
    _cancel.cancel();
    notifyListeners();
  }

  void _update(int index, AccountImportRow row) {
    _rows = [..._rows]..[index] = row;
    notifyListeners();
  }

  /// 開始匯入；只有第一次呼叫有作用。
  Future<void> start() async {
    if (_started) return;
    _started = true;
    for (var index = 0; index < _rows.length; index++) {
      if (_cancel.isCancelled) {
        _update(
          index,
          _rows[index].copyWith(status: ImportRowStatus.cancelled),
        );
        continue;
      }
      await _importOne(index);
    }
    _finished = true;
    // 結果顯示在頁面頂端的狀態列（[AccountImportPage]），不跳提示：提示會蓋住底部的「完成」。
    notifyListeners();
  }

  Future<void> _importOne(int index) async {
    final playlist = _rows[index].playlist;
    _update(index, _rows[index].copyWith(status: ImportRowStatus.importing));
    try {
      final result = await importer.importPlaylistId(
        pluginId,
        playlist.playlistId,
        writable: playlist.writable,
        expectedTotal: playlist.trackCount,
        cancel: _cancel,
        onProgress: (progress) =>
            _update(index, _rows[index].copyWith(progress: progress)),
      );
      switch (result) {
        case ImportedPlaylist(:final playlistId):
          _update(
            index,
            _rows[index].copyWith(
              status: ImportRowStatus.done,
              libraryId: playlistId,
            ),
          );
        case ImportCancelled(:final playlistId):
          _update(
            index,
            _rows[index].copyWith(
              status: ImportRowStatus.cancelled,
              libraryId: playlistId,
            ),
          );
        default:
          // 僅元資料來源（沒有 resolveStream）：交給匯入預覽，這裡什麼都沒寫。
          _update(
            index,
            _rows[index].copyWith(
              status: ImportRowStatus.failed,
              failure: translations.accounts.playlistUnsupported,
            ),
          );
      }
    } on Object catch (thrown, stackTrace) {
      final error = AppError.wrap(thrown, stackTrace, pluginId: pluginId);
      log.report(
        'Failed to import an account playlist',
        error,
        tag: libraryLogTag,
      );
      _update(
        index,
        _rows[index].copyWith(
          status: ImportRowStatus.failed,
          failure: translations.accounts.playlistImportFailed(
            reason: failureReason(error),
          ),
        ),
      );
    }
  }
}

/// 在 [context] 所在的 Navigator 開帳號匯入頁並開始匯入 [run]；頁面關閉（完成後）才回來。
Future<void> openAccountImport(BuildContext context, AccountImportRun run) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        // 自己的 Material：理由見 `AppShell` 的根頁。
        builder: (_) => Material(
          type: MaterialType.transparency,
          child: AccountImportPage(run: run),
        ),
      ),
    );

/// 帳號匯入的全頁進度（ADR 0035 §決定 11、L-01 B）：頂端「歌單 n／m」，每張一列（名稱、
/// 「已匯入 n／M 首」、狀態），底部「取消」；跑完換成「完成」，列可以點開歌單詳情。
///
/// 匯入進行中不能離開（返回鍵、Esc 都不作用），只能取消。
class AccountImportPage extends ConsumerStatefulWidget {
  const AccountImportPage({super.key, required this.run});

  final AccountImportRun run;

  @override
  ConsumerState<AccountImportPage> createState() => _AccountImportPageState();
}

class _AccountImportPageState extends ConsumerState<AccountImportPage> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.run.start());
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final a = t.accounts;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final run = widget.run;
    return ListenableBuilder(
      listenable: run,
      builder: (context, _) {
        final total = run.rows.length;
        return PopScope(
          canPop: run.finished,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  spacing.x4,
                  spacing.x4,
                  spacing.x4,
                  spacing.x2,
                ),
                child: Semantics(
                  header: true,
                  child: Text(
                    a.importPageTitle,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.x4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 進度念給螢幕閱讀器。
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _statusText(a, run, total),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    SizedBox(height: spacing.x1),
                    LinearProgressIndicator(
                      value: total == 0 ? 1 : run.settledCount / total,
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing.x2),
              Expanded(
                child: ListView.builder(
                  itemCount: total,
                  itemBuilder: (context, index) => _ImportRow(
                    row: run.rows[index],
                    onOpen: run.finished && run.rows[index].libraryId != null
                        ? () => unawaited(
                            openPlaylist(context, run.rows[index].libraryId!),
                          )
                        : null,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(spacing.x4),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: run.finished
                      ? FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(a.importFinish),
                        )
                      : OutlinedButton(
                          onPressed: run.cancelRequested ? null : run.cancel,
                          child: Text(a.importCancel),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 頂端狀態列：進行中「歌單 n／m」，跑完換成結果（取消、全部成功、有失敗）。
String _statusText(
  Translations$accounts$zh_TW a,
  AccountImportRun run,
  int total,
) {
  if (!run.finished) {
    return a.importOverall(done: run.settledCount, total: total);
  }
  if (run.cancelRequested) return a.importCancelled(count: run.importedCount);
  if (run.failedCount == 0) return a.importedCount(count: run.importedCount);
  return a.importedWithFailures(
    count: run.importedCount,
    failed: run.failedCount,
  );
}

class _ImportRow extends ConsumerWidget {
  const _ImportRow({required this.row, required this.onOpen});

  final AccountImportRow row;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(translationsProvider).accounts;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spacing = AppTokens.of(context).spacing;
    final playlist = row.playlist;
    final progress = row.progress;
    final total = progress?.displayTotal ?? playlist.trackCount;
    final countText = progress == null
        ? null
        : total == null || total < progress.count
        ? a.itemProgress(count: progress.count)
        : a.itemProgressOf(count: progress.count, total: total);
    final statusText = switch (row.status) {
      ImportRowStatus.waiting => a.itemWaiting,
      ImportRowStatus.importing => countText ?? a.itemImporting,
      ImportRowStatus.done => countText ?? a.itemDone,
      ImportRowStatus.failed => row.failure ?? '',
      ImportRowStatus.cancelled =>
        countText == null ? a.itemCancelled : '${a.itemCancelled} · $countText',
    };
    final failed = row.status == ImportRowStatus.failed;
    final value =
        row.status == ImportRowStatus.importing &&
            progress != null &&
            progress.displayTotal != null
        ? progress.count / progress.displayTotal!
        : null;
    return ListTile(
      onTap: onOpen,
      leading: PlaylistCover(
        artwork: [
          for (final image in playlist.artwork)
            TrackArtwork(url: image.url, width: image.width),
        ],
        firstTrack: null,
        size: AppLayout.artworkThumbnail,
      ),
      title: Text(playlist.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            statusText,
            style: failed
                ? theme.textTheme.bodySmall?.copyWith(color: scheme.error)
                : null,
          ),
          if (row.status == ImportRowStatus.importing) ...[
            SizedBox(height: spacing.x1),
            LinearProgressIndicator(value: value),
          ],
        ],
      ),
      trailing: switch (row.status) {
        ImportRowStatus.done => Icon(
          Icons.check_circle_outline,
          color: scheme.primary,
          semanticLabel: a.itemDone,
        ),
        ImportRowStatus.failed => Icon(
          Icons.error_outline,
          color: scheme.error,
        ),
        ImportRowStatus.cancelled => Icon(
          Icons.block,
          color: scheme.onSurfaceVariant,
          semanticLabel: a.itemCancelled,
        ),
        ImportRowStatus.importing => const SizedBox.square(
          dimension: AppLayout.buttonSpinner,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        ImportRowStatus.waiting => Icon(
          Icons.schedule,
          color: scheme.onSurfaceVariant,
          semanticLabel: a.itemWaiting,
        ),
      },
    );
  }
}
