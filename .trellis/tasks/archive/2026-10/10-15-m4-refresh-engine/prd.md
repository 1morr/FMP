# M4 PR 8a 匯入與刷新引擎

> M4 的 PR 8a（`../10-15-m4-library-sync/implement.md` § 8a）。設計在 `../10-15-m4-library-sync/design.md` §5.1、§5.2、§3.1、§2.2；決定在 ADR 0033 §決定 1、2，ADR 0019 §決定 2、3，ADR 0032 §決定 2（完整性、`writable`、錯誤）。沒有 UI（PR 8b）。

## 做什麼

- **schema v16**：`playlist_remote`（ADR 0033 §決定 1 的欄位；`playlist_id` 主鍵、外鍵連帶刪除；唯一（`plugin_id`, `remote_id`）；`writable` 與三個 `*_overridden` 預設假；`refresh_generation` 預設 0；`status` 列舉 `active`／`sourceGone`／`authRequired`、`last_result` 列舉 `complete`／`partial`／`failed`，寫死字串進 `converters.dart`，值型別在 `domain/playlist.dart`）。
- **repository**（`PlaylistRepository`，只加有人呼叫的）：建匯入歌單（`playlists` 一列 `kind = imported`＋`playlist_remote` 一列，同一個 transaction）、以（插件, `remote_id`）找列、開始刷新（`refresh_generation` 加一取得 g）、寫一頁（比對與接尾，每頁一個 transaction）、完整套用、標部分完成、標失敗與狀態。
- **`lib/library/playlist_importer.dart`**：`PlaylistImporter`——依 `pluginRegistryProvider` 順序問已啟用、宣告 `importPlaylist` 的插件 `playlistFromUrl`（插件拋錯就停）；都回 `null` → 「無法辨識這個網址」；`mixSeed` 與僅元資料來源回對應結果交給呼叫端（PR 11、19 處理，本 PR 只回傳型別）；已在 `playlist_remote` → 重新匯入＝刷新那一列、不覆寫本地設定；否則取第一頁，**第一頁成功才建列**（名稱取遠端標題、間隔 24 小時、`writable` 取回應），之後的頁交給刷新器。名稱不唯一、不自動改名。
- **`lib/library/playlist_refresher.dart`**：`PlaylistRefresher.refresh(playlistId, {trigger})`，演算法照 design §5.2 與 ADR 0033 §決定 2：全 App 一個 FIFO 鎖；比對鍵兩種（`remote_item_id`；否則（曲目鍵, 第 k 次出現）多重集合）；每頁寫入與套用前檢查代際與觸發者是否仍有效；完整（每頁成功、最後 `cursor` 空、有 `total` 時筆數相等）才刪 `seen_generation < g`、重寫 `position`、未覆寫的名稱／描述／封面跟遠端、`owner_name`、`writable`（回應給了才寫）、`last_result = complete`、`last_refreshed_at`、`status = active`、`updated_at`；不完整只寫 `partial`、`last_refreshed_at`、`status = active`；`NotFound` → `sourceGone`、`AuthRequired` → `authRequired`、其他 → `failed`（`status` 不動），都不碰項目；插件停用或移除 → 回「音源已停用／未安裝」不寫。
- **lint**：`fmp_layer_imports` 的 `library/` 那半條（`core/`、`domain/`、`data/`、`scheduler/` 不 import `library/`；`library/` 不 import `ui/`），雙向變異測試、`tool/lint_sentinel.dart` 違規行、`app/AGENTS.md` § Lint 表。
- `app/AGENTS.md`（§ 資料層、§ 插件的 `importPlaylist` 條改掉「`PlaylistImporter` 與刷新器還沒有」、新增 § 音樂庫）、`.trellis/spec/app/data/index.md`。

## 驗收

- **先寫測試**，再寫實作。測試：ADR 0019 §如何確認的刷新差異全部（新增、移除、順序、元資料、覆寫旗標、部分失敗不移除、重複影片保留、來源失效停止、重新匯入不覆寫設定）；比對鍵兩種；完整性三條件各缺一個是部分完成；中途被殺（某頁之後丟例外）後再刷一次結果正確；代際過期不寫；`writable` 為 `null` 保留上次的值；FIFO 鎖（兩次觸發同時只有一張在刷）；第一頁失敗不建列；插件停用不寫；migration 三種與新索引／唯一約束；lint 雙向變異。用 `fmp-test` 的假歌單（`pl-basic`、`pl-grow`、`pl-partial`、`pl-gone`、`pl-auth`、`pl-unavailable`、`pl-parts`）或測試內的假插件。
- 一萬首歌單的一次完整刷新量一次耗時（寫進回報，不做斷言）。
- `dart format`、`build_runner` 後無實質變動、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`；動到 lint 另跑 `packages/fmp_lints/` 的 `dart test` 與 `dart run tool/lint_sentinel.dart`。
- 沒有使用者看得到的改動：不做實機驗證。
