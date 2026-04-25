# Review-Driven Refactor Phase 4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Phase 4 long-tail performance and data-integrity hardening without reopening the completed Phase 3 playback, history, download-completion, queue-state, or Source-ownership refactors.

**Architecture:** Keep Phase 4 deliberately incremental: UI rebuild optimizations stay at provider/list boundaries, file scanning moves off the UI isolate without changing download file layout, and logical uniqueness work starts as an explicit scan/repair service rather than immediate schema-level unique indexes. `PlaybackOwnershipCoordinator` is out of scope for this phase because no new radio/media-control behavior is being added.

**Tech Stack:** Flutter, Dart, Riverpod, Isar, `flutter_test`, `Isolate.run`, existing source/static guard tests, existing repository/provider test harness patterns.

---

## Scope and File Map

Phase 4 covers four concrete items from `docs/review/summary_review.md`, `docs/review/performance_memory_review.md`, and `docs/review/database_review.md`:

- Modify `lib/providers/lyrics_provider.dart`: expose a current synced-lyrics line-index provider so widgets are notified only when the highlighted line changes.
- Modify `lib/ui/widgets/lyrics_display.dart`: consume the line-index provider instead of watching playback position directly inside the lyrics widget.
- Test `test/providers/lyrics_current_line_provider_test.dart`: pure line-index behavior and source guard that `LyricsDisplay` no longer watches `audioControllerProvider.select((s) => s.position)`.
- Modify `lib/providers/download/download_scanner.dart`: add a folder-detail scan DTO and isolate entrypoint for category detail scans.
- Modify `lib/providers/download/download_providers.dart`: run `downloadedCategoryTracksProvider` through `Isolate.run()`.
- Test `test/providers/download/download_category_scan_isolate_test.dart`: verify DTO conversion, real temp-folder scan behavior, and provider source guard.
- Modify `lib/ui/pages/settings/download_manager_page.dart`: flatten download manager rows into builder rows so non-active tasks are lazy-built.
- Test `test/ui/pages/settings/download_manager_page_phase4_test.dart`: extend existing structural tests to require flattened rows and reject spread-map `ListView(children)` patterns.
- Create `lib/services/database/data_integrity_service.dart`: scan and explicitly repair logical duplicates for Track, DownloadTask, Account, and PlayQueue before any future unique-index migration.
- Test `test/services/database/data_integrity_service_test.dart`: repository-level duplicate scan/repair coverage using a temp Isar database.

Out of scope:

- Do not add Isar unique indexes in Phase 4.
- Do not auto-run duplicate repair at app startup.
- Do not introduce `PlaybackOwnershipCoordinator` unless a later feature expands radio/media-control behavior.
- Do not rewrite `AudioController`, queue persistence, or Phase 3 history pagination.

---

### Task 1: Lyrics Current Line Index Provider

**Files:**
- Modify: `lib/providers/lyrics_provider.dart:184-201`
- Modify: `lib/ui/widgets/lyrics_display.dart:251-364`
- Create: `test/providers/lyrics_current_line_provider_test.dart`

- [ ] **Step 1: Write the failing provider/source-guard tests**

Create `test/providers/lyrics_current_line_provider_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/providers/lyrics_provider.dart';
import 'package:fmp/services/lyrics/lrc_parser.dart';

void main() {
  group('current lyrics line index provider support', () {
    test('calculateCurrentLyricsLineIndex changes only at lyric boundaries', () {
      final lyrics = ParsedLyrics(
        isSynced: true,
        lines: const [
          LyricsLine(timestamp: Duration(seconds: 1), text: 'first'),
          LyricsLine(timestamp: Duration(seconds: 5), text: 'second'),
          LyricsLine(timestamp: Duration(seconds: 9), text: 'third'),
        ],
      );

      expect(
        calculateCurrentLyricsLineIndex(
          lyrics: lyrics,
          position: const Duration(milliseconds: 500),
          offsetMs: 0,
        ),
        -1,
      );
      expect(
        calculateCurrentLyricsLineIndex(
          lyrics: lyrics,
          position: const Duration(seconds: 2),
          offsetMs: 0,
        ),
        0,
      );
      expect(
        calculateCurrentLyricsLineIndex(
          lyrics: lyrics,
          position: const Duration(seconds: 4),
          offsetMs: 0,
        ),
        0,
      );
      expect(
        calculateCurrentLyricsLineIndex(
          lyrics: lyrics,
          position: const Duration(seconds: 5),
          offsetMs: 0,
        ),
        1,
      );
    });

    test('calculateCurrentLyricsLineIndex applies offset', () {
      final lyrics = ParsedLyrics(
        isSynced: true,
        lines: const [
          LyricsLine(timestamp: Duration(seconds: 3), text: 'line'),
        ],
      );

      expect(
        calculateCurrentLyricsLineIndex(
          lyrics: lyrics,
          position: const Duration(seconds: 2),
          offsetMs: 1000,
        ),
        0,
      );
    });

    test('LyricsDisplay consumes line index provider instead of raw position', () {
      final source = File('lib/ui/widgets/lyrics_display.dart').readAsStringSync();

      expect(source, contains('currentLyricsLineIndexProvider'));
      expect(
        source,
        isNot(contains('audioControllerProvider.select((s) => s.position)')),
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests and verify they fail**

Run: `flutter test test/providers/lyrics_current_line_provider_test.dart`
Expected: FAIL because `calculateCurrentLyricsLineIndex` and `currentLyricsLineIndexProvider` do not exist, and `LyricsDisplay` still watches raw position.

- [ ] **Step 3: Add the line-index helper and provider**

In `lib/providers/lyrics_provider.dart`, after `parsedLyricsProvider`, add:

```dart
int calculateCurrentLyricsLineIndex({
  required ParsedLyrics? lyrics,
  required Duration position,
  required int offsetMs,
}) {
  if (lyrics == null || !lyrics.isSynced || lyrics.isEmpty) {
    return -1;
  }
  return LrcParser.findCurrentLineIndex(
    lyrics.lines,
    position,
    offsetMs,
  );
}

/// 当前同步歌词行索引。
///
/// This provider may recompute for every playback position tick, but it only
/// notifies dependents when the integer line index changes. Lyrics widgets
/// should watch this provider instead of watching raw playback position.
final currentLyricsLineIndexProvider = Provider.autoDispose<int>((ref) {
  final lyrics = ref.watch(parsedLyricsProvider);
  final match = ref.watch(currentLyricsMatchProvider).valueOrNull;
  final position = ref.watch(
    audioControllerProvider.select((state) => state.position),
  );

  return calculateCurrentLyricsLineIndex(
    lyrics: lyrics,
    position: position,
    offsetMs: match?.offsetMs ?? 0,
  );
});
```

- [ ] **Step 4: Update LyricsDisplay to consume the provider**

In `lib/ui/widgets/lyrics_display.dart`, remove the import of `../../services/audio/audio_provider.dart` if it is no longer needed directly by the file.

In `_buildSyncedLyrics()`, replace the raw position watch and inline calculation:

```dart
    final position = ref.watch(audioControllerProvider.select((s) => s.position));
    final currentTrack = ref.watch(currentTrackProvider);

    final newIndex = LrcParser.findCurrentLineIndex(
      lyrics.lines,
      position,
      offsetMs,
    );
```

with:

```dart
    final newIndex = ref.watch(currentLyricsLineIndexProvider);
    final currentTrack = ref.watch(currentTrackProvider);
```

Keep the existing first-build scroll, line-change scroll, manual-scroll resume, and offset-control logic unchanged.

- [ ] **Step 5: Verify and commit**

Run: `dart format lib/providers/lyrics_provider.dart lib/ui/widgets/lyrics_display.dart test/providers/lyrics_current_line_provider_test.dart`
Expected: files formatted.

Run: `flutter test test/providers/lyrics_current_line_provider_test.dart`
Expected: PASS.

Run: `flutter test test/services/lyrics/lyrics_auto_match_service_phase4_test.dart`
Expected: PASS.

Run: `git add lib/providers/lyrics_provider.dart lib/ui/widgets/lyrics_display.dart test/providers/lyrics_current_line_provider_test.dart && git commit -m "perf(lyrics): providerize current line index"`
Expected: commit succeeds.

---

### Task 2: Downloaded Category Detail Isolate Scan

**Files:**
- Modify: `lib/providers/download/download_scanner.dart:44-89`, `lib/providers/download/download_scanner.dart:197-330`
- Modify: `lib/providers/download/download_providers.dart:247-251`
- Create: `test/providers/download/download_category_scan_isolate_test.dart`

- [ ] **Step 1: Write the failing isolate/DTO tests**

Create `test/providers/download/download_category_scan_isolate_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/providers/download/download_scanner.dart';

void main() {
  group('downloaded category detail scan isolate support', () {
    test('scanFolderTrackDtosInIsolate returns transferable metadata DTOs', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'download_category_scan_isolate_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final videoDir = Directory('${tempDir.path}/yt-1_Test Video');
      await videoDir.create(recursive: true);
      await File('${videoDir.path}/audio.m4a').writeAsBytes([1, 2, 3]);
      await File('${videoDir.path}/metadata.json').writeAsString(
        jsonEncode({
          'sourceId': 'yt-1',
          'sourceType': 'youtube',
          'title': 'Test Video',
          'artist': 'Tester',
          'durationMs': 123000,
          'thumbnailUrl': 'https://img.example/thumb.jpg',
          'downloadedAt': '2026-04-25T12:00:00.000',
        }),
      );

      final dtos = await scanFolderTrackDtosInIsolate(
        ScanFolderTracksParams(tempDir.path),
      );
      final track = dtos.single.toTrack();

      expect(dtos, hasLength(1));
      expect(track.sourceId, 'yt-1');
      expect(track.sourceType, SourceType.youtube);
      expect(track.title, 'Test Video');
      expect(track.artist, 'Tester');
      expect(track.playlistInfo.single.downloadPath,
          '${videoDir.path}/audio.m4a');
    });

    test('downloadedCategoryTracksProvider uses Isolate.run entrypoint', () {
      final source = File(
        'lib/providers/download/download_providers.dart',
      ).readAsStringSync();

      expect(source, contains('Isolate.run'));
      expect(source, contains('scanFolderTrackDtosInIsolate'));
      expect(source, contains('ScanFolderTracksParams(folderPath)'));
      expect(
        source,
        isNot(contains('DownloadScanner.scanFolderForTracks(folderPath)')),
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests and verify they fail**

Run: `flutter test test/providers/download/download_category_scan_isolate_test.dart`
Expected: FAIL because `ScanFolderTracksParams` and `scanFolderTrackDtosInIsolate` do not exist, and `downloadedCategoryTracksProvider` still calls `DownloadScanner.scanFolderForTracks()` on the main isolate.

- [ ] **Step 3: Add transferable DTOs and isolate entrypoint**

In `lib/providers/download/download_scanner.dart`, after `ScanCategoriesParams`, add:

```dart
/// 参数类（用于 Isolate.run() 扫描单个下载分类详情）
class ScanFolderTracksParams {
  final String folderPath;
  const ScanFolderTracksParams(this.folderPath);
}

class DownloadedTrackDto {
  const DownloadedTrackDto({
    required this.sourceId,
    required this.sourceTypeName,
    required this.title,
    required this.audioPath,
    this.artist,
    this.durationMs,
    this.thumbnailUrl,
    this.cid,
    this.pageNum,
    this.pageCount,
    this.parentTitle,
    required this.createdAtIso,
  });

  final String sourceId;
  final String sourceTypeName;
  final String title;
  final String? artist;
  final int? durationMs;
  final String? thumbnailUrl;
  final int? cid;
  final int? pageNum;
  final int? pageCount;
  final String? parentTitle;
  final String audioPath;
  final String createdAtIso;

  Track toTrack() {
    final sourceType = SourceType.values.firstWhere(
      (e) => e.name == sourceTypeName,
      orElse: () => SourceType.bilibili,
    );
    return Track()
      ..sourceId = sourceId
      ..sourceType = sourceType
      ..title = title
      ..artist = artist
      ..durationMs = durationMs
      ..thumbnailUrl = thumbnailUrl
      ..cid = cid
      ..pageNum = pageNum
      ..pageCount = pageCount
      ..parentTitle = parentTitle
      ..playlistInfo = [
        PlaylistDownloadInfo()
          ..playlistId = 0
          ..downloadPath = audioPath,
      ]
      ..createdAt = DateTime.tryParse(createdAtIso) ?? DateTime.now();
  }
}
```

Add this top-level isolate entrypoint near `scanCategoriesInIsolate()`:

```dart
Future<List<DownloadedTrackDto>> scanFolderTrackDtosInIsolate(
  ScanFolderTracksParams params,
) {
  return DownloadScanner.scanFolderForTrackDtos(params.folderPath);
}
```

- [ ] **Step 4: Move scan internals to DTO-first scanning**

In `DownloadScanner`, replace `trackFromMetadata()` with DTO creation helpers:

```dart
  static DownloadedTrackDto? trackDtoFromMetadata(
    Map<String, dynamic> json,
    String audioPath,
  ) {
    try {
      final sourceTypeStr = json['sourceType'] as String?;
      if (sourceTypeStr == null) return null;

      return DownloadedTrackDto(
        sourceId: json['sourceId'] as String? ?? '',
        sourceTypeName: sourceTypeStr,
        title: json['title'] as String? ?? p.basenameWithoutExtension(audioPath),
        artist: json['artist'] as String?,
        durationMs: json['durationMs'] as int?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        cid: json['cid'] as int?,
        pageNum: json['pageNum'] as int?,
        pageCount: json['pageCount'] as int?,
        parentTitle: json['parentTitle'] as String?,
        audioPath: audioPath,
        createdAtIso: json['downloadedAt'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
```

Rename the old scan logic into a DTO method:

```dart
  static Future<List<DownloadedTrackDto>> scanFolderForTrackDtos(
    String folderPath,
  ) async {
    final folder = Directory(folderPath);
    if (!await folder.exists()) return [];

    final tracks = <DownloadedTrackDto>[];

    await for (final entity in folder.list()) {
      if (entity is Directory) {
        final folderName = p.basename(entity.path);
        final sourceIdFromFolder = extractSourceId(folderName);

        await for (final audioEntity in entity.list()) {
          if (audioEntity is! File || !audioEntity.path.endsWith('.m4a')) {
            continue;
          }

          DownloadedTrackDto? track;
          final fileName = p.basenameWithoutExtension(audioEntity.path);
          final newPageMatch = RegExp(r'^P(\d+)$').firstMatch(fileName);
          final oldPageMatch = RegExp(r'^P(\d+)\s*-\s*(.+)$').firstMatch(fileName);

          File? metadataFile;
          Map<String, dynamic>? metadata;

          if (newPageMatch != null) {
            final pageNumStr = newPageMatch.group(1)!;
            final pageMetadataFile =
                File(p.join(entity.path, 'metadata_P$pageNumStr.json'));
            final defaultMetadataFile = File(p.join(entity.path, 'metadata.json'));

            if (await pageMetadataFile.exists()) {
              metadataFile = pageMetadataFile;
            } else if (await defaultMetadataFile.exists()) {
              metadataFile = defaultMetadataFile;
            }
          } else {
            metadataFile = File(p.join(entity.path, 'metadata.json'));
          }

          if (metadataFile != null && await metadataFile.exists()) {
            try {
              final content = await metadataFile.readAsString();
              metadata = jsonDecode(content) as Map<String, dynamic>;
            } catch (_) {}
          }

          if (metadata != null) {
            track = trackDtoFromMetadata(metadata, audioEntity.path);
            if (track != null && newPageMatch != null) {
              track = DownloadedTrackDto(
                sourceId: track.sourceId,
                sourceTypeName: track.sourceTypeName,
                title: track.title,
                artist: track.artist,
                durationMs: track.durationMs,
                thumbnailUrl: track.thumbnailUrl,
                cid: track.cid,
                pageNum: int.tryParse(newPageMatch.group(1)!),
                pageCount: track.pageCount,
                parentTitle: track.parentTitle,
                audioPath: track.audioPath,
                createdAtIso: track.createdAtIso,
              );
            } else if (track != null && oldPageMatch != null) {
              track = DownloadedTrackDto(
                sourceId: track.sourceId,
                sourceTypeName: track.sourceTypeName,
                title: oldPageMatch.group(2)!,
                artist: track.artist,
                durationMs: track.durationMs,
                thumbnailUrl: track.thumbnailUrl,
                cid: track.cid,
                pageNum: int.tryParse(oldPageMatch.group(1)!),
                pageCount: track.pageCount,
                parentTitle: track.parentTitle,
                audioPath: track.audioPath,
                createdAtIso: track.createdAtIso,
              );
            }
          }

          track ??= DownloadedTrackDto(
            sourceId: sourceIdFromFolder ?? p.basename(entity.path),
            sourceTypeName: SourceType.bilibili.name,
            title: extractDisplayName(p.basename(entity.path)),
            audioPath: audioEntity.path,
            createdAtIso: DateTime.now().toIso8601String(),
          );

          tracks.add(track);
        }
      }
    }

    tracks.sort((a, b) {
      final groupCompare =
          (a.parentTitle ?? a.title).compareTo(b.parentTitle ?? b.title);
      if (groupCompare != 0) return groupCompare;
      return (a.pageNum ?? 0).compareTo(b.pageNum ?? 0);
    });

    return tracks;
  }

  static Future<List<Track>> scanFolderForTracks(String folderPath) async {
    final dtos = await scanFolderForTrackDtos(folderPath);
    return dtos.map((dto) => dto.toTrack()).toList();
  }
```

- [ ] **Step 5: Update the provider to use the isolate entrypoint**

In `lib/providers/download/download_providers.dart`, replace `downloadedCategoryTracksProvider` with:

```dart
final downloadedCategoryTracksProvider =
    FutureProvider.family<List<Track>, String>((ref, folderPath) async {
  final dtos = await Isolate.run(
    () => scanFolderTrackDtosInIsolate(ScanFolderTracksParams(folderPath)),
  );
  return dtos.map((dto) => dto.toTrack()).toList();
});
```

- [ ] **Step 6: Verify and commit**

Run: `dart format lib/providers/download/download_scanner.dart lib/providers/download/download_providers.dart test/providers/download/download_category_scan_isolate_test.dart`
Expected: files formatted.

Run: `flutter test test/providers/download/download_category_scan_isolate_test.dart`
Expected: PASS.

Run: `flutter test test/providers/download_providers_phase4_test.dart test/providers/download/download_event_handler_test.dart`
Expected: PASS.

Run: `git add lib/providers/download/download_scanner.dart lib/providers/download/download_providers.dart test/providers/download/download_category_scan_isolate_test.dart && git commit -m "perf(download): scan category details off ui isolate"`
Expected: commit succeeds.

---

### Task 3: Lazy Download Manager Rows

**Files:**
- Modify: `lib/ui/pages/settings/download_manager_page.dart:100-148`
- Modify: `test/ui/pages/settings/download_manager_page_phase4_test.dart`

- [ ] **Step 1: Extend the structural tests for flattened builder rows**

Append these tests to `test/ui/pages/settings/download_manager_page_phase4_test.dart` inside the existing group:

```dart
    test('download manager uses flattened builder rows for task sections', () {
      final source = File(
        '$repoRoot/lib/ui/pages/settings/download_manager_page.dart',
      ).readAsStringSync();

      expect(source, contains('class _DownloadListRow'));
      expect(source, contains('ListView.builder'));
      expect(source, contains('_buildRows('));
      expect(source, contains('_DownloadListRow.header'));
      expect(source, contains('_DownloadListRow.fixedDownloadingSection'));
      expect(source, contains('_DownloadListRow.task'));
      expect(source, isNot(contains('return ListView(\n            children:')));
      expect(source, isNot(contains('...pending.map')));
      expect(source, isNot(contains('...paused.map')));
      expect(source, isNot(contains('...failed.map')));
      expect(source, isNot(contains('...completed.map')));
    });
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `flutter test test/ui/pages/settings/download_manager_page_phase4_test.dart`
Expected: FAIL because `DownloadManagerPage` still builds grouped task sections with `ListView(children: [...map])` and no `_DownloadListRow` class exists.

- [ ] **Step 3: Add row model and row builder helpers**

In `lib/ui/pages/settings/download_manager_page.dart`, after `DownloadManagerPage`, add:

```dart
enum _DownloadListRowType { header, fixedDownloadingSection, task }

class _DownloadListRow {
  const _DownloadListRow._({
    required this.type,
    this.title,
    this.count,
    this.tasks,
    this.task,
    this.maxSlots,
  });

  const _DownloadListRow.header({
    required String title,
    required int count,
  }) : this._(
          type: _DownloadListRowType.header,
          title: title,
          count: count,
        );

  const _DownloadListRow.fixedDownloadingSection({
    required List<DownloadTask> tasks,
    required int maxSlots,
  }) : this._(
          type: _DownloadListRowType.fixedDownloadingSection,
          tasks: tasks,
          maxSlots: maxSlots,
        );

  const _DownloadListRow.task(DownloadTask task)
      : this._(
          type: _DownloadListRowType.task,
          task: task,
        );

  final _DownloadListRowType type;
  final String? title;
  final int? count;
  final List<DownloadTask>? tasks;
  final DownloadTask? task;
  final int? maxSlots;
}

List<_DownloadListRow> _buildRows({
  required List<DownloadTask> tasks,
  required int maxConcurrent,
}) {
  final downloading = tasks.where((task) => task.isDownloading).toList();
  final pending = tasks.where((task) => task.isPending).toList();
  final paused = tasks.where((task) => task.isPaused).toList();
  final failed = tasks.where((task) => task.isFailed).toList();
  final completed = tasks.where((task) => task.isCompleted).toList();

  final rows = <_DownloadListRow>[];
  if (downloading.isNotEmpty || pending.isNotEmpty) {
    rows.add(_DownloadListRow.header(
      title: t.settings.downloadManager.downloading,
      count: downloading.length,
    ));
    rows.add(_DownloadListRow.fixedDownloadingSection(
      tasks: downloading,
      maxSlots: maxConcurrent,
    ));
  }
  if (pending.isNotEmpty) {
    rows.add(_DownloadListRow.header(
      title: t.settings.downloadManager.waiting,
      count: pending.length,
    ));
    rows.addAll(pending.map(_DownloadListRow.task));
  }
  if (paused.isNotEmpty) {
    rows.add(_DownloadListRow.header(
      title: t.settings.downloadManager.paused,
      count: paused.length,
    ));
    rows.addAll(paused.map(_DownloadListRow.task));
  }
  if (failed.isNotEmpty) {
    rows.add(_DownloadListRow.header(
      title: t.settings.downloadManager.failed,
      count: failed.length,
    ));
    rows.addAll(failed.map(_DownloadListRow.task));
  }
  if (completed.isNotEmpty) {
    rows.add(_DownloadListRow.header(
      title: t.settings.downloadManager.completed,
      count: completed.length,
    ));
    rows.addAll(completed.map(_DownloadListRow.task));
  }
  return rows;
}
```

- [ ] **Step 4: Replace the eager `ListView(children)` section**

In `DownloadManagerPage.build()`, replace the grouped lists and `return ListView(children: [...])` block with:

```dart
          final maxConcurrent = ref.watch(maxConcurrentDownloadsProvider);
          final rows = _buildRows(
            tasks: tasks,
            maxConcurrent: maxConcurrent,
          );

          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              switch (row.type) {
                case _DownloadListRowType.header:
                  return _SectionHeader(
                    title: row.title!,
                    count: row.count!,
                  );
                case _DownloadListRowType.fixedDownloadingSection:
                  return _FixedHeightDownloadingSection(
                    tasks: row.tasks!,
                    maxSlots: row.maxSlots!,
                  );
                case _DownloadListRowType.task:
                  return _DownloadTaskTile(task: row.task!);
              }
            },
          );
```

Do not change `_FixedHeightDownloadingSection`, `_SectionHeader`, or `_DownloadTaskTile` behavior.

- [ ] **Step 5: Verify and commit**

Run: `dart format lib/ui/pages/settings/download_manager_page.dart test/ui/pages/settings/download_manager_page_phase4_test.dart`
Expected: files formatted.

Run: `flutter test test/ui/pages/settings/download_manager_page_phase4_test.dart`
Expected: PASS.

Run: `flutter test test/providers/download_providers_phase4_test.dart`
Expected: PASS.

Run: `git add lib/ui/pages/settings/download_manager_page.dart test/ui/pages/settings/download_manager_page_phase4_test.dart && git commit -m "perf(download): lazily build manager rows"`
Expected: commit succeeds.

---

### Task 4: Data Integrity Scan and Repair Service

**Files:**
- Create: `lib/services/database/data_integrity_service.dart`
- Create: `test/services/database/data_integrity_service_test.dart`

- [ ] **Step 1: Write the failing duplicate scan/repair tests**

Create `test/services/database/data_integrity_service_test.dart`:

```dart
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/account.dart';
import 'package:fmp/data/models/download_task.dart';
import 'package:fmp/data/models/play_queue.dart';
import 'package:fmp/data/models/playlist.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/services/database/data_integrity_service.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DataIntegrityService', () {
    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    test('scan reports duplicate logical records without modifying data', () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      await harness.seedDuplicates();

      final report = await harness.service.scan();

      expect(report.duplicateTrackKeys, contains('youtube:same'));
      expect(report.duplicateDownloadSavePaths,
          contains('/downloads/Playlist/Song/audio.m4a'));
      expect(report.duplicateAccountPlatforms, contains(SourceType.youtube));
      expect(report.playQueueCount, 2);
      expect(report.hasIssues, isTrue);

      final tracks = await harness.isar.tracks.where().findAll();
      final tasks = await harness.isar.downloadTasks.where().findAll();
      final accounts = await harness.isar.accounts.where().findAll();
      final queues = await harness.isar.playQueues.where().findAll();
      expect(tracks, hasLength(3));
      expect(tasks, hasLength(2));
      expect(accounts, hasLength(2));
      expect(queues, hasLength(2));
    });

    test('repair merges or removes duplicates using deterministic keep rules',
        () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);

      await harness.seedDuplicates();

      final result = await harness.service.repair();

      expect(result.removedTrackIds, hasLength(1));
      expect(result.removedDownloadTaskIds, hasLength(1));
      expect(result.removedAccountIds, hasLength(1));
      expect(result.removedPlayQueueIds, hasLength(1));

      final report = await harness.service.scan();
      expect(report.hasIssues, isFalse);

      await harness.service.repair();
      final secondReport = await harness.service.scan();
      expect(secondReport.hasIssues, isFalse);

      final tracks = await harness.isar.tracks.where().findAll();
      expect(tracks, hasLength(2));
      expect(tracks.map((track) => track.title),
          containsAll(['Complete Track', 'Other Track']));
      final keptTrack = tracks.singleWhere((track) => track.sourceId == 'same');
      expect(keptTrack.title, 'Complete Track');
      expect(keptTrack.thumbnailUrl, 'https://img.example/cover.jpg');

      final playlists = await harness.isar.playlists.where().findAll();
      expect(playlists.single.trackIds, [keptTrack.id]);
      expect(playlists.single.trackIds,
          isNot(contains(harness.trackIdsByTitle['Sparse Track'])));

      final tasks = await harness.isar.downloadTasks.where().findAll();
      expect(tasks, hasLength(1));
      expect(tasks.single.status, DownloadStatus.completed);
      expect(tasks.single.trackId, keptTrack.id);

      final accounts = await harness.isar.accounts.where().findAll();
      expect(accounts, hasLength(1));
      expect(accounts.single.isLoggedIn, isTrue);
      expect(accounts.single.userName, 'Logged In');

      final queues = await harness.isar.playQueues.where().findAll();
      expect(queues, hasLength(1));
      expect(queues.single.trackIds, [
        keptTrack.id,
        harness.trackIdsByTitle['Other Track'],
      ]);
    });
  });
}

class _Harness {
  _Harness(this.isar) : service = DataIntegrityService(isar);

  final Isar isar;
  final DataIntegrityService service;
  final trackIdsByTitle = <String, int>{};

  Future<void> seedDuplicates() async {
    await isar.writeTxn(() async {
      final trackIds = await isar.tracks.putAll([
        Track()
          ..sourceId = 'same'
          ..sourceType = SourceType.youtube
          ..title = 'Sparse Track'
          ..createdAt = DateTime(2026, 4, 24),
        Track()
          ..sourceId = 'same'
          ..sourceType = SourceType.youtube
          ..title = 'Complete Track'
          ..thumbnailUrl = 'https://img.example/cover.jpg'
          ..durationMs = 180000
          ..createdAt = DateTime(2026, 4, 25),
        Track()
          ..sourceId = 'other'
          ..sourceType = SourceType.youtube
          ..title = 'Other Track'
          ..createdAt = DateTime(2026, 4, 25),
      ]);
      final sparseTrackId = trackIds[0];
      final completeTrackId = trackIds[1];
      final otherTrackId = trackIds[2];
      trackIdsByTitle['Sparse Track'] = sparseTrackId;
      trackIdsByTitle['Complete Track'] = completeTrackId;
      trackIdsByTitle['Other Track'] = otherTrackId;

      await isar.playlists.put(Playlist()
        ..name = 'Mixed Playlist'
        ..trackIds = [sparseTrackId, completeTrackId]
        ..createdAt = DateTime(2026, 4, 25));
      await isar.downloadTasks.putAll([
        DownloadTask()
          ..trackId = sparseTrackId
          ..savePath = '/downloads/Playlist/Song/audio.m4a'
          ..status = DownloadStatus.pending
          ..createdAt = DateTime(2026, 4, 24),
        DownloadTask()
          ..trackId = sparseTrackId
          ..savePath = '/downloads/Playlist/Song/audio.m4a'
          ..status = DownloadStatus.completed
          ..createdAt = DateTime(2026, 4, 25)
          ..completedAt = DateTime(2026, 4, 25, 1),
      ]);
      await isar.accounts.putAll([
        Account()
          ..platform = SourceType.youtube
          ..isLoggedIn = false
          ..userName = 'Logged Out'
          ..lastRefreshed = DateTime(2026, 4, 24),
        Account()
          ..platform = SourceType.youtube
          ..isLoggedIn = true
          ..userName = 'Logged In'
          ..lastRefreshed = DateTime(2026, 4, 25),
      ]);
      await isar.playQueues.putAll([
        PlayQueue()
          ..trackIds = [sparseTrackId]
          ..lastUpdated = DateTime(2026, 4, 24),
        PlayQueue()
          ..trackIds = [sparseTrackId, completeTrackId, otherTrackId]
          ..lastUpdated = DateTime(2026, 4, 25),
      ]);
    });
  }

  Future<void> dispose() async {
    final dir = Directory(isar.directory!);
    await isar.close(deleteFromDisk: true);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

Future<_Harness> _createHarness() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'data_integrity_service_test_',
  );
  final isar = await Isar.open(
    [
      TrackSchema,
      PlaylistSchema,
      DownloadTaskSchema,
      AccountSchema,
      PlayQueueSchema,
    ],
    directory: tempDir.path,
    name: 'data_integrity_service_test',
  );
  return _Harness(isar);
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfigFile =
      File('${Directory.current.path}/.dart_tool/package_config.json');
  final packageConfig =
      jsonDecode(await packageConfigFile.readAsString()) as Map<String, dynamic>;
  final packages = packageConfig['packages'] as List<dynamic>;
  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');

  for (final package in packages) {
    if (package is! Map<String, dynamic> ||
        package['name'] != 'isar_flutter_libs') {
      continue;
    }
    final packageDir = Directory(
      packageConfigDir.uri.resolve(package['rootUri'] as String).toFilePath(),
    );
    if (Platform.isWindows) return '${packageDir.path}/windows/isar.dll';
    if (Platform.isLinux) return '${packageDir.path}/linux/libisar.so';
    if (Platform.isMacOS) return '${packageDir.path}/macos/libisar.dylib';
  }

  throw StateError('Unsupported platform for Isar test setup');
}
```

- [ ] **Step 2: Run the tests and verify they fail**

Run: `flutter test test/services/database/data_integrity_service_test.dart`
Expected: FAIL because `lib/services/database/data_integrity_service.dart` does not exist.

- [ ] **Step 3: Create report and repair result types**

Create `lib/services/database/data_integrity_service.dart`:

```dart
import 'package:isar/isar.dart';

import '../../data/models/account.dart';
import '../../data/models/download_task.dart';
import '../../data/models/play_queue.dart';
import '../../data/models/playlist.dart';
import '../../data/models/track.dart';

class DataIntegrityReport {
  const DataIntegrityReport({
    required this.duplicateTrackKeys,
    required this.duplicateDownloadSavePaths,
    required this.duplicateAccountPlatforms,
    required this.playQueueCount,
  });

  final List<String> duplicateTrackKeys;
  final List<String> duplicateDownloadSavePaths;
  final List<SourceType> duplicateAccountPlatforms;
  final int playQueueCount;

  bool get hasIssues =>
      duplicateTrackKeys.isNotEmpty ||
      duplicateDownloadSavePaths.isNotEmpty ||
      duplicateAccountPlatforms.isNotEmpty ||
      playQueueCount > 1;
}

class DataIntegrityRepairResult {
  const DataIntegrityRepairResult({
    required this.removedTrackIds,
    required this.removedDownloadTaskIds,
    required this.removedAccountIds,
    required this.removedPlayQueueIds,
  });

  final List<int> removedTrackIds;
  final List<int> removedDownloadTaskIds;
  final List<int> removedAccountIds;
  final List<int> removedPlayQueueIds;
}
```

- [ ] **Step 4: Implement scanning and deterministic repair**

In the same file, below the result types, add:

```dart
class DataIntegrityService {
  DataIntegrityService(this._isar);

  final Isar _isar;

  Future<DataIntegrityReport> scan() async {
    final tracks = await _isar.tracks.where().findAll();
    final tasks = await _isar.downloadTasks.where().findAll();
    final accounts = await _isar.accounts.where().findAll();
    final queues = await _isar.playQueues.where().findAll();

    return DataIntegrityReport(
      duplicateTrackKeys: _duplicateKeys(
        tracks,
        (track) => track.uniqueKey,
      ),
      duplicateDownloadSavePaths: _duplicateKeys(
        tasks.where((task) => task.savePath != null && task.savePath!.isNotEmpty),
        (task) => task.savePath!,
      ),
      duplicateAccountPlatforms: _duplicateKeys(
        accounts,
        (account) => account.platform,
      ),
      playQueueCount: queues.length,
    );
  }

  Future<DataIntegrityRepairResult> repair() async {
    final removedTrackIds = <int>[];
    final removedDownloadTaskIds = <int>[];
    final removedAccountIds = <int>[];
    final removedPlayQueueIds = <int>[];

    await _isar.writeTxn(() async {
      final trackIdRemap = <int, int>{};
      final tracks = await _isar.tracks.where().findAll();
      for (final duplicateGroup in _duplicateGroups(
        tracks,
        (track) => track.uniqueKey,
      )) {
        final keep = duplicateGroup.reduce(_preferTrack);
        final remove =
            duplicateGroup.where((track) => track.id != keep.id).toList();
        for (final track in remove) {
          trackIdRemap[track.id] = keep.id;
        }
        removedTrackIds.addAll(remove.map((track) => track.id));
      }
      await _remapTrackReferences(trackIdRemap);
      await _isar.tracks.deleteAll(removedTrackIds);

      final tasks = await _isar.downloadTasks.where().findAll();
      for (final duplicateGroup in _duplicateGroups(
        tasks.where(
          (task) => task.savePath != null && task.savePath!.isNotEmpty,
        ),
        (task) => task.savePath!,
      )) {
        final keep = duplicateGroup.reduce(_preferDownloadTask);
        final remove =
            duplicateGroup.where((task) => task.id != keep.id).toList();
        removedDownloadTaskIds.addAll(remove.map((task) => task.id));
        await _isar.downloadTasks.deleteAll(
          remove.map((task) => task.id).toList(),
        );
      }

      final accounts = await _isar.accounts.where().findAll();
      for (final duplicateGroup in _duplicateGroups(
        accounts,
        (account) => account.platform,
      )) {
        final keep = duplicateGroup.reduce(_preferAccount);
        final remove =
            duplicateGroup.where((account) => account.id != keep.id).toList();
        removedAccountIds.addAll(remove.map((account) => account.id));
        await _isar.accounts.deleteAll(
          remove.map((account) => account.id).toList(),
        );
      }

      final queues = await _isar.playQueues.where().findAll();
      if (queues.length > 1) {
        final keep = queues.reduce(_preferPlayQueue);
        final remove = queues.where((queue) => queue.id != keep.id).toList();
        removedPlayQueueIds.addAll(remove.map((queue) => queue.id));
        await _isar.playQueues.deleteAll(
          remove.map((queue) => queue.id).toList(),
        );
      }
    });

    return DataIntegrityRepairResult(
      removedTrackIds: removedTrackIds,
      removedDownloadTaskIds: removedDownloadTaskIds,
      removedAccountIds: removedAccountIds,
      removedPlayQueueIds: removedPlayQueueIds,
    );
  }

  Future<void> _remapTrackReferences(Map<int, int> remap) async {
    if (remap.isEmpty) return;

    final playlists = await _isar.playlists.where().findAll();
    for (final playlist in playlists) {
      playlist.trackIds = _remapAndDedupeIds(playlist.trackIds, remap);
    }
    await _isar.playlists.putAll(playlists);

    final tasks = await _isar.downloadTasks.where().findAll();
    for (final task in tasks) {
      task.trackId = remap[task.trackId] ?? task.trackId;
    }
    await _isar.downloadTasks.putAll(tasks);

    final queues = await _isar.playQueues.where().findAll();
    for (final queue in queues) {
      queue.trackIds = _remapAndDedupeIds(queue.trackIds, remap);
    }
    await _isar.playQueues.putAll(queues);
  }

  static List<int> _remapAndDedupeIds(List<int> ids, Map<int, int> remap) {
    final result = <int>[];
    final seen = <int>{};
    for (final id in ids) {
      final mapped = remap[id] ?? id;
      if (seen.add(mapped)) {
        result.add(mapped);
      }
    }
    return result;
  }

  static List<K> _duplicateKeys<T, K>(
    Iterable<T> items,
    K Function(T item) keyOf,
  ) {
    return _duplicateGroups(items, keyOf)
        .map((group) => keyOf(group.first))
        .toList();
  }

  static List<List<T>> _duplicateGroups<T, K>(
    Iterable<T> items,
    K Function(T item) keyOf,
  ) {
    final groups = <K, List<T>>{};
    for (final item in items) {
      groups.putIfAbsent(keyOf(item), () => <T>[]).add(item);
    }
    return groups.values.where((group) => group.length > 1).toList();
  }

  static Track _preferTrack(Track a, Track b) {
    final scoreA = _trackCompletenessScore(a);
    final scoreB = _trackCompletenessScore(b);
    if (scoreA != scoreB) return scoreA > scoreB ? a : b;
    return (a.updatedAt ?? a.createdAt).isAfter(b.updatedAt ?? b.createdAt)
        ? a
        : b;
  }

  static int _trackCompletenessScore(Track track) {
    var score = 0;
    if (track.audioUrl != null && track.audioUrl!.isNotEmpty) score += 8;
    if (track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty) score += 4;
    if (track.durationMs != null && track.durationMs! > 0) score += 2;
    if (track.artist != null && track.artist!.isNotEmpty) score += 1;
    if (track.playlistInfo.isNotEmpty) score += 1;
    return score;
  }

  static DownloadTask _preferDownloadTask(DownloadTask a, DownloadTask b) {
    final scoreA = _downloadTaskScore(a);
    final scoreB = _downloadTaskScore(b);
    if (scoreA != scoreB) return scoreA > scoreB ? a : b;
    return a.createdAt.isAfter(b.createdAt) ? a : b;
  }

  static int _downloadTaskScore(DownloadTask task) {
    switch (task.status) {
      case DownloadStatus.completed:
        return 4;
      case DownloadStatus.downloading:
        return 3;
      case DownloadStatus.pending:
        return 2;
      case DownloadStatus.paused:
        return 1;
      case DownloadStatus.failed:
        return 0;
    }
  }

  static Account _preferAccount(Account a, Account b) {
    if (a.isLoggedIn != b.isLoggedIn) {
      return a.isLoggedIn ? a : b;
    }
    final refreshedA =
        a.lastRefreshed ?? a.loginAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final refreshedB =
        b.lastRefreshed ?? b.loginAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return refreshedA.isAfter(refreshedB) ? a : b;
  }

  static PlayQueue _preferPlayQueue(PlayQueue a, PlayQueue b) {
    final updatedA = a.lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(0);
    final updatedB = b.lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(0);
    if (!updatedA.isAtSameMomentAs(updatedB)) {
      return updatedA.isAfter(updatedB) ? a : b;
    }
    return a.trackIds.length >= b.trackIds.length ? a : b;
  }
}
```

- [ ] **Step 5: Verify and commit**

Run: `dart format lib/services/database/data_integrity_service.dart test/services/database/data_integrity_service_test.dart`
Expected: files formatted.

Run: `flutter test test/services/database/data_integrity_service_test.dart`
Expected: PASS.

Run: `flutter test test/providers/database_migration_test.dart test/data/repositories/play_history_repository_phase4_test.dart`
Expected: PASS.

Run: `git add lib/services/database/data_integrity_service.dart test/services/database/data_integrity_service_test.dart && git commit -m "feat(database): add integrity scan and repair service"`
Expected: commit succeeds.

---

### Task 5: Phase 4 Validation

**Files:**
- Test only: focused Phase 4 tests and analyzer.

- [ ] **Step 1: Run all Phase 4 focused tests**

Run:

```bash
flutter test test/providers/lyrics_current_line_provider_test.dart test/providers/download/download_category_scan_isolate_test.dart test/ui/pages/settings/download_manager_page_phase4_test.dart test/services/database/data_integrity_service_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run related regression tests**

Run:

```bash
flutter test test/services/lyrics/lyrics_auto_match_service_phase4_test.dart test/providers/download_providers_phase4_test.dart test/providers/download/download_event_handler_test.dart test/services/download/download_completion_transaction_test.dart test/providers/database_migration_test.dart test/data/repositories/play_history_repository_phase4_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Inspect git diff scope**

Run: `git diff --stat HEAD~4..HEAD`
Expected: only Phase 4 files from this plan are present, with no generated Isar schema changes.

Run: `git status --short`
Expected: clean working tree after the final validation commit, or only intentionally uncommitted plan/task metadata if the executor was told not to commit.

- [ ] **Step 5: Commit final validation notes if needed**

If validation required a code fix, commit the fix with a conventional message after rerunning the failing command. If no code changed, do not create an empty commit.
