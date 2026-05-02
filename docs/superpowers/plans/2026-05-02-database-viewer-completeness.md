# Database Viewer Completeness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the developer database viewer list every current Isar collection and expose all model fields/getters useful for debugging, then document the maintenance rule.

**Architecture:** Keep the existing hand-written per-collection viewer in `database_viewer_page.dart`. Add missing collection views for `Account` and `LyricsTitleParseCache`, then patch existing sections with missing fields/getters. Add a source-level coverage test so future schema additions are less likely to miss the viewer.

**Tech Stack:** Flutter, Dart, Riverpod, Isar, flutter_test.

---

## File Structure

- Modify: `lib/ui/pages/settings/database_viewer_page.dart` — collection selector, switch, imports, per-table display sections.
- Modify: `CLAUDE.md` — database maintenance guidance.
- Create: `test/ui/pages/settings/database_viewer_page_coverage_test.dart` — source-level guard for collection and field visibility.

### Task 1: Add failing database viewer coverage test

**Files:**
- Create: `test/ui/pages/settings/database_viewer_page_coverage_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const viewerPath = 'lib/ui/pages/settings/database_viewer_page.dart';
  const databaseProviderPath = 'lib/providers/database_provider.dart';

  String read(String path) => File(path).readAsStringSync();

  test('database viewer lists every opened Isar collection', () {
    final provider = read(databaseProviderPath);
    final viewer = read(viewerPath);
    final schemas = RegExp(r'^\s*([A-Za-z0-9_]+)Schema,', multiLine: true)
        .allMatches(provider)
        .map((match) => match.group(1)!)
        .toSet();

    expect(
      schemas,
      containsAll(<String>{
        'Track',
        'Playlist',
        'PlayQueue',
        'Settings',
        'SearchHistory',
        'DownloadTask',
        'PlayHistory',
        'RadioStation',
        'LyricsMatch',
        'LyricsTitleParseCache',
        'Account',
      }),
    );

    for (final collection in schemas) {
      expect(viewer, contains("'$collection'"), reason: '$collection is missing from _collections');
      expect(viewer, contains('_${collection}ListView'), reason: '$collection is missing a list view');
    }
  });

  test('database viewer exposes current model fields and debug getters', () {
    final viewer = read(viewerPath);
    const expectedTokens = <String>{
      'bilibiliAid',
      'uniqueKey',
      'groupKey',
      'formattedDuration',
      'lyricsDisplayModeIndex',
      'lyricsDisplayMode',
      'lyricsSourcePriority',
      'lyricsSourcePriorityList',
      'disabledLyricsSources',
      'disabledLyricsSourcesSet',
      'lyricsAiTitleParsingModeIndex',
      'lyricsAiTitleParsingMode',
      'lyricsAiEndpoint',
      'lyricsAiModel',
      'lyricsAiTimeoutSeconds',
      'rankingRefreshIntervalMinutes',
      'radioRefreshIntervalMinutes',
      'audioFormatPriorityList',
      'youtubeStreamPriorityList',
      'bilibiliStreamPriorityList',
      'neteaseStreamPriorityList',
      'isDownloading',
      'isCompleted',
      'isFailed',
      'isPending',
      'isPaused',
      'isPartOfPlaylist',
      'formattedProgress',
      'trackCount',
      'uniqueKey',
      'LyricsTitleParseCache',
      'parsedTrackName',
      'parsedArtistName',
      'confidence',
      'provider',
      'model',
      'Account',
      'platform',
      'userId',
      'userName',
      'avatarUrl',
      'isLoggedIn',
      'lastRefreshed',
      'loginAt',
      'isVip',
    };

    for (final token in expectedTokens) {
      expect(viewer, contains("'$token'"), reason: '$token is not displayed by the database viewer');
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/pages/settings/database_viewer_page_coverage_test.dart`
Expected: FAIL because `Account`, `LyricsTitleParseCache`, and several field tokens are not yet displayed.

### Task 2: Add missing Isar collections to the viewer

**Files:**
- Modify: `lib/ui/pages/settings/database_viewer_page.dart:8-17,30-40,116-128`

- [ ] **Step 1: Add imports**

Add these imports near the existing model imports:

```dart
import '../../../data/models/account.dart';
import '../../../data/models/lyrics_title_parse_cache.dart';
```

- [ ] **Step 2: Add selector and switch cases**

Add these names to `_collections` after `LyricsMatch`:

```dart
'LyricsTitleParseCache',
'Account',
```

Add these cases to `_buildCollectionData` after `LyricsMatch`:

```dart
'LyricsTitleParseCache' => _LyricsTitleParseCacheListView(isar: isar),
'Account' => _AccountListView(isar: isar),
```

- [ ] **Step 3: Add missing list view classes**

Insert before `_truncate`:

```dart
class _LyricsTitleParseCacheListView extends StatelessWidget {
  final Isar isar;

  const _LyricsTitleParseCacheListView({required this.isar});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LyricsTitleParseCache>>(
      future: isar.lyricsTitleParseCaches.where().findAll(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final caches = snapshot.data ?? [];
        return _buildList(
          context,
          itemCount: caches.length,
          headerText: t.databaseViewer.recordCount(count: caches.length),
          itemBuilder: (index) {
            final cache = caches[index];
            return _DataCard(
              title: cache.parsedTrackName,
              subtitle: 'ID: ${cache.id} | ${cache.trackUniqueKey}',
              sections: [
                _DataSection(title: t.databaseViewer.basicInfo, data: {
                  'id': cache.id.toString(),
                  'trackUniqueKey': cache.trackUniqueKey,
                  'sourceType': cache.sourceType,
                }),
                _DataSection(title: 'Parsed Result', data: {
                  'parsedTrackName': cache.parsedTrackName,
                  'parsedArtistName': cache.parsedArtistName ?? 'null',
                  'confidence': cache.confidence.toStringAsFixed(3),
                  'provider': cache.provider,
                  'model': cache.model,
                }),
                _DataSection(title: t.databaseViewer.timestamps, data: {
                  'createdAt': cache.createdAt.toIso8601String(),
                  'updatedAt': cache.updatedAt.toIso8601String(),
                }),
              ],
            );
          },
        );
      },
    );
  }
}

class _AccountListView extends StatelessWidget {
  final Isar isar;

  const _AccountListView({required this.isar});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Account>>(
      future: isar.accounts.where().findAll(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final accounts = snapshot.data ?? [];
        return _buildList(
          context,
          itemCount: accounts.length,
          headerText: t.databaseViewer.recordCount(count: accounts.length),
          itemBuilder: (index) {
            final account = accounts[index];
            return _DataCard(
              title: account.userName ?? account.platform.name,
              subtitle: 'ID: ${account.id} | ${account.platform.name}',
              sections: [
                _DataSection(title: t.databaseViewer.basicInfo, data: {
                  'id': account.id.toString(),
                  'platform': account.platform.name,
                  'userId': account.userId ?? 'null',
                  'userName': account.userName ?? 'null',
                  'avatarUrl': _truncate(account.avatarUrl, 60),
                }),
                _DataSection(title: 'Login State', data: {
                  'isLoggedIn': account.isLoggedIn.toString(),
                  'isVip': account.isVip.toString(),
                  'lastRefreshed': account.lastRefreshed?.toIso8601String() ?? 'null',
                  'loginAt': account.loginAt?.toIso8601String() ?? 'null',
                }),
              ],
            );
          },
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run focused test**

Run: `flutter test test/ui/pages/settings/database_viewer_page_coverage_test.dart`
Expected: still FAIL only for missing existing-view field tokens.

### Task 3: Complete existing table field/getter coverage

**Files:**
- Modify: `lib/ui/pages/settings/database_viewer_page.dart`

- [ ] **Step 1: Patch `Track` sections**

Add these entries in the existing `Track` card: add `'bilibiliAid'` to `partInfo`, and add a new computed section after timestamps.

```dart
'bilibiliAid': track.bilibiliAid?.toString() ?? 'null',
```

```dart
_DataSection(
  title: 'Computed',
  data: {
    'uniqueKey': track.uniqueKey,
    'groupKey': track.groupKey,
    'formattedDuration': track.formattedDuration,
  },
),
```

- [ ] **Step 2: Patch `Settings` sections**

Extend `audioQualitySettings`, `lyricsSettings`, and `otherSettings`; add refresh settings.

```dart
'audioFormatPriorityList': setting.audioFormatPriorityList.map((e) => e.name).join(', '),
'youtubeStreamPriorityList': setting.youtubeStreamPriorityList.map((e) => e.name).join(', '),
'bilibiliStreamPriorityList': setting.bilibiliStreamPriorityList.map((e) => e.name).join(', '),
'neteaseStreamPriorityList': setting.neteaseStreamPriorityList.map((e) => e.name).join(', '),
```

```dart
'lyricsDisplayModeIndex': setting.lyricsDisplayModeIndex.toString(),
'lyricsDisplayMode': setting.lyricsDisplayMode.name,
'lyricsSourcePriority': setting.lyricsSourcePriority,
'lyricsSourcePriorityList': setting.lyricsSourcePriorityList.join(', '),
'disabledLyricsSources': setting.disabledLyricsSources,
'disabledLyricsSourcesSet': setting.disabledLyricsSourcesSet.join(', '),
'lyricsAiTitleParsingModeIndex': setting.lyricsAiTitleParsingModeIndex.toString(),
'lyricsAiTitleParsingMode': setting.lyricsAiTitleParsingMode.name,
'lyricsAiEndpoint': setting.lyricsAiEndpoint,
'lyricsAiModel': setting.lyricsAiModel,
'lyricsAiTimeoutSeconds': '${setting.lyricsAiTimeoutSeconds}s',
```

```dart
_DataSection(
  title: 'Refresh Settings',
  data: {
    'rankingRefreshIntervalMinutes': '${setting.rankingRefreshIntervalMinutes} min',
    'radioRefreshIntervalMinutes': '${setting.radioRefreshIntervalMinutes} min',
  },
),
```

- [ ] **Step 3: Patch remaining computed values**

Add these entries to existing cards where their objects are already in scope.

```dart
// Playlist trackList section
'trackCount': playlist.trackCount.toString(),

// DownloadTask status/file sections
'isDownloading': task.isDownloading.toString(),
'isCompleted': task.isCompleted.toString(),
'isFailed': task.isFailed.toString(),
'isPending': task.isPending.toString(),
'isPaused': task.isPaused.toString(),
'formattedProgress': task.formattedProgress,
'isPartOfPlaylist': task.isPartOfPlaylist.toString(),

// RadioStation basicInfo section
'uniqueKey': station.uniqueKey,
```

- [ ] **Step 4: Run focused test**

Run: `flutter test test/ui/pages/settings/database_viewer_page_coverage_test.dart`
Expected: PASS.

### Task 4: Update CLAUDE.md and run validation

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add database viewer maintenance rule**

In the `Database Migration (Isar)` section, add this rule after the new-field checklist:

```markdown
**Database viewer maintenance:** When adding, removing, or changing an Isar collection, persisted field, embedded object, or schema registration in `database_provider.dart`, update `lib/ui/pages/settings/database_viewer_page.dart` in the same change so the developer database viewer remains complete.
```

- [ ] **Step 2: Run full validation**

Run: `flutter test test/ui/pages/settings/database_viewer_page_coverage_test.dart`
Expected: PASS.

Run: `flutter analyze`
Expected: no new issues.

- [ ] **Step 3: Check git status, but do not commit unless explicitly requested**

Run: `git status --short`
Expected changed files: `CLAUDE.md`, `lib/ui/pages/settings/database_viewer_page.dart`, `test/ui/pages/settings/database_viewer_page_coverage_test.dart`, and this plan/spec if uncommitted.

---

## Self-Review

- Spec coverage: all opened Isar collections are represented; missing `Account` and `LyricsTitleParseCache` get dedicated views; existing views get missing model fields/getters; `CLAUDE.md` gains the maintenance rule.
- Placeholder scan: no TBD/TODO/future placeholders.
- Type consistency: collection names match `database_provider.dart`; extension getters use existing model property names from current source files.
