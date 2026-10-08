# M3 三音源、帳號與開發工具：ADR 範圍摘要

> 目的：讓 planner 把 M3 拆成 PR 大小的 child task，並把「未定之處」整理成擁有者問題。本檔只彙整既有 ADR、計畫與程式現況，不新增決定；ADR 之間或 ADR 與現況矛盾的地方列在 §7，不自行判斷。
> 來源：`.trellis/tasks/09-26-fmp-rewrite/milestones.md` §M3（範圍與驗收的權威）及 §M4–M9 的交界段落、`phase2-plan.md` §5／§7／§8／§9、`docs/audit/questions.md`（E2、E6、E12、E13、M 項、D 項）與 `sources.md`、`accounts-network.md`、`devtools.md`、`playback.md`、`docs/adr/0008`–`0027`、M1／M2 任務的 `implement.md`／`design.md`／`research/`、`app/` 現況、`C:\Users\Roxy\orca\fmp-plugins`、舊版 `lib/`（只摘要行為與位置）。
> 格式：每則 ADR 分四段——(a) M3 要做的、(b) M3 的驗證、(c) 不在 M3、(d) ADR 已固定的名稱。仿 M2 的 `m2-scope-digest.md`。
> 「現況」只列存在什麼（檔案加一行），不評論。查證日期 2026-10-08（HEAD `1d119ae8`）。沒有連網，套件版本沒有重查。

## 0. M3 的權威定義

- **做完**：`milestones.md:62`——「三個音源都能搜尋、播放、登入。」
- **一句話性質**（ADR 0026 §決定 3 的表，`0026:75`）：M3 =「YouTube、網易雲、登入；插件庫與插件頁；Debug 頁與插件開發工具」。依賴 M2；M4 依賴 M3（`milestones.md:11-12`）。ADR 0026 的表沒有寫電台、Mix、分 P、排程器；後者在 `0026:84` 的修訂與 `milestones.md:64-69` 補上（見 §7 矛盾 3）。
- **範圍**（`milestones.md:64-69`）：
  1. YouTube、網易雲插件；B 站分 P（E2）、Mix（E13）、電台直播（E12）
  2. 帳號與 `CredentialStore`、`AuthRequirement`（ADR 0012，E6）
  3. `1morr/fmp-plugins` repo、CI、`index.json`；插件頁；首次啟動引導（ADR 0014）
  4. Debug 頁與插件開發工具（ADR 0025、0015 §7）；錯誤詳細頁、GitHub 回報、`.github/ISSUE_TEMPLATE/bug_report.yml`（ADR 0023）
  5. 背景排程器（ADR 0017）與 lint `fmp_periodic_timer_owner`，第一個工作是電台狀態（2026-10-01 從 M2 移來）；`QueueModel` 的 `mix`、`live` 模式
- **驗收**（`milestones.md:70-74`）：[ ] 兩平台端到端操作（Android 與 Windows 各一次，ADR 0026 §決定 1）；[ ] ADR 0017 排程器的測試；[ ] §8：YouTube App 內網頁登入（ADR 0012）；[ ] §8：加入 Debug 頁的里程碑實測（ADR 0025）。M2 的驗收列了「ADR 0016、0018 的測試」，M3 沒有列 ADR 0012／0014／0015／0023／0025 的測試（見未定之處 1）。
- **§8 的兩項實測**（`phase2-plan.md:238,243`）：
  - YouTube App 內網頁登入（桌面 UA）是否仍可用——「第一個加入 YouTube 登入的里程碑先實測；不可用則只提供貼上 cookie」。
  - Windows release 版開啟開發者模式、重啟後仍開啟、再從總開關關掉；Debug 頁看到一次搜尋的網路摘要；匯出的診斷包能以解壓工具打開。
- **範圍相關的先前決定**：YouTube 走插件，不改用 Dart（YouTube.js 探針通過，`0014:59`；證據 `.trellis/tasks/archive/2026-09/09-30-youtubejs-probe/research/youtubejs-probe.md`）。擁有者 2026-10-01 規劃 M2 時把排程器、`mix`、`live` 移到 M3（`milestones.md:56`、M2 `design.md:65-66`）。
- **不是 M3**：Linux、macOS、iOS 實作（Mac 到貨後，`milestones.md:132-149`）；歌單、匯入、排行、遠端歌單編輯（M4）；舊資料匯入（M5）；下載（M6）；歌詞與 AI 插件（M7）；托盤與全域快捷鍵（M8）；應用內更新、使用者指南與關於頁（M9）。
- **ADR 0027**：M3 每個改到使用者看得到的 PR 都要 Android 與 Windows 各驗一次；預設模式「重播」，改動本身是插件、網路層、登入、或正在錄 fixture 時才用「真實」（`0027:36-41`）。

---

## 1. 逐 ADR 摘錄

### ADR 0012 — 網路層與帳號（M3 的主體之一）

**(a) M3 要做的**
- `CredentialStore`（§決定 3，`0012:38-40`）：唯一憑證來源，`flutter_secure_storage` 11.x，以音源 id 為鍵；登入狀態由它推導；帳號的非機密顯示資訊存資料庫；讀取失敗時狀態為「暫時無法讀取」並稍後重試、**不刪除**；憑證載入或更新時登記到遮蔽函式。
- 登入是音源能力（§決定 4，`0012:41-43`）：音源宣告支援的方式（QR、App 內網頁登入、貼上 cookie），UI 顯示「音源支援 ∩ 平台有能力」。B 站、網易以 QR 為主；YouTube 以 App 內網頁登入（桌面 UA）為主、貼上 cookie 為備案。**拿到憑證後先呼叫帳號資訊 API 驗證，通過才寫入**。
- 刷新與失效（§決定 5，`0012:44-49`）：
  - 刷新由音源宣告是否支援與時機（B 站啟動時詢問是否需要刷新）；帳號頁顯示最後刷新時間與結果。
  - 只有帶了憑證的請求才可能觸發失效；每個音源明確列出哪些回應代表憑證無效，網路錯誤、限流、風控碼不算。
  - 憑證無效：`QueuedInterceptor` 單飛，支援刷新就先刷新、**以新憑證重建請求**後重送一次；否則標記已失效。
  - 已失效：保留憑證、停止帶它、提示一次，帳號頁與相關入口顯示需要重新登入；重新登入後下一次失效會再提示。
  - 登出：清該音源憑證、該音源網域的 WebView cookie、記憶體 cookie、遮蔽登記。重設所有資料：清資料庫、全部憑證、全部 WebView 資料。
- 「以登入身分瀏覽與播放」（§決定 6，`0012:50-52`）：每音源一個開關（每音源設定表，ADR 0011），控制所有 `userPreference` 請求；預設由音源宣告，**B 站、網易、YouTube 皆開**；YouTube 旁附說明「以登入身分大量請求可能被視為自動化行為（推測）」。
- `AuthRequirement` 已在 M1 實作（`required`／`userPreference`／`never`）；M3 把認證來源從 `NoCredentials` 換成 `CredentialStore` ＋每音源設定表（`app/lib/core/network/auth.dart` 檔內註解「M3 由 `CredentialStore`…實作」）。
- 只能匯入的來源（Spotify、QQ）標為 `never`（§決定 7）；那兩個插件屬 M4。
- 沒有 WebView 的平台（Linux）：B 站、網易用 QR，YouTube 貼上 cookie（§決定 8）——Linux 非 M3。
- M1 已有的網路層（HTTP client 每插件一個、轉址 5 跳、媒體 client、網路紀錄）不在 M3 重做。

**(b) M3 的驗證**（`0012:69-75`）
- 契約測試：每個音源的媒體請求經媒體 client 發出後，請求上不含任何 Cookie／Authorization（M1 對 B 站已有；M3 對 YouTube、網易補）。
- 測試：`AuthRequirement` 三種標記在「未登入／已登入且開關開／已登入且開關關」下的注入結果（`auth_test.dart` 現有 `NoCredentials` 版本）。
- 測試：刷新後重送的請求帶的是新憑證；每個音源的「憑證無效」判定表；限流與網路錯誤碼不會把帳號標為失效；登出與重設所有資料後 `CredentialStore` 為空且請求不再帶憑證。
- §8 實測：YouTube App 內網頁登入（`0012:65`、`phase2-plan.md:238`）。

**(c) 不在 M3**
- Linux 沒有 keyring 時 secure storage 的行為（Linux 平台任務，`milestones.md:139`）。
- 舊憑證以 10.x 讀入（M5 `legacy_import`，`0012:40`、ADR 0010）。
- 統一錯誤型別與限流退避細節（已由 ADR 0013 定）。
- Linux 的 `webview_cef`（Linux 任務決定）。

**(d) ADR 已固定的名稱**：`CredentialStore`、`AuthRequirement`（`required`／`userPreference`／`never`）、`flutter_secure_storage` 11.x、`cookie_jar`＋`dio_cookie_manager`（M1 已加）、`QueuedInterceptor`、登入方式名「QR」「App 內網頁登入」「貼上 cookie」、B 站刷新「啟動時詢問」。舊版錨點：登入頁 `lib/ui/pages/settings/{bilibili,youtube,netease}_login_page.dart`，帳號服務 `lib/services/account/`（`accounts-network.md` §1、§6）。

---

### ADR 0014 — 腳本插件（插件庫、插件頁、引導、三個音源）

**(a) M3 要做的**
- 插件庫（§決定 6，`0014:48-50`）：官方插件在獨立 repo `1morr/fmp-plugins`，每插件一目錄（腳本、manifest、錄下的測試 fixture）；其 CI 跑契約測試並產生 `index.json`（含 SHA-256，針對單一 `.js` 檔，`0014:64`）。App 插件頁預設讀官方 index，可加自訂 index 網址，也可從檔案或網址安裝；由 index 安裝時驗證 SHA-256；安裝前顯示能力與會連的網域，並警告「此腳本會以你的登入身分存取這些網站」。
- 更新（§決定 7，`0014:51`）：只在打開插件頁或手動檢查時比對 index，可一鍵全部更新；不做背景自動檢查。
- 首次啟動與升級（§決定 8，`0014:52-53`）：沒有來源時引導安裝官方插件；移除插件時清除其 storage 與憑證，曲目保留並標示。（legacy import 偵測舊資料用到的音源並提示一鍵安裝＝M5。）
- 三個音源（§決定 2、4、10，`0014:34-40,57-59`）：YouTube（YouTube.js 18.1.0 打成單一插件檔，約 793 KB／204 KB gzip，以 `fmp.http.request` 補 Web API，VISIONOS client；可用 client 會隨 YouTube 封鎖而換）、網易雲（舊 Dart 程式碼為規格改用 JS 重寫）。能力：`search`、`resolveStream`、`trackDetail`、`multiPart`、`importPlaylist`、`libraryRead`、`libraryWrite`、`charts`、`live`、`mix`、`lyrics`、`login`（`0014:38`）。M3 範圍內用到的：`multiPart`（B 站分 P）、`live`（B 站電台）、`mix`（YouTube Mix）、`login`；`trackDetail` 的里程碑 ADR 與 `milestones.md` 都沒指定（未定之處 2）；`importPlaylist`／`libraryRead`／`libraryWrite`／`charts` 屬 M4；`lyrics` 屬 M7。
- 宿主 API v1（§決定 5，`0014:41-47`）：`credentials`（只讀自己音源）現況 M1 一律回 null；`resolveStream` 的 `expiresAt`、`artwork`、`previewOnly`、`quality` 已在 M2 擴充。
- 執行環境補充（`0014:66`）：每個插件在自己的背景 isolate；呼叫逾時先送存活探測，無回應者標「沒有回應」並停用到 App 重啟。M1 follow-up：若要讓使用者手動停用，M3 插件頁一併處理（M1 `implement.md:195`）。

**(b) M3 的驗證**（`0014:77-82`）
- 結構測試：每個插件的 manifest 能力與實際匯出一致；`apiVersion` 不相容時拒絕載入。
- 契約測試：以錄下的 HTTP 回應重播（M1 已有執行器 `app/test/plugins/contract/`）；M3 的三個插件各自涵蓋 ADR 0011（遮蔽）、0012（媒體請求不帶憑證、`AuthRequirement`）、0013（錯誤對應）。
- 宿主 HTTP 拒絕 manifest 網域以外請求、腳本無法讀其他插件 storage 與憑證（M1 已有）。
- lint `fmp_source_id_literal`：官方插件 id 字串只在 `legacy_import` 與測試；現況清單只有 `bilibili`（`app/packages/fmp_lints/lib/src/rules/source_id_literal.dart:11-14`），加 YouTube、網易時要加進清單。

**(c) 不在 M3**
- 背景自動檢查插件更新（否決，`0014:28`）；腳本讀其他音源憑證或檔案系統（否決）。
- 匹配核心、Spotify／QQ 匯入（ADR 0014 §決定 9，M4）；歌詞源與 AI 插件（M7）。
- legacy import 偵測舊音源並提示安裝（M5）。

**(d) ADR 已固定的名稱**：`SourcePlugin`、manifest 欄位（`id`、名稱、版本、作者、`apiVersion`、能力、允許網域、登入方式、重試與限流策略、遮蔽名單追加、預設值、圖示，`0014:37`）、安裝檔標頭 `/* ==FMP Plugin==` … `==/FMP Plugin== */`、`1morr/fmp-plugins`、`index.json`（SHA-256）、`flutter_js`（QuickJS）、`fmp_source_id_literal`。官方 id：現有 `bilibili`；`youtube`、`netease` 等 id 字串 ADR 未寫。

---

### ADR 0015 — 測試與閘門、插件開發工具（§7）

**(a) M3 要做的**
- 插件開發工具（§決定 7，`0015:67-69`）：開發者模式下從資料夾載入插件（先限桌面，由平台層宣告）、重新載入、跑案例看 log、**以 App 內登入錄 fixture**、每插件切換真實／錄製／重播；命令列只負責重播（M1 更正：命令列也能錄製不需登入的案例）。版面見 ADR 0025。
- 檢查案例一份四用（§決定 4，`0015:59`）：`checks.json` 同一份用於契約測試、冒煙測試（`--live` 手動）、Debug 頁健康檢查、錄製。M3 加入 Debug 頁健康檢查（ADR 0025 §6）。
- fixture（§決定 5，`0015:60-62`）：錄製與重播在 dio 最底層的 `HttpClientAdapter`，寫檔前經正式遮蔽函式。現況這兩個 adapter 在 `app/test/plugins/contract/fixture_adapters.dart`；M1 `implement.md:201` 記「M3 的 App 內開發工具要用時移進 `lib/core/network/`，格式不變」。
- 新 lint（§決定 2 後續，`0015:51`）：`fmp_periodic_timer_owner`（ADR 0017，M3 加）；`fmp_toast_entry` 與 `fmp_design_tokens` 已在 M1／M2。

**(b) M3 的驗證**
- `fmp_periodic_timer_owner` 的雙向變異測試（`0015:54`）。
- 契約執行器對三個官方插件執行（`FMP_PLUGIN_DIR` 指到各插件目錄）；插件庫 CI 以固定 FMP 版本執行（`0015:66`）。
- 掃描所有 fixture 不得有未遮蔽憑證（`0015:101`，M1 已有 `fixture_scan_test.dart`）。
- `app/AGENTS.md` 列的每條靜態規則都寫出對應規則名（`0015:102`）：新增 lint 時同步。

**(c) 不在 M3**
- 冒煙測試排程上 CI（否決）；Android 插件開發（`0025:185`，需 SAF，另立 ADR）。

**(d) ADR 已固定的名稱**：`checks.json`、`fixtures/`（插件資料夾）、`pluginDevTools`（平台能力，`0025:94`）、`FMP_PLUGIN_DIR`、tag `live`、tag `health`（`0025:125`）。

---

### ADR 0017 — 背景排程器（移到 M3）與啟動維護清單

**(a) M3 要做的**
- `BackgroundScheduler`（§決定 1–5，`0017:27-42`）：會發網路請求的週期工作的唯一擁有者。M3 的真工作：電台直播狀態、收聽中的直播間資訊（固定 1 分鐘）（`0017:27`）。首頁排行、匯入歌單刷新屬 M4。
  - 工作宣告：id、所屬插件（可空）、間隔（空＝關閉）、執行函式；「上次成功時間」存資料庫；只用一個計時器指向最早到期的工作。
  - 只有 `resumed`／`inactive` 且網路 `Online` 才跑；`hidden`／`paused` 取消計時器、進行中的請求跑完；變可見或網路恢復時已到期工作各跑一次；啟動視同變可見（先顯示快取）。
  - 全域最多 2 個、同一插件依序；失敗依 1、2、4… 分鐘退避、上限為該工作間隔，`RateLimited.retryAfter` 優先。
  - 手動刷新不看間隔；插件停用／移除、榜單停用、歌單改不啟用、間隔設關閉時立即移除工作，代際檢查丟掉過期結果。
- 設定（§決定 6，`0017:43-44`）：排行刷新間隔 30／60／120／240 分或關閉（預設 60）；電台狀態間隔 關閉／1／3／5／10 分（預設 5）；匯入歌單每張 1／6／12／24／48／72／168 小時或不啟用（新匯入預設 24 小時）。M2 `design.md:65` 把「三組刷新間隔設定」列在 M3 排程器一起做。
- 啟動維護清單（M2 已實作，`app/lib/app/startup_maintenance.dart`）：M3 登記診斷包暫存清理（ADR 0025 §10；M2 `design.md:389` 寫「診斷包暫存（M3）…各自在它們的里程碑登記，M2 不放空的登記點」）。

**(b) M3 的驗證**（`0017:55-66`；`milestones.md:72`）
- 單元測試（假時鐘、假生命週期、假網路狀態）：看不見與離線時不跑；恢復後到期的工作各跑一次；只有一個計時器；手動刷新不看間隔；移除或停用後不再跑且丟掉過期結果；退避與 `retryAfter`；上次成功時間重啟後生效。
- lint `fmp_periodic_timer_owner`（`Timer.periodic`、`Stream.periodic` 只准在排程器與播放核心模組）＋雙向變異測試。現況 `lib/` 只有 `playback/queue_store.dart:217` 一處 `Timer.periodic`；規則表（`app/AGENTS.md:1431-1445`）沒有這條。

**(c) 不在 M3**
- 首頁排行（E14）、匯入歌單自動刷新（E4）具體工作（M4）。
- 播放位置存檔（播放核心）、下載、快取淘汰、log 輪替、更新檢查（`0017:28-33`）；`workmanager`、桌面縮到托盤時繼續跑（否決）。
- 更新檔清理（ADR 0022，M9）、孤兒曲目清理（ADR 0019，M2 已因 `tracks` 提前登記）。

**(d) ADR 已固定的名稱**：`BackgroundScheduler`（「service 層」）、「啟動維護清單」、`fmp_periodic_timer_owner`、狀態名 `Online`（ADR 0016）、間隔選項集合如 (a)。舊行為錨點：`main.dart:347-365`（電台輪詢只在看不見時暫停，#95）；`radio_refresh_service.dart:12-26,34,92-130`（舊間隔預設 5 分、被風控退避上限 30 分）。

---

### ADR 0018 — 播放核心（M3 部分：`mix`、`live`）

**(a) M3 要做的**
- `QueueModel` 模式 `mix`（插件 `mix` 能力，已播超過 100 首刪最舊的已播項目）與 `live`（`0018:38-39`）；`detached` 已於 2026-10-01 更正為不實作（`0018:41`）。現況只有 `queue`、`temporary`（`app/lib/playback/queue_model.dart:6-15`）。
- 跳過規則（§決定 7，`0018:51`）：跳過在 `queue`、`mix` 走下一首（D3），在 `temporary` 回到佇列；Mix 與普通佇列同樣處理（`phase2-plan.md:215`）。
- 直播（§決定 9，`0018:55-57`）：`PlaybackController.playLive` 經插件 `live` 能力取流、走同一個 `PlaybackSession`，開直播必然取消進行中的音樂請求（D8）；進入時記佇列快照、停止時回到原佇列；提前結束時先問插件是否仍在直播，是才以 1／3／10 秒重連 3 次；直播狀態查詢失敗顯示「查詢失敗」，不當成「未開播」（D10）；狀態輪詢與收聽中刷新由 ADR 0017 排程器負責。
- 持久化（§決定 10）：佇列持久化含「模式」「Mix 身分」；M2 `design.md:595` 寫「`Mix 身分` 與 `mode` 欄位在 M3 跟 Mix 一起加」（M2 的 `player_state` 沒有這兩欄）。
- 被取代的 `resolveStream` 取消網路工作（§決定 6）：M2 `design.md:70` 留給 M3 動插件 API 時設計。

**(b) M3 的驗證**（`0018:75-78`；M2 `design.md:928` 已把這兩條移到 M3）
- 單元測試：`QueueModel` 的 Mix 修剪；開直播取消進行中的音樂請求。
- `RecoveryPolicy` 的 live 重連（1／3／10 秒）無專條，歸在 §如何確認的 `RecoveryPolicy` 一般項。

**(c) 不在 M3**：Mix 的歌單 UI（`playlists.kind = mix`，M4，`0019:36`）；均衡器、響度、睡眠定時器；蘋果平台 AVPlayer 對 DASH／HLS 的實測（macOS、iOS 任務）。

**(d) ADR 已固定的名稱**：`playLive`、模式值 `mix`／`live`、Mix 100 首修剪、直播重連 1／3／10 秒、`PlaybackController`（`AudioController` 是舊名，`0025:112` 已更正）。舊行為錨點（`playback.md`）：Mix §3.11（禁隨機、禁加入／插入／打亂、清空退出 Mix，Mix 佇列只增不減）；電台 §3.12（取流 `/room/v1/Room/playUrl` 取 `durl` 第一個、`qn=80`、沒有到期時間；電台暫停實為 `stop()`）。

---

### ADR 0023 — 統一 Toast（M3 部分：詳細頁與回報）

**(a) M3 要做的**
- `ErrorReport`（§決定 4，`0023:56-65`）：錯誤發生時組裝一次並經遮蔽函式；內容：錯誤類型與原因、音源（插件 id 與版本）、使用者動作、請求摘要（方法、已遮蔽網址、狀態碼、耗時）、stack trace、App 版本與 flavor、系統與版本、ISO 8601 時間。
- 誰看得到：開發者模式下每則錯誤提示附「詳細」；一般使用者只有 `Unsupported`、`UnexpectedError` 附「回報」，開同一頁。
- 詳細頁：文字可選取；「複製」（Markdown）；「在 GitHub 回報」——先複製，再開新增 issue 頁（bug 範本），**內容不放進網址**；第一次使用提醒 repo 公開、送出前檢查。
- 新增 `.github/ISSUE_TEMPLATE/bug_report.yml`（`0023:89`；現況 repo 沒有 `.github/ISSUE_TEMPLATE/`）。
- Debug 頁錯誤歷史用同一個詳細頁（ADR 0025）。
- M1 `implement.md:276` 記：`ErrorReport`、詳細頁、「回報」延到 M3（與 Debug 頁一起）。

**(b) M3 的驗證**（`0023:94-101`）
- 單元測試：開發者模式與一般使用者的按鈕；`ErrorReport` 經遮蔽（假 cookie、token、簽名網址不出現在 Markdown）；GitHub 網址不含報告內容。
- widget 測試：全螢幕路由與對話框開啟時提示可見（M1／M2 已有；M3 新增的頁面路由要納入）。

**(c) 不在 M3**：系統層通知；桌面歌詞子視窗的錯誤轉送（M7，`0023:54`）。

**(d) ADR 已固定的名稱**：`ErrorReport`、「複製」「在 GitHub 回報」、`.github/ISSUE_TEMPLATE/bug_report.yml`、第一次提醒的「不再提醒」設定（與 ADR 0025 §10 診斷包提醒共用，`0025:156`）。`fmp_url_literal` 規定 URL 字面值只在 `lib/core/endpoints.dart`（`app/AGENTS.md:1439`），該檔現況不存在。

---

### ADR 0025 — Debug 頁與開發者模式（M3 的主體之一）

**(a) M3 要做的**
- 開發者模式（§決定 1，`0025:66-80`）：存「開發者」設定組，欄位 `developerMode`（空值：prod 關、dev flavor 開）、`logLevel`（空值＝info）；開啟＝「設定→關於」版本列連點 7 次（第 2 次起提示還差幾次，離開頁面計數歸零）；關閉＝Debug 頁「概覽」最上方總開關（同一筆寫入：`logLevel` 清空、卸載插件開發資料夾）；控制設定頁入口、錯誤提示「詳細」、log 可調到 debug、Debug 路由、插件開發工具；關閉時路由 redirect 回設定頁。
- 版面（§決定 2，`0025:81-96`）：沿用設定頁 list-detail；八個區塊：概覽、Log 與錯誤歷史、網路、播放狀態、音源健康檢查、插件開發（只在平台宣告 `pluginDevTools` 的平台出現，先限桌面）、資料庫、重設資料。
- Log 與錯誤歷史（§決定 3）：JSON Lines（M1 已實作）；預設看這次執行的記憶體歷史，「含之前的紀錄」才在 isolate 解析 log 檔（最多 6MB）；篩選層級／tag／文字；「只看錯誤」＝錯誤歷史，點一筆開詳細頁；動作：複製已篩選、匯出 log 檔、「清除 log」同時清記憶體與檔案。（保留 7 天已在 M2 完成。）
- 網路（§決定 4）：資料來源是 log 門面的網路摘要（tag `network`，M1／M2 已寫）；清單欄位時間／方法／主機／路徑／狀態／耗時／大小／音源；篩選音源／狀態碼類別／文字；單筆詳細含遮過的 query、錯誤類型、對應錯誤紀錄。
- 播放狀態（§決定 5）：唯讀；顯示 sealed 狀態、曲目（插件 id、曲目鍵）、串流（格式、位元率、容器、來源類型）、音訊後端、輸出裝置、重試次數與下次重試時間、佇列（總數、目前索引、前後各 5 首、隨機與循環模式）；位置每秒刷新；「複製快照」JSON，串流網址經遮蔽。M2 `design.md:71`：這些欄位「M3 有讀的人時再加」，現況 `PlaybackState.Retrying` 已帶 `attempt` 與 `delay`。
- 音源健康檢查（§決定 6）：對已安裝且啟用的插件以真實連線跑 `checks.json`；手動觸發「全部」或單一插件、一次一個插件；結果每案例通過／失敗、耗時、`AppError` 類別，未登入案例標「略過」；以 tag `health` 經門面寫入。
- 插件開發（§決定 7）：`file_selector.getDirectoryPath` 選資料夾、路徑記在「開發者」組；資料夾中的插件標「開發中」，本次執行取代同 id 已安裝插件；「重新載入」＝拆掉該插件 JS runtime 再重建；每插件可切換真實、錄製、重播；錄製的 fixture 經遮蔽寫到插件資料夾 `fixtures/`；案例可單跑或全跑，顯示已遮蔽的回傳值與錯誤。
- 資料庫（§決定 8）：唯讀瀏覽 `allTables` 與筆數、`select(table)` 每頁 50 列、每個值經遮蔽、插件 storage 表整欄遮蔽；「檢查」按鈕只報告：`PRAGMA integrity_check`、`foreign_key_check`、孤兒曲目數、「檔案遺失」的下載數；有問題時提供「從備份還原」與「重設資料」；不在啟動時自動檢查。
- 重設資料（§決定 9）：清空資料庫（含設定）、secure storage 中 FMP 的憑證、快取；不動已下載檔與 sidecar、log 檔；流程：①以 ADR 0010 的備份格式自動備份到資料目錄 `backups/` ②對話框列出備份位置、二次確認 ③清空後重啟；備份失敗就不清空。
- 診斷包（§決定 10）：`diagnostics.txt`、`diagnostics.json` 加目前的 log 檔；動作：「複製」（純文字摘要）、「存檔」（`fmp-diagnostics-<時間>.zip`；桌面 `file_selector.getSaveLocation`，Android 系統建立文件對話框）、「分享」（`share_plus`，只在平台層宣告能分享檔案的平台顯示）；第一次匯出提醒「送出前請檢查」；暫存 zip 分享後刪除，殘留由啟動維護清單清掉。
- M1 follow-up：診斷包不得含帳號名稱，啟動 log 的 `App started` 帶 `dataDirectory`（含系統使用者名稱），M3 做診斷包時處理（M1 `implement.md:222`）。

**(b) M3 的驗證**（`0025:188-211`）
- `fmp_platform_checks`：Debug 模組只讀平台層宣告的能力。
- 單元測試：開發者模式（連點 7 次開啟並寫入、關閉時 `logLevel` 清空與資料夾卸載、dev flavor 預設開）；log 檔 JSON Lines 讀回與壞行略過（M1 已有）；網路篩選；資料檢查（關外鍵寫入違規列再開，報告會列出；乾淨資料庫無問題）；重設（備份失敗時不清空、成功時已下載檔仍在）；遮蔽（播放快照、資料庫瀏覽、診斷包不含假憑證與假簽名網址）。
- widget 測試：開發者模式關閉時直接進 Debug 路由會被 redirect；未宣告 `pluginDevTools` 的平台不顯示插件開發區塊；未宣告檔案分享的平台不顯示「分享」。
- **加入 Debug 頁的里程碑實測**（`milestones.md:74`）：見 §0。

**(c) 不在 M3**：記憶體磚；在 App 內編輯資料庫；每次啟動自動檢查；自動修復損壞資料庫；檔案監看自動重載插件；Android 插件開發（需 SAF，另立 ADR）；資料庫打不開時的啟動錯誤畫面（由啟動流程任務決定，`0025:184`）。

**(d) ADR 已固定的名稱**：`developerMode`、`logLevel`、`pluginDevTools`、八個區塊名、`backups/`、`fmp-diagnostics-<時間>.zip`、`diagnostics.txt`／`diagnostics.json`、tag `health`、`file_selector`（`getDirectoryPath`、`getSaveLocation`）、`share_plus`。舊版錨點（`devtools.md`）：開發者選項頁 `developer_options_page.dart`、`log_viewer_page.dart`、`database_viewer_page.dart`；連點 7 次在 `settings_about.dart:4-39`、`developer_options_provider.dart:49`。

---

### ADR 0013 — 錯誤模型（M3 部分）

- (a) 各音源在自己的目錄內以對應表把狀態碼與錯誤碼轉成 `AppError`（含 ADR 0012 的「憑證無效」判定，`0013:39-40`）——YouTube、網易插件各一份（M2 digest 記為「M3 加入 YouTube／網易時」）；YouTube 的「確認你不是機器人」歸 `VerificationRequired`（`0013:35`）；呈現表中屬 M3 的行：需登入「提示並附『登入』」、憑證無效「刷新一次，刷新失敗才提示一次需重新登入」、風控驗證「提示並建議登入、貼上 cookie 或稍後再試」（`0013:52-54`）。
- (b) 契約測試：每個音源以錄下的錯誤回應 fixture 斷言對應到的 `AppError` 類別（`0013:75`）。
- (c) B 站 geetest 驗證互動不做（待辦，`0013:28`）。
- (d) `AppError` 十個子類（`AuthRequired`、`CredentialInvalid`、`VerificationRequired` 等，M1 已有）。

### ADR 0011 — 設定與日誌（M3 部分）

- (a) 「每個音源的設定另一張表，以音源 id 為主鍵」（`0011:46`）：M3 引入（放「以登入身分瀏覽與播放」開關，`0012:50`）；「開發者」組（ADR 0025）；ADR 0026 §決定 2：各組欄位在引入它的里程碑定案；診斷包（`0011:42-43`：版本、平台、語系、各音源啟用與登入狀態（是／否）、非敏感設定摘要、已遮蔽 log 與錯誤歷史；不含硬體識別、帳號名稱、歌單內容）；憑證登記到遮蔽函式（`0011:35-36`）。
- (b) 設定測試（寫入使用者值後改預設，仍讀到使用者值）；遮蔽測試（每個音源一組假憑證與假簽名 URL，經 log 檔、記憶體歷史、診斷包、網路紀錄都不再出現）。
- (c) 其他設定組（音樂庫與同步、下載、歌詞、桌面）。
- (d) 組名八個；`SettingsGroup` 現況三個（外觀、播放、網路，`app/lib/ui/settings/settings_page.dart:13-16`）。

### ADR 0016 — 快取與離線（M3 部分）

- (a) 移除插件時刪除其快取項目：M2 已做 `CacheStore.removePlugin`，事件來源是插件頁「移除」，M3 接上時只呼叫那一個方法（M2 `design.md:305-306`）。離線時「插件安裝與更新、登入、電台與直播」顯示離線狀態、不送請求，用 M2 的共用離線空狀態元件（`0016:46-50`；M2 `design.md:369` 寫「其餘頁面（…插件、登入）跟著各自的里程碑」）。插件更新後重新解析：M2 只有單元測試，M3 有插件頁才有實機入口（M2 `implement.md:655`）。
- (b) widget 測試：插件頁、登入、電台頁在離線時顯示離線狀態。
- (c) 排行快取（M4）、歌詞快取（M7）。
- (d) 見 M2 digest。

### ADR 0009 / 0010 / 0019 / 0024 / 0026 / 0027 — 與 M3 相關的摘要

- ADR 0009 `0009:39-45`：平台層能力清單含「登入 WebView」，**沒有選套件**；`PlatformCapabilities` 現況沒有登入 WebView、`pluginDevTools`、檔案分享欄位（`app/lib/platform/platform_capabilities.dart`）。§決定 6 列 `file_picker` 五平台共用。新能力依 `.trellis/spec/app/platform/index.md` 的五步加。
- ADR 0010：`legacy_import` 讀舊憑證要 `flutter_secure_storage` 10.x，新憑證存放與升 11.x 的條件「在網路與帳號的 ADR 決定」（`0010:78`）＝ADR 0012 §決定 3；M5 才用。
- ADR 0019：`playlists.kind`＝`local`／`imported`／`mix`（`0019:36`），Mix 的歌單形態屬 M4。`libraryWrite` 只對已登入且具備能力的音源出現入口（`0019:54`）。
- ADR 0024：設定頁依 ADR 0011 分組、list-detail（`0024:89`）；「容易卡住處就地說明：首次引導、權限說明、快捷鍵清單」（`0024:118`）；導覽與斷點見 §決定 3。ADR 0024 沒有插件頁、帳號頁、電台頁的版面。
- ADR 0026：M3 的 PR 子任務結構、擁有者核准一次 prd／design／implement（`0026:53-64`）。
- ADR 0027：預設重播；真實連線條件（`0027:36-41`）。M3 開始，「改動本身是插件、網路層、登入」成為常態，真實模式的使用規則會被頻繁引用。

---

## 2. 前面里程碑留給 M3 的待辦

| # | 待辦 | 來源 |
|---|---|---|
| 1 | 被取代的 `resolveStream` 取消網路工作：需要宿主知道每個 `fmp.http.request` 屬於哪一次插件呼叫（改宿主 API 呼叫上下文），留給 M3 動插件 API 時一起設計 | M2 `design.md:70`；`app/AGENTS.md:441-442` |
| 2 | **Android 上時長未知的前瞻永遠接不上**：just_audio 後端等事件帶時長才確認交接；時長未知的串流照樣出聲但 App 停在上一首。「M3 加 YouTube／直播類插件前要實機找別的載入訊號」 | M2 `implement.md:680` |
| 3 | `fmp-plugin.d.ts` 沒有規定候選的備援順序（只是 B 站的決定）；M3 寫網易插件時再看要不要成為規範 | M2 `implement.md:702` |
| 4 | `previewOnly` 的輸出欄位 B 站不需要，只在測試插件 `fmp-test` 用；M3 的網易插件使用 | M2 `design.md:901` |
| 5 | B 站插件標題沒解 HTML 實體（`&#x27;` 原樣顯示）：問題在 `1morr/fmp-plugins` | M2 `implement.md:786`、`research/m2-acceptance.md:68` |
| 6 | B 站插件回傳原圖網址（每張最大約 885 KB）：應回傳多種尺寸（hdslb 的 `@160w` 後綴），宿主 `pickArtwork` 已會挑；在 fmp-plugins 處理 | M2 `implement.md:637` |
| 7 | B 站插件 manifest 仍是 0.1.0（沒有發佈版本） | M2 `implement.md:703` |
| 8 | 「插件更新後重新解析」只有單元測試；M3 有插件頁才有實機入口 | M2 `implement.md:655` |
| 9 | 冪等只看 HTTP 方法；YouTube innertube 與網易查詢是 POST、照規則不會重試；讓音源標記「語意冪等的 POST」屬 M3 加入這兩個插件時決定（RFC 9110 §9.2.2 允許） | M1 `implement.md:159` |
| 10 | 探測的取捨：插件若無限迴圈呼叫宿主 API，每次都回應探測，只會一直得到 `NetworkError`、不會被停用；M3 插件頁若要讓使用者手動停用，一併處理 | M1 `implement.md:195` |
| 11 | 錄製與重播的 adapter 在 `app/test/plugins/contract/`；M3 的 App 內開發工具要用時移進 `lib/core/network/`，格式不變 | M1 `implement.md:201` |
| 12 | 登入後 `_AuthInterceptor` 以 `headers.addAll` 注入 `Cookie`，會整個蓋掉插件送的匿名 `buvid3`（舊專案是合併）；M3 登入任務決定合併或交給插件 | M1 `implement.md:210` |
| 13 | 啟動 log `App started` 帶 `dataDirectory`（含系統使用者名稱）；做診斷包時遮掉或去掉 | M1 `implement.md:222` |
| 14 | 插件每重新載入一次，`Redactor._mediaCdns` 多一份相同規則；M3 插件頁的重新載入出現時一併去重 | M1 `implement.md:231` |
| 15 | 媒體 CDN 簽名參數目前整個拿掉，內建名單每變嚴格一次既有 fixture 就過不了「再遮蔽一次不變」掃描（審查建議改成「值遮蔽」） | M1 `implement.md:230` |
| 16 | `ErrorReport`、詳細頁、「回報」延到 M3 | M1 `implement.md:276` |
| 17 | Debug 頁要讀的播放資料（下次重試時間、串流格式等）M3 有讀的人時再加 | M2 `design.md:71` |
| 18 | `Mix 身分` 與 `mode` 欄位在 M3 跟 Mix 一起加（M2 `player_state` 沒有） | M2 `design.md:595` |
| 19 | 詳細欄（`trackDetail`）M3 有時補；M2 的詳細分頁只放現有資料 | M2 `design.md:69,799` |
| 20 | M2 驗收沒實機驗的項目（鎖定畫面控制、Windows 實體媒體鍵、Android 永久失去焦點、Windows 斷網）；與 M3 範圍無直接關係，不列為 M3 工作 | M2 `implement.md:787-791` |

---

## 3. 與其他里程碑的交界

| 交界 | 內容 | 出處 |
|---|---|---|
| M3→M4 | Mix 的歌單形態（`playlists.kind=mix`）、歌單卡「Mix 播放」、匯入 Mix 簡寫 `youtube_mix_shorthand.dart` 屬歌單功能（M4）；M3 只做佇列的 `mix` 模式與播放 | `0019:36`；`features.md:61,79,103,142` |
| M3→M4 | `importPlaylist`／`libraryRead`／`libraryWrite`／`charts` 四個能力、帳號頁「帳號歌單匯入」；B 站收藏夾需登入（`AuthRequirement.required`）；排行與匯入歌單刷新是排程器的 M4 工作 | `milestones.md:79-82`；`0017:27` |
| M3→M4 | 備份與還原（E16，新格式）在 M4；ADR 0025 重設資料與「從備份還原」使用「ADR 0010 的備份格式」（見矛盾 1） | `milestones.md:82`；`0025:146` |
| M3→M5 | 舊憑證匯入（10.x→11.x `CredentialStore`）、legacy import 偵測舊音源並提示一鍵安裝（需插件安裝流程）、未安裝前曲目標示「音源未安裝」；M5 的錯誤頁含「匯出診斷」 | `milestones.md:89-90`；`0010:55-58`；`0014:52-53` |
| M3→M5 | M3 新增的表（每音源設定、排程器上次成功、帳號顯示資訊等）的舊資料對照要到 M5 寫（ADR 0026 §決定 2「M5 起」） | `0026:66-67` |
| M3→M6 | 下載的「檔案遺失」數顯示在 Debug 資料庫區塊（M3 無下載紀錄）；`resolveStream` 用途＝下載；媒體 client 已在 M2 建好 | `0025:138`；`milestones.md:97` |
| M3→M7 | 歌詞插件（`lyrics`、`aiAssist`）、網易歌詞源；ADR 0014 §決定 2 把「歌詞源（網易、QQ、lrclib）」列為與可播放音源並列的類別，沒說網易播放插件與網易歌詞源是否同一個插件（見未定之處 9 的備註） | `0014:34-36`；`0021:40-44` |
| M3→M8 | 無直接交界（托盤／全域快捷鍵）；設定頁「鍵盤快捷鍵」M8 | `milestones.md:114` |
| M3→M9 | 「關於」頁與 `docs/user-guide.md` 屬 M9，但 ADR 0025 的開發者模式開啟入口在「設定→關於」版本列（M3） | `milestones.md:123`；`0025:70` |
| M3→M9 | `index.json` 的發佈與插件庫 CI 用的「固定 FMP 版本」；FMP 的 `app-release.yml` 在 M9 前只手動跑 | `0015:66`；根 `AGENTS.md` |

---

## 4. 現況（查證 2026-10-08）

### 4.1 `app/`

| 檔案 | 一行 |
|---|---|
| `app/lib/plugins/source_plugin.dart` | `SourcePlugin` 介面只有 `search`、`resolveStream`（檔頭「方法只在引入它們的里程碑加」）、`health`、`whenUnresponsive`、`close` |
| `app/lib/plugins/manifest/plugin_manifest.dart` | 12 個能力列舉齊全；`login` 欄位非空時整個拒收（`:249-250`）；`hostApiVersion = 1` |
| `app/lib/plugins/types/fmp-plugin.d.ts` | 型別定義；`FmpPluginExports` 只有 `search`、`resolveStream`（`:263`）；`FmpChecks` 只有這兩個鍵（`:282`）；`credentials.get()`「M1 一律 null」（`:204`）；物件欄位封閉，多出欄位整個拒收 |
| `app/lib/plugins/plugin_registry.dart` | 啟動載入 `installed_plugins`、`register`（更新取代）、每插件媒體 client；沒有移除路徑；沒有啟用／停用狀態 |
| `app/lib/plugins/install/{plugin_installer,dev_plugin_entry}.dart` | `installBytes`／`installSource`；dev 的 `--fmp-dev-plugin=` 入口（prod 不讀）；沒有選檔 UI、沒有安裝前確認 UI、沒有 index 讀取 |
| `app/lib/core/network/auth.dart` | `AuthRequirement`、`decideAuth`、`CredentialSource` 介面、`NoCredentials`（目前唯一實作） |
| `app/lib/core/network/{source_http_client,media_http_client,network_status,interceptors,network_log,...}.dart` | 每插件一個 dio＋記憶體 cookie jar、媒體 client、`NetworkStatusNotifier`、網路紀錄 tag `network` |
| `app/lib/core/errors/{app_error,report_error}.dart` | sealed `AppError` 十個子類；`Log.report`（錯誤歷史寫入口）；沒有 `ErrorReport` |
| `app/lib/core/logging/log_file.dart` | JSON Lines 輪替 2MB×3，M2 加 7 天保留；沒有檢視／篩選 UI |
| `app/lib/playback/queue_model.dart` | `QueueMode` 只有 `queue`、`temporary`；`playback_state.dart`、`recovery_policy.dart`、`playback_session.dart` 等 M2 已拆出 |
| `app/lib/playback/queue_store.dart` | 佇列持久化；`:217` 是 `lib/` 唯一的 `Timer.periodic`（位置存檔） |
| `app/lib/app/startup_maintenance.dart` | 啟動維護清單：現有 log 保留與孤兒曲目兩項（`startupMaintenanceTasksProvider`） |
| `app/lib/data/database/tables.dart` | 主資料庫 10 張表：`appearance_settings`、`network_settings`、`playback_settings`、`installed_plugins`（id、version、manifestJson、script、installedAt）、`plugin_storage`、`tracks`、`queue_entries`、`player_state`、`play_history`、`layout_state`，另 `cache.db`（`lib/data/cache/`）。沒有帳號、每音源設定、排程器、電台表 |
| `app/lib/ui/shell/app_shell.dart` | 導覽三項：搜尋、歷史、設定（`:270-290`） |
| `app/lib/ui/settings/settings_page.dart` | `SettingsGroup` 三組：外觀、播放、網路（`:13-16`）；沒有帳號、插件、關於、開發者 |
| `app/lib/ui/search/{search_page,source_chips}.dart` | 搜尋頁與音源 chip 列（只收有 `search` 能力的插件）；沒有「沒有任何插件」的引導 |
| `app/lib/ui/player/{player_page,queue_view,track_details}.dart` | 播放頁 B、佇列分頁、詳細分頁（只放現有資料）|
| `app/lib/ui/toast/{toaster,toast_host}.dart` | `Toaster.error(AppError)` 無「詳細」「回報」按鈕 |
| `app/lib/ui/offline/offline.dart` | 離線空狀態元件與全域離線提示 |
| `app/lib/platform/{audio,cache_directory,cache_sizes,connectivity,fonts,media_controls,app_data_directory}/` | 已有的平台能力；沒有登入 WebView、`pluginDevTools`、檔案儲存／分享 |
| `app/test/plugins/contract/` | 契約執行器（`contract_runner`、`checks`、`fixture`、`fixture_adapters`、`credential_scan`、`record_test`）；`app/test/fixtures/plugins/{test_plugin,http_test_plugin}` |
| `app/packages/fmp_lints/lib/src/rules/` | 13 個規則檔（含 `toast_entry`、`design_tokens`、`material_import`）；沒有 `periodic_timer_owner` |
| `app/pubspec.yaml` | **沒有** `flutter_secure_storage`、任何 WebView 套件、`file_selector`、`file_picker`、`share_plus`、`url_launcher`、zip 套件（grep 無）；已有 `cookie_jar`、`dio_cookie_manager`、`flutter_js`、`connectivity_plus`、`path_provider` |
| `.github/ISSUE_TEMPLATE/` | 不存在；`.github/workflows/` 有 `ci.yml`、`release.yml`、`app-release.yml` |
| `app/lib/core/endpoints.dart` | 不存在（`fmp_url_literal` 規定 URL 字面值只在這個檔） |

### 4.2 `1morr/fmp-plugins`（本機 `C:\Users\Roxy\orca\fmp-plugins`，HEAD `33caa3a`）

| 內容 | 一行 |
|---|---|
| `bilibili/bilibili.js`、`checks.json`、`fixtures/{search,resolveStream}`、`README.md` | 唯一的插件；manifest 0.1.0，能力只有 `search`、`resolveStream`；`resolveStream` 檢查含 `expiresAtPattern` |
| `README.md`、`LICENSE`（MIT）、`.gitattributes`、`.gitignore` | README 寫「開發中…目前沒有發佈版本」，契約測試靠 checkout FMP 後 `FMP_PLUGIN_DIR=… flutter test` |
| （不存在） | `.github/`（沒有 CI）、`index.json`、YouTube／網易目錄、版本發佈 |

### 4.3 舊版 App（`lib/`，已凍結）的相關行為與位置——供「看成熟產品怎麼做」參考

| 主題 | 行為 | 檔案 |
|---|---|---|
| YouTube 音源 | `youtube_explode`＋InnerTube；串流先匿名（androidVr／ios／safari 等），失敗才同 streamType 帶 auth 打 WEB `/player`；URL 期限寫死 1 小時（D9）；排行是 YouTube Music「New This Week」歌單；Mix（`DynamicPlaylistSource`）；音質 `qualityLevel`＋`formatPriority`（opus／aac）| `lib/data/sources/youtube_source.dart`（`sources.md` §1.1） |
| 網易雲音源 | eapi `/song/enhance/player/url/v1`；`search()` 收了 `order` 沒用；試聽片段當完整歌曲播（D4）；寫入請求附偽造 `X-Real-IP: 118.88.88.88`（B3）；音質映射 `lossless`／`exhigh`／`standard`；歌單 URL 與 `163cn.tv` 短網址；熱歌榜 `3778678` | `lib/data/sources/netease_source.dart`、`netease_playlist_service.dart:240-253` |
| B 站分 P（E2） | `PagedVideoSource`；搜尋結果展開分 P 列（`_PageTile`）；匯入時展開多 P；以 `cid` 區分（ADR 0005）| `bilibili_source.dart:649-680`；`search_page.dart:1082`；`import_service.dart:205,454,588` |
| Mix（E13） | YouTube 專屬；入口是歌單卡「Mix 播放」與匯入 Mix 簡寫；禁隨機、禁加入／插入／打亂、清空退出；佇列只增不減；重啟恢復 Mix；Mix 不跳過不可播的歌（推測非刻意，D3） | `mix_session_coordinator.dart`、`playlist_card_actions.dart:26-71`、`youtube_mix_shorthand.dart`、`playback.md` §3.11 |
| 電台直播（E12） | 只支援 B 站直播間；「電台」是使用者存的清單（`RadioStation`，URL 新增、搜尋頁直播結果「加為電台」、排序、刪除；`isFavorite` 欄位無 UI 入口）；帳號頁「粉絲勳章牆」匯入電台；電台頁＋電台全螢幕播放頁＋首頁電台區塊；直播狀態輪詢預設 5 分、被風控退避上限 30 分、背景暫停；收聽中每秒更新時長、每分鐘刷新高能用戶數；繞過控制器直接操作後端（D8）| `lib/services/radio/`、`lib/ui/pages/radio/`、`lib/data/models/radio_station.dart`、`bilibili_live_client.dart`；`features.md` §7、`playback.md` §3.12 |
| 帳號與登入 | B 站：WebView（行動 UA）＋QR 兩分頁，cookie refresh 流程（RSA-OAEP＋correspond＋refresh_csrf）；YouTube：僅 WebView（桌面 Chrome UA，Android 去掉 `;wv`），取 cookie 與 `DATASYNC_ID`、JS 呼叫 `accounts_list` 取帳號名（B14）；網易：Android WebView＋QR、Windows 只有 QR，驗證 `/api/nuser/account/get`；Isar `Account` 列存非敏感狀態、secure storage 存憑證；啟動時 `verifyAllAccountStatuses` | `lib/services/account/`、`lib/ui/pages/settings/{bilibili,youtube,netease}_login_page.dart`、`account_management_page.dart`；`accounts-network.md` §1、§6 |
| 登入 WebView 套件 | `flutter_inappwebview ^6.1.5`（Windows 為 WebView2）、`flutter_secure_storage ^10.3.1` | 舊 `pubspec.yaml:66,73` |
| 開發者模式與 Debug 頁 | 連點 7 次版本列、只存記憶體；開發者選項頁（記憶體、日誌層級、資料庫檢視器 11 collection、重設所有資料直接 `isar.clear()`）；`DataIntegrityRepository.scan/repair` 零呼叫點 | `developer_options_page.dart`、`log_viewer_page.dart`、`database_viewer_page.dart`；`devtools.md` §1–§3 |
| 設定頁區塊 | 帳號管理 → 外觀 → 播放 → 快取 → 儲存 → 備份 → 桌面 → 關於 → 開發者選項（隱藏） | `settings_page.dart:64-196`（`features.md:201`）|

---

## 5. 新增的依賴套件（尚未在 `app/pubspec.yaml`）

只列 ADR 或程式現況需要但沒有的；本檔不加依賴、沒有查版本。

| 套件 | 出處 | 用途 |
|---|---|---|
| `flutter_secure_storage` 11.x | ADR 0012 §決定 3 | `CredentialStore` |
| （登入 WebView 套件） | ADR 0009 能力清單、ADR 0012 §決定 4 | App 內網頁登入；ADR 沒有指名套件（舊版 `flutter_inappwebview`）|
| `file_selector` | ADR 0025 §決定 7、10 | 選插件資料夾、存診斷包 zip |
| `file_picker` | ADR 0009 §決定 6 | 「五平台共用」；ADR 0025 `:185` 提到它沒有 SAF |
| `share_plus` | ADR 0025 §決定 10 | 分享診斷包 |
| （開網址的套件） | ADR 0023 §決定 4 | 「在 GitHub 回報」開瀏覽器；ADR 沒有指名套件 |
| （zip 套件） | ADR 0025 §決定 10 | 產生診斷包 zip；ADR 沒有指名套件 |
| （QR 顯示套件） | ADR 0012 §決定 4 | B 站／網易 QR 登入畫面；ADR 沒有指名套件 |

---

## 6. M3 範圍總表

| `milestones.md` M3 範圍 | ADR 章節 | 備註 |
|---|---|---|
| YouTube 插件 | ADR 0014 §決定 2、10；ADR 0013 §決定 2；ADR 0012 §決定 4–6 | 探針已過；錯誤對應表、憑證無效判定表要寫 |
| 網易雲插件 | ADR 0014 §決定 2、5；ADR 0013；ADR 0012 | `previewOnly` 使用者；B3 `X-Real-IP` 先實測（`phase2-plan.md:181`）；QR 為主 |
| B 站分 P（E2） | ADR 0014 §決定 4（`multiPart`）；ADR 0005 | 契約未定（未定之處 5）|
| Mix（E13） | ADR 0014 §決定 4（`mix`）；ADR 0018 §決定 4 | 入口未定（未定之處 4）|
| 電台直播（E12） | ADR 0014 §決定 4（`live`）；ADR 0018 §決定 9；ADR 0017 §決定 1、6 | 資料與頁面無 ADR（未定之處 3）|
| 帳號、`CredentialStore`、`AuthRequirement` | ADR 0012；ADR 0011 §決定 7 | `AuthRequirement` M1 已有 |
| 插件庫、CI、`index.json` | ADR 0014 §決定 6；ADR 0015 §決定 6 | 未定之處 15、16 |
| 插件頁、首次啟動引導 | ADR 0014 §決定 6–8；ADR 0016 §決定 7 | 無版面 ADR（未定之處 7、18–20）|
| Debug 頁、插件開發工具 | ADR 0025；ADR 0015 §決定 4、7 | 八區塊 |
| 錯誤詳細頁、GitHub 回報、`bug_report.yml` | ADR 0023 §決定 4 | |
| 背景排程器、`fmp_periodic_timer_owner`、電台狀態 | ADR 0017 | 未定之處 25 |
| `QueueModel` 的 `mix`、`live` | ADR 0018 §決定 4、9、10 | M2 `design.md:595` |
| 驗收 | `milestones.md:70-74`；ADR 0027 | 未定之處 1、33 |

---

## 7. 矛盾與不一致（列出，不判斷）

1. **ADR 0025 §決定 9 與 ADR 0010／`milestones.md`**：重設資料第 1 步「以 ADR 0010 的備份格式自動備份到 `backups/`」（`0025:146`），「資料庫」區塊也提供「從備份還原」（`0025:139`）；但 ADR 0010 的決定文字沒有定義備份格式（`0010:5` 的影響範圍寫了「備份格式」，§決定 1–4 沒有對應條目）；「新格式的備份與還原」（E16）屬 M4（`milestones.md:82`）。M3 的重設資料依賴一個 M4 才有的功能。
2. **套件名**：ADR 0009 §決定 6 寫 `file_picker` 五平台共用（`0009:51`）；ADR 0025 §決定 7、10 寫 `file_selector.getDirectoryPath`／`getSaveLocation`（`0025:128,153`），同一 ADR `:185` 又說「file_picker 沒有 SAF」。
3. **排程器在哪個里程碑**：ADR 0017 §決定 1「清單在 M2 實作，ADR 0026」未提排程器本體的里程碑；ADR 0026 §決定 3 的表 M2 列「背景排程器」（`0026:72`），`0026:84` 的修訂才把它移到 M3；M3 在 ADR 0026 表的描述（`0026:75`）也沒有電台、Mix、分 P、排程器。`milestones.md:56,69` 與 M2 `design.md:65` 已是 M3。ADR 0017 本文沒有修訂註記。
4. **「關於」頁的里程碑**：ADR 0025 §決定 1 的開啟入口是「設定→關於」版本列（`0025:70`）；`milestones.md:123` 把「關於頁」列在 M9。M3 需要至少一個可以連點的版本列。
5. **ADR 0012 §決定 6 與舊版預設**：新設計三音源皆開（`0012:51`）；舊版 YouTube 預設關（`questions.md:161`、`accounts-network.md` §7.4）。ADR 本身已寫明這是改動並要在發行說明交代（`0012:52`），列在這裡因為 M5 匯入舊開關值、M3 設預設時會直接遇到。
6. **匿名 cookie 的存放**：ADR 0012 §決定 1「匿名用的非機密 cookie（例如 B 站 `buvid`）存資料庫」（`0012:31`）；M1 實作是由插件從 `Set-Cookie` 取值寫進自己的 `plugin_storage`（`app/AGENTS.md:531-533`）。字面不同（兩者都在資料庫）。
7. **直播重連與音樂重試的秒數**：ADR 0018 §決定 7 重試 1／3／9 秒（`0018:47`），§決定 9 直播重連 1／3／10 秒（`0018:57`）。同一 ADR 內兩組不同數字，沒有說明是否刻意。
8. **mix 的兩個層次**：ADR 0018 §決定 4 `QueueModel` 模式 `mix`（M3）；ADR 0019 §決定 1 `playlists.kind = mix`（M4，`0019:36`）；ADR 0018 §決定 10 的「Mix 身分」持久化格式在兩者之間沒有對應說明。
9. **`checks.json` 能力範圍**：ADR 0015 §決定 4「每插件每能力最多一條檢查案例」（`0015:59`）；現況 `FmpChecks` 只收 `search`、`resolveStream`（`fmp-plugin.d.ts:282`；`SourcePlugin` 也只有這兩個方法）。新能力需要擴充，ADR 沒有寫格式。
10. **ADR 0015 §決定 6 的更正與 §決定 7 的需求**：M1 更正寫「錄製與重播的 adapter 放進 `lib/` 也違反分層」（`0015:66`，指獨立套件）；App 內開發工具必須在 `lib/` 裡錄製與重播（`0015:67-69`）。M1 `implement.md:201` 已記「M3 移進 `lib/core/network/`」，但 ADR 0015 本文沒有同步。
11. **宿主 API v1 的擴充與封閉欄位**：ADR 0014 把擴充限定為「發佈前在 v1 內」（`0014:46-47`）；`fmp-plugin.d.ts` 檔頭寫「多出不認得的欄位，宿主整個拒收」。何時算「發佈」ADR 沒有寫（M3 的 `index.json` 與插件庫 CI 是第一次有發佈物）。
12. **設定組與頁面**：ADR 0011 §決定 7 的八個設定組沒有「帳號」「插件」；ADR 0024 §決定 6 的設定頁依這八組分（`0024:89`）。帳號頁、插件頁、Debug 頁入口的位置，兩份 ADR 都沒有寫（舊版設定頁第一區就是「帳號管理」，`features.md:201`）。
13. **M3 驗收只列四項**：M2 的驗收明列 ADR 測試範圍（`milestones.md:59`）；M3 的驗收（`milestones.md:70-74`）沒有 ADR 0012、0014、0015、0023、0025 的測試項。
14. **`trackDetail` 沒有里程碑**：ADR 0014 §決定 4 列為能力（`0014:38`）；`milestones.md` 全文沒有 `trackDetail`；M2 `design.md:69,799` 寫「M3 有 `trackDetail` 時補」。

---

## 8. 未定之處

每條列出處與為什麼要擁有者決定。分類：A 範圍與驗收、B 插件契約、C 插件庫與插件頁、D 帳號、E 排程器、F 開發工具與回報。這一節只寫問題，不寫建議。

### A. 範圍與驗收

1. **M3 驗收要涵蓋哪些測試與實測。** `milestones.md:70-74` 只有四項；ADR 0012、0014、0015、0023、0025 各有「如何確認」（`0012:69-75`、`0014:77-82`、`0023:91-101`、`0025:188-211`）。「登入」在 `milestones.md:62`「三個音源都能搜尋、播放、登入」的意思——三個音源各自哪種登入方式（B 站 QR、網易 QR 與 Windows 沒有網頁登入、YouTube 網頁登入或貼上 cookie）算通過——ADR 沒有逐項寫。
2. **`trackDetail`（曲目詳細）歸哪個里程碑。** ADR 0014 §決定 4 有這個能力；`milestones.md` 沒有；M2 把播放頁「詳細」分頁留成「只放現有資料」並註「M3 有 trackDetail 時補」（M2 `design.md:69,799`）。M3 要不要做會影響插件 DTO 與播放頁詳細分頁。
3. **電台（E12）的資料、頁面與入口。** `questions.md:250` 勾「保留」，ADR 0014、0017、0018 只規定 `live` 能力、直播狀態輪詢、`playLive`。沒有 ADR 定：電台清單（舊版 `RadioStation`：URL 新增、排序、刪除、`isFavorite` 無 UI 入口）的資料表；導覽入口（現有導覽是搜尋、歷史、設定）；搜尋頁「直播間」結果與「加為電台」；帳號「粉絲勳章牆」匯入電台（舊 `bilibili_account_service.dart:529`，屬 `libraryRead` 還是電台專屬）；電台全螢幕播放頁；首頁電台區塊（首頁屬 M4）。排程器的第一個真工作（電台狀態）輪詢的對象就是這份清單。
4. **Mix（E13）在沒有歌單的 M3 從哪裡開始，以及行為規則。** 舊入口是歌單卡「Mix 播放」與匯入 Mix 簡寫（`features.md:61,79,103,142`），歌單屬 M4（`0019:36`）。ADR 0018 §決定 4 只寫「`mix`（插件 `mix` 能力，已播超過 100 首刪最舊的已播項目）」。沒寫：M3 的入口（搜尋結果的曲目選單？）；舊版限制（禁隨機、禁加入／插入／打亂、清空退出，`playback.md` §3.11）是否沿用；補歌何時觸發；「Mix 身分」持久化內容（M2 `design.md:595`）；重啟是否恢復 Mix。
5. **B 站分 P（E2）。** `multiPart` 能力（`0014:38`）沒有 DTO 與函式簽名；`TrackSummary.cid` 與曲目鍵已有。沒寫：分 P 列表由哪個插件函式取得、搜尋結果「展開分 P」入口（舊 `_PageTile`）與多選行為、分 P 在佇列與歷史怎麼顯示（同一支影片的分組鍵 `TrackKey.formatGroup` 已有）。
6. **「以登入身分瀏覽與播放」的名稱與預設。** ADR 0012 §決定 6 預設三音源皆開；`questions.md:161` 舊版 YouTube 預設關；`phase2-plan.md:192` 寫「可能改名」，ADR 沒有定名稱；開關放在哪一頁（每音源設定表尚未建）。擁有者需要確認 YouTube 預設與名稱。
7. **帳號頁、插件頁、電台頁、Debug 頁在導覽與設定頁中的位置。** 現況導覽三項、設定三組（見 §4.1）；ADR 0011／0024 的八組沒有帳號與插件（矛盾 12）；ADR 0014 只說「App 插件頁」。影響 PR 切分與 `settings_page` 的版面。

### B. 插件契約

8. **`login` 的 manifest 欄位與插件函式契約。** `0014:37` 的 manifest 列「登入方式」但 `manifest.login` 目前整個拒收（`plugin_manifest.dart:249-250`）。沒寫：插件如何實作 QR（產生碼、輪詢）與貼上 cookie 的驗證；App 內網頁登入由宿主開 WebView 時，網址、UA、要取哪些 cookie 由 manifest 宣告還是宿主內建；「拿到憑證後先呼叫帳號資訊 API 驗證」由插件函式還是宿主呼叫；B 站 cookie 刷新（需要 RSA 公鑰與多步請求，舊 `bilibili_crypto.dart`）在插件裡實作的介面；`fmp.credentials.get()` 回傳的形狀與 `CredentialSource.credentialHeaders` 的 header 組裝誰負責（YouTube 舊版要 `Authorization: SAPISIDHASH`，`accounts-network.md` §1.1）；登入後 Cookie 與插件自己送的 `buvid3` 合併或覆蓋（M2 待辦 12）。
9. **`live`、`mix`、`trackDetail`、`multiPart` 的 DTO 與 `checks.json` 案例格式。** ADR 0014 §決定 5 只描述 `live`「提供直播串流與直播狀態」；其餘能力沒有輸入輸出。需要定的包括：直播狀態的「未開播」與「查詢失敗」如何表示（D10）、`live` 是否也要 `expiresAt`、直播間資訊（高能用戶數等舊版每分鐘刷新的資料）要回什麼、`mix` 如何標示 Mix 身分與續取下一批、檢查案例如何涵蓋這些能力（矛盾 9）。備註：網易音源與網易歌詞源是否同一個插件（`0014:34-36` 並列兩類）影響 M7 時的 id 與能力宣告，ADR 0021 沒有明說。
10. **v1 何時凍結。** 矛盾 11。M3 的三個插件與 `index.json` 是第一批可被使用者安裝的物件；之後加欄位就會被已發佈的 App 拒收。決定點影響 M3 要不要在發佈前把 `live`／`mix`／`login` 一次擴完。
11. **被取代請求的取消參數。** M2 `design.md:70` 留給 M3：需要宿主知道每個 `fmp.http.request` 屬於哪一次插件呼叫。ADR 0018 §決定 6 要求「被取代的請求經宿主 `http.request` 取消網路工作」，並影響 `playLive` 取消進行中的音樂請求（ADR 0018 §決定 9 的驗證）。這是宿主 API 的改動，要不要和 `login`／`live` 的擴充同一次做。
12. **「語意冪等的 POST」的宣告方式。** M1 `implement.md:159`：YouTube innertube 與網易查詢是 POST，照現行規則不重試；M3 加兩個插件時決定怎麼標（manifest？每次 `http.request` 的選項？）。影響 ADR 0013 §決定 4 的「只重試冪等請求」。
13. **候選備援順序與 `previewOnly` 是否升為插件規範。** M2 `implement.md:702` 與 `design.md:901`。影響 `fmp-plugin.d.ts` 與網易插件。
14. **Android 時長未知的前瞻。** M2 `implement.md:680` 明寫「M3 加 YouTube／直播類插件前要實機找別的載入訊號」。直播串流沒有時長，這個限制直接擋 `live`；需要決定在 M3 的哪個 PR 先處理，以及處理失敗時直播要不要不使用前瞻。

### C. 插件庫與插件頁

15. **`index.json` 的格式、託管與官方網址。** ADR 0014 §決定 6 只寫含 SHA-256、預設讀官方 index、可加自訂 index。沒寫：欄位（id、名稱、版本、能力、下載網址、`apiVersion`、最低 FMP 版本？）、官方 index 放哪（GitHub raw、Releases、Pages）、網址寫進哪個常數檔（`lib/core/endpoints.dart` 現況不存在）、多個 index 同一 id 衝突、自訂 index 的信任提示。fmp-plugins 現況無 `.github/`、無 `index.json`、無發佈版本。
16. **插件庫 CI 與版本。** ADR 0015 §決定 6「插件庫 CI 以固定的 FMP 版本執行」；FMP 目前沒有發佈版本（`app-release.yml` 只手動跑）。「固定的 FMP 版本」指 tag、commit 還是分支；index 產生與發佈由誰觸發；插件版本號規則（B 站是 0.1.0）。
17. **插件的啟用／停用狀態。** ADR 0017 §決定 5（「插件停用或移除」）、ADR 0025 §決定 6（「已安裝且啟用的插件」）、ADR 0014 §決定 9（「所有啟用的目標來源」）都假設有「啟用」；`installed_plugins` 沒有此欄位，registry 也沒有此概念。語意（停用後搜尋 chip、排程器、Mix／電台、已存曲目的顯示）與「手動停用無回應插件」（M1 `implement.md:195`）是否同一件事，ADR 沒有定。
18. **安裝、更新、移除的流程細節。** ADR 0014 §決定 6–8 只有原則。沒寫：安裝前確認 UI 的內容與跳過規則（dev 入口跳過確認，`dev_plugin_entry.dart` 檔頭）；SHA-256 不符時的處理；更新比對「只升不降」與 `apiVersion` 不相容的呈現；更新時舊版的憑證與 storage 是否保留；移除時的順序與確認（storage cascade 已有、`CredentialStore`、快取庫 `removePlugin`、排程器工作、WebView cookie）；移除後佇列與歷史中的曲目如何標「音源未安裝」（現況 `pluginNameProvider` 找不到插件時顯示插件 id，`app/AGENTS.md:1329-1331`）。
19. **首次啟動引導。** ADR 0014 §決定 8 只有一句「沒有來源時引導安裝官方插件」。沒寫：觸發條件（零個插件？零個有 `resolveStream` 的插件？）、安裝幾個、預設全裝還是勾選、離線時的呈現（ADR 0016 §決定 7 規定顯示離線狀態）、略過後搜尋頁的空狀態、dev flavor 與測試插件的關係。
20. **插件頁的內容與版面。** ADR 0014 §決定 6–7 與 ADR 0016 §決定 7 提到的功能：已安裝清單（能力、網域、版本、健康狀態）、官方 index 清單、自訂 index、從檔案或網址安裝、手動檢查更新、一鍵全部更新、移除、登入入口？ADR 0024 沒有此頁版面，無示意稿。

### D. 帳號

21. **登入 WebView 的套件與平台能力欄位。** ADR 0009 能力清單列「登入 WebView」，ADR 0012 §決定 8 只決定 Linux 另議；舊版是 `flutter_inappwebview`（`pubspec.yaml:66`）。新 App 的 Android、Windows 用哪個套件、`PlatformCapabilities` 的欄位名稱與粒度（是否區分網頁登入與 QR）、網易在 Windows 是否仍「只有 QR」（`accounts-network.md` §1.1，ADR 0012 §決定 4 寫「B 站、網易以 QR 為主」）。
22. **YouTube App 內網頁登入的實測條件。** `milestones.md:73`、`phase2-plan.md:238`。實測需要真實 Google 帳號與桌面 UA；ADR 0027 §決定 2 要求最少操作且擁有者帳號可能被風控（`questions.md` M 項、`0012:51` 的「推測」說明）。用哪個帳號、Android 與 Windows 都測還是其一、失敗後 M3 是否就不提供網頁登入（只剩貼上 cookie）、UA 偽裝沿用舊版做法（Android 去掉 `;wv`）與否，需要擁有者決定。
23. **帳號與每音源設定的資料表。** ADR 0012 §決定 3「帳號的非機密顯示資訊存資料庫」、ADR 0011 §決定 7「每個音源的設定另一張表」。舊 `Account` 欄位：userId、userName、avatarUrl、isLoggedIn、isVip、sessionExpired、loginAt、lastRefreshed（`accounts-network.md` §1.1）。哪些要保留、是否由插件回報（頭像、VIP）、「已失效」「暫時無法讀取」狀態存哪裡、診斷包的「登入狀態（是／否）」以哪一個為準；ADR 0012 §決定 3 說登入狀態由 `CredentialStore` 推導。
24. **啟動時的帳號檢查與刷新。** ADR 0012 §決定 5 寫「只有帶了憑證的請求才可能觸發失效」「B 站啟動時詢問是否需要刷新」；舊版啟動時對每個已登入平台跑 `verifyAllAccountStatuses`（`accounts-network.md` §1.5）。新版啟動時是否仍主動檢查、頻率、離線時行為沒有寫；「相關入口顯示需要重新登入」（`0012:48`）的入口有哪些（搜尋頁音源 chip？播放時的提示附「登入」按鈕？）。

### E. 排程器

25. **排程器的位置、設定組與資料表。** ADR 0017 稱「service 層」，`app/lib/` 現況沒有 `services/`（頂層是 `app/core/data/domain/i18n/platform/playback/plugins/settings/ui`）；`fmp_periodic_timer_owner` 的允許目錄（現有 `lib/playback/`）ADR 沒有寫路徑；「上次成功時間」表名與欄位未定；三組間隔設定屬哪個設定組（M2 `design.md:203` 傾向「網路」組，ADR 0011 沒寫）；M3 只有電台的兩個工作，排行與匯入歌單的間隔設定是現在加還是 M4 加（M2 `design.md:65` 寫三組都在 M3）；電台狀態沒有電台清單可輪詢時（未定之處 3）第一個工作的資料來源與快取（ADR 0017 §決定 3「先顯示快取」）。

### F. 開發工具與回報

26. **「開發者」設定組與「關於」頁的最小內容。** 矛盾 4。`developerMode`／`logLevel` 與插件資料夾路徑記在「開發者」組（`0025:67-69,127`）；版本列連點 7 次需要一個「關於」頁或區塊，而 `milestones.md:123` 把關於頁放 M9。M3 的最小版本包含哪些內容（版本、flavor、授權？），M9 再補什麼，需要劃線。
27. **插件開發工具的平台與錄製來源。** ADR 0015 §決定 7、ADR 0025 §決定 7：先限桌面、由平台層宣告 `pluginDevTools`；「以 App 內登入錄 fixture」依賴未定之處 8 的登入契約；每插件「真實／錄製／重播」切換需要 adapter 移進 `lib/core/network/`（M2 待辦 11）；ADR 0027 實機驗證預設用重播，Android 不能做插件開發（`0025:185`）時，Android 上 YouTube／網易的 fixture 從哪來（桌面錄好再放進哪裡？）。
28. **診斷包的套件與資料。** ADR 0025 §決定 10 沒指名 zip 套件；`file_selector`、`share_plus` 是否核准加依賴（見 §5）；`dataDirectory` 帳號名稱處理（M2 待辦 13）；「第一次匯出提醒」與「在 GitHub 回報」提醒共用的「不再提醒」欄位屬哪個設定組（`0025:156`、`0023:64`）；診斷包欄位中「各音源啟用與登入狀態」依賴未定之處 17、23。
29. **錯誤回報的目標、範本與開網址。** ADR 0023 §決定 4：開「新增 issue 頁（bug 範本）」。沒寫：目標 repo（FMP 或 fmp-plugins，插件造成的 `UnexpectedError`／`ParseError` 該回報到哪）；`bug_report.yml` 的欄位、標籤與語言（根 `AGENTS.md` 規定 Issues 標題與內文用繁中）；開網址用哪個套件（`url_launcher` 未在 pubspec、ADR 未指名）；GitHub 網址常數放 `lib/core/endpoints.dart`（現況不存在）；dev flavor 是否也顯示「在 GitHub 回報」。
30. **Debug 頁「播放狀態」需要新增的 `PlaybackState`／Session 欄位。** ADR 0025 §決定 5 列的欄位（下次重試時間、串流格式／位元率／容器／來源類型、輸出裝置、後端）中，M2 現況只有 `Retrying{attempt, delay}`（M2 `design.md:71`）；其餘欄位要在播放核心新增，屬 M3 的哪個 PR、是否改動 `PlaybackState` 的形狀，需要和 ADR 0018 §決定 2（`QueueState` 與播放狀態無共同欄位）對照。
31. **重設資料與資料庫區塊對 M4 功能的依賴。** 矛盾 1。M3 的重設資料「自動備份」使用的備份格式、「從備份還原」與「孤兒曲目數」「檔案遺失的下載數」（M3 沒有下載紀錄）在 M3 是否出現、出現多少，需要決定。
32. **排程器之外的 lint 與文件同步。** `fmp_periodic_timer_owner` 的雙向變異測試（`0015:54`）、`app/AGENTS.md` 規則表與 `.trellis/spec/app/lints/index.md` 同步；`fmp_source_id_literal` 的 `officialPluginIds` 加 YouTube、網易（官方 id 字串 ADR 未寫）；官方 id 的最終拼寫會寫進 `legacy_import` 對照（M5）與 index，需要先確定。
33. **M3 實機驗證的模式與帳號使用。** ADR 0027：預設重播；插件、網路層、登入的 PR 用真實。M3 幾乎每個 PR 都屬這類，每次真實連線的「最少操作」上限、擁有者帳號被風控時的備案（YouTube 匿名被擋、B 站 412，`0027:12`）、YouTube 與網易 fixture 首次錄製需要登入時的做法（命令列只能錄不需登入的案例，`0015:69`），需要擁有者先給規則。
