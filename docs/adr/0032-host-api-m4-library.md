# 0032 — 宿主 API v1 在發佈前擴充歌單匯入、帳號資料讀寫與排行；會改動遠端的檢查案例只重播

- 狀態：已採納
- 日期：2026-10-15
- 影響範圍：`app/lib/plugins/`（`SourcePlugin`、`fmp-plugin.d.ts`、DTO 驗證、`checks.json`、健康檢查與錄製）、`app/test/fixtures/plugins/`（測試插件）、`1morr/fmp-plugins` 的三個官方插件與新的 `spotify`、`qqmusic` 插件

## 背景

ADR 0014 §決定 4 列了 `importPlaylist`、`libraryRead`、`libraryWrite`、`charts` 四個能力，ADR 0028 定了「凍結前在 v1 內照同樣的方式加」，但四個能力都沒有 DTO、匯出與檢查案例（`fmp-plugin.d.ts` 與 `PluginCapability` 只有名稱）。M4 的歌單匯入與刷新（ADR 0019 §決定 2–5）、帳號頁的歌單與電台匯入（ADR 0031）、首頁排行（ADR 0016、0017）都要用它們。

另外三件事也落在插件契約上（`.trellis/tasks/archive/2026-10/10-15-m4-library-sync/research/m4-decisions.md`）：

- **分 P 兩欄**：`TrackSummary` 沒有 `partIndex`、`parentTitle`，B 站收藏夾匯入時展開多 P 會以「最後寫入為準」清掉曲目的分 P 兩欄（M3 審查發現）。
- **私人歌單的認證**：ADR 0012 §決定 2 把「讀收藏夾與私人歌單」列為 `required`、「歌單刷新」列為 `userPreference`，刷新一個收藏夾兩邊都算；照字面標 `required` 會讓未登入的人不能匯入公開收藏夾（舊版可以）。
- **會改動遠端的檢查案例**：ADR 0015 §決定 4 的「一份四用」讓健康檢查、冒煙、錄製都以真實連線跑每一條案例；`libraryWrite` 的案例真的跑就會改使用者的遠端歌單。

## 考慮過的選項

### 歌單匯入的輸入

- **只收網址，插件自己解析並抓完整歌單**：一次回傳整張歌單，宿主無從做到 ADR 0019 的「抓一頁寫一頁、部分失敗不移除」。否決。
- **網址辨識與分頁讀取分成兩個匯出**：`playlistFromUrl` 認網址（同 ADR 0028 的 `liveRoomFromUrl`，宿主依序問、第一個認得的勝出），`importPlaylist` 以 `cursor` 分頁。帳號頁匯入時直接以 `playlistId` 呼叫後者。採用（MusicFree 的 `importMusicSheet(urlLike)` 與 `getMusicSheetInfo(sheet, page)` 分工相同）。

### 完整性回報

- **插件回一個「完整」旗標**：插件不知道宿主那一端有沒有每一頁都寫成功。否決。
- **宿主判斷：每頁成功、最後 `cursor` 為空、有 `total` 時筆數相等**：插件只在確定 `total` 等於會回傳的筆數時才給（YouTube 的標頭筆數含被隱藏的影片，給了會讓每次刷新都「部分完成」）。採用。

### 粉絲勳章牆的能力

- **新能力 `liveImport`**：要改 ADR 0014 §決定 4 的能力清單，而它只是「讀帳號的資料」。否決。
- **`libraryRead` 下的選填匯出**：ADR 0031 本來就把它歸「`libraryRead` 一類」。採用。

### 私人歌單的認證

- **匯入與刷新一律 `required`**：未登入不能匯入公開收藏夾。否決。
- **宿主依「這是不是自己的歌單」決定**：宿主沒有音源分支，也不知道歌單的擁有者。否決。
- **一律 `userPreference`，被拒時插件以 `required` 重送一次**：只在「回應是無權限、這次沒帶憑證（`credentialsAttached` 為假）、`fmp.credentials.get()` 不是 `null`」時重送。宿主不必改。採用。

### 會改動遠端的案例

- **`libraryWrite` 不寫檢查案例**：違反 ADR 0015「每個能力一條」，錯誤對應沒有契約守。否決。
- **案例標 `mutates: true`，只在契約測試重播**：健康檢查、命令列冒煙與錄製、App 內開發工具的真實與錄製模式一律略過並標「略過：會改動遠端」；fixture 一律手寫。採用。

## 決定

在 v1 內加選填欄位與新匯出，`hostApiVersion` 維持 1（ADR 0028 §決定 1）。

1. **`TrackSummary` 加選填 `partIndex?`（正整數）、`parentTitle?`**：分 P 曲目的序號與影片標題，對到 `tracks.part_index`、`parent_title`。插件回傳分 P 曲目時一定要給，宿主的 upsert 才不會清掉這兩欄。
2. **`importPlaylist`** 的兩個匯出：
   - `playlistFromUrl({url}) → {playlistId} | {mixSeed: {sourceId, cid?}} | null`：不是這個插件的網址回 `null`，可以發請求（短網址）。`mixSeed` 只有同時宣告 `mix` 的插件能回（Mix 網址與 `mix:<id>` 簡寫由插件認，宿主不解析任何音源的網址）。
   - `importPlaylist({playlistId, cursor?}) → {playlist: {title, description?, artwork?, ownerName?, writable?}, items: [{track: TrackSummary, remoteItemId?, unavailable?}], cursor: string | null, total?}`。`cursor` 為空＝最後一頁；`remoteItemId` 是遠端項目的 id（YouTube 的 `setVideoId`，移除要用）；`unavailable` 是遠端標的失效；`writable` 是「這張是登入的帳號自己的、可以寫」，`null` 或沒有＝這次不知道（沒帶憑證），宿主保留上次的值。
   - **完整**＝每一頁都成功、最後 `cursor` 為空、有 `total` 時拿到的筆數等於 `total`。只有完整才套用移除與順序（ADR 0019 §決定 2）。
   - **錯誤**：遠端歌單不存在或沒有權限讀：`NotFound`；要登入才讀得到而沒有登入：`AuthRequired`。宿主依此標「來源失效」或「需要登入」。
   - **認證**：請求一律 `userPreference`；回應是無權限、`credentialsAttached` 為假、`fmp.credentials.get()` 不是 `null` 時，以 `required` 重送一次（ADR 0012 §決定 2 的補充）。
   - **補充（2026-10-21，M4 PR 17）：`truncated`**。`importPlaylist` 的回傳加選填 `truncated?: boolean`（缺省 `false`）：`true`＝插件已讀完它讀得到的，但遠端歌單可能還有更多。只能出現在最後一頁（`cursor` 為空），帶 `cursor` 時宿主以 `ParseError` 拒收。刷新視為不完整（等同 `total` 不符）：只新增與更新、不移除不重排，標「上次刷新：部分完成」（ADR 0019 §決定 2）。外部匯入（匯入預覽，PR 19）不算讀取失敗：照常進匹配，並在預覽頁提示「來源只提供了部分曲目」。起因是 Spotify embed 頁每張歌單最多只給前 100 首、沒有總數欄位（PR 17 開頭實測；擁有者 2026-10-21 決定匯入前 100 首並提示）。
3. **`libraryRead`**：
   - `libraryPlaylists({cursor?}) → {playlists: [{playlistId, title, artwork?, trackCount?, writable}], cursor: string | null}`，請求 `required`。「已匯入」由宿主以（插件 id, `playlistId`）比對，插件不管。
   - 選填 `libraryLiveRooms() → {rooms: LiveRoom[]}`，請求 `required`；只有同時宣告 `live` 的插件能匯出（帳號區的「從帳號匯入電台」依它出現）。
4. **`libraryWrite`**（必須同時宣告 `libraryRead`，manifest 驗證時檢查），請求一律 `required`：
   - `createPlaylist({title}) → {playlistId}`；
   - `addToPlaylist({playlistId, tracks: [{sourceId, cid?}]}) → {results: [{status: 'added' | 'alreadyPresent' | 'failed', error?}]}`；
   - `removeFromPlaylist({playlistId, items: [{sourceId, cid?, remoteItemId?}]}) → {results: [{status: 'removed' | 'notPresent' | 'failed', error?}]}`。
   - `results` 與輸入同長同順序；`error` 是結構化錯誤的形狀（`fmpError`、`reason?`）。去重（已在歌單裡）與音源自己的 id 換算（B 站 bvid→aid）在插件內做。
5. **`charts`**：`chartList() → {charts: [{chartId, title}]}`（可以是插件內的常數，不發請求）；`chart({chartId}) → {tracks: TrackSummary[]}`，不分頁。請求 `userPreference`。榜單的來源與排序由插件決定。
6. **匯出與能力**：照 `login`、`live` 的前例，每個能力的匯出列在 `requiredExports`／`knownExports`，宣告就要全有、匯出了沒宣告就拒載——`importPlaylist`：`playlistFromUrl`、`importPlaylist`；`libraryRead`：`libraryPlaylists`（選填 `libraryLiveRooms`，匯出了而沒宣告 `live` 拒載）；`libraryWrite`：`createPlaylist`、`addToPlaylist`、`removeFromPlaylist`；`charts`：`chartList`、`chart`。
7. **`checks.json`**：
   - 每能力一個鍵：`importPlaylist`（輸入 `{url}`，跑 `playlistFromUrl` 再跑第一頁，檢查 `items`；用公開歌單，不標 `requiresLogin`）、`libraryRead`（`libraryPlaylists` 第一頁，`requiresLogin`）、`libraryWrite`（`addToPlaylist`，`requiresLogin`＋`mutates`）、`charts`（`chart`）。
   - **`mutates: true`**：只有契約測試的重播會跑；健康檢查、命令列錄製與冒煙、App 內開發工具的真實與錄製模式一律略過並標「略過：會改動遠端」。它的 fixture 一律手寫並標 `meta.edited`。ADR 0015 §決定 4「一份四用」的例外。
   - `requiresLogin` 但不是 `login` 的案例：健康檢查與 App 內錄製在隔離環境帶上該音源已存的憑證；錄到的流量寫檔前以該插件 `accounts` 列的 id、名稱、頭像換值（`scrubAccount` 擴大到所有 `requiresLogin` 案例），仍看得到就不寫；錄到的檔照 ADR 0015 §決定 7 的更正刪減後才提交。
8. **僅元資料來源**：Spotify、QQ 是只宣告 `importPlaylist` 的插件，官方 id `spotify`、`qqmusic`（與舊版 `originalSource` 的字串相同），請求 `never`（ADR 0012 §決定 7）。
9. **同步點**照 ADR 0028 §決定 9：每加一個欄位或匯出，同一個 PR 改 `fmp-plugin.d.ts`、Dart 端的 shapes、`SourcePlugin` 的方法與 `FmpChecks`；`fmp-plugins` 在 FMP 合併後實作並改 `FMP_REF`。

採用的慣例：MusicFree 的 `importMusicSheet`／`getMusicSheetInfo`（分頁、`isEnd`）與 `getTopLists`／`getTopListDetail`；ADR 0028 的 `liveRoomFromUrl`（依序問、第一個認得的勝出）；逐項結果照 ADR 0013 §決定 5「部分成功要標出失敗項」；`mutates` 與 ADR 0028 的 `idempotent` 同一個理由放在宣告處：只有寫案例的人知道呼叫會不會改東西。

## 後果

- 好的：四個能力有了契約，宿主仍沒有音源分支；部分失敗看得出來；公開收藏夾不登入也能匯入，私人歌單關掉「以登入身分瀏覽與播放」仍能刷新；健康檢查不會改到使用者的遠端歌單；分 P 曲目匯入後不掉欄位。
- 壞的：`libraryWrite` 的錯誤對應只有手寫 fixture 守，端點改版要靠擁有者在場的實測才看得到；`writable` 只在帶了憑證的回應才更新，關掉開關的使用者看到的是上次的值；插件要自己做「被拒時以 `required` 重送」，漏做的插件私人歌單會變「來源失效」。
- 之後要注意：
  - M7 的 `lyrics` 照同樣的方式加；
  - 「加入遠端歌單」要預先勾出已含該曲目的歌單時，加選填的 `playlistsContaining` 匯出；
  - Spotify、QQ 抓頁面的方式隨改版失效時只改插件（ADR 0012 §決定 7 交給健康檢查）。

## 如何確認

- `type_definitions_test.dart`：新欄位、新匯出、`results` 的 `status` union 與 Dart 端一致（含變異案例）。
- 各能力自己的 `*_capability_test.dart`（ADR 0028 的更正）：宣告了沒匯出、匯出了沒宣告拒載；`libraryWrite` 沒宣告 `libraryRead`、`libraryLiveRooms` 沒宣告 `live`、`mixSeed` 來自沒宣告 `mix` 的插件都拒絕；`results` 長度與輸入不同是 `ParseError`；回傳值驗證。
- `checks_test.dart`、`contract_runner_test.dart`：四個能力的案例格式；`mutates` 的案例重播照跑；`record_test.dart`、`health_check_test.dart`、`dev_case_runs_test.dart`：`mutates` 一律略過、不連網。
- `account_scrub_test.dart`／`dev_case_runs_test.dart`：`requiresLogin` 的 `libraryRead` 案例錄製時，含自己帳號名稱的回應換值後才寫、換不掉就不寫；改一個無關欄位不擋（雙向變異）。
- 刷新引擎的單元測試：完整性三個條件各缺一個都是「部分完成」；`writable` 為 `null` 時保留上次的值。
- 三個官方插件與 `spotify`、`qqmusic` 的契約案例在 `fmp-plugins` 的 CI 以固定的 FMP 版本執行（ADR 0015 §決定 6）；私人歌單重送 `required` 的行為以各插件 repo 的 Node 測試守（M3 PR 1 的做法）。
