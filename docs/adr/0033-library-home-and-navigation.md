# 0033 — 音樂庫的資料與刷新、首頁與探索、五項導覽

- 狀態：已採納
- 日期：2026-10-15
- 影響範圍：資料表 `playlists`、`playlist_remote`、`playlist_entries`、`track_origins`、`match_results`、`chart_settings`，`source_settings` 與 `network_settings` 的新欄位；`app/lib/library/`、`app/lib/charts/`、`app/lib/core/matching/`；排程器的兩種新工作；外殼的導覽、首頁、探索頁、音樂庫、歌單詳情、多選、匯入與匯入預覽、帳號頁的歌單與電台匯入、設定頁的「音樂庫」區

## 背景

ADR 0019 定了音樂庫的原則：六張表的名稱與大意、遠端權威的單向刷新、來源失效、明確的遠端操作、僅元資料來源的匹配。ADR 0017 定了排行與匯入歌單刷新的排程規則，ADR 0016 定了排行快取，ADR 0031 把導覽重排、首頁的電台區塊、Mix 的歌單形態、粉絲勳章匯入留給 M4。

沒有定的（`.trellis/tasks/archive/2026-10/10-15-m4-library-sync/research/m4-scope-digest.md` §9）：表的欄位、刷新怎麼在每頁一個 transaction 下保持一致、「已失效」記在哪、Mix 歌單存什麼、排程工作怎麼切、排行與匹配的設定放哪、導覽與首頁的內容、各頁面的入口。另外兩個事實讓既有文字不成立：

- ADR 0028 §決定 4、ADR 0031 §決定 11 說 `playlists.kind = mix` 存（插件 id, `mixId`）；但 `mix` 的續取要 `{mixId, cursor}` 而 `cursor` 必填，`mixId` 開不了新的 Mix，要 `{seed}`。
- 加入首頁與音樂庫後導覽有 6 項，超過 Material 3 導覽列「三到五個目的地」的建議（m3.material.io 的 navigation bar guidelines）。

擁有者 2026-10-15 決定：M4 拆成 M4a「音樂庫與平台歌單」與 M4b「外部匯入、排行與備份」；導覽是 首頁｜搜尋｜音樂庫｜電台｜設定（各寬度同一組），「歷史」移進音樂庫頂端、首頁「最近播放」附「查看全部」，探索是首頁排行區塊的子頁，首頁排行設定放設定頁新的「音樂庫」區，不保留舊版「至少留一個榜單」。這改動了 M2 時「歷史當導覽項」的擁有者決定。

## 考慮過的選項

### 名稱、描述、封面的本地覆寫

- **遠端值與本地值各存一份**：顯示時再挑，多一組欄位、每個讀者都要挑。否決。
- **只存一份在 `playlists`，旗標為真時刷新不動它**：M5 的舊 `hasCustomCover` 直接對到封面旗標。採用。

### 「已失效」記在哪

- **`tracks`**：所有歌單共用，一張遠端歌單說失效，同一首在本機歌單也跟著標；而且是推導值（ADR 0010 §決定 2 只存事實）。否決。
- **`playlist_entries`**：「這張遠端歌單上次刷新時說這首不能播」，下一次刷新覆寫。採用。

### 刷新中途的一致性

- **暫存表抓完再整批換上**：刷新期間要兩份資料，中途被殺要清暫存。否決。
- **每頁一個 transaction 寫進正式表，以代際標出這次見過的項目**：中途被殺只留下代際落後的項目，下一次刷新修好。採用（ADR 0019 §決定 2 的字面）。

### 匯入歌單的排程工作

- **每張歌單一個工作**：幾十個計時器項目，「一次刷一張」要另外協調。否決。
- **每個插件一個工作**：同插件依序有了，但跨插件仍會同時刷兩張。否決。
- **一個全域工作每 30 分鐘檢查到期的歌單、依序刷**：「一次刷一張」自然成立。採用（舊版 `auto_refresh_service.dart` 的做法）。

### 排行、匹配的設定放哪

- **新的「音樂庫與同步」設定組**：排行間隔與電台間隔同性質，匹配目標與首頁排行都是「每個音源／每個榜單」的資料，不是單列表的欄位；這組在 M4 會是空表。否決。
- **排行間隔放「網路」組、匹配目標放每音源設定表、首頁排行一張以（插件, 榜單）為鍵的表**。採用。

### 導覽

- **六項全放**：超出 Material 的建議。否決。
- **首頁｜搜尋｜音樂庫｜歷史｜設定，電台只留首頁區塊**：電台是擁有者 M3 選的導覽項。否決。
- **設定移到首頁右上角**（Spotify、YouTube Music）：動得比較多。否決。
- **首頁｜搜尋｜音樂庫｜電台｜設定，歷史移進音樂庫**：YouTube Music 把歷史放在音樂庫裡；Material 3 文件的音樂 App 示例是 Home、Browse、Radio、Library。採用（擁有者決定）。

## 決定

1. **資料表**（列舉存寫死的字串、時間存 UTC epoch 毫秒，`app/AGENTS.md` § 資料層）：
   - `playlists`：`id`、`kind`（`local`／`imported`／`mix`）、`name`（不唯一）、`description?`、`artwork_json?`、`sort_order`、`created_at`、`updated_at`，Mix 三欄 `mix_plugin_id?`、`mix_seed_source_id?`、`mix_seed_cid?`；CHECK 保證「`kind = mix` ⇔ `mix_plugin_id` 與 `mix_seed_source_id` 都有值」。
   - `playlist_remote`（只有 `imported`）：`playlist_id`（主鍵，外鍵連帶刪除）、`plugin_id`、`remote_id`（與 `plugin_id` 唯一）、`owner_name?`、`writable`、`name_overridden`、`description_overridden`、`artwork_overridden`、`refresh_interval_hours?`（空＝不啟用；新匯入 24）、`last_refreshed_at?`、`last_result?`（`complete`／`partial`／`failed`）、`status`（`active`／`sourceGone`／`authRequired`）、`refresh_generation`。不建外鍵到 `installed_plugins`（`radio_stations` 的前例）。
   - `playlist_entries`：`id`、`playlist_id`（連帶刪除）、`position`、`track_key`（外鍵 `tracks`，`RESTRICT`，有索引，算孤兒的參照者）、`remote_item_id?`、`unavailable`、`seen_generation`；不對（歌單, 曲目鍵）或（歌單, 位置）設唯一，讀取依（`position`, `id`）排序。
   - `match_results`：主鍵（`origin_plugin_id`, `origin_id`）；`title`、`artists?`、`duration_ms?`（外部歌曲本身）、`selected_track_key?`（外鍵 `tracks`，`RESTRICT`，算孤兒的參照者；空＝匹配失敗或排除）、`score?`、`user_selected`。前 5 名候選不存。
   - `track_origins`：主鍵（`track_key`, `origin_plugin_id`），`origin_id`；`track_key` 外鍵 `ON DELETE CASCADE`，不算孤兒的參照者。
   - `chart_settings`：主鍵（`plugin_id`, `chart_id`），`enabled?`（空＝啟用）、`sort_order?`。
   - `source_settings` 加 `match_target?`（空＝依預設）、`match_rank?`；`network_settings` 加 `chart_refresh_interval_minutes?`（空＝60，`0`＝關閉）。
2. **刷新**（ADR 0019 §決定 2 的落地）：
   - 開始時 `refresh_generation` 加一得到 g。每一頁一個 transaction：upsert 曲目（元資料照遠端）；與既有項目比對，比到的寫 `seen_generation = g` 並更新 `unavailable`，比不到的接在尾端並寫 g。比對鍵：有 `remote_item_id` 用它，否則用（曲目鍵, 第 k 次出現），重複影片照多重集合比對、不合併。
   - 完整（ADR 0032 §決定 2）時一個 transaction：刪 `seen_generation < g` 的項目、照遠端順序重寫 `position`、名稱等未覆寫的欄位跟遠端、`last_result = complete`。不完整：不刪、不重排，`partial`。
   - 每頁與最後套用前檢查代際與工作是否仍有效；過期就丟掉、不寫。
   - `NotFound` → `status = sourceGone`、`AuthRequired` → `authRequired`，兩者都停止自動刷新，保留內容；其他錯誤 → `last_result = failed`，保留內容、不停止。重試或登入後成功就回到 `active`。
   - 重新匯入同一張（同插件、同 `remote_id`）＝刷新那一列，不動本地設定。
3. **Mix 歌單**存插件 id 與種子曲目，不存 `mixId`、不存曲目；「Mix 播放」以 `mix({seed})` 開新的一批並取代佇列（ADR 0031 §決定 9）。建立入口只有匯入（Mix 網址或 `mix:` 簡寫，經插件的 `playlistFromUrl`）。
4. **排程工作**（ADR 0017）：
   - `playlist-refresh`：所屬插件為空，間隔固定 30 分鐘；每次依序刷新所有到期的歌單（`status = active`、間隔不為空、插件已啟用、`last_refreshed_at` 加間隔已過）。單張失敗只寫那張的狀態；到期的全部失敗才算工作失敗。手動刷新（歌單卡、詳情頁、遠端寫入之後）走同一個刷新器，一個互斥鎖保證全 App 同時只刷一張，不看間隔。
   - `charts:<pluginId>`：每個有啟用榜單的已啟用插件一個，間隔是「網路」組的排行間隔；榜單全停用就不登記（B12）。單一榜單失敗只標那一個，全部失敗才退避（電台工作的前例）。
5. **導覽**：首頁｜搜尋｜音樂庫｜電台｜設定，compact、medium／expanded、large 以上三種導覽元件同一組，App 開在首頁。每個目的地有自己的巢狀 `Navigator`：歌單詳情、歷史、探索在內容區內開，導覽與播放列留著，返回回到原頁。
   - 補充（2026-10-24，U PR 0，ADR 0035）：導覽是 首頁｜搜尋｜音樂庫｜佇列｜電台｜設定（六項），手機的佇列是整頁（ADR 0035 §決定 2）。
6. **首頁**的區塊依序：排行（每個啟用的榜單依使用者順序列前 5 首，附「查看全部」開探索頁）、我的歌單、電台、最近播放（後三者至多 20 項，各附「查看全部」切到音樂庫、電台，或開歷史）。沒有舊版的「正在播放」「佇列預覽」（新版有播放列、右側面板、佇列分頁）。沒有任何已啟用、具 `search` 能力的插件時，首頁顯示首次啟動引導（ADR 0030 §決定 12 的同一個元件）。
7. **探索頁**：每個啟用的榜單一個分頁（依使用者順序），完整清單、多選。停用的榜單不抓、不顯示、刪快取（ADR 0016 §決定 4）。
8. **音樂庫**：頂端「歷史」入口，下面是歌單卡（封面、名稱、首數、本機／匯入（音源）／Mix 標記），拖曳排序；工具列「新增」「匯入」。歌單卡選單：Mix 播放（Mix）、全部加入佇列、隨機加入、編輯、刷新（匯入）、刪除。
9. **歌單詳情**：標頭（封面、名稱、描述、擁有者、匯入歌單的上次刷新與狀態列）、「全部」（只加入佇列，ADR 0018 的 D2）、「隨機加入」；曲目以 `TrackKey.formatGroup` 分 P 分組；只有本機歌單能拖曳重排與刪除曲目；超過 10,000 首的加入整批拒絕（ADR 0018 §決定 4）。狀態列：「來源失效：遠端歌單已刪除或無權限」＋「重試」、「需要登入才能刷新」＋「登入」、「上次刷新：部分完成」、「刷新失敗」＋「重試」。
10. **多選**：一個共用的多選模式，用在歌單詳情、搜尋、歷史、探索；動作是加入佇列、加入歌單、加入遠端歌單、從本機歌單移除。
11. **曲目選單**加「加入歌單…」（只列 `local` 歌單，對話框內可新增）與「加入遠端歌單…」（曲目所屬插件宣告 `libraryWrite` 且已登入時出現；只列那個插件 `libraryPlaylists` 裡可寫的歌單，勾選後直接送出，另有「在遠端新增歌單」）；可寫的匯入歌單詳情另有「從遠端歌單移除」（確認框）。
12. **匯入**：音樂庫「匯入」對話框收網址或 `mix:` 簡寫，經 `playlistFromUrl` 依序問已啟用的插件。有 `resolveStream` 的插件直接匯入（進度、完成後開詳情）；只有 `importPlaylist` 的插件（Spotify、QQ）開全頁的匯入預覽：逐首以共用評分核心在目標音源中搜尋、保留合併後的前 5 名、第一名過門檻才自動選；可改選、重搜、排除；確認後建立 `local` 歌單並寫 `match_results`、`track_origins`。同一首外部歌再被匯入時直接用 `match_results`，不重算。
    - 補充（2026-10-21，M4 PR 19）：有 `resolveStream` 的插件的歌單，對話框另有「配對到其他音源」（預設仍是「匯入為平台歌單」；`mixSeed` 的網址沒有這個選擇），選了就走同一個匯入預覽、建 `local` 歌單、不寫 `playlist_remote`、不刷新。不針對任何插件 id；插件端沿用 `importPlaylist`，不另加能力或 manifest 欄位。這次匯入的目標音源預設不勾來源插件自己，預覽頁的 chip 可以勾回。最後一頁 `truncated` 時照常匹配，預覽頁提示「來源只提供了部分曲目」（M4 `design.md` §17 第 19 條）。
13. **帳號頁**：宣告 `libraryRead` 且已登入的音源一列多「歌單」：列出帳號歌單、已匯入的標示並停用勾選、勾選後逐張匯入。匯出 `libraryLiveRooms` 的音源另有「從帳號匯入電台」，摘要「新增 n 個，m 個已在電台清單」；字樣不寫「粉絲勳章」（宿主沒有音源分支）。
14. **設定頁**多「音樂庫」區（首頁排行的榜單排序與啟用、匹配目標音源的排序與勾選），排行刷新間隔在「網路」區、與電台間隔並列。「音樂庫與同步」組在 M4 沒有欄位、不建表。

採用的慣例：Finamp 的 id 集合差集刷新；舊版 `auto_refresh_service.dart` 的 30 分鐘檢查、一次一張；舊版首頁、探索頁、音樂庫、歌單卡選單、`account_playlists_sheet.dart` 的內容；YouTube Music 把歷史放進音樂庫；Material 3 的導覽列目的地數與巢狀導覽（每個目的地自己的 back stack）；Namida「加入不確認、移除才確認」（ADR 0019 已採）。

## 後果

- 好的：每張表的資料都有讀者；刷新中途被殺不會壞掉資料，部分完成看得見；重複影片保留；Mix 歌單開得了新的一批；導覽回到 Material 的建議項數；排行與匹配的設定跟著每音源、每榜單走，插件增減不必 migration。
- 壞的：歷史從導覽項降一層；首次啟動引導要在首頁與搜尋頁兩處維持一致；`match_results` 只增不減（使用者改選後不再重算的代價，列很小）；多一個巢狀 `Navigator` 要照顧快捷鍵與焦點三區。
- 之後要注意：
  - M5 把舊 `Playlist`、`Track.isAvailable`／`originalSongId`／`originalSource`、排行設定對到這些表（對照表在 M4 的 `design.md`）；
  - M6 的下載紀錄加進孤兒查詢，歌單詳情加下載按鈕；
  - M7 歌詞以 `track_origins` 的原始 id 直接抓、與匯入共用評分核心；
  - 「另存為本地歌單」、曲目收藏、網易「疑似換版本」仍在功能凍結待辦（ADR 0019）。

## 如何確認

- 資料庫測試：每張新表的 migration 三種（空資料升級、資料完整性、不改使用者設定過的值）；CHECK（`kind = mix` 缺欄位寫不進去）；外鍵連帶刪除；孤兒清理不刪被歌單項目或 `match_results` 參照的曲目；`playlist_entries.track_key` 的索引（升級與全新兩例）。
- 刷新的單元測試：ADR 0019 §如何確認的全部案例，加上：比對鍵（有 `remote_item_id`、沒有時的第 k 次出現）、中途被殺後再刷新一次結果正確、代際過期的頁不寫、`writable` 為 `null` 時保留。
- 排程：在排程器的假時鐘測試模式下，`playlist-refresh` 只選到期且 `active` 的歌單、一次一張、全部失敗才退避、手動刷新與排程互斥；`charts:<pluginId>` 榜單全停用時不登記、單一榜單失敗不退避。
- widget 測試：五個導覽項（三種視窗寬度）與 App 開在首頁；首頁區塊與「查看全部」；沒有插件時首頁出現引導；詳情頁四種狀態列；多選在四頁的動作；曲目選單的兩個新項目只在條件成立時出現；guideline 400／1000 寬。
- 實機（ADR 0027）：M4a、M4b 驗收的端到端步驟（任務的 `implement.md`）。
