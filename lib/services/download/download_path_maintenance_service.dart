import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:fmp/core/constants/download_filenames.dart';
import 'package:fmp/core/logger.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/models/track_key.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/providers/download/download_scanner.dart';
import 'package:fmp/services/download/download_path_manager.dart';
import 'package:fmp/services/download/download_path_utils.dart';

class ChangeBasePathMaintenanceResult {
  const ChangeBasePathMaintenanceResult({
    required this.affectedPlaylistIds,
    required this.clearedDownloadTrackCount,
    required this.clearedTaskCount,
  });

  final List<int> affectedPlaylistIds;
  final int clearedDownloadTrackCount;
  final int clearedTaskCount;
}

class DownloadPathDeletionResult {
  const DownloadPathDeletionResult({
    required this.affectedPlaylistIds,
    required this.clearedPathCount,
    required this.skippedForeignCount,
  });

  final List<int> affectedPlaylistIds;
  final int clearedPathCount;

  /// 因為 FMP 證明不了是自己寫的而原地留下的項目數（含符號連結）。UI 據此在
  /// 刪除不如預期時改發 warning toast，而不是照發成功訊息。
  final int skippedForeignCount;
}

/// `_clearDeletedPaths` 的結果。兩個 public 方法各自組裝
/// [DownloadPathDeletionResult]，skipped 數才不會在多個 return 點漏填。
typedef _ClearedPaths = ({List<int> affectedPlaylistIds, int clearedPathCount});

class DownloadPathMaintenanceService with Logging {
  DownloadPathMaintenanceService({
    required TrackRepository trackRepository,
    required DownloadPathManager pathManager,
    required Future<int> Function() clearCompletedAndErrorTasks,
  }) : _trackRepository = trackRepository,
       _pathManager = pathManager,
       _clearCompletedAndErrorTasks = clearCompletedAndErrorTasks;

  final TrackRepository _trackRepository;
  final DownloadPathManager _pathManager;
  final Future<int> Function() _clearCompletedAndErrorTasks;

  Future<ChangeBasePathMaintenanceResult> changeBasePathAndResetDownloads(
    String newPath,
  ) async {
    final tracksWithDownloads = await _trackRepository
        .getAllTracksWithDownloads();
    final affectedPlaylistIds = _collectAffectedPlaylistIds(
      tracksWithDownloads,
    );

    if (tracksWithDownloads.isNotEmpty) {
      await _trackRepository.clearAllDownloadPaths();
    }

    final clearedTaskCount = await _clearCompletedAndErrorTasks();
    await _pathManager.saveDownloadPath(newPath);

    return ChangeBasePathMaintenanceResult(
      affectedPlaylistIds: affectedPlaylistIds,
      clearedDownloadTrackCount: tracksWithDownloads.length,
      clearedTaskCount: clearedTaskCount,
    );
  }

  Future<DownloadPathDeletionResult> deleteDownloadedCategory(
    String folderPath,
  ) async {
    // 掃描必須在刪除之前：`_clearDeletedPaths` 靠「掃描時還在、現在不見了」認出
    // 被刪掉的檔案來清 DB 路徑，刪完再掃就什麼都掃不到。
    final scannedTracks = await DownloadScanner.scanFolderForTracks(folderPath);
    final trackedPaths = _collectTrackedPaths(scannedTracks);
    final baseDir = await _resolveEffectiveBaseDir();

    final outcome = await compute(
      _deleteCategoryInIsolate,
      _CategoryDeletionParams(categoryPath: folderPath, baseDir: baseDir),
    );

    if (outcome.outsideBase) {
      logWarning(
        'Refusing to delete a downloaded category outside the download base: '
        '$folderPath',
      );
      return const DownloadPathDeletionResult(
        affectedPlaylistIds: [],
        clearedPathCount: 0,
        skippedForeignCount: 0,
      );
    }

    final cleared = await _clearDeletedPaths(scannedTracks, trackedPaths);
    _logDeletionOutcome(outcome, 'category $folderPath');

    return DownloadPathDeletionResult(
      affectedPlaylistIds: cleared.affectedPlaylistIds,
      clearedPathCount: cleared.clearedPathCount,
      skippedForeignCount: outcome.skippedForeignCount,
    );
  }

  Future<DownloadPathDeletionResult> deleteDownloadedTracks(
    List<Track> scannedTracks,
  ) async {
    final trackedPaths = _collectTrackedPaths(scannedTracks);
    final baseDir = await _resolveEffectiveBaseDir();

    final outcome = await compute(
      _deleteFilesInIsolate,
      _TrackDeletionParams(paths: trackedPaths.toList(), baseDir: baseDir),
    );

    final cleared = await _clearDeletedPaths(scannedTracks, trackedPaths);
    _logDeletionOutcome(outcome, '${trackedPaths.length} track path(s)');

    return DownloadPathDeletionResult(
      affectedPlaylistIds: cleared.affectedPlaylistIds,
      clearedPathCount: cleared.clearedPathCount,
      skippedForeignCount: outcome.skippedForeignCount,
    );
  }

  /// 解析目前有效的下載根目錄；失敗回 null = containment guard 停用。
  ///
  /// isolate 內不寫 log（file sink 只在 main isolate 開得起來），所以判斷留在
  /// 這裡：拿不到 base 就等於認不出擁有權的邊界，此時寧可停用 guard 也不要讓
  /// 使用者的刪除操作直接失敗。
  Future<String?> _resolveEffectiveBaseDir() async {
    try {
      return await _pathManager.getEffectiveBaseDir();
    } catch (e, stackTrace) {
      logError(
        'Resolving the download base failed; the deletion containment guard '
        'is disabled for this operation',
        e,
        stackTrace,
      );
      return null;
    }
  }

  /// isolate 只帶回數字，診斷字串在這裡才寫進 log。
  void _logDeletionOutcome(_DeletionOutcome outcome, String target) {
    logDebug(
      'Deleted ${outcome.deletedFileCount} file(s) and kept '
      '${outcome.skippedForeignCount} item(s) FMP cannot prove it wrote '
      '($target)',
    );
  }

  Future<_ClearedPaths> _clearDeletedPaths(
    List<Track> scannedTracks,
    Set<String> trackedPaths,
  ) async {
    if (scannedTracks.isEmpty || trackedPaths.isEmpty) {
      return (affectedPlaylistIds: <int>[], clearedPathCount: 0);
    }

    final deletedPaths = <String>{};
    for (final path in trackedPaths) {
      if (!await File(path).exists()) {
        deletedPaths.add(_normalizePath(path));
      }
    }

    if (deletedPaths.isEmpty) {
      return (affectedPlaylistIds: <int>[], clearedPathCount: 0);
    }

    final persistedTracks = await _trackRepository.getAllTracksWithDownloads();
    final tracksBySourceKey = <String, List<Track>>{};
    for (final track in persistedTracks) {
      tracksBySourceKey.putIfAbsent(_sourceKey(track), () => []).add(track);
    }

    final affectedPlaylistIds = <int>{};
    var clearedPathCount = 0;

    for (final scannedTrack in scannedTracks) {
      final persistedTrack = _findMatchingPersistedTrack(
        scannedTrack,
        tracksBySourceKey[_sourceKey(scannedTrack)] ?? const [],
      );
      if (persistedTrack == null) {
        continue;
      }

      final scannedPathsForTrack = _matchDeletedPathsForTrack(
        scannedTrack: scannedTrack,
        deletedPaths: deletedPaths,
      );
      if (scannedPathsForTrack.isEmpty) {
        continue;
      }

      var changed = false;
      final nextPlaylistInfo = <PlaylistDownloadInfo>[];
      for (final info in persistedTrack.playlistInfo) {
        final shouldClear =
            info.downloadPath.isNotEmpty &&
            scannedPathsForTrack.contains(_normalizePath(info.downloadPath));
        nextPlaylistInfo.add(
          PlaylistDownloadInfo()
            ..playlistId = info.playlistId
            ..playlistName = info.playlistName
            ..downloadPath = shouldClear ? '' : info.downloadPath,
        );
        if (shouldClear) {
          changed = true;
          clearedPathCount++;
          if (info.playlistId > 0) {
            affectedPlaylistIds.add(info.playlistId);
          }
        }
      }

      if (changed) {
        persistedTrack.playlistInfo = nextPlaylistInfo;
        await _trackRepository.save(persistedTrack);
      }
    }

    return (
      affectedPlaylistIds: _sortIds(affectedPlaylistIds),
      clearedPathCount: clearedPathCount,
    );
  }

  Set<String> _collectTrackedPaths(List<Track> scannedTracks) {
    return scannedTracks
        .expand((track) => track.allDownloadPaths)
        .where((path) => path.isNotEmpty)
        .toSet();
  }

  Set<String> _matchDeletedPathsForTrack({
    required Track scannedTrack,
    required Set<String> deletedPaths,
  }) {
    final matchedPaths = <String>{};
    for (final path in scannedTrack.allDownloadPaths) {
      final normalizedPath = _normalizePath(path);
      if (path.isNotEmpty && deletedPaths.contains(normalizedPath)) {
        matchedPaths.add(normalizedPath);
        continue;
      }

      final folderPath = p.dirname(path);
      if (folderPath.isNotEmpty && !Directory(folderPath).existsSync()) {
        matchedPaths.add(normalizedPath);
      }
    }
    return matchedPaths;
  }

  Track? _findMatchingPersistedTrack(
    Track scannedTrack,
    List<Track> candidates,
  ) {
    if (candidates.isEmpty) {
      return null;
    }

    if (scannedTrack.cid != null) {
      return candidates
          .where((track) => track.cid == scannedTrack.cid)
          .firstOrNull;
    }

    if (scannedTrack.pageNum != null) {
      return candidates
          .where((track) => track.pageNum == scannedTrack.pageNum)
          .firstOrNull;
    }

    if (candidates.length == 1) {
      return candidates.first;
    }

    return candidates
        .where((track) => track.cid == null && track.pageNum == null)
        .firstOrNull;
  }

  List<int> _collectAffectedPlaylistIds(List<Track> tracks) {
    final playlistIds = <int>{};
    for (final track in tracks) {
      for (final info in track.playlistInfo) {
        if (info.downloadPath.isNotEmpty && info.playlistId > 0) {
          playlistIds.add(info.playlistId);
        }
      }
    }
    return _sortIds(playlistIds);
  }

  String _sourceKey(Track track) =>
      TrackKey.formatGroup(track.sourceType, track.sourceId);

  String _normalizePath(String path) {
    if (path.isEmpty) {
      return path;
    }
    return p.normalize(path.replaceAll('\\', '/'));
  }

  List<int> _sortIds(Set<int> ids) {
    final sorted = ids.toList()..sort();
    return sorted;
  }
}

/// 分類刪除的 isolate 參數。
///
/// 自訂類別跨 isolate 傳遞在此 repo 是既有做法（`DownloadedCategory` 就是這樣
/// 進出 `compute`）。
class _CategoryDeletionParams {
  const _CategoryDeletionParams({required this.categoryPath, this.baseDir});

  final String categoryPath;

  /// 有效下載根目錄；null = 解析失敗，containment guard 停用。
  final String? baseDir;
}

/// 追蹤檔刪除的 isolate 參數。
class _TrackDeletionParams {
  const _TrackDeletionParams({required this.paths, this.baseDir});

  final List<String> paths;
  final String? baseDir;
}

/// isolate 刪除結果。
///
/// isolate 不寫 log（file sink 只在 main isolate 開得起來），診斷一律由這個
/// 物件帶回 main isolate 記錄。
class _DeletionOutcome {
  const _DeletionOutcome({
    this.deletedFileCount = 0,
    this.skippedForeignCount = 0,
    this.outsideBase = false,
  });

  /// 實際刪掉的檔案數（含一併刪掉的 metadata / 封面 / 頭像）。
  final int deletedFileCount;

  /// 認不出擁有權而原地留下的項目數。
  final int skippedForeignCount;

  /// 目標不在下載根目錄內：整個操作拒絕執行。
  final bool outsideBase;
}

/// 刪除一整個已下載分類。
///
/// 擁有權只用「證明」判定：名字是 FMP 的共通產物，或是與配對 metadata 同層的
/// 音訊檔。其餘一律跳過並回報。**永遠不遞迴刪除** —— 目錄只在嚴格為空時由深到
/// 淺移除，所以使用者放在同一個資料夾裡的其他檔案會讓它留下來。
Future<_DeletionOutcome> _deleteCategoryInIsolate(
  _CategoryDeletionParams params,
) async {
  final categoryPath = params.categoryPath;
  final baseDir = params.baseDir;
  if (!_isPathInsideBase(categoryPath, baseDir)) {
    return const _DeletionOutcome(outsideBase: true);
  }

  final root = Directory(categoryPath);
  if (!await root.exists()) {
    return const _DeletionOutcome();
  }

  var deletedFileCount = 0;
  var skippedForeignCount = 0;
  final filesByFolder = <String, List<String>>{};
  final directories = <String>[categoryPath];

  try {
    // followLinks: false —— 不跟隨也不刪除符號連結，連結本身計入 skipped。
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Directory) {
        directories.add(entity.path);
      } else if (entity is File) {
        filesByFolder
            .putIfAbsent(entity.parent.path, () => <String>[])
            .add(entity.path);
      } else {
        skippedForeignCount++;
      }
    }
  } on FileSystemException {
    // Keep best-effort deletion behavior for UI flows.
  }

  // 擁有權用「刪除前」的同層檔名清單判定：`metadata.json` 是共通產物，會在
  // 同一輪被刪掉，邊刪邊判定會讓它的音檔兄弟看起來像孤兒。
  for (final entry in filesByFolder.entries) {
    final names = entry.value.map(p.basename).toSet();
    for (final filePath in entry.value) {
      final name = p.basename(filePath);
      // `.downloading` 暫存檔屬於還在佇列上的可續傳任務，由啟動孤兒掃描處理；
      // 這裡既不刪除，也不算成外來檔案。
      if (_isTempDownloadFile(name)) continue;
      if (!_isOwnedDownloadFile(name, names)) {
        skippedForeignCount++;
        continue;
      }
      try {
        await File(filePath).delete();
        deletedFileCount++;
      } on FileSystemException {
        // Keep best-effort deletion behavior for UI flows.
      }
    }
  }

  // 空目錄刪除一律在掃描結束後、由深到淺進行，絕不遞迴。
  for (final dirPath in _deepestFirst(directories)) {
    if (_isBaseDirItself(dirPath, baseDir)) continue;
    try {
      await _deleteDirectoryIfEmpty(Directory(dirPath));
    } on FileSystemException {
      // Keep best-effort deletion behavior for UI flows.
    }
  }

  return _DeletionOutcome(
    deletedFileCount: deletedFileCount,
    skippedForeignCount: skippedForeignCount,
  );
}

/// 刪除指定的已下載音檔（單曲／整個分P）。
Future<_DeletionOutcome> _deleteFilesInIsolate(
  _TrackDeletionParams params,
) async {
  final baseDir = params.baseDir;
  var deletedFileCount = 0;
  var skippedForeignCount = 0;
  final foldersToClean = <String>{};
  final foldersToInspect = <String>{};
  final namesByFolder = <String, Set<String>>{};

  for (final path in params.paths) {
    try {
      if (!_isPathInsideBase(path, baseDir)) {
        skippedForeignCount++;
        continue;
      }

      final file = File(path);
      if (!await file.exists()) continue;

      final parentDir = file.parent;
      foldersToInspect.add(parentDir.path);
      var names = namesByFolder[parentDir.path];
      if (names == null) {
        names = await _fileNamesIn(parentDir);
        namesByFolder[parentDir.path] = names;
      }

      final name = p.basename(path);
      // 認不出擁有權的目標路徑不在這裡計數：它的資料夾已進 `foldersToInspect`，
      // 刪除結束後 `_countUnprovenItems` 會連同其他外來檔一起算一次。這裡再加
      // 一次就是重複計數（實測：單一無 metadata 的 `.m4a` 回報 2 而非 1）。
      if (!_isOwnedDownloadFile(name, names)) continue;

      await file.delete();
      deletedFileCount++;
      foldersToClean.add(parentDir.path);
      deletedFileCount += await _deletePageMetadataForAudio(parentDir, name);
    } on FileSystemException {
      // Keep best-effort deletion behavior for UI flows.
    }
  }

  for (final folderPath in foldersToClean) {
    try {
      if (_isBaseDirItself(folderPath, baseDir)) continue;

      final dir = Directory(folderPath);
      if (!await dir.exists()) continue;
      // 還有 FMP 音檔就什麼都不動：封面／頭像／共用 metadata 都還有人要。
      if (await _hasRemainingAudioFiles(dir)) continue;

      deletedFileCount += await _deleteFolderArtifacts(dir);
      await _deleteDirectoryIfEmpty(dir);
      await _deleteParentIfEmpty(dir.parent, baseDir);
    } on FileSystemException {
      // Keep best-effort deletion behavior for UI flows.
    }
  }

  // 被碰過的資料夾裡認不出擁有權的東西一律回報（含剛才因為沒有配對 metadata
  // 而跳過的音檔）。在刪除之後才算，數字才是使用者實際看到的結果。
  for (final folderPath in foldersToInspect) {
    final dir = Directory(folderPath);
    if (!await dir.exists()) continue;
    skippedForeignCount += await _countUnprovenItems(dir);
  }

  return _DeletionOutcome(
    deletedFileCount: deletedFileCount,
    skippedForeignCount: skippedForeignCount,
  );
}

/// 刪掉與音檔同頁的 `metadata_P{N}.json`，回傳刪除數。
///
/// 共用的 `metadata.json` **不在這裡刪**：舊版佈局的多頁資料夾共用同一個
/// `metadata.json`（檔名分不出誰是擁有者），在這裡刪掉會讓兄弟頁的 metadata
/// 當場變成認不出擁有權的孤兒檔。它留給 [_deleteFolderArtifacts] 在整個資料夾
/// 已經沒有 FMP 音檔時才處理。
Future<int> _deletePageMetadataForAudio(
  Directory parentDir,
  String audioName,
) async {
  for (final candidate in DownloadFileNames.metadataCandidatesForAudio(
    audioName,
  )) {
    if (candidate == DownloadFileNames.metadata) continue;
    final metadataFile = File(p.join(parentDir.path, candidate));
    if (await metadataFile.exists()) {
      await metadataFile.delete();
      return 1;
    }
  }
  return 0;
}

/// 資料夾已經沒有 FMP 音檔時，清掉封面、頭像與沒音檔可配的 metadata。
Future<int> _deleteFolderArtifacts(Directory dir) async {
  var deleted = 0;
  for (final entity in await dir.list(followLinks: false).toList()) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (name != DownloadFileNames.cover &&
        name != DownloadFileNames.avatar &&
        !_isMetadataFile(name)) {
      continue;
    }
    try {
      await entity.delete();
      deleted++;
    } on FileSystemException {
      // Keep best-effort deletion behavior for UI flows.
    }
  }
  return deleted;
}

/// FMP 證明不了擁有權、因而留在資料夾裡的項目數（不含 `.downloading`）。
Future<int> _countUnprovenItems(Directory dir) async {
  var count = 0;
  final names = <String>{};
  try {
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) {
        names.add(p.basename(entity.path));
      } else if (entity is! Directory) {
        count++;
      }
    }
  } on FileSystemException {
    return count;
  }

  for (final name in names) {
    if (_isTempDownloadFile(name)) continue;
    if (!_isOwnedDownloadFile(name, names)) count++;
  }
  return count;
}

/// 這個資料夾裡還有沒有音訊 —— 問的是「封面／頭像／共用 metadata 還有人要嗎」，
/// 所以放寬到使用者可能自己放進來的音訊格式。
const _audioExtensions = <String>['.m4a', '.mp3', '.aac', '.opus'];

/// FMP 寫得出來的音訊副檔名：`DownloadPathUtils.computeDownloadPath` 只寫 `.m4a`
/// （單頁 `audio.m4a`、多頁 `P{NN}.m4a`），來源設定裡的 opus/aac 只決定串流容器，
/// 不影響檔名。刪除端只認這一種 —— 同層就算有 `metadata.json`，`my_song.mp3`
/// 也不可能是 FMP 下載的，寧可留下來回報。
const _ownedAudioExtensions = <String>['.m4a'];

final _pageMetadataPattern = RegExp(r'^metadata_P\d+\.json$');

/// 可續傳任務的暫存檔；由啟動孤兒掃描處理，不屬於任何一次刪除。
bool _isTempDownloadFile(String name) =>
    name.toLowerCase().endsWith('.downloading');

bool _isMetadataFile(String name) =>
    name == DownloadFileNames.metadata || _pageMetadataPattern.hasMatch(name);

/// 擁有權判定：共通產物名，或與配對 metadata 同層的 FMP 音訊檔。
/// 其餘都是外來檔案。
bool _isOwnedDownloadFile(String name, Set<String> siblingNames) {
  if (name == DownloadFileNames.cover ||
      name == DownloadFileNames.avatar ||
      _isMetadataFile(name)) {
    return true;
  }

  final lower = name.toLowerCase();
  if (!_ownedAudioExtensions.any(lower.endsWith)) return false;

  return DownloadFileNames.metadataCandidatesForAudio(
    name,
  ).any(siblingNames.contains);
}

/// base 未知（解析失敗）時不設限；否則要求目標在 base 內。
bool _isPathInsideBase(String path, String? baseDir) {
  if (baseDir == null) return true;
  return DownloadPathUtils.isPathInsideBase(path, baseDir);
}

/// 空目錄刪除的唯一避險：下載根目錄本身永遠不刪。
bool _isBaseDirItself(String path, String? baseDir) {
  if (baseDir == null) return false;
  return p.equals(
    p.normalize(p.absolute(path)),
    p.normalize(p.absolute(baseDir)),
  );
}

/// 由深到淺排序，父目錄要等子目錄處理完才輪到。
List<String> _deepestFirst(Iterable<String> paths) {
  final sorted = paths.toList()
    ..sort((a, b) {
      final byDepth = p.split(b).length.compareTo(p.split(a).length);
      return byDepth != 0 ? byDepth : b.length.compareTo(a.length);
    });
  return sorted;
}

Future<Set<String>> _fileNamesIn(Directory dir) async {
  final names = <String>{};
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is File) names.add(p.basename(entity.path));
  }
  return names;
}

Future<bool> _hasRemainingAudioFiles(Directory dir) async {
  final entities = await dir.list(followLinks: false).toList();
  return entities.any((entity) {
    if (entity is! File) return false;
    final name = p.basename(entity.path).toLowerCase();
    return _audioExtensions.any(name.endsWith);
  });
}

Future<void> _deleteDirectoryIfEmpty(Directory dir) async {
  if (!await dir.exists()) return;
  if ((await dir.list(followLinks: false).toList()).isNotEmpty) return;
  await dir.delete();
}

Future<void> _deleteParentIfEmpty(Directory dir, String? baseDir) async {
  if (_isBaseDirItself(dir.path, baseDir)) return;
  await _deleteDirectoryIfEmpty(dir);
}
