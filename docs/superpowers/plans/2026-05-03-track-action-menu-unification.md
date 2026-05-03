# Track Action and Menu Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Define common track actions once, render them through shared menu descriptors, and route common single-track and multi-track execution through shared handlers while keeping page-specific actions injectable.

**Architecture:** Keep the existing `TrackActionHandler` as the single-track execution primitive, add public action ids, add a multi-track handler for queue/play-next/playlist/remote actions, and add UI-facing menu descriptor/rendering helpers. Pages will compose common descriptors with local extra actions such as download, delete, remove-from-playlist, and remove-from-remote.

**Tech Stack:** Flutter, Dart, Riverpod, Material popup menus, existing `TrackActionHandler`, `SelectionModeAppBar`, `ContextMenuRegion`, generated `slang` translations.

---

## File Structure

- Modify: `lib/ui/handlers/track_action_handler.dart:4-145`
  - Replace private action-id constants with public constants.
  - Add `TrackAction.menuId` extension.
  - Add `MultiTrackActionHandler` and `MultiTrackActionFeedbackSink` for common multi-track execution.
- Create: `lib/ui/handlers/track_action_menu.dart`
  - Define `TrackActionMenuScope`, `TrackActionMenuOptions`, and `TrackActionMenuItem`.
  - Build common action descriptors for single-track and multi-track surfaces.
  - Render descriptors as `PopupMenuEntry<String>` values.
- Create: `lib/ui/handlers/track_action_coordinator.dart`
  - Centralize widget/Riverpod glue for common single-track and multi-track actions.
  - Show existing toasts and dialogs consistently.
- Modify: `lib/ui/widgets/selection_mode_app_bar.dart:13-374`
  - Render common multi-track actions from descriptors.
  - Dispatch common actions through `TrackActionCoordinator.handleMulti`.
  - Keep download, delete, and remove-from-remote callbacks injectable.
- Modify: `lib/ui/pages/explore/explore_page.dart:939-1029`
  - Replace hard-coded common popup items and repeated single-track handler setup.
- Modify: `lib/ui/pages/home/home_page.dart:939-1029`
  - Replace hard-coded history-track common popup items and repeated single-track handler setup.
- Modify: `lib/ui/pages/library/downloaded_category_page.dart:893-1000`
  - Compose common track actions with the local delete-download action.
- Modify: `lib/ui/pages/search/search_page.dart:863-969,1187-1194,1278-1283,1430-1490,1589-1596`
  - Use descriptor builders for video, page, group, and local-track menus.
  - Route single-track common actions through the coordinator.
  - Keep multi-page/group behavior where a row represents multiple tracks.
- Modify: `lib/ui/pages/library/playlist_detail_page.dart:497-566,1316-1358,1632-1790`
  - Use descriptor builders for selection, group, and track-row menus.
  - Dispatch common actions before page-specific download/remove actions.
- Modify: `CLAUDE.md`
  - Document that new track action menus must use shared descriptors/coordinators.
- Test: `test/ui/handlers/track_action_handler_test.dart`
- Test: `test/ui/handlers/track_action_menu_test.dart`

### Task 1: Public Action IDs and Menu Descriptor Contract

**Files:**
- Modify: `lib/ui/handlers/track_action_handler.dart:4-46`
- Create: `lib/ui/handlers/track_action_menu.dart`
- Create: `test/ui/handlers/track_action_menu_test.dart`
- Modify: `test/ui/handlers/track_action_handler_test.dart:5-53`

- [ ] **Step 1: Add failing tests for action ids and descriptors**

Append these tests inside `group('TrackActionHandler', () { ... })` in `test/ui/handlers/track_action_handler_test.dart`:

```dart
    test('track actions expose stable menu ids', () {
      expect(TrackAction.play.menuId, playTrackActionId);
      expect(TrackAction.playNext.menuId, playNextTrackActionId);
      expect(TrackAction.addToQueue.menuId, addToQueueTrackActionId);
      expect(TrackAction.addToPlaylist.menuId, addToPlaylistTrackActionId);
      expect(TrackAction.matchLyrics.menuId, matchLyricsTrackActionId);
      expect(TrackAction.addToRemote.menuId, addToRemoteTrackActionId);
    });
```

Create `test/ui/handlers/track_action_menu_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/ui/handlers/track_action_handler.dart';
import 'package:fmp/ui/handlers/track_action_menu.dart';

void main() {
  group('buildCommonTrackActionMenuItems', () {
    test('single track menu exposes all common actions in stable order', () {
      final items = buildCommonTrackActionMenuItems(
        translations: AppLocale.en.translations,
      );

      expect(
        items.map((item) => item.id),
        [
          playTrackActionId,
          playNextTrackActionId,
          addToQueueTrackActionId,
          addToPlaylistTrackActionId,
          matchLyricsTrackActionId,
          addToRemoteTrackActionId,
        ],
      );
      expect(items.first.icon, Icons.play_arrow);
      expect(items.first.trackAction, TrackAction.play);
    });

    test('multi track menu omits single-only play and lyrics actions', () {
      final items = buildCommonTrackActionMenuItems(
        translations: AppLocale.en.translations,
        scope: TrackActionMenuScope.multi,
      );

      expect(
        items.map((item) => item.id),
        [
          playNextTrackActionId,
          addToQueueTrackActionId,
          addToPlaylistTrackActionId,
          addToRemoteTrackActionId,
        ],
      );
      expect(items.any((item) => item.id == playTrackActionId), isFalse);
      expect(items.any((item) => item.id == matchLyricsTrackActionId), isFalse);
    });

    test('options hide unsupported actions for page child rows', () {
      final items = buildCommonTrackActionMenuItems(
        translations: AppLocale.en.translations,
        options: const TrackActionMenuOptions(
          includePlay: false,
          includeAddToPlaylist: false,
          includeMatchLyrics: false,
          includeAddToRemote: false,
        ),
      );

      expect(
        items.map((item) => item.id),
        [playNextTrackActionId, addToQueueTrackActionId],
      );
    });
  });
}
```

- [ ] **Step 2: Run the descriptor tests and verify failure**

Run: `flutter test test/ui/handlers/track_action_handler_test.dart test/ui/handlers/track_action_menu_test.dart`

Expected: FAIL because `menuId`, public action-id constants, and `track_action_menu.dart` do not exist.

- [ ] **Step 3: Expose stable action ids in the handler**

In `lib/ui/handlers/track_action_handler.dart`, replace lines 4-9 and add the extension below `enum TrackAction`:

```dart
const playTrackActionId = 'play';
const playNextTrackActionId = 'play_next';
const addToQueueTrackActionId = 'add_to_queue';
const addToPlaylistTrackActionId = 'add_to_playlist';
const matchLyricsTrackActionId = 'matchLyrics';
const addToRemoteTrackActionId = 'add_to_remote';

extension TrackActionMenuId on TrackAction {
  String get menuId {
    switch (this) {
      case TrackAction.play:
        return playTrackActionId;
      case TrackAction.playNext:
        return playNextTrackActionId;
      case TrackAction.addToQueue:
        return addToQueueTrackActionId;
      case TrackAction.addToPlaylist:
        return addToPlaylistTrackActionId;
      case TrackAction.matchLyrics:
        return matchLyricsTrackActionId;
      case TrackAction.addToRemote:
        return addToRemoteTrackActionId;
    }
  }
}
```

Then update `tryParseTrackAction` to use the new public constants:

```dart
TrackAction? tryParseTrackAction(String action) {
  switch (action) {
    case playTrackActionId:
      return TrackAction.play;
    case playNextTrackActionId:
      return TrackAction.playNext;
    case addToQueueTrackActionId:
      return TrackAction.addToQueue;
    case addToPlaylistTrackActionId:
      return TrackAction.addToPlaylist;
    case matchLyricsTrackActionId:
      return TrackAction.matchLyrics;
    case addToRemoteTrackActionId:
      return TrackAction.addToRemote;
  }

  return null;
}
```

- [ ] **Step 4: Implement menu descriptor builders**

Create `lib/ui/handlers/track_action_menu.dart`:

```dart
import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import 'track_action_handler.dart';

enum TrackActionMenuScope {
  single,
  multi,
}

class TrackActionMenuOptions {
  const TrackActionMenuOptions({
    this.includePlay = true,
    this.includePlayNext = true,
    this.includeAddToQueue = true,
    this.includeAddToPlaylist = true,
    this.includeMatchLyrics = true,
    this.includeAddToRemote = true,
  });

  final bool includePlay;
  final bool includePlayNext;
  final bool includeAddToQueue;
  final bool includeAddToPlaylist;
  final bool includeMatchLyrics;
  final bool includeAddToRemote;
}

class TrackActionMenuItem {
  const TrackActionMenuItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.trackAction,
    this.enabled = true,
    this.destructive = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final TrackAction trackAction;
  final bool enabled;
  final bool destructive;
}

List<TrackActionMenuItem> buildCommonTrackActionMenuItems({
  required Translations translations,
  TrackActionMenuScope scope = TrackActionMenuScope.single,
  TrackActionMenuOptions options = const TrackActionMenuOptions(),
}) {
  final isSingle = scope == TrackActionMenuScope.single;
  final items = <TrackActionMenuItem>[];

  if (isSingle && options.includePlay) {
    items.add(
      TrackActionMenuItem(
        id: playTrackActionId,
        label: translations.general.play,
        icon: Icons.play_arrow,
        trackAction: TrackAction.play,
      ),
    );
  }

  if (options.includePlayNext) {
    items.add(
      TrackActionMenuItem(
        id: playNextTrackActionId,
        label: translations.general.playNext,
        icon: Icons.queue_play_next,
        trackAction: TrackAction.playNext,
      ),
    );
  }

  if (options.includeAddToQueue) {
    items.add(
      TrackActionMenuItem(
        id: addToQueueTrackActionId,
        label: translations.general.addToQueue,
        icon: Icons.add_to_queue,
        trackAction: TrackAction.addToQueue,
      ),
    );
  }

  if (options.includeAddToPlaylist) {
    items.add(
      TrackActionMenuItem(
        id: addToPlaylistTrackActionId,
        label: translations.general.addToPlaylist,
        icon: Icons.playlist_add,
        trackAction: TrackAction.addToPlaylist,
      ),
    );
  }

  if (isSingle && options.includeMatchLyrics) {
    items.add(
      TrackActionMenuItem(
        id: matchLyricsTrackActionId,
        label: translations.lyrics.matchLyrics,
        icon: Icons.lyrics_outlined,
        trackAction: TrackAction.matchLyrics,
      ),
    );
  }

  if (options.includeAddToRemote) {
    items.add(
      TrackActionMenuItem(
        id: addToRemoteTrackActionId,
        label: translations.remote.addToFavorites,
        icon: Icons.cloud_upload_outlined,
        trackAction: TrackAction.addToRemote,
      ),
    );
  }

  return items;
}

List<PopupMenuEntry<String>> buildTrackActionPopupMenuEntries(
  List<TrackActionMenuItem> items, {
  Color? destructiveColor,
}) {
  return [
    for (final item in items)
      PopupMenuItem(
        value: item.id,
        enabled: item.enabled,
        child: ListTile(
          leading: Icon(
            item.icon,
            color: item.destructive ? destructiveColor : null,
          ),
          title: Text(
            item.label,
            style: item.destructive && destructiveColor != null
                ? TextStyle(color: destructiveColor)
                : null,
          ),
          contentPadding: EdgeInsets.zero,
        ),
      ),
  ];
}
```

- [ ] **Step 5: Run descriptor tests and verify pass**

Run: `flutter test test/ui/handlers/track_action_handler_test.dart test/ui/handlers/track_action_menu_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit descriptor contract**

```bash
git add lib/ui/handlers/track_action_handler.dart lib/ui/handlers/track_action_menu.dart test/ui/handlers/track_action_handler_test.dart test/ui/handlers/track_action_menu_test.dart
git commit -m "refactor(ui): define shared track action menu descriptors"
```

### Task 2: Common Track Action Coordinator

**Files:**
- Modify: `lib/ui/handlers/track_action_handler.dart:69-145`
- Create: `lib/ui/handlers/track_action_coordinator.dart`
- Modify: `test/ui/handlers/track_action_handler_test.dart:5-109`

- [ ] **Step 1: Add failing multi-track handler tests**

Append these tests inside `group('TrackActionHandler', () { ... })` in `test/ui/handlers/track_action_handler_test.dart`:

```dart
    test('multi addToQueue delegates each selected track and reports count', () async {
      final audio = FakeTrackActionAudioController()..addToQueueResult = true;
      final sink = FakeMultiTrackActionFeedbackSink();
      final handler = MultiTrackActionHandler(
        audioController: audio,
        feedbackSink: sink,
      );
      final tracks = [
        buildTrack(sourceId: 'track-1', title: 'Track 1'),
        buildTrack(sourceId: 'track-2', title: 'Track 2'),
      ];

      await handler.handle(
        TrackAction.addToQueue,
        tracks: tracks,
        isLoggedIn: (_) => true,
        onAddToPlaylist: () async {},
        onAddToRemote: (_) async {},
      );

      expect(audio.addToQueueCalls.map((track) => track.sourceId), [
        'track-1',
        'track-2',
      ]);
      expect(sink.addedToQueueCounts, [2]);
    });

    test('multi playNext adds tracks in reverse to preserve visible order', () async {
      final audio = FakeTrackActionAudioController()..addNextResult = true;
      final sink = FakeMultiTrackActionFeedbackSink();
      final handler = MultiTrackActionHandler(
        audioController: audio,
        feedbackSink: sink,
      );
      final tracks = [
        buildTrack(sourceId: 'track-1', title: 'Track 1'),
        buildTrack(sourceId: 'track-2', title: 'Track 2'),
      ];

      await handler.handle(
        TrackAction.playNext,
        tracks: tracks,
        isLoggedIn: (_) => true,
        onAddToPlaylist: () async {},
        onAddToRemote: (_) async {},
      );

      expect(audio.addNextCalls.map((track) => track.sourceId), [
        'track-2',
        'track-1',
      ]);
      expect(sink.addedToNextCounts, [2]);
    });

    test('multi addToRemote filters logged-out platforms and reports skipped platforms', () async {
      final audio = FakeTrackActionAudioController();
      final sink = FakeMultiTrackActionFeedbackSink();
      final handler = MultiTrackActionHandler(
        audioController: audio,
        feedbackSink: sink,
      );
      final bilibiliTrack = buildTrack(sourceId: 'track-1', title: 'Track 1')
        ..sourceType = SourceType.bilibili;
      final youtubeTrack = buildTrack(sourceId: 'track-2', title: 'Track 2')
        ..sourceType = SourceType.youtube;
      var remoteTracks = <Track>[];

      await handler.handle(
        TrackAction.addToRemote,
        tracks: [bilibiliTrack, youtubeTrack],
        isLoggedIn: (sourceType) => sourceType == SourceType.bilibili,
        onAddToPlaylist: () async {},
        onAddToRemote: (tracks) async {
          remoteTracks = tracks;
        },
      );

      expect(remoteTracks, [bilibiliTrack]);
      expect(sink.skippedPlatformMessages.single, contains(SourceType.youtube.displayName));
    });
```

Add this fake below `FakeTrackActionFeedbackSink`:

```dart
class FakeMultiTrackActionFeedbackSink implements MultiTrackActionFeedbackSink {
  final List<int> addedToNextCounts = [];
  final List<int> addedToQueueCounts = [];
  final List<String> skippedPlatformMessages = [];
  int loginPrompts = 0;

  @override
  void showAddedToNext(int count) {
    addedToNextCounts.add(count);
  }

  @override
  void showAddedToQueue(int count) {
    addedToQueueCounts.add(count);
  }

  @override
  void showPleaseLogin() {
    loginPrompts++;
  }

  @override
  void showSkippedNotLoggedIn(Set<String> platforms) {
    skippedPlatformMessages.add(platforms.join('、'));
  }
}
```

- [ ] **Step 2: Run handler tests and verify failure**

Run: `flutter test test/ui/handlers/track_action_handler_test.dart`

Expected: FAIL because `MultiTrackActionHandler` and `MultiTrackActionFeedbackSink` do not exist.

- [ ] **Step 3: Implement multi-track action handling**

In `lib/ui/handlers/track_action_handler.dart`, add this code below `CallbackTrackActionFeedbackSink`:

```dart
abstract class MultiTrackActionFeedbackSink {
  void showAddedToNext(int count);
  void showAddedToQueue(int count);
  void showPleaseLogin();
  void showSkippedNotLoggedIn(Set<String> platforms);
}

class CallbackMultiTrackActionFeedbackSink
    implements MultiTrackActionFeedbackSink {
  CallbackMultiTrackActionFeedbackSink({
    required this.onAddedToNext,
    required this.onAddedToQueue,
    required this.onPleaseLogin,
    required this.onSkippedNotLoggedIn,
  });

  final void Function(int count) onAddedToNext;
  final void Function(int count) onAddedToQueue;
  final void Function() onPleaseLogin;
  final void Function(Set<String> platforms) onSkippedNotLoggedIn;

  @override
  void showAddedToNext(int count) => onAddedToNext(count);

  @override
  void showAddedToQueue(int count) => onAddedToQueue(count);

  @override
  void showPleaseLogin() => onPleaseLogin();

  @override
  void showSkippedNotLoggedIn(Set<String> platforms) {
    onSkippedNotLoggedIn(platforms);
  }
}

class MultiTrackActionHandler {
  MultiTrackActionHandler({
    required TrackActionAudioController audioController,
    required MultiTrackActionFeedbackSink feedbackSink,
  })  : _audioController = audioController,
        _feedbackSink = feedbackSink;

  final TrackActionAudioController _audioController;
  final MultiTrackActionFeedbackSink _feedbackSink;

  Future<void> handle(
    TrackAction action, {
    required List<Track> tracks,
    required bool Function(SourceType sourceType) isLoggedIn,
    required Future<void> Function() onAddToPlaylist,
    required Future<void> Function(List<Track> tracks) onAddToRemote,
  }) async {
    switch (action) {
      case TrackAction.play:
      case TrackAction.matchLyrics:
        throw ArgumentError('Unsupported multi-track action: $action');
      case TrackAction.playNext:
        var addedCount = 0;
        for (final track in tracks.reversed) {
          final added = await _audioController.addNext(track);
          if (added) {
            addedCount++;
          }
        }
        _feedbackSink.showAddedToNext(addedCount);
        return;
      case TrackAction.addToQueue:
        var addedCount = 0;
        for (final track in tracks) {
          final added = await _audioController.addToQueue(track);
          if (added) {
            addedCount++;
          }
        }
        _feedbackSink.showAddedToQueue(addedCount);
        return;
      case TrackAction.addToPlaylist:
        await onAddToPlaylist();
        return;
      case TrackAction.addToRemote:
        final remoteTracks = tracks.where((track) {
          return isLoggedIn(track.sourceType);
        }).toList();
        if (remoteTracks.isEmpty) {
          _feedbackSink.showPleaseLogin();
          return;
        }

        final skippedPlatforms = tracks
            .where((track) => !isLoggedIn(track.sourceType))
            .map((track) => track.sourceType.displayName)
            .toSet();
        if (skippedPlatforms.isNotEmpty) {
          _feedbackSink.showSkippedNotLoggedIn(skippedPlatforms);
        }

        await onAddToRemote(remoteTracks);
        return;
    }
  }
}
```

- [ ] **Step 4: Add widget-facing coordinator**

Create `lib/ui/handlers/track_action_coordinator.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/toast_service.dart';
import '../../data/models/track.dart';
import '../../i18n/strings.g.dart';
import '../../providers/account_provider.dart';
import '../../services/audio/audio_provider.dart';
import '../widgets/dialogs/add_to_playlist_dialog.dart';
import '../widgets/dialogs/add_to_remote_playlist_dialog.dart';
import '../pages/lyrics/lyrics_search_sheet.dart';
import 'track_action_handler.dart';

class TrackActionCoordinator {
  const TrackActionCoordinator._();

  static Future<void> handleSingle({
    required BuildContext context,
    required WidgetRef ref,
    required Track track,
    required String actionId,
  }) async {
    final action = parseTrackAction(actionId);
    final handler = TrackActionHandler(
      audioController: AudioControllerTrackActionAdapter(
        ref.read(audioControllerProvider.notifier),
      ),
      feedbackSink: CallbackTrackActionFeedbackSink(
        onAddedToNext: () {
          if (context.mounted) {
            ToastService.success(context, t.general.addedToNext);
          }
        },
        onAddedToQueue: () {
          if (context.mounted) {
            ToastService.success(context, t.general.addedToQueue);
          }
        },
        onPleaseLogin: () {
          if (context.mounted) {
            ToastService.show(context, t.remote.pleaseLogin);
          }
        },
      ),
    );

    await handler.handle(
      action,
      track: track,
      isLoggedIn: ref.read(isLoggedInProvider(track.sourceType)),
      onAddToPlaylist: () async {
        if (context.mounted) {
          await showAddToPlaylistDialog(context: context, track: track);
        }
      },
      onMatchLyrics: () async {
        if (context.mounted) {
          await showLyricsSearchSheet(context: context, track: track);
        }
      },
      onAddToRemote: () async {
        if (context.mounted) {
          await showAddToRemotePlaylistDialog(context: context, track: track);
        }
      },
    );
  }

  static Future<void> handleMulti({
    required BuildContext context,
    required WidgetRef ref,
    required List<Track> tracks,
    required String actionId,
  }) async {
    final action = parseTrackAction(actionId);
    final handler = MultiTrackActionHandler(
      audioController: AudioControllerTrackActionAdapter(
        ref.read(audioControllerProvider.notifier),
      ),
      feedbackSink: CallbackMultiTrackActionFeedbackSink(
        onAddedToNext: (count) {
          if (context.mounted) {
            ToastService.success(context, t.selectionMode.addedToNext(count: count));
          }
        },
        onAddedToQueue: (count) {
          if (context.mounted) {
            ToastService.success(context, t.selectionMode.addedToQueue(count: count));
          }
        },
        onPleaseLogin: () {
          if (context.mounted) {
            ToastService.show(context, t.remote.pleaseLogin);
          }
        },
        onSkippedNotLoggedIn: (platforms) {
          if (context.mounted) {
            ToastService.show(
              context,
              t.remote.skippedNotLoggedIn(platforms: platforms.join('、')),
            );
          }
        },
      ),
    );

    await handler.handle(
      action,
      tracks: tracks,
      isLoggedIn: (sourceType) => ref.read(isLoggedInProvider(sourceType)),
      onAddToPlaylist: () async {
        if (context.mounted) {
          await showAddToPlaylistDialog(context: context, tracks: tracks);
        }
      },
      onAddToRemote: (remoteTracks) async {
        if (context.mounted) {
          await showAddToRemotePlaylistDialogMulti(
            context: context,
            tracks: remoteTracks,
          );
        }
      },
    );
  }
}
```

- [ ] **Step 5: Run focused tests and analyzer for new files**

Run: `flutter test test/ui/handlers/track_action_handler_test.dart test/ui/handlers/track_action_menu_test.dart`

Expected: PASS.

Run: `flutter analyze`

Expected: PASS.

- [ ] **Step 6: Commit coordinator and multi-track handler**

```bash
git add lib/ui/handlers/track_action_handler.dart lib/ui/handlers/track_action_coordinator.dart test/ui/handlers/track_action_handler_test.dart
git commit -m "refactor(ui): centralize common track action execution"
```

### Task 3: Selection Menu Migration

**Files:**
- Modify: `lib/ui/widgets/selection_mode_app_bar.dart:13-374`
- Test: `flutter analyze`

- [ ] **Step 1: Replace the selection action enum with descriptor ids**

In `lib/ui/widgets/selection_mode_app_bar.dart`, replace the local `SelectionAction` enum with aliases to the shared action ids plus page-specific ids:

```dart
const selectionActionAddToQueue = addToQueueTrackActionId;
const selectionActionPlayNext = playNextTrackActionId;
const selectionActionAddToPlaylist = addToPlaylistTrackActionId;
const selectionActionAddToRemotePlaylist = addToRemoteTrackActionId;
const selectionActionRemoveFromRemotePlaylist = 'remove_from_remote';
const selectionActionDownload = 'download';
const selectionActionDelete = 'delete';
```

Change the widget field from:

```dart
final Set<SelectionAction> availableActions;
```

to:

```dart
final Set<String> availableActions;
```

Update the constructor parameter type to match.

- [ ] **Step 2: Render common multi-track entries from descriptors**

Replace the `PopupMenuButton.itemBuilder` block with:

```dart
          itemBuilder: (context) => _buildSelectionMenuEntries(colorScheme),
```

Add this method inside `SelectionModeAppBar`:

```dart
  List<PopupMenuEntry<String>> _buildSelectionMenuEntries(
    ColorScheme colorScheme,
  ) {
    final commonItems = buildCommonTrackActionMenuItems(
      translations: t,
      scope: TrackActionMenuScope.multi,
      options: TrackActionMenuOptions(
        includePlayNext: availableActions.contains(selectionActionPlayNext),
        includeAddToQueue: availableActions.contains(selectionActionAddToQueue),
        includeAddToPlaylist:
            availableActions.contains(selectionActionAddToPlaylist),
        includeAddToRemote:
            availableActions.contains(selectionActionAddToRemotePlaylist),
      ),
    );

    return [
      ...buildTrackActionPopupMenuEntries(commonItems),
      if (availableActions.contains(selectionActionRemoveFromRemotePlaylist))
        PopupMenuItem(
          value: selectionActionRemoveFromRemotePlaylist,
          child: ListTile(
            leading: Icon(Icons.cloud_off_outlined, color: colorScheme.error),
            title: Text(
              t.remote.removeFromFavorites,
              style: TextStyle(color: colorScheme.error),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (availableActions.contains(selectionActionDownload))
        PopupMenuItem(
          value: selectionActionDownload,
          child: ListTile(
            leading: const Icon(Icons.download),
            title: Text(t.selectionMode.download),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (availableActions.contains(selectionActionDelete))
        PopupMenuItem(
          value: selectionActionDelete,
          child: ListTile(
            leading: Icon(Icons.delete_outline, color: colorScheme.error),
            title: Text(
              t.selectionMode.removeFromPlaylist,
              style: TextStyle(color: colorScheme.error),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
    ];
  }
```

- [ ] **Step 3: Dispatch common selection actions through the coordinator**

Replace the common cases in `_handleMenuAction` with one parse check:

```dart
  void _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    List<Track> tracks,
  ) {
    if (tryParseTrackAction(action) != null) {
      _handleCommonAction(context, ref, action, tracks);
      return;
    }

    switch (action) {
      case selectionActionRemoveFromRemotePlaylist:
        _removeFromRemotePlaylist(context, ref, tracks);
        break;
      case selectionActionDownload:
        _download(context, ref, tracks);
        break;
      case selectionActionDelete:
        _delete(context, ref, tracks);
        break;
    }
  }

  Future<void> _handleCommonAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    List<Track> tracks,
  ) async {
    final notifier = ref.read(selectionProvider.notifier);
    notifier.exitSelectionMode();
    await TrackActionCoordinator.handleMulti(
      context: context,
      ref: ref,
      tracks: tracks,
      actionId: action,
    );
  }
```

Remove the old private `_addToQueue`, `_playNext`, `_addToPlaylist`, and `_addToRemotePlaylist` methods after `_handleCommonAction` is in place. Keep `_download`, `_delete`, and `_removeFromRemotePlaylist`.

- [ ] **Step 4: Update page call sites to pass action ids**

In `lib/ui/pages/search/search_page.dart`, replace the available-action set with:

```dart
    const availableActions = <String>{
      selectionActionAddToQueue,
      selectionActionPlayNext,
      selectionActionAddToPlaylist,
      selectionActionAddToRemotePlaylist,
    };
```

In `lib/ui/pages/library/playlist_detail_page.dart`, replace the available-action set with:

```dart
    final availableActions = <String>{
      selectionActionAddToQueue,
      selectionActionPlayNext,
      selectionActionAddToPlaylist,
      selectionActionAddToRemotePlaylist,
      if (isImported && !isMix) selectionActionRemoveFromRemotePlaylist,
      if (!isMix) selectionActionDownload,
      if (!isImported && !isMix) selectionActionDelete,
    };
```

In `lib/ui/pages/explore/explore_page.dart`, replace the available-action set with:

```dart
    const availableActions = <String>{
      selectionActionAddToQueue,
      selectionActionPlayNext,
      selectionActionAddToPlaylist,
      selectionActionAddToRemotePlaylist,
    };
```

- [ ] **Step 5: Run analyzer for selection migration**

Run: `flutter analyze`

Expected: PASS. The implementation is complete when the analyzer reports no remaining `SelectionAction.` references.

- [ ] **Step 6: Commit selection migration**

```bash
git add lib/ui/widgets/selection_mode_app_bar.dart lib/ui/pages/search/search_page.dart lib/ui/pages/library/playlist_detail_page.dart lib/ui/pages/explore/explore_page.dart
git commit -m "refactor(ui): route selection menus through track action descriptors"
```

### Task 4: Representative Single-Track Menu Migration

**Files:**
- Modify: `lib/ui/pages/explore/explore_page.dart:939-1029`
- Modify: `lib/ui/pages/home/home_page.dart:939-1029`
- Modify: `lib/ui/pages/library/downloaded_category_page.dart:893-1000`
- Test: `flutter analyze`

- [ ] **Step 1: Migrate Explore track menus to shared descriptors**

In `lib/ui/pages/explore/explore_page.dart`, add imports for:

```dart
import '../../handlers/track_action_coordinator.dart';
import '../../handlers/track_action_menu.dart';
```

Replace the `_ExploreTrackTile._buildMenuItems()` body with:

```dart
  List<PopupMenuEntry<String>> _buildMenuItems() {
    return buildTrackActionPopupMenuEntries(
      buildCommonTrackActionMenuItems(translations: t),
    );
  }
```

Replace `_ExploreTrackTile._handleMenuAction(...)` with:

```dart
  Future<void> _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    await TrackActionCoordinator.handleSingle(
      context: context,
      ref: ref,
      track: track,
      actionId: action,
    );
  }
```

- [ ] **Step 2: Migrate Home history track menus to shared descriptors**

In `lib/ui/pages/home/home_page.dart`, add imports for the shared coordinator and menu helper using the correct relative path for this file:

```dart
import '../../handlers/track_action_coordinator.dart';
import '../../handlers/track_action_menu.dart';
```

Replace the `_HomeHistoryTrackCard._buildMenuItems()` body with:

```dart
  List<PopupMenuEntry<String>> _buildMenuItems() {
    return buildTrackActionPopupMenuEntries(
      buildCommonTrackActionMenuItems(translations: t),
    );
  }
```

Replace `_HomeHistoryTrackCard._handleMenuAction(...)` with:

```dart
  Future<void> _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    await TrackActionCoordinator.handleSingle(
      context: context,
      ref: ref,
      track: track,
      actionId: action,
    );
  }
```

- [ ] **Step 3: Migrate downloaded track menus while preserving delete injection**

In `lib/ui/pages/library/downloaded_category_page.dart`, add imports for:

```dart
import '../../handlers/track_action_coordinator.dart';
import '../../handlers/track_action_menu.dart';
```

Replace `_DownloadedTrackTile._buildMenuItems()` with:

```dart
  List<PopupMenuEntry<String>> _buildMenuItems() {
    return [
      ...buildTrackActionPopupMenuEntries(
        buildCommonTrackActionMenuItems(
          translations: t,
          options: const TrackActionMenuOptions(
            includePlay: false,
            includeAddToRemote: false,
          ),
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'delete',
        child: ListTile(
          leading: const Icon(Icons.delete_outline),
          title: Text(t.library.deleteDownload),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ];
  }
```

In `_DownloadedTrackTile._handleMenuAction(...)`, replace the old `TrackActionHandler` construction and `handler.handle(...)` block with:

```dart
    await TrackActionCoordinator.handleSingle(
      context: context,
      ref: ref,
      track: track,
      actionId: action,
    );
```

Keep the existing `if (action == 'delete') { ... return; }` branch unchanged.

- [ ] **Step 4: Run analyzer for representative migrations**

Run: `flutter analyze`

Expected: PASS.

- [ ] **Step 5: Commit representative migrations**

```bash
git add lib/ui/pages/explore/explore_page.dart lib/ui/pages/home/home_page.dart lib/ui/pages/library/downloaded_category_page.dart
git commit -m "refactor(ui): reuse track action menus on core surfaces"
```

### Task 5: Search and Playlist Detail Menu Migration

**Files:**
- Modify: `lib/ui/pages/search/search_page.dart:863-969,1187-1194,1278-1283,1430-1490,1589-1596`
- Modify: `lib/ui/pages/library/playlist_detail_page.dart:497-566,1316-1358,1632-1790`
- Test: `flutter analyze`

- [ ] **Step 1: Migrate search single-track menu rendering**

In `lib/ui/pages/search/search_page.dart`, add imports for:

```dart
import '../../handlers/track_action_coordinator.dart';
import '../../handlers/track_action_menu.dart';
```

Replace `_VideoResultCard._buildMenuItems()` and `_LocalTrackTile._buildMenuItems()` with:

```dart
  List<PopupMenuEntry<String>> _buildMenuItems() {
    return buildTrackActionPopupMenuEntries(
      buildCommonTrackActionMenuItems(translations: t),
    );
  }
```

Replace `_VideoPageTile._buildMenuItems()` with:

```dart
  List<PopupMenuEntry<String>> _buildMenuItems() {
    return buildTrackActionPopupMenuEntries(
      buildCommonTrackActionMenuItems(
        translations: t,
        options: const TrackActionMenuOptions(
          includeAddToPlaylist: false,
          includeMatchLyrics: false,
          includeAddToRemote: false,
        ),
      ),
    );
  }
```

- [ ] **Step 2: Route search single-track common actions through coordinator**

In the search page state method `_handleMenuAction(Track track, String action)`, keep the multi-page branch unchanged. Replace the non-multi-page `TrackActionHandler` construction and `handler.handle(...)` block with:

```dart
    await TrackActionCoordinator.handleSingle(
      context: context,
      ref: ref,
      track: track,
      actionId: action,
    );
```

In `_LocalPlaylistGroupTile._handleMenuAction(...)`, keep the existing group behavior because a grouped row may represent multiple local tracks. Only replace string literals in the `switch` cases with public constants:

```dart
      case playTrackActionId:
      case playNextTrackActionId:
      case addToQueueTrackActionId:
      case addToPlaylistTrackActionId:
      case addToRemoteTrackActionId:
```

- [ ] **Step 3: Migrate playlist detail selection menu builder**

In `lib/ui/pages/library/playlist_detail_page.dart`, add imports for:

```dart
import '../../handlers/track_action_coordinator.dart';
import '../../handlers/track_action_menu.dart';
```

In `_PlaylistDetailPageState._buildSelectionMenuItems(...)`, build common entries first with `buildCommonTrackActionMenuItems(scope: TrackActionMenuScope.multi, ...)` and keep page-specific entries after them:

```dart
    final commonItems = buildCommonTrackActionMenuItems(
      translations: t,
      scope: TrackActionMenuScope.multi,
      options: TrackActionMenuOptions(
        includeAddToQueue: availableActions.contains(selectionActionAddToQueue),
        includePlayNext: availableActions.contains(selectionActionPlayNext),
        includeAddToPlaylist:
            availableActions.contains(selectionActionAddToPlaylist),
        includeAddToRemote:
            availableActions.contains(selectionActionAddToRemotePlaylist),
      ),
    );
```

Then start the returned list with:

```dart
      ...buildTrackActionPopupMenuEntries(commonItems),
```

Keep existing page-specific `remove_from_remote`, `download`, and `delete` entries, but use the selection constants for their values.

- [ ] **Step 4: Migrate playlist detail track-row menu rendering**

Replace `_PlaylistTrackTile._buildMenuItems(BuildContext context)` common entries with descriptor entries and keep page-specific actions:

```dart
  List<PopupMenuEntry<String>> _buildMenuItems(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return [
      ...buildTrackActionPopupMenuEntries(
        buildCommonTrackActionMenuItems(
          translations: t,
          options: TrackActionMenuOptions(
            includePlay: false,
            includeAddToPlaylist: !isPartOfMultiPage,
          ),
        ),
      ),
      if (!isMix)
        PopupMenuItem(
          value: 'download',
          child: ListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(t.library.detail.download),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (isImported && !isMix)
        PopupMenuItem(
          value: 'remove_from_remote',
          child: ListTile(
            leading: Icon(Icons.cloud_off_outlined, color: colorScheme.error),
            title: Text(
              t.remote.removeFromFavorites,
              style: TextStyle(color: colorScheme.error),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (!isImported)
        PopupMenuItem(
          value: 'remove',
          child: ListTile(
            leading: const Icon(Icons.remove_circle_outline),
            title: Text(t.library.detail.removeFromPlaylist),
            contentPadding: EdgeInsets.zero,
          ),
        ),
    ];
  }
```

In `_PlaylistTrackTile._handleMenuAction(...)`, after the page-specific `switch`, replace the old `TrackActionHandler` construction and `handler.handle(...)` block with:

```dart
    await TrackActionCoordinator.handleSingle(
      context: context,
      ref: ref,
      track: track,
      actionId: action,
    );
```

- [ ] **Step 5: Keep playlist detail group actions page-specific**

Do not force `_PlaylistGroupHeader._buildMenuItems()` into `TrackActionMenuItem`: its actions operate on grouped parts (`play_first`, `add_all_to_queue`, `download_all`, `remove_all`) and are not the same contract as single/multi common track actions. Replace any common string literals that overlap with shared actions (`add_to_playlist`, `add_to_remote`) with `addToPlaylistTrackActionId` and `addToRemoteTrackActionId` only.

- [ ] **Step 6: Run analyzer for broad migration**

Run: `flutter analyze`

Expected: PASS.

- [ ] **Step 7: Commit search and playlist detail migrations**

```bash
git add lib/ui/pages/search/search_page.dart lib/ui/pages/library/playlist_detail_page.dart
git commit -m "refactor(ui): share track action menus in search and playlist detail"
```

### Task 6: Cleanup, Documentation, and Verification

**Files:**
- Modify: `CLAUDE.md`
- Inspect: `lib/ui/pages/**/*.dart`
- Test: `flutter analyze`
- Test: `flutter test test/ui/handlers/track_action_handler_test.dart test/ui/handlers/track_action_menu_test.dart`

- [ ] **Step 1: Search for remaining duplicated common action menu blocks**

Run these searches:

```bash
rg "value: 'play'|value: 'play_next'|value: 'add_to_queue'|value: 'add_to_playlist'|value: 'matchLyrics'|value: 'add_to_remote'" lib/ui
rg "TrackActionHandler\(" lib/ui
```

Expected:
- Remaining raw values should be page-specific group/radio/history delete actions or code already being migrated in this task.
- Remaining `TrackActionHandler(` usage in UI pages should be gone; coordinator/handler usage may remain in `lib/ui/handlers/` and tests.

- [ ] **Step 2: Replace leftover common single-track menu blocks**

Replace these remaining single-track menu builders when the Step 1 search identifies them:

- `lib/ui/pages/history/play_history_page.dart` track history menu: use `buildCommonTrackActionMenuItems(translations: t)` for the common actions, then append the existing `delete` and `delete_all` actions after a divider.
- `lib/ui/widgets/track_detail_panel.dart` track menu, if it still defines queue/playlist/lyrics/remote actions inline: use `buildCommonTrackActionMenuItems(translations: t)` for common actions and keep any panel-only action local.

Use this replacement for full common single-track menus:

```dart
  List<PopupMenuEntry<String>> _buildMenuItems() {
    return buildTrackActionPopupMenuEntries(
      buildCommonTrackActionMenuItems(translations: t),
    );
  }
```

Use this replacement for menus that intentionally support only play-next and add-to-queue:

```dart
  List<PopupMenuEntry<String>> _buildMenuItems() {
    return buildTrackActionPopupMenuEntries(
      buildCommonTrackActionMenuItems(
        translations: t,
        options: const TrackActionMenuOptions(
          includePlay: false,
          includeAddToPlaylist: false,
          includeMatchLyrics: false,
          includeAddToRemote: false,
        ),
      ),
    );
  }
```

For leftover UI handlers that build `TrackActionHandler` directly, replace them with:

```dart
    await TrackActionCoordinator.handleSingle(
      context: context,
      ref: ref,
      track: track,
      actionId: action,
    );
```

Keep custom group, radio, playlist-card, delete, download, remove-from-playlist, and remove-from-remote actions local.

- [ ] **Step 3: Document the UI action-menu rule**

In `CLAUDE.md`, under `## UI Development Guidelines` → `### Code Consistency ⚠️ CRITICAL`, add this numbered item after the existing menu-action guidance:

```markdown
6. **Track action menus:** Common track actions must use `buildCommonTrackActionMenuItems()` / `buildTrackActionPopupMenuEntries()` and dispatch through `TrackActionCoordinator`. Page-specific actions (download, delete, remove-from-playlist, remove-from-remote, group actions) should be appended/injected locally instead of duplicating common queue/playlist/lyrics/remote action definitions.
```

Renumber later items if needed so the list remains sequential.

- [ ] **Step 4: Run focused tests**

Run: `flutter test test/ui/handlers/track_action_handler_test.dart test/ui/handlers/track_action_menu_test.dart`

Expected: PASS.

- [ ] **Step 5: Run full analyzer**

Run: `flutter analyze`

Expected: PASS.

- [ ] **Step 6: Run full test suite**

Run: `flutter test`

Expected: PASS. Existing non-fatal pub advisory decode warnings may appear, but test failures must be fixed before continuing.

- [ ] **Step 7: Commit cleanup and docs**

```bash
git add CLAUDE.md lib/ui test/ui
git commit -m "docs(ui): document shared track action menus"
```

## Self-Review

**Spec coverage:** Phase 4 requires common action definitions, consistent queue/play-next/add-to-playlist/add-to-remote/lyrics behavior, multi-track support, and injectable page-specific actions. Tasks 1-2 define descriptors and shared handlers. Tasks 3-5 migrate selection, single-track pages, search, and playlist detail. Task 6 verifies no broad duplicated common blocks remain and documents the rule. Page-specific actions stay local.

**Placeholder scan:** This plan contains no TBD/TODO/fill-in placeholders. Commands, file paths, action ids, test code, and migration snippets are explicit.

**Type consistency:** `TrackActionMenuOptions`, `TrackActionMenuItem`, `TrackActionCoordinator`, `MultiTrackActionHandler`, `selectionAction*` constants, and public action id names are introduced before use and are used consistently across tasks.
