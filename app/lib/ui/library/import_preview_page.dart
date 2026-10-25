import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/network/network_status.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/library/external_import.dart';
import 'package:fmp/ui/empty_state/empty_state.dart';
import 'package:fmp/ui/errors/error_message.dart';
import 'package:fmp/ui/format/duration_text.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/layout/window_class.dart';
import 'package:fmp/ui/library/playlist_detail_page.dart';
import 'package:fmp/ui/plugins/plugin_name.dart';
import 'package:fmp/ui/theme/app_tokens.dart';
import 'package:fmp/ui/toast/toaster.dart';
import 'package:fmp/ui/shell/page_app_bar.dart';

/// 在目前目的地的巢狀導覽裡開匯入預覽頁（音樂庫的「匯入」）。
Future<void> openImportPreview(
  BuildContext context, {
  required String pluginId,
  required String playlistId,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    // 自己的 Material 與捲動觀察者：理由見 [PageSurface]。
    builder: (_) => PageSurface(
      child: ImportPreviewPage(pluginId: pluginId, playlistId: playlistId),
    ),
  ),
);

/// 匯入預覽（M4 design §10.9，ADR 0019 §決定 5）：一次 [ExternalImport]，頁面關掉就丟掉。
///
/// - 標頭：遠端標題、來源，下面一塊依進度換：讀取中「讀取中 n 首」；讀不到是錯誤與「重試」；讀完
///   是首數、「每首會在 n 個音源搜尋」、沿用幾首、目標音源的 chip 與「開始匹配」；匹配中與完成是
///   「已匹配 n／總數」與 chip（臨時改目標並重搜未手動改選的，不寫設定）。`truncated` 多一行提示。
/// - 每首一列：原標題、歌手、時長｜選定的候選（標題、上傳者、音源、時長、分數）或狀態；寬版兩欄
///   並排，窄版上下。點一列展開：前 5 名（換選）、自訂關鍵字「重搜」、「排除」。
/// - 底部「建立歌單」：每一首都有結果、至少一首會加入才可按，旁邊寫幾首不會加入。建立後換成新
///   歌單的詳情。
/// - 離開（返回鍵、Esc、標頭的返回、再點導覽項）前確認；讀不到、已建立時不問。
class ImportPreviewPage extends ConsumerStatefulWidget {
  const ImportPreviewPage({
    super.key,
    required this.pluginId,
    required this.playlistId,
  });

  final String pluginId;
  final String playlistId;

  @override
  ConsumerState<ImportPreviewPage> createState() => _ImportPreviewPageState();
}

class _ImportPreviewPageState extends ConsumerState<ImportPreviewPage> {
  ExternalImport? _job;
  AppError? _openError;

  /// 展開的列（依位置；同一首出現兩次時各自展開）。
  final _expanded = <int>{};
  final _keywords = <int, TextEditingController>{};

  /// 確認離開或建立好了：之後的 pop 不再問。
  var _leaving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final job = await ref
          .read(externalImportsProvider)
          .open(widget.pluginId, widget.playlistId);
      if (!mounted) {
        job.dispose();
        return;
      }
      job.addListener(_changed);
      setState(() => _job = job);
      await job.read();
    } on Object catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => _openError = AppError.wrap(error, stackTrace));
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _job?.dispose();
    for (final controller in _keywords.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 離開要不要攔：建立中一律攔（不問）；使用者做過會丟掉的事（開始匹配、改選、排除、重搜）才問。
  /// 讀取中、讀不到、讀完還沒開始（含全部沿用而直接完成）都直接離開。
  bool _guarded(ExternalImport? job) {
    if (_leaving || job == null) return false;
    return job.creating || job.touched;
  }

  Future<void> _confirmLeave() async {
    final t = ref.read(translationsProvider).importPreview;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.leaveTitle),
        content: Text(t.leaveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.leaveKeep),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.leaveConfirm),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    setState(() => _leaving = true);
    Navigator.of(context).pop();
  }

  /// 「開始匹配」：要搜的次數超過 [largeSearchThreshold] 時先確認。
  Future<void> _start(ExternalImport job) async {
    final searches = job.plannedSearches;
    if (searches > largeSearchThreshold) {
      final t = ref.read(translationsProvider).importPreview;
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.largeTitle(count: searches)),
          // 只剩一個目標時沒有「減少目標」可建議。
          content: Text(
            job.targets.length > 1 ? t.largeBody : t.largeBodyOneTarget,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t.largeCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t.largeStart),
            ),
          ],
        ),
      );
      // 確認框開著時頁面可能被關掉或階段已變。
      if (go != true || !mounted || job.phase != ExternalImportPhase.ready) {
        return;
      }
    }
    job.start();
  }

  void _toggle(int row, ImportSong song) {
    setState(() {
      if (_expanded.remove(row)) {
        _keywords.remove(row)?.dispose();
      } else {
        _expanded.add(row);
        _keywords[row] = TextEditingController(text: song.defaultKeyword);
      }
    });
  }

  Future<void> _research(ExternalImport job, int row, ImportSong song) async {
    final keyword = _keywords[row]?.text.trim();
    await job.research(
      song,
      keyword: keyword == song.defaultKeyword ? null : keyword,
    );
  }

  void _setTargets(ExternalImport job, String pluginId, bool selected) {
    final next = {...job.targets};
    if (selected) {
      next.add(pluginId);
    } else {
      next.remove(pluginId);
    }
    job.setTargets(next);
  }

  Future<void> _create(ExternalImport job) async {
    final t = ref.read(translationsProvider).importPreview;
    final toaster = ref.read(toasterProvider);
    try {
      final id = await job.confirm();
      if (!mounted) return;
      setState(() => _leaving = true);
      toaster.success(t.created);
      unawaited(openPlaylist(context, id, replace: true));
    } on AppError catch (error) {
      toaster.error(
        error,
        operation: 'Failed to create a playlist from an import',
        tag: matchingLogTag,
        sentence: (reason) => t.createFailed(reason: reason),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    final translations = ref.watch(translationsProvider);
    final t = translations.importPreview;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final canGoBack = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    final source =
        ref.watch(pluginNameProvider(widget.pluginId)) ?? widget.pluginId;
    final header = Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.x4,
        spacing.x4,
        spacing.x4,
        spacing.x2,
      ),
      child: Row(
        children: [
          if (canGoBack)
            IconButton(
              tooltip: t.cancel,
              icon: const BackButtonIcon(),
              onPressed: () => unawaited(Navigator.of(context).maybePop()),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    job?.title ?? t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                Text(
                  t.from(source: source),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    // 外殼的返回鍵、Esc 與「再點導覽項」都經這一層（`AppShell` 停在不放行的頁並 `maybePop`）。
    return PopScope(
      canPop: !_guarded(job),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // 建立中：直接攔下，不開確認框（寫入完成後頁面自己換成歌單詳情）。
        if (job?.creating ?? false) return;
        unawaited(_confirmLeave());
      },
      child: switch ((job, _openError)) {
        (final job?, _) => _body(context, job, header),
        (null, final error?) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(child: _ReadFailed(error: error)),
          ],
        ),
        (null, null) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const Expanded(child: Center(child: CircularProgressIndicator())),
          ],
        ),
      },
    );
  }

  Widget _body(BuildContext context, ExternalImport job, Widget header) {
    final t = ref.watch(translationsProvider).importPreview;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    switch (job.phase) {
      case ExternalImportPhase.reading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Padding(
              padding: EdgeInsets.all(spacing.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      t.reading(count: job.readCount),
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  SizedBox(height: spacing.x2),
                  const LinearProgressIndicator(),
                ],
              ),
            ),
          ],
        );
      case ExternalImportPhase.readFailed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(
              child: _ReadFailed(
                error: job.readError!,
                onRetry: () => unawaited(job.read()),
              ),
            ),
          ],
        );
      case ExternalImportPhase.ready ||
          ExternalImportPhase.matching ||
          ExternalImportPhase.done:
        final wide = switch (WindowClass.of(context)) {
          WindowClass.compact || WindowClass.medium => false,
          _ => true,
        };
        // 標頭（標題、首數、目標 chip、「開始匹配」）跟著清單一起捲走：compact 的高度放不下固定的標頭加
        // 底部列與播放列（實機只剩三列）。清單是 `SliverList.builder`，一千首也只建看得到的。進度在固定的
        // 底部列，捲走標頭也看得到。
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: header),
                  SliverToBoxAdapter(
                    child: _Summary(
                      job: job,
                      onTarget: _setTargets,
                      onStart: () => unawaited(_start(job)),
                    ),
                  ),
                  const SliverToBoxAdapter(child: Divider(height: 0)),
                  SliverList.builder(
                    itemCount: job.rows.length,
                    itemBuilder: (context, index) {
                      final song = job.rows[index];
                      final expanded = _expanded.contains(index);
                      return Column(
                        key: ValueKey(index),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SongRow(
                            song: song,
                            wide: wide,
                            expanded: expanded,
                            onTap: () => _toggle(index, song),
                          ),
                          if (expanded)
                            _SongPanel(
                              job: job,
                              song: song,
                              keyword: _keywords[index]!,
                              onResearch: () =>
                                  unawaited(_research(job, index, song)),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 0),
            _CreateBar(job: job, onCreate: () => unawaited(_create(job))),
          ],
        );
    }
  }
}

/// 讀不到歌單（或開不了這次匯入）：原因與「重試」。
class _ReadFailed extends ConsumerWidget {
  const _ReadFailed({required this.error, this.onRetry});

  final AppError error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translations = ref.watch(translationsProvider);
    final t = translations.importPreview;
    final pluginId = error.pluginId;
    final reason = switch (ref.watch(networkStatusProvider)) {
      NetworkStatus.noInterface => translations.offline.noInterface,
      NetworkStatus.unreachable => translations.offline.unreachable,
      NetworkStatus.online => errorMessage(
        translations,
        error,
        sourceName: pluginId == null
            ? null
            : ref.watch(pluginNameProvider(pluginId)) ?? pluginId,
      ),
    };
    final onRetry = this.onRetry;
    return EmptyState(
      icon: Icons.error_outline,
      title: t.readFailed(reason: reason),
      action: onRetry == null
          ? null
          : FilledButton.tonal(onPressed: onRetry, child: Text(t.retry)),
    );
  }
}

/// 列表上方的一塊：首數與搜尋數或進度、`truncated` 提示、目標音源的 chip、「開始匹配」。
class _Summary extends ConsumerWidget {
  const _Summary({
    required this.job,
    required this.onTarget,
    required this.onStart,
  });

  final ExternalImport job;
  final VoidCallback onStart;
  final void Function(ExternalImport job, String pluginId, bool selected)
  onTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).importPreview;
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    final spacing = tokens.spacing;
    final hint = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final ready = job.phase == ExternalImportPhase.ready;
    final targets = job.targets;
    final total = job.rows.length;
    final songs = total == 1 ? t.songsOne : t.songs(count: total);
    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.x4, 0, spacing.x4, spacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 進度（「已匹配 n／總數」）在固定的底部列。
          Text(
            [
              songs,
              if (targets.isNotEmpty)
                targets.length == 1
                    ? t.searchesEachOne
                    : t.searchesEach(count: targets.length),
              if (job.reusedCount > 0) t.reused(count: job.reusedCount),
            ].join(' · '),
            style: theme.textTheme.bodyLarge,
          ),
          if (job.truncated) ...[
            SizedBox(height: spacing.x2),
            Row(
              children: [
                Icon(Icons.info_outline, color: tokens.warning.color),
                SizedBox(width: spacing.x2),
                Expanded(
                  child: Text(t.truncated, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ],
          SizedBox(height: spacing.x3),
          if (job.available.isEmpty)
            Text(t.noTargets, style: hint)
          else ...[
            Text(t.targets, style: theme.textTheme.titleSmall),
            SizedBox(height: spacing.x1),
            Wrap(
              spacing: spacing.x2,
              runSpacing: spacing.x2,
              children: [
                for (final plugin in job.available)
                  _TargetChip(
                    pluginId: plugin.manifest.id,
                    selected: targets.contains(plugin.manifest.id),
                    // 開始之後至少留一個（沒有目標就沒辦法重搜）。
                    locked:
                        !ready &&
                        targets.length == 1 &&
                        targets.contains(plugin.manifest.id),
                    onSelected: (selected) =>
                        onTarget(job, plugin.manifest.id, selected),
                  ),
              ],
            ),
          ],
          if (ready) ...[
            SizedBox(height: spacing.x3),
            Row(
              children: [
                FilledButton(
                  onPressed: targets.isEmpty ? null : onStart,
                  child: Text(t.start),
                ),
                if (targets.isEmpty && job.available.isNotEmpty) ...[
                  SizedBox(width: spacing.x3),
                  Expanded(child: Text(t.pickTarget, style: hint)),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TargetChip extends ConsumerWidget {
  const _TargetChip({
    required this.pluginId,
    required this.selected,
    required this.locked,
    required this.onSelected,
  });

  final String pluginId;
  final bool selected;
  final bool locked;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).importPreview;
    final chip = FilterChip(
      label: Text(ref.watch(pluginNameProvider(pluginId)) ?? pluginId),
      selected: selected,
      onSelected: locked ? null : onSelected,
    );
    return locked ? Tooltip(message: t.lastTarget, child: chip) : chip;
  }
}

/// 一首：原曲｜匹配結果。點一下展開或收起。
class _SongRow extends ConsumerWidget {
  const _SongRow({
    required this.song,
    required this.wide,
    required this.expanded,
    required this.onTap,
  });

  final ImportSong song;
  final bool wide;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).importPreview;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final original = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge,
        ),
        Text(
          [
            ?song.artists,
            if (song.duration case final duration?) formatDuration(duration),
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    final result = _MatchSummary(song: song);
    return ListTile(
      onTap: onTap,
      title: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: original),
                SizedBox(width: spacing.x4),
                Expanded(child: result),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                original,
                SizedBox(height: spacing.x1),
                result,
              ],
            ),
      trailing: Icon(
        expanded ? Icons.expand_less : Icons.expand_more,
        semanticLabel: expanded ? t.hideCandidates : t.showCandidates,
      ),
    );
  }
}

/// 一首的匹配結果：選定的候選（兩行），或狀態。
class _MatchSummary extends ConsumerWidget {
  const _MatchSummary({required this.song});

  final ImportSong song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).importPreview;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    Widget status(IconData icon, String text, Color color) => Row(
      children: [
        Icon(icon, color: color),
        SizedBox(width: spacing.x2),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
    if (song.excluded) {
      return status(Icons.block, t.excluded, colors.onSurfaceVariant);
    }
    final reused = song.match is MatchReused;
    final (track, score) = switch (song.match) {
      MatchFound(:final selected?) => (
        selected.track,
        selected.score.total as double?,
      ),
      MatchReused(:final selected?, :final score) => (selected, score),
      _ => (null, null),
    };
    if (track != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, color: colors.primary),
          SizedBox(width: spacing.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  _detail(
                    ref,
                    ref.watch(translationsProvider),
                    track,
                    score,
                    reused: reused,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              ],
            ),
          ),
        ],
      );
    }
    return switch (song.match) {
      MatchPending() => status(
        Icons.schedule,
        t.pending,
        colors.onSurfaceVariant,
      ),
      MatchSearching() => Row(
        children: [
          SizedBox.square(
            dimension: spacing.x4,
            child: const CircularProgressIndicator(),
          ),
          SizedBox(width: spacing.x2),
          Text(t.searching, style: muted),
        ],
      ),
      MatchSearchFailed() => status(
        Icons.error_outline,
        t.searchFailed,
        colors.error,
      ),
      MatchFound() || MatchReused() => status(
        Icons.help_outline,
        reused ? '${t.unmatched} · ${t.reusedTag}' : t.unmatched,
        colors.error,
      ),
    };
  }
}

/// 候選的第二行：上傳者 · 音源 · 時長 · 分數（沿用的另標）。
String _detail(
  WidgetRef ref,
  Translations translations,
  TrackInfo track,
  double? score, {
  bool reused = false,
}) {
  final t = translations.importPreview;
  final parts = [
    ?track.uploader,
    ref.watch(pluginNameProvider(track.sourceTypeId)) ?? track.sourceTypeId,
    if (track.duration case final duration?) formatDuration(duration),
    if (score != null) t.score(percent: (score * 100).round()),
    if (reused) t.reusedTag,
  ];
  return parts.join(' · ');
}

/// 展開的一首：前 5 名（換選）、自訂關鍵字重搜、排除。
class _SongPanel extends ConsumerWidget {
  const _SongPanel({
    required this.job,
    required this.song,
    required this.keyword,
    required this.onResearch,
  });

  final ExternalImport job;
  final ImportSong song;
  final TextEditingController keyword;
  final VoidCallback onResearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translations = ref.watch(translationsProvider);
    final t = translations.importPreview;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final colors = theme.colorScheme;
    final match = song.match;
    final searching = !match.settled;
    final canSearch = job.targets.isNotEmpty;
    // 自己的 Material：候選是 RadioListTile，水波與底色要畫在這一層上（畫在外層會被底色蓋住）。
    return Material(
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.x4,
          spacing.x2,
          spacing.x4,
          spacing.x3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            switch (match) {
              MatchFound(:final candidates) when candidates.isEmpty => Text(
                t.noCandidates,
                style: theme.textTheme.bodyMedium,
              ),
              MatchFound(:final candidates, :final selected) =>
                RadioGroup<ImportCandidate>(
                  groupValue: song.excluded ? null : selected,
                  onChanged: (candidate) {
                    if (candidate != null) job.select(song, candidate);
                  },
                  child: Column(
                    children: [
                      for (final candidate in candidates)
                        RadioListTile<ImportCandidate>(
                          value: candidate,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            candidate.track.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            _detail(
                              ref,
                              translations,
                              candidate.track,
                              candidate.score.total,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              MatchReused() => Text(
                t.reusedHint,
                style: theme.textTheme.bodyMedium,
              ),
              MatchSearchFailed(:final error) => Text(
                errorMessage(
                  translations,
                  error,
                  sourceName: switch (error.pluginId) {
                    final id? => ref.watch(pluginNameProvider(id)) ?? id,
                    null => null,
                  },
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.error,
                ),
              ),
              MatchPending() || MatchSearching() => const SizedBox.shrink(),
            },
            SizedBox(height: spacing.x2),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: keyword,
                    enabled: !searching,
                    textInputAction: TextInputAction.search,
                    onSubmitted: searching || !canSearch
                        ? null
                        : (_) => onResearch(),
                    decoration: InputDecoration(labelText: t.keyword),
                  ),
                ),
                SizedBox(width: spacing.x2),
                FilledButton.tonal(
                  onPressed: searching || !canSearch ? null : onResearch,
                  child: Text(t.research),
                ),
              ],
            ),
            SizedBox(height: spacing.x2),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () =>
                    job.setExcluded(song, excluded: !song.excluded),
                icon: Icon(song.excluded ? Icons.undo : Icons.block),
                label: Text(song.excluded ? t.include : t.exclude),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部（固定，不跟著捲）：開始之後的進度「已匹配 n／總數」（匹配中另有進度條）、完成後幾首不會加入、
/// 「建立歌單」。
class _CreateBar extends ConsumerWidget {
  const _CreateBar({required this.job, required this.onCreate});

  final ExternalImport job;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).importPreview;
    final theme = Theme.of(context);
    final spacing = AppTokens.of(context).spacing;
    final phase = job.phase;
    final started = phase != ExternalImportPhase.ready;
    final total = job.rows.length;
    final skipped = total - job.chosenCount;
    // 匹配中：目前正在搜的那一首（ADR 0035 §決定 11 的同一條進度資訊）。
    final currentSong = phase == ExternalImportPhase.matching
        ? job.rows.where((row) => row.match is MatchSearching).firstOrNull
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (phase == ExternalImportPhase.matching)
          LinearProgressIndicator(
            value: total == 0 ? 1 : job.settledCount / total,
          ),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.x4,
            vertical: spacing.x3,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (started)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          t.progress(done: job.settledCount, total: total),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    if (currentSong != null)
                      Text(
                        t.currentSong(title: currentSong.title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (phase == ExternalImportPhase.done && skipped > 0)
                      Text(
                        skipped == 1 ? t.skippedOne : t.skipped(count: skipped),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: spacing.x3),
              FilledButton(
                onPressed: job.canCreate ? onCreate : null,
                child: Text(t.create),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
