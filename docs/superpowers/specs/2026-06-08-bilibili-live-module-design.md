# Bilibili Live Module Design

## Goal

Deepen Bilibili live API ownership by moving live-room mechanics into one
Bilibili-specific module while preserving current search, radio, and account
import behavior.

## Context

FMP currently supports Bilibili live rooms in three places:

- `lib/data/sources/bilibili_source.dart` owns live-room search helpers,
  live-room info lookup, and a live stream URL helper used by search flows.
- `lib/services/radio/radio_source.dart` owns radio URL parsing, live room
  info lookup, high-energy viewer lookup, stream URL lookup, and
  `RadioStation` construction.
- `lib/services/account/bilibili_account_service.dart` owns account login and
  also performs live medal wall room lookup.

`SourceHttpPolicy` already owns live header defaults. The friction is that
endpoint sequencing, response parsing, real room ID normalization, and live
stream parameters are duplicated across modules.

## Scope

This is a behavior-preserving refactor. It includes:

- Bilibili live room URL parsing for `live.bilibili.com/<id>` and
  `live.bilibili.com/h5/<id>`.
- Real room ID resolution through Bilibili live `room_init`.
- Live room info lookup through `get_info`, anchor info, and room news.
- High-energy viewer count lookup through the current live ranking endpoint.
- Radio stream lookup through `/room/v1/Room/playUrl` with the existing radio
  low-bitrate parameters.
- Search-page stream URL lookup with the existing `h5` / `quality: 4`
  behavior.
- Live room search through the current `live_room` and `bili_user` search
  paths.
- Medal wall room lookup for account radio import.

It does not include:

- Multi-source radio support.
- Playback behavior changes.
- Stream quality parameter changes.
- Header policy changes.
- A broad source base interface.
- UI redesign.

## Architecture

Add a Bilibili-specific live module named `BilibiliLiveClient`. It will be the
only module that knows Bilibili live endpoint URLs, live Dio creation, and live
response shapes.

`BilibiliSource` keeps the public live methods needed by existing callers, but
those methods become thin adapters to `BilibiliLiveClient`. It remains the
adapter for normal Bilibili video search, metadata, and audio stream resolution.

`RadioSource` keeps its public interface for `RadioController` and
`RadioRefreshService`. It remains responsible for radio-facing orchestration and
mapping live room data to `RadioStation`, but it no longer owns live endpoint
mechanics.

`BilibiliAccountService` keeps account and credential ownership. It obtains the
auth cookie and user mid, then delegates medal wall live room lookup to
`BilibiliLiveClient`.

`SourceHttpPolicy` remains the source of live headers and live Dio creation.
The new module must use `SourceHttpPolicy.createBilibiliLiveDio()` and
`SourceHttpPolicy.bilibiliLiveHeaders()`.

## Module Interface

The new module will expose behavior-oriented methods:

- `parseLiveUrl(String url)`: returns a parsed live room ID and normalized URL,
  or `null` for non-Bilibili live URLs.
- `resolveRealRoomId(String roomId)`: resolves short room IDs and returns the
  original room ID if resolution fails.
- `getRoomInfo(String roomId)`: returns combined room, anchor, and room-news
  data, or `null` when the primary room info API fails in contexts that already
  tolerate missing info.
- `getRadioStream(String roomId)`: returns radio playback URL plus live media
  headers, using the current radio low-bitrate playUrl parameters.
- `getHighEnergyUserCount(String roomId)`: returns the current high-energy
  viewer count value, or `null` on lookup failure.
- `getSearchStreamUrl(int roomId)`: returns the current search-page stream URL
  behavior, including `platform: h5` and `quality: 4`.
- `searchRooms(String query, {int page, int pageSize, LiveRoomFilter filter})`:
  returns `LiveSearchResult` using the current merge/filter behavior.
- `getMedalWallRooms({required String targetId, required String cookie})`:
  returns medal wall room items for account radio import.

The public interfaces of `RadioSource` and `BilibiliSource` should remain
compatible during this refactor.

## Data Flow

### Search Live Rooms

`SearchNotifier` continues to call `BilibiliSource.searchLiveRooms()`.
`BilibiliSource` delegates to `BilibiliLiveClient.searchRooms()`. Search state,
pagination, and stale-request protection remain unchanged.

### Radio Station Creation

`RadioSource.createStationFromUrl()` parses the URL, creates a basic
`RadioStation`, then asks `BilibiliLiveClient.getRoomInfo()` for metadata.
It maps the result into the existing `RadioStation` fields.

### Radio Playback

`RadioController.play()` continues to call `_radioSource.getStreamUrl(station)`.
`RadioSource` delegates stream lookup to the live client. The live client
resolves the real room ID and uses the current radio playUrl parameters:

- `platform: web`
- `quality: 2`
- `qn: 80`

It returns `LiveStreamInfo` with `SourceHttpPolicy.bilibiliLiveHeaders()`.

### Radio Refresh

`RadioRefreshService` continues to depend on `RadioSource`. `RadioSource`
delegates room info, high-energy viewer count, and live status checks to the
live client, then maps the result into existing `LiveRoomInfo`, `int?`, and
`bool` responses.

### Account Radio Import

`BilibiliAccountService.fetchMedalWall()` continues to own account checks. It
gets the Bilibili auth cookie and user mid, then calls the live client to fetch
and resolve medal wall room entries. Existing `MedalWallItem` behavior remains.

## Error Handling

Preserve current behavior:

- Real room ID resolution failures are logged and fall back to the original room
  ID.
- Room info primary API failures surface through the existing caller behavior:
  radio station creation falls back to a generic room title, while live search
  enrichment falls back to the basic search result.
- Anchor info and room news failures do not fail the full room info request.
- Radio stream failures throw when playUrl returns a non-zero code or an empty
  `durl`.
- Search stream URL lookup returns `null` on playUrl failure.
- Medal wall lookup skips individual failed room entries without failing the
  whole list.
- No live Referer or user-agent values are hard-coded outside
  `SourceHttpPolicy`.

## Testing

Use TDD for the implementation. Add focused tests for the new live module
before moving production logic.

Required tests:

- `parseLiveUrl()` accepts standard and `/h5/` Bilibili live URLs.
- `resolveRealRoomId()` returns API room ID and falls back to input on request
  failure.
- `getRoomInfo()` combines room info, anchor info, and room news.
- `getRoomInfo()` tolerates anchor/news failure.
- `getRadioStream()` uses the current radio playUrl parameters and returns live
  headers.
- `getHighEnergyUserCount()` preserves the current ranking endpoint behavior
  and returns `null` on lookup failure.
- `getSearchStreamUrl()` preserves current search stream parameters and null
  on failure behavior.
- `searchRooms()` preserves current `live_room` + `bili_user` merge/filter
  behavior.
- `getMedalWallRooms()` maps room items and skips failed room lookups.

Update static policy tests to check the new module, not string ownership inside
`RadioSource` or `BilibiliSource`.

Run at minimum:

```bash
flutter test test/services/radio test/services/account test/data/sources
flutter test test/providers/search_pagination_stale_test.dart
```

## Documentation

Update `lib/data/sources/AGENTS.md` so live room helpers and the live Dio are
owned by the new Bilibili live module rather than `BilibiliSource`.

Update `lib/services/AGENTS.md` only if the account medal wall import wording
needs to mention the new module. No human-facing `docs/` update is expected
because product behavior should not change.

## Constraints

- UI playback controls must continue to go through `AudioController`.
- Radio remains Bilibili-only.
- Live radio stream URLs continue to come from `/room/v1/Room/playUrl` `durl`
  responses.
- Bilibili video stream resolution must continue to preserve `Track.cid` and is
  outside this refactor.
- Header policy remains in `SourceHttpPolicy`.
- Existing public provider names remain unchanged for this refactor.
