# M4 音樂庫與同步：ADR 範圍摘要

> 目的：讓 planner 把 M4 拆成 PR 大小的 child task，並把「未定之處」整理成擁有者問題。本檔只彙整既有 ADR、計畫與程式現況，不新增決定；ADR 之間、ADR 與 milestones、ADR 與現況不一致的地方列在 §8，不自行判斷。
> 來源：`.trellis/tasks/09-26-fmp-rewrite/milestones.md` §M4 與「舊版頁面對照」表、`phase2-plan.md`、`docs/audit/questions.md`（B1、B2、B3、B12、M12、E3–E5、E7、E12–E14、E16）與 `features.md`／`data.md`／`sources.md`／`ui.md`、`docs/adr/0009`–`0031`、M2／M3 任務（含 `archive/2026-10/10-15-account-redaction`、`10-15-m3-product-followups`）的 `prd`／`design`／`implement`／`research`、`app/` 現況、`1morr/fmp-plugins`（本機與 FMP 同層的 checkout）、舊版 `lib/`（只摘要行為與位置）、pub.dev API。
> 格式：每則 ADR 分四段——(a) M4 要做的、(b) M4 的驗證、(c) 不在 M4、(d) ADR 已固定的名稱。仿 `m3-scope-digest.md`。
> 「現況」只列存在什麼（檔案加一行），不評論。查證日期 2026-10-15（`main` 在 `14b6d03d`；工作樹有未提交的 `app/test/fixtures/plugins/test_plugin/test_plugin.js` 與各平台 generated plugin 檔變動，與本檔無關）。套件版本於 2026-10-15 查 pub.dev API。

## 0. M4 的權威定義

- **狀態**：`milestones.md:13`——「M4 音樂庫與同步，依賴 M3b，未開始」。M3a（2026-10-13）、M3b（2026-10-15）已完成（`milestones.md:11-12`）。
- **做完**（`milestones.md:120`）：「建歌單、匯入並刷新平台歌單、匯入 Spotify／QQ 歌單。」
- **一句話性質**（ADR 0026 §決定 3 的表，`0026:76`）：M4 =「歌單、匯入並刷新、外部歌單匹配、備份與還原」。依賴 M3（`0026:85` 修訂後為 M3b）。M5 依賴 M4（`milestones.md:14`）。
- **範圍**（`milestones.md:122-124`，只有三條）：
  1. 關聯表與孤兒清理（ADR 0019）；本機歌單（E3）；
  2. 匯入與刷新（E4）；僅元資料來源的匹配（E5）；遠端歌單編輯（E7）；
  3. 首頁排行（E14）；新格式的備份與還原（E16）。
- **「舊版頁面對照」表裡標 M4 的列**（`milestones.md:39,42-46`）：
  - 帳號頁「管理歌單」、粉絲勳章匯入電台 → 「—」，M4（ADR 0031）；
  - 首頁（排行、最近播放、電台區塊）、探索頁、首頁排行設定 → 「首頁與探索；導覽重排」，M4（E14、ADR 0031）；
  - 音樂庫、歌單詳情、建立／編輯歌單 → 「音樂庫」，M4（E3、E7）；
  - 匯入歌單、匯入預覽 → 「音樂庫的匯入與匹配」，M4（E4、E5）；
  - 備份與還原 → 「設定」，M4（E16）；
  - 加入本機歌單、加入遠端歌單 → 「曲目選單」，M4（E3、E7）。
  表頭註明「範圍以各里程碑那一節為準，這裡只是索引」（`milestones.md:28`），但上列有七項不在 §M4 的三條範圍裡（見矛盾 2）。
- **驗收**（`milestones.md:125-127`）：[ ] 兩平台端到端操作；[ ] `opencc` native assets 在各平台建置（ADR 0019）。沒有列 ADR 0016／0017／0019／0028 的測試項（對照 M3 驗收有列，見矛盾 8）。
- **擁有者已定**（`questions.md`）：E3、E4、E5、E7、E14、E16 皆勾「保留」（`questions.md:241-243,245,252,254`）；B1、B2 勾「保留」且有備註——遠端是權威、只往下同步、使用者不能在本地增刪匯入歌單曲目、保留明確標示的遠端操作、匯入歌單的名稱／描述／封面／自動刷新設定可在本地改（`questions.md:115-116,131`）。B12「首頁排行停用某音源仍抓」未勾（`questions.md:126`）但 ADR 0016、0017 已採「停用即不抓」；B3「網易寫入請求偽造 `X-Real-IP`」未勾、「不確定」欄打勾（`questions.md:117`）；M12「歌單使用登入刷新被重新匯入覆寫」未勾（`questions.md:171`），ADR 0019 以「依 ADR 0012 的音源設定」處理。
- **不是 M4**：舊資料匯入與舊備份檔匯入（M5，ADR 0010 §決定 4）；下載與 `downloads` 表（M6）；歌詞與 AI 插件（M7，含歌詞匹配結果進備份）；托盤與全域快捷鍵（M8）；關於頁與使用者指南（M9）。來源失效時「另存為本地歌單」、曲目收藏、網易「疑似換版本」偵測列在功能凍結待辦，不設計（`0019:80`、`phase2-plan.md:34`）。
- **ADR 約束**：根 `AGENTS.md` 規定「`app/` 沒有已採納的 ADR 涵蓋就不寫程式碼」。ADR 0019、0031、0028 涵蓋資料模型、Mix、能力清單，但沒有首頁／音樂庫／探索頁的 UI、`importPlaylist`／`libraryRead`／`libraryWrite`／`charts` 的 DTO、E16 的格式（見 §9）。

---

## 1. 逐 ADR 摘錄

### ADR 0019 — 音樂庫與同步（M4 的主體）

**(a) M4 要做的**
- 資料模型（§決定 1，`0019:35-43`）：
  - `playlists`（`kind`：`local`／`imported`／`mix`，名稱不唯一）；
  - `playlist_remote`（插件、遠端 id、擁有者、名稱／描述／封面的本地覆寫旗標、上次刷新時間與結果、狀態）；
  - `playlist_entries`（歌單 FK 連帶刪除、位置、曲目鍵 FK、遠端項目 id），**不對（歌單, 曲目鍵）設唯一**（YouTube 歌單可含重複影片）；
  - `tracks`（ADR 0005 格式照搬，M2 已建）；
  - `track_origins`（原始平台與 id）；
  - `match_results`（選定曲目、分數、使用者改選）。
  - 開資料庫 `PRAGMA foreign_keys = ON`（M1 已做，`app_database.dart` 的 `beforeOpen`）；孤兒曲目以查詢判斷（沒有被歌單項目、佇列、下載紀錄參照），登記在啟動維護清單（M2 已登記 `orphan-tracks`）。
  - 更正（2026-10-01，`0019:44`）：`tracks` 在 M2 先建，M4 只加欄位與其他表；孤兒的參照者另含播放歷史。
- 刷新（§決定 2，`0019:45-51`，經插件 `importPlaylist`，排程見 ADR 0017，登入依 ADR 0012）：
  - 以曲目鍵比對：遠端有本地無則新增；本地有遠端無則**從該歌單移除**（下載檔不刪）；順序完全照遠端；
  - 曲目元資料與可用狀態照遠端更新，遠端標失效的曲目保留並標「已失效」；
  - 歌單名稱、描述、封面未在本地覆寫就跟遠端；
  - 任何一頁失敗或筆數不足時只新增與更新、不移除，歌單頁顯示「上次刷新：部分完成」；
  - 抓一頁寫一頁、每頁一個 transaction 加刷新代際，完整抓完後一次套用移除與順序；
  - 重新匯入同一張遠端歌單等於刷新，不覆寫本地設定（M12）。
- 來源失效（§決定 3，`0019:52-53`）：遠端 `NotFound` 或無權限時標「來源失效」、停止自動刷新、保留唯讀副本並提供「重試」；自動刷新不跳 toast，只更新歌單頁狀態（ADR 0013）。
- 遠端操作（§決定 4，`0019:54-58`，插件 `libraryWrite`，只對已登入且具備能力的音源出現入口）：
  - 「從遠端歌單移除」有確認框，先寫遠端、成功後刪本地、再背景刷新，部分成功列出失敗項；
  - 「加入遠端歌單」在對話框勾選後直接送出，不重複加入已存在的曲目，不加確認框；
  - 本地「加入歌單」只列 `local` 歌單；匯入歌單的曲目不能在本地增刪或重排。
- 僅元資料來源的匯入（§決定 5，`0019:59-61`，Spotify、QQ 等只有 `importPlaylist` 的插件）：逐首以共用評分核心在使用者設定的目標音源中搜尋，**保留前 5 名、第一名自動選**；匯入預覽頁可改選、重搜、排除；確認後建立 `local` 歌單並寫入 `match_results` 與 `track_origins`；自動匹配與手動重搜同一套評分；節流交給網路層的每插件限流（ADR 0013）。
- 共用評分核心（§決定 6，`0019:62-65`，宿主 Dart，歌詞共用）：正規化 NFKC（`unorm_dart`）→ 小寫 → 繁簡統一（`opencc`）→ 去裝飾標點與空白 → 括號內容單獨比對；相似度 `string_similarity`（Dice）；時長以「10 秒或 5% 取較寬」為硬門檻再連續給分；多歌手拆開取最佳；不使用播放量等來源特有訊號。

**(b) M4 的驗證**（`0019:84-88`）
- 單元測試：刷新差異（新增、移除、順序、元資料、覆寫旗標、部分失敗不移除、重複影片保留、來源失效停止自動刷新、重新匯入不覆寫設定）；評分核心（全半形、繁簡、括號、時長門檻、多歌手；自動與手動重搜同分）。
- 資料庫測試：外鍵連帶刪除、孤兒清理只刪無人參照的曲目、刷新中途失敗後的一致性。
- 插件契約（ADR 0015）：`importPlaylist` 分頁與完整性回報、`libraryWrite` 的錯誤對應。

**(c) 不在 M4**：來源失效時另存為本地歌單、曲目收藏、網易疑似換版本偵測（`0019:80`）；歌詞端如何使用評分核心（歌詞 ADR，M7）；舊資料匯入把整數陣列與反向欄位轉成關聯表、換算覆寫旗標（M5，`0019:78`）。

**(d) 已固定的名稱**：`playlists`、`playlist_remote`、`playlist_entries`、`tracks`、`track_origins`、`match_results`；`kind` 值 `local`／`imported`／`mix`；套件 `unorm_dart`、`opencc`、`string_similarity`；否決 `fuzzywuzzy`（GPL-2.0）；UI 字串「上次刷新：部分完成」「已失效」「來源失效」「從遠端歌單移除」「加入遠端歌單」「重試」。

---

### ADR 0031 — 電台與 Mix 的入口（M4 接手的部分）

**(a) M4 要做的**（`0031:62-63`「之後要注意」，`0031:41`）
- 粉絲勳章匯入電台（`0031:24` 說那是「帳號的資料讀取（`libraryRead` 一類），與 M4 的帳號歌單匯入同一批做」）。
- 首頁的電台區塊。
- 歌單卡「Mix 播放」與匯入 Mix 簡寫。
- 導覽重排：現行順序 搜尋｜歷史｜電台｜設定（手機底部 4 項），「M4 加音樂庫與首頁時整體重排」（`0031:41`）。
- Mix 的歌單形態：`playlists.kind = mix` 存同一對 Mix 身分（插件 id, `mixId`）（`0031:54`、`0028:52`）。

**(b) M4 的驗證**：ADR 0031 §如何確認（`0031:69-75`）屬 M3b，已完成；M4 無條目。

**(c) 不在 M4**：舊版 `RadioStation.isFavorite`、`lastPlayedAt` 沒有讀者，不匯入（`0031:64`）；「佇列非空時先確認」開始 Mix 是日後問題（`0031:65`）。

**(d) 已固定的名稱**：`radio_stations`（M3 已建）、`QueueMode.mix`、`MixSession`、Mix 身分＝（插件 id, `mixId`）、曲目選單「開始 Mix」。

---

### ADR 0017 — 背景排程器（M4 新增兩種工作）

**(a) M4 要做的**
- 排程器本體與電台工作已在 M3b 完成（`lib/scheduler/background_scheduler.dart`）。M4 加兩種工作：首頁排行、匯入歌單自動刷新（`0017:27`）。
- 規則（`0017:34-42`）：工作宣告含 id、所屬插件（可空）、間隔（空＝關閉）、執行函式；「上次成功時間」存資料庫；只在 `resumed`／`inactive` 且 `Online` 才跑；全域最多 2 個、同一插件依序；**匯入歌單一次刷一張**；失敗依 1、2、4… 分鐘退避、上限為該工作間隔，`RateLimited.retryAfter` 優先；手動刷新不看間隔；插件停用／移除、榜單在首頁停用（B12）、歌單改為不啟用、間隔設為關閉時立即移除工作，代際檢查丟掉過期結果。
- 設定（§決定 6，`0017:43-44`）：排行刷新間隔 30／60／120／240 分或關閉（預設 60）；匯入歌單每張 1／6／12／24／48／72／168 小時或不啟用（新匯入預設 24 小時）。「舊值原樣匯入」（M5）。電台間隔已在 M3 加（`network_settings.radio_status_interval_minutes`）。
- 孤兒曲目清理已在啟動維護清單；M4 在同一個查詢加歌單項目（`tracks_repository.dart:62-66`、M2 `design.md:158`）。

**(b) M4 的驗證**：排程器測試已在 M3b 完成；M4 新工作需在既有假時鐘測試模式下加案例（`0017:57-64` 的項目對新工作的適用性 ADR 未逐條寫）。

**(c) 不在 M4**：更新檢查、`workmanager`、桌面縮到托盤繼續跑（否決）。

**(d) 已固定的名稱**：`BackgroundScheduler`、工作 id 現行寫法 `radio-status:<pluginId>`、`live-info`（`app/AGENTS.md:1102`）、`scheduler_runs` 表（`tables.dart:354-366`）。M3 把排行與匯入歌單的間隔設定延到 M4，理由「現在加就是沒有讀者的欄位」（M3 `design.md:605`，`app/AGENTS.md:1102`）。

---

### ADR 0016 — 快取與離線（排行快取）

**(a) M4 要做的**：排行快取——鍵為插件＋榜單 id；先顯示快取並標「更新於 …」再背景刷新；只抓已啟用插件且在首頁啟用的榜單（B12）；停用就刪掉快取（`0016:42`）。快取庫是 `cache.db`（M2 已有，`lib/data/cache/`）。離線時歌詞與排行顯示快取，沒有就顯示離線狀態（`0016:48`）；音樂庫、歌單、設定離線完整可用（`0016:47`）。
**(b) 驗證**：ADR 0016 §如何確認對排行快取沒有專條（M3 digest §ADR 0016「排行快取（M4）」）。
**(c) 不在 M4**：已下載曲目離線行為（M6）；歌詞快取（M7）。
**(d) 名稱**：`cache.db`、鍵＝插件＋榜單 id、「更新於 …」。

---

### ADR 0028 — 宿主 API v1（M4 的四個能力）

**(a) M4 要做的**（`0028:66`）：「M4 的 `importPlaylist`、`libraryRead`、`libraryWrite`、`charts` 照同樣的方式加，凍結前定完」。照同樣方式＝在 v1 內加選填欄位與新匯出，`apiVersion` 不變；`fmp-plugins` 同一輪跟上（`0028:43`，凍結點是 M9）。
- 同步點（`0028:57`）：每加一個欄位或匯出，同一 PR 改 `fmp-plugin.d.ts`、Dart 端 shapes、`SourcePlugin` 方法與 `FmpChecks`；`SourcePlugin` 的方法只在引入它的 PR 加。
- `checks.json`（`0028:55`）：每個能力一個鍵，案例形狀與 `search` 相同（`input`＋`expect`）；案例可標 `requiresLogin: true`——契約測試照常重播；健康檢查與 App 內錄製遇到它時，已登入就用已存憑證跑，未登入標「略過」；命令列錄製略過它。
- `HttpRequest.idempotent?`（`0028:44`）：POST 查詢可標語意冪等。`credentialsAttached`（`0028:45`）：插件的「憑證無效」判定只在它為真的回應上成立。
- Mix 身分與 `mix` 的 cursor 契約已定（`0028:52`）。
**(b) 驗證**：`type_definitions_test.dart`（d.ts 與 Dart 一致含變異案例）、各能力自己的 `*_capability_test.dart`（`0028:73` 更正）、`checks_test.dart`、`contract_runner_test.dart`、三個官方插件的契約案例在 `fmp-plugins` CI 以固定 FMP 版本執行（`0028:70-77`）。
**(c) 不在 M4**：`lyrics`（M7）；若量到被取代請求造成問題再設計呼叫 id（需新 ADR）。
**(d) 名稱**：能力名 `importPlaylist`、`libraryRead`、`libraryWrite`、`charts`（`fmp-plugin.d.ts:22-26`、`plugin_manifest.dart:24-27` 已在列舉裡，但沒有 DTO、匯出或 `SourcePlugin` 方法，見 §4.1）。

---

### ADR 0014 — 腳本插件（匹配、插件類別）

**(a) M4 要做的**
- 僅元資料來源（Spotify、QQ 匯入）是與可播放音源並列的「類別」，**所有來源都是 JS 腳本＋manifest，App 不內建任何來源**（§決定 2，`0014:34-36`）。
- 匹配（§決定 9，`0014:55-57`）：宿主一份共用評分核心，歌單匯入與歌詞共用；**對所有啟用的目標來源比較取最高分，同分依使用者排序；目標來源集合由使用者設定，自動與手動重搜一致；結果持久化，使用者改選後不再重算；匹配失敗保留並標示**。
- 能力清單第 4 條（`0014:38`）：`importPlaylist`、`libraryRead`、`libraryWrite`、`charts` 的名稱；同一能力有多個提供者時 UI 全部列出（`0014:40`）。
**(b) 驗證**（`0014:80-83`）：manifest 能力與實際匯出一致；契約測試涵蓋遮蔽、`AuthRequirement`、錯誤對應；lint `fmp_source_id_literal`（`source_id_literal.dart` 的官方 id 清單，M3 已加 YouTube／網易；Spotify／QQ 的 id 字串 ADR 未寫）。
**(c) 不在 M4**：歌詞源 `lyrics`（M7）。
**(d) 名稱**：`SourcePlugin`、manifest 欄位、`1morr/fmp-plugins`、`index.json`。官方 id 現有 `bilibili`、`youtube`、`netease`（`fmp-plugins/index.json`）。

---

### ADR 0012 — 網路與帳號（歌單相關的認證）

**(a) M4 要做的**：`AuthRequirement.required`＝「寫入遠端歌單、讀收藏夾與私人歌單；未登入就不發請求，直接回『需要登入』」；`userPreference`＝「搜尋、排行、詳情、串流解析、下載詳情、歌單刷新、電台、Mix；已登入且開關開啟才帶」（`0012:35-36`）；Spotify（embed 頁）、QQ（公開歌單）標 `never`，「抓頁面可能隨改版失效，由音源健康檢查涵蓋」（`0012:55`）。「以登入身分瀏覽與播放」每音源一個開關（`source_settings.browse_as_logged_in`，M3 已建）控制所有 `userPreference`，包含排行與歌單刷新。
**(b) 驗證**：`AuthRequirement` 三種標記的注入測試（M3 已有）；M4 需要的新案例（歌單刷新、排行用 `userPreference`；libraryRead／libraryWrite 用 `required`）ADR 未逐條列。
**(c) 不在 M4**：Linux 與 `webview_cef`。
**(d) 名稱**：`required`／`userPreference`／`never`、`credentialsAttached`（`0028:45`）。

---

### ADR 0011 — 設定（「音樂庫與同步」組）

**(a) M4 要做的**：八個設定組之一「音樂庫與同步」（`0011:46`）在 M4 引入，**欄位在引入它的里程碑定案**（`0011:56`、`0026:68`）；每組一張單列表、每欄位有型別、欄位為空＝使用者沒設定過、預設只在 Notifier 套用；**設定包含在備份中**（`0011:47`）。現況只有「外觀」「播放」「網路」「開發者」四張單列表，另有每音源設定表（見 §4.1）。排行／匯入歌單間隔、匹配目標來源集合、首頁排行來源順序與啟用等欄位歸哪一組，ADR 沒寫（未定之處 19）。
**(b) 驗證**：設定測試（寫入使用者值後改預設，仍讀到使用者值）、migration 不改使用者設定過的值（ADR 0010 §決定 3）。
**(c) 不在 M4**：「下載」「歌詞」「桌面」三組。
**(d) 名稱**：組名「音樂庫與同步」（`0011:46`）；「診斷包」不含歌單內容（`0011:44`）。

---

### ADR 0010／0025 — 備份（M4 的 E16 與已存在的資料庫檔備份）

**(a) M4 要做的**
- ADR 0010 影響範圍列「備份格式」（`0010:5`），但 §決定 1–4 沒有定義備份格式；只在 §決定 4 寫「舊備份檔可匯入，與資料庫匯入共用同一套轉換」（`0010:59`，M5）。
- ADR 0025 §決定 9 的更正（2026-10-08，M3 PR 0，`0025:152`）：自動備份＝以 SQLite `VACUUM INTO` 把資料庫複製到 `backups/fmp-<時間>.db`；「從備份還原」＝換回該檔並重啟；憑證不在資料庫，還原後要重新登入；**「M4 的 E16 匯出格式另定」**。已實作於 `app/lib/data/database/database_backups.dart`、`app/lib/app/data_reset.dart`，入口在 Debug 頁（`app/lib/ui/debug/debug_data_actions.dart`）。
- E16「備份與還原」勾保留（`questions.md:254`）；ADR 0026 的 M4 說明「備份與還原」（`0026:76`）；`milestones.md:124`「新格式的備份與還原」；舊版入口在設定「備份→匯出、匯入」（`features.md:201,223`）。
- 設定在備份內（`0011:47`）；`layout_state` 不收（M2 `design.md:214`、`app/AGENTS.md:436`）；AI key 不進備份（`0021:67`，M7）。
- ADR 0015 §決定 8（`0015:75`）：開發版資料預設空白，真實資料以舊資料匯入或「還原正式版備份」帶入。
**(b) 驗證**：ADR 0010／0025 對 E16 無專條；M3 的重設與還原測試覆蓋資料庫檔副本（`0025:206`）。
**(c) 不在 M4**：舊備份檔匯入（M5）。
**(d) 名稱**：`backups/`、`fmp-<UTC 時間>.db`、`VACUUM INTO`、`DataReset`、`DatabaseBackups`；舊格式檔名 `fmp_backup_<ISO 時間>.json`、`kBackupVersion = 5`（舊版，見 §5.7）。

---

### ADR 0018 — 播放核心（歌單的播放入口）

**(a) M4 要做的**：歌單「全部」只加入佇列（D2）；所有加入方式檢查 10,000 首上限（`0018:39`，M2 `design.md:419,455`：「歌單的『全部加入佇列』在 M4」，整批拒絕不部分加入，「M4 的歌單『全部』沿用」）。Mix 歌單的「播放」把 Mix 取代整個佇列（ADR 0031 §決定 9，M3 已有 `startMixFrom`）。
**(b) 驗證**：10,000 首上限對歌單「全部」的適用性 ADR 未寫專條。
**(c) 不在 M4**：隨機加入（舊版歌單卡有「隨機加入」，`features.md:61`；ADR 0018 沒有）。
**(d) 名稱**：`QueueFull` 事件（M2 `design.md:419`）。

---

### ADR 0026／0027／0015／0013／0009／0024／0020／0021（交界）

- ADR 0026 §決定 2（`0026:66-68`）：縱向切片；**每個新增資料表的里程碑，同時補上那張表的舊資料匯入（M5 起）**；各組設定欄位在引入它的里程碑定案。§決定 1（`0026:53-64`）：里程碑任務開工走 brainstorm，擁有者核准一次 prd／design／implement；PR 子任務一個分支一個 PR，合併後 `app/` 可編譯、測試全綠；里程碑驗收＝Android 與 Windows 各做一次端到端操作。
- ADR 0027（`0027:36-41`，見 M3 digest）：預設「重播」；改動本身是插件、網路層、登入、或正在錄 fixture 時用「真實」。
- ADR 0015 §決定 7 更正（#254，`0015:71`）：需要登入的案例錄到的回應帶帳號資訊，不原樣提交，fixture 一律手寫或錄後刪減並在 `meta.edited` 寫明；閘門在插件庫 `test/login_fixtures_test.dart`。
- ADR 0013（`0013:61`）：背景工作不跳 toast，只在對應畫面顯示狀態；部分成功要標出失敗的音源或項目。
- ADR 0009 §決定 6（`0009:51`）：`file_picker` 五平台共用；ADR 0025 `:129,161` 已更正 `file_selector` 改用 `file_picker`。`FileDialogs`（`app/lib/platform/files/files.dart:6-20`）已有 `pickFile`、`saveFile`、`pickDirectory`。
- ADR 0024：沒有首頁、音樂庫、探索頁、歌單詳情的版面；§決定 3 導覽表只定到 compact／medium／expanded／large／extraLarge 的導覽元件；`0024:157` 只在 a11y 測試清單裡提到「首頁、搜尋、歌單、播放頁、設定」。
- ADR 0020 §決定 7（`0020:58`）：`downloads` 表以曲目鍵關聯，孤兒判定納入它（M6）；刷新移出歌單不刪下載。
- ADR 0021（`0021:67`）：AI key 存插件憑證區，不進 log、不進備份。

---

## 2. 前面里程碑留給 M4 的待辦

| # | 待辦 | 來源 |
|---|---|---|
| 1 | Mix 的歌單形態（`playlists.kind = mix`）、歌單卡「Mix 播放」、匯入 Mix 簡寫（M3 只做曲目選單「開始 Mix」） | ADR 0031 `:62-63`；M3 `design.md:84`；`prd.md:34` |
| 2 | 粉絲勳章匯入電台、首頁的電台區塊 | ADR 0031；M3 `design.md:85`；`prd.md:33` |
| 3 | `importPlaylist`、`libraryRead`、`libraryWrite`、`charts` 四個能力 | M3 `design.md:86`；ADR 0028 `:66` |
| 4 | 新格式的備份與還原（E16）；M3 的重設資料用資料庫檔副本 | M3 `design.md:87,697`、`prd.md:71`、`research/m3-decisions.md:14` |
| 5 | 排行與匯入歌單的刷新間隔設定「跟 M4 的工作一起加」 | M3 `design.md:83,605`、`prd.md:72`、`implement` 與 `app/AGENTS.md:1102` |
| 6 | 帳號頁的「帳號歌單匯入」 | M3 `prd.md:70`；`milestones.md:39` |
| 7 | 導覽整體重排（M3 順序 搜尋｜歷史｜電台｜設定，手機底部 4 項） | M3 `design.md:624`、`prd`；ADR 0031 `:41` |
| 8 | **M4 匯入要帶分 P 兩欄**：帶 cid 卻沒帶 `partIndex`／`parentTitle` 的 upsert 會照「最後寫入為準」清掉那一 P 的兩欄 | M3 `implement.md:505`（審查發現） |
| 9 | 佇列與歷史不分組；「真的分組在 M4 歌單詳情（舊版也只有那裡有）」 | M3 `implement.md:504` |
| 10 | 隔離環境只把已存憑證當 `loginVerify` 的輸入；M4 出現「需要登入、但不是 login」的案例時，隔離環境要帶上該音源憑證 | M3 `implement.md:545,557`；`app/AGENTS.md:1093` |
| 11 | 網路紀錄的 query 可能帶使用者 id（B 站 `mid`、`uid`、`vmid` 不在鍵名名單）；「M4 前開 issue 擴充名單（要重跑各插件的契約測試）」 | M3 `implement.md:563` |
| 12 | `recordCase` 的換值與閘門只在結果是 `LoginAccount` 時執行；M4 的收藏、歌單案例回應含自己的 creator 名稱、id、頭像，今天沒有閘門；要讓 `recordCase` 從 `accounts` 列取得帳號（與第 10 條一起做）；重播時自己的 id 是整段 `***`，`fixtureUrlMatches` 視為萬用值 | `archive/2026-10/10-15-account-redaction/design.md:206-212`；其 `prd.md:40` |
| 13 | M4 新插件選哪個端點未定（網易 `/api/user/playlist?uid=` query 或 `/api/v1/user/detail/<uid>` 路徑）；鍵名名單遮不到路徑 | account-redaction `design.md:60` |
| 14 | B 站 `mid` 於 UP 主頁與藝人 id 要用別人的 `mid`，契約測不到 | account-redaction `design.md:86` |
| 15 | `layout_state` 不屬於任何設定組，M4 備份不收 | M2 `design.md:208-215`；`app/AGENTS.md:436` |
| 16 | 孤兒查詢要加歌單項目；`playlist_entries` 等參照 `tracks` 的表要建 `track_key` 索引（1 萬首佇列加 1 萬孤兒從 9.3 秒降到 14 ms） | `tracks_repository.dart:42-44`；M2 `design.md:158,606`；`app/AGENTS.md` 資料層段（孤兒查詢由後加表的 PR 各自加入） |
| 17 | M2 驗收未實機驗的項目（鎖定畫面控制、Windows 實體媒體鍵等）與 M4 無直接關係 | M3 digest §2 第 20 條 |

---

## 3. 與其他里程碑的交界

| 交界 | 內容 | 出處 |
|---|---|---|
| M4→M5 | `legacy_import` 要把舊 `Playlist`（整數陣列與反向欄位）轉成 `playlists`／`playlist_entries`，換算 `hasCustomCover`→覆寫旗標；舊 `refreshIntervalHours`／`notifyOnUpdate`／`useAuthForRefresh`／`isMix`／`mixPlaylistId`／`mixSeedVideoId` 要對照 M4 欄位；每個新增資料表同時補舊資料匯入 | `0019:78`；`0026:67`；舊 `playlist.dart`（§5.1） |
| M4→M5 | 舊備份檔（JSON、`kBackupVersion = 5`）匯入「與資料庫匯入共用同一套轉換」；M4 的新格式備份要讓 M5 知道舊格式（§5.7） | `0010:59`；`milestones.md:131` |
| M4→M5 | 歌單名稱在新版不唯一，舊 Isar `Playlist.name` unique、舊備份匯入同名略過 | `0019:36`；`data.md:38`；`backup_service.dart:461-470` |
| M4→M6 | 孤兒查詢要加 `downloads`；下載依歌單分類的「已下載」頁分類由資料庫關聯算出；歌單詳情的下載按鈕 | `0020:49,58`；`tracks_repository.dart:42-44` |
| M4→M7 | 評分核心歌詞共用（「歌詞另加同步歌詞加分」）；歌詞匹配結果進備份；備份不含 AI key | `0014:55`；`0019:80`；`0021:67` |
| M4→M9 | 宿主 API v1 凍結（M9 切換）；新能力 DTO 要在 M9 前定完；`fmp-plugins` 的 `FMP_REF` 要隨宿主 API 更新 | `0028:43,66`；`fmp-plugins/.github/workflows/ci.yml:28` |
| M3→M4 | 已完成的基礎：`tracks`、`radio_stations`、`scheduler_runs`、`accounts`、`source_settings`、`BackgroundScheduler`、`DatabaseBackups`／`DataReset`、`FileDialogs`、`TrackRowMenu`、`startMixFrom`、`InstalledPlugins.enabled` | §4.1 |
| 平台 | Linux、macOS、iOS 實作屬平台任務（Mac 到貨後），M4 只需 Android 與 Windows；`opencc` 的建置驗證卻要涵蓋「各平台」（`milestones.md:127`）——見矛盾 5 | `milestones.md:19-21,127` |

---

## 4. 現況（查證 2026-10-15）

### 4.1 `app/`

| 檔案:行 | 一行 |
|---|---|
| `app/lib/data/database/app_database.dart:48` | `schemaVersion => 14`；`:60-146` migration 到 v14；`beforeOpen` 開 `PRAGMA foreign_keys = ON`；失敗整個回滾 |
| `app/drift_schemas/app_database/` | 每版快照 `drift_schema_v*.json`（含 v14） |
| `app/lib/data/database/tables.dart:16-396` | 現有表：`appearance_settings`(16)、`network_settings`(33)、`playback_settings`(54)、`installed_plugins`(83)、`plugin_indexes`(116)、`plugin_storage`(132)、`tracks`(151)、`queue_entries`(186)、`player_state`(208)、`play_history`(245)、`layout_state`(262)、`accounts`(288)、`source_settings`(314)、`developer_settings`(330)、`scheduler_runs`(354)、`radio_stations`(371)。**沒有** `playlists`、`playlist_remote`、`playlist_entries`、`track_origins`、`match_results`，沒有搜尋歷史表，沒有「音樂庫與同步」設定表 |
| `app/lib/data/database/tables.dart:151-173` | `tracks`：`track_key` 主鍵、`source_type_id`、`source_id`、`cid`、`title`、`uploader`、`duration_ms`、`artwork_json`、`updated_at`、`part_index`、`parent_title`；**沒有**可用／失效狀態欄位、觀看數、擁有者 id |
| `app/lib/data/repositories/tracks_repository.dart:18,45-66` | `upsert(Iterable<TrackInfo>)`；`deleteOrphans()` 的條件現在只有 `queue_entries` 與 `play_history`（註解寫歌單項目 M4、下載 M6 各自加進來） |
| `app/lib/data/repositories/` | `account_`、`appearance_settings_`、`database_inspector`、`developer_settings_`、`layout_state_`、`network_settings_`、`play_history_`、`playback_settings_`、`plugin_`、`plugin_storage_`、`queue_`、`radio_`、`scheduler_runs_`、`tracks_` 各一個 repository；沒有歌單 repository |
| `app/lib/data/database/database_backups.dart:1-120` | 資料庫檔備份：`VACUUM INTO` 到 `backups/fmp-<UTC>.db`；`create`／`list`／`restore`／`erase`；`restore`／`erase` 先關閉資料庫 |
| `app/lib/app/data_reset.dart:17-120` | `DataReset`：`backUp`、`backups`、`resetAndRestart`、`restoreAndRestart`；還原先清 secure storage 與登入 WebView（備份不含憑證） |
| `app/lib/ui/debug/debug_data_actions.dart:83-120,235-297` | Debug 頁「從備份還原」對話框與流程（唯一的備份 UI；設定頁沒有「備份」區） |
| `app/lib/app/startup_maintenance.dart:20-67` | 啟動維護清單三項：`log-retention`、`diagnostics-temp`、`orphan-tracks` |
| `app/lib/scheduler/background_scheduler.dart:1-80` | `SchedulerJob{id, interval, run, pluginId}`、`JobContext.isCurrent`、`RunNowResult{completed, offline, unknown, alreadyRunning}`、`maxConcurrentJobs = 2`、`firstBackoff = 1 分` |
| `app/lib/radio/radio_status_jobs.dart:41,72-185` | 唯一的真工作：`radio-status:<pluginId>`；間隔 0＝登記為 `interval: null`（只能手動）；`runNow` 手動刷新 |
| `app/lib/data/database/tables.dart:33-45` | `network_settings` 只有 `cache_limit_mb`、`radio_status_interval_minutes`；沒有排行或匯入歌單的間隔欄位 |
| `app/lib/ui/shell/app_shell.dart:34,255-290` | `ShellDestination { search, history, radio, settings }`；`IndexedStack` 裡四頁：`SearchPage`、`HistoryPage`、`RadioPage`、`SettingsPage`；compact `NavigationBar`、medium／expanded `NavigationRail`、large 以上 `NavigationDrawer` |
| `app/lib/ui/settings/settings_page.dart:23-34` | `SettingsSection { accounts, appearance, playback, network, plugins, about }`；沒有「音樂庫與同步」「備份」；開發者模式下尾端多一列 Debug |
| `app/lib/ui/accounts/accounts_section.dart` | 帳號區（登入、登出、「以登入身分瀏覽與播放」）；沒有「管理歌單」 |
| `app/lib/ui/tracks/track_row_menu.dart`、`start_mix.dart` | 曲目列選單（搜尋、歷史、佇列共用）；「開始 Mix」（`canStartMixProvider` 依插件宣告 `mix`）；**沒有**「加入本機歌單」「加入遠端歌單」；`lib/ui/` 內沒有多選模式（grep `selection` 只命中 Debug 頁文字選取與錯誤詳細頁） |
| `app/lib/ui/radio/radio_page.dart` | 電台頁（M3b 完成）；沒有首頁電台區塊、沒有粉絲勳章匯入 |
| `app/lib/ui/` 目錄 | `accounts artwork debug empty_state errors format history i18n layout offline player plugins radio search settings shell theme toast tracks`；沒有 `home`、`explore`、`library` |
| `app/lib/` 頂層目錄 | `app core data domain i18n platform playback plugins radio scheduler settings ui`；沒有 `library`、`import` |
| `app/lib/domain/` | `account`、`appearance`、`developer`、`loop_mode`、`mix_identity`、`output_device`、`playback_speed`、`player_mode`、`player_tab`、`radio`、`stream_preferences`、`track_info`、`track_key`；沒有歌單型別 |
| `app/lib/plugins/manifest/plugin_manifest.dart:24-27,40-43` | 能力列舉已含 `importPlaylist`、`libraryRead`、`libraryWrite`、`charts` |
| `app/lib/plugins/types/fmp-plugin.d.ts:22-26,481-518` | 能力 union 含四個名稱；`FmpPluginExports` 的匯出只有 `search`、`resolveStream`、`liveSearch`、`liveRoomFromUrl`、`liveStatus`、`resolveLive`、`mix`、`multiPart`、`trackDetail`、`loginQrStart`、`loginQrPoll`、`loginVerify`、`loginRefresh`；**沒有** `importPlaylist`、`libraryRead`、`libraryWrite`、`charts` 的 DTO 或匯出；`FmpChecks`（`:535-`）也沒有對應鍵 |
| `app/lib/plugins/types/fmp-plugin.d.ts:285-298` | `MixContinueQuery` 的 `cursor` 為必填字串；`MixBatch.cursor` 可 `null` |
| `app/lib/plugins/source_plugin.dart:12-63` | `SourcePlugin` 方法：`search`、`resolveStream`、`liveSearch`、`liveRoomFromUrl`、`liveStatus`、`resolveLive`、`mix`、`multiPart`、`trackDetail`、`loginQrStart`、`loginQrPoll`、`loginVerify`、`loginRefresh`；沒有歌單相關方法 |
| `app/pubspec.yaml` | 已有：`archive ^4.5.2`、`file_picker ^13.1.0`、`share_plus ^13.3.1`、`url_launcher ^6.3.3`、`qr_flutter`、`flutter_secure_storage ^11.2.0`、`flutter_inappwebview 6.2.0-beta.3`、`drift ^2.35.0`、`flutter_js 0.8.7`；**沒有** `unorm_dart`、`opencc`、`string_similarity`、`file_selector`；SDK `^3.13.4` |
| `app/lib/platform/platform_capabilities.dart:61-108` | 能力欄位含 `files`(88)、`loginWebView`(92)、`urlOpener`(96)、`restartsItself`(100)、`shareFiles`(104)、`pluginDevTools`(108) |
| `app/test/fixtures/plugins/test_plugin/`、`http_test_plugin/` | 重播模式用的測試插件（`fmp-test`）；目前工作樹有未提交修改 |
| `app/AGENTS.md:1101-1121` | 排程器規則：週期計時器只准在 `lib/scheduler/` 與 `lib/playback/`；排程器不 import `ui/`、`radio/` 等；「排行與匯入歌單的刷新在 M4」 |
| `.trellis/spec/app/data/index.md` | 加表、改 schema、寫 repository 的做法（每版快照、migration 測試） |

### 4.2 `1morr/fmp-plugins`（本機與 FMP 同層的 checkout，HEAD `9380554`）

| 內容 | 一行 |
|---|---|
| `index.json`（`indexVersion: 1`） | `bilibili` 1.5.0：`search, resolveStream, multiPart, trackDetail, live, login`；`netease` 1.3.0：`search, resolveStream, trackDetail, login`；`youtube` 1.2.1：`search, resolveStream, mix, trackDetail, login`。**三個插件都沒有** `importPlaylist`、`libraryRead`、`libraryWrite`、`charts`；沒有 Spotify、QQ 插件 |
| `bilibili/`、`netease/`、`youtube/` | 各有 `src/`、`build.mjs`、`checks.json`、`fixtures/`、`README.md`；`checks.json` 現有鍵：bilibili 含 `search`、`resolveStream`、`live`、`login`、`multiPart` 等；無歌單／排行案例 |
| `.github/workflows/ci.yml` | 契約測試以 `FMP_REF: 9d22d95cc36f2c024fd0a8471295b157945606c9` checkout FMP 重播（不連網）；檢查 index 是最新的 |
| `test/login_fixtures_test.dart`、`test/build_index_test.dart`、`tool/build_index.dart` | login fixture 手寫／刪減閘門；index 產生與檢查 |
| `netease/src/plugin.js:65-69` | 網易插件取流已用 `X-Real-IP: 118.88.88.88`（M3 B3 讀取側的結果）；寫入請求的處理屬 `libraryWrite`，尚無 |
| `youtube/src/mix.js` | YouTube Mix 的 `/next` 續取實作（M3b） |

### 4.3 套件（pub.dev API，2026-10-15）

| 套件 | stable 版本／發佈 | 授權 | native／平台 | 備註 |
|---|---|---|---|---|
| `unorm_dart` | 0.3.3，2026-10-04 | MIT | 純 Dart，無依賴；tags 含 android、ios、windows、linux、macos、web | Unicode 18.0 的 NFC／NFD／NFKC／NFKD；likes 31 |
| `string_similarity` | 2.2.0，2026-04-04 | MIT | 純 Dart，無依賴；五平台＋web | Dice 係數；likes 129，pub points 160/160 |
| `opencc` | stable 1.1.0，2024-10-01；另有預發佈 `1.2.0-dev.1`，2025-08-01 | Apache-2.0（pub.dev tag） | 靠 native assets（建置時從 GitHub 下載預編譯庫）；pub.dev tags 列 android、ios、windows、linux、macos；1.1.0 的依賴為 `ffi ^2.1.3`、`native_assets_cli ^0.8.0`、`glob`、`path`，SDK `^3.3.0`；likes 0 | **GitHub release `opencc-v1`（2025-08-01）的資產只有 `opencc-linux-arm64.zip`、`opencc-linux-x64.zip`、`opencc-macos-x64.zip`、`opencc-windows-arm64.zip`、`opencc-windows-x64.zip`**——沒有 Android、iOS、macOS arm64（以 GitHub API 查得）；`main` 的 README 寫 native assets 在 dart 3.8 後僅 dev 渠道、要設環境變數 `OPENCC_SHARED_DIR=.dart_tool/share` 讓字典資源可被載入；`main` 的 pubspec 是 1.2.0-dev.1，依賴 `hooks ^0.19.0`、`code_assets ^0.19.0`、`sdk: 3.10.0-14.0.dev`；repo 最後 push 2025-08-07 |

「是否與 `app/` 的 Dart `^3.13.4`、Flutter 當前 stable 的 native assets（hooks）相容」未實測，標「待查」。

---

## 5. 舊版行為（`lib/`，已凍結；供「看成熟產品怎麼做」參考）

### 5.1 歌單資料模型
- `Playlist`（Isar）：`name`（unique）、`description`、`coverUrl`、`hasCustomCover`、`sourceUrl`（非空＝匯入）、`importSourceType`、`refreshIntervalHours`、`lastRefreshed`、`notifyOnUpdate`（預設 true）、`ownerName`、`ownerUserId`、`useAuthForRefresh`、`isMix`、`mixPlaylistId`、`mixSeedVideoId`、`trackIds`（有序整數陣列）、`createdAt`、`updatedAt`、`sortOrder`——`lib/data/models/playlist.dart:20-110`；`needsRefresh` 看 `refreshIntervalHours` 與 `lastRefreshed`（`:77-86` 附近）。
- Mix 歌單不保存曲目（`isMix`，註解「動態生成，不保存 tracks」）；開始時用 `mixSeedVideoId`／`mixPlaylistId`（`playlist.dart`；`playlist_card_actions.dart:26-71,151-164`）。

### 5.2 音樂庫、歌單詳情、建立／編輯
- 音樂庫頁：排序模式（拖曳）、右上「已下載」、新增與匯入入口——`lib/ui/pages/library/library_page.dart:32-117,251,258`；`features.md:121-135`。
- 建立／編輯對話框：名稱、封面、自動刷新間隔——`create_playlist_dialog.dart:39-61,291`（`features.md:125`）。
- 歌單詳情：播放、多選、下載、刪除曲目、分 P 群組——`playlist_detail_page.dart`（`:565-610,1575-1610` 遠端移除；`:884-890` 「全部」只加入佇列＝D2）。
- 歌單卡選單：Mix 播放／全部加入佇列／隨機加入／編輯／刷新／刪除——`lib/ui/widgets/menus/playlist_card_actions.dart:26-71`。
- 曲目選單：播放／下一首播放／加入佇列／加入歌單／匹配歌詞／加入遠端歌單；多選模式在歌單詳情、搜尋、探索、歷史四頁——`features.md:59-60`。
- 加入本機歌單：`lib/ui/widgets/dialogs/add_to_playlist_dialog.dart:19`。

### 5.3 匯入與刷新
- 內部直接匯入（B 站收藏夾 URL、YouTube 歌單與 Mix、網易雲歌單與 `163cn.tv`）——`lib/services/import/import_service.dart:156`（`importFromUrl`）、`:330`（`_importMixPlaylist`）、`:406`（`refreshPlaylist`）、`:544`（`autoRefreshAll`）、`:561`（`_expandMultiPageVideos`：匯入時展開 B 站多 P）、`:648`（`_generateUniqueName`：重名自動改名）。
- 外部匯入（QQ、Spotify）：`lib/services/import/playlist_import_service.dart:120-190`（`importAndMatch`，`maxSearchResults = 5`，搜尋來源 `SearchSourceConfig { all, bilibiliOnly, youtubeOnly }`，`:22-37`；網易雲不在比對來源內，`sources.md:301`）；來源實作 `lib/data/sources/playlist_import/spotify_playlist_source.dart`（抓 `open.spotify.com/embed/playlist/<id>` 頁面解析）、`qq_music_playlist_source.dart`（`u6.y.qq.com/cgi-bin/musics.fcg`＋自簽 `qq_music_sign.dart`，`pageSize = 1000`）。
- 舊評分（與 ADR 0019 §決定 6 不同）：`playlist_import_service.dart:443-534` 相關度分數含播放量（`viewScore`）、頻道加分、版本加分、括號內歌名加分、時長分；`:619` 時長分；手動重搜只依播放量排序（ADR 0019 背景）。
- 匯入預覽對話框（檔名 `import_preview_page.dart`，實為對話框）：換候選、處理未匹配——`lib/ui/pages/library/import_preview_page.dart:21-33,268,330-353`。
- 自動刷新：`lib/services/library/auto_refresh_service.dart:16-130`，每 30 分檢查一次、個別歌單依 `refreshIntervalHours`（預設 24 小時）、一次一張、間隔 5 秒、app 開著就跑（不看前景背景）（`features.md:333`）。
- YouTube Mix 簡寫：`lib/services/import/youtube_mix_shorthand.dart`（輸入 `mix:<videoId>`，種子至多 64 字，轉成 `watch?v=<id>&list=RD<id>`）。
- 帳號歌單匯入：`lib/ui/pages/settings/widgets/account_playlists_sheet.dart:129-172,226`（三個平台各一個 service 列歌單，勾選後以 URL 走一般匯入；帳號頁匯入一律帶登入＝M12）。

### 5.4 遠端寫入
- B 站：`lib/services/account/bilibili_favorites_service.dart:55`（`getFavFolders`）、`:117`（建立）、`:154`（`updateVideoFavorites`）、`:187`（`batchRemoveFromFolder`）、`:216`（`getVideoAid`，B 站 bvid→aid）。
- YouTube：`youtube_playlist_service.dart:63`（`getPlaylists`）、`:77`（`checkVideoInPlaylist`）、`:88`（加入）、`:105`（移除）、`:132`（`getSetVideoId`）、`:150`（`getVideoIdsInPlaylist`）、`:218`（建立）。
- 網易：`netease_playlist_service.dart:68`（`getPlaylists`）、`:96`（`getWritablePlaylists`）、`:101`（建立）、`:123`（`getTrackIdsInPlaylist`）、`:146`／`:159`（加入／移除）、`:240-253`（寫入請求附偽造 `X-Real-IP: 118.88.88.88`＝B3）。
- 編輯控制器與三個 adapter：`lib/services/library/remote_playlist_edit_controller.dart:19-440`（`RemotePlaylistEditAdapter`；B 站 `:225`、YouTube `:310`、網易 `:367`）；寫入後自動刷新對應本機歌單：`remote_playlist_sync_service.dart:13-28`、`remote_playlist_sync_provider.dart:39-77`。
- 未登入的來源在「加入遠端」對話框被過濾：`track_action_handler.dart:220,306`（`features.md:129`）。

### 5.5 排行、首頁、探索
- 排行來源：B 站 `ranking/v2`（預設 `rid` 音樂區；`bilibili_source.dart:865-917`）；YouTube 取 YouTube Music「New This Week」歌單並依播放數排序（`youtube_source.dart:1617-1652`）；網易官方熱歌榜歌單 `3778678`，預設 50 首（`netease_source.dart:332-364`）。
- 排行快取：`lib/services/cache/ranking_cache_service.dart:110-259`；預設 1 小時；單一榜單失敗依退避重試；網路恢復時重抓；背景仍抓所有音源（B12）。
- 首頁：`lib/ui/pages/home/home_page.dart:125-160`，區塊依序 `HomeRankingsSection`、`_RecentPlaylistsSection`（我的歌單）、`_RadioSection`、`_NowPlayingSection`、`_QueuePreviewSection`、`_RecentHistorySection`；排行區每音源前 `homeTrackPreviewCount = 5`、其他清單 `homeListPreviewCount = 20`（`app_constants.dart:162,165`）。
- 探索頁：`lib/ui/pages/explore/explore_page.dart:26-108`，依音源分 Tab 的完整排行，從首頁排行區塊的按鈕進入。
- 首頁排行設定：`home_ranking_settings_page.dart`（來源順序與啟用，至少留一個），`settings.dart:170-186`；欄位 `homeRankingSourcePriority`、`disabledHomeRankingSources`、`rankingRefreshIntervalMinutes`。
- 舊導覽 6 項：首頁、搜尋、佇列、音樂庫、電台、設定（`ui.md:77`）。

### 5.6 帳號頁管理歌單、粉絲勳章
- 「管理歌單」按鈕開 `AccountPlaylistsSheet`（`account_management_page.dart:193`）；粉絲勳章牆匯入電台：`account_management_page.dart:79,202`、`lib/services/account/bilibili_account_service.dart:529`（`fetchMedalWall`）、`lib/data/sources/bilibili_live_client.dart:339-344`（僅 B 站列有此按鈕，`features.md:145`）。

### 5.7 舊備份格式
- 單一 JSON 檔 `fmp_backup_<ISO 時間>.json`，沒有壓縮、沒有加密；Android 選目錄、其他平台 `saveFile`——`backup_service.dart:51-89`；`kBackupVersion = 5`（`:35`），匯入只擋比目前版本新的（`:314-321`），缺少的鍵用預設值（`data.md:289-290`）。
- 頂層鍵：`version`、`exportedAt`、`appVersion`、`playlists`（`trackKeys` 為 `sourceType:sourceId[:cid]` 字串陣列＋歌單欄位）、`tracks`（不含 `audioUrl`／`audioUrlExpiry`／下載路徑；含 `isAvailable`、`isVip`、`unavailableReason`、`bilibiliAid`、`viewCount`、`pageNum`、`parentTitle`、`originalSongId`、`originalSource`）、`playHistory`、`searchHistory`、`radioStations`、`settings`、`lyricsMatches`——`backup_data.dart:13-120,164-340,444,592-642,858`。
- 不含：帳號與 Cookie、AI API key、DownloadTask、PlayQueue、下載音檔；設定含 `lyricsAiEndpoint`、`lyricsAiModel`（`data.md:293-302`）。
- 匯入：全部先解析成待寫物件再以單一 transaction 寫入；曲目依 `uniqueKey` 略過重複、歌單依 name 略過同名；可勾選類別（`importPlaylists`、`importPlayHistory`、`importSearchHistory`、`importRadioStations`、`importLyricsMatches`、`importSettings`）；匯入時保留目前的 `customDownloadDir`、`preferredAudioDevice*`，`hotkeyConfig` 只在 Windows 匯入（`backup_service.dart:371-461,751-755,707-709`；`data.md:304`）。結果型別 `ImportResult` 計數每類的匯入與略過（`backup_data.dart:895`）。

---

## 6. 新增依賴（尚未在 `app/pubspec.yaml`）

| 套件 | 出處 | 用途 |
|---|---|---|
| `unorm_dart` | ADR 0019 §決定 6 | NFKC 正規化 |
| `opencc` | ADR 0019 §決定 6 | 繁簡統一（native assets；見矛盾 5） |
| `string_similarity` | ADR 0019 §決定 6 | Dice 相似度 |

備份、匯入檔案選取已有 `file_picker`（經 `FileDialogs`）；壓縮已有 `archive`；沒有其他 ADR 指名的新依賴。

---

## 7. M4 範圍總表（`milestones.md` 範圍／頁面對照 → ADR）

| M4 項目 | ADR 章節 | 備註 |
|---|---|---|
| 關聯表與孤兒清理 | ADR 0019 §決定 1 | 欄位細節未定（未定之處 11–15） |
| 本機歌單、音樂庫、歌單詳情、建立／編輯（E3） | ADR 0019 §決定 4；ADR 0018 §決定 4（全部加入佇列、10,000 上限） | 無版面 ADR（未定之處 26、30） |
| 加入本機歌單、加入遠端歌單（曲目選單） | ADR 0019 §決定 4 | 現有 `TrackRowMenu` 沒有（未定之處 32） |
| 匯入與刷新（E4） | ADR 0019 §決定 2、3；ADR 0017 §決定 6；ADR 0012 | `importPlaylist` 契約未定（未定之處 4） |
| 僅元資料來源的匹配（E5）、匯入預覽 | ADR 0019 §決定 5、6；ADR 0014 §決定 9 | Spotify／QQ 插件不存在（矛盾 3） |
| 遠端歌單編輯（E7） | ADR 0019 §決定 4；ADR 0012 §決定 3 | `libraryWrite` 契約未定（未定之處 6） |
| 帳號頁管理歌單（帳號歌單匯入） | ADR 0031 `:24` | `libraryRead` 契約未定（未定之處 5、34） |
| 粉絲勳章匯入電台、首頁電台區塊 | ADR 0031 `:62-63` | 資料來源能力未定（未定之處 33） |
| 首頁排行（E14）、探索頁、首頁排行設定 | ADR 0017 §決定 1、6；ADR 0016 §決定 4 | `charts` 契約未定（未定之處 7）；無版面 ADR（未定之處 27–29） |
| 導覽重排 | ADR 0031 `:41` | 未定之處 26 |
| Mix 的歌單形態、匯入 Mix 簡寫 | ADR 0019 §決定 1；ADR 0028 §決定 4；ADR 0031 §決定 11 | 矛盾 6、未定之處 16 |
| 備份與還原（E16） | ADR 0011 §決定 7；ADR 0025 `:152` | 格式未定（矛盾 1、未定之處 35–38） |
| 驗收：`opencc` 各平台建置 | ADR 0019；`milestones.md:127` | 矛盾 5 |

---

## 8. 矛盾與不一致（列出，不判斷）

1. **「備份」至少有四種說法。**
   - ADR 0025 `:152` 的更正：備份＝`VACUUM INTO` 的 `.db` 副本（已實作於 `database_backups.dart`），「E16 匯出格式另定」。
   - `milestones.md:124`「新格式的備份與還原」、`questions.md:254` E16、ADR 0010 影響範圍列「備份格式」（`0010:5`，決定文字無條目）。
   - ADR 0011 `:47`「設定包含在備份中」；M2 `design.md:214`「`layout_state` 不屬於任何設定組，M4 的備份不收它」；ADR 0021 `:67`「AI key 不進備份」。
   - ADR 0015 `:75`「還原正式版備份帶入真實資料」（沒說哪種格式）；ADR 0010 `:59` 舊備份檔（JSON）匯入屬 M5。
   - 現況的 `.db` 副本包含 `layout_state`、`installed_plugins`（含 `script`）、`plugin_storage`、`accounts` 列；M3 的還原因此先清 secure storage（`data_reset.dart:76-84`）。
2. **`milestones.md` §M4 的範圍只有三條**（`:122-124`），但同檔「舊版頁面對照」表標 M4 的七項（帳號頁管理歌單、粉絲勳章匯入電台、首頁與探索、導覽重排、首頁排行設定、音樂庫的匯入與匹配、曲目選單的加入歌單；`:39,42-46`）與 ADR 0031 `:62-63`（粉絲勳章、首頁電台區塊、歌單卡 Mix 播放、匯入 Mix 簡寫、導覽重排）沒有出現在範圍條目。範圍條目的「首頁排行（E14）」比對照表的「首頁（排行、最近播放、電台區塊）、探索頁、首頁排行設定」窄。
3. **「匯入 Spotify／QQ 歌單」是 M4 的「做完」（`milestones.md:120`），但範圍沒有寫 Spotify／QQ 插件。** ADR 0014 §決定 2 規定 App 不內建任何來源（`0014:34`），ADR 0012 `:55` 把它們標 `never`；`fmp-plugins` 現況沒有這兩個插件（§4.2）；M3 digest 曾寫「那兩個插件屬 M4」，`milestones.md` M4 範圍沒有。
4. **ADR 0019 `playlist_remote` 的欄位清單沒有刷新間隔與「是否啟用」**（`0019:37`）；ADR 0017 §決定 6 需要「匯入歌單每張」間隔、「不啟用」，ADR 0019 §決定 3 與 ADR 0017 §決定 5 需要「歌單改為不啟用」「停止自動刷新」。舊欄位 `refreshIntervalHours`、`notifyOnUpdate`、`useAuthForRefresh`（`playlist.dart`）；`useAuthForRefresh` 被 ADR 0019 否決（`0019:28`），`notifyOnUpdate` ADR 未提。
5. **ADR 0019 §決定 6 與 `milestones.md:127` 驗收假設 `opencc` 可以在各平台以 native assets 建置**，pub.dev／GitHub 的事實（§4.3）：stable 1.1.0 依賴 `native_assets_cli ^0.8.0`；預發佈 1.2.0-dev.1 的 `main` pubspec 釘 `sdk: 3.10.0-14.0.dev`；release 資產沒有 Android、iOS、macOS arm64。全域規則是依賴裝當前 stable、alpha／RC／dev 只在沒有可行 stable 替代時用並說明風險。另 `milestones.md:127` 寫「各平台」，M4 只實作 Android 與 Windows，Linux／macOS／iOS 屬平台任務。
6. **Mix 的歌單形態存的欄位不夠重新開始一個 Mix。** ADR 0028 `:52`、ADR 0031 `:54`、M3 `design.md:308`：`playlists.kind = mix` 存「（插件 id, `mixId`）」同一對身分；但 `mix` 的續取查詢 `{mixId, cursor}` 的 `cursor` 必填（`fmp-plugin.d.ts:285-288`），開新 Mix 要 `{seed: {sourceId, cid?}}`（`0028:52`）。舊版歌單另存 `mixSeedVideoId` 供「Mix 播放」開始（`playlist.dart`，`playlist_card_actions.dart:151-164`）。ADR 0019 `playlist_remote` 的欄位清單（插件、遠端 id…）沒有 Mix 專用欄位。
7. **歌單名稱唯一性：** ADR 0019 `:36`「名稱不唯一」；舊 `Playlist.name` unique（`data.md:38`）、舊備份匯入同名略過（`backup_service.dart:461-470`）、舊匯入重名自動改名（`import_service.dart:648`）。新版對「重新匯入」靠遠端 id 辨識（`0019:51`），對「備份匯入同名」沒有規定。
8. **M4 驗收項太少。** `milestones.md:125-127` 只列「兩平台端到端」與「`opencc` 建置」，對照 M3a／M3b 列了 ADR 測試與編號（`milestones.md:97-100,112-116`）；ADR 0019 §如何確認、ADR 0017（新工作）、ADR 0016（排行快取）、ADR 0028（新能力與 `checks.json`）、ADR 0031（導覽）各有可驗項。（與 M3 digest 矛盾 13 同型。）
9. **ADR 0014 §決定 9 與 ADR 0019 §決定 5 的匹配描述不同**：前者「對所有啟用的目標來源比較取最高分，同分依使用者排序」，後者「在使用者設定的目標音源中搜尋，保留前 5 名、第一名自動選」。前 5 名是跨來源合併後的前 5 還是每來源 5 個，兩份都沒寫；舊版是每來源 `maxSearchResults = 5`（`playlist_import_service.dart:150-153,247`）。
10. **首頁電台區塊在 ADR 0031 `:62-63` 列為 M4，電台頁在 M3b 已完成；導覽重排「M4 加音樂庫與首頁時整體重排」（`0031:41`）**，但 ADR 0024 §決定 3 的導覽表沒有列出導覽目的地的個數與順序，只寫元件，M3 的順序（搜尋｜歷史｜電台｜設定）是 ADR 0031 定的；加上首頁與音樂庫後 compact 底部導覽會是 6 項。（事實陳述；Material 的項數規範未查證，待查。）

---

## 9. 未定之處

分類：【產品】產品／範圍決定；【技術】技術決定。這一節只寫問題，不寫建議。

### A. 範圍與驗收
1. 【產品】**M4 範圍條目要不要補齊**（矛盾 2）：首頁／探索／導覽重排／帳號歌單匯入／粉絲勳章／Mix 歌單與簡寫／曲目選單加入歌單／音樂庫 UI 是否都在 M4；以及驗收要不要補 ADR 測試項（矛盾 8）。
2. 【產品】**Spotify、QQ 插件是否在 M4 做、做幾個**（矛盾 3）：舊版的抓取方式（Spotify embed 頁、QQ 自簽 `sign`）還能不能用沒有實測；插件放 `fmp-plugins`、id 字串（`spotify`／`qq`？ADR 未寫，影響 `fmp_source_id_literal` 清單）；實機驗證怎麼做（ADR 0027：真實連線、最少操作）；進入官方 index 後 ADR 0030 §決定 12 的首次啟動引導（「官方插件清單預設全勾」）要不要涵蓋這兩個沒有 `search` 的插件。
3. 【產品】**E16 的備份要包含什麼、要不要加密**（矛盾 1）：見 35–38。

### B. 插件契約（宿主 API v1 擴充，凍結前定完，`0028:43,66`）
4. 【技術】**`importPlaylist` 的輸入輸出。** 輸入是 URL 還是 playlistId；如何由 URL 認出屬於哪個插件（ADR 0031 §決定 2 的 `liveRoomFromUrl` 是前例：依序問每個啟用且宣告該能力的插件）；分頁形式（page／`cursor`）與「完整性回報」（`0019:49` 的「任何一頁失敗或筆數不足」需要總筆數或 hasMore）；歌單 metadata（名稱、描述、封面、擁有者、是否為 Mix）；項目的遠端項目 id（`playlist_entries` 要存，YouTube `setVideoId` 是前例，`youtube_playlist_service.dart:132`）；曲目的失效標記；`TrackSummary` 是否夠用（分 P 兩欄，M3 `implement.md:505`）；B 站收藏夾是否匯入時展開多 P（舊 `import_service.dart:561`）；Mix 簡寫由誰解析。
5. 【技術】**`libraryRead` 的輸入輸出。** 列出帳號歌單／收藏夾的形狀（是否含曲目數、可寫旗標、已匯入判斷由宿主做）；是否同時是「粉絲勳章牆」的來源（`0031:24` 說「`libraryRead` 一類」，但勳章牆是直播間清單不是歌單）；`AuthRequirement.required`；網易 query vs 路徑端點（§2 第 13 條）。
6. 【技術】**`libraryWrite` 的輸入輸出。** 建立歌單、加入、移除、「曲目是否已在歌單」查詢（YouTube `checkVideoInPlaylist`、網易 `getTrackIdsInPlaylist`、B 站 `updateVideoFavorites` 差集）；B 站 bvid→aid 轉換放插件還是宿主；部分成功回報（`0019:55` 的「列出失敗項」）與 `libraryWrite` 的錯誤對應；網易寫入是否沿用 `X-Real-IP` 偽造（B3 未定、`questions.md:117`；讀取側取流已用）；寫入後的「背景刷新」由誰觸發。
7. 【技術】**`charts` 的輸入輸出。** 一個插件有幾個榜單、榜單 id 與顯示名、分類／limit 參數（舊 B 站 `rid`、YouTube `category`、網易 limit 50）；manifest 是否宣告榜單的預設啟用；YouTube 的榜單來源（舊為「New This Week」歌單依播放數排序，非真排行榜，`sources.md:28`）；`userPreference` 對排行的語意（`0012:36`；舊版 YouTube／網易排行永遠不帶，`0012:12`）。
8. 【技術】**`checks.json` 對新能力的案例，與健康檢查的副作用。** ADR 0025 §決定 6 的健康檢查以真實連線跑 `checks.json`；`libraryWrite` 的案例（建立／加入／移除）真實跑會改使用者的遠端歌單，ADR 0028 `:55` 的 `requiresLogin` 只處理「略過」；`libraryRead`／`importPlaylist` 對私人收藏夾的案例要帳號；每能力一條案例的規則（`0015:59`）對讀與寫如何套用。
9. 【技術】**宿主與 `fmp-plugins` 同一輪改。** 三個官方插件的能力升級、版本號、`index.json` 重產、CI 的 `FMP_REF` 更新（`ci.yml:28`）、FMP 先合併還是插件先合併的順序；插件 PR 與 FMP PR 之間的相依。
10. 【技術】**帶憑證錄 fixture 的遮蔽閘門**（§2 第 10–14 條）：`recordCase` 對非 `LoginAccount` 結果的換值、隔離環境帶憑證、B 站 `mid`／`uid`／`vmid` 在 query 與路徑的遮蔽、自己建立的歌單 `creator`；M4 前要不要先開 issue 擴充名單（`implement.md:563` 建議）。

### C. 資料模型
11. 【技術】**五張新表的欄位**：`playlists`（名稱、描述、封面與本地覆寫旗標、排序、建立／更新時間）、`playlist_remote`（含矛盾 4 的間隔與啟用、`notifyOnUpdate` 有無、上次刷新結果與狀態列舉、擁有者）、`playlist_entries`（位置、遠端項目 id、`track_key` FK 的刪除規則）、`track_origins`（欄位與用途：Spotify／QQ 的原始 id？）、`match_results`（是否也存前 5 名候選或只存選定項與分數，`0019:41` 只列「選定曲目、分數、使用者改選」）。
12. 【技術】**曲目「已失效」「可用狀態」放哪**：`tracks`（所有歌單共用）還是 `playlist_entries`（逐歌單）；舊 `Track` 有 `isAvailable`、`isVip`、`unavailableReason`、`viewCount`、`bilibiliAid`（`backup_data.dart:267-340`），新 `tracks` 沒有（§4.1）；ADR 0010 §決定 2「只存事實、不持久化推導值」。
13. 【技術】**刷新套用的交易與中斷一致性**（`0019:50`「抓一頁寫一頁、每頁一個 transaction 加刷新代際」＋「完整抓完後一次套用移除與順序」）：頁寫入期間歌單顯示的順序；重複影片（同一曲目鍵多筆）用什麼鍵比對順序與移除；中途被殺掉後下次啟動的狀態；與 `JobContext.isCurrent` 的整合；ADR 0019 `:87` 要測「刷新中途失敗後的一致性」。
14. 【產品】**「重新匯入同一張遠端歌單」的辨識**：以（插件, 遠端 id）；使用者在本地改過名稱／封面的處理；從帳號頁匯入與從 URL 匯入同一張歌單的結果（M12）。
15. 【技術】**孤兒查詢與外鍵**：`playlist_entries.track_key` 對 `tracks` 是 `RESTRICT` 還是其他（佇列與歷史是 `RESTRICT`，`tables.dart:186,245`）；刪歌單 `CASCADE` 項目後曲目要等下次啟動維護才被清；`track_key` 索引（M2 `design.md:606`）。
16. 【產品】**Mix 歌單形態**（矛盾 6）：存什麼欄位、歌單詳情頁顯示什麼（沒有曲目）、歌單卡的動作、匯入 Mix 簡寫在新版屬哪個插件解析、在音樂庫以 `kind = mix` 建立的入口（匯入對話框？曲目選單「存成 Mix 歌單」？）。
17. 【產品】**來源失效的 UI**（`0019:52`）：「重試」「唯讀副本」呈現；需要登入（`AuthRequired`）與「無權限」「NotFound」的區別；「另存為本地歌單」被列為凍結待辦（`0019:80`）。

### D. 刷新與排程
18. 【技術】**排程工作切分**：「一次刷一張」（`0017:39`）是一個歌單一個工作、一個插件一個工作還是一個匯入總工作；工作 id 規則（前例 `radio-status:<pluginId>`）；啟動時登記與歌單新增／刪除／改間隔的同步；歌單卡「刷新」用 `runNow`、`alreadyRunning` 與離線的 UI；排行工作與榜單停用（B12）的移除。
19. 【技術】**設定歸屬與欄位**（`0011:46,56`、`0026:68`）：排行刷新間隔放現有 `network_settings`（電台間隔已在那）還是新的「音樂庫與同步」組；匯入歌單的新預設間隔（24 小時）；匹配目標來源集合；首頁排行來源順序與啟用（舊 `homeRankingSourcePriority`、`disabledHomeRankingSources`）；備份相關設定；這些哪些屬於「設定包含在備份中」。
20. 【產品】**`notifyOnUpdate`**（舊預設 true）新版是否保留；`0019:52` 寫自動刷新不跳 toast、只更新歌單頁狀態；舊欄位 M5 如何對照。
21. 【技術】**背景刷新的失敗呈現**：離線（不跑，`0017:36`）、`RateLimited`、`AuthRequired`（私人收藏夾、已失效帳號）、部分完成在歌單頁各顯示什麼；`0013:61`「背景工作不跳 toast」。

### E. 匹配
22. 【技術】**`opencc` 的取得與建置**（矛盾 5）：現有資料顯示 Android 沒有預編譯庫；是否需要在 Android 上自建、換套件或改 ADR 決定；`unorm_dart`、`string_similarity` 無此問題。
23. 【技術】**評分核心的細節**（`0019:62-65` 只定框架）：標題／歌手／時長權重；「第一名自動選」是否有最低分門檻與「匹配失敗」的判定（`0014:56`）；時長缺失時；多歌手的拆分符號；括號內容單獨比對的合成方式；核心放哪個目錄（`app/lib/` 沒有 `library`／`match`）與歌詞（M7）共用的介面。
24. 【產品】**目標音源集合**：預設值與可選範圍（舊版只有 B 站與 YouTube 三選一，網易不在內，`sources.md:301`；新版是任何有 `search`＋`resolveStream` 的啟用插件？）；設定放哪、匯入預覽能否臨時改；「同分依使用者排序」的使用者排序來源（`0014:56`）。
25. 【技術】**逐首搜尋的執行方式**：大歌單（QQ 一頁 1000 首）的並行度與耗時、進度與取消、App 進背景時是否繼續（排程器只管週期工作，不管這個）、失敗的單首如何處理（`0013:61` 部分成功要標出失敗項目）。

### F. UI 與導覽
26. 【產品】**導覽重排**：首頁、音樂庫加入後的順序與項數；compact 底部導覽放得下的項數；`ShellDestination`／`IndexedStack` 的結構改動；各頁（音樂庫、歌單詳情、探索）在 compact／expanded 的版面（ADR 0024 沒有，也沒有示意稿）。
27. 【產品】**首頁內容**：舊版六個區塊（排行、我的歌單、電台、正在播放、佇列預覽、最近播放）；對照表只列「排行、最近播放、電台區塊」；新版已有右側「正在播放」面板與佇列分頁，這兩個區塊是否保留；「我的歌單」區塊未列入；首頁電台區塊用 `radio_stations` 的哪些欄位。
28. 【產品】**探索頁**：是否為導覽項還是首頁排行區塊的子頁；多榜單（`charts` 多個榜單）如何呈現（舊為依音源分 Tab）；多選與加入歌單。
29. 【產品】**首頁排行設定**：位置（設定→哪一區）、內容（來源順序、啟用、榜單層級的啟用，`0016:42`「榜單 id」）、「至少留一個」規則是否保留；B12 停用即不抓與刪快取。
30. 【產品】**音樂庫與歌單詳情**：歌單卡版面、拖曳排序（舊有）、多選動作（新版 `lib/ui/` 目前沒有多選模式）、建立／編輯對話框欄位、分 P 群組（M3 `implement.md:504` 指定在歌單詳情做）、「全部」（加入佇列，D2）與舊的「隨機加入」、下載按鈕（M6 才有）、遠端歌單標示與「部分完成」「已失效」「來源失效」的呈現。
31. 【產品】**匯入入口位置**：舊版在音樂庫「匯入」對話框；新版是對話框或頁面、是否與帳號頁「管理歌單」同一流程、匯入預覽是對話框或頁面（`0019:60` 稱「匯入預覽頁」）。
32. 【產品】**曲目選單的「加入本機歌單」「加入遠端歌單」**：套用在 `TrackRowMenu` 的哪些頁（搜尋、歷史、佇列、歌單詳情、播放頁、右側面板）；多選模式是否在 M4 引入；遠端歌單對話框的勾選介面（三個平台各自列表）。
33. 【產品】**粉絲勳章匯入電台**：只做 B 站；資料取得放哪個能力（矛盾見 §9 第 5 點）；入口在帳號區；與電台重複的處理（沿用 `radio_stations` 的「已在電台清單」提示，`0031:40`）；需要的 uid 遮蔽。
34. 【產品】**帳號頁「管理歌單」的範圍**：列出、勾選、顯示已匯入狀態（舊 `account_playlists_sheet.dart`）；是否含「在遠端建立歌單」（舊版在加入遠端對話框內）；帳號頁匯入是否一律帶登入（舊 M12，新依 `userPreference`）。

### G. 備份與還原
35. 【產品】**備份內容**：歌單、曲目、播放歷史、電台、設定（新版沒有搜尋歷史表，舊備份有 `searchHistory`）、`installed_plugins`（含腳本）、`plugin_storage`、`accounts` 顯示資訊、`source_settings`、`scheduler_runs`、`layout_state`（M2 決定不收）、`match_results`；憑證不收（舊版與 M3 都不收）；加不加密；還原到另一台裝置時帶來的插件與登入狀態。
36. 【技術】**備份格式**：延續 `.db` 副本、版本化 JSON（如舊版）、zip 內含兩者或另一種；schema 版本相容（`schemaVersion` 14 起，備份比目前新時的處理）；與 M5「舊備份檔匯入與資料庫匯入共用同一套轉換」（`0010:59`）的關係；匯入是「合併」（舊版：略過重複／同名）還是「取代並重啟」（M3 還原）；是否可勾選類別（舊版可）。
37. 【技術】**還原的執行路徑**：重啟（M3 的 `restoreAndRestart`）或熱換；還原前自動備份；dev flavor 帶 prod 備份（`0015:75`）時的拒絕與提示；還原後 `installed_plugins` 腳本是否重新驗 SHA-256／重新確認能力與網域（ADR 0030 §決定 8 的安裝確認不會經過）。
38. 【產品】**備份入口與時機**：設定頁新增「備份」區（`SettingsSection` 目前沒有）；匯出到哪（`FileDialogs.saveFile`／`pickDirectory`）；Android 與 Windows 行為；有無自動定期備份（舊版無；M3 只有重設前自動備份）；與 Debug 頁「從備份還原」的關係。

### H. 其他
39. 【技術】**目錄與分層**：歌單、匯入、匹配、備份的模組放哪（`app/lib/` 頂層沒有對應目錄）；`fmp_layer_imports` 的允許關係、排程器的 import 限制（`app/AGENTS.md:1121`）需要涵蓋的新依賴方向；新 lint 規則是否需要（目前無）。
40. 【技術】**M5 預留**：ADR 0026 `:67` 要求新增資料表的里程碑同時補舊資料匯入的對照，M5 才實作；M4 是否要在 design 中先寫「舊欄位→新欄位對照」。
41. 【技術】**重播模式的測試插件**：實機驗證預設用重播（ADR 0027）；`fmp-test` 要擴充 `importPlaylist`／`libraryRead`／`libraryWrite`／`charts` 才能走完匯入、刷新、遠端編輯、排行。
42. 【技術】**i18n 與 a11y**：三語言（zh-Hant、zh-Hans、en）字串、新頁面在 `meetsGuideline` 測試清單（`0024:157` 已列首頁、歌單）。

---

## 10. M4 可能的 PR 切分素材（只列工作單元與依賴，不排定順序）

| 代號 | 工作單元 | 依賴 |
|---|---|---|
| U0 | 文件與決定：新 ADR（或 ADR 0019／0028／0031 的補充）涵蓋 `importPlaylist`／`libraryRead`／`libraryWrite`／`charts` DTO、備份格式、首頁／音樂庫／探索／導覽；`milestones.md` M4 範圍補齊 | 擁有者回答 §9 的對應問題 |
| U1 | 資料層：`playlists`／`playlist_remote`／`playlist_entries`／`track_origins`／`match_results` 的表、migration（v15 起）、快照、repository、`tracks` 新欄位、孤兒查詢加歌單項目、外鍵與孤兒測試 | U0（欄位） |
| U2 | 本機歌單：建立／編輯／刪除／排序、歌單詳情（播放、全部加入佇列、10,000 上限）、音樂庫頁、「加入本機歌單」曲目選單項 | U1；導覽殼（U9） |
| U3 | 宿主契約 `importPlaylist`：d.ts、Dart shapes、`SourcePlugin` 方法、`FmpChecks`、契約執行器、`fmp-test` 測試插件 | U0 |
| U4 | 三個官方插件的 `importPlaylist`（`fmp-plugins` repo）：fixtures、`checks.json`、版本、`index.json`、`FMP_REF` | U3 |
| U5 | 匯入與刷新引擎：URL→插件、分頁寫入、差集比對、部分完成、來源失效、重新匯入＝刷新、匯入入口 UI | U1、U3、U4 |
| U6 | 排程器的匯入歌單刷新工作與排行工作、刷新間隔設定、「音樂庫與同步」設定組（含 migration 不改使用者值測試） | U5（匯入）、U11（排行）、設定歸屬決定 |
| U7 | 宿主契約 `libraryRead`＋插件實作＋帳號頁「管理歌單」（帳號歌單匯入） | U3、U4、U5 |
| U8 | 宿主契約 `libraryWrite`＋插件實作＋「加入遠端歌單」「從遠端歌單移除」＋寫入後刷新 | U1、U5、U7（歌單列表）；錄製需帶憑證的閘門（§2 第 10–12 條） |
| U9 | 導覽重排＋首頁骨架（`ShellDestination` 擴充、各寬度導覽元件、首頁最近播放／電台區塊） | U0（導覽決定）；音樂庫頁（U2）、首頁排行（U11）可後掛 |
| U10 | 匹配核心：加入 `unorm_dart`／`opencc`／`string_similarity`、正規化與評分、測試；`opencc` 在 Android／Windows 的建置驗證 | U0（`opencc` 決定） |
| U11 | `charts`：契約＋三個插件實作＋排行快取（`cache.db`）＋首頁排行區塊＋探索頁＋首頁排行設定（B12 停用即不抓） | U0、U9（首頁）、U6（排程） |
| U12 | Spotify／QQ 插件（`fmp-plugins`）＋匯入預覽 UI（換候選、重搜、排除）＋`match_results`／`track_origins` 寫入 | U1、U3、U5、U10 |
| U13 | Mix 的歌單形態（`kind = mix`、歌單卡「Mix 播放」、匯入 Mix 簡寫） | U1、U2、U5；Mix 欄位決定（矛盾 6） |
| U14 | 粉絲勳章匯入電台（帳號區入口）＋首頁電台區塊 | U7（若走 `libraryRead`）、U9 |
| U15 | 備份與還原：新格式匯出、匯入／還原、設定頁備份區、與 `DatabaseBackups`／`DataReset` 的關係 | U0（格式）、U1（表）、U2、其餘新表齊全後 |
| U16 | 收尾：`app/AGENTS.md` 與 `.trellis/spec/app` 同步、lint（若有）、i18n 三語言、兩平台端到端驗收、`milestones.md` 勾選、M5 對照註記 | 其他全部 |
