# YouTube Mix Shorthand Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Commit steps are checkpoints; execute them only after explicit user authorization for commits.

**Goal:** Let the library playlist import dialog accept `mix:<youtube-video-id>` and create the equivalent YouTube Mix playlist.

**Architecture:** Add one focused shorthand parser/normalizer shared by UI and service code. The dialog uses it for detection/validation; `ImportService.importFromUrl()` normalizes shorthand before existing source detection so all existing YouTube Mix import logic is reused.

**Tech Stack:** Flutter, Dart, Riverpod, Isar, existing `ImportService`, existing `YouTubeSource` Mix import.

---

## File Structure

- Create: `lib/services/import/youtube_mix_shorthand.dart`
  - Owns `mix:` detection, seed validation, and normalized YouTube Mix URL generation.
- Create: `test/services/import/youtube_mix_shorthand_test.dart`
  - Unit tests for shorthand parsing and normalization.
- Modify: `lib/services/import/import_service.dart`
  - Normalize shorthand before source detection and use the normalized URL for import persistence.
- Modify: `test/services/import/import_service_phase4_test.dart`
  - Add tests that prove shorthand normalizes before YouTube Mix import and stores normalized `sourceUrl`.
- Modify: `lib/ui/pages/library/widgets/import_playlist_dialog.dart`
  - Detect valid shorthand as internal YouTube and reject invalid shorthand in validation.

### Task 1: Add shared shorthand parser

**Files:**
- Create: `lib/services/import/youtube_mix_shorthand.dart`
- Create: `test/services/import/youtube_mix_shorthand_test.dart`

- [ ] **Step 1: Write failing parser tests**

Create `test/services/import/youtube_mix_shorthand_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/import/youtube_mix_shorthand.dart';

void main() {
  group('YouTube Mix shorthand', () {
    test('parses lowercase, uppercase, and whitespace padded shorthand', () {
      expect(parseYouTubeMixShorthandSeedId('mix:dvgZkm1xWPE'), 'dvgZkm1xWPE');
      expect(parseYouTubeMixShorthandSeedId('MIX:dvgZkm1xWPE'), 'dvgZkm1xWPE');
      expect(parseYouTubeMixShorthandSeedId('  mix:dvgZkm1xWPE  '), 'dvgZkm1xWPE');
      expect(parseYouTubeMixShorthandSeedId('mix: dvgZkm1xWPE'), 'dvgZkm1xWPE');
    });

    test('rejects empty, invalid character, and overly long seeds', () {
      expect(looksLikeYouTubeMixShorthand('mix:'), isTrue);
      expect(parseYouTubeMixShorthandSeedId('mix:'), isNull);
      expect(parseYouTubeMixShorthandSeedId('mix:dvgZkm1xWPE!'), isNull);
      expect(parseYouTubeMixShorthandSeedId('mix:${'a' * 65}'), isNull);
      expect(parseYouTubeMixShorthandSeedId('https://www.youtube.com/watch?v=dvgZkm1xWPE'), isNull);
    });

    test('normalizes valid shorthand to a YouTube Mix URL', () {
      expect(
        normalizeYouTubeMixShorthandUrl(' MIX:dvgZkm1xWPE '),
        'https://www.youtube.com/watch?v=dvgZkm1xWPE&list=RDdvgZkm1xWPE',
      );
      expect(normalizeYouTubeMixShorthandUrl('mix:dvgZkm1xWPE!'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test and verify failure**

Run: `flutter test test/services/import/youtube_mix_shorthand_test.dart`
Expected: FAIL because `youtube_mix_shorthand.dart` does not exist.

- [ ] **Step 3: Implement parser**

Create `lib/services/import/youtube_mix_shorthand.dart`:

```dart
const int youtubeMixShorthandMaxSeedLength = 64;
final RegExp _youtubeMixSeedIdPattern = RegExp(r'^[A-Za-z0-9_-]+$');

bool looksLikeYouTubeMixShorthand(String input) {
  return input.trim().toLowerCase().startsWith('mix:');
}

String? parseYouTubeMixShorthandSeedId(String input) {
  final trimmed = input.trim();
  if (!looksLikeYouTubeMixShorthand(trimmed)) return null;

  final seedId = trimmed.substring(4).trim();
  if (seedId.isEmpty || seedId.length > youtubeMixShorthandMaxSeedLength) {
    return null;
  }
  if (!_youtubeMixSeedIdPattern.hasMatch(seedId)) return null;
  return seedId;
}

String? normalizeYouTubeMixShorthandUrl(String input) {
  final seedId = parseYouTubeMixShorthandSeedId(input);
  if (seedId == null) return null;
  return 'https://www.youtube.com/watch?v=$seedId&list=RD$seedId';
}
```

- [ ] **Step 4: Run parser tests**

Run: `flutter test test/services/import/youtube_mix_shorthand_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit checkpoint if authorized**

Run only after explicit commit approval:

```bash
git add lib/services/import/youtube_mix_shorthand.dart test/services/import/youtube_mix_shorthand_test.dart
git commit -m "feat: add youtube mix shorthand parser"
```

### Task 2: Normalize shorthand in import service

**Files:**
- Modify: `lib/services/import/import_service.dart`
- Modify: `test/services/import/import_service_phase4_test.dart`

- [ ] **Step 1: Add failing service tests**

In `test/services/import/import_service_phase4_test.dart`, add two tests inside `group('ImportService phase 4 dispatch', () { ... })`:

```dart
test('importFromUrl normalizes mix shorthand before YouTube Mix import', () async {
  final source = _FakeYouTubeSource();
  sourceManager.detectedSource = source;
  sourceManager.youtubeSource = source;
  final service = ImportService(
    sourceManager: sourceManager,
    playlistRepository: playlistRepository,
    trackRepository: trackRepository,
    isar: isar,
  );

  await expectLater(
    () => service.importFromUrl(' MIX:dvgZkm1xWPE '),
    throwsA(isA<_MixImportSentinel>()),
  );

  expect(sourceManager.lastDetectedUrl,
      'https://www.youtube.com/watch?v=dvgZkm1xWPE&list=RDdvgZkm1xWPE');
  expect(source.lastMixInfoUrl,
      'https://www.youtube.com/watch?v=dvgZkm1xWPE&list=RDdvgZkm1xWPE');
});

test('importFromUrl stores normalized sourceUrl for shorthand Mix playlist', () async {
  final source = _FakeYouTubeSource()
    ..mixInfo = const MixPlaylistInfo(
      title: 'Mix',
      playlistId: 'RDdvgZkm1xWPE',
      seedVideoId: 'dvgZkm1xWPE',
      coverUrl: 'https://img.example/cover.jpg',
    );
  sourceManager.detectedSource = source;
  sourceManager.youtubeSource = source;
  final service = ImportService(
    sourceManager: sourceManager,
    playlistRepository: playlistRepository,
    trackRepository: trackRepository,
    isar: isar,
  );

  final result = await service.importFromUrl('mix:dvgZkm1xWPE');

  expect(result.playlist.isMix, isTrue);
  expect(result.playlist.mixPlaylistId, 'RDdvgZkm1xWPE');
  expect(result.playlist.mixSeedVideoId, 'dvgZkm1xWPE');
  expect(result.playlist.sourceUrl,
      'https://www.youtube.com/watch?v=dvgZkm1xWPE&list=RDdvgZkm1xWPE');
  expect(result.addedCount, 0);
});
```

Replace `_FakeSourceManager` with:

```dart
class _FakeSourceManager extends SourceManager {
  _FakeSourceManager() : super();

  BaseSource? detectedSource;
  BaseSource? youtubeSource;
  String? lastDetectedUrl;

  @override
  BaseSource? detectSource(String url) {
    lastDetectedUrl = url;
    return detectedSource;
  }

  @override
  BaseSource? getSourceForUrl(String url) {
    lastDetectedUrl = url;
    return detectedSource;
  }

  @override
  BaseSource? getSource(SourceType type) {
    if (type == SourceType.youtube) return youtubeSource ?? detectedSource;
    return detectedSource?.sourceType == type ? detectedSource : null;
  }

  @override
  void dispose() {}
}
```

Extend `_FakeYouTubeSource` with:

```dart
String? lastMixInfoUrl;
MixPlaylistInfo? mixInfo;

@override
Future<MixPlaylistInfo> getMixPlaylistInfo(String url) async {
  lastMixInfoUrl = url;
  final info = mixInfo;
  if (info == null) throw _MixImportSentinel();
  return info;
}
```

- [ ] **Step 2: Run service tests and verify failure**

Run: `flutter test test/services/import/import_service_phase4_test.dart`
Expected: FAIL because `mix:` is not normalized and is not detected as a YouTube URL.

- [ ] **Step 3: Implement service normalization**

In `lib/services/import/import_service.dart`, add import:

```dart
import 'youtube_mix_shorthand.dart';
```

Inside `importFromUrl()`, at the start of the `try` block, add:

```dart
final normalizedUrl = normalizeYouTubeMixShorthandUrl(url) ?? url.trim();
```

Then replace uses of `url` in source detection, Mix detection, playlist parsing, `getBySourceUrl`, and new playlist `sourceUrl` with `normalizedUrl`:

```dart
final source = _sourceManager.detectSource(normalizedUrl);
if (source == null) {
  throw ImportException(t.importSource.unrecognizedUrlFormat);
}

if (source is YouTubeSource && YouTubeSource.isMixPlaylistUrl(normalizedUrl)) {
  return _importMixPlaylist(
    url: normalizedUrl,
    customName: customName,
    refreshIntervalHours: refreshIntervalHours,
    notifyOnUpdate: notifyOnUpdate,
  );
}

final result = await source.parsePlaylist(normalizedUrl, authHeaders: authHeaders);
final existingPlaylist = await _playlistRepository.getBySourceUrl(normalizedUrl);
```

When creating a new playlist, set:

```dart
..sourceUrl = normalizedUrl
```

- [ ] **Step 4: Run service tests**

Run: `flutter test test/services/import/import_service_phase4_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit checkpoint if authorized**

Run only after explicit commit approval:

```bash
git add lib/services/import/import_service.dart test/services/import/import_service_phase4_test.dart
git commit -m "feat: normalize youtube mix shorthand imports"
```

### Task 3: Update import dialog detection and validation

**Files:**
- Modify: `lib/ui/pages/library/widgets/import_playlist_dialog.dart`

- [ ] **Step 1: Implement dialog shorthand detection**

Add import:

```dart
import '../../../../services/import/youtube_mix_shorthand.dart';
```

In `_onUrlChanged()`, after the empty-input check and before source manager detection, add:

```dart
if (looksLikeYouTubeMixShorthand(trimmed)) {
  final newDetected = parseYouTubeMixShorthandSeedId(trimmed) != null
      ? const _DetectedUrl(
          type: _UrlType.internal,
          platform: _SourcePlatform.youtube,
        )
      : null;
  if (_detected?.type != newDetected?.type ||
      _detected?.platform != newDetected?.platform) {
    setState(() => _detected = newDetected);
  }
  return;
}
```

- [ ] **Step 2: Implement dialog validation**

In the `TextFormField` validator, after `final trimmed = value.trim();`, add:

```dart
if (looksLikeYouTubeMixShorthand(trimmed)) {
  return parseYouTubeMixShorthandSeedId(trimmed) == null
      ? t.library.importPlaylist.unsupportedFormat
      : null;
}
```

- [ ] **Step 3: Run focused tests and analyzer**

Run: `flutter test test/services/import/youtube_mix_shorthand_test.dart test/services/import/import_service_phase4_test.dart`
Expected: PASS.

Run: `flutter analyze`
Expected: no new analyzer errors.

- [ ] **Step 4: Commit checkpoint if authorized**

Run only after explicit commit approval:

```bash
git add lib/ui/pages/library/widgets/import_playlist_dialog.dart
git commit -m "feat: accept youtube mix shorthand in import dialog"
```

### Task 4: Manual validation

**Files:**
- No code changes expected.

- [ ] **Step 1: Launch the app**

Run: `flutter run`
Expected: app starts on the selected device/platform.

- [ ] **Step 2: Verify import dialog recognition**

Open Music Library, click import playlist, enter:

```text
mix:dvgZkm1xWPE
```

Expected: the input is accepted as a YouTube internal import and shows the YouTube source indicator.

- [ ] **Step 3: Verify Mix playlist creation**

Submit the import.
Expected: a Mix playlist is created with no stored tracks, and opening/playing it loads tracks through the existing YouTube Mix flow.

- [ ] **Step 4: Verify invalid shorthand**

Open the import dialog and enter:

```text
mix:dvgZkm1xWPE!
```

Expected: the dialog rejects the input with the existing unsupported-format message.

## Self-Review Notes

- Spec coverage: parser, UI detection, service normalization, normalized persistence, validation, and tests are covered.
- Placeholder scan: no TBD/TODO/fill-later steps remain.
- Type consistency: helper names are `looksLikeYouTubeMixShorthand`, `parseYouTubeMixShorthandSeedId`, and `normalizeYouTubeMixShorthandUrl` throughout.
