# Lyrics AI Advanced Matching Design

## Context

Current automatic lyrics matching has two relevant limitations:

- AI only parses a video title into a likely track title and artist. It does not inspect lyrics search results before a match is saved.
- Automatic matching currently rejects results without synced lyrics. Users need an explicit setting to decide whether plain, non-synced lyrics can be matched automatically.

This design adds an AI advanced matching mode that lets AI select from actual lyrics search candidates, while keeping API search volume controlled to avoid rate limiting.

## Goals

- Add an AI advanced matching mode that selects the best lyrics candidate from search results.
- Provide video title, uploader, video duration, lyrics source priority, and each candidate's synced/plain status to AI.
- Adopt AI-selected matches when the selected candidate is known, valid, and allowed by the synced/plain setting.
- Add a setting to control whether automatic matching may save non-synced lyrics.
- Default AI title parsing to off for new installs and migrate legacy fallback mode to off.
- Log all AI request payloads and responses for both existing title parsing and new advanced matching, without logging API keys.
- Avoid regex fallback after an AI mode returns a valid no-selection or unknown-candidate result.

## Non-goals

- Do not change manual lyrics search behavior.
- Do not change the `LyricsMatch` persistence format.
- Do not add new lyrics providers.
- Do not store AI candidate-selection decisions in the database beyond the normal saved `LyricsMatch`.

## AI Modes

The settings UI will expose three modes:

1. **Off**
   - No AI calls.
   - Automatic matching uses the existing regex title parser and local scoring.
   - This is the default for new installs.
   - Legacy `fallbackAfterRules` settings are repaired to this mode.

2. **AI title parsing**
   - Renames the old `alwaysAi` behavior in the UI.
   - After direct ID lyrics fetches fail, AI parses `trackName` and optional `artistName` from the video title and uploader context.
   - Search and selection still use local matching/scoring.
   - If AI parses successfully but no lyrics match is selected, matching ends without falling back to regex.
   - If AI configuration, connection, timeout, or response parsing fails, matching falls back to regex.

3. **AI advanced matching**
   - After direct ID lyrics fetches fail, AI parses the title.
   - The app searches candidates in the configured lyrics source priority order.
   - The app sends filtered candidates to AI for selection.
   - AI must return a selected candidate and confidence.
   - The app saves the match only if the selected candidate is valid, known, and allowed by the synced/plain setting.
   - If AI explicitly returns no selection or an unknown candidate, matching ends without falling back to regex.
   - If AI configuration, connection, timeout, or response parsing fails, matching falls back to regex.

Direct ID fetches remain before all AI modes because they are precise and avoid broad search:

- Netease tracks use `sourceId` directly.
- Imported tracks with `originalSongId` and `originalSource` use the original platform ID directly.

## Non-synced Lyrics Setting

Add a persisted setting:

```dart
bool allowPlainLyricsAutoMatch = false;
```

Behavior:

- When false:
  - Direct fetches, regex matching, AI title parsing, and AI advanced matching only accept synced lyrics.
  - AI advanced matching only sends synced candidates to AI.
- When true:
  - Automatic matching may save plain, non-synced lyrics.
  - AI advanced matching sends synced and plain candidates to AI.
  - The AI prompt still instructs the model to always prefer synced lyrics.

The Isar default for a new bool field is `false`, which matches the desired default, so no dedicated migration is required for this setting.

## Advanced Matching Candidate Flow

After AI title parsing succeeds, the service builds query pairs:

- `trackName + artistName` if AI returns an accepted artist.
- `trackName` alone only when AI does not return an accepted artist.

For each query pair, the service searches enabled lyrics sources in the user's configured priority order. Netease and QQ Music advanced candidate searches request up to 10 results, matching manual search defaults.

Each candidate sent to AI includes:

- Stable candidate key, such as `netease:123456`.
- Lyrics source.
- Source priority rank.
- Track name.
- Artist name.
- Album name.
- Candidate duration.
- Video duration.
- Absolute duration difference.
- Whether synced lyrics are available.
- Whether plain lyrics are available.
- Whether translated or romaji lyrics are available.

If `allowPlainLyricsAutoMatch` is false, non-synced candidates are filtered before the AI selection request.

## AI Candidate Selection Contract

The AI selection call uses the same OpenAI-compatible chat completions endpoint as title parsing.

The prompt must tell AI:

- Use video title, uploader, video duration, and source priority to choose.
- Uploader is context and is not necessarily the artist.
- Always choose the closest acceptable candidate, including covers, remixes, live versions, or alternate performances when they are the best available match for the same song.
- Return `selectedCandidateId: null` only when every candidate is a completely different song.
- Respect lyrics source priority when candidates otherwise look similarly accurate.
- Always prefer synced lyrics over plain lyrics.
- Return strict JSON only.

Expected JSON shape:

```json
{
  "selectedCandidateId": "netease:123456",
  "confidence": 0.91,
  "reason": "Title, artist, duration, and synced lyrics availability match."
}
```

No-match shape:

```json
{
  "selectedCandidateId": null,
  "confidence": 0.42,
  "reason": "No candidate is reliable enough."
}
```

The app saves a match only when:

- `selectedCandidateId` matches a candidate sent to AI.
- The candidate is allowed by the non-synced lyrics setting.

Confidence is logged for diagnostics, but there is no hard confidence threshold. The model should express completely different-song cases by returning `selectedCandidateId: null`.

## Logging

All AI calls log debug information without exposing the API key.

Title parsing logs:

- AI mode.
- Endpoint base URL.
- Model.
- Title.
- Uploader.
- Timeout.
- Request user payload.
- Raw response content.
- Parsed result.
- Whether artist name was accepted based on confidence.

Advanced matching logs:

- Original track title.
- Uploader.
- Video duration.
- Lyrics source priority.
- Whether plain lyrics auto-match is allowed.
- AI parsed title result.
- Query pairs.
- Candidate list sent to AI.
- Raw AI response.
- Parsed selected candidate, confidence, and reason.
- Final save/skip decision and reason.

## UI

The lyrics source settings AI dialog will:

- Remove the fallback mode option.
- Display old `alwaysAi` as **AI title parsing**.
- Add **AI advanced matching**.
- Explain that AI title parsing only changes the search query, while AI advanced matching lets AI choose from candidates.
- Keep **Allow automatic matching of non-synced lyrics** on the lyrics source settings page, default off.

## Data Migration and Compatibility

Implementation should avoid enum index drift causing legacy settings to map to the wrong mode.

Recommended approach:

- Keep a stable persisted integer mapping in `Settings.lyricsAiTitleParsingMode` getter/setter.
- Treat legacy fallback index as `off`.
- Treat legacy always index as `alwaysAi`.
- Add a new persisted index for `advancedAiSelect`.
- Update database default repair so legacy fallback defaults become off.

## Tests

Add or update tests for:

- AI title parsing JSON parsing and artist confidence filtering.
- AI candidate-selection JSON parsing.
- Legacy fallback index resolving to off.
- `allowPlainLyricsAutoMatch=false` filtering non-synced automatic matches.
- Advanced mode sending only synced candidates when plain matching is disabled.
- Advanced mode saving known selected candidates regardless of confidence.
- Advanced mode not falling back to regex after valid no-selection or unknown-candidate AI responses.
- AI title parsing and advanced matching falling back to regex only for AI configuration, connection, timeout, or response parsing failures.
