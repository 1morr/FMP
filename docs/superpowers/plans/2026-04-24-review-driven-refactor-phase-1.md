# Review-Driven Refactor Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Phase 1 of the `docs/review` refactor roadmap: small, test-first fixes for playback URL expiry, resume seek races, Windows ZIP safety, Android storage permission branching, hot-path logging, settings updates, and UI consistency.

**Architecture:** Keep FMP's existing architecture intact: UI continues to call `AudioController`, `QueueManager` continues to own queue state, source access continues through `SourceManager`, and platform audio backends stay split. Phase 1 only adds narrow helpers or injectable seams where needed for tested fixes; structural refactors remain deferred to later phases.

**Tech Stack:** Flutter/Dart, Riverpod, Isar, `permission_handler`, `archive`, `path`, Kotlin Android embedding, Flutter test.

---

## File Structure

### Audio URL expiry and resume race

- Modify: `lib/services/audio/internal/audio_stream_delegate.dart`
  - Store `DateTime.now().add(streamResult.expiry ?? const Duration(hours: 1))` for playback URL refreshes.
- Modify: `lib/services/audio/audio_provider.dart`
  - Add request/track guard before delayed resume seek in `_resumeWithFreshUrlIfNeeded()`.
- Modify: `test/services/audio/audio_stream_manager_test.dart`
  - Extend `_FakeSource` with configurable `nextAudioExpiry`.
  - Add tests for source expiry and fallback-to-one-hour expiry on the main playback path.
- Modify: `test/services/audio/audio_controller_phase1_test.dart`
  - Extend `_FakeSource` with configurable `nextAudioExpiry` if needed.
  - Add tests for expired-URL resume restoring position and superseded resume not seeking the new track.

### Windows ZIP safety

- Modify: `lib/services/update/update_service.dart`
  - Add a small safe ZIP destination helper used by `_downloadAndExtractZip()`.
  - Reject entries with `..`, absolute paths, Windows drive paths, or paths that normalize outside the extraction directory.
- Create: `test/services/update/update_service_zip_test.dart`
  - Unit-test the safe ZIP helper with normal and malicious entries.

### Android storage permission SDK detection

- Modify: `lib/services/storage_permission_service.dart`
  - Replace permission-status-probing version detection with SDK-int lookup.
  - Add a test-only injectable SDK provider so unit tests do not require Android devices.
- Modify: `android/app/src/main/kotlin/com/personal/fmp/MainActivity.kt`
  - Add a `MethodChannel` method that returns `Build.VERSION.SDK_INT`.
- Create: `test/services/storage_permission_service_test.dart`
  - Test Android 10 versus Android 11+ branching via the injectable SDK provider and fake permission callbacks.

### Hot-path repository logging

- Modify: `lib/data/repositories/track_repository.dart`
  - Remove default stack trace logging and detailed `playlistInfo` debug construction from `save()`.
  - Keep only cheap summary logging, or remove `save()` debug logs entirely.
- No separate test is needed because behavior does not change. Verify with existing repository/audio/download tests.

### Settings download path updates

- Modify: `lib/services/download/download_path_manager.dart`
  - Change `saveDownloadPath()` and `clearDownloadPath()` to use `SettingsRepository.update()`.
- Create or modify: `test/services/download/download_path_manager_test.dart`
  - Verify updating/clearing the custom download directory preserves unrelated settings modified in the same repository state.

### UI consistency fixes

- Modify: `lib/ui/pages/home/home_page.dart`
  - Add size hints to playlist cover `ImageLoadingService.loadImage()` calls where missing.
- Modify: `lib/ui/pages/library/downloaded_page.dart`
  - Add size hints to category cover `ImageLoadingService.loadImage()`.
- Modify: `lib/ui/pages/library/downloaded_category_page.dart`
  - Add size hints to category header/cover `ImageLoadingService.loadImage()` calls.
- Modify: `lib/ui/pages/library/widgets/cover_picker_dialog.dart`
  - Add `super.key` to `_CoverGridItem` and pass `ValueKey(track.thumbnailUrl)` at call sites.
  - Add `targetDisplaySize` to URL preview image loading.
- Modify: `lib/ui/pages/library/import_preview_page.dart`
  - Add `super.key` to `_AlternativeTrackTile` and pass stable `ValueKey`s for both search-result and expanded alternative rows.
- Modify: `lib/ui/widgets/track_thumbnail.dart`
  - Use a non-null default `targetDisplaySize` for non-high-resolution `TrackCover`.
- Modify: `test/ui/pages/search/search_page_phase2_test.dart` or create `test/ui/ui_consistency_phase1_test.dart`
  - Add lightweight static tests for the new key and image-size consistency rules.

### Search history cleanup

- Modify: `lib/providers/search_provider.dart`
  - Remove unused `searchHistoryProvider` if full-code search confirms no references.
- Test: existing search tests plus `flutter analyze` should catch stale references.

### Documentation

- Modify: `docs/superpowers/plans/2026-04-24-review-driven-refactor-phase-1.md`
  - This plan.
- Documentation check after implementation: update `CLAUDE.md` or `.serena/memories/update_system.md` only if the implementation introduces durable platform/update rules that future agents must know.

---

## Phase 1 Roadmap Context

The full design is saved at `docs/superpowers/specs/2026-04-24-review-driven-refactor-design.md`.

Phase 1 includes only low-risk high-value fixes. Do not implement these deferred items in this plan:

- `PlayerState.queue` provider split.
- Play history pagination/flattened sliver rewrite.
- `AudioController` provider wiring or retry-policy extraction.
- Radio/audio ownership coordinator.
- Track/DownloadTask unique indexes or historical data merge.
- Remote playlist action service.
- FileExistsCache negative cache.
- Download media headers helper.

---

### Task 1: Playback Stream Expiry

**Files:**
- Modify: `test/services/audio/audio_stream_manager_test.dart:245-278`, `test/services/audio/audio_stream_manager_test.dart:381-452`
- Modify: `lib/services/audio/internal/audio_stream_delegate.dart:61-69`

- [ ] **Step 1: Add configurable source expiry to the audio stream fake**

In `test/services/audio/audio_stream_manager_test.dart`, update `_FakeSource` to include a one-shot expiry field:

```dart
class _FakeSource extends BaseSource {
  AudioStreamConfig? lastAlternativeConfig;
  String? lastFailedUrl;
  final List<String> audioStreamRequests = [];
  Map<String, String>? lastAudioAuthHeaders;
  bool throwOnRefresh = false;
  Duration? nextAudioExpiry;
```

Then update `_FakeSource.getAudioStream()` to pass it through and reset it after use:

```dart
  @override
  Future<AudioStreamResult> getAudioStream(
    String sourceId, {
    AudioStreamConfig config = AudioStreamConfig.defaultConfig,
    Map<String, String>? authHeaders,
  }) async {
    audioStreamRequests.add(sourceId);
    lastAudioAuthHeaders = authHeaders;
    final expiry = nextAudioExpiry;
    nextAudioExpiry = null;
    return AudioStreamResult(
      url: 'https://example.com/$sourceId.m4a',
      container: 'm4a',
      codec: 'aac',
      streamType: StreamType.audioOnly,
      expiry: expiry,
    );
  }
```

- [ ] **Step 2: Add failing test for source-provided expiry on main playback path**

Insert this test in `test/services/audio/audio_stream_manager_test.dart` after `selectPlayback attaches playback headers for remote streams`:

```dart
    test('selectPlayback stores source-provided stream expiry on the track',
        () async {
      sourceManager.source.nextAudioExpiry = const Duration(minutes: 16);

      final selection = await manager.selectPlayback(
        _track('stream-expiry', title: 'Stream Expiry'),
      );

      expect(selection.localPath, isNull);
      expect(selection.url, 'https://example.com/stream-expiry.m4a');
      expect(selection.track.audioUrl, selection.url);
      expect(selection.track.audioUrlExpiry, isNotNull);
      final expiryDelta =
          selection.track.audioUrlExpiry!.difference(DateTime.now());
      expect(
        expiryDelta.inMinutes,
        inInclusiveRange(15, 16),
      );
    });
```

- [ ] **Step 3: Add fallback-to-one-hour test for sources with no expiry**

Insert this test immediately after the previous one:

```dart
    test('selectPlayback falls back to one hour when source omits expiry',
        () async {
      sourceManager.source.nextAudioExpiry = null;

      final selection = await manager.selectPlayback(
        _track('stream-default-expiry', title: 'Stream Default Expiry'),
      );

      expect(selection.track.audioUrlExpiry, isNotNull);
      final expiryDelta =
          selection.track.audioUrlExpiry!.difference(DateTime.now());
      expect(
        expiryDelta.inMinutes,
        inInclusiveRange(59, 60),
      );
    });
```

- [ ] **Step 4: Run the expiry tests and verify failure**

Run:

```bash
flutter test test/services/audio/audio_stream_manager_test.dart --plain-name "selectPlayback stores source-provided stream expiry on the track"
```

Expected: FAIL because `AudioStreamDelegate.ensureAudioStream()` stores a fixed one-hour expiry, so `expiryDelta.inMinutes` is near 59/60 instead of 15/16.

- [ ] **Step 5: Implement source expiry storage**

In `lib/services/audio/internal/audio_stream_delegate.dart`, replace:

```dart
      track.audioUrl = streamResult.url;
      track.audioUrlExpiry = DateTime.now().add(const Duration(hours: 1));
      track.updatedAt = DateTime.now();
```

with:

```dart
      track.audioUrl = streamResult.url;
      track.audioUrlExpiry = DateTime.now().add(
        streamResult.expiry ?? const Duration(hours: 1),
      );
      track.updatedAt = DateTime.now();
```

- [ ] **Step 6: Run the audio stream manager regression tests**

Run:

```bash
flutter test test/services/audio/audio_stream_manager_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit Task 1**

```bash
git add lib/services/audio/internal/audio_stream_delegate.dart test/services/audio/audio_stream_manager_test.dart
git commit -m "fix(audio): preserve playback stream expiry"
```

---

### Task 2: Expired URL Resume Seek Guard

**Files:**
- Modify: `test/services/audio/audio_controller_phase1_test.dart:153-344`, `test/services/audio/audio_controller_phase1_test.dart:756-827`
- Modify: `lib/services/audio/audio_provider.dart:2171-2192`

- [ ] **Step 1: Add configurable source expiry to the controller fake source**

In `test/services/audio/audio_controller_phase1_test.dart`, update `_FakeSource`:

```dart
class _FakeSource extends BaseSource {
  Object? _nextGetAudioStreamError;
  Duration? nextAudioExpiry;
```

Then update `_FakeSource.getAudioStream()`:

```dart
  @override
  Future<AudioStreamResult> getAudioStream(String sourceId,
      {AudioStreamConfig config = AudioStreamConfig.defaultConfig,
      Map<String, String>? authHeaders}) async {
    final error = _nextGetAudioStreamError;
    if (error != null) {
      _nextGetAudioStreamError = null;
      throw error;
    }

    final expiry = nextAudioExpiry;
    nextAudioExpiry = null;
    return AudioStreamResult(
      url: 'https://example.com/$sourceId.m4a',
      container: 'm4a',
      codec: 'aac',
      streamType: StreamType.audioOnly,
      expiry: expiry,
    );
  }
```

- [ ] **Step 2: Expose the fake source expiry through `_FakeSourceManager`**

Add this method to `_FakeSourceManager` in `test/services/audio/audio_controller_phase1_test.dart`:

```dart
  void setNextAudioExpiry(Duration? expiry) {
    _source.nextAudioExpiry = expiry;
  }
```

- [ ] **Step 3: Add happy-path expired URL resume test**

Insert this test in the `AudioController phase 1 regressions` group after `superseded failing request does not stop or error the newer request`:

```dart
    test('togglePlayPause refreshes expired remote URL and restores position',
        () async {
      sourceManager.setNextAudioExpiry(const Duration(milliseconds: 1));
      await controller.playTrack(_track('expired-resume', title: 'Expired Resume'));
      await controller.seekTo(const Duration(seconds: 42));
      audioService.setPositionValue(const Duration(seconds: 42));
      await controller.pause();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      audioService.playUrlCalls.clear();
      audioService.seekCalls.clear();

      await controller.togglePlayPause();
      await pumpEventQueue(times: 20);

      expect(audioService.playUrlCalls.single.url,
          'https://example.com/expired-resume.m4a');
      expect(audioService.seekCalls.single, const Duration(seconds: 42));
      expect(controller.state.playingTrack?.sourceId, 'expired-resume');
      expect(controller.state.isPlaying, isTrue);
    });
```

- [ ] **Step 4: Add local-file exclusion test**

Insert this test immediately after the happy-path test:

```dart
    test('togglePlayPause does not refresh expired URL when local file exists',
        () async {
      final localFile = File('${tempDir.path}/local-expired.m4a');
      await localFile.writeAsString('audio-bytes');
      final track = _track('local-expired', title: 'Local Expired')
        ..audioUrl = 'https://stale.example/local-expired.m4a'
        ..audioUrlExpiry = DateTime.now().subtract(const Duration(minutes: 1))
        ..playlistInfo = [
          PlaylistDownloadInfo()
            ..playlistId = 1
            ..playlistName = 'Downloaded'
            ..downloadPath = localFile.path,
        ];

      await controller.playTrack(track);
      await controller.pause();
      audioService.playUrlCalls.clear();
      audioService.seekCalls.clear();

      await controller.togglePlayPause();
      await pumpEventQueue(times: 10);

      expect(audioService.playUrlCalls, isEmpty);
      expect(audioService.seekCalls, isEmpty);
      expect(controller.state.isPlaying, isTrue);
    });
```

- [ ] **Step 5: Add superseded delayed-seek regression test**

Insert this test after the local-file exclusion test:

```dart
    test('superseded expired URL resume does not seek the newer track',
        () async {
      sourceManager.setNextAudioExpiry(const Duration(milliseconds: 1));
      await controller.playTrack(_track('old-expired', title: 'Old Expired'));
      await controller.seekTo(const Duration(seconds: 42));
      audioService.setPositionValue(const Duration(seconds: 42));
      await controller.pause();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      audioService.playUrlCalls.clear();
      audioService.seekCalls.clear();
      final oldResume = controller.togglePlayPause();
      await audioService.waitForPlayUrlCallCount(1);

      final newerTrack = _track('new-after-expired', title: 'New After Expired');
      await controller.playTrack(newerTrack);
      await oldResume;
      await pumpEventQueue(times: 20);

      expect(controller.state.playingTrack?.sourceId, 'new-after-expired');
      expect(controller.state.currentTrack?.sourceId, 'new-after-expired');
      expect(audioService.playUrlCalls.map((call) => call.url), containsAllInOrder([
        'https://example.com/old-expired.m4a',
        'https://example.com/new-after-expired.m4a',
      ]));
      expect(audioService.seekCalls, isEmpty);
    });
```

- [ ] **Step 6: Run the new superseded resume test and verify failure**

Run:

```bash
flutter test test/services/audio/audio_controller_phase1_test.dart --plain-name "superseded expired URL resume does not seek the newer track"
```

Expected: FAIL because `_resumeWithFreshUrlIfNeeded()` currently performs delayed `seekTo(position)` without checking whether another play request or track replacement happened.

- [ ] **Step 7: Implement request/track guard**

In `lib/services/audio/audio_provider.dart`, replace `_resumeWithFreshUrlIfNeeded()` with this implementation:

```dart
  Future<bool> _resumeWithFreshUrlIfNeeded() async {
    final track = state.currentTrack;
    if (track == null) return false;

    // 只在 URL 确实过期时触发（有 URL 但已过期）
    if (track.audioUrl == null || track.hasValidAudioUrl) return false;

    // 排除已下载的本地文件（本地文件不会过期）
    if (track.allDownloadPaths.any((p) => File(p).existsSync())) return false;

    logDebug(
        'Audio URL expired for: ${track.title}, re-fetching and resuming from ${state.position}');
    final position = state.position;
    final trackKey = track.uniqueKey;
    final requestGeneration = _playRequestId;
    final requestTrack = _createPlaybackRequestTrack(track);
    await _playTrack(requestTrack);

    if (_isDisposed) return true;
    if (_playRequestId != requestGeneration + 1) return true;
    if (state.currentTrack?.uniqueKey != trackKey) return true;

    // 播放成功后恢复到之前的位置
    if (position.inSeconds > 0) {
      await Future.delayed(AppConstants.seekStabilizationDelay);
      if (_isDisposed) return true;
      if (_playRequestId != requestGeneration + 1) return true;
      if (state.currentTrack?.uniqueKey != trackKey) return true;
      await seekTo(position);
    }
    return true;
  }
```

Note: this assumes `_playTrack()` increments `_playRequestId` exactly once through `_executePlayRequest()`. If existing code uses a different generation pattern, keep the same guard intent but compare against the actual request id returned by the request entry point.

- [ ] **Step 8: Run the AudioController regression tests**

Run:

```bash
flutter test test/services/audio/audio_controller_phase1_test.dart
```

Expected: PASS.

- [ ] **Step 9: Commit Task 2**

```bash
git add lib/services/audio/audio_provider.dart test/services/audio/audio_controller_phase1_test.dart
git commit -m "fix(audio): guard expired URL resume seek"
```

---

### Task 3: Windows Portable ZIP Path Safety

**Files:**
- Modify: `lib/services/update/update_service.dart:413-424`
- Create: `test/services/update/update_service_zip_test.dart`

- [ ] **Step 1: Create tests for ZIP entry path validation**

Create `test/services/update/update_service_zip_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/update/update_service.dart';

void main() {
  group('UpdateService ZIP extraction path safety', () {
    test('allows normal nested relative entries', () {
      final path = UpdateService.safeZipEntryDestinationForTest(
        r'C:\Temp\fmp_update',
        'FMP/data/app.dll',
      );

      expect(path.replaceAll('\\', '/'), endsWith('/FMP/data/app.dll'));
    });

    test('rejects parent traversal entries', () {
      expect(
        () => UpdateService.safeZipEntryDestinationForTest(
          r'C:\Temp\fmp_update',
          '../evil.txt',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects absolute slash entries', () {
      expect(
        () => UpdateService.safeZipEntryDestinationForTest(
          r'C:\Temp\fmp_update',
          '/evil.txt',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects Windows drive entries', () {
      expect(
        () => UpdateService.safeZipEntryDestinationForTest(
          r'C:\Temp\fmp_update',
          r'C:\evil.txt',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run ZIP safety tests and verify failure**

Run:

```bash
flutter test test/services/update/update_service_zip_test.dart
```

Expected: FAIL because `UpdateService.safeZipEntryDestinationForTest` does not exist yet.

- [ ] **Step 3: Add path import to UpdateService**

In `lib/services/update/update_service.dart`, add this import near other package imports:

```dart
import 'package:path/path.dart' as p;
```

- [ ] **Step 4: Add safe ZIP helper to `UpdateService`**

Inside `class UpdateService`, near other private helpers, add:

```dart
  @visibleForTesting
  static String safeZipEntryDestinationForTest(
    String extractDir,
    String entryName,
  ) {
    return _safeZipEntryDestination(extractDir, entryName);
  }

  static String _safeZipEntryDestination(String extractDir, String entryName) {
    final normalizedName = entryName.replaceAll('\\', '/');
    final parts = p.posix.split(normalizedName);
    final hasDrivePrefix = RegExp(r'^[A-Za-z]:').hasMatch(entryName);

    if (normalizedName.startsWith('/') ||
        normalizedName.startsWith('\\') ||
        hasDrivePrefix ||
        parts.any((part) => part == '..')) {
      throw FormatException('Unsafe ZIP entry path: $entryName');
    }

    final normalizedExtractDir = p.normalize(extractDir);
    final destination = p.normalize(p.join(normalizedExtractDir, ...parts));
    final extractWithSeparator = normalizedExtractDir.endsWith(p.separator)
        ? normalizedExtractDir
        : '$normalizedExtractDir${p.separator}';

    if (destination != normalizedExtractDir &&
        !destination.startsWith(extractWithSeparator)) {
      throw FormatException('Unsafe ZIP entry path: $entryName');
    }

    return destination;
  }
```

If `@visibleForTesting` is not already imported, add:

```dart
import 'package:flutter/foundation.dart';
```

- [ ] **Step 5: Use the helper during extraction**

In `_downloadAndExtractZip()`, replace:

```dart
    for (final file in archive) {
      final filePath = '$extractDir/${file.name}';
      if (file.isFile) {
        final outFile = File(filePath);
        outFile.createSync(recursive: true);
        outFile.writeAsBytesSync(file.content as List<int>);
      } else {
        Directory(filePath).createSync(recursive: true);
      }
    }
```

with:

```dart
    for (final file in archive) {
      final filePath = _safeZipEntryDestination(extractDir, file.name);
      if (file.isFile) {
        final outFile = File(filePath);
        outFile.createSync(recursive: true);
        outFile.writeAsBytesSync(file.content as List<int>);
      } else {
        Directory(filePath).createSync(recursive: true);
      }
    }
```

- [ ] **Step 6: Run ZIP tests**

Run:

```bash
flutter test test/services/update/update_service_zip_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit Task 3**

```bash
git add lib/services/update/update_service.dart test/services/update/update_service_zip_test.dart
git commit -m "fix(update): reject unsafe ZIP entries"
```

---

### Task 4: Android Storage Permission SDK Branching

**Files:**
- Modify: `lib/services/storage_permission_service.dart:17-79`
- Modify: `android/app/src/main/kotlin/com/personal/fmp/MainActivity.kt:1-5`
- Create: `test/services/storage_permission_service_test.dart`

- [ ] **Step 1: Add injectable permission seams to StoragePermissionService**

In `lib/services/storage_permission_service.dart`, add this import:

```dart
import 'package:flutter/services.dart';
```

Inside `class StoragePermissionService`, before `hasStoragePermission()`, add:

```dart
  static const MethodChannel _platformChannel =
      MethodChannel('com.personal.fmp/platform');

  @visibleForTesting
  static Future<int?> Function()? debugAndroidSdkProvider;

  @visibleForTesting
  static Future<bool> Function()? debugManageExternalStorageGranted;

  @visibleForTesting
  static Future<bool> Function()? debugStorageGranted;

  @visibleForTesting
  static Future<PermissionStatus> Function()? debugManageExternalStorageStatus;

  @visibleForTesting
  static Future<PermissionStatus> Function()? debugRequestManageExternalStorage;

  @visibleForTesting
  static Future<PermissionStatus> Function()? debugRequestStorage;

  @visibleForTesting
  static bool? debugIsAndroidOverride;

  @visibleForTesting
  static void resetDebugOverrides() {
    debugAndroidSdkProvider = null;
    debugManageExternalStorageGranted = null;
    debugStorageGranted = null;
    debugManageExternalStorageStatus = null;
    debugRequestManageExternalStorage = null;
    debugRequestStorage = null;
    debugIsAndroidOverride = null;
  }
```

Also add the missing foundation import for `@visibleForTesting`:

```dart
import 'package:flutter/foundation.dart';
```

- [ ] **Step 2: Replace direct platform checks with helper methods**

Add these methods to `StoragePermissionService`:

```dart
  static bool get _isAndroid => debugIsAndroidOverride ?? Platform.isAndroid;

  static Future<int?> _androidSdkInt() async {
    final debugProvider = debugAndroidSdkProvider;
    if (debugProvider != null) return debugProvider();
    return _platformChannel.invokeMethod<int>('getAndroidSdkInt');
  }

  static Future<bool> _isAndroid11OrHigher() async {
    final sdkInt = await _androidSdkInt();
    return sdkInt != null && sdkInt >= 30;
  }

  static Future<bool> _isManageExternalStorageGranted() async {
    final debugGranted = debugManageExternalStorageGranted;
    if (debugGranted != null) return debugGranted();
    return Permission.manageExternalStorage.isGranted;
  }

  static Future<bool> _isStorageGranted() async {
    final debugGranted = debugStorageGranted;
    if (debugGranted != null) return debugGranted();
    return Permission.storage.isGranted;
  }

  static Future<PermissionStatus> _manageExternalStorageStatus() async {
    final debugStatus = debugManageExternalStorageStatus;
    if (debugStatus != null) return debugStatus();
    return Permission.manageExternalStorage.status;
  }

  static Future<PermissionStatus> _requestManageExternalStorage() async {
    final debugRequest = debugRequestManageExternalStorage;
    if (debugRequest != null) return debugRequest();
    return Permission.manageExternalStorage.request();
  }

  static Future<PermissionStatus> _requestStorage() async {
    final debugRequest = debugRequestStorage;
    if (debugRequest != null) return debugRequest();
    return Permission.storage.request();
  }
```

Then update `hasStoragePermission()` to:

```dart
  static Future<bool> hasStoragePermission() async {
    if (!_isAndroid) return true;

    if (await _isAndroid11OrHigher()) {
      return _isManageExternalStorageGranted();
    }

    return _isStorageGranted();
  }
```

- [ ] **Step 3: Update requestStoragePermission branching**

In `requestStoragePermission()`, replace `Platform.isAndroid` with `_isAndroid`, replace `Permission.manageExternalStorage.status` with `_manageExternalStorageStatus()`, replace `Permission.manageExternalStorage.request()` with `_requestManageExternalStorage()`, and replace `Permission.storage.request()` with `_requestStorage()`.

The Android 10-and-lower branch should become:

```dart
    // Android 10 及以下
    final status = await _requestStorage();
    return status.isGranted;
```

- [ ] **Step 4: Add Android MethodChannel implementation**

Replace `android/app/src/main/kotlin/com/personal/fmp/MainActivity.kt` with:

```kotlin
package com.personal.fmp

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.personal.fmp/platform"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAndroidSdkInt" -> result.success(Build.VERSION.SDK_INT)
                else -> result.notImplemented()
            }
        }
    }
}
```

- [ ] **Step 5: Add storage permission branching tests**

Create `test/services/storage_permission_service_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/storage_permission_service.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  group('StoragePermissionService SDK branching', () {
    tearDown(StoragePermissionService.resetDebugOverrides);

    test('non-Android platforms are treated as already permitted', () async {
      StoragePermissionService.debugIsAndroidOverride = false;

      expect(await StoragePermissionService.hasStoragePermission(), isTrue);
    });

    test('Android 10 and lower checks storage permission', () async {
      var storageChecked = false;
      var manageChecked = false;
      StoragePermissionService.debugIsAndroidOverride = true;
      StoragePermissionService.debugAndroidSdkProvider = () async => 29;
      StoragePermissionService.debugStorageGranted = () async {
        storageChecked = true;
        return true;
      };
      StoragePermissionService.debugManageExternalStorageGranted = () async {
        manageChecked = true;
        return false;
      };

      expect(await StoragePermissionService.hasStoragePermission(), isTrue);
      expect(storageChecked, isTrue);
      expect(manageChecked, isFalse);
    });

    test('Android 11 and higher checks manage external storage permission',
        () async {
      var storageChecked = false;
      var manageChecked = false;
      StoragePermissionService.debugIsAndroidOverride = true;
      StoragePermissionService.debugAndroidSdkProvider = () async => 30;
      StoragePermissionService.debugStorageGranted = () async {
        storageChecked = true;
        return false;
      };
      StoragePermissionService.debugManageExternalStorageGranted = () async {
        manageChecked = true;
        return true;
      };

      expect(await StoragePermissionService.hasStoragePermission(), isTrue);
      expect(manageChecked, isTrue);
      expect(storageChecked, isFalse);
    });

    testWidgets('Android 10 denied request returns false from storage permission branch', (tester) async {
      StoragePermissionService.debugIsAndroidOverride = true;
      StoragePermissionService.debugAndroidSdkProvider = () async => 29;
      StoragePermissionService.debugRequestStorage = () async => PermissionStatus.denied;
      StoragePermissionService.debugRequestManageExternalStorage = () async {
        throw StateError('manageExternalStorage should not be requested');
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final allowed = await StoragePermissionService.requestStoragePermission(context);
                expect(allowed, isFalse);
              },
              child: const Text('request'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('request'));
      await tester.pump();
    });
  });
}
```

The request-path test uses a real widget `BuildContext`, so no fake context or skipped test is needed. Keep all tests in this file compiling and active.

- [ ] **Step 6: Run storage permission tests**

Run:

```bash
flutter test test/services/storage_permission_service_test.dart
```

Expected: PASS after all test cases compile and run.

- [ ] **Step 7: Run Dart analyzer and Android debug build**

Run the analyzer first:

```bash
flutter analyze
```

Expected: PASS with no Dart issues. Kotlin issues may only surface during Android build.

Then run the Android debug build:

```bash
flutter build apk --debug
```

Expected: build succeeds. If this environment has no configured Android SDK, capture the exact Flutter error and mark the Android build as blocked in the final handoff; do not treat it as a code pass until it succeeds on a configured Android machine.

- [ ] **Step 8: Commit Task 4**

```bash
git add lib/services/storage_permission_service.dart android/app/src/main/kotlin/com/personal/fmp/MainActivity.kt test/services/storage_permission_service_test.dart
git commit -m "fix(android): use SDK version for storage permission"
```

---

### Task 5: Remove TrackRepository Hot-Path StackTrace Logging

**Files:**
- Modify: `lib/data/repositories/track_repository.dart:83-93`

- [ ] **Step 1: Inspect current hot-path logs**

Confirm `TrackRepository.save()` currently contains:

```dart
    logDebug('Saving track: ${track.title} (id: ${track.id}, sourceId: ${track.sourceId})');
    logDebug('  playlistInfo: ${track.playlistInfo.map((i) => "playlist=${i.playlistId}:path=${i.downloadPath.isNotEmpty ? "HAS_PATH" : "EMPTY"}").join(", ")}');
    // 打印调用栈以找出谁在调用 save
    logDebug('  caller: ${StackTrace.current.toString().split('\n').take(5).join(' -> ')}');
```

- [ ] **Step 2: Remove expensive debug construction**

Replace `save()` with:

```dart
  /// 保存歌曲并返回更新后的歌曲
  Future<Track> save(Track track) async {
    track.updatedAt = DateTime.now();
    final id = await _isar.writeTxn(() => _isar.tracks.put(track));
    track.id = id;
    return track;
  }
```

- [ ] **Step 3: Keep or remove unused logger import/mixin only after checking usage**

If `TrackRepository` still calls `logDebug` elsewhere, keep:

```dart
import '../../core/logger.dart';
class TrackRepository with Logging {
```

If no `logDebug`, `logInfo`, `logWarning`, or `logError` calls remain in the file, remove:

```dart
import '../../core/logger.dart';
```

and change:

```dart
class TrackRepository with Logging {
```

into:

```dart
class TrackRepository {
```

- [ ] **Step 4: Run repository-related tests**

Run:

```bash
flutter test test/services/audio/audio_stream_manager_test.dart test/services/download/download_path_maintenance_service_phase2_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit Task 5**

```bash
git add lib/data/repositories/track_repository.dart
git commit -m "perf(data): remove track save stack logging"
```

---

### Task 6: Atomic Download Path Settings Updates

**Files:**
- Modify: `lib/services/download/download_path_manager.dart:65-83`
- Create: `test/services/download/download_path_manager_test.dart`

- [ ] **Step 1: Add regression test for saving path without resetting unrelated settings**

Create `test/services/download/download_path_manager_test.dart` with:

```dart
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/services/download/download_path_manager.dart';
import 'package:isar/isar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DownloadPathManager settings updates', () {
    late Directory tempDir;
    late Isar isar;
    late SettingsRepository settingsRepository;
    late DownloadPathManager manager;

    setUpAll(() async {
      await Isar.initializeIsarCore(
        libraries: {Abi.current(): await _resolveIsarLibraryPath()},
      );
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('download_path_manager_');
      isar = await Isar.open(
        [SettingsSchema],
        directory: tempDir.path,
        name: 'download_path_manager_test',
      );
      settingsRepository = SettingsRepository(isar);
      manager = DownloadPathManager(settingsRepository);
    });

    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saveDownloadPath preserves unrelated settings', () async {
      final settings = await settingsRepository.get();
      settings.audioQualityLevelIndex = 2;
      settings.useNeteaseAuthForPlay = false;
      await settingsRepository.save(settings);

      await manager.saveDownloadPath('/tmp/fmp-downloads');

      final updated = await settingsRepository.get();
      expect(updated.customDownloadDir, '/tmp/fmp-downloads');
      expect(updated.audioQualityLevelIndex, 2);
      expect(updated.useNeteaseAuthForPlay, isFalse);
    });

    test('clearDownloadPath preserves unrelated settings', () async {
      final settings = await settingsRepository.get();
      settings.customDownloadDir = '/tmp/fmp-downloads';
      settings.audioQualityLevelIndex = 1;
      settings.useNeteaseAuthForPlay = false;
      await settingsRepository.save(settings);

      await manager.clearDownloadPath();

      final updated = await settingsRepository.get();
      expect(updated.customDownloadDir, isNull);
      expect(updated.audioQualityLevelIndex, 1);
      expect(updated.useNeteaseAuthForPlay, isFalse);
    });
  });
}

Future<String> _resolveIsarLibraryPath() async {
  final packageConfig = await _loadPackageConfig();
  final packageDir = _resolvePackageDirectory(packageConfig, 'isar_flutter_libs');

  if (Platform.isWindows) {
    return '${packageDir.path}/windows/isar.dll';
  }
  if (Platform.isLinux) {
    return '${packageDir.path}/linux/libisar.so';
  }
  if (Platform.isMacOS) {
    return '${packageDir.path}/macos/libisar.dylib';
  }

  throw UnsupportedError(
      'Unsupported platform for Isar tests: ${Platform.operatingSystem}');
}

Future<Map<String, dynamic>> _loadPackageConfig() async {
  final packageConfigFile =
      File('${Directory.current.path}/.dart_tool/package_config.json');
  if (!await packageConfigFile.exists()) {
    throw StateError(
      'Could not find .dart_tool/package_config.json for test package resolution',
    );
  }

  return jsonDecode(await packageConfigFile.readAsString())
      as Map<String, dynamic>;
}

Directory _resolvePackageDirectory(
  Map<String, dynamic> packageConfig,
  String packageName,
) {
  final packages = packageConfig['packages'];
  if (packages is! List) {
    throw StateError('Invalid package_config.json format');
  }

  final packageConfigDir = Directory('${Directory.current.path}/.dart_tool');
  for (final package in packages) {
    if (package is! Map<String, dynamic>) continue;
    if (package['name'] != packageName) continue;

    final rootUri = package['rootUri'];
    if (rootUri is! String) break;

    return Directory(packageConfigDir.uri.resolve(rootUri).toFilePath());
  }

  throw StateError('Package not found in package_config.json: $packageName');
}
```

- [ ] **Step 2: Run the new test before implementation**

Run:

```bash
flutter test test/services/download/download_path_manager_test.dart
```

Expected: PASS or FAIL depending on whether the existing get+save path happens to preserve this simple case. The test still documents the expected behavior; the implementation change is required by the review because `SettingsRepository.update()` is the established atomic update API.

- [ ] **Step 3: Use SettingsRepository.update()**

In `lib/services/download/download_path_manager.dart`, replace:

```dart
  Future<void> saveDownloadPath(String path) async {
    final settings = await _settingsRepo.get();
    settings.customDownloadDir = path;
    await _settingsRepo.save(settings);
  }
```

with:

```dart
  Future<void> saveDownloadPath(String path) async {
    await _settingsRepo.update((settings) {
      settings.customDownloadDir = path;
    });
  }
```

Replace:

```dart
  Future<void> clearDownloadPath() async {
    final settings = await _settingsRepo.get();
    settings.customDownloadDir = null;
    await _settingsRepo.save(settings);
  }
```

with:

```dart
  Future<void> clearDownloadPath() async {
    await _settingsRepo.update((settings) {
      settings.customDownloadDir = null;
    });
  }
```

- [ ] **Step 4: Run download path tests**

Run:

```bash
flutter test test/services/download/download_path_manager_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit Task 6**

```bash
git add lib/services/download/download_path_manager.dart test/services/download/download_path_manager_test.dart
git commit -m "fix(settings): update download path atomically"
```

---

### Task 7: UI Image Sizing and Stable Keys

**Files:**
- Modify: `lib/ui/pages/home/home_page.dart:1218-1226`
- Modify: `lib/ui/pages/library/downloaded_page.dart:309-317`
- Modify: `lib/ui/pages/library/downloaded_category_page.dart:391-424`
- Modify: `lib/ui/pages/library/widgets/cover_picker_dialog.dart:179-200`, `lib/ui/pages/library/widgets/cover_picker_dialog.dart:259-266`, `lib/ui/pages/library/widgets/cover_picker_dialog.dart:291-301`
- Modify: `lib/ui/pages/library/import_preview_page.dart:647-652`, `lib/ui/pages/library/import_preview_page.dart:812-817`, `lib/ui/pages/library/import_preview_page.dart:826-836`
- Modify: `lib/ui/widgets/track_thumbnail.dart:209-216`
- Create: `test/ui/ui_consistency_phase1_test.dart`

- [ ] **Step 1: Add static UI consistency tests**

Create `test/ui/ui_consistency_phase1_test.dart` with:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 1 UI consistency', () {
    test('cover picker grid items expose and receive stable keys', () {
      final source = File(
        'lib/ui/pages/library/widgets/cover_picker_dialog.dart',
      ).readAsStringSync();

      expect(
        RegExp(r'const\s+_CoverGridItem\s*\(\s*\{\s*super\.key,', dotAll: true)
            .hasMatch(source),
        isTrue,
      );
      expect(
        source.contains('key: ValueKey(track.thumbnailUrl),'),
        isTrue,
      );
    });

    test('import preview alternative rows expose and receive stable keys', () {
      final source = File(
        'lib/ui/pages/library/import_preview_page.dart',
      ).readAsStringSync();

      expect(
        RegExp(r'const\s+_AlternativeTrackTile\s*\(\s*\{\s*super\.key,', dotAll: true)
            .hasMatch(source),
        isTrue,
      );
      expect(
        source.contains("ValueKey('alternative-search-") ||
            source.contains("ValueKey('alternative-expanded-"),
        isTrue,
      );
    });

    test('known fixed-size image loads pass display-size hints', () {
      final home = File('lib/ui/pages/home/home_page.dart').readAsStringSync();
      final downloaded =
          File('lib/ui/pages/library/downloaded_page.dart').readAsStringSync();
      final downloadedCategory = File(
        'lib/ui/pages/library/downloaded_category_page.dart',
      ).readAsStringSync();
      final coverPicker = File(
        'lib/ui/pages/library/widgets/cover_picker_dialog.dart',
      ).readAsStringSync();
      final trackThumbnail =
          File('lib/ui/widgets/track_thumbnail.dart').readAsStringSync();

      expect(home.contains('targetDisplaySize: 160'), isTrue);
      expect(downloaded.contains('targetDisplaySize: 160'), isTrue);
      expect(downloadedCategory.contains('targetDisplaySize: 240'), isTrue);
      expect(coverPicker.contains('targetDisplaySize: 320'), isTrue);
      expect(
        trackThumbnail.contains('targetDisplaySize: highResolution ? 480.0 : 320.0'),
        isTrue,
      );
    });
  });
}
```

- [ ] **Step 2: Run the UI consistency test and verify failure**

Run:

```bash
flutter test test/ui/ui_consistency_phase1_test.dart
```

Expected: FAIL because `_CoverGridItem` and `_AlternativeTrackTile` do not expose keys, and several image calls do not include the expected display-size hints.

- [ ] **Step 3: Add size hint to home playlist cover image**

In `lib/ui/pages/home/home_page.dart`, update the playlist cover `loadImage()` call around line 1221 from:

```dart
                          ? ImageLoadingService.loadImage(
                              localPath: coverData.localPath,
                              networkUrl: coverData.networkUrl,
                              placeholder: const ImagePlaceholder.playlist(),
                              fit: BoxFit.cover,
                            )
```

into:

```dart
                          ? ImageLoadingService.loadImage(
                              localPath: coverData.localPath,
                              networkUrl: coverData.networkUrl,
                              placeholder: const ImagePlaceholder.playlist(),
                              fit: BoxFit.cover,
                              targetDisplaySize: 160,
                            )
```

- [ ] **Step 4: Add size hint to downloaded category card cover**

In `lib/ui/pages/library/downloaded_page.dart`, update `_buildCover()` from:

```dart
      return ImageLoadingService.loadImage(
        localPath: category.coverPath,
        networkUrl: null,
        placeholder: _buildDefaultCover(colorScheme),
        fit: BoxFit.cover,
      );
```

into:

```dart
      return ImageLoadingService.loadImage(
        localPath: category.coverPath,
        networkUrl: null,
        placeholder: _buildDefaultCover(colorScheme),
        fit: BoxFit.cover,
        targetDisplaySize: 160,
      );
```

- [ ] **Step 5: Add size hints to downloaded category page cover images**

In `lib/ui/pages/library/downloaded_category_page.dart`, update both `loadImage()` calls.

For the darkened header cover around line 397, add:

```dart
          targetDisplaySize: 240,
```

For the regular cover around line 419, add:

```dart
        targetDisplaySize: 160,
```

- [ ] **Step 6: Add key support and URL preview size in cover picker**

In `lib/ui/pages/library/widgets/cover_picker_dialog.dart`, update the `_CoverGridItem` call:

```dart
        return _CoverGridItem(
          key: ValueKey(track.thumbnailUrl),
          imageUrl: track.thumbnailUrl!,
          isSelected: isSelected,
          onTap: () {
```

Update URL preview `loadImage()` around line 262:

```dart
                      child: ImageLoadingService.loadImage(
                        networkUrl: _urlController.text,
                        placeholder: const ImagePlaceholder.track(),
                        fit: BoxFit.contain,
                        targetDisplaySize: 320,
                      ),
```

Update `_CoverGridItem` constructor:

```dart
  const _CoverGridItem({
    super.key,
    required this.imageUrl,
    required this.isSelected,
    required this.onTap,
  });
```

- [ ] **Step 7: Add stable keys to import preview alternative rows**

In `lib/ui/pages/library/import_preview_page.dart`, update search result rows:

```dart
          ...searchResults.take(5).map((result) => _AlternativeTrackTile(
                key: ValueKey(
                  'alternative-search-${result.sourceType.name}:${result.sourceId}:${result.pageNum ?? result.cid ?? 0}',
                ),
                track: result,
                isSelected: matchedTrack.selectedTrack?.sourceId == result.sourceId,
                onSelect: () => onSelectTrack(result),
              )),
```

Update expanded rows:

```dart
          ...matchedTrack.searchResults.map((altTrack) => _AlternativeTrackTile(
                key: ValueKey(
                  'alternative-expanded-${altTrack.sourceType.name}:${altTrack.sourceId}:${altTrack.pageNum ?? altTrack.cid ?? 0}',
                ),
                track: altTrack,
                isSelected: altTrack.sourceId == track.sourceId,
                onSelect: () => onSelectAlternative(altTrack),
              )),
```

Update `_AlternativeTrackTile` constructor:

```dart
  const _AlternativeTrackTile({
    super.key,
    required this.track,
    required this.isSelected,
    required this.onSelect,
  });
```

- [ ] **Step 8: Add default TrackCover display size**

In `lib/ui/widgets/track_thumbnail.dart`, update `TrackCover._buildImage()` from:

```dart
      showLoadingIndicator: showLoadingIndicator,
      targetDisplaySize: highResolution ? 480.0 : null,
```

into:

```dart
      showLoadingIndicator: showLoadingIndicator,
      targetDisplaySize: highResolution ? 480.0 : 320.0,
```

- [ ] **Step 9: Run UI consistency tests**

Run:

```bash
flutter test test/ui/ui_consistency_phase1_test.dart test/ui/pages/search/search_page_phase2_test.dart
```

Expected: PASS.

- [ ] **Step 10: Commit Task 7**

```bash
git add lib/ui/pages/home/home_page.dart lib/ui/pages/library/downloaded_page.dart lib/ui/pages/library/downloaded_category_page.dart lib/ui/pages/library/widgets/cover_picker_dialog.dart lib/ui/pages/library/import_preview_page.dart lib/ui/widgets/track_thumbnail.dart test/ui/ui_consistency_phase1_test.dart
git commit -m "fix(ui): add image sizing hints and stable keys"
```

---

### Task 8: Remove Unused Search History FutureProvider

**Files:**
- Modify: `lib/providers/search_provider.dart:601-606`

- [ ] **Step 1: Confirm only the provider declaration references `searchHistoryProvider`**

Run:

```bash
git grep -n "searchHistoryProvider"
```

Expected output should only include the declaration in `lib/providers/search_provider.dart`. If there are other references, stop and either migrate them to `searchHistoryManagerProvider` or leave this task unimplemented and document the references.

- [ ] **Step 2: Remove the unused provider**

Delete this block from `lib/providers/search_provider.dart`:

```dart
/// 搜索历史 Provider
final searchHistoryProvider =
    FutureProvider<List<SearchHistory>>((ref) async {
  final service = ref.watch(searchServiceProvider);
  return service.getSearchHistory();
});
```

Keep `SearchHistoryNotifier` and `searchHistoryManagerProvider` unchanged.

- [ ] **Step 3: Run search/UI tests and analyzer**

Run:

```bash
flutter test test/ui/pages/search/search_page_phase2_test.dart
flutter analyze
```

Expected: PASS and analyzer reports no missing symbol references.

- [ ] **Step 4: Commit Task 8**

```bash
git add lib/providers/search_provider.dart
git commit -m "refactor(search): remove unused history provider"
```

---

### Task 9: Phase 1 Verification and Documentation Check

**Files:**
- Documentation review: `CLAUDE.md`
- Documentation review: `.serena/memories/update_system.md`
- Documentation review: `.serena/memories/download_system.md`

- [ ] **Step 1: Run focused Phase 1 tests**

Run:

```bash
flutter test test/services/audio/audio_stream_manager_test.dart test/services/audio/audio_controller_phase1_test.dart test/services/update/update_service_zip_test.dart test/services/storage_permission_service_test.dart test/services/download/download_path_manager_test.dart test/ui/ui_consistency_phase1_test.dart test/ui/pages/search/search_page_phase2_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run full analyzer**

Run:

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 3: Run the full test suite**

Run:

```bash
flutter test
```

Expected: PASS. If the full suite is blocked by a missing platform dependency or environment problem, capture the exact error output, keep the focused tests from Step 1 passing, and document the blocker in the final handoff.

- [ ] **Step 4: Perform manual smoke checks**

Manual checks to run where platform/device access exists:

```text
Audio:
1. Play a remote Bilibili or Netease track.
2. Pause long enough or force an expired URL in debug state.
3. Resume and verify the track refreshes and returns to the old position.
4. Immediately switch to another track during resume and verify the new track is not seeked to the old position.

Windows update:
1. Run a normal portable ZIP update flow in a test install directory.
2. Verify files extract into the temporary update directory and the updater script still starts.
3. Do not test with real malicious packages outside a disposable temp directory.

Android storage:
1. Android 10 or lower: choose a custom download directory and verify storage permission path uses normal storage permission.
2. Android 11+: choose a custom download directory and verify manage external storage flow still opens the expected system setting.

UI:
1. Open Home playlist cards, Downloaded page, Downloaded category page, Cover picker, and Import preview.
2. Verify covers still load, placeholders still show, and selecting alternative import tracks still works.
```

- [ ] **Step 5: Update docs only if durable behavior changed**

If Android permission behavior or update ZIP safety needs to become future-agent guidance, update `CLAUDE.md` under the relevant platform/update section with concise text such as:

```markdown
- Android storage permission checks must branch by actual SDK int: API 30+ uses `MANAGE_EXTERNAL_STORAGE`; older versions use `Permission.storage`.
- Windows portable ZIP updates must validate each entry path before extraction and reject absolute, drive-prefixed, or `..` traversal paths.
```

If this repeats detailed implementation already in `update_system.md`, update the memory instead and keep `CLAUDE.md` concise.

- [ ] **Step 6: Commit final docs or verification-only state**

If docs changed:

```bash
git add CLAUDE.md .serena/memories/update_system.md .serena/memories/download_system.md
git commit -m "docs: record Phase 1 platform safety rules"
```

If no docs changed, do not create an empty commit.

---

## Plan Self-Review

### Spec coverage

- Playback expiry: Task 1.
- Expired resume seek guard: Task 2.
- Windows ZIP traversal: Task 3.
- Android storage SDK branching: Task 4.
- TrackRepository hot-path logging: Task 5.
- Download path atomic settings update: Task 6.
- Image sizing and ValueKey consistency: Task 7.
- Search history duplicate provider cleanup: Task 8.
- Verification/manual platform checks/docs: Task 9.
- Deferred structural items are explicitly excluded in the roadmap context.

### Placeholder scan

No `TBD`, `TODO`, `implement later`, or unspecified “add tests” placeholders remain. Each code-changing task includes exact files, code snippets, commands, and expected results.

### Type and naming consistency

- Uses existing types: `AudioStreamResult.expiry`, `SourceType`, `PlaylistDownloadInfo`, `SettingsRepository.update()`, `PermissionStatus`, and `ImageLoadingService.loadImage()`.
- New test seams are consistently named `debug...` and reset through `resetDebugOverrides()`.
- ZIP helper test entry point is `UpdateService.safeZipEntryDestinationForTest()` and the private helper is `_safeZipEntryDestination()`.
