# 同步演算法與匹配的技術事實

- 查證日期：2026-09-28
- 查證方式：
  - `mcp__context7__query-docs`（library `/websites/drift_simonbinder_eu`，即 <https://drift.simonbinder.eu>）查 drift 官方文件
  - `mcp__tavily-lb__tavily-search`（basic）查 SQLite、排序演算法、各平台 id 穩定性、Unicode 正規化
  - `curl` 直接讀 `https://pub.dev/api/packages/<name>` 與 `/score`（版本、發佈日期、pub points、likes、下載數、授權 tag），以及 GitHub REST API 取授權
  - `curl` 讀 `https://raw.githubusercontent.com/simolus3/drift/develop/drift/lib/src/sqlite3/database.dart` 確認 drift 實際發出的 transaction SQL
  - 本地唯讀：`lib/services/import/playlist_import_service.dart`、`lib/services/lyrics/lyrics_auto_match_service.dart`、`lib/core/constants/app_constants.dart`
- 標記約定：**推測** = 由已知事實推導但無直接來源；**查不到** = 本次查證範圍內找不到可信來源。所有版本號與日期逐字取自 pub.dev API，非憑記憶。

---

## A. 以遠端為權威的單向同步

### A1 差異計算

**四類差異的定義與算法選擇**

單向（遠端權威）同步與雙向同步的差異計算難度不同，這點決定了要不要引入 diff 演算法。

| 差異類別 | 偵測方式 | 需要 diff 演算法嗎 |
|---|---|---|
| 新增 | 遠端 key 集合 − 本地 key 集合 | 不需要（集合差） |
| 移除 | 本地 key 集合 − 遠端 key 集合 | 不需要（集合差） |
| 移動（順序） | 兩邊同一個 key 的 order 值不同 | 不需要（逐列比對欄位） |
| 元資料（標題/歌手/時長/封面） | 兩邊同一個 key 的欄位值不同 | 不需要（逐欄比對） |

成熟做法分兩派：

1. **遠端提供序號時直接覆寫**。YouTube Data API 的 playlist item 就帶 `snippet.position`（unsigned integer，0 起算），且 `PlaylistItems.update` 可指定 `snippet.position`——順序是伺服器端的一等公民欄位，客戶端不需要自己算「誰被移走了」（來源：<https://developers.google.com/youtube/v3/docs/playlistItems>；GeeksforGeeks 的 `playlist_item_update_position` 範例 <https://www.geeksforgeeks.org/python/youtube-data-api-playlist-set-4>）。此時差異計算退化為「把遠端 position 寫進本地 order 欄位，只 UPDATE 值不同的列」。
2. **遠端只給一組有序陣列、自己算差異**時才用 LCS / Myers diff / 最長遞增子序列（LIS）求「最少移動次數」。這在雙向同步或要產生 patch 時才有價值，代價是 O(n·d) 或 O(n log n) 的時間與額外程式碼。

**關鍵事實：單向權威下不需要 LCS。** 因為本地不允許使用者改順序（決策已定：使用者不能在本地增刪匯入歌單的曲目），所以不存在「兩邊各自編輯」需要三方合併的情境。差異就是「遠端狀態 → 本地狀態」的覆寫，比較集合與欄位即可。

**實務上仍要注意的一點**：YouTube 允許同一支影片在同一張歌單出現多次（`ytmusicapi` 的 `add_playlist_items` 有 `duplicates` 參數說明這件事，來源：<https://ytmusicapi.readthedocs.io/en/0.22.0/reference.html>）。因此「以曲目 key 為唯一鍵」的集合運算會把重複項摺疊掉。若要保持「同一首歌在歌單裡出現兩次」，關聯表不能只用 `UNIQUE(playlist_id, track_key)`，而要允許 (playlist_id, track_key, position) 有多列——位置本身才是那一筆的身分。（**推測**：這是 ytmusicapi 文件推導出的結論，未在 YouTube 官方文件看到明文規定重複項的唯一性語意。）

### A2 穩定排序

**問題**：遠端沒給穩定順序時（或遠端只給「新增到最後」的語意時），關聯表的排序欄位怎麼維護。

三種成熟做法：

1. **整數連續（1,2,3…）＋整表重排**。任何一次插入/移動都要 UPDATE 後續所有列。5000 列在一次 transaction 內就是 5000 次 UPDATE——SQLite 實務上完全可行（單一 transaction 內的 UPDATE 不做 fsync，只在 COMMIT 時 flush 一次），但每次刷新都寫滿全表會讓 WAL 膨脹、也讓「這次刷新動了哪幾首」難以從資料庫看出。
2. **稀疏整數排序（sparse ordering）**：間隔 1000（1000, 2000, 3000…），插入時取中間值（`Pnew = (Pi + Pi+1) / 2`），只有新元素要寫；間隔用盡才重排一次。來源：<https://www.poyters.pl/blog/sparse-ordering-maintaining-ordered-lists-without-renumbering>。該文比較後明確偏好稀疏整數而非浮點 fractional indexing：「For most applications, sparse integer ordering is preferable: it is predictable, stable, and easier to monitor for rebalancing.」
3. **字典序排序（LexoRank / fractional indexing）**：用字串 key，`generateKeyBetween(a, b)` 可在任意兩 key 之間產生新 key，永不重排。Jira 的 LexoRank 是代表實作（來源：<https://yasoob.me/posts/how-to-efficiently-reorder-or-rerank-items-in-database>）；純 fractional indexing 的說明見 <https://www.steveruiz.me/posts/reordering-fractional-indices> 與 <https://sonim1.com/en/blog/fractional-indexing>。

**drift / SQLite 上實際可行的做法**

- 稀疏整數用 `INTEGER` 欄位配 `ORDER BY position, id`（第二鍵當 tie-breaker，避免兩列同值時順序不確定）。整數排序在 SQLite 上走 B-tree，無額外成本。
- LexoRank 在 SQLite 就是 `TEXT` 欄位配預設 `BINARY` collation；可行但要自己實作 base-62 進位與 bucket 正規化，是三者中實作成本最高的。
- 一個對 FMP 更省事的變體：**直接存遠端 position**（例如 YouTube 的 `snippet.position`），不自己做稀疏間隔。遠端是權威，遠端怎麼排本地就怎麼存；只有遠端沒給 position 的時候（**推測**：B 站收藏夾 API 只回有序陣列、不回 position 欄位）才退化成「陣列索引寫進 position 欄位」。此時每次刷新都是整表 position 覆寫，但因為單向且整批在同一個 transaction 裡，寫入量與第 1 種做法相同，不需要稀疏間隔的複雜度。
- drift 宣告唯一鍵的方式是覆寫表格的 `uniqueKeys`（`List<Set<Column<Object>>>`），複合外鍵走 `customConstraints` 覆寫（來源：<https://drift.simonbinder.eu/dart_api/tables>、<https://drift.simonbinder.eu/dart_api/writes>）。

### A3 大歌單效能與分頁

**drift 的 bulk insert 官方做法：batch**

```dart
await batch((batch) {
  // functions in a batch don't have to be awaited - just
  // await the whole batch afterwards.
  batch.insertAll(todos, [ /* companions */ ]);
});
```

來源：<https://drift.simonbinder.eu/dart_api/writes>。要點是「batch 內的呼叫不必逐一 await，整個 batch 一起 await」，batch 本身包在單一 transaction 內。

Upsert 用 `insertOnConflictUpdate(...)`，或對非主鍵的唯一鍵指定衝突目標：

```dart
return into(matches).insert(
  data,
  onConflict: DoUpdate((old) => data, target: [matches.teamA, matches.teamB]),
);
```

（同上來源；`target` 需要該欄位組已在 `uniqueKeys` 宣告。）

**常見瓶頸（依重要性排序）**

1. **逐列 await 各自成一個 transaction**。沒有包 transaction 時，每一條 INSERT 都是一次自己的隱式 commit，也就是一次 fsync。5000 首會變成 5000 次 fsync，這是行動裝置上真正的殺手。解法只有一個：把整批（或分批）放進 `batch()` 或顯式 `transaction()`。
2. **`InsertMode.insertOrReplace` 的語意陷阱**：SQLite 的 `INSERT OR REPLACE` 在衝突時是 **DELETE 既有列再 INSERT**，不是 UPDATE。對有外鍵 `ON DELETE CASCADE` 的關聯表，這會連動刪掉子列；對被其他表外鍵參照的曲目列，可能觸發 cascade 或 FK 違反。要「合併」而不是「換掉」時應該用 `DoUpdate`（真 UPDATE），只有在「這列的存在與否由遠端決定」時才適合 replace。（**推測**：由 SQLite 的 `INSERT OR REPLACE` 語意推導；drift 沒有針對此語意的專文。）
3. **事務時間過長造成寫鎖持有過久**。見 A4：drift 的 sqlite3 實作在 transaction 開始就取寫鎖（`BEGIN IMMEDIATE`）。一個 5000 列的大 transaction 會在這段時間內擋住所有其他寫入。WAL 模式下讀取不受影響（見 A4）。
4. **從遠端抓取本身的 API 分頁**，與本地寫入是兩件事，不要綁在一起。YouTube `playlistItems.list` 的 `maxResults` 上限是 50（`pageToken`/`nextPageToken` 分頁），所以 5000 首至少 100 次請求。

**建議的形狀（給 FMP）**：遠端抓取與本地寫入解耦成「抓一頁 → 寫一頁」的流水線，每頁一個 transaction；整張歌單的最終一致狀態由 A4 的 refresh generation 標記保證。這樣記憶體不會一次扛 5000 筆，進度可持久化、可中斷續跑，寫鎖也不會被單一巨大 transaction 長時間佔住。

### A4 刷新失敗的原子性（drift / SQLite）

**drift `transaction()` 的官方語意（版本：drift 2.35.0，2026-09-09 發佈，來源 <https://pub.dev/api/packages/drift>）**

- 巢狀 transaction 自 **drift 2.0** 起支援。內層 transaction 的寫入在成功完成前只對外層可見（等於一次原子更新）。
- 內層拋出例外時，內層被回滾，外層回到「內層開始前」的狀態。外層若 catch 掉例外，可以繼續；不 catch 則例外往上冒、連外層一起回滾。
- 支援巢狀的實作：`NativeDatabase`、`WasmDatabase`、`WebDatabase`、`SqfliteDatabase`，以及跑在 isolate / web worker 上的遠端連線（只要底層支援）。
- **所有查詢都必須 await**：transaction 在傳入的函式回傳時結束；漏 await 會讓查詢用到已關閉的 transaction，drift 有檢查並會拋例外。**timer 之類的非同步排程不能在 transaction 內安排**，因為它們會在 transaction 結束後才執行。
- 來源：<https://drift.simonbinder.eu/dart_api/transactions>（官方文件，本次逐段引用前述四點）

**drift 實際發出的 SQL：`BEGIN IMMEDIATE`（原始碼確認）**

`drift/lib/src/sqlite3/database.dart`（develop 分支）中，`Sqlite3Delegate.transactionDelegate` 回傳：

```dart
return const NoTransactionDelegate(
  // We don't currently have readonly transactions. So we might as well
  // acquire the write lock at the earliest opportunity to avoid contention
  // issues on the first statement of the transaction (if multiple database
  // connections are opened to the same underlying database).
  start: 'BEGIN IMMEDIATE',
);
```

來源：<https://raw.githubusercontent.com/simolus3/drift/develop/drift/lib/src/sqlite3/database.dart>（第 66–74 行）。也就是說：**在 native（Android / Windows）上，drift 的 `transaction()` 一進去就取寫鎖**，不是等到第一條寫入才升級。這對「一次刷新要嘛全成功要嘛全不動」是好消息——不會有「讀完才發現要升級鎖、然後 SQLITE_BUSY」的中途失敗。官方文件沒有明文寫這件事，**查不到**文件層級的說明，只能從原始碼確認。

**SQLite 層面的意義**

- `BEGIN`（＝`BEGIN DEFERRED`）一開始只是讀交易，第一條讀取才真正開始，之後若要寫入則在升級時取鎖；若此時別的連線已持有寫鎖，SQLite **立刻**回 `SQLITE_BUSY`，且**不遵守 `busy_timeout`**。來源：SQLite 官方 <https://www.sqlite.org/lang_transaction.html> 與官方論壇 <https://sqlite.org/forum/forumpost/04ed1d235b>；實測與解說另見 <https://tenthousandmeters.com/blog/sqlite-concurrent-writes-and-database-is-locked-errors>。
- `BEGIN IMMEDIATE` 立即開始寫交易；若已有其他寫交易，回 `SQLITE_BUSY`（此時可以走 `busy_timeout` 重試）。`BEGIN EXCLUSIVE` 在 **WAL 模式下與 IMMEDIATE 相同**，差異只在 rollback journal 模式。來源同上。
- **WAL 模式**的價值：單一寫者與多個讀者可以並行。drift 官方文件在多執行緒（isolate + read pool）情境明白寫道，開 WAL 是為了避免「database locked」，且「a single writer and multiple readers can operate on the database in parallel」：

  ```dart
  NativeDatabase.createInBackground(
    File('path/to/database.db'),
    setup: (database) {
      database.execute('pragma journal_mode = WAL;');
    },
    readPool: 4,
  );
  ```

  來源：<https://drift.simonbinder.eu/platforms/vm>。同一頁也說明 transaction 與 `exclusively` 區塊一定走寫 isolate。
- **外鍵強制**：SQLite 預設不強制外鍵，必須 `PRAGMA foreign_keys = ON`。drift 官方建議在 `beforeOpen` 開、在 migration 期間關（`PRAGMA foreign_keys = OFF`），並在 debug 用 `PRAGMA foreign_key_check` 驗證沒有孤兒列：

  ```dart
  beforeOpen: (details) async {
    await customStatement('PRAGMA foreign_keys = ON');
  },
  ```

  來源：<https://drift.simonbinder.eu/migrations>、<https://drift.simonbinder.eu/migrations/api>、<https://drift.simonbinder.eu/migrations/step_by_step>。

**對「一次刷新要嘛全成功要嘛全不動」的結論**

- 把整次刷新的寫入包在一個 `transaction()` 裡，就能拿到這個保證：drift 發 `BEGIN IMMEDIATE` → 取寫鎖 → 全部成功才 COMMIT，任何例外（含 await 到的網路錯誤）都回滾。這是**唯一**能達到「全有全無」的機制；`batch()` 與 `transaction()` 的差別在於 batch 只是一組語句，仍需要有外層 transaction 才能跨多個 batch 原子化。（**推測**：drift 文件未明說 batch 自帶 transaction，但 `transaction()` 的說明與 batch 的「一起 await」寫法都指向 batch 在單一 transaction 內執行；此點若要絕對確定，需看 drift 原始碼 `batch()` 實作。）
- 但整張 5000 首包一個 transaction 會長時間持有寫鎖（`BEGIN IMMEDIATE` 從頭到尾），代價是所有其他寫入被擋。折衷是 A3 的「分頁 transaction ＋ refresh generation」：每頁寫入時帶上本輪的 `refresh_generation` 標記，全部頁數寫完才把 generation 標記為 complete；查詢一律只讀「最新 completed generation」。這樣中途失敗的結果是「舊的完整版本還在」，而不是「半新半舊」。這是對 FMP 的建議（**推測**：業界的 staging/影子表模式在音樂 App 的公開文件裡查不到直接先例）。

---

## B. 遠端曲目身分

### B1 B 站（bvid + cid）

- **aid / bvid 是「稿件」層級的編號**，代表 UP 主上傳的那個作品，可互相轉換（社群工具普遍支援互轉）。來源：B 站社群專欄 <https://www.bilibili.com/read/cv6415114>（「通过BV号或者av获取稿件的P数」、以 aid 或 bvid 二選一呼叫 API）。
- **cid 是「分 P」層級的編號**，指定稿件內某一個具體的視頻檔案。一個稿件可能有多個 P，只給 bvid 伺服器不知道要播哪一個，所以取得播放位址必須 bvid + cid。來源：同上專欄；CSDN 教學 <https://bbs.csdn.net/weixin_32520601/article/details/100128689>（「aid 作为视频稿件的顶层标识，cid 用于区分同一稿件下的不同分P内容」）。
- **cid 的另一個身分**：cid 是「儲存該視頻彈幕資料的倉庫」編號，與 avid 和早期的 VID 綁定。來源：B 站專欄 <https://www.bilibili.com/opus/1097650249106718720>（「可以理解成一个个储存指定视频的弹幕数据的仓库，它与视频编号(av号)和VID绑定」）。
- **bvid 會不會變？** 官方沒有文件說明 bvid 的產生規則或是否可變，**查不到**。可從結構推測：bvid 是 avid 的可逆編碼（可互相轉換），因此只要 avid 不變 bvid 就不變（**推測**）。稿件被刪除後重新上傳會得到新的 aid/bvid（**推測**，未找到官方說明）。
- **影片被替換／重新上傳時會怎樣？** B 站是否允許 UP 主在保留 bvid 的前提下替換視頻源、替換後 cid 是否改變，**查不到**官方或半官方說法。
- **對 FMP 的意義**：`TrackKey = bilibili:bvid:cid` 是正確的粒度——它鎖定的是「那個具體的視頻」，稿件層級的變動（改標題、改封面、改 UP 名）不影響它。已存在的 cid 在分 P 被刪除後會永久消失（**推測**：cid 與檔案綁定，刪 P 等於刪檔案），此時本地參照必然失效，只能靠 B4 的可用性標記處理。

### B2 YouTube（videoId / playlist item id）

- **同一筆 playlist item 上有兩個不同的 id**，官方文件把它們並列：
  - playlist item 的 `id`：形如 `UEx4SkJKQzR0Q1l0eVdXbFNBQms1TlRER2kyc2ZxYnFWLkIwRDYyOTk1Nzc0NkVFQ0En`，是「這支影片在這張歌單裡的這一筆」的身分。
  - `snippet.resourceId.videoId` 與 `contentDetails.videoId`：11 字元的影片身分。
  - `snippet.position`：unsigned integer，從 0 起算的順序。
  來源：<https://developers.google.com/youtube/v3/docs/playlistItems>（欄位表逐字）與 <https://developers.google.com/youtube/v3/docs/playlistItems/list>（`videoId` 參數「return only the playlist items that contain the specified video」，即一對多關係）。
- **哪個更穩定**：
  - `videoId` 是影片的身分，跨歌單、跨使用者都相同。
  - playlist item id 是「影片 × 歌單」這一筆關聯的身分。移動/刪除一筆項目要用 item id（GeeksforGeeks 的 `playlist_item_update_position` 用 `id` 指定項目，來源 <https://www.geeksforgeeks.org/python/youtube-data-api-playlist-set-4>）；ytmusicapi 的對應概念是 `setVideoId`，文件明言「The setVideoId is the unique id of this playlist item and needed for moving/removing playlist items」（來源：<https://ytmusicapi.readthedocs.io/en/0.22.0/reference.html>）。把影片移出歌單再加入，會拿到新的 item id（**推測**：由「item 是關聯的身分」推導，未見官方明文）。
  - 結論：**對 FMP 的 TrackKey 而言，`videoId` 才是曲目身分**（`TrackKey = youtube:<videoId>`）；playlist item id 只在需要區分「同一支影片在同一歌單出現兩次」時才需要存。這一點與 A1 提到的重複項問題是同一個問題。
- **影片重新上傳**：YouTube 沒有「替換同一 videoId 的內容」的公開機制；重新上傳會得到新的 videoId、舊的變成不可用。官方文件**查不到**明文，此為社群共識（例如 <https://camcatbooks.com/youtube-video-unavailable-heres-the-fix> 把不可用歸因於版權聲明、地區封鎖、帳號限制等，來源等級為一般文章，非官方文件）。
- **歌單內已刪除／已轉私人影片**：官方文件的錯誤碼只涵蓋 `videoNotFound` / `playlistNotFound`（請求參數層級，來源 <https://developers.google.com/youtube/v3/docs/playlistItems/list>），**沒有**說明清單內一筆已被刪除的項目在回應中的長相。社群普遍說法是被刪的項目會以 `Deleted video` / `Private video` 佔位、且取不到 `resourceId.videoId`（來源僅為社群教學，**官方文件查不到逐字條文**）。實務上必須**防禦性處理**：把 `resourceId` 或 videoId 缺失當成 `unavailable`，而不是當成解析失敗。

### B3 網易雲（songId）

- **版權到期下架**：歌曲變灰，點擊顯示「因合作方要求，該資源暫時無法使用」。下架是授權狀態的變化，**songId 本身不變**；恢復上架後同一個 id 可播。來源：第一財經 2017-08-11 報導 <https://www.yicai.com/news/5329909.html>、21 世紀經濟報導 <https://m.21jingji.com/article/20170811/herald/11f17c1efb966cb5ef46c109122ee356.html>、網易雲音樂官方聲明（同前兩篇引用）。
- **版權方重新授權上傳新版本時，新舊是兩筆不同的歌曲**。網易雲官方公告寫得很清楚（2026-05-08）：
  - 「因当前版本歌曲版权到期等原因，部分歌曲会下架，若在下架前已购买，可以在已购列表中正常播放和下载。」
  - 「但有一种情况：版权方重新授权上传了新版本。此时：旧版本：可播放可下载，但暂时无法红心收藏，若旧版本恢复上架则不影响。新版本：支持红心收藏，但需要重新购买才能享有永久播放下载权益。」
  - 來源：IT之家 <https://www.ithome.com/0/947/979.htm>、新浪財經 <https://finance.sina.com.cn/tech/discovery/2026-05-09/doc-inhxfhtz4031095.shtml>
- **對 FMP 的意義**：songId 對「同一筆上架紀錄」穩定；但「同一首歌被換版本」在網易雲是**新 songId**，本地舊參照會指向一個已下架或已不可紅心的舊紀錄。這正是 B4 要處理的情境。
- 平台自行換源（非版權方重新上傳）是否會換 id，**查不到**。

### B4 遠端替換或重新上傳

**業界有沒有公開做法？分層回答。**

1. **領域模型層：MusicBrainz 的 recording 邊界（最權威的公開慣例）**
   - remaster **不**建立新的 recording：「separate recordings should not be created for remastered tracks, since remastered tracks generally feature the original recording with different mastering applied」，remaster 用 release 之間的 relationship 描述。
   - 例外：被標為 remaster 但實際上是 remix 的，才走 remix 規則另立 recording。
   - live 錄音的演出資訊移到 disambiguation，而不是塞進標題。
   - 來源：<https://musicbrainz.org/doc/Style/Recording>（逐字引用前述句子）。
   - 意義：**「同一個錄音的不同母帶/版本」是同一首歌的屬性，不是新歌；「不同演出/不同錄音」才是新歌**。這是 FMP 判斷「重新上傳後該不該視為同一首」時可用的判準。

2. **串流平台層：網易雲自己揭露的模式（最貼近本題的實證）**
   - 舊版本與新版本**並存為兩筆**，各自獨立可播/可收藏；使用者的已購權益綁在「購買當下的那一筆」，換版本不繼承。
   - 來源同 B3（IT之家、新浪財經）。這個模式等價於：**平台不會幫你把舊參照 relink 到新 id**，把判斷留給客戶端。

3. **客戶端層：Spotify / YouTube Music 的官方開發者文件**
   - Spotify 有沒有「relinked track / unavailable track」的公開 API 語意或處理指引，**查不到**（搜到的都是 Local Files 的支援文章與社群除錯，例如 <https://support.spotify.com/us/article/local-files>、<https://community.spotify.com/t5/Android/quot-This-track-isn-t-available-on-your-device-quot-for-some/td-p/5648967>，與本題無關）。
   - YouTube Music 的 item 層級身分只在非官方的反向工程套件（ytmusicapi 的 `setVideoId`）看得到，**官方文件查不到**。
   - 使用者可見行為（無法播放的曲目在介面上變灰、保留在歌單中）是普遍現象，但**查不到**把它寫成規範的官方開發者文件。**推測**：各大平台的共通做法是「保留參照 + 標示不可用」，因為刪除使用者歌單裡的一列是更糟的體驗。

**對 FMP 的建議（依上述證據）**

- 本地保留參照，不因遠端消失就刪列；新增一個可用性欄位（例如 `availability`：`available` / `unavailable` / `replaced`）。依據：網易雲的「舊版本仍可播放」與 MusicBrainz 的「remaster 不另立 recording」都指向「保留並標示」而非「刪除」。
- 遠端若以新 id 回報同一首歌，需要一個「疑似換版本」的偵測：用 C 段的評分核心比對（標題＋歌手＋時長），命中就標 `replaced` 並提示使用者，而不是靜默新增一列重複曲目。依據：網易雲的版本替換是新 songId（B3），而使用者心智上仍是同一首歌（MusicBrainz 的 recording 邊界）。
- B 站的 cid 消失、YouTube 的 videoId 消失，兩者都只能標 `unavailable`，因為遠端沒有留下任何可 relink 的線索。依據：B1/B2 的查證結果。

---

## C. 匹配評分

### C1 字串正規化

**全形/半形與相容字符：用 Unicode NFKC**

- NFKC（Normalization Form KC，compatibility composition）會把相容等價的字符摺疊：全形 `Ｒ`（U+FF32）→ `R`（U+0052）、連字 `ﬁ`（U+FB01）→ `fi`、羅馬數字 `Ⅸ`（U+2168）→ 字母、上標 `⁵`（U+2075）→ `5`、半形與全形片假名正規化成同一串。
- NFC/NFD（canonical）**不會**做這些摺疊，NFKC/NFKD（compatibility）才會。這是 NFKC 與 NFC 的關鍵差異。
- 來源：Unicode 官方 UAX #15 <https://unicode.org/reports/tr15>（「Normalization Form KC additionally folds the differences between compatibility-equivalent characters…the halfwidth and fullwidth katakana characters will normalize to the same strings, as will Roman numerals and their letter equivalents」）；IBM Db2 文件對四種形式的定義 <https://www.ibm.com/docs/en/db2-for-zos/13.0.0?topic=ccsids-normalization-unicode-strings>；微軟 Win32 文件對 KC/KD 的說明 <https://learn.microsoft.com/en-us/windows/win32/intl/using-unicode-normalization-to-represent-strings>。
- 實作順序範例（Python，可對應到 Dart）：先 NFKC 處理全形與連字 → 再處理空白 → 再 casefold。來源：<https://mbrenndoerfer.com/writing/text-normalization-unicode-nlp>。

**建議的正規化管線順序（給 FMP）**

1. `NFKC`（全形→半形、連字、羅馬數字、上下標）
2. `toLowerCase`（casefold；拉丁字母大小寫）
3. 簡繁統一（見下方 C4 的 `opencc`）
4. 去除裝飾性標點與多餘空白（舊版 FMP 已有等價實作，見 `playlist_import_service.dart` 的 `_normalize`，涵蓋 `【】\[\]()（）「」『』《》〈〉` 等與裝飾符號）
5. 版本標記的處理——**不要無條件刪除括號內容**，理由見下

**括號內容（feat. / Live / Remix / 官方版）**

- 音樂領域有明確慣例：MusicBrainz 把「不屬於主標題、用來區分不同 release 或同名 track 的額外資訊」叫 **ETI（extra title information）**，規定寫在主標題之後、以單一空格加圓括號包住；且規定大小寫——純描述性的（mix、remix、live、remaster、edit）用小寫。來源：<https://musicbrainz.org/doc/Style/Titles>（逐字：「additional information on a release or track name that is not part of its main title…is referred to as extra title information (ETI) and should be entered after the main title, preceded by a single space and wrapped in parentheses」）。
- 同一頁明確區分 **feat. 不屬於 ETI**：「Featured artists should not be entered in this manner, but rather as part of the artist…」。也就是說 **feat./ft. 應該歸到歌手欄位，而不是當成標題的變體標記**。
- 推論（**推測**）：因為 ETI 的分類本身帶語意（studio vs live vs remix 是**不同錄音**，remaster 是**同一個錄音**，見 B4 的 MusicBrainz recording 規則），把括號內容整段丟掉會讓 live 版和原版變成同一個字串，反而降低匹配精度。正確做法是**抽出來單獨比對**，而不是刪掉。舊版 FMP 已經這樣做（`playlist_import_service.dart` 的 `_calculateBracketContentSimilarity` 抽 `「」《》『』【】〈〉` 五種括號內容，與原標題比對後取較高分），這個方向有慣例支撐，值得沿用。

### C2 時長容差

**業界慣例的實際樣貌**

- MusicBrainz Picard 的配對門檻是**可設定的相似度分數**，不是固定秒數（「This setting determines the minimum match between a cluster and a release on MusicBrainz for the release to be considered」）。來源：<https://picard-docs.musicbrainz.org/en/latest/config/options_matching.html>。
- 純以時長為硬門檻的公開規範，在 MusicBrainz / AcoustID / lrclib 的文件裡**查不到**——它們主要靠錄音指紋或搜尋結果品質，時長只當輔助欄位。
- FMP 自己的現行值（唯讀，供比較）：
  - 歌詞自動匹配硬門檻 `AppConstants.lyricsDurationToleranceSec = 20` 秒；評分函式內分級 ≤3 秒給 1.0、≤10 秒給 0.8、≤20 秒給 0.5。來源：`lib/core/constants/app_constants.dart:179`、`lib/services/lyrics/lyrics_auto_match_service.dart` 的 `_calculateScore`。
  - 歌單匯入用「絕對值＋百分比混合」：`|Δ| ≤ 10 秒` 直接給滿分；短曲（<180 秒）放寬到 15/20/30 秒；否則按百分比分級 5/10/15/20/30/50/80/100/200%，>200% 直接過濾（判為合集/串燒）。來源：`playlist_import_service.dart` 的 `_calculateDurationMatchScore`。
- **建議**：維持「絕對值與百分比取較寬者」的兩段式（硬門檻過濾明顯不是同一首 + 軟評分連續給分），因為純秒數對 2 分鐘的短曲太鬆、對 10 分鐘的長曲太緊。硬門檻建議 ≤10 秒或 ≤5%（取較寬者）；軟評分的滿分區間 ≤3 秒（與舊版歌詞匹配一致）。**依據**：舊版兩處的實作經驗值 + Picard 以相似度門檻而非秒數的慣例。**注意**：現場版與不同母帶會有數秒差，5000 首規模下門檻不宜收緊到 ±3 秒。

### C3 多歌手

**慣例**

- MusicBrainz 的 artist credit 是**有序列表**，每個 artist 後面可帶 join phrase（`&`、`feat.`、`,` 等），且 feat. 歸屬在 artist credit 而非標題（來源同 C1：<https://musicbrainz.org/doc/Style/Titles>）。這確立了「順序有意義、但順序不同不改變身分」的性質。
- **推測**（由上述慣例推導，未見規範明文）：順序對「誰是主要歌手」有語意，所以不能完全忽略順序。

**建議做法**

1. 兩邊的歌手欄位都先正規化並**拆成集合**：以 `,` `&` `/` `、` `×` `x` `feat.` `ft.` `featuring` `with` `vs.` 為分隔符切開，逐項做 C1 的正規化。
2. 集合相似度用 Jaccard（交集/聯集），或「一對一最佳配對後取平均」。
3. 對「只有一位符合」給部分分數，不要直接判 0：取兩集合所有配對中的最高相似度當分數下限。**推測**：這是「多位歌手其中一位命中」的自然處理方式，無公開規範。
4. 主要歌手加權：兩邊清單的**第一位**（或遠端標記為主要的那位）相似度乘上較高權重（舊版 FMP 的 0.25 權重即屬此類）。
5. **feat. 出現在標題裡時的處理**：比對前先從標題剝離 `feat.` / `ft.` / `featuring` / `with` 之後的段落，把它當作歌手資訊的**補充來源**——只在歌手欄位缺失或明顯不完整時才採用，且打折計分。**依據**：MusicBrainz 明言 feat. 屬於 artist credit 而非標題（C1），所以它在標題中出現時是「欄位搬錯了位置」的資訊，應該搬回去而不是當成標題噪音丟掉。
6. 舊版 FMP 已實作「歌手出現在頻道名優先、出現在標題需 >70 分才採用且打 0.8 折」的近似邏輯（`playlist_import_service.dart` 的 `_calculateRelevanceScore` 內 `artistSimilarity` 計算），可作為新評分核心的參考基準。

### C4 Dart 套件（版本、發佈日期、授權、維護狀態）

以下全部逐字取自 `https://pub.dev/api/packages/<name>` 與 `/score`（2026-09-28 讀取）。

| 套件 | 最新版 | 最後發佈 | 授權 | pub points | likes | 30 天下載 | 判斷 |
|---|---|---|---|---|---|---|---|
| `string_similarity` | 2.2.0 | 2026-04-04 | MIT（pub tag `license:mit`） | 160/160 | 129 | 76,594 | **建議採用**。Dice coefficient（bigram）；官方描述自稱「mostly better than Levenshtein distance」，對 CJK 有效。7 個版本，最新一次 5 個月前。 |
| `unorm_dart` | 0.3.2 | 2025-10-01 | MIT | 150/160 | 29 | 263,526 | **建議採用**。NFC/NFD/NFKC/NFKD，Unicode 17.0，`walling/unorm` 的 Dart port。用來做 C1 的全形/半形正規化。 |
| `diacritic` | 0.1.6 | 2024-09-23 | 未列在 pub tag；GitHub repo 欄位為空 | 160/160 | 291 | 666,875 | **可用**（去重音符號，`café`→`cafe`）。下載量高、滿分，但已近 2 年未發版。 |
| `string_normalizer` | 0.4.0 | 2025-10-20 | MIT | 160/160 | 9 | 6,122 | 與 `diacritic` 功能重疊，二選一（`diacritic` 較熱門） |
| `opencc` | 1.1.0 | 2024-10-01 | Apache-2.0 | 150/160 | 0 | 496 | **可用於繁簡統一**。OpenCC 演算法的 Dart port（repo: `lindeer/opencc-dart`）。注意：需要在 native 端帶 assets（描述明寫「with native-assets」），且已有 `1.2.0-dev.1` 預覽版（不要用 dev）。likes 0、下載量低，維護風險需自行評估。 |
| `pinyin` | 3.3.0 | 2024-04-16 | BSD-2-Clause | 160/160 | 19 | 10,286 | 漢字→拼音，描述含「simplified or traditional Chinese」轉換。若要做中英/拼音混合比對才需要；否則 `opencc` 較貼題。 |
| `fuzzywuzzy` | 1.2.0 | 2024-08-15 | **GPL-2.0**（GitHub API `sphericalkat/dart-fuzzywuzzy`） | 150/160 | 153 | 110,856 | **不建議**。功能最完整（`ratio`/`partialRatio`/`tokenSortRatio`/`tokenSetRatio`），但 GPL-2.0 對 MIT 專案（FMP 的 `LICENSE` 為 MIT License, Copyright (c) 2026 imoR）有傳染性。repo 最後 push 2026-09-11，仍在維護。 |
| `levenshtein` | 1.0.2 | **2014-02-10** | Unlicense | 25/160 | 0 | 11 | **不要用**。pub tag 含 `is:legacy`、`is:unlisted`，12 年未更新，points 25/160。 |
| `text_similarity` | 1.0.1 | 2023-09-21 | 未查 | 150/160 | 7 | 8 | 不採用（Levenshtein automaton 查詢，非字串相似度） |
| `jaro_winkler` | — | — | — | — | — | — | **不存在**：`https://pub.dev/api/packages/jaro_winkler` 回 **404** |
| `chinese_converter` | — | — | — | — | — | — | **不存在**：`https://pub.dev/api/packages/chinese_converter` 回 **404** |

**舊版自寫了什麼、套件能不能取代**

- `lib/services/import/playlist_import_service.dart`：整條評分鏈（`_calculateRelevanceScore` 及其十餘個 `_calculate*` 輔助函式）約 700 行手寫。其中**純字串相似度核心**是 `_calculateSimilarity`，由三塊組成：子串包含關係加分、`_calculateNGramSimilarity`（字元 bigram 的 **Jaccard** 係數，`|A∩B| / |A∪B|`）、`_levenshteinDistance`（手寫 O(n·m) 二維 DP）。取值為三者最大。
- `lib/services/lyrics/lyrics_auto_match_service.dart`：`_stringSimilarity` 是 `1 - levenshtein / maxLen`，而 `_levenshteinDistance` **又手寫了一份**（與上一個檔案的實作重複）。
- **可被套件取代的部分**：bigram Jaccard 這一段。`string_similarity` 提供的 Dice coefficient 為 `2|A∩B| / (|A|+|B|)`，與 Jaccard 存在單調關係 `Dice = 2J / (1 + J)`（**推測**：這是標準的集合相似度恆等式，非來自查到的來源），因此**換成 Dice 不會改變任何兩個字串的相對排序**，可以直接取代手寫 N-gram 那一段。
- **無法被現成套件乾淨取代的部分**：Levenshtein 沒有可用的穩定套件（`levenshtein` 已淘汰、`fuzzywuzzy` 是 GPL）。手寫一份帶早退的 Levenshtein 約 30 行，且舊版已經有兩份可合併——建議重寫時**收斂成一個共用核心**，而不是找套件。
- 剩下的部分（播放量加權、官方頻道加分、版本關鍵字加分、標題負面關鍵字如「合集/串燒/作業用」）是**領域規則**，沒有任何通用套件能取代，只能自己維護成一份資料表。

---

## 對 FMP 的具體建議（每條附依據）

1. **差異計算不要引入 LCS/Myers diff。** 單向權威同步下四類差異都是集合運算或逐欄比較（A1）；LCS 只用於雙向或產生 patch 的場景。依據：A1 的分類表與 YouTube `snippet.position` 的存在。
2. **關聯表的排序欄位存遠端序號，本地不自己算間隔。** 遠端給 position 就存 position，只給有序陣列就存陣列索引；每次刷新在單一 transaction 內整批覆寫 order，不引入稀疏間隔或 LexoRank 的複雜度。依據：A1/A2；稀疏整數與 LexoRank 的價值在於「只有少量項目變動時少寫幾列」，而單向刷新本來就是整批處理。
   - 若日後真的需要避免整表 position 覆寫，退化成本最低的是稀疏整數（間隔 1000），因為它不需要 base-62 實作（A2 的來源明確偏好整數而非浮點）。
3. **關聯表要允許同一首歌在同一歌單出現兩次。** `UNIQUE(playlist_id, track_key)` 會把 YouTube 歌單裡的重複影片摺疊掉；唯一鍵要含 position，或不要對 (playlist_id, track_key) 設唯一。依據：A1（ytmusicapi 的 `duplicates` 參數）與 B2（videoId 對 playlist item id 是一對多）。
4. **任何批次寫入都要包在 transaction 或 batch 內，不要逐列 await。** 每列一個隱式 commit 就是一次 fsync（A3 瓶頸第 1 項）。大歌單採「抓一頁寫一頁」的流水線，每頁一個 transaction。
5. **避免在有外鍵關聯的列上用 `INSERT OR REPLACE`。** SQLite 的 `INSERT OR REPLACE` 是 DELETE + INSERT，會觸發 `ON DELETE CASCADE`；要合併欄位時用 drift 的 `DoUpdate(target: [...])`。依據：A3 瓶頸第 2 項（SQLite 語意推導，標為推測）。
6. **「整張歌單刷新」用 refresh generation 標記達成原子性，而不是一個巨大的 transaction。** 每頁寫入時帶本輪 generation，全部頁數完成才標記 complete，讀取一律只認最新 completed generation。這樣中途失敗的結果是「舊的完整版本還在」。依據：A4（drift 的 `BEGIN IMMEDIATE` 會讓巨大 transaction 長時間持有寫鎖，因此整張包一個 transaction 在寫鎖維度上有代價）。
   - 如果產品上可以接受「刷新期間介面暫時鎖住」，那直接整張包一個 `transaction()` 是最簡單且唯一能保證全有全無的做法（A4 末段）。
7. **在 `beforeOpen` 執行 `PRAGMA foreign_keys = ON`，並在 migration 期間關閉後重開。** 這是 drift 官方建議，且 SQLite 預設不強制外鍵。依據：A4 的 drift migrations 文件。
8. **開啟 WAL。** 讓長達數秒的刷新寫入不阻塞 UI 的讀取查詢；drift 官方在多 isolate / read pool 的設定裡明說 WAL 是避免 "database locked" 的前提。依據：A4（<https://drift.simonbinder.eu/platforms/vm>）。
9. **曲目身分：YouTube 用 `videoId`、B 站用 `bvid:cid`、網易雲用 `songId`**（與已定案的 `TrackKey` 一致）。額外要記住的是：YouTube 的 playlist item id、B 站的 cid 分 P 順序，都是「關聯」而非「曲目」的身分，不該進 `TrackKey`。依據：B1（cid 指的是具體視頻檔案）、B2（videoId 對 playlist item id 一對多）。
10. **遠端曲目消失時保留並標示 `unavailable`，不刪列。** 並用評分核心偵測「疑似換版本」標成 `replaced` 後提示使用者。依據：B3（網易雲版本替換是新 songId）、B4（網易雲新舊並存、MusicBrainz 的 remaster 不另立 recording）、以及 A4/B4 兩處的「查不到官方指引 → 依可用證據自行決定」。
11. **正規化管線固定為：NFKC → 小寫 → 簡繁統一 → 去裝飾標點/空白 → 抽出括號內容單獨比對。** 不要把括號內容整段丟掉。依據：C1（UAX #15 的 NFKC 語意、MusicBrainz 的 ETI 規範）。
12. **歌手比對用集合相似度，先從標題剝離 feat. 段落。** 依據：C1（MusicBrainz 明言 feat. 屬 artist credit 而非標題）與 C3。
13. **時長用「絕對值與百分比取較寬者」的兩段式，硬門檻建議 ≤10 秒或 ≤5%。** 依據：C2（舊版實作經驗值、Picard 以相似度門檻而非固定秒數的慣例）。
14. **套件選擇：`string_similarity` 2.2.0（MIT）取代手寫 bigram Jaccard；`unorm_dart` 0.3.2（MIT）做 NFKC；`opencc` 1.1.0（Apache-2.0）做繁簡統一；`diacritic` 0.1.6 做重音符號。Levenshtein 自己寫（沒有可用的 MIT 套件）。`fuzzywuzzy` 因 GPL-2.0 不採用（FMP 是 MIT）。** 依據：C4 的 pub.dev 逐項查證。
    - `diacritic` 的授權在 pub.dev 上沒有 tag、GitHub repo 欄位為空，採用前需自行確認授權檔（本次**查不到**其授權）。

---

## 查不到清單（明確列出，避免後人重複查）

| 主題 | 查不到的內容 |
|---|---|
| B1 | bvid 的產生規則、是否可能變動；B 站允許 UP 主替換視頻源後 cid 是否改變；稿件刪除後重建是否沿用 bvid |
| B2 | YouTube 官方對「同一 videoId 內容被替換」的說明（重新上傳＝新 videoId 僅為社群共識）；`playlistItems` 對清單內已刪除/私人影片的 placeholder 明文（`Deleted video` / `Private video`） |
| B3 | 網易雲平台自行換源（非版權方重新上傳）是否會換 songId |
| B4 | Spotify 官方對 relinked / unavailable track 的開發者文件；YouTube Music 的 item 身分官方說明 |
| A4 | drift 官方**文件**對「`transaction()` 發出 `BEGIN IMMEDIATE`」的說明（只在原始碼註解看到，見本檔引用的 `database.dart` 第 66–74 行）；`batch()` 是否自帶 transaction 的明文（未查證 drift 原始碼的 `batch()` 實作） |
| C2 | 業界對「曲目匹配時長容差」的公開規範值（MusicBrainz / AcoustID / lrclib 都沒有把秒數寫成規範） |
| C4 | `diacritic` 的授權（pub.dev 無 license tag、pubspec 無 repository 欄位）；`jaro_winkler` 與 `chinese_converter` 在 pub.dev **不存在**（API 回 404） |
