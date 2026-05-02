# AI Lyrics Context Enrichment Design

## Context

AI advanced lyrics matching currently receives video title, uploader, duration, source priority, and candidate metadata. It does not receive video description text or any lyric content from candidates. This can make it hard for AI to distinguish official lyrics from covers, remixes, live versions, instrumental tracks, or unrelated songs with similar metadata.

This design enriches only the AI advanced matching selection payload. It avoids extra platform API calls and keeps token use bounded.

## Goals

- Include existing video description context when it is already available.
- Include a short deterministic lyrics preview for each AI candidate.
- Improve AI candidate selection accuracy without changing manual search or regex matching.
- Avoid sending full lyrics to AI.
- Avoid adding network requests during automatic matching.
- Preserve current selection rules: AI may save only known candidate IDs, and there is no hard confidence threshold.

## Non-goals

- Do not fetch missing video descriptions from YouTube, Bilibili, Netease, or other platforms.
- Do not add a new database field in this change unless an existing model already has a suitable description field.
- Do not change lyrics source search limits or source priority behavior.
- Do not change fallback rules for AI unavailable, invalid, or no-selection cases.
- Do not send full synced, translated, romaji, or plain lyrics to AI.

## Payload Shape

Extend the existing AI selection request payload.

Top-level payload adds:

```json
{
  "videoDescription": "optional existing description text"
}
```

Each candidate adds:

```json
{
  "lyricsPreview": "short normalized lyric excerpt"
}
```

Both fields are optional strings. Omit `videoDescription` when no existing description is available. Use an empty preview only when a candidate has no eligible lyric text after filtering.

## Video Description Source

Use existing data only.

Candidate implementation order:

1. Check whether `Track` or the already-loaded track detail data exposes a description field.
2. If no existing description is available in the advanced matching call path, omit `videoDescription`.
3. Do not call platform detail APIs from automatic matching.

The description must be normalized before sending:

- Trim whitespace.
- Collapse repeated whitespace.
- Cap to a fixed character limit.
- Do not include secrets, cookies, request headers, or URLs fetched only for playback.

Recommended cap: 500 characters.

## Lyrics Preview Generation

Preview generation happens per `LyricsResult` before constructing `AiLyricsCandidate`.

Source text selection:

1. Prefer `syncedLyrics` when present.
2. If `syncedLyrics` is absent and `allowPlainLyricsAutoMatch` is enabled, use `plainLyrics`.
3. If neither eligible text exists, use an empty preview.

Normalization:

- Strip LRC timestamps such as `[00:12.34]`.
- Remove metadata tags such as `[ar:...]`, `[ti:...]`, and `[by:...]`.
- Trim each line.
- Drop empty lines.
- Drop duplicate lines while preserving order.

Excerpt strategy:

- Take the first 4 normalized lines.
- Take up to 4 normalized lines from the middle third of the lyric, as a simple chorus/representative-content approximation.
- Combine those segments, remove duplicates again, and join with newline characters.
- Cap the final preview to 8 lines and 500 characters.

This is deterministic and avoids model-dependent preprocessing.

## AI Prompt Update

Update the AI selector system prompt to tell the model:

- It may use `videoDescription` as additional context.
- It may use `lyricsPreview` to compare candidate content.
- Uploader remains context and is not necessarily the artist.
- Prefer synced lyrics over plain lyrics.
- Choose the closest acceptable same-song candidate.
- Return `selectedCandidateId: null` only when every candidate is a completely different song.

## Logging

Existing debug logging may continue to print the JSON payload, but the payload is now larger. The preview and description are user-visible metadata/lyrics excerpts, not credentials.

Keep current API-key protections:

- Never log `apiKey`.
- Never log `Authorization` headers.

## Tests

Add or update tests for:

- `AiLyricsSelector` includes `videoDescription` and candidate `lyricsPreview` in the request payload.
- API keys remain absent from logs and payload assertions.
- Lyrics preview generation strips timestamps and metadata tags.
- Lyrics preview generation uses first lines plus a middle segment and respects line/character caps.
- Advanced matching sends candidate previews to AI.
- Plain-only candidate previews are not sent when `allowPlainLyricsAutoMatch` is false because those candidates remain filtered out before AI selection.

## Open Decisions Resolved

- Video description source: existing fields/data only; no automatic platform detail fetch.
- Lyrics preview strategy: first lines plus middle segment approximation.
- Token control: cap both description and per-candidate preview to 500 characters.
