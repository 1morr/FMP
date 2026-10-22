# M4 規劃決定草案：矛盾處理、未定之處分類、拆分與 PR 順序

> 輸入：`research/m4-scope-digest.md`（§8 的 10 條矛盾、§9 的 42 條未定之處，下稱「矛盾 n」「#n」）。
> 套件事實在 2026-10-15 以 pub.dev API（`/api/packages/<名稱>`、`/score`）查證，只取 stable；`pinyin` 的繁簡轉換以一個暫時的 Dart 程式實跑（下方 §2 #22）；OpenCC 字表從 `BYVoid/OpenCC` 的 `data/dictionary/TSCharacters.txt` 取得計數。Flutter 的 build hooks 狀態以 flutter/flutter#129757 與 dart.dev/tools/hooks 查證。MusicFree 插件協定以官方文件 `musicfree.catcat.work/plugin/protocol.html` 查證。Material 導覽列項數以 m3.material.io 查證。沒有打任何音源的真實 API；查不到或沒實測的標「待查」「未實測」。
> 分類：甲＝文件已有答案（附出處）；乙＝技術決定（附建議、慣例、要不要新 ADR）；丙＝擁有者決定。
> 乙類裡會改到 ADR 文字或舊版行為的，列進最後一節「需要擁有者確認的技術決定」（比照 M3 design §16），不另外當丙類問。
> 作者：opus 規劃代理（只寫本檔）。**這是草案**：之後與 `design.md`、新 ADR 不同之處以後者為準。

## 0. 先講結論

- 丙類壓到 4 題：範圍與拆分、導覽與首頁、備份、真實帳號與遠端寫入的實測。
- `opencc` 在目前的 Flutter stable 建不起來（靜態證據，§2 #22）；建議改用 OpenCC 的字表產生純 Dart 對照，屬乙類，列入確認清單。
- 新 ADR 三則：0032（宿主 API v1 的 M4 擴充）、0033（音樂庫、首頁與導覽的資料與入口）、0034（備份檔與還原）。
- 建議拆成 M4a「音樂庫與平台歌單」（PR 1–15）與 M4b「外部匯入、排行與備份」（PR 16–22）。
- digest 漏掉一條 ADR 之間的矛盾（矛盾 11：ADR 0012 對「收藏夾」的 `required` 與「歌單刷新」的 `userPreference` 重疊）；digest §2 第 11、13、14 條已被 `archive/2026-10/10-15-account-redaction` 的擁有者決定取代（見 §2 甲 #9 後的附註）。

## 1. 矛盾（digest §8）的處理

| # | 處理 | 動作 |
|---|---|---|
| 1 | 備份的四種說法收斂成一種，由丙3 決定。建議 E16 沿用 M3 的資料庫副本（`VACUUM INTO`），排除不可攜的表，開放到設定頁匯出、匯入。 | 新 ADR 0034；ADR 0025 §決定 9 加一行「E16 的備份檔見 ADR 0034」；ADR 0010 影響範圍的「備份格式」加一行指到 0034（ADR 0010 本文只有舊備份檔匯入，M5）。 |
| 2 | 頁面對照表與 ADR 0031 的七項本來就屬 M4（E3 含「多選」、E14 含「探索」都已勾保留，`questions.md:243,252`），只是 §M4 範圍漏寫。由丙1 一起確認。 | `milestones.md` § M4 範圍補齊（PR 0）；若拆分，ADR 0026 §決定 3 加一行修訂。 |
| 3 | Spotify、QQ 插件要做才能達成「做完」那一句；ADR 0014 §決定 2 規定它們是插件。放 M4b（丙1）。 | `milestones.md` § M4 範圍加「Spotify、QQ 插件（`1morr/fmp-plugins`，id `spotify`、`qqmusic`）」。 |
| 4 | `playlist_remote` 補「刷新間隔」一欄，空＝不啟用；新匯入寫 24。舊 `notifyOnUpdate` 不保留：舊版只存、備份、顯示在資料庫檢視，沒有任何地方依它通知（`lib/` grep 只命中 `import_service.dart`、`backup_*`、`database_catalog.dart`）。`useAuthForRefresh` ADR 0019 已否決。 | ADR 0019 §決定 1 加一行補充；列入確認清單第 5 條。 |
| 5 | 不用 `opencc` 套件。改用 OpenCC 的 `TSCharacters.txt` 產生純 Dart 對照（§2 #22）。純 Dart 沒有建置驗證可做，驗收改成評分核心的繁簡測試。 | ADR 0019 §決定 6 與 §後果各加一行更正；`milestones.md` § M4 驗收的「`opencc` native assets 在各平台建置」換成 ADR 0019 的測試項；列入確認清單第 1 條。 |
| 6 | Mix 歌單存「插件 id＋種子曲目（`sourceId`、`cid?`）」，播放時以 `mix({seed})` 開新的一批；不存 `mixId`（`{mixId, cursor}` 的 `cursor` 必填，開不了新的）。這也是舊版的做法（`mixSeedVideoId`）。 | ADR 0028 §決定 4、ADR 0031 §決定 11 各加一行更正；列入確認清單第 2 條。 |
| 7 | 新版名稱不唯一（ADR 0019 已定），匯入不自動改名；重新匯入靠（插件, 遠端 id）辨識。若丙3 選「取代並重啟」，備份沒有合併，同名問題不存在。舊備份匯入的同名規則屬 M5。 | 不改文件；M5 的對照註記寫進 design（#40）。舊版自動改名的移除列入確認清單第 6 條。 |
| 8 | 照 M3 先例補驗收項：每半各一條「ADR 測試對到表」。 | `milestones.md` § M4 驗收（PR 0）；見 §2 乙 #1 的說明（併在丙1）。 |
| 9 | 兩份說法相容：對所有目標音源搜尋、合併評分、取前 5 名，第一名自動選，同分依使用者排序。舊版是每音源各 5 個。 | ADR 0019 §決定 5 加一行補充；列入確認清單第 7 條。 |
| 10 | 由丙2 決定導覽。事實補上：Material 3 的導覽列「三到五個目的地」（m3.material.io navigation-bar guidelines），加首頁與音樂庫後的 6 項超出。 | ADR 0031 §決定 3 加一行更正；新 ADR 0033 寫導覽。 |
| 11（新） | **ADR 0012 §決定 2 的 `required` 含「讀收藏夾與私人歌單」，`userPreference` 含「歌單刷新」**：刷新一個 B 站收藏夾兩邊都算。照字面標 `required` 會讓未登入的人不能匯入公開收藏夾（舊版可以）。處理：匯入與刷新一律 `userPreference`；回應是「無權限」且這次沒帶憑證（`credentialsAttached` 為假，ADR 0028 §決定 2）、使用者已登入時，插件以 `required` 重送一次——讀私人歌單本來就是 `required`。宿主不必改。 | ADR 0012 §決定 2 加一行補充（指到 ADR 0032）；列入確認清單第 4 條。 |

## 2. 未定之處（digest §9）

### 甲、文件已有答案（5 條）

- **#9 宿主與 `fmp-plugins` 同一輪改**
  - 順序：FMP 先合併宿主契約，`fmp-plugins` 再實作並開 PR 改 `FMP_REF`（ADR 0030 §決定 3：「以 `FMP_REF` checkout FMP」；`0030:25`「宿主 API 變了就開 PR 改它」）。
  - 版本：`.js` 有改動時 manifest 版本必須提高，index 由腳本重產（`0030:39`）。
  - 同一輪的範圍：ADR 0028 §決定 1、9（同一 PR 改 d.ts、Dart shapes、`SourcePlugin`、`FmpChecks`）。
  - M3 的實際順序相同（M3 `implement.md`，PR 1／2 → PR 3）。
  - 附註（digest §2 第 11、13、14 條已過時）：`archive/2026-10/10-15-account-redaction/prd.md` 的擁有者決定（2026-10-15）是只遮自己的 id、以帳號的 `userId` 登記為已知值、不照 #264 原文加鍵名。所以「M4 前擴充鍵名名單」不再需要；網易 uid 不論放 query 或路徑都會被已知值遮掉（子字串比對，全數字只看數字邊界）；別人的 `mid` 照留，契約測得到。剩下的只有 #10。
- **#14 「重新匯入同一張遠端歌單」的辨識**
  - 等於刷新、不覆寫本地設定（ADR 0019 §決定 2 最後一條，M12）。辨識鍵自然是（插件 id, 遠端 id），`playlist_remote` 對它設唯一。
  - 本地改過的名稱、描述、封面看覆寫旗標（`0019:37,48`），不動。
  - 從帳號頁與從網址匯入同一張＝同一列，結果相同；帶不帶憑證依 ADR 0012 的音源設定（`0019:28` 否決每張歌單各存）。
- **#15 孤兒查詢與外鍵**
  - `playlist_entries.track_key` 照 `queue_entries`、`play_history` 的做法：外鍵 `ON DELETE RESTRICT`、建索引、加進 `TracksRepository.deleteOrphans`（`app/AGENTS.md` § 資料層：「之後加表的 PR（歌單項目、下載紀錄）各自把自己加進那個查詢」，索引的理由與 `migration_test.dart` 的閘門同段）。
  - 刪歌單以 `CASCADE` 刪項目，曲目留到下次啟動維護（ADR 0019 §決定 1「登記在啟動維護清單」）。
- **#21 背景刷新的失敗呈現**
  - 自動刷新不跳 toast，只更新歌單頁狀態（ADR 0019 §決定 3、ADR 0013 `:61`）；離線不跑（ADR 0017 §決定 3）；`RateLimited.retryAfter` 優先（ADR 0017 §決定 4）；部分完成顯示「上次刷新：部分完成」（ADR 0019 §決定 2）；`NotFound`／無權限標「來源失效」並停止自動刷新（ADR 0019 §決定 3）。
  - 需要登入（`AuthRequired`）照 ADR 0013 `:52`「提示並附『登入』」。狀態列舉與文案細節在 #17。
- **#42 i18n 與 a11y**
  - 三語言 slang（ADR 0024 §決定 7，`app/AGENTS.md` § 介面）；`meetsGuideline` 清單已列首頁與歌單（`0024:157`），新頁面照列。

### 乙、技術決定（29 條）

#### 範圍與驗收

- **#1 驗收項（範圍本身在丙1）**
  - 建議每半各加一條「ADR 測試逐項對到 `implement.md` 的表，證據寫進 `research/m4-adr-tests.md`」，照 M3a／M3b（`milestones.md:97-100,112-116`）。
  - M4a：ADR 0019 §如何確認（刷新差異、資料庫、`importPlaylist`／`libraryWrite` 契約）、0017（新工作）、0028／0032（新能力與 `checks.json`）、0033（導覽的 widget 測試）。
  - M4b：ADR 0019 §決定 6 的評分測試、0016（排行快取）、0017（排行工作）、0034（備份與還原）。
  - 文件：`milestones.md`，不需要 ADR。

#### 插件契約（全部寫進新 ADR 0032）

- **#4 `importPlaylist`**
  - 匯出：
    - `playlistFromUrl({url}) → {playlistId} | {mixSeed: {sourceId, cid?}} | null`：不是這個插件的網址回 `null`。宿主依序問每個已啟用、宣告 `importPlaylist` 的插件，第一個認得的勝出（ADR 0031 §決定 2 `liveRoomFromUrl` 的做法）。YouTube 插件認得 `list=RD…` 的 Mix 網址與 `mix:<videoId>` 簡寫，回 `mixSeed`；宿主不解析任何音源的網址。
    - `importPlaylist({playlistId, cursor?}) → {playlist: {title, description?, artwork?, ownerName?, writable?}, items: [{track: TrackSummary, remoteItemId?, unavailable?}], cursor: string | null, total?}`。`cursor` 為空＝最後一頁。
  - 完整性：每一頁都成功、最後 `cursor` 為空、而且（有 `total` 時）拿到的筆數等於 `total`，才算完整，才套用移除與順序（ADR 0019 §決定 2）。插件只在確定 `total` 等於會回傳的筆數時才給它：YouTube 的標頭筆數含被隱藏的無法播放影片，給了會讓每次刷新都變「部分完成」。
  - `TrackSummary` 加選填的 `partIndex`、`parentTitle`：B 站收藏夾照舊版在匯入時展開多 P（`import_service.dart:561`），由插件呼叫影片資訊 API 展開；這也解掉 M3 留下的「upsert 清掉分 P 兩欄」（digest §2 第 8 條）。
  - `remoteItemId`：YouTube 的 `setVideoId`（移除要用）；`unavailable`：遠端標失效（#12）；`writable`：插件從帶了憑證的回應判斷這張是不是自己的、可寫（#6 的入口條件用）。
  - 認證：`userPreference`，私人歌單的重送見矛盾 11。
  - `checks.json`：案例跑 `importPlaylist` 第一頁，用公開歌單，不標 `requiresLogin`。
  - 慣例：MusicFree 的 `importMusicSheet(urlLike)` 與分頁的 `getMusicSheetInfo(sheet, page)`（回 `isEnd`）；ADR 0031 的 `liveRoomFromUrl`。
- **#5 `libraryRead`**
  - `libraryPlaylists({cursor?}) → {playlists: [{playlistId, title, artwork?, trackCount?, writable}], cursor | null}`，`required`。
  - 「已匯入」由宿主比對（插件 id, `playlistId`）與 `playlist_remote`，插件不管。
  - 粉絲勳章牆：同能力下的選填匯出 `libraryLiveRooms() → {rooms: LiveRoom[]}`，`required`；有匯出且插件也宣告 `live` 時，帳號區才出現「從帳號匯入電台」（#33）。ADR 0031 `:24` 本來就把它歸「`libraryRead` 一類」，不另立能力（ADR 0014 §決定 4 的能力清單不用改）。選填匯出的前例是 `login` 依 `methods` 決定要匯出哪些。
  - 網易用哪個端點（digest §2 第 13 條）交給插件 PR：自己的 uid 已登記為已知值（甲 #9 附註），query 或路徑都會被遮。
- **#6 `libraryWrite`**
  - `createPlaylist({title}) → {playlistId}`；`addToPlaylist({playlistId, tracks: [{sourceId, cid?}]}) → {results: [{status: 'added' | 'alreadyPresent' | 'failed', error?}]}`；`removeFromPlaylist({playlistId, items: [{sourceId, cid?, remoteItemId?}]}) → {results: [{status: 'removed' | 'notPresent' | 'failed', error?}]}`。結果與輸入同順序，`error` 用插件錯誤的既有形狀（ADR 0013）。全部 `required`。
  - 宣告 `libraryWrite` 必須同時宣告 `libraryRead`（列可寫的歌單要用它），manifest 驗證時檢查。
  - 去重在插件內做（YouTube 的 `checkVideoInPlaylist`、網易的 `getTrackIdsInPlaylist`、B 站的 `fav_state`），宿主只看 `alreadyPresent`。B 站 bvid→aid 也在插件內（ADR 0014 §決定 1：宿主沒有音源分支）。
  - 「加入遠端歌單」對話框不預先勾出已含該曲目的歌單（舊版 B 站有），列入確認清單第 10 條。要的話之後加一個選填的 `playlistsContaining` 匯出。
  - 寫入成功後由宿主觸發那張本地匯入歌單的刷新（ADR 0019 §決定 4「再背景刷新」），走 #18 的同一個刷新器。
  - 網易寫入的 `X-Real-IP`：沿用 M3 design §16 第 14 條已核准的做法——先以真實連線測「不帶」，不帶不行才只在必要的請求送，寫進插件 README。
  - 慣例：Namida「加入不確認、移除才確認」（ADR 0019 已採）；部分成功逐項回報照 ADR 0013 `:61`。
- **#7 `charts`**
  - `chartList() → {charts: [{chartId, title}]}`（可以是插件內的常數，不發請求）；`chart({chartId}) → {tracks: TrackSummary[]}`，不分頁（舊版各取約 50 首）。認證 `userPreference`（ADR 0012 §決定 2 已把排行列在裡面；舊版 YouTube、網易排行永遠不帶，M6 的不一致就此統一）。
  - 預設：所有榜單都啟用；停用的不抓、刪快取（B12，ADR 0016 §決定 4、ADR 0017 §決定 5）。
  - YouTube 的榜單照舊版（YouTube Music「New This Week」歌單，依觀看數排）由插件決定，宿主不知道。
  - 慣例：MusicFree 的 `getTopLists()` 與 `getTopListDetail(topListItem, page)`。
- **#8 `checks.json` 與健康檢查的副作用**
  - 案例可標 `mutates: true`：只在契約測試重播；Debug 頁健康檢查、命令列冒煙、App 內錄製一律略過並標「略過：會改動遠端」。fixture 一律手寫或刪減並標 `meta.edited`（ADR 0015 §決定 7 的更正、`fmp-plugins/test/login_fixtures_test.dart` 已守 `requiresLogin` 的案例）。
  - 每能力一條：`importPlaylist`（公開歌單）、`libraryRead`（`requiresLogin`）、`libraryWrite`（`addToPlaylist`，`requiresLogin`＋`mutates`）、`charts`（第一個榜單）。
  - 這是 ADR 0015 §決定 4「一份四用」的例外，列入確認清單第 3 條。
- **#10 帶憑證錄 fixture 的閘門**
  - 建議在第一個需要登入、又不是 `login` 的錄製之前，獨立一個 PR（§4 PR 12）：`recordCase` 對所有 `requiresLogin` 案例都以 `accounts` 列的 `userId`、`displayName`、頭像換值，`accountLeaks` 照樣當最後一道；隔離環境帶上該音源的已存憑證（`app/AGENTS.md:1093`、M3 `implement.md:545,557`）。
  - 依據：account-redaction design §10 已寫好這條待辦與做法。
  - 新增的閘門要在測試檔內做雙向變異（含自己 creator 名稱的回應會被擋；改一個無關欄位不擋）。

#### 資料模型（寫進新 ADR 0033 的資料段）

- **#11 五張表的欄位**（每張表由第一個用到它的 PR 建，不提前建沒有讀者的表）
  - `playlists`：`id`、`kind`（`local`／`imported`／`mix`）、`name`、`description?`、`artwork_json?`、`sort_order`、`created_at`、`updated_at`；Mix 三欄 `mix_plugin_id?`、`mix_seed_source_id?`、`mix_seed_cid?`，以 CHECK 保證「`kind = mix` ⇔ 前兩欄有值」（同 `player_state` 的 Mix 欄位做法）。
  - `playlist_remote`：`playlist_id`（主鍵、外鍵連帶刪除）、`plugin_id`、`remote_id`（與 `plugin_id` 唯一）、`owner_name?`、`writable`、三個覆寫旗標、`refresh_interval_hours?`（空＝不啟用）、`last_refreshed_at?`、`last_result`（`complete`／`partial`／`failed`）、`status`（`active`／`sourceGone`／`authRequired`）、`refresh_generation`。不建外鍵到 `installed_plugins`（`radio_stations`、`accounts` 的前例）。
  - 名稱、描述、封面只存一份在 `playlists`：旗標為假時刷新把遠端值寫進去，為真時不動。M5 的 `hasCustomCover` 直接對到封面旗標。
  - `playlist_entries`：`id`、`playlist_id`（連帶刪除）、`position`、`track_key`（`RESTRICT`，甲 #15）、`remote_item_id?`、`unavailable`、`seen_generation`；不對（歌單, 曲目鍵）設唯一（ADR 0019）。
  - `track_origins`：`track_key`（`ON DELETE CASCADE`，不算孤兒的參照者）、`plugin_id`、`origin_id`。M4 的寫入者是外部匯入；讀者是 M5（舊 `originalSource`／`originalSongId`）與 M7（以原始 id 直接抓歌詞）。
  - `match_results`：以（來源插件 id, 原始 id）為鍵，存原始標題、歌手、時長、`selected_track_key?`（`RESTRICT`，算參照者，讓「使用者改選後不再重算」不會因孤兒清理失效）、`score?`、`user_selected`。不存候選清單：前 5 名只在匯入預覽的記憶體裡。未匹配的歌存 `selected_track_key` 為空。
  - 同一首外部歌再被匯入時直接用 `match_results` 的結果，不重算；這就是 ADR 0014 §決定 9「結果持久化」的讀者。未匹配的歌只在預覽頁標示，不進本地歌單（歌單項目一定要有曲目鍵），列入確認清單第 12 條。
- **#12 「已失效」放哪**
  - 放 `playlist_entries.unavailable`：它是「這張遠端歌單上次刷新時說這首不能播」的觀察，下一次刷新覆寫。ADR 0010 §決定 2「只存事實」；本機歌單不標，播放失敗照 ADR 0018 處理。
  - 舊 `Track.isAvailable` 在 M5 對到含該曲目的匯入歌單項目。列入確認清單第 11 條（ADR 0019 §決定 2 寫的是「曲目……可用狀態」）。
- **#13 刷新套用的交易與中斷一致性**
  - 每次刷新先把 `refresh_generation` 加一得到 g。每一頁一個 transaction：upsert 曲目（元資料照遠端）；比對既有項目，比到的寫 `seen_generation = g` 並更新 `unavailable`，比不到的接在尾端新增並寫 g。
  - 比對鍵：有 `remote_item_id` 就用它；沒有就用（曲目鍵, 第 k 次出現），所以重複影片照多重集合比對，不會被合併。
  - 完整抓完：一個 transaction 刪掉 `seen_generation < g` 的項目、照遠端順序重寫 `position`（`queue_entries` 先改負值的技巧）、更新名稱等。不完整：不刪、不重排，`last_result = partial`。
  - 中途被殺：已寫的頁各自一致，只是有 `seen_generation` 落後的項目；下一次刷新會修好。每頁與最後套用前都檢查 `JobContext.isCurrent` 與代際。
  - 刷新期間歌單頁顯示資料庫現況（舊順序加尾端新增），不加暫存表。
  - 慣例：Finamp 的 id 集合差集（ADR 0019 已採）。測試涵蓋 ADR 0019 `:85,87` 列的全部案例。
- **#16 Mix 歌單**
  - 欄位見 #11；建立入口只有「匯入」對話框（Mix 網址或 `mix:` 簡寫，經 YouTube 插件的 `playlistFromUrl`），建立時呼叫一次 `mix({seed})` 驗證並取標題當預設名稱。舊版也只有這個入口。
  - 歌單卡選單：「Mix 播放」、編輯（名稱）、刪除；詳情頁不列曲目，只有「Mix 播放」與種子曲目。播放走 M3 的 `startMixFrom`（取代佇列，ADR 0031 §決定 9）。
  - 慣例：舊版 `playlist_card_actions.dart:151-164`。ADR 更正見矛盾 6。
- **#17 來源失效與需要登入的呈現**
  - 歌單頁頂端狀態列：`sourceGone`＝「來源失效：遠端歌單已刪除或無權限」＋「重試」；`authRequired`＝「需要登入才能刷新」＋「登入」（ADR 0013 `:52`）。兩者都停止自動刷新；重試或登入後重新排入。
  - `failed`（其他錯誤）保留上次成功的內容，不停止自動刷新；`partial` 顯示「上次刷新：部分完成」。都附上次刷新時間。
  - 唯讀副本就是原本的歌單，曲目照常能播。「另存為本地歌單」仍是凍結待辦（`0019:80`）。

#### 刷新與排程

- **#18 排程工作切分**
  - 匯入歌單：一個全域工作 `playlist-refresh`（所屬插件為空，ADR 0017 §決定 2 允許），間隔固定 30 分鐘，每次依序刷新所有到期的歌單（`last_refreshed_at + refresh_interval_hours` 已過、插件已啟用、狀態為 `active`）。「一次刷一張」因此是全域的。
    - 單張失敗只寫該張的狀態；到期的全部失敗才算工作失敗、進退避（ADR 0031 §決定 6 電台工作的前例）。
    - 手動刷新（歌單卡、歌單頁、寫入後）呼叫同一個刷新器，以互斥鎖保證同時只刷一張，不看間隔；排程中的那一輪正在跑時排在它後面。
    - 間隔改成「不啟用」、插件停用或移除時，下一輪自然不選它；正在跑的那張以代際丟掉結果（ADR 0017 §決定 5）。
    - 慣例：舊版 `auto_refresh_service.dart` 每 30 分鐘檢查、一次一張。
  - 排行：每個有啟用榜單的插件一個工作 `charts:<pluginId>`，間隔是「網路」組的排行間隔；榜單全停用就不登記（B12）。照 `radio-status:<pluginId>`。
  - 工作登記寫在新的 `lib/library/`、`lib/charts/`，排程器不 import 它們（#39 的 lint）。
- **#19 設定歸屬與欄位**
  - 排行刷新間隔：`network_settings.chart_refresh_interval_minutes`，與電台間隔同組同表示法（空＝預設 60，0＝關閉）。M2 design 把電台間隔歸「網路」組，同一類放一起。
  - 每張歌單的間隔：`playlist_remote.refresh_interval_hours`（資料列，不是設定組）；新匯入的 24 小時是常數。
  - 匹配目標音源：每音源設定表 `source_settings` 加 `match_target`（可空，空＝預設啟用）、`match_rank`（可空，拖曳排序）。ADR 0011 §決定 7「每個音源的設定另一張表」。
  - 首頁排行的順序與啟用：新表 `chart_settings(plugin_id, chart_id, enabled?, sort_order?)`，榜單是插件動態給的，不能是單列表的欄位。
  - 結果：「音樂庫與同步」組在 M4 沒有欄位，不建空表（M3 design §16 第 5 條同一個理由：沒有讀者的欄位不加）。列入確認清單第 9 條。
  - 都在資料庫，所以都在備份裡（ADR 0011 §決定 7），除非丙3 選了排除。
- **#20 `notifyOnUpdate`**：不保留（矛盾 4）。M5 對照時丟掉它。列入確認清單第 5 條。

#### 匹配

- **#22 繁簡統一的實作**（M3 的 `opencc` 假設不成立）
  - 查到的選項（2026-10-15）：

    | 選項 | 版本與日期 | 授權 | 平台與建置 | 判斷 |
    |---|---|---|---|---|
    | `opencc` 1.1.0 | 2024-10-01 | Apache-2.0 | 依賴 `native_assets_cli ^0.8.0`，那是 build hooks 在 Dart 3.10／Flutter 3.38 穩定之前的實驗 API（flutter/flutter#129757）；`app/` 用 Flutter 3.47.5。release `opencc-v1` 沒有 Android、iOS 的預編譯庫 | 不可用（靜態證據，未實跑：建置會從一個 0 likes 套件的 GitHub release 下載並執行原生庫，沒有在本機跑） |
    | `opencc` 1.2.0-dev.1 | 2025-08-01 | 同上 | prerelease，`main` 釘 `sdk: 3.10.0-14.0.dev`；repo 最後 push 2025-08 | 不採（有 stable 替代） |
    | `flutter_opencc_plus` 0.1.4 | 2026-10-05（首版 2026-08-21） | Apache-2.0 | `hooks ^2.2.0`、`code_assets ^2.0.0`，Dart ≥3.10、Flutter ≥3.35；預編譯 Android 四個 ABI、iOS、macOS、Windows x64／arm64、Linux；建置時從 GitHub release 下載並驗 SHA-256；pub points 155、likes 0 | 可行的備案：完整 OpenCC（含詞組）；代價是新套件、單一維護者、建置要連 GitHub（與 `sqlite3` 相同）、多一個原生庫 |
    | `flutter_open_chinese_convert` 1.0.0 | 2026-08-28 | MIT | 平台通道，只有 Android、iOS、web | 不可用（沒有 Windows） |
    | `pinyin` 3.3.0 | 2024-04-16（repo 最後 push 2026-03） | BSD-2-Clause | 純 Dart，五平台＋web；字級 7654 對、詞組 277 條；pub points 160、likes 19、30 天下載約 1.46 萬 | 實跑：`週杰倫`→`週杰伦`、`乾杯`→`乾杯`、`隨著`→`随著`（OpenCC 的字表給 `周`、`干`）。它把兩岸都用的字保留不轉，對顯示是對的，對比對是漏洞：`周杰伦` 與 `週杰倫` 會失配 |
    | **OpenCC `TSCharacters.txt` 產生的純 Dart 對照** | OpenCC `master`（2026-10-09 push） | Apache-2.0（資料） | 純 Dart；5062 個繁體字，998 個有多個候選取第一個；原檔約 100 KB | **建議** |

  - 建議：`tool/` 放一份釘在某個 OpenCC commit 的 `TSCharacters.txt`（含授權標頭）與產生器，產生 `lib/core/matching/` 下的 const map 並提交；測試斷言「重新產生的內容等於已提交的」（不連網）與一組已知字對。授權以 `LicenseRegistry` 登記 OpenCC 的 Apache-2.0。
  - 理由：比對只需要「兩邊折成同一個字」，不需要正確的簡體文字。兩邊都經同一張字級對照，`乾隆` 折成 `干隆` 也是兩邊一致；所以不需要詞組轉換與原生庫。字表正是 ADR 0019 指名 `opencc` 想要的資料。
  - 順序照全域規則：專案依賴裡沒有；成熟套件裡，原生的那個太新、純 Dart 的那個資料對比對有缺口（實跑證據）；剩下的是資料而不是邏輯，產生器約數十行。
  - 驗收：ADR 0019 §如何確認的「繁簡」案例＋上面兩項測試；「各平台建置」不再適用（矛盾 5）。
  - 列入確認清單第 1 條。若擁有者要完整 OpenCC，改用 `flutter_opencc_plus`，先在 Android 與 Windows 各建一次（§6）。
- **#23 評分核心的細節**
  - 位置：`lib/core/matching/`（純函式，不依賴 `data`、`plugins`；M7 歌詞直接 import）。`unorm_dart` 0.3.3、`string_similarity` 2.2.0（都純 Dart、MIT）只准在這裡（`fmp_layer_imports` 的 `externalPackageOwners`）。
  - 起始公式：`0.6 × 標題 + 0.3 × 歌手 + 0.1 × 時長`。
    - 標題：主標題（去掉括號）的 Dice，與括號內容另外比（MusicBrainz 的延伸資訊不整段刪，ADR 0019 已採）：兩邊括號內容不同（例如一邊 `Live`）時扣一點，不整首否決。
    - 歌手：以 `/ 、 , & ; feat. ft. × x` 拆開，取兩兩最佳。
    - 時長：超出「10 秒或 5% 取較寬」直接淘汰；之內線性給分。任一邊缺時長就不設門檻、時長分給 0.5。
  - 自動選：第一名的分數到門檻（起始 0.6）才選；沒有任何候選過門檻就是「匹配失敗」。權重與門檻用一份手寫的測試語料（約 50 對真實標題，不連網）校準後寫死。
  - ADR 0019 只定框架，這些寫進 design 與測試，不需要新 ADR。
- **#24 目標音源集合**
  - 預設：所有已啟用、同時有 `search` 與 `resolveStream` 的插件，**含網易**（舊版只有 B 站與 YouTube，因為當時網易不能播；`sources.md:301`）；同分依 `source_settings.match_rank` 排序。
  - 設定頁「音樂庫」區一個可拖曳、可勾選的清單（舊版首頁排行設定頁的樣式），匯入預覽頁可以臨時改並重搜。
  - 列入確認清單第 8 條（網易可能匹配到試聽片段；它的 `previewOnly` 由播放處理，評分不看來源特有訊號，ADR 0019 §決定 6）。
- **#25 逐首搜尋的執行**
  - 依序處理每首；每首對各目標音源同時搜尋第一頁，節流交給每插件限流（ADR 0013）。
  - 匯入預覽頁顯示進度「n／總數」與取消；離開頁面先確認並取消。不交給排程器（它只管週期工作），App 在背景時只要行程還在就繼續。
  - 單首搜尋失敗標「搜尋失敗」並可在預覽頁重搜，不中斷整批（ADR 0013 `:61` 部分成功要標出失敗項目）。
  - 大歌單的耗時見 §6 風險 4。慣例：舊版 `importAndMatch`。

#### UI（寫進新 ADR 0033）

- **#30 音樂庫與歌單詳情**（舊版行為為準）
  - 音樂庫頁：歌單卡（封面、名稱、首數、本機／匯入（插件圖示）／Mix 標記）、拖曳排序（`sort_order`），工具列「新增」「匯入」。
  - 歌單卡選單：Mix 播放（Mix）、全部加入佇列、隨機加入、編輯、刷新（匯入）、刪除。「隨機加入」照舊版保留：打亂後加入佇列，成本很小（ADR 0018 沒有它，但也沒否決）。
  - 詳情頁：標頭（封面、名稱、描述、擁有者、上次刷新與狀態列 #17）、「全部」（只加入佇列，D2）、「隨機加入」；曲目清單以 `TrackKey.formatGroup` 做分 P 分組（M3 `implement.md:504`）；只有本機歌單能拖曳重排、刪除曲目；超過 10,000 首整批拒絕（ADR 0018 §決定 4，M2 的 `QueueFull`）。
  - 建立／編輯對話框：名稱（必填）、描述、封面（預設第一首；自訂照舊版 `create_playlist_dialog.dart`）、自動刷新間隔（只有匯入歌單）。
  - 多選（E3 勾了保留，新版還沒有）：共用的多選模式，用在歌單詳情、搜尋、歷史、探索（舊版四頁，`features.md:59-60`）；動作是加入佇列、加入歌單、加入遠端歌單、從本機歌單移除。
  - 下載按鈕等 M6。
- **#31 匯入入口**
  - 音樂庫工具列「匯入」→ 對話框，一個文字欄（網址或 `mix:` 簡寫）→ `playlistFromUrl`。
  - 可播放音源的歌單直接匯入（進度對話框，完成後進歌單頁）；只有 `importPlaylist`、沒有 `resolveStream` 的插件（Spotify、QQ）進匯入預覽頁（全頁，ADR 0019 §決定 5 稱「匯入預覽頁」；大歌單放不進對話框）。
  - 帳號頁「管理歌單」是另一個入口，走同一個匯入引擎（#34）。
- **#32 曲目選單的兩個新項目**
  - `TrackRowMenu` 加「加入歌單…」（只列 `local` 歌單，對話框內可「新增歌單」，ADR 0019 §決定 4）與「加入遠端歌單…」。
  - 後者只在曲目所屬插件宣告 `libraryWrite` 且已登入時出現：B 站的曲目只能加進 B 站的收藏夾（舊版 `track_action_handler.dart:220,306` 也是過濾）。對話框列 `libraryPlaylists` 裡 `writable` 的歌單，勾選後直接送出（不加確認框），另有「在遠端新增歌單」。
  - 匯入歌單的詳情頁，`writable` 為真時曲目選單另有「從遠端歌單移除」（確認框，ADR 0019 §決定 4）。
  - 套用在所有用 `TrackRowMenu` 的地方（搜尋、歷史、佇列、歌單詳情、探索），加上多選列。
- **#33 從帳號匯入電台**
  - 帳號區該音源一列的選單「從帳號匯入電台」，經 `libraryLiveRooms`；結果寫 `radio_stations`，摘要「新增 n 個，m 個已在電台清單」（ADR 0031 §決定 2 的重複提示）。
  - 字樣不寫「粉絲勳章」：宿主沒有音源分支（ADR 0014 §決定 1）。列入確認清單第 13 條。
  - 自己的 `mid` 已登記為已知值（甲 #9 附註）。
- **#34 帳號頁「管理歌單」**
  - 帳號區每個宣告 `libraryRead` 且已登入的音源一列多一個「歌單」，開一頁清單：勾選、已匯入的標「已匯入」並停用勾選；確認後逐張匯入（舊版 `account_playlists_sheet.dart`）。
  - 「在遠端新增歌單」只放在加入遠端的對話框（舊版同）。
  - 帶不帶憑證：`libraryRead` 是 `required`；匯入後的刷新依 ADR 0012 的音源設定，私人歌單照矛盾 11 重送（取代舊版「帳號頁匯入一律帶登入」，M12）。

#### 備份（依丙3 的選擇；以下是選 a 時的技術細節，寫進新 ADR 0034）

- **#36 格式**
  - 單一檔 `fmp-backup-<UTC 時間>.db`：以 `VACUUM INTO` 複製到暫存檔，在副本上清空排除的表，再交給 `FileDialogs.saveFile`（Android 走 `file_picker` 的系統建立文件對話框，M3 已用）。
  - 版本：資料庫自己的 `user_version` 就是 schema 版本，不另加 manifest。比目前新就拒絕（「這份備份來自較新版的 FMP」）；比目前舊就在開啟時照常 migration（ADR 0010 §決定 3）。
  - 與 M5 無關：舊 JSON 備份的轉換由 `legacy_import` 做（ADR 0010 §決定 4）。
  - 慣例：NewPipe 的「匯出資料庫」（zip 內是資料庫檔與設定，匯入取代並重啟）、AntennaPod 的「匯出／匯入資料庫」；FMP 的設定本來就在資料庫裡，所以不需要 zip。
- **#37 還原路徑**
  - 沿用 M3 的 `DataReset.restoreAndRestart`：還原前自動備份目前的資料庫（`DatabaseBackups.create`），換檔，重啟。
  - 還原前的確認框列出備份裡的插件（名稱、網域），沿用 ADR 0030 安裝確認的警告文字：還原不經過安裝確認，這一步代替它。
  - dev flavor 可以還原 prod 的備份（ADR 0015 §決定 8 `:75` 要這條路）；反方向不擋。
  - 登入的處理依丙3 的子選項。

#### 其他

- **#39 目錄與分層**
  - `lib/library/`（歌單 service、匯入、刷新器、`playlist-refresh` 工作、遠端操作）、`lib/charts/`（排行快取、`charts:<pluginId>` 工作）、`lib/core/matching/`（評分核心與字表）、備份放 `lib/app/`（與 `data_reset.dart` 同處）。
  - UI：`lib/ui/library/`（音樂庫、詳情、匯入、預覽、管理歌單）、`lib/ui/home/`（首頁與探索）。
  - lint `fmp_layer_imports`：`library/`、`charts/` 照 `radio/` 的規則加進 `forbiddenLayerImports`（`core/`、`domain/`、`data/`、`scheduler/` 不 import 它們，它們不 import `ui/`）；`externalPackageOwners` 加 `unorm_dart`、`string_similarity` → `core/matching/`。新規則在 `packages/fmp_lints/test/rules/layer_imports_test.dart` 做雙向變異，同步 `app/AGENTS.md` 規則表與 `.trellis/spec/app/lints/index.md`。
  - 照 `lib/radio/` 的做法，功能目錄放在頂層，不新設 `services/`。
- **#40 M5 預留**
  - 建議 design 寫一張「舊欄位 → 新欄位」對照（`Playlist` 全部欄位、`Track.isAvailable`／`originalSongId`／`originalSource`、`Settings` 的排行三欄、舊備份的 `trackKeys`），M4 不寫轉換程式。
  - 理由：每張新表在建表 PR 就確認舊資料放得進去，避免 M5 才發現少欄位。ADR 0026 §決定 2 的「同時補上舊資料匯入（M5 起）」指 M5 以後的里程碑；M4 的表由 M5 一次匯入。
- **#41 重播用的測試插件**：每個契約 PR 同時擴充 `fmp-test`（`app/test/fixtures/plugins/test_plugin/`），讓實機的重播能走完匯入、刷新、遠端編輯、排行（M3 每個能力 PR 的做法；ADR 0027）。
- **#2 的技術部分**（範圍在丙1）
  - id 用 `spotify`、`qqmusic`：與舊版 `originalSource` 字串相同（`playlist_import_provider.dart:97-107`），M5 對照不用轉換；M7 的 QQ 歌詞源宣告在同一個 `qqmusic` 插件（ADR 0014 §決定 4：能力屬於插件），也對得上舊的 `lyricsSourcePriority` 值。在各自的插件 PR 加進 `officialPluginIds`。
  - 兩個插件只宣告 `importPlaylist`，認證 `never`（ADR 0012 §決定 7）。QQ 的 `sign` 只要 MD5 與 base64，宿主 `crypto.md5` 已有（`fmp-plugin.d.ts:398`），不必擴充宿主 API。
  - 首次啟動引導照 ADR 0030 §決定 12 不改：官方插件預設全勾，Spotify、QQ 也裝上，E5 開箱可用。

### 丙、擁有者決定（8 條，併成 4 題；清單見最後）

#2、#3、#26、#27、#28、#29、#35、#38，另加 digest 沒有列、但 ADR 0027 需要擁有者答的「真實帳號與遠端寫入的實測」。

## 3. M4 要不要拆

見丙1。建議拆：

- **M4a「音樂庫與平台歌單」**（PR 1–15）。做完能做：建本機歌單、多選；從網址或帳號頁匯入 B 站、YouTube、網易歌單並自動刷新；加入或移除遠端歌單；Mix 歌單；新的導覽與首頁（最近播放、我的歌單、電台）；從帳號匯入電台。驗收：兩平台端到端＋ADR 0017、0019、0028／0032、0033 的測試。
- **M4b「外部匯入、排行與備份」**（PR 16–22）。做完能做：匯入 Spotify、QQ 歌單並在預覽頁改選；首頁排行、探索頁、排行設定；備份與還原。驗收：兩平台端到端＋ADR 0016、0017、0019 §決定 6、0034 的測試。
- M5 依賴 M4b（不變）：舊資料匯入是首次啟動的一次性動作（ADR 0010 §決定 4），M4b 的表（`track_origins`、`match_results`、`chart_settings`）要在它之前就存在，否則舊的 `originalSongId` 與排行設定就沒有地方放。

## 4. PR 順序草案（假設丙1 選拆分、丙2 選 a、丙3 選 a）

標 ★ 的 PR 動到 `1morr/fmp-plugins`：FMP 先合併宿主契約，`fmp-plugins` 再實作並改 `FMP_REF`（甲 #9）。加表或改 schema 的 PR（1、8、19、21，以及 20 的 `network_settings` 欄位）會互相衝突 `schemaVersion`，要依序合併。

| PR | 內容 | U | 依賴 | 要先接受的 ADR |
|---|---|---|---|---|
| 0 | 規劃檔、ADR 0032–0034、各 ADR 一行更正、`milestones.md`（範圍、拆分、驗收） | U0 | 核准 | — |
| **M4a** | | | | |
| 1 | 資料層：`playlists`、`playlist_entries`（v15）、repository、孤兒查詢加歌單項目、`track_key` 索引、外鍵與孤兒測試 | U1 | 0 | 0033 |
| 2 | 導覽重排、音樂庫頁、本機歌單建立／編輯／刪除／拖曳排序；「歷史」搬進音樂庫 | U9、U2 | 1 | 0033 |
| 3 | 歌單詳情（全部、隨機加入、10,000 上限、分 P 分組、重排、刪曲目）＋曲目選單「加入歌單…」 | U2 | 2 | 0033 |
| 4 | 首頁：最近播放、我的歌單、電台區塊（排行區塊在 PR 21 接上） | U9、U14 | 2 | 0033 |
| 5 | 多選模式（歌單詳情、搜尋、歷史；探索在 PR 21 接上） | U2 | 3 | 0033 |
| 6 | 宿主契約 `importPlaylist`（`playlistFromUrl`、分頁、`TrackSummary` 分 P 兩欄）＋`fmp-test` | U3 | 0 | 0032 |
| 7 ★ | YouTube `importPlaylist`（含 Mix 網址與 `mix:` 簡寫） | U4 | 6 | 0032 |
| 8 | 匯入與刷新引擎、`playlist_remote`（v16）、「匯入」對話框、手動刷新、狀態列 | U5 | 3、6（實機用 7） | 0019 更正、0033 |
| 9 ★ | B 站（收藏夾、多 P 展開）、網易 `importPlaylist` | U4 | 6 | 0032 |
| 10 | `playlist-refresh` 工作、每張歌單的間隔 | U6 | 8 | 0017、0033 |
| 11 | Mix 歌單（`kind = mix`、種子、歌單卡「Mix 播放」） | U13 | 8、7 | 0028／0031 更正 |
| 12 | 帶憑證錄製：`recordCase` 對 `requiresLogin` 案例換值、隔離環境帶憑證；`checks.json` 的 `mutates` | （#10） | 0 | 0015 更正、0032 |
| 13 ★ | 宿主契約 `libraryRead`＋三個插件＋帳號頁「歌單」 | U7 | 8、12 | 0032 |
| 14 ★ | 宿主契約 `libraryWrite`＋三個插件＋加入／移除遠端、在遠端新增、寫後刷新 | U8 | 13 | 0032 |
| 15 ★ | `libraryLiveRooms`（B 站）＋「從帳號匯入電台」 | U14 | 13 | 0032 |
| — | M4a 驗收 | | 1–15 | |
| **M4b** | | | | |
| 16 | 匹配核心：`core/matching/`、`unorm_dart`、`string_similarity`、OpenCC 字表產生器與資料、測試語料 | U10 | 0（可與 M4a 平行） | 0019 更正 |
| 17 ★ | Spotify 插件（`spotify`）；FMP 加 `officialPluginIds` | U12 | 6 | 0032 |
| 18 ★ | QQ 插件（`qqmusic`）；同上 | U12 | 6 | 0032 |
| 19 | 匯入預覽頁、逐首匹配（進度、取消）、`track_origins`、`match_results`（v17）、匹配目標音源設定（`source_settings` 兩欄） | U12 | 8、16、17 | 0019 更正、0033 |
| 20 ★ | 宿主契約 `charts`＋三個插件＋排行快取（`cache.db`）＋`charts:<pluginId>` 工作＋排行間隔 | U11、U6 | 0 | 0032 |
| 21 | 首頁排行區塊、探索頁、首頁排行設定（`chart_settings`，停用即不抓、刪快取）；探索接上多選 | U11 | 20、4、5 | 0033 |
| 22 | 備份與還原、設定頁「備份與還原」區（取代 Debug 頁之外的唯一入口） | U15 | 19、21（所有加表的 PR） | 0034 |
| — | M4b 驗收（U16 的文件同步分散在各 PR，照全域規則同輪更新） | | 16–22 | |

- 曳光彈：PR 1 → 2 → 3 先讓一張本機歌單端到端可用；接著 6 → 7 → 8 讓「貼一個 YouTube 歌單網址 → 匯入 → 刷新」可用。之後每一步都只加能力。
- 可以平行：0 之後 1、6、12、16 同時開；M4a 期間 16、20 可先做（不碰歌單 UI）。
- 最長的鏈：0 → 1 → 2 → 3 → 8 → 13 → 14。
- 先做高風險的：§6 的實測放在 PR 7、9、17、18 開頭；PR 8 的刷新引擎（重複影片、代際）是邏輯最重的一個。
- PR 5、21 若太大可再拆（多選本身、探索頁本身）。

## 5. 需要的新 ADR

| ADR | 決定什麼 | 依賴的丙類 |
|---|---|---|
| 0032 宿主 API v1 的 M4 擴充 | `importPlaylist`（`playlistFromUrl`、分頁與完整性、`TrackSummary.partIndex`／`parentTitle`）、`libraryRead`（`libraryPlaylists`、選填 `libraryLiveRooms`）、`libraryWrite`（建立、加入、移除，逐項結果，必須同時宣告 `libraryRead`）、`charts`（`chartList`、`chart`）；`checks.json` 的 `mutates`；私人歌單以 `required` 重送；Spotify、QQ 的 id | 丙4（`mutates` 與實測規則） |
| 0033 音樂庫、首頁與導覽的資料與入口 | 歌單三張表與 `chart_settings`、`source_settings` 新欄位、`network_settings` 排行間隔；刷新的交易與代際；排程工作的切分；導覽、首頁區塊、探索、音樂庫、詳情、多選、匯入與預覽、管理歌單、從帳號匯入電台、狀態列 | 丙1、丙2 |
| 0034 備份檔與還原 | 備份＝資料庫副本、排除哪些表、版本規則、還原＝取代並重啟、插件的確認、登入的處理、入口 | 丙3 |

另外是一行更正或補充：0010（影響範圍的備份格式）、0012 §決定 2（矛盾 11）、0015 §決定 4（`mutates`）、0019（§決定 1 間隔、§決定 2 已失效放項目、§決定 5 前 5 名、§決定 6 與 §後果的字表）、0025 §決定 9（E16 指到 0034）、0026 §決定 3（若拆分）、0028 §決定 4 與 0031 §決定 11（Mix 存種子）、0031 §決定 3（導覽）。`track_origins`、`match_results` 的欄位寫在 0033，不另立匹配的 ADR（ADR 0019 §決定 6 已有框架，細節是常數與測試）。

## 6. 對規劃者的提醒

**先做的實測**（真實連線最少量；寫進各 PR 的 prd，不在規劃階段打 API）：

1. **Spotify embed 頁還能不能匿名抓**（PR 17 開頭）：`open.spotify.com/embed/playlist/<id>` 的 `__NEXT_DATA__` 結構是否還在；超過 100 首的歌單是否完整（未實測，待查）。抓不到就要換方式，可能牽動丙1 的範圍。
2. **QQ 的 `musics.fcg` 自簽 `sign` 還能不能匿名用**（PR 18 開頭）：舊版 `qq_music_sign.dart` 的演算法、`pageSize = 1000`。
3. **三平台公開歌單的匿名讀取**（PR 7、9 開頭）：B 站公開收藏夾是否要 WBI 簽名或容易觸發風控；YouTube 公開清單的續取與「被隱藏的無法播放影片」造成的總數差；網易歌單詳情只給前幾首完整資料、其餘要以 id 分批補（舊版做法待讀原始碼確認）。
4. **寫入端點**（PR 14，需要擁有者在場登入）：只在丙4 指定的測試歌單上加入、移除一首，各平台一次。
5. **若擁有者選完整 OpenCC**：`flutter_opencc_plus` 先在 Android 模擬器與 Windows 各建一次、跑一次轉換，再決定。

**最大的風險**：

1. **範圍**：22 個 PR，比 M3 的 21 個還多，而且 7 個 PR 動到 `fmp-plugins`。不拆的話，驗收要等到最後；這是丙1 建議拆的主因。
2. **刷新引擎的正確性**：重複影片、代際、中途被殺、部分完成五種情況交錯；PR 8 要先寫測試（ADR 0019 `:85,87` 全部案例），再寫實作。
3. **導覽重排會動到既有測試**：ADR 0031 §如何確認的「四個導覽項（三種視窗寬度）」widget 測試、快捷鍵與焦點三區（ADR 0024），PR 2 要一起改。
4. **大歌單匹配的等待時間**：1000 首 × 3 個目標音源＝3000 次搜尋，以 B 站的限流估計可能十幾分鐘（未量測，待查）。預覽頁要能顯示進度、取消，並在開始前顯示首數。
5. **健康檢查的寫入副作用**：`mutates` 沒做好前，不要在 `checks.json` 放 `libraryWrite` 的案例（PR 12 必須在 PR 14 之前）。
6. **備份帶著插件腳本**：還原不經過安裝確認；PR 22 的確認框是唯一的一道。
7. **抓頁面的插件**（Spotify、QQ）隨改版失效：ADR 0012 §決定 7 交給健康檢查；M4b 驗收時兩個都要實際匯入一次。
8. **schema 版本衝突**：平行開發的加表 PR 要排隊合併，每個都要新快照與 migration 測試（`.trellis/spec/app/data/index.md`）。

**查證時發現、規劃時要記得的**：

- 新 `TrackSummary` 沒有 `partIndex`／`parentTitle`（`fmp-plugin.d.ts:132-144`），PR 6 要加，否則 B 站收藏夾匯入會碰到 M3 審查記下的分 P 欄位被清掉。
- `installed_plugins` 沒有排序欄位；「同分依使用者排序」需要新的排序來源（#24 用 `source_settings.match_rank`）。
- 舊版的 `notifyOnUpdate` 沒有讀者，可以安心丟掉（矛盾 4）。
- `flutter_js` 的 YouTube 插件已約 800 KB；`importPlaylist`、`libraryWrite` 會再加大，PR 7 量一次載入時間。

## 丙類問題清單（依「影響最大、最先擋住規劃」排序）

1. **M4 的範圍與拆分**（#2、矛盾 2、3、8；驗收項的寫法見乙 #1）
   - 要決定：拆不拆；`milestones.md` § M4 範圍要不要補上頁面對照表與 ADR 0031 的七項（帳號頁管理歌單、從帳號匯入電台、首頁與探索、導覽重排、首頁排行設定、匯入預覽、曲目選單加入歌單）、多選、Spotify／QQ 插件；備份留不留在 M4；M5 依賴哪一半。
   - 為什麼重要：決定 PR 0 的文件改動、驗收的時間點、`implement.md` 的結構；不定就無法排 PR。
   - 選項：
     - a 不拆：22 個 PR 一次驗收。
     - b 拆成 M4a「音樂庫與平台歌單」（PR 1–15）與 M4b「外部匯入、排行與備份」（PR 16–22），上述項目全部留在 M4，M5 依賴 M4b。
     - c 拆三份：M4a 音樂庫與平台歌單、M4b 排行與首頁、M4c 匹配（Spotify／QQ）與備份。
     - d 不拆，但把首頁排行、探索與備份移出 M4（另排到 M9 之前）。
   - 建議 b：M4a 做完就能像舊版一樣管理與同步歌單，是最常用的一半；兩半各約 10 個 PR，與 M3 的先例相同。M5 依賴 M4b，因為舊資料匯入只跑一次，需要所有 M4 的表都在。c 多一次驗收而沒有多換到什麼；d 會讓「做完」的 Spotify／QQ 也跟著掉出去或變成孤立的一項。

2. **導覽、首頁與探索**（#26–#29、矛盾 10）
   - 要決定：手機底部導覽的項目與順序、「歷史」放哪、首頁有哪些區塊、探索在哪裡、首頁排行設定放哪、要不要保留「至少留一個榜單」。
   - 為什麼重要：PR 2 是 M4a 的第二個 PR，導覽一動就要改既有的 widget 測試；首頁區塊決定 PR 4 的內容。
   - 選項：
     - a **首頁｜搜尋｜音樂庫｜電台｜設定**（5 項，各寬度同一組）；「歷史」變成音樂庫頂端的入口，首頁的「最近播放」附「查看全部」；探索是首頁排行區塊的子頁（舊版）。
     - b 首頁｜搜尋｜音樂庫｜歷史｜設定；電台移進音樂庫或只留首頁的電台區塊。
     - c 六項全放（超出 Material 導覽列的 3–5 項）。
     - d 設定移到首頁右上角（Spotify、YouTube Music 的做法），導覽是首頁｜搜尋｜音樂庫｜歷史｜電台。
   - 首頁區塊（各選項共用的建議）：排行（M4b 才接上，每榜單前 5 首）、我的歌單、電台、最近播放（後兩者至多 20 項，舊版常數）；不放舊版的「正在播放」「佇列預覽」，新版已有播放列、右側面板與佇列分頁。
   - 首頁排行設定放設定頁新的「音樂庫」區（與匹配目標音源同一處），以榜單為單位排序與啟用；不保留「至少留一個」：全部停用就是首頁沒有排行區塊，比擋住使用者簡單。
   - 建議 a：Material 3 文件裡音樂 App 導覽的示例就是 Home、Browse、Radio、Library；YouTube Music 把歷史放在音樂庫裡；電台是擁有者在 M3 選的導覽項，保留它；設定照現況留在導覽裡，動得最少。代價是「歷史」從 M2 起的導覽項降一層，這改動了 M2 的擁有者決定，所以要你確認。

3. **備份的內容與格式**（#3、#35、#38、矛盾 1）
   - 要決定：備份檔是什麼、含哪些資料、還原是取代還是合併、登入怎麼處理、入口在哪。
   - 為什麼重要：這是對外的持久化格式（換裝置、dev 帶 prod 資料都靠它），定了就難改；也決定 PR 22 的大小。
   - 選項：
     - a **資料庫副本**（`fmp-backup-<時間>.db`，`VACUUM INTO`），排除 `layout_state`（M2 已定不收）、`accounts`、`plugin_storage`（匿名 cookie 這類裝置身分）、`scheduler_runs`；含設定、歌單、曲目、歷史、電台、匹配結果、已安裝的插件（含腳本）；還原＝取代並重啟，還原前自動備份；設定頁新增「備份與還原」區（匯出、匯入）。
     - b 版本化 JSON（舊版的格式）＋合併匯入、可勾類別：最像舊版，但每張表都要寫序列化與合併規則，並跟著每一版 schema 改。
     - c a 的檔案＋合併匯入（從備份讀出歌單合併進目前的資料）：介於兩者之間，合併規則（同名、同遠端 id、重複曲目）要另外定。
   - 子選項（選 a 或 c 時）：還原後**保留目前的登入**（把目前的帳號列帶進還原的資料庫，憑證不動；舊版匯入也不碰帳號）／**登出全部**（M3 現有的還原路徑，最省事）。
   - 一律不含：憑證、Cookie、AI key（ADR 0012、0021；在 secure storage，不在資料庫）。下載紀錄（M6）會在資料庫裡跟著走，但檔案路徑只對原本那台有效，換裝置後的處理由 M6 的設計定（標為檔案遺失）。不做自動定期備份（舊版沒有；M3 已有重設前的自動備份）。
   - 建議 a＋保留登入：NewPipe、AntennaPod 的「匯出／匯入資料庫」就是這種；FMP 的設定本來就在資料庫裡，副本就是完整的備份，M3 已實作大半。代價是沒有合併：匯入別台的備份會取代這台的歌單（確認框寫清楚，並先自動備份）。插件跟著還原，播放才不會一片「音源未安裝」；確認框列出插件與網域代替安裝確認。

4. **真實帳號與遠端寫入的實測**（ADR 0027；#8、#41 的延伸）
   - 要決定：匯入私人歌單、`libraryRead`、`libraryWrite` 用哪些帳號實測，遠端寫入寫在哪張歌單上，健康檢查能不能寫入。
   - 為什麼重要：`libraryWrite` 的真實測試會改你在平台上的資料；不先定就無法寫 PR 13、14 的驗收步驟。
   - 選項：
     - a 你在三個平台各建一張私人的「FMP 測試」歌單；寫入的實測只對它加入、移除一首，各平台一次；帳號沿用 M3（YouTube 用測試帳號，B 站、網易用你指定的帳號），登入由你自己掃 QR 或輸入密碼；寫入的檢查案例標 `mutates`，健康檢查與冒煙測試永遠不跑它。
     - b 直接用主帳號的現有歌單。
     - c 不做真實寫入實測，只靠手寫 fixture 重播：省事，但端點改版時看不到。
     - d B 站、網易也另開測試帳號。
   - 建議 a：寫入只碰一張專用的歌單，出錯也不傷到真實收藏；私人歌單的匯入與 `libraryRead` 用同一個帳號實測一次即可。Spotify、QQ 匿名，各實際匯入一次公開歌單。

## 需要擁有者確認的技術決定

這些改到 ADR 的文字或舊版行為，或是本草案才提出的產品行為（標「新」）；核准 design 時請逐條確認。

1. **繁簡統一改用 OpenCC 字表產生的純 Dart 對照**，不用 `opencc` 套件（stable 1.1.0 依賴 hooks 穩定前的實驗 API、沒有 Android 預編譯庫）；ADR 0019 §決定 6 與 §後果更正，`milestones.md` 的「`opencc` native assets 建置」驗收換成繁簡測試。建議：照做（§2 #22）；要完整 OpenCC 時改 `flutter_opencc_plus` 並先實測建置。
2. **Mix 歌單存「插件 id＋種子曲目」**，不存 `mixId`；ADR 0028 §決定 4、ADR 0031 §決定 11 更正。建議：照做（`cursor` 必填，`mixId` 開不了新的 Mix；舊版也存種子）。
3. **`checks.json` 的案例可標 `mutates: true`**：只在契約重播跑，健康檢查、冒煙、App 內錄製略過；ADR 0015 §決定 4「一份四用」的例外。建議：照做（否則健康檢查會改你的遠端歌單）。
4. **私人歌單的刷新**：以 `userPreference` 讀，被拒且這次沒帶憑證、使用者已登入時，以 `required` 重送一次；ADR 0012 §決定 2 補一行（矛盾 11）。效果：關掉「以登入身分瀏覽與播放」仍能刷新自己的私人收藏夾，公開收藏夾不登入也能匯入。建議：照做。
5. **`playlist_remote` 加刷新間隔（空＝不啟用、新匯入 24 小時）；不保留舊 `notifyOnUpdate`**（舊版只存不讀）；ADR 0019 §決定 1 補一行。建議：照做。
6. **匯入不再自動改名**（舊版 `_generateUniqueName`）：名稱不唯一，重新匯入靠遠端 id。建議：照做。
7. **匹配的「前 5 名」是所有目標音源合併評分後的前 5**（舊版每音源各 5 個）；ADR 0019 §決定 5 補一行。建議：照做（與 ADR 0014 §決定 9「比較取最高分」一致）。
8. **（新）匹配目標音源預設含網易**（舊版只有 B 站、YouTube），可在設定頁拖曳排序與取消勾選。建議：照做（網易現在能播；不想要可以取消）。
9. **（新）「音樂庫與同步」設定組在 M4 不建表**：排行間隔放「網路」組，匹配目標放每音源設定表，首頁排行放 `chart_settings`，每張歌單的間隔放 `playlist_remote`。建議：照做（沒有欄位的空表沒有讀者）。
10. **（新）「加入遠端歌單」對話框不預先勾出已含該曲目的歌單**（舊版 B 站有），重複的由插件略過並回報「已存在」。建議：照做；要的話之後加選填匯出。
11. **「已失效」記在歌單項目**（該遠端歌單上次刷新的觀察），不記在曲目；ADR 0019 §決定 2「曲目……可用狀態」補一行。建議：照做（同一首在本機歌單不受影響；符合 ADR 0010「只存事實」）。
12. **未匹配的外部歌曲只存在 `match_results` 並在預覽頁標示**，不進本地歌單；同一首再匯入時沿用先前的匹配與改選。建議：照做（歌單項目一定要有曲目；這是 ADR 0014 §決定 9「結果持久化、匹配失敗保留並標示」的落地）。
13. **（新）「從帳號匯入電台」用中性字樣**，不寫「粉絲勳章」，只在插件提供時出現。建議：照做（宿主沒有音源分支）。
14. **（新）歌單卡保留舊版的「隨機加入」**（ADR 0018 沒有寫）。建議：照做（舊版行為、成本很小）。
