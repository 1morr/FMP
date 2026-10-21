import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/core/core_providers.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/core/logging/log.dart';
import 'package:fmp/core/matching/matching.dart';
import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/match_results_repository.dart';
import 'package:fmp/data/repositories/playlist_repository.dart';
import 'package:fmp/domain/track_info.dart';
import 'package:fmp/domain/track_key.dart';
import 'package:fmp/library/match_targets.dart';
import 'package:fmp/plugins/manifest/plugin_manifest.dart';
import 'package:fmp/plugins/plugin_registry.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

/// 外部匯入的 log tag（M4 design §13）。
const matchingLogTag = 'matching';

/// 每首保留的候選數：所有目標音源合併評分後的前 5 名（§17 第 7 條）。
const matchCandidateLimit = 5;

/// 一首的候選：目標音源的一首曲目與它的分數。
@immutable
final class ImportCandidate {
  const ImportCandidate({required this.track, required this.score});

  final TrackInfo track;
  final MatchScore score;
}

/// 一首外部歌曲現在的匹配狀態。
sealed class SongMatch {
  const SongMatch();

  /// 這一首已經有結果（搜過、失敗或沿用），不是還在等或正在搜。
  bool get settled => true;
}

/// 還沒搜。
final class MatchPending extends SongMatch {
  const MatchPending();

  @override
  bool get settled => false;
}

/// 正在搜。
final class MatchSearching extends SongMatch {
  const MatchSearching();

  @override
  bool get settled => false;
}

/// 搜過了：[candidates] 是合併後的前 5 名（由高到低）；[selected] 是選定的那一個，`null` 是
/// 匹配失敗（沒有候選，或第一名沒過門檻而使用者也還沒選）。
final class MatchFound extends SongMatch {
  const MatchFound({required this.candidates, this.selected});

  final List<ImportCandidate> candidates;
  final ImportCandidate? selected;
}

/// 每個目標音源的搜尋都失敗（「搜尋失敗」，可以重搜）。[error] 是第一個失敗的。
final class MatchSearchFailed extends SongMatch {
  const MatchSearchFailed(this.error);

  final AppError error;
}

/// 沿用 `match_results` 先前的結果，沒有搜尋：[selected] 是當時選定的曲目（空＝當時匹配失敗或
/// 排除）。候選沒有存，要換就重搜。
final class MatchReused extends SongMatch {
  const MatchReused({this.selected, this.score});

  final TrackInfo? selected;
  final double? score;
}

/// 匯入預覽的一首外部歌曲。來源歌單裡同一首（同一個外部 id）出現多次時共用一個：改一處兩處
/// 都跟著變，`match_results` 也只有一列。狀態只由 [ExternalImport] 改。
final class ImportSong {
  ImportSong._(this.track, this.originId);

  /// 插件給的外部歌曲（標題、歌手、時長）。
  final TrackSummary track;

  /// 外部 id：`match_results` 與 `track_origins` 的 `origin_id`。分 P 的歌（配對模式下的 B 站）
  /// 帶 cid，同曲目鍵的後兩段（`<sourceId>:<cid>`）。
  final String originId;

  SongMatch _match = const MatchPending();
  bool _excluded = false;
  bool _picked = false;
  bool _manual = false;
  int _generation = 0;

  String get title => track.title;
  String? get artists => track.uploader;
  Duration? get duration => track.duration;
  SongMatch get match => _match;

  /// 使用者排除了這一首：不進歌單，`match_results` 記成排除。
  bool get excluded => _excluded;

  /// 使用者自己選過候選（或沿用的結果是使用者選的）。
  bool get picked => _picked;

  /// 臨時改目標音源時不重搜這一首：使用者選過、排除過、以自訂關鍵字重搜過，或沿用的是使用者的選擇。
  bool get manual => _manual;

  /// 會進歌單的曲目；排除、匹配失敗、搜尋失敗、還沒搜完都是 `null`。
  TrackInfo? get chosen {
    if (_excluded) return null;
    return switch (_match) {
      MatchFound(:final selected?) => selected.track,
      MatchReused(:final selected?) => selected,
      _ => null,
    };
  }

  /// 預設的搜尋關鍵字：原標題＋空白＋第一位歌手（M4 design §8.4）。
  String get defaultKeyword =>
      [track.title.trim(), ?firstArtist(track.uploader)].join(' ');

  MatchQuery get _query => MatchQuery(
    title: track.title,
    artist: track.uploader,
    duration: track.duration,
  );
}

/// [ExternalImport] 現在在哪一步。
enum ExternalImportPhase {
  /// 正在讀來源歌單的頁（「讀取中 n 首」）。
  reading,

  /// 有一頁讀不到：停在錯誤與「重試」，不進匹配（§17 第 18 條）。
  readFailed,

  /// 讀完了，還沒開始匹配：顯示首數與「每首會在 n 個音源搜尋」。
  ready,

  /// 還有沒搜完的。
  matching,

  /// 每一首都有結果了：可以建立歌單。
  done,
}

final externalImportsProvider = Provider<ExternalImports>(ExternalImports.new);

/// 開一次外部匯入（[ExternalImport.read] 之前的準備：找插件、算這次的目標音源）。
final class ExternalImports {
  ExternalImports(this._ref);

  final Ref _ref;

  /// 為來源 [pluginId] 的歌單 [playlistId] 開一次匯入。來源插件不在清單上或沒宣告
  /// `importPlaylist` 是 [Unsupported]。
  ///
  /// 目標音源照設定（[matchTargetOptions]）；來源插件自己能播（配對模式，§17 第 19 條）時，這次的
  /// 預設另外不勾它。
  Future<ExternalImport> open(String pluginId, String playlistId) async {
    final plugins = await _ref.read(pluginRegistryProvider.future);
    final source = plugins[pluginId];
    if (source == null ||
        !source.manifest.capabilities.contains(
          PluginCapability.importPlaylist,
        )) {
      throw Unsupported(
        pluginId: pluginId,
        cause: StateError('The source cannot import a playlist'),
      );
    }
    final settings = await _ref
        .read(sourceSettingsRepositoryProvider)
        .watchMatchTargets()
        .first;
    final options = matchTargetOptions(plugins.values, settings);
    final pairing = source.manifest.capabilities.contains(
      PluginCapability.resolveStream,
    );
    return ExternalImport(
      source: source,
      playlistId: playlistId,
      available: [for (final option in options) option.plugin],
      targets: [
        for (final option in options)
          if (option.enabled && !(pairing && option.pluginId == pluginId))
            option.pluginId,
      ],
      playlists: _ref.read(playlistRepositoryProvider),
      results: _ref.read(matchResultsRepositoryProvider),
      log: _ref.read(logProvider),
    );
  }
}

/// 一次外部匯入（M4 design §8.4，ADR 0019 §決定 5）：讀完來源歌單的所有頁 → 逐首在目標音源搜尋並
/// 評分 → 使用者改選、重搜、排除 → [confirm] 一個 transaction 建本機歌單。生命週期跟著匯入預覽頁：
/// 頁面關掉就 [dispose]，進行中的搜尋結果丟掉，什麼都不寫。候選只在記憶體。
///
/// 每次狀態改變都 [notifyListeners]。
final class ExternalImport extends ChangeNotifier {
  ExternalImport({
    required this.source,
    required this.playlistId,
    required this.available,
    required List<String> targets,
    required this._playlists,
    required this._results,
    required this._log,
  }) : _targets = _ordered(available, targets);

  /// 來源插件（`importPlaylist`）。
  final SourcePlugin source;

  /// 來源裡的歌單 id。
  final String playlistId;

  /// 可以當目標的音源（目標 chip），依設定的順序。
  final List<SourcePlugin> available;

  final PlaylistRepository _playlists;
  final MatchResultsRepository _results;
  final Log _log;

  List<String> _targets;
  var _reading = false;
  AppError? _readError;
  var _readCount = 0;
  var _started = false;
  var _running = false;
  var _creating = false;
  var _created = false;
  var _touched = false;
  var _disposed = false;
  var _scan = 0;
  String? _title;
  var _truncated = false;
  List<ImportSong> _rows = const [];
  List<ImportSong> _songs = const [];

  String get pluginId => source.manifest.id;

  /// 來源插件自己能播：這是「配對到其他音源」（§17 第 19 條）。
  bool get pairing =>
      source.manifest.capabilities.contains(PluginCapability.resolveStream);

  /// 這次匯入的目標音源（插件 id），依 [available] 的順序（同分時的先後）。
  List<String> get targets => _targets;

  ExternalImportPhase get phase {
    if (_reading) return ExternalImportPhase.reading;
    if (_readError != null) return ExternalImportPhase.readFailed;
    if (!_started) return ExternalImportPhase.ready;
    return _songs.every((song) => song.match.settled)
        ? ExternalImportPhase.done
        : ExternalImportPhase.matching;
  }

  /// 讀取失敗的原因（[ExternalImportPhase.readFailed]）。
  AppError? get readError => _readError;

  /// 讀取中已讀的首數。
  int get readCount => _readCount;

  /// 遠端歌單的標題（第一頁回來之後才有）；建立的歌單用它當名稱。
  String? get title => _title;

  /// 最後一頁是 `truncated`：來源只提供了部分曲目。
  bool get truncated => _truncated;

  /// 來源歌單的每一列，依原順序（同一首出現多次時是同一個 [ImportSong]）。
  List<ImportSong> get rows => _rows;

  /// 不重複的外部歌曲，依第一次出現的順序。
  List<ImportSong> get songs => _songs;

  /// 已經有結果的列數（「已匹配 n／總數」的 n）。
  int get settledCount => _rows.where((row) => row.match.settled).length;

  /// 會進歌單的列數。
  int get chosenCount => _rows.where((row) => row.chosen != null).length;

  /// 要搜尋的首數（不重複、沒有沿用先前結果的）。
  int get searchCount =>
      _songs.where((song) => song.match is! MatchReused).length;

  /// 沿用先前結果的首數（不重複）。
  int get reusedCount => _songs.length - searchCount;

  /// 正在建立歌單。
  bool get creating => _creating;

  /// 已經建好歌單（[confirm] 成功過）：不能再建一次。
  bool get created => _created;

  /// 使用者做過會丟掉的事：按了「開始匹配」，或改選、排除、重搜過，或開始後改過目標。只讀完（含全部沿用
  /// 而直接完成）時是假：離開不用確認。
  bool get touched => _touched;

  /// 可以按「建立歌單」：每一首都有結果、至少一列會進歌單、不在建立中、還沒建過。
  bool get canCreate =>
      phase == ExternalImportPhase.done &&
      chosenCount > 0 &&
      !_creating &&
      !_created;

  /// 讀來源歌單的所有頁（失敗後的「重試」也是它）。任何一頁失敗就停在
  /// [ExternalImportPhase.readFailed]，不進匹配；最後一頁 `truncated` 照常往下。讀完後以
  /// `match_results` 找出沿用的結果（不搜尋）；每一首都沿用時沒有要搜的，直接是
  /// [ExternalImportPhase.done]（不用按「開始匹配」）。
  Future<void> read() async {
    if (_reading || _started) return;
    _reading = true;
    _readError = null;
    _readCount = 0;
    _notify();
    try {
      final items = <RemotePlaylistItem>[];
      final cursors = <String>{};
      String? cursor;
      var truncated = false;
      do {
        final page = await source.importPlaylist(
          PlaylistPageQuery(playlistId: playlistId, cursor: cursor),
        );
        if (_disposed) return;
        _title ??= page.playlist.title;
        items.addAll(page.items);
        _readCount = items.length;
        truncated = page.truncated;
        cursor = page.cursor;
        if (cursor != null && !cursors.add(cursor)) {
          throw ParseError(
            pluginId: pluginId,
            cause: StateError('The playlist repeats a cursor'),
          );
        }
        _notify();
      } while (cursor != null);
      final byId = <String, ImportSong>{};
      final rows = [
        for (final item in items)
          byId.putIfAbsent(
            _originId(item.track),
            () => ImportSong._(item.track, _originId(item.track)),
          ),
      ];
      final stored = await _results.find(pluginId, byId.keys);
      if (_disposed) return;
      for (final song in byId.values) {
        final result = stored[song.originId];
        if (result == null) continue;
        song._match = MatchReused(
          selected: result.selected,
          score: result.score,
        );
        // 選定為空而 `user_selected` 真＝排除：那是排除旗標，不是「選過」（取消排除後就不再是使用者的選擇）。
        song._picked = result.userSelected && result.selected != null;
        song._manual = result.userSelected;
        song._excluded = result.selected == null && result.userSelected;
      }
      _rows = List.unmodifiable(rows);
      _songs = List.unmodifiable(byId.values);
      _truncated = truncated;
      _reading = false;
      // 全部沿用：沒有要搜的，直接完成（chip 照樣可以臨時改目標並重搜沿用的自動結果）。
      if (_songs.isNotEmpty && searchCount == 0) _started = true;
      _log.info(
        'External playlist read',
        tag: matchingLogTag,
        fields: {
          'pluginId': pluginId,
          'items': _rows.length,
          'songs': _songs.length,
          'reused': reusedCount,
          'truncated': truncated,
        },
      );
      _notify();
    } on Object catch (error, stackTrace) {
      if (_disposed) return;
      final appError = AppError.wrap(error, stackTrace, pluginId: pluginId);
      _log.report(
        'Failed to read a playlist for matching',
        appError,
        tag: matchingLogTag,
      );
      _reading = false;
      _readError = appError;
      _notify();
    }
  }

  /// 開始逐首匹配（[ExternalImportPhase.ready] 之後）。沿用的、已經重搜過的不再搜。
  void start() {
    if (phase != ExternalImportPhase.ready) {
      throw StateError('Matching can start once, after reading: $phase');
    }
    if (_targets.isEmpty) throw StateError('No match target');
    _started = true;
    _touched = true;
    _notify();
    unawaited(_run());
  }

  /// 臨時改這次的目標音源（不寫設定）。已開始匹配時，重搜所有不是 [ImportSong.manual] 的
  /// （沒有被使用者改選、排除或自訂重搜過的，含沿用的自動結果）；開始後不能一個都不選。
  void setTargets(Iterable<String> pluginIds) {
    final next = _ordered(available, pluginIds);
    if (listEquals(next, _targets)) return;
    if (_started && next.isEmpty) {
      throw ArgumentError.value(pluginIds, 'pluginIds', 'must not be empty');
    }
    _targets = next;
    if (_started) {
      _touched = true;
      for (final song in _songs) {
        if (song._manual || song.match is MatchPending) continue;
        song._generation++;
        song._match = const MatchPending();
        song._picked = false;
      }
      _scan = 0;
      unawaited(_run());
    }
    _notify();
  }

  /// 選 [candidate]（[song] 目前的候選之一）。
  void select(ImportSong song, ImportCandidate candidate) {
    final match = song.match;
    if (match is! MatchFound || !match.candidates.contains(candidate)) {
      throw ArgumentError.value(candidate, 'candidate', 'is not a candidate');
    }
    song._match = MatchFound(candidates: match.candidates, selected: candidate);
    song._picked = true;
    song._manual = true;
    song._excluded = false;
    _touched = true;
    _notify();
  }

  /// 排除或取消排除 [song]。排除的不進歌單，`match_results` 記成使用者排除。
  void setExcluded(ImportSong song, {required bool excluded}) {
    if (song._excluded == excluded) return;
    song._excluded = excluded;
    if (excluded) song._manual = true;
    _touched = true;
    _notify();
  }

  /// 重搜 [song]：[keyword] 是自訂的關鍵字（空白或 `null` 用預設的），同一套評分。自訂關鍵字的
  /// 重搜算手動（臨時改目標時不再被重搜）。
  Future<void> research(ImportSong song, {String? keyword}) async {
    if (_targets.isEmpty) throw StateError('No match target');
    final custom = keyword?.trim();
    final manual = custom != null && custom.isNotEmpty;
    // 一開始就算手動：進行中的自訂重搜不會被這期間的 [setTargets] 換掉。
    if (manual) song._manual = true;
    _touched = true;
    await _search(song, keyword: manual ? custom : null, manual: manual);
  }

  /// 確認（每一首都有結果之後）：一個 transaction 建本機歌單（名稱＝遠端標題），依原順序寫會進
  /// 歌單的曲目，每首寫 `match_results`（匹配失敗、排除的選定為空；搜尋失敗的不寫，下次匯入再搜），
  /// 選定的寫 `track_origins`。配對模式也一樣，不寫 `playlist_remote`。回傳新歌單的 id。
  /// 失敗丟 `AppError`，什麼都沒寫（可以再試）；成功之後不能再呼叫（[StateError]）。
  Future<int> confirm() async {
    if (_created) throw StateError('The playlist has been created');
    if (!canCreate) throw StateError('Nothing to create yet: $phase');
    _creating = true;
    _notify();
    try {
      final tracks = [for (final row in _rows) ?row.chosen];
      final matches = [
        for (final song in _songs)
          if (song.match is! MatchSearchFailed) _resultOf(song),
      ];
      final id = await _playlists.createFromMatches(
        name: _title!,
        tracks: tracks,
        matches: matches,
      );
      _log.info(
        'External import created',
        tag: matchingLogTag,
        fields: {
          'pluginId': pluginId,
          'playlistId': id,
          'items': _rows.length,
          'added': tracks.length,
          'pairing': pairing,
        },
      );
      _created = true;
      return id;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(AppError.wrap(error, stackTrace), stackTrace);
    } finally {
      _creating = false;
      _notify();
    }
  }

  /// 頁面關掉：進行中的搜尋結果之後回來也丟掉。呼叫兩次無妨。
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }

  MatchResult _resultOf(ImportSong song) {
    final chosen = song.chosen;
    return MatchResult(
      originPluginId: pluginId,
      originId: song.originId,
      title: song.title,
      artists: song.artists,
      duration: song.duration,
      selected: chosen,
      score: chosen == null
          ? null
          : switch (song.match) {
              MatchFound(:final selected?) => selected.score.total,
              MatchReused(:final score) => score,
              _ => null,
            },
      userSelected: song._picked || song._excluded,
    );
  }

  /// 依序搜還沒搜的（一次一首，每首對每個目標音源同時搜）；改目標後從頭再掃一次。
  Future<void> _run() async {
    if (_running) return;
    _running = true;
    try {
      while (!_disposed) {
        while (_scan < _songs.length && _songs[_scan].match is! MatchPending) {
          _scan++;
        }
        if (_scan >= _songs.length) break;
        await _search(_songs[_scan], manual: false);
      }
    } finally {
      _running = false;
    }
    if (!_disposed && phase == ExternalImportPhase.done) {
      _log.info(
        'External import matched',
        tag: matchingLogTag,
        fields: {
          'pluginId': pluginId,
          'songs': _songs.length,
          'matched': _songs.where((song) => song.chosen != null).length,
          'failed': _songs
              .where((song) => song.match is MatchSearchFailed)
              .length,
          'targets': _targets.length,
        },
      );
    }
  }

  Future<void> _search(
    ImportSong song, {
    String? keyword,
    required bool manual,
  }) async {
    final generation = ++song._generation;
    song._match = const MatchSearching();
    _notify();
    try {
      await _searchAndRank(song, generation, keyword: keyword);
    } on Object catch (error, stackTrace) {
      // 插件以外的錯誤（關鍵字是空的、評分丟例外）：這一首標「搜尋失敗」，整批照常往下，不卡在搜尋中。
      if (_disposed || song._generation != generation) return;
      final appError = AppError.wrap(error, stackTrace);
      _log.report('Match search failed', appError, tag: matchingLogTag);
      song._match = MatchSearchFailed(appError);
    }
    if (_disposed || song._generation != generation) return;
    song._picked = false;
    if (manual) song._manual = true;
    _notify();
  }

  Future<void> _searchAndRank(
    ImportSong song,
    int generation, {
    String? keyword,
  }) async {
    final query = SearchQuery(keyword: keyword ?? song.defaultKeyword);
    final targets = [
      for (final plugin in available)
        if (_targets.contains(plugin.manifest.id)) plugin,
    ];
    final pages = await Future.wait([
      for (final plugin in targets) _searchOne(plugin, query),
    ]);
    if (_disposed || song._generation != generation) return;
    final found = [
      for (final page in pages)
        if (page case (final SearchPage found, null)) found,
    ];
    if (found.isEmpty && targets.isNotEmpty) {
      final error = pages.first.$2!;
      _log.warning(
        'Match search failed',
        tag: matchingLogTag,
        fields: {'pluginId': pluginId, 'type': error.typeName},
      );
      song._match = MatchSearchFailed(error);
    } else {
      final ranked = rank(song._query, [
        for (final page in found)
          for (final item in page.items)
            (
              item.toTrackInfo(),
              MatchCandidate(
                title: item.title,
                uploader: item.uploader,
                duration: item.duration,
              ),
            ),
      ], limit: matchCandidateLimit);
      final candidates = [
        for (final entry in ranked)
          ImportCandidate(track: entry.item, score: entry.score),
      ];
      song._match = MatchFound(
        candidates: List.unmodifiable(candidates),
        selected: candidates.firstOrNull?.score.autoSelectable ?? false
            ? candidates.first
            : null,
      );
    }
  }

  /// 一個目標音源的第一頁；失敗回錯誤（記一行 warning），不中斷其他音源與整批。
  Future<(SearchPage?, AppError?)> _searchOne(
    SourcePlugin plugin,
    SearchQuery query,
  ) async {
    try {
      return (await plugin.search(query), null);
    } on Object catch (error, stackTrace) {
      final appError = AppError.wrap(
        error,
        stackTrace,
        pluginId: plugin.manifest.id,
      );
      _log.warning(
        'Match target search failed',
        tag: matchingLogTag,
        fields: {'pluginId': plugin.manifest.id, 'type': appError.typeName},
      );
      return (null, appError);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static List<String> _ordered(
    List<SourcePlugin> available,
    Iterable<String> pluginIds,
  ) {
    final wanted = pluginIds.toSet();
    return List.unmodifiable([
      for (final plugin in available)
        if (wanted.contains(plugin.manifest.id)) plugin.manifest.id,
    ]);
  }

  /// 外部 id：音源內的 id，分 P 的歌另接 cid（同曲目鍵的後兩段），同一支影片的各 P 才分得開。
  static String _originId(TrackSummary track) {
    final key = TrackKey.format(
      track.sourceTypeId,
      track.sourceId,
      cid: track.cid,
    );
    return key.substring(track.sourceTypeId.length + 1);
  }
}
