# M4 PR 6 `importPlaylist` 契約與 `fmp-test`

> M4 的 PR 6（`../10-15-m4-library-sync/implement.md` § 6）。契約在 ADR 0032 §決定 1、2、6、7、9；落地細節在 `../10-15-m4-library-sync/design.md` §4.1–§4.3、§4.9。

## 做什麼

- **`TrackSummary` 的分 P 兩欄**：選填 `partIndex`（正整數）、`parentTitle`（不空），兩個要嘛都有、要嘛都沒有（只給一個是 `ParseError`）。改 `fmp-plugin.d.ts`、Dart 端的 shapes（`sourceDtoShapes`）、`checks.dart` 的 `trackFields`；宿主寫進 `TrackInfo.partIndex`、`parentTitle`。搜尋結果也照收。
- **`importPlaylist` 能力**：`ImportPlaylistExports`（`playlistFromUrl`、`importPlaylist`）進 `requiredExports`／`knownExports`（宣告就要全有、匯出了沒宣告就拒載）；`SourcePlugin.playlistFromUrl`／`importPlaylist` 與 DTO、回傳值驗證：
  - `playlistFromUrl({url}) → {playlistId} | {mixSeed: {sourceId, cid?}} | null`；`mixSeed` 只收宣告 `mix` 的插件。
  - `importPlaylist({playlistId, cursor?}) → {playlist: {title, description?, artwork?, ownerName?, writable?}, items: [{track, remoteItemId?, unavailable?}], cursor: string|null, total?}`；`items` 可以是空陣列；`cursor` 空字串拒收；`total` 非負。
  - `FmpChecks.importPlaylist`：輸入 `{url}`，跑 `playlistFromUrl` 再跑第一頁，檢查 `items`（照既有能力檢查的期望寫法）。
  - 本 PR 不做 `PlaylistImporter`（依序問插件的服務在 PR 8a），不做 UI。
- **`fmp-test`**：design §4.9 表的 `importPlaylist` 列：`playlistFromUrl` 認 `https://fmp.test/playlist/<id>` 與 `https://fmp.test/mix/<sourceId>`（回 `mixSeed`）；歌單 `pl-basic`、`pl-grow`、`pl-partial`、`pl-gone`、`pl-auth`、`pl-unavailable`、`pl-parts`，行為照該表；狀態在插件 isolate 記憶體；寫進它的 README。
- `app/AGENTS.md` § 插件、`.trellis/spec/app/plugins/index.md` 同步（只寫查不到的契約）。

## 驗收

- 測試：
  - `import_playlist_capability_test.dart`：匯出與能力一致（宣告沒匯出、匯出沒宣告都拒載）；回傳值驗證；`mixSeed` 只給宣告 `mix` 的插件；`cursor` 空字串拒收；分 P 兩欄只給一個拒收。
  - `type_definitions_test.dart`：新欄位與新匯出 d.ts 與 Dart 一致（含變異案例）。
  - `checks_test.dart`、`contract_runner_test.dart` 的 `an importPlaylist check…`：沒宣告能力、期望不符會紅；改無關處不紅。
  - `health_check_test.dart`、`dev_case_runs_test.dart` 的 `an importPlaylist case`。
  - `test_plugin_bundle_test.dart` 守 `fmp-test` 的新歌單。
- `dart format`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全過。
- 沒有使用者看得到的改動：不做實機驗證。
