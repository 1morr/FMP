# M4 PR 1 歌單表與孤兒清理

> M4 的 PR 1（`../10-15-m4-library-sync/implement.md` § 1）。設計在 `../10-15-m4-library-sync/design.md` §3.1、§3.2，欄位清單在 ADR 0033 §決定 1。

## 做什麼

- schema v15：新增 `playlists`（含 Mix 三欄 `mix_plugin_id`、`mix_seed_source_id`、`mix_seed_cid` 與 CHECK：`kind = 'mix'` 時兩個 Mix 字串欄位非空，否則三個 Mix 欄位都空）、`playlist_entries`（`playlist_id` 連帶刪除、`track_key` RESTRICT、遠端三欄 `remote_item_id`、`unavailable`、`seen_generation`，索引 `playlist_entries_playlist`（`playlist_id`, `position`）與 `playlist_entries_track_key`）。`PlaylistKind`（`local`／`imported`／`mix`）等寫死字串進 `converters.dart`。
- `PlaylistRepository`（只加有人呼叫的方法）：`watchAll`（依 `sort_order`）、`create`、`update`（名稱、描述、封面）、`delete`、`reorder`（整批重寫 `sort_order`）、`entries(playlistId)`（依 `position`, `id`，join `tracks`）、`addTracks`（以 `TracksRepository.upsert` 寫曲目、接在尾端）、`removeEntries`、`moveEntries`（整批重寫 `position`）、`changes()`（`tableUpdates`）。
- 孤兒查詢（`TracksRepository._orphanCondition`）加 `playlist_entries`。
- `app/AGENTS.md` § 資料層、`.trellis/spec/app/data/index.md` 同步（只寫查不到的契約）。

## 驗收

- 照 `.trellis/spec/app/data/index.md` § 改 schema：快照、`stepByStep`、三種 migration 測試（空資料升級、資料完整性、不改使用者設定過的值），兩個新索引的升級與全新兩例。
- 測試：CHECK（mix 缺欄位、非 mix 帶 Mix 欄位都被拒）；刪歌單連帶刪項目；被歌單項目參照的曲目不能刪（RESTRICT）；`only unreferenced tracks are orphans` 加歌單項目的案例；`stored format` 測試含新列舉字串；`moveEntries`／`reorder` 重寫後順序正確；`addTracks` 接在尾端。
- 一萬首歌單的 `entries` 與 `moveEntries` 耗時量一次（寫進 PR 描述，不做斷言）。
- `dart format`、`build_runner` 後無實質變動、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全過。
- 沒有使用者看得到的改動：不做實機驗證。
