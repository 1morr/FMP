# AI Lyrics Context Enrichment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrich AI advanced lyrics matching with bounded existing video description context and deterministic lyrics previews so AI can select better same-song candidates.

**Architecture:** Keep `AiLyricsSelector` responsible for serializing the AI request and prompt contract. Keep `LyricsAutoMatchService` responsible for converting searched `LyricsResult` objects into AI candidates; add a small deterministic preview generator there so the full lyric text never leaves the service boundary. Do not add platform detail fetches or database fields; because `Track` has no description field in the automatic matching path, `videoDescription` stays optional and is omitted until existing call-path data exposes one.

**Tech Stack:** Flutter/Dart, Dio OpenAI-compatible chat completions, Isar-backed lyrics auto-match tests, flutter_test.

---

## File Structure

- Modify `lib/services/lyrics/ai_lyrics_selector.dart`: add optional `lyricsPreview` on `AiLyricsCandidate`, add optional `videoDescription` to `select()`, normalize/cap description, include new fields in payload, and update the system prompt.
- Modify `lib/services/lyrics/lyrics_auto_match_service.dart`: generate deterministic lyrics previews from each allowed `LyricsResult` before building `AiLyricsCandidate`; pass `videoDescription: null` for now because the current `Track` model has no existing description field.
- Modify `test/services/lyrics/ai_lyrics_selector_test.dart`: assert `videoDescription` and candidate `lyricsPreview` are sent, capped, and do not leak API keys; assert prompt mentions both new context fields.
- Modify `test/services/lyrics/lyrics_auto_match_ai_title_parser_test.dart`: assert advanced matching sends normalized lyrics previews, strips LRC timestamps and metadata, combines first and middle lyric segments, caps preview length, and keeps plain-only previews out when plain automatic matching is disabled.

---

### Task 1: Extend AI Selector Payload Contract

**Files:**
- Modify: `lib/services/lyrics/ai_lyrics_selector.dart:7-53,72-139`
- Test: `test/services/lyrics/ai_lyrics_selector_test.dart:36-156`

- [ ] **Step 1: Write the failing payload test**

In `test/services/lyrics/ai_lyrics_selector_test.dart`, replace the body of `sends candidate selection payload without API key leakage` with this version:

```dart
test('sends enriched candidate selection payload without API key leakage',
    () async {
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
    videoDescription: '  Official music video\nwith  lyrics in description.  ',
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
        lyricsPreview: 'first line\nchorus line',
      ),
    ],
    timeoutSeconds: 5,
  );

  expect(result?.selectedCandidateId, 'netease:123');
  expect(capturedBody?['model'], 'gpt-test');
  final messages = capturedBody?['messages'] as List<dynamic>;
  final userMessage = messages.firstWhere(
    (message) => (message as Map<String, dynamic>)['role'] == 'user',
  ) as Map<String, dynamic>;
  final payload = jsonDecode(userMessage['content'] as String)
      as Map<String, dynamic>;
  expect(payload['title'], 'Video Title');
  expect(payload['uploader'], 'Uploader');
  expect(
    payload['videoDescription'],
    'Official music video with lyrics in description.',
  );
  final candidates = payload['candidates'] as List<dynamic>;
  final candidate = candidates.single as Map<String, dynamic>;
  expect(candidate['candidateId'], 'netease:123');
  expect(candidate['lyricsPreview'], 'first line\nchorus line');
  final bodyText = jsonEncode(capturedBody);
  expect(bodyText, isNot(contains('secret-key')));
});
```

- [ ] **Step 2: Add failing selector edge-case tests**

Add these tests below the enriched payload test:

```dart
test('omits blank video description and preserves empty lyrics preview',
    () async {
  final dio = Dio();
  Map<String, dynamic>? capturedBody;
  dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
    capturedBody = jsonDecode(requestBody as String) as Map<String, dynamic>;
    return _jsonResponse({
      'choices': [
        {
          'message': {
            'content': jsonEncode({
              'selectedCandidateId': null,
              'confidence': 0.1,
              'reason': 'no match',
            }),
          },
        },
      ],
    });
  });

  await AiLyricsSelector(dio: dio).select(
    endpoint: 'https://api.example.com/v1',
    apiKey: 'secret-key',
    model: 'gpt-test',
    title: 'Video Title',
    uploader: null,
    videoDescription: '   ',
    durationSeconds: 180,
    sourcePriority: const ['netease'],
    allowPlainLyricsAutoMatch: false,
    candidates: const [
      AiLyricsCandidate(
        candidateId: 'netease:empty',
        source: 'netease',
        sourcePriorityRank: 0,
        trackName: 'Song',
        artistName: 'Artist',
        albumName: 'Album',
        durationSeconds: 180,
        videoDurationSeconds: 180,
        durationDiffSeconds: 0,
        hasSyncedLyrics: true,
        hasPlainLyrics: false,
        hasTranslatedLyrics: false,
        hasRomajiLyrics: false,
        lyricsPreview: '',
      ),
    ],
    timeoutSeconds: 5,
  );

  final messages = capturedBody?['messages'] as List<dynamic>;
  final userMessage = messages.firstWhere(
    (message) => (message as Map<String, dynamic>)['role'] == 'user',
  ) as Map<String, dynamic>;
  final payload = jsonDecode(userMessage['content'] as String)
      as Map<String, dynamic>;
  expect(payload.containsKey('videoDescription'), isFalse);
  final candidates = payload['candidates'] as List<dynamic>;
  expect(
    (candidates.single as Map<String, dynamic>)['lyricsPreview'],
    isEmpty,
  );
});

test('caps video description to 500 characters', () async {
  final dio = Dio();
  Map<String, dynamic>? capturedBody;
  dio.httpClientAdapter = _FakeHttpClientAdapter((options, requestBody) {
    capturedBody = jsonDecode(requestBody as String) as Map<String, dynamic>;
    return _jsonResponse({
      'choices': [
        {
          'message': {
            'content': jsonEncode({
              'selectedCandidateId': null,
              'confidence': 0.1,
              'reason': 'no match',
            }),
          },
        },
      ],
    });
  });

  await AiLyricsSelector(dio: dio).select(
    endpoint: 'https://api.example.com/v1',
    apiKey: 'secret-key',
    model: 'gpt-test',
    title: 'Video Title',
    videoDescription: '${List.filled(520, 'a').join()} trailing',
    durationSeconds: 180,
    sourcePriority: const ['netease'],
    allowPlainLyricsAutoMatch: false,
    candidates: const [],
    timeoutSeconds: 5,
  );

  final messages = capturedBody?['messages'] as List<dynamic>;
  final userMessage = messages.firstWhere(
    (message) => (message as Map<String, dynamic>)['role'] == 'user',
  ) as Map<String, dynamic>;
  final payload = jsonDecode(userMessage['content'] as String)
      as Map<String, dynamic>;
  expect(payload['videoDescription'], List.filled(500, 'a').join());
});
```

- [ ] **Step 3: Update the prompt test to fail on missing context instructions**

In `prompt asks AI to pick closest acceptable candidate`, add `lyricsPreview` to the candidate constructor:

```dart
lyricsPreview: 'poker face chorus preview',
```

Then append these expectations to the end of the test:

```dart
expect(prompt, contains('videoDescription'));
expect(prompt, contains('lyricsPreview'));
expect(prompt, contains('compare candidate content'));
```

- [ ] **Step 4: Run selector tests and verify they fail**

Run:

```bash
flutter test test/services/lyrics/ai_lyrics_selector_test.dart
```

Expected: compile failures mention missing `videoDescription` and `lyricsPreview`, or assertion failures mention missing prompt text.

- [ ] **Step 5: Implement selector payload fields**

In `lib/services/lyrics/ai_lyrics_selector.dart`, update `AiLyricsCandidate`:

```dart
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
    required this.lyricsPreview,
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
  final String lyricsPreview;

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
        'lyricsPreview': lyricsPreview,
      };
}
```

Update the `select()` signature:

```dart
Future<AiLyricsSelection?> select({
  required String endpoint,
  required String apiKey,
  required String model,
  required String title,
  String? uploader,
  String? videoDescription,
  required int durationSeconds,
  required List<String> sourcePriority,
  required bool allowPlainLyricsAutoMatch,
  required List<AiLyricsCandidate> candidates,
  required int timeoutSeconds,
}) async {
```

Add this private helper near `_stripCodeFence`:

```dart
static String? _normalizeOptionalText(String? text, {required int maxChars}) {
  final normalized = text?.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized == null || normalized.isEmpty) return null;
  if (normalized.length <= maxChars) return normalized;
  return normalized.substring(0, maxChars);
}
```

Update `userPayload`:

```dart
final normalizedVideoDescription = _normalizeOptionalText(
  videoDescription,
  maxChars: 500,
);
final userPayload = {
  'title': title,
  if (uploader != null && uploader.trim().isNotEmpty)
    'uploader': uploader.trim(),
  if (normalizedVideoDescription != null)
    'videoDescription': normalizedVideoDescription,
  'durationSeconds': durationSeconds,
  'sourcePriority': sourcePriority,
  'allowPlainLyricsAutoMatch': allowPlainLyricsAutoMatch,
  'candidates': candidates.map((candidate) => candidate.toJson()).toList(),
};
```

- [ ] **Step 6: Update the selector system prompt**

Replace the system message content with:

```dart
'content': 'Choose the best lyrics candidate for the provided video. '
    'Use videoDescription as additional context when present. Use '
    'lyricsPreview to compare candidate content, but remember each preview '
    'is only a short excerpt. The uploader is context and is not '
    'necessarily the artist. Always choose the closest acceptable candidate, '
    'including a cover, remix, live version, or alternate performance when '
    'that is the best available match for the same song. Use '
    'selectedCandidateId null only when every candidate is a completely '
    'different song. Respect sourcePriority when candidates are otherwise '
    'similarly accurate. Always prefer synced lyrics over plain lyrics. '
    'Return strict JSON only with exactly these fields: selectedCandidateId, '
    'confidence, reason.',
```

- [ ] **Step 7: Update existing selector test candidates**

Every `AiLyricsCandidate(...)` constructor in `test/services/lyrics/ai_lyrics_selector_test.dart` must now include a `lyricsPreview` argument. Use the value that best matches each test:

```dart
lyricsPreview: 'first line\nchorus line',
```

```dart
lyricsPreview: '',
```

```dart
lyricsPreview: 'poker face chorus preview',
```

- [ ] **Step 8: Run selector tests and verify they pass**

Run:

```bash
flutter test test/services/lyrics/ai_lyrics_selector_test.dart
```

Expected: all `AiLyricsSelector` tests pass.

---

### Task 2: Generate Lyrics Previews for Advanced Matching

**Files:**
- Modify: `lib/services/lyrics/lyrics_auto_match_service.dart:305-467`
- Test: `test/services/lyrics/lyrics_auto_match_ai_title_parser_test.dart:438-497,784-827`

- [ ] **Step 1: Write failing advanced matching preview test**

In `test/services/lyrics/lyrics_auto_match_ai_title_parser_test.dart`, replace `advanced mode saves AI selected high-confidence synced candidate` with this version:

```dart
test('advanced mode sends normalized lyrics preview to AI selection',
    () async {
  config = _config(mode: LyricsAiTitleParsingMode.advancedAiSelect);
  aiParser.result =
      _aiParsed(trackName: 'AI Song', artistName: 'AI Artist');
  netease.searchResultsByQuery['AI Song AI Artist'] = [
    _lyricsResult(
      id: 'chosen',
      source: 'netease',
      trackName: 'AI Song',
      artistName: 'AI Artist',
      syncedLyrics: '''
[ar:Metadata Artist]
[ti:Metadata Title]
[00:01.00] first line
[00:02.00] second line
[00:03.00] second line
[00:04.00] third line
[00:05.00] fourth line
[00:06.00] fifth line
[00:07.00] sixth line
[00:08.00] chorus line
[00:09.00] bridge line
''',
    ),
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
  final call = aiLyricsSelector.calls.single;
  expect(call.candidates.single.candidateId, 'netease:chosen');
  expect(call.candidates.single.hasSyncedLyrics, isTrue);
  expect(call.candidates.single.videoDurationSeconds, 180);
  expect(call.candidates.single.lyricsPreview, '''
first line
second line
third line
fourth line
fifth line
sixth line
chorus line
bridge line
'''.trim());
  expect(call.sourcePriority, ['netease']);
  expect(call.allowPlainLyricsAutoMatch, isFalse);
  expect(call.videoDescription, isNull);
  final saved = await repo.getByTrackKey('youtube:advanced-selected');
  expect(saved?.externalId, 'chosen');
});
```

- [ ] **Step 2: Add failing preview cap test**

Add this test after the normalized preview test:

```dart
test('advanced mode caps lyrics preview to 8 lines and 500 characters',
    () async {
  config = _config(mode: LyricsAiTitleParsingMode.advancedAiSelect);
  aiParser.result =
      _aiParsed(trackName: 'AI Song', artistName: 'AI Artist');
  final longLine = 'x' * 120;
  netease.searchResultsByQuery['AI Song AI Artist'] = [
    _lyricsResult(
      id: 'long-preview',
      source: 'netease',
      trackName: 'AI Song',
      artistName: 'AI Artist',
      syncedLyrics: List.generate(
        20,
        (index) => '[00:${index.toString().padLeft(2, '0')}.00]$longLine $index',
      ).join('\n'),
    ),
  ];
  aiLyricsSelector.result = const AiLyricsSelection(
    selectedCandidateId: 'netease:long-preview',
    confidence: 0.91,
    reason: 'best synced match',
  );

  final matched = await buildService().tryAutoMatch(
    _track('advanced-long-preview'),
    enabledSources: const ['netease'],
  );

  expect(matched, isTrue);
  final preview = aiLyricsSelector.calls.single.candidates.single.lyricsPreview;
  expect(preview.split('\n'), hasLength(lessThanOrEqualTo(8)));
  expect(preview.length, lessThanOrEqualTo(500));
});
```

- [ ] **Step 3: Add failing plain preview behavior test**

Add this test near `advanced mode filters plain candidates before AI when disabled`:

```dart
test('advanced mode uses plain lyrics preview only when plain matching is allowed',
    () async {
  config = _config(mode: LyricsAiTitleParsingMode.advancedAiSelect);
  aiParser.result =
      _aiParsed(trackName: 'AI Song', artistName: 'AI Artist');
  netease.searchResultsByQuery['AI Song AI Artist'] = [
    _lyricsResult(
      id: 'plain',
      source: 'netease',
      trackName: 'AI Song',
      artistName: 'AI Artist',
      syncedLyrics: null,
      plainLyrics: '''
[by:metadata]
plain first
plain second
plain third
plain fourth
plain fifth
plain sixth
''',
    ),
  ];
  aiLyricsSelector.result = const AiLyricsSelection(
    selectedCandidateId: 'netease:plain',
    confidence: 0.91,
    reason: 'best plain match',
  );

  final matched = await buildService().tryAutoMatch(
    _track('advanced-plain-preview'),
    enabledSources: const ['netease'],
    allowPlainLyricsAutoMatch: true,
  );

  expect(matched, isTrue);
  expect(
    aiLyricsSelector.calls.single.candidates.single.lyricsPreview,
    '''
plain first
plain second
plain third
plain fourth
plain fifth
plain sixth
'''.trim(),
  );
});
```

- [ ] **Step 4: Update fake selector call shape to compile after Task 1**

In `_FakeAiLyricsSelector.calls`, add `String? videoDescription` between `uploader` and `durationSeconds`:

```dart
final List<
    ({
      String endpoint,
      String apiKey,
      String model,
      String title,
      String? uploader,
      String? videoDescription,
      int durationSeconds,
      List<String> sourcePriority,
      bool allowPlainLyricsAutoMatch,
      List<AiLyricsCandidate> candidates,
      int timeoutSeconds,
    })> calls = [];
```

Update `_FakeAiLyricsSelector.select()` signature and recorded call:

```dart
@override
Future<AiLyricsSelection?> select({
  required String endpoint,
  required String apiKey,
  required String model,
  required String title,
  String? uploader,
  String? videoDescription,
  required int durationSeconds,
  required List<String> sourcePriority,
  required bool allowPlainLyricsAutoMatch,
  required List<AiLyricsCandidate> candidates,
  required int timeoutSeconds,
}) async {
  calls.add((
    endpoint: endpoint,
    apiKey: apiKey,
    model: model,
    title: title,
    uploader: uploader,
    videoDescription: videoDescription,
    durationSeconds: durationSeconds,
    sourcePriority: sourcePriority,
    allowPlainLyricsAutoMatch: allowPlainLyricsAutoMatch,
    candidates: candidates,
    timeoutSeconds: timeoutSeconds,
  ));
  return result;
}
```

- [ ] **Step 5: Run advanced matching tests and verify they fail**

Run:

```bash
flutter test test/services/lyrics/lyrics_auto_match_ai_title_parser_test.dart
```

Expected: failures mention missing `lyricsPreview` on `AiLyricsCandidate`, missing `videoDescription` forwarding, or empty/missing preview content.

- [ ] **Step 6: Implement preview generation and candidate enrichment**

In `lib/services/lyrics/lyrics_auto_match_service.dart`, update the selector call in `_matchAdvancedAi()` to pass the optional description explicitly. The current `Track` model has no description field, so do not synthesize one from title/uploader and do not fetch platform details:

```dart
final selection = await selector.select(
  endpoint: config.endpoint,
  apiKey: config.apiKey,
  model: config.model,
  title: track.title,
  uploader: track.artist,
  videoDescription: null,
  durationSeconds: trackDurationSec,
  sourcePriority: sources,
  allowPlainLyricsAutoMatch: allowPlainLyricsAutoMatch,
  candidates: aiCandidates,
  timeoutSeconds: config.timeoutSeconds,
);
```

Change `_toAiCandidate()` to accept `allowPlainLyricsAutoMatch`:

```dart
aiCandidates.add(
  _toAiCandidate(
    result,
    candidateId,
    sourceIndex,
    trackDurationSec,
    allowPlainLyricsAutoMatch,
  ),
);
```

Replace `_toAiCandidate()` with:

```dart
AiLyricsCandidate _toAiCandidate(
  LyricsResult result,
  String candidateId,
  int sourcePriorityRank,
  int videoDurationSeconds,
  bool allowPlainLyricsAutoMatch,
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
    lyricsPreview: _buildLyricsPreview(result, allowPlainLyricsAutoMatch),
  );
}
```

Add these helpers below `_toAiCandidate()`:

```dart
String _buildLyricsPreview(
  LyricsResult result,
  bool allowPlainLyricsAutoMatch,
) {
  final sourceText = result.syncedLyrics?.trim().isNotEmpty == true
      ? result.syncedLyrics
      : allowPlainLyricsAutoMatch
          ? result.plainLyrics
          : null;
  if (sourceText == null || sourceText.trim().isEmpty) return '';

  final normalizedLines = _normalizePreviewLines(sourceText);
  if (normalizedLines.isEmpty) return '';

  final selected = <String>[];
  void addLine(String line) {
    if (!selected.contains(line)) selected.add(line);
  }

  for (final line in normalizedLines.take(4)) {
    addLine(line);
  }

  final middleStart = normalizedLines.length ~/ 3;
  for (final line in normalizedLines.skip(middleStart).take(4)) {
    addLine(line);
  }

  final cappedLines = selected.take(8).toList();
  final buffer = StringBuffer();
  for (final line in cappedLines) {
    final prefix = buffer.isEmpty ? '' : '\n';
    final nextLength = buffer.length + prefix.length + line.length;
    if (nextLength > 500) {
      final remaining = 500 - buffer.length - prefix.length;
      if (remaining > 0) {
        buffer.write(prefix);
        buffer.write(line.substring(0, remaining));
      }
      break;
    }
    buffer.write(prefix);
    buffer.write(line);
  }
  return buffer.toString();
}

List<String> _normalizePreviewLines(String lyrics) {
  final lines = <String>[];
  for (final rawLine in const LineSplitter().convert(lyrics)) {
    final line = rawLine
        .replaceAll(RegExp(r'\[[0-9]{1,2}:[0-9]{2}(?:\.[0-9]{1,3})?\]'), '')
        .replaceAll(RegExp(r'^\s*\[(?:ar|ti|al|by|offset|length|re):[^\]]*\]\s*', caseSensitive: false), '')
        .trim();
    if (line.isEmpty || lines.contains(line)) continue;
    lines.add(line);
  }
  return lines;
}
```

Because these helpers use `LineSplitter`, add this import at the top of `lyrics_auto_match_service.dart`:

```dart
import 'dart:convert';
```

- [ ] **Step 7: Run advanced matching tests and verify they pass**

Run:

```bash
flutter test test/services/lyrics/lyrics_auto_match_ai_title_parser_test.dart
```

Expected: all tests in `LyricsAutoMatchService AI title parsing` pass.

---

### Task 3: Update Remaining Candidate Constructors and Regression Coverage

**Files:**
- Modify: `test/services/lyrics/lyrics_auto_match_ai_title_parser_test.dart:499-685`
- Modify: `test/services/lyrics/lyrics_auto_match_service_phase4_test.dart` only if compilation reveals helper constructor changes are needed there

- [ ] **Step 1: Update remaining tests for the new required candidate field**

Search for every remaining `AiLyricsCandidate(` constructor in tests and production. Each constructor must pass `lyricsPreview`. In `test/services/lyrics/lyrics_auto_match_ai_title_parser_test.dart`, the fake selector records candidates created by production code, so most tests need no constructor edits. In `test/services/lyrics/ai_lyrics_selector_test.dart`, Task 1 already updated direct constructors.

If compilation finds any additional direct constructor calls, add:

```dart
lyricsPreview: '',
```

for tests that do not care about preview content.

- [ ] **Step 2: Add assertion that plain-only disabled candidates are not sent**

In the existing `advanced mode filters plain candidates before AI when disabled` test, keep the existing assertions:

```dart
expect(matched, isFalse);
expect(aiLyricsSelector.calls, isEmpty);
```

This is the regression that proves plain-only candidate previews are not sent when `allowPlainLyricsAutoMatch` is false because those candidates are filtered out before AI selection.

- [ ] **Step 3: Run focused lyrics tests**

Run:

```bash
flutter test test/services/lyrics/ai_lyrics_selector_test.dart test/services/lyrics/lyrics_auto_match_ai_title_parser_test.dart test/services/lyrics/lyrics_auto_match_service_phase4_test.dart
```

Expected: all focused lyrics tests pass.

---

### Task 4: Final Verification and Documentation Check

**Files:**
- Verify: `docs/superpowers/specs/2026-05-02-ai-lyrics-context-enrichment-design.md`
- Verify: `CLAUDE.md`

- [ ] **Step 1: Confirm no documentation update is required**

Read the implementation diff and compare it to `docs/superpowers/specs/2026-05-02-ai-lyrics-context-enrichment-design.md`. The existing spec already documents the new `videoDescription` and `lyricsPreview` payload fields, no platform description fetches, and the preview cap rules. `CLAUDE.md` already describes the lyrics/AI system broadly and does not need a new model-field or migration note because this implementation does not add a database field.

If the implementation adds any behavior beyond this plan, update the relevant doc before final verification. If it stays within this plan, do not edit docs.

- [ ] **Step 2: Run analyzer**

Run:

```bash
flutter analyze
```

Expected: analyzer exits with code 0.

- [ ] **Step 3: Run full test suite**

Run:

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 4: Inspect final diff**

Run:

```bash
git diff -- lib/services/lyrics/ai_lyrics_selector.dart lib/services/lyrics/lyrics_auto_match_service.dart test/services/lyrics/ai_lyrics_selector_test.dart test/services/lyrics/lyrics_auto_match_ai_title_parser_test.dart
```

Expected: diff shows only payload enrichment, prompt updates, deterministic preview generation, and tests. It must not show platform detail fetches, new database fields, API key logging, source-limit changes, or confidence-threshold changes.
