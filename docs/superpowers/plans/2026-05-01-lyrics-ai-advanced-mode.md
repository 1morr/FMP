# Lyrics AI Advanced Matching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an AI advanced lyrics matching mode that lets AI choose from real lyrics candidates, while defaulting AI off and giving users control over non-synced automatic matches.

**Architecture:** Keep `LyricsAutoMatchService` as the orchestration point. Keep `AiTitleParser` responsible for title parsing, add a focused `AiLyricsSelector` for candidate selection, and pass settings through existing Riverpod providers. Persist only normal `LyricsMatch` rows; AI selection is transient.

**Tech Stack:** Flutter/Dart, Riverpod, Isar, Dio OpenAI-compatible chat completions, slang i18n, flutter_test.

---

## File Structure

- Modify `lib/data/models/settings.dart`: stable AI mode mapping, default AI off, new `allowPlainLyricsAutoMatch` field.
- Regenerate ignored Isar `.g.dart` files locally with build_runner; do not commit generated files because `*.g.dart` is ignored.
- Modify `lib/providers/database_provider.dart`: repair legacy fallback/invalid AI mode indexes to off.
- Modify `lib/providers/audio_settings_provider.dart`: expose `allowPlainLyricsAutoMatch` and setter.
- Modify `lib/services/lyrics/lyrics_ai_config_service.dart`: no schema change; verify mode availability uses new enum.
- Modify `lib/services/lyrics/ai_title_parser.dart`: richer debug logs for existing title parsing.
- Create `lib/services/lyrics/ai_lyrics_selector.dart`: OpenAI-compatible candidate selection request/response parsing.
- Modify `lib/providers/lyrics_provider.dart`: provide `AiLyricsSelector` and pass advanced settings into auto-match service.
- Modify `lib/services/lyrics/lyrics_auto_match_service.dart`: new mode flow, candidate collection, plain-lyrics filtering, fallback rules.
- Modify `lib/ui/pages/settings/lyrics_source_settings_page.dart`: remove fallback option, add advanced mode and plain lyrics switch.
- Modify i18n files: `lib/i18n/en/settings.i18n.json`, `lib/i18n/zh-CN/settings.i18n.json`, `lib/i18n/zh-TW/settings.i18n.json`.
- Regenerate ignored `lib/i18n/strings.g.dart` locally with `dart run slang`; do not commit generated files because `*.g.dart` is ignored.
- Update tests under `test/data/models`, `test/providers`, and `test/services/lyrics`.
- Update `CLAUDE.md` Data Models / Lyrics System notes after implementation.

---

### Task 1: Stabilize Settings Model and Migration

**Files:**
- Modify: `lib/data/models/settings.dart:65-69,182-193,459-483`
- Modify: `lib/providers/database_provider.dart:105-119`
- Test: `test/data/models/settings_ai_title_parsing_test.dart`
- Test: `test/providers/database_migration_test.dart`

- [ ] **Step 1: Write failing settings model tests**

Replace `test/data/models/settings_ai_title_parsing_test.dart` expectations with:

```dart
test('defaults to AI off with empty connection fields', () {
  final settings = Settings();
  expect(settings.lyricsAiTitleParsingMode, LyricsAiTitleParsingMode.off);
  expect(settings.lyricsAiTitleParsingModeIndex, 0);
  expect(settings.allowPlainLyricsAutoMatch, isFalse);
  expect(settings.lyricsAiEndpoint, isEmpty);
  expect(settings.lyricsAiModel, isEmpty);
  expect(settings.lyricsAiTimeoutSeconds, 10);
});

test('maps legacy fallback index to off', () {
  final settings = Settings()..lyricsAiTitleParsingModeIndex = 1;
  expect(settings.lyricsAiTitleParsingMode, LyricsAiTitleParsingMode.off);
});

test('round-trips stable AI mode indexes', () {
  final settings = Settings();
  settings.lyricsAiTitleParsingMode = LyricsAiTitleParsingMode.alwaysAi;
  expect(settings.lyricsAiTitleParsingModeIndex, 2);
  settings.lyricsAiTitleParsingMode = LyricsAiTitleParsingMode.advancedAiSelect;
  expect(settings.lyricsAiTitleParsingModeIndex, 3);
  settings.lyricsAiTitleParsingMode = LyricsAiTitleParsingMode.off;
  expect(settings.lyricsAiTitleParsingModeIndex, 0);
});

test('invalid mode index resolves to off', () {
  final settings = Settings()..lyricsAiTitleParsingModeIndex = 99;
  expect(settings.lyricsAiTitleParsingMode, LyricsAiTitleParsingMode.off);
});
```

- [ ] **Step 2: Write failing migration tests**

In `test/providers/database_migration_test.dart`, update AI migration expectations:

```dart
expect(migratedSettings!.lyricsAiTitleParsingModeIndex, 0);
expect(migratedSettings.lyricsAiTitleParsingMode, LyricsAiTitleParsingMode.off);
expect(migratedSettings.lyricsAiTimeoutSeconds, 10);
```

Add this test in the migration group:

```dart
test('repairs legacy fallback AI mode index to off', () async {
  await openTestDatabase();
  final settings = Settings()
    ..lyricsAiTitleParsingModeIndex = 1
    ..lyricsAiTimeoutSeconds = 10;
  await isar.writeTxn(() async => isar.settings.put(settings));
  await runDatabaseMigrationForTesting(isar);
  final migratedSettings = await isar.settings.get(0);
  expect(migratedSettings!.lyricsAiTitleParsingModeIndex, 0);
  expect(migratedSettings.lyricsAiTitleParsingMode, LyricsAiTitleParsingMode.off);
});
```

- [ ] **Step 3: Run tests and verify they fail**

Run:

```bash
flutter test test/data/models/settings_ai_title_parsing_test.dart test/providers/database_migration_test.dart
```

Expected: failures mention missing `allowPlainLyricsAutoMatch`, missing `advancedAiSelect`, or old fallback defaults.

- [ ] **Step 4: Implement settings model changes**

In `lib/data/models/settings.dart`, change enum and fields:

```dart
enum LyricsAiTitleParsingMode {
  off,
  alwaysAi,
  advancedAiSelect,
}

int lyricsAiTitleParsingModeIndex = 0;
bool allowPlainLyricsAutoMatch = false;
```

Replace the getter/setter with stable persisted indexes:

```dart
@ignore
LyricsAiTitleParsingMode get lyricsAiTitleParsingMode {
  switch (lyricsAiTitleParsingModeIndex) {
    case 2:
      return LyricsAiTitleParsingMode.alwaysAi;
    case 3:
      return LyricsAiTitleParsingMode.advancedAiSelect;
    case 0:
    case 1:
    default:
      return LyricsAiTitleParsingMode.off;
  }
}

set lyricsAiTitleParsingMode(LyricsAiTitleParsingMode mode) {
  switch (mode) {
    case LyricsAiTitleParsingMode.off:
      lyricsAiTitleParsingModeIndex = 0;
    case LyricsAiTitleParsingMode.alwaysAi:
      lyricsAiTitleParsingModeIndex = 2;
    case LyricsAiTitleParsingMode.advancedAiSelect:
      lyricsAiTitleParsingModeIndex = 3;
  }
}
```

- [ ] **Step 5: Implement migration repair**

In `lib/providers/database_provider.dart`, replace AI repair block with:

```dart
if (settings.lyricsAiTimeoutSeconds < 1) {
  settings.lyricsAiTimeoutSeconds = 10;
  needsUpdate = true;
}
if (settings.lyricsAiTitleParsingModeIndex == 1 ||
    settings.lyricsAiTitleParsingModeIndex < 0 ||
    settings.lyricsAiTitleParsingModeIndex > 3) {
  settings.lyricsAiTitleParsingModeIndex = 0;
  needsUpdate = true;
}
```

- [ ] **Step 6: Regenerate Isar code**

Run:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

Expected: `lib/data/models/settings.g.dart` includes `allowPlainLyricsAutoMatch`.

- [ ] **Step 7: Run tests and commit**

Run:

```bash
flutter test test/data/models/settings_ai_title_parsing_test.dart test/providers/database_migration_test.dart
```

Expected: PASS.

Commit:

```bash
git add lib/data/models/settings.dart lib/providers/database_provider.dart test/data/models/settings_ai_title_parsing_test.dart test/providers/database_migration_test.dart
git commit -m "feat(lyrics): default AI matching mode to off"
```

### Task 2: Expose Plain-Lyrics Setting Through Providers

**Files:**
- Modify: `lib/providers/audio_settings_provider.dart:14-68,111-127,187-235`
- Test: `test/providers/audio_settings_ai_title_parsing_test.dart`

- [ ] **Step 1: Write failing provider tests**

Update defaults in `test/providers/audio_settings_ai_title_parsing_test.dart`:

```dart
expect(state.lyricsAiTitleParsingMode, LyricsAiTitleParsingMode.off);
expect(state.allowPlainLyricsAutoMatch, isFalse);
```

Add this notifier test:

```dart
test('updates plain lyrics automatic matching setting', () async {
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  final repository = _FakeSettingsRepository(Settings());
  final notifier = AudioSettingsNotifier(repository);
  await Future<void>.delayed(Duration.zero);
  await notifier.setAllowPlainLyricsAutoMatch(true);
  expect(notifier.state.allowPlainLyricsAutoMatch, isTrue);
  expect(repository.settings.allowPlainLyricsAutoMatch, isTrue);
});
```

- [ ] **Step 2: Run test and verify it fails**

Run:

```bash
flutter test test/providers/audio_settings_ai_title_parsing_test.dart
```

Expected: FAIL because `allowPlainLyricsAutoMatch` is not exposed.

- [ ] **Step 3: Implement provider state and setter**

In `AudioSettingsState`, add field/default/copyWith:

```dart
final bool allowPlainLyricsAutoMatch;

this.allowPlainLyricsAutoMatch = false,

bool? allowPlainLyricsAutoMatch,

allowPlainLyricsAutoMatch:
    allowPlainLyricsAutoMatch ?? this.allowPlainLyricsAutoMatch,
```

In `_loadSettings`, set:

```dart
allowPlainLyricsAutoMatch: _settings!.allowPlainLyricsAutoMatch,
```

Add notifier method:

```dart
Future<void> setAllowPlainLyricsAutoMatch(bool enabled) async {
  if (_settings == null) return;
  await _settingsRepository
      .update((s) => s.allowPlainLyricsAutoMatch = enabled);
  _settings!.allowPlainLyricsAutoMatch = enabled;
  state = state.copyWith(allowPlainLyricsAutoMatch: enabled);
}
```

- [ ] **Step 4: Run test and commit**

Run:

```bash
flutter test test/providers/audio_settings_ai_title_parsing_test.dart
```

Expected: PASS.

Commit:

```bash
git add lib/providers/audio_settings_provider.dart test/providers/audio_settings_ai_title_parsing_test.dart
git commit -m "feat(lyrics): expose plain lyrics auto-match setting"
```

### Task 3: Add AI Lyrics Candidate Selector

**Files:**
- Create: `lib/services/lyrics/ai_lyrics_selector.dart`
- Test: `test/services/lyrics/ai_lyrics_selector_test.dart`

- [ ] **Step 1: Write failing selector tests**

Create `test/services/lyrics/ai_lyrics_selector_test.dart` with tests for parsing and request payload:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/services/lyrics/ai_lyrics_selector.dart';

void main() {
  group('AiLyricsSelector', () {
    test('parses selected candidate JSON', () {
      final result = AiLyricsSelector.parseContent(jsonEncode({
        'selectedCandidateId': 'netease:123',
        'confidence': 0.91,
        'reason': 'good match',
      }));
      expect(result?.selectedCandidateId, 'netease:123');
      expect(result?.confidence, 0.91);
      expect(result?.reason, 'good match');
    });

    test('parses null selection JSON', () {
      final result = AiLyricsSelector.parseContent(jsonEncode({
        'selectedCandidateId': null,
        'confidence': 0.42,
        'reason': 'not reliable',
      }));
      expect(result?.selectedCandidateId, isNull);
      expect(result?.confidence, 0.42);
      expect(result?.reason, 'not reliable');
    });

    test('invalid JSON returns null', () {
      expect(AiLyricsSelector.parseContent('not json'), isNull);
    });

    test('sends candidate selection payload without API key leakage', () async {
      final dio = Dio();
      Map<String, dynamic>? capturedBody;
      dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
        capturedBody = jsonDecode(requestBody as String) as Map<String, dynamic>;
        return _jsonResponse({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'selectedCandidateId': 'netease:123',
                  'confidence': 0.91,
                  'reason': 'synced and close duration',
                }),
              },
            },
          ],
        });
      });

      final selector = AiLyricsSelector(dio: dio);
      final result = await selector.select(
        endpoint: 'https://api.example.com/v1',
        apiKey: 'secret-key',
        model: 'gpt-test',
        title: 'Video Title',
        uploader: 'Uploader',
        durationSeconds: 180,
        sourcePriority: const ['netease', 'qqmusic'],
        allowPlainLyricsAutoMatch: false,
        candidates: const [
          AiLyricsCandidate(
            candidateId: 'netease:123',
            source: 'netease',
            sourcePriorityRank: 0,
            trackName: 'Song',
            artistName: 'Artist',
            albumName: 'Album',
            durationSeconds: 181,
            videoDurationSeconds: 180,
            durationDiffSeconds: 1,
            hasSyncedLyrics: true,
            hasPlainLyrics: true,
            hasTranslatedLyrics: false,
            hasRomajiLyrics: false,
          ),
        ],
        timeoutSeconds: 5,
      );

      expect(result?.selectedCandidateId, 'netease:123');
      expect(capturedBody?['model'], 'gpt-test');
      final bodyText = jsonEncode(capturedBody);
      expect(bodyText, contains('Video Title'));
      expect(bodyText, contains('Uploader'));
      expect(bodyText, contains('netease:123'));
      expect(bodyText, isNot(contains('secret-key')));
    });
  });
}

ResponseBody _jsonResponse(Map<String, dynamic> body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: {Headers.contentTypeHeader: ['application/json']},
  );
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);
  final ResponseBody Function(RequestOptions options, Object? requestBody)
      _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final requestBody = requestStream == null
        ? null
        : utf8.decode(await requestStream.expand((chunk) => chunk).toList());
    return _handler(options, requestBody);
  }

  @override
  void close({bool force = false}) {}
}
```

- [ ] **Step 2: Run test and verify it fails**

Run:

```bash
flutter test test/services/lyrics/ai_lyrics_selector_test.dart
```

Expected: FAIL because `ai_lyrics_selector.dart` does not exist.

- [ ] **Step 3: Implement selector**

Create `lib/services/lyrics/ai_lyrics_selector.dart`:

```dart
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/logger.dart';

class AiLyricsCandidate {
  const AiLyricsCandidate({
    required this.candidateId,
    required this.source,
    required this.sourcePriorityRank,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    required this.durationSeconds,
    required this.videoDurationSeconds,
    required this.durationDiffSeconds,
    required this.hasSyncedLyrics,
    required this.hasPlainLyrics,
    required this.hasTranslatedLyrics,
    required this.hasRomajiLyrics,
  });

  final String candidateId;
  final String source;
  final int sourcePriorityRank;
  final String trackName;
  final String artistName;
  final String albumName;
  final int durationSeconds;
  final int videoDurationSeconds;
  final int durationDiffSeconds;
  final bool hasSyncedLyrics;
  final bool hasPlainLyrics;
  final bool hasTranslatedLyrics;
  final bool hasRomajiLyrics;

  Map<String, dynamic> toJson() => {
        'candidateId': candidateId,
        'source': source,
        'sourcePriorityRank': sourcePriorityRank,
        'trackName': trackName,
        'artistName': artistName,
        'albumName': albumName,
        'durationSeconds': durationSeconds,
        'videoDurationSeconds': videoDurationSeconds,
        'durationDiffSeconds': durationDiffSeconds,
        'hasSyncedLyrics': hasSyncedLyrics,
        'hasPlainLyrics': hasPlainLyrics,
        'hasTranslatedLyrics': hasTranslatedLyrics,
        'hasRomajiLyrics': hasRomajiLyrics,
      };
}

class AiLyricsSelection {
  const AiLyricsSelection({
    required this.selectedCandidateId,
    required this.confidence,
    required this.reason,
  });

  final String? selectedCandidateId;
  final double confidence;
  final String reason;
}

class AiLyricsSelector with Logging {
  AiLyricsSelector({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<AiLyricsSelection?> select({
    required String endpoint,
    required String apiKey,
    required String model,
    required String title,
    String? uploader,
    required int durationSeconds,
    required List<String> sourcePriority,
    required bool allowPlainLyricsAutoMatch,
    required List<AiLyricsCandidate> candidates,
    required int timeoutSeconds,
  }) async {
    final trimmedEndpoint = endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    final trimmedApiKey = apiKey.trim();
    final trimmedModel = model.trim();
    final timeout = Duration(seconds: timeoutSeconds < 1 ? 10 : timeoutSeconds);
    if (trimmedEndpoint.isEmpty || trimmedApiKey.isEmpty || trimmedModel.isEmpty) {
      logDebug('AI lyrics selector skipped because configuration is incomplete');
      return null;
    }

    final userPayload = {
      'title': title,
      if (uploader != null && uploader.trim().isNotEmpty)
        'uploader': uploader.trim(),
      'durationSeconds': durationSeconds,
      'sourcePriority': sourcePriority,
      'allowPlainLyricsAutoMatch': allowPlainLyricsAutoMatch,
      'candidates': candidates.map((candidate) => candidate.toJson()).toList(),
    };
    logDebug('AI lyrics selector request payload: ${jsonEncode(userPayload)}');

    try {
      final response = await _dio.post<dynamic>(
        '$trimmedEndpoint/chat/completions',
        options: Options(
          headers: {
            Headers.contentTypeHeader: Headers.jsonContentType,
            'Authorization': 'Bearer $trimmedApiKey',
          },
          connectTimeout: timeout,
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
        data: {
          'model': trimmedModel,
          'temperature': 0.1,
          'messages': [
            {
              'role': 'system',
              'content': 'Choose the most accurate lyrics candidate for the provided video. The uploader is context and is not necessarily the artist. Respect sourcePriority when candidates are otherwise similarly accurate. Always prefer synced lyrics over plain lyrics. Return strict JSON only with exactly these fields: selectedCandidateId, confidence, reason. Use selectedCandidateId null when no candidate is reliable enough.',
            },
            {'role': 'user', 'content': jsonEncode(userPayload)},
          ],
        },
      );

      final content = _extractContent(response.data);
      if (content == null) {
        logWarning('AI lyrics selector response has no content');
        return null;
      }
      logDebug('AI lyrics selector raw response content: $content');
      final parsed = parseContent(content);
      logDebug('AI lyrics selector parsed result: selected=${parsed?.selectedCandidateId}, confidence=${parsed?.confidence}, reason=${parsed?.reason}');
      return parsed;
    } on DioException catch (e) {
      logWarning('AI lyrics selector request failed: ${e.message ?? e.error ?? e.type}');
      return null;
    } catch (e) {
      logWarning('AI lyrics selector failed: $e');
      return null;
    }
  }

  static AiLyricsSelection? parseContent(String content) {
    try {
      final decoded = jsonDecode(_stripCodeFence(content));
      if (decoded is! Map<String, dynamic>) return null;
      final selected = decoded['selectedCandidateId'];
      final confidence = decoded['confidence'];
      final reason = decoded['reason'];
      if (selected != null && selected is! String) return null;
      if (confidence is! num) return null;
      return AiLyricsSelection(
        selectedCandidateId: selected as String?,
        confidence: confidence.toDouble(),
        reason: reason is String ? reason : '',
      );
    } catch (_) {
      return null;
    }
  }

  static String? _extractContent(dynamic data) {
    if (data is! Map<String, dynamic>) return null;
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final firstChoice = choices.first;
    if (firstChoice is! Map<String, dynamic>) return null;
    final message = firstChoice['message'];
    if (message is! Map<String, dynamic>) return null;
    final content = message['content'];
    return content is String ? content : null;
  }

  static String _stripCodeFence(String content) {
    final trimmed = content.trim();
    final match = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$', caseSensitive: false)
        .firstMatch(trimmed);
    return match?.group(1)?.trim() ?? trimmed;
  }
}
```

- [ ] **Step 4: Run test and commit**

Run:

```bash
flutter test test/services/lyrics/ai_lyrics_selector_test.dart
```

Expected: PASS.

Commit:

```bash
git add lib/services/lyrics/ai_lyrics_selector.dart test/services/lyrics/ai_lyrics_selector_test.dart
git commit -m "feat(lyrics): add AI candidate selector"
```

### Task 4: Add Debug Logs to Existing AI Title Parser

**Files:**
- Modify: `lib/services/lyrics/ai_title_parser.dart:26-124`
- Test: `test/services/lyrics/ai_title_parser_test.dart`

- [ ] **Step 1: Write failing log assertions**

In `test/services/lyrics/ai_title_parser_test.dart`, update the successful request test to expect detailed logs:

```dart
final messages = AppLogger.logs.map((entry) => entry.message).toList();
expect(messages, contains(contains('AI title parser request payload')));
expect(messages, contains(contains('AI title parser raw response content')));
expect(messages, contains(contains('AI title parser parsed result')));
expect(messages.join('\n'), isNot(contains('secret-key')));
```

- [ ] **Step 2: Run test and verify it fails**

Run:

```bash
flutter test test/services/lyrics/ai_title_parser_test.dart
```

Expected: FAIL because detailed debug log messages are missing.

- [ ] **Step 3: Implement debug logs**

In `AiTitleParser.parse`, build `userPayload` before the Dio call:

```dart
final userPayload = {
  'title': title,
  if (trimmedUploader != null && trimmedUploader.isNotEmpty)
    'uploader': trimmedUploader,
};
logDebug('AI title parser config: endpoint=$trimmedEndpoint, model=$trimmedModel, timeoutSeconds=${timeout.inSeconds}');
logDebug('AI title parser request payload: ${jsonEncode(userPayload)}');
```

Use `jsonEncode(userPayload)` in the user message. After extracting `content`, add:

```dart
logDebug('AI title parser raw response content: $content');
```

After `parseContent(content)`, add:

```dart
logDebug('AI title parser parsed result: track=${parsed?.trackName}, artist=${parsed?.artistName}, artistConfidence=${parsed?.artistConfidence}');
```

Do not log `trimmedApiKey`.

- [ ] **Step 4: Run test and commit**

Run:

```bash
flutter test test/services/lyrics/ai_title_parser_test.dart
```

Expected: PASS.

Commit:

```bash
git add lib/services/lyrics/ai_title_parser.dart test/services/lyrics/ai_title_parser_test.dart
git commit -m "chore(lyrics): log AI title parsing payloads"
```

### Task 5: Refactor Auto-Match Service for Plain Lyrics Filtering

**Files:**
- Modify: `lib/services/lyrics/lyrics_auto_match_service.dart:35-53,81-188,314-480`
- Test: `test/services/lyrics/lyrics_auto_match_service_phase4_test.dart`

- [ ] **Step 1: Write failing plain-lyrics tests**

In `test/services/lyrics/lyrics_auto_match_service_phase4_test.dart`, add tests:

```dart
test('rejects plain-only lyrics by default', () async {
  netease.searchResults = [
    _lyricsResult(
      id: 'plain-only',
      source: 'netease',
      syncedLyrics: null,
      plainLyrics: 'plain line',
    ),
  ];
  final matched = await service.tryAutoMatch(
    _track('plain-default'),
    enabledSources: const ['netease'],
  );
  expect(matched, isFalse);
  expect(await repo.getByTrackKey('youtube:plain-default'), isNull);
});

test('accepts plain-only lyrics when setting allows it', () async {
  service = LyricsAutoMatchService(
    lrclib: lrclib,
    netease: netease,
    qqmusic: qqmusic,
    repo: repo,
    cache: cache,
    parser: parser,
    allowPlainLyricsAutoMatch: true,
  );
  netease.searchResults = [
    _lyricsResult(
      id: 'plain-allowed',
      source: 'netease',
      syncedLyrics: null,
      plainLyrics: 'plain line',
    ),
  ];
  final matched = await service.tryAutoMatch(
    _track('plain-allowed'),
    enabledSources: const ['netease'],
  );
  expect(matched, isTrue);
  final saved = await repo.getByTrackKey('youtube:plain-allowed');
  expect(saved?.externalId, 'plain-allowed');
});
```

Update helper `_lyricsResult` signature:

```dart
LyricsResult _lyricsResult({
  required String id,
  required String source,
  int duration = 180,
  String? syncedLyrics = '[00:01.00]line',
  String? plainLyrics,
}) {
  return LyricsResult(
    id: id,
    trackName: 'Song Name',
    artistName: 'Singer',
    albumName: 'Album',
    duration: duration,
    instrumental: false,
    syncedLyrics: syncedLyrics,
    plainLyrics: plainLyrics,
    source: source,
  );
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
flutter test test/services/lyrics/lyrics_auto_match_service_phase4_test.dart
```

Expected: FAIL because constructor lacks `allowPlainLyricsAutoMatch` and plain-only results are always rejected.

- [ ] **Step 3: Add constructor setting and helper**

In `LyricsAutoMatchService`, add field and constructor parameter:

```dart
final bool _allowPlainLyricsAutoMatch;

bool allowPlainLyricsAutoMatch = false,

_allowPlainLyricsAutoMatch = allowPlainLyricsAutoMatch;
```

Add helper:

```dart
bool _isAllowedLyricsResult(LyricsResult result) {
  if (result.hasSyncedLyrics) return true;
  return _allowPlainLyricsAutoMatch && result.hasPlainLyrics;
}
```

Replace all `result.hasSyncedLyrics` acceptance checks in direct fetch, Netease, QQ Music, and lrclib matching with `_isAllowedLyricsResult(result)`.

- [ ] **Step 4: Run tests and commit**

Run:

```bash
flutter test test/services/lyrics/lyrics_auto_match_service_phase4_test.dart
```

Expected: PASS.

Commit:

```bash
git add lib/services/lyrics/lyrics_auto_match_service.dart test/services/lyrics/lyrics_auto_match_service_phase4_test.dart
git commit -m "feat(lyrics): support optional plain lyrics auto-match"
```

### Task 6: Implement AI Mode Flow Semantics

**Files:**
- Modify: `lib/services/lyrics/lyrics_auto_match_service.dart:113-145,183-294`
- Test: `test/services/lyrics/lyrics_auto_match_ai_title_parser_test.dart`

- [ ] **Step 1: Update tests for removed fallback mode**

In `test/services/lyrics/lyrics_auto_match_ai_title_parser_test.dart`:

- Change setup default config to `LyricsAiTitleParsingMode.alwaysAi`.
- Delete tests that expect `fallbackAfterRules` to run regex first.
- Update source-priority expectations so always AI does not search regex first.
- Add this test:

```dart
test('alwaysAi does not fall back to regex when AI parse succeeds but matching fails', () async {
  config = _config(mode: LyricsAiTitleParsingMode.alwaysAi);
  aiParser.result = _aiParsed(trackName: 'AI No Match', artistName: 'AI Artist');
  netease.searchResultsByQuery['Regex Song Regex Artist'] = [
    _lyricsResult(id: 'regex-should-not-run', source: 'netease'),
  ];

  final matched = await buildService().tryAutoMatch(
    _track('no-regex-after-ai-match-fail'),
    enabledSources: const ['netease'],
  );

  expect(matched, isFalse);
  expect(netease.searchCalls, ['AI No Match AI Artist', 'AI No Match']);
  expect(await repo.getByTrackKey('youtube:no-regex-after-ai-match-fail'), isNull);
});
```

- Keep tests where `aiParser.result = null` or invalid parse falls back to regex.

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
flutter test test/services/lyrics/lyrics_auto_match_ai_title_parser_test.dart
```

Expected: FAIL because old fallback mode still exists and successful AI parse failures may fall back incorrectly.

- [ ] **Step 3: Implement mode flow**

In `tryAutoMatch`, replace mode branches with:

```dart
final aiConfig = await _loadAiConfigSafely();
final shouldTryAi = _shouldTryAi(aiConfig);

if (shouldTryAi && aiConfig!.mode == LyricsAiTitleParsingMode.alwaysAi) {
  final aiParsed = await _loadOrParseAiTitle(track, aiConfig);
  if (aiParsed != null) {
    return _matchAiParsedTitle(track, aiParsed, sources);
  }
  return _matchRegexParsedTitle(track, sources);
}

if (shouldTryAi && aiConfig!.mode == LyricsAiTitleParsingMode.advancedAiSelect) {
  // Implemented in Task 7. For now, fall back only if title parse fails.
  final aiParsed = await _loadOrParseAiTitle(track, aiConfig);
  if (aiParsed != null) {
    return false;
  }
  return _matchRegexParsedTitle(track, sources);
}

return _matchRegexParsedTitle(track, sources);
```

Remove all `fallbackAfterRules` references from this service.

- [ ] **Step 4: Run tests and commit**

Run:

```bash
flutter test test/services/lyrics/lyrics_auto_match_ai_title_parser_test.dart
```

Expected: PASS.

Commit:

```bash
git add lib/services/lyrics/lyrics_auto_match_service.dart test/services/lyrics/lyrics_auto_match_ai_title_parser_test.dart
git commit -m "feat(lyrics): update AI title parsing flow"
```

### Task 7: Implement AI Advanced Matching Flow

**Files:**
- Modify: `lib/services/lyrics/lyrics_auto_match_service.dart`
- Modify: `lib/providers/lyrics_provider.dart:40-75`
- Test: `test/services/lyrics/lyrics_auto_match_ai_title_parser_test.dart`

- [ ] **Step 1: Write failing advanced-mode tests**

In `test/services/lyrics/lyrics_auto_match_ai_title_parser_test.dart`, add fake selector and tests.

Add import near the other lyrics imports:

```dart
import 'package:fmp/services/lyrics/ai_lyrics_selector.dart';
```

Add field in group setup:

```dart
late _FakeAiLyricsSelector aiLyricsSelector;
```

Initialize it in `setUp`:

```dart
aiLyricsSelector = _FakeAiLyricsSelector();
```

Update `buildService()` so the service constructor includes the selector and plain-lyrics setting:

```dart
return LyricsAutoMatchService(
  lrclib: lrclib,
  netease: netease,
  qqmusic: qqmusic,
  repo: repo,
  cache: cache,
  parser: parser,
  aiTitleParser: aiParser,
  aiLyricsSelector: aiLyricsSelector,
  aiConfigLoader: () async => config,
  titleParseCacheRepo: titleParseCacheRepo,
  allowPlainLyricsAutoMatch: false,
);
```

Add tests:

```dart
test('advanced mode saves AI selected high-confidence synced candidate', () async {
  config = _config(mode: LyricsAiTitleParsingMode.advancedAiSelect);
  aiParser.result = _aiParsed(trackName: 'AI Song', artistName: 'AI Artist');
  netease.searchResultsByQuery['AI Song AI Artist'] = [
    _lyricsResult(id: 'chosen', source: 'netease', trackName: 'AI Song', artistName: 'AI Artist'),
  ];
  aiLyricsSelector.result = const AiLyricsSelection(
    selectedCandidateId: 'netease:chosen',
    confidence: 0.91,
    reason: 'best synced match',
  );

  final matched = await buildService().tryAutoMatch(
    _track('advanced-selected'),
    enabledSources: const ['netease'],
  );

  expect(matched, isTrue);
  expect(aiLyricsSelector.calls, hasLength(1));
  expect(aiLyricsSelector.calls.single.candidates.single.candidateId, 'netease:chosen');
  final saved = await repo.getByTrackKey('youtube:advanced-selected');
  expect(saved?.externalId, 'chosen');
});

test('advanced mode filters plain candidates before AI when disabled', () async {
  config = _config(mode: LyricsAiTitleParsingMode.advancedAiSelect);
  aiParser.result = _aiParsed(trackName: 'AI Song', artistName: 'AI Artist');
  netease.searchResultsByQuery['AI Song AI Artist'] = [
    _lyricsResult(id: 'plain', source: 'netease', trackName: 'AI Song', artistName: 'AI Artist', syncedLyrics: null, plainLyrics: 'plain'),
  ];

  final matched = await buildService().tryAutoMatch(
    _track('advanced-filter-plain'),
    enabledSources: const ['netease'],
  );

  expect(matched, isFalse);
  expect(aiLyricsSelector.calls, isEmpty);
});

test('advanced mode does not fall back to regex after low confidence selection', () async {
  config = _config(mode: LyricsAiTitleParsingMode.advancedAiSelect);
  aiParser.result = _aiParsed(trackName: 'AI Song', artistName: 'AI Artist');
  netease.searchResultsByQuery['AI Song AI Artist'] = [
    _lyricsResult(id: 'candidate', source: 'netease', trackName: 'AI Song', artistName: 'AI Artist'),
  ];
  netease.searchResultsByQuery['Regex Song Regex Artist'] = [
    _lyricsResult(id: 'regex-should-not-run', source: 'netease'),
  ];
  aiLyricsSelector.result = const AiLyricsSelection(
    selectedCandidateId: 'netease:candidate',
    confidence: 0.8,
    reason: 'not enough',
  );

  final matched = await buildService().tryAutoMatch(
    _track('advanced-low-confidence'),
    enabledSources: const ['netease'],
  );

  expect(matched, isFalse);
  expect(netease.searchCalls, isNot(contains('Regex Song Regex Artist')));
  expect(await repo.getByTrackKey('youtube:advanced-low-confidence'), isNull);
});
```

Add fake class at bottom:

```dart
class _FakeAiLyricsSelector extends AiLyricsSelector {
  final List<({List<AiLyricsCandidate> candidates})> calls = [];
  AiLyricsSelection? result;

  @override
  Future<AiLyricsSelection?> select({
    required String endpoint,
    required String apiKey,
    required String model,
    required String title,
    String? uploader,
    required int durationSeconds,
    required List<String> sourcePriority,
    required bool allowPlainLyricsAutoMatch,
    required List<AiLyricsCandidate> candidates,
    required int timeoutSeconds,
  }) async {
    calls.add((candidates: candidates));
    return result;
  }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
flutter test test/services/lyrics/lyrics_auto_match_ai_title_parser_test.dart
```

Expected: FAIL because advanced flow and selector dependency are not implemented.

- [ ] **Step 3: Add selector dependency to providers and service**

In `lib/providers/lyrics_provider.dart`, import and provide selector:

```dart
import '../services/lyrics/ai_lyrics_selector.dart';

final aiLyricsSelectorProvider = Provider<AiLyricsSelector>((ref) => AiLyricsSelector());
```

Pass to `LyricsAutoMatchService`:

```dart
aiLyricsSelector: ref.watch(aiLyricsSelectorProvider),
allowPlainLyricsAutoMatch: ref.watch(audioSettingsProvider).allowPlainLyricsAutoMatch,
```

In service constructor add:

```dart
final AiLyricsSelector? _aiLyricsSelector;

AiLyricsSelector? aiLyricsSelector,
bool allowPlainLyricsAutoMatch = false,

_aiLyricsSelector = aiLyricsSelector,
```

- [ ] **Step 4: Implement advanced candidate collection and selection**

Add method skeletons in `LyricsAutoMatchService`:

```dart
Future<bool> _matchAdvancedAi(
  Track track,
  AiParsedTitle parsed,
  LyricsAiConfig config,
  List<String> sources,
) async {
  final selector = _aiLyricsSelector;
  if (selector == null) return false;
  final trackDurationSec = (track.durationMs ?? 0) ~/ 1000;
  final candidatesById = <String, LyricsResult>{};
  final aiCandidates = <AiLyricsCandidate>[];
  final queryPairs = _buildAiQueryPairs(parsed);
  logDebug('AI advanced matching query pairs: $queryPairs');

  for (final source in sources) {
    for (final query in queryPairs) {
      final results = await _searchSource(source, query.trackName, query.artistName);
      for (final result in results) {
        if (!_passesDuration(result, trackDurationSec)) continue;
        if (!_isAllowedLyricsResult(result)) continue;
        final candidateId = '${result.source}:${result.id}';
        if (candidatesById.containsKey(candidateId)) continue;
        candidatesById[candidateId] = result;
        aiCandidates.add(_toAiCandidate(
          result,
          candidateId,
          sources.indexOf(source),
          trackDurationSec,
        ));
      }
    }
  }

  if (aiCandidates.isEmpty) {
    logDebug('AI advanced matching has no candidates after filtering');
    return false;
  }

  final selection = await selector.select(
    endpoint: config.endpoint,
    apiKey: config.apiKey,
    model: config.model,
    title: track.title,
    uploader: track.artist,
    durationSeconds: trackDurationSec,
    sourcePriority: sources,
    allowPlainLyricsAutoMatch: _allowPlainLyricsAutoMatch,
    candidates: aiCandidates,
    timeoutSeconds: config.timeoutSeconds,
  );
  if (selection == null) return _matchRegexParsedTitle(track, sources);
  final selectedId = selection.selectedCandidateId;
  if (selectedId == null || selection.confidence <= 0.8) return false;
  final selected = candidatesById[selectedId];
  if (selected == null || !_isAllowedLyricsResult(selected)) return false;
  await _saveMatch(track, selected, selected.source, selected.id);
  logInfo('AI advanced matched lyrics: ${track.title} → ${selected.source}:${selected.id} confidence=${selection.confidence}');
  return true;
}
```

Add helpers:

```dart
Future<List<LyricsResult>> _searchSource(
  String source,
  String trackName,
  String artistName,
) async {
  switch (source) {
    case 'netease':
      return _netease.searchLyrics(
        query: [trackName, artistName].where((s) => s.isNotEmpty).join(' '),
        limit: 5,
      );
    case 'qqmusic':
      return _qqmusic.searchLyrics(
        query: [trackName, artistName].where((s) => s.isNotEmpty).join(' '),
        limit: 5,
      );
    case 'lrclib':
      return _lrclib.search(
        trackName: trackName,
        artistName: artistName.isNotEmpty ? artistName : null,
      );
  }
  return const [];
}

bool _passesDuration(LyricsResult result, int trackDurationSec) {
  if (result.duration == 0) return true;
  return (result.duration - trackDurationSec).abs() <=
      AppConstants.lyricsDurationToleranceSec;
}

AiLyricsCandidate _toAiCandidate(
  LyricsResult result,
  String candidateId,
  int sourcePriorityRank,
  int videoDurationSeconds,
) {
  final durationDiff = result.duration == 0
      ? 0
      : (result.duration - videoDurationSeconds).abs();
  return AiLyricsCandidate(
    candidateId: candidateId,
    source: result.source,
    sourcePriorityRank: sourcePriorityRank,
    trackName: result.trackName,
    artistName: result.artistName,
    albumName: result.albumName,
    durationSeconds: result.duration,
    videoDurationSeconds: videoDurationSeconds,
    durationDiffSeconds: durationDiff,
    hasSyncedLyrics: result.hasSyncedLyrics,
    hasPlainLyrics: result.hasPlainLyrics,
    hasTranslatedLyrics: result.hasTranslatedLyrics,
    hasRomajiLyrics: result.hasRomajiLyrics,
  );
}
```

- [ ] **Step 5: Wire advanced branch**

In the `advancedAiSelect` branch from Task 6:

```dart
final aiParsed = await _loadOrParseAiTitle(track, aiConfig);
if (aiParsed != null) {
  return _matchAdvancedAi(track, aiParsed, aiConfig, sources);
}
return _matchRegexParsedTitle(track, sources);
```

- [ ] **Step 6: Run tests and commit**

Run:

```bash
flutter test test/services/lyrics/lyrics_auto_match_ai_title_parser_test.dart test/services/lyrics/ai_lyrics_selector_test.dart
```

Expected: PASS.

Commit:

```bash
git add lib/services/lyrics/lyrics_auto_match_service.dart lib/providers/lyrics_provider.dart test/services/lyrics/lyrics_auto_match_ai_title_parser_test.dart
git commit -m "feat(lyrics): add advanced AI lyrics matching"
```

### Task 8: Update Settings UI and i18n

**Files:**
- Modify: `lib/ui/pages/settings/lyrics_source_settings_page.dart:121-129,221-245,488-588`
- Modify: `lib/i18n/en/settings.i18n.json:75-107`
- Modify: `lib/i18n/zh-CN/settings.i18n.json:75-107`
- Modify: `lib/i18n/zh-TW/settings.i18n.json:75-107`
- Regenerate locally: `lib/i18n/strings.g.dart` (ignored generated file, not committed)

- [ ] **Step 1: Update i18n JSON**

In each settings i18n JSON under `lyricsSourceSettings`, replace old AI labels and add new keys.

English:

```json
"aiSectionTitle": "AI lyrics matching",
"aiMode": "Mode",
"aiModeOff": "Off",
"aiModeAlways": "AI title parsing",
"aiModeAdvanced": "AI advanced matching",
"aiModeAlwaysDescription": "AI parses the video title; local rules still choose the lyrics result.",
"aiModeAdvancedDescription": "AI selects from searched lyrics candidates and saves only confidence > 0.8.",
"allowPlainLyricsAutoMatch": "Allow auto-matching non-synced lyrics",
"allowPlainLyricsAutoMatchDescription": "When off, automatic matching only accepts synced lyrics.",
```

Simplified Chinese:

```json
"aiSectionTitle": "AI 歌词匹配",
"aiMode": "模式",
"aiModeOff": "关闭",
"aiModeAlways": "AI 标题解析",
"aiModeAdvanced": "AI 高级匹配",
"aiModeAlwaysDescription": "AI 解析视频标题，歌词结果仍由本地规则选择。",
"aiModeAdvancedDescription": "AI 从搜索到的候选歌词中选择，仅在 confidence > 0.8 时保存。",
"allowPlainLyricsAutoMatch": "允许自动匹配非同步歌词",
"allowPlainLyricsAutoMatchDescription": "关闭时，自动匹配只接受同步歌词。",
```

Traditional Chinese:

```json
"aiSectionTitle": "AI 歌詞匹配",
"aiMode": "模式",
"aiModeOff": "關閉",
"aiModeAlways": "AI 標題解析",
"aiModeAdvanced": "AI 高級匹配",
"aiModeAlwaysDescription": "AI 解析影片標題，歌詞結果仍由本地規則選擇。",
"aiModeAdvancedDescription": "AI 從搜尋到的候選歌詞中選擇，僅在 confidence > 0.8 時保存。",
"allowPlainLyricsAutoMatch": "允許自動匹配非同步歌詞",
"allowPlainLyricsAutoMatchDescription": "關閉時，自動匹配只接受同步歌詞。",
```

Remove `aiModeFallback` from the JSON files.

- [ ] **Step 2: Update settings page mode labels and dialog props**

In `_getModeLabel`, remove fallback and add advanced:

```dart
String _getModeLabel(LyricsAiTitleParsingMode mode) {
  switch (mode) {
    case LyricsAiTitleParsingMode.off:
      return t.settings.lyricsSourceSettings.aiModeOff;
    case LyricsAiTitleParsingMode.alwaysAi:
      return t.settings.lyricsSourceSettings.aiModeAlways;
    case LyricsAiTitleParsingMode.advancedAiSelect:
      return t.settings.lyricsSourceSettings.aiModeAdvanced;
  }
}
```

Add callback when creating `_AiTitleParsingSettingsDialog`:

```dart
onAllowPlainLyricsAutoMatchChanged: (enabled) => ref
    .read(audioSettingsProvider.notifier)
    .setAllowPlainLyricsAutoMatch(enabled),
```

Add widget field:

```dart
final ValueChanged<bool> onAllowPlainLyricsAutoMatchChanged;
```

- [ ] **Step 3: Filter dropdown modes and add descriptions/switch**

Replace `items: LyricsAiTitleParsingMode.values.map(...)` with:

```dart
items: const [
  LyricsAiTitleParsingMode.off,
  LyricsAiTitleParsingMode.alwaysAi,
  LyricsAiTitleParsingMode.advancedAiSelect,
]
    .map(
      (mode) => DropdownMenuItem(
        value: mode,
        child: Text(widget.modeLabelBuilder(mode)),
      ),
    )
    .toList(),
```

After the dropdown, add explanatory text:

```dart
const SizedBox(height: 8),
Text(
  switch (widget.audioSettings.lyricsAiTitleParsingMode) {
    LyricsAiTitleParsingMode.alwaysAi =>
      t.settings.lyricsSourceSettings.aiModeAlwaysDescription,
    LyricsAiTitleParsingMode.advancedAiSelect =>
      t.settings.lyricsSourceSettings.aiModeAdvancedDescription,
    LyricsAiTitleParsingMode.off => '',
  },
  style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
),
const SizedBox(height: 12),
SwitchListTile(
  contentPadding: EdgeInsets.zero,
  title: Text(t.settings.lyricsSourceSettings.allowPlainLyricsAutoMatch),
  subtitle: Text(
    t.settings.lyricsSourceSettings.allowPlainLyricsAutoMatchDescription,
  ),
  value: widget.audioSettings.allowPlainLyricsAutoMatch,
  onChanged: widget.onAllowPlainLyricsAutoMatchChanged,
),
```

- [ ] **Step 4: Regenerate slang output**

Run:

```bash
dart run slang
```

Expected: `lib/i18n/strings.g.dart` regenerates without errors.

- [ ] **Step 5: Run analyze and commit**

Run:

```bash
flutter analyze
```

Expected: no new analysis errors.

Commit:

```bash
git add lib/ui/pages/settings/lyrics_source_settings_page.dart lib/i18n/en/settings.i18n.json lib/i18n/zh-CN/settings.i18n.json lib/i18n/zh-TW/settings.i18n.json
git commit -m "feat(settings): add AI lyrics matching options"
```

### Task 9: Update Configuration and Backup Coverage

**Files:**
- Modify: `test/services/lyrics/lyrics_ai_config_service_test.dart`
- Modify: `test/services/backup/backup_service_test.dart`

- [ ] **Step 1: Update AI config tests**

In `test/services/lyrics/lyrics_ai_config_service_test.dart`, ensure expectations use new defaults:

```dart
expect(config.mode, LyricsAiTitleParsingMode.off);
expect(config.isAvailable, isFalse);
```

Add advanced availability test:

```dart
test('advanced mode is available with endpoint key and model', () async {
  final service = LyricsAiConfigService(
    loadSettings: () async => Settings()
      ..lyricsAiTitleParsingMode = LyricsAiTitleParsingMode.advancedAiSelect
      ..lyricsAiEndpoint = 'https://example.test/v1'
      ..lyricsAiModel = 'test-model',
    secureStorage: _FakeSecureKeyValueStore({'lyrics_ai_api_key': 'key'}),
  );
  final config = await service.loadConfig();
  expect(config.mode, LyricsAiTitleParsingMode.advancedAiSelect);
  expect(config.isAvailable, isTrue);
});
```

Use the existing fake secure store pattern in that test file.

- [ ] **Step 2: Update backup tests if settings serialization assertions include AI mode**

Search in `test/services/backup/backup_service_test.dart` for `lyricsAiTitleParsingModeIndex`. Update expected defaults from `1` to `0` and include `allowPlainLyricsAutoMatch` if the test checks raw JSON keys.

- [ ] **Step 3: Run tests and commit**

Run:

```bash
flutter test test/services/lyrics/lyrics_ai_config_service_test.dart test/services/backup/backup_service_test.dart
```

Expected: PASS.

Commit:

```bash
git add test/services/lyrics/lyrics_ai_config_service_test.dart test/services/backup/backup_service_test.dart
git commit -m "test(lyrics): cover new AI matching settings"
```

### Task 10: Full Verification and Documentation

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update project documentation**

In `CLAUDE.md`, update:

- `Data Models` settings row: mention `allowPlainLyricsAutoMatch` and new AI modes.
- `Database Migration`: mention fallback mode repair to off and `allowPlainLyricsAutoMatch` no-migration default.
- `Lyrics System`: replace fallback mode text with off / AI title parsing / AI advanced matching behavior.

Use concise text matching the existing style.

- [ ] **Step 2: Run focused tests**

Run:

```bash
flutter test test/data/models/settings_ai_title_parsing_test.dart test/providers/audio_settings_ai_title_parsing_test.dart test/providers/database_migration_test.dart test/services/lyrics/ai_title_parser_test.dart test/services/lyrics/ai_lyrics_selector_test.dart test/services/lyrics/lyrics_ai_config_service_test.dart test/services/lyrics/lyrics_auto_match_service_phase4_test.dart test/services/lyrics/lyrics_auto_match_ai_title_parser_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run generated-code and i18n checks**

Run:

```bash
flutter pub run build_runner build --delete-conflicting-outputs && dart run slang && flutter analyze
```

Expected: no generator diffs except intended generated files, and analyze passes.

- [ ] **Step 4: Run full test suite**

Run:

```bash
flutter test
```

Expected: PASS. If unrelated pre-existing failures appear, capture exact failing tests and continue only after confirming they are unrelated.

- [ ] **Step 5: Commit documentation and final verification updates**

Commit:

```bash
git add CLAUDE.md
git commit -m "docs: update lyrics AI matching guidance"
```

- [ ] **Step 6: Manual UI verification**

Start the app:

```bash
flutter run -d windows
```

Verify in the app:

1. Open Settings → Lyrics Sources.
2. Open the AI dialog.
3. Confirm mode options are Off, AI title parsing, AI advanced matching.
4. Confirm no fallback option appears.
5. Toggle non-synced lyrics setting and reopen dialog; verify state persists.
6. Enter test endpoint/model/API key if available and click Test AI; verify debug logs in Developer Options → Live Log do not show API key.

If no usable AI endpoint is available, state that API-call UI testing was limited to configuration persistence and log safety review.

- [ ] **Step 7: Final status**

Run:

```bash
git status --short
```

Expected: clean except for user-approved uncommitted artifacts, if any.
