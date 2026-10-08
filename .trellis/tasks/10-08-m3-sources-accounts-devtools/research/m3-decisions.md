# M3 規劃決定草案：矛盾處理、未定之處分類、拆分與 PR 順序

> 輸入：`research/m3-scope-digest.md`（§7 的 14 條矛盾、§8 的 33 條未定之處，下稱「矛盾 n」「#n」）。
> 套件版本在 2026-10-08 以 pub.dev API（`/api/packages/<名稱>`）查證，只取 stable；API 行為以 context7 查證（flutter_inappwebview、file_picker）。查不到的標「待查」。
> 分類：甲＝文件已有答案；乙＝技術決定（附建議與慣例）；丙＝擁有者決定。
> 乙類裡會改到 ADR 文字或舊版行為的，列進 design 的「需要擁有者明確確認的決定」（比照 M2 design §12），不另外當丙類問。
> 作者：opus 規劃代理（唯讀，由主對話代存）。

## 1. 矛盾（§7）的處理

| # | 處理 | 動作 |
|---|---|---|
| 1 | ADR 0010 沒有定義備份格式，ADR 0025 §決定 9 不能依賴它。M3 改用資料庫檔副本（見 #31）。 | ADR 0025 §決定 9 加一行：「更正（M3）：自動備份＝以 SQLite `VACUUM INTO` 把資料庫複製到 `backups/fmp-<時間>.db`；『從備份還原』＝換回該檔並重啟。憑證不在資料庫，還原後要重新登入。M4 的 E16 匯出格式另定。」 |
| 2 | 用 `file_picker` 一個套件。ADR 0009 §決定 6 已把它列為五平台共用，舊版也在用（舊 `pubspec.yaml:77`）。13.x 有 `getDirectoryPath`、`saveFile(bytes:)`，Android 有 `androidOptions`（SAF）。 | ADR 0025 加一行：「更正（M3）：§決定 7、10 的 `file_selector.getDirectoryPath`／`getSaveLocation` 改用 ADR 0009 §決定 6 的 `file_picker`（13.1.0）的 `getDirectoryPath`、`saveFile`；『file_picker 沒有 SAF』不成立（13.x 有 `androidOptions`），Android 插件開發仍另立 ADR。」Android 的 `saveFile` 是否走系統建立文件對話框：待查（實作時讀原始碼確認）。 |
| 3 | 不需更正。`0026:84` 已修訂，範圍以 `milestones.md` 為權威（`0026:69`）。ADR 0017 本文沒有寫里程碑。 | 無；若丙1 選拆分，ADR 0026 §決定 3 另加一行修訂。 |
| 4 | ADR 0024 §決定 9 定的是關於頁的完整內容（`0024:117`），M9 才做完；M3 只需要版本列（見 #26）。 | `milestones.md` § M3 範圍加：「設定『關於』區塊的版本列（開發者模式入口；其餘內容 M9）」。 |
| 5 | 不是矛盾。ADR 0012 已決定三個音源預設皆開，並寫明發行說明要交代（`0012:51-52`）；M5 照舊值匯入。 | 無。 |
| 6 | 兩處都在資料庫，字面不同而已。 | ADR 0012 §決定 1 加一行：「補充（M3）：匿名 cookie 由插件存在自己的 storage（`plugin_storage` 表）；登入後的 Cookie 與插件自己送的同名 cookie 以憑證為準合併（ADR 0029）。」 |
| 7 | 1／3／10 秒是舊版電台常數（`lib/core/constants/app_constants.dart:256`），沒有刻意要跟 1／3／9 秒不同。共用一份排程最簡單。 | ADR 0018 §決定 9 加一行：「更正（M3）：直播重連改用 §決定 7 的 1／3／9 秒；1／3／10 是舊版 `RadioReconnectConfig` 的值，沒有刻意區分。」列入 design 確認清單。 |
| 8 | M3 先定「Mix 身分」＝（插件 id, 插件回傳的 `mixId`），M4 的 `playlists.kind = mix` 存同一對值。 | 寫進 ADR 0028；ADR 0019 不改。 |
| 9 | `checks.json` 每個新能力一個鍵，需要登入的案例加 `requiresLogin: true`，健康檢查標「略過」（`0025:124`），契約測試照常重播。 | 寫進 ADR 0028。 |
| 10 | App 內開發工具必須在 `lib/` 錄製與重播。adapter 本身屬網路層，放 `lib/core/network/` 不違反分層；M1 更正指的是「獨立套件互相依賴」。 | ADR 0015 §決定 6 加一行：「更正（M3）：錄製與重播的 adapter 移到 `lib/core/network/`（App 內開發工具使用），`app/test/plugins/contract/` 改為引用它，格式不變；上一則更正的『放進 `lib/` 違反分層』只指 QuickJS 與零聯網的測試準備。」 |
| 11 | 見 #10。「發佈」定為 `app/` 第一個 prod 版本對外發佈。 | ADR 0014 §決定 5 加一行：「補充（M3）：『發佈』指 `app/` 第一個 prod 版本對外發佈（M9 切換）；在那之前 v1 可加選填欄位，`fmp-plugins` 同一輪跟上。」 |
| 12 | 設定頁的區塊可以不只是設定表：`0024:117` 的「關於」就不是 ADR 0011 的設定組。 | ADR 0024 §決定 6 加一行：「補充（M3）：設定頁除 ADR 0011 的設定組外，另有『帳號』（第一個）、『插件』、『關於』，開發者模式下最後一個是 Debug 頁入口；這些不是設定表。」 |
| 13 | 照 M2 先例補驗收項（見 #1）。 | `milestones.md` § M3 驗收加一條（PR 0）。 |
| 14 | 需要擁有者決定。 | 丙類「`trackDetail`」（#2）。 |

## 2. 未定之處（§8）

### 甲、文件已有答案（3 條）

- **#6 「以登入身分瀏覽與播放」的名稱與預設**
  - 名稱就是這句（`docs/adr/0012-network-layer-and-accounts.md:50`）；`phase2-plan.md:192` 的「可能改名」早於 ADR 採納，以 ADR 為準。
  - 預設三個音源皆開，YouTube 附說明（`0012:51`）；legacy import 用舊值（`0012:52`，M5）。
  - 開關存每音源設定表（`0011-settings-and-logging.md:46`）。放在帳號頁該音源那一列，屬乙類細節。
- **#13 候選備援順序與 `previewOnly`**
  - 輸出本來就是「依優先序排好的候選串流」（`0014-script-source-plugins.md:45`），順序由各插件決定，不升為規範。
  - `previewOnly` 已在 v1（`0014:46`；`app/lib/plugins/types/fmp-plugin.d.ts`），網易插件直接使用。
- **#24 啟動時的帳號檢查與刷新**
  - 不做全面驗證：只有帶了憑證的請求才可能觸發失效（`0012:46`）。
  - 刷新由音源宣告，B 站在啟動時詢問（`0012:45`）。
  - 需登入時「提示並附『登入』」，憑證無效時「刷新一次，失敗才提示一次」（`0013-unified-error-model.md:52-53`）。
  - 離線中不發背景請求（`0016-cache-and-offline.md:46`），所以啟動刷新要等到 `Online`。
  - 「相關入口」＝帳號頁該列，加上提示的「登入」動作。搜尋 chip 不加標記（乙類預設）。

### 乙、技術決定（25 條）

- **#1 M3 驗收**
  - 建議：照 M2 先例（`milestones.md:59`），驗收加一條「ADR 0012、0014、0015 §決定 7、0017、0018（mix、live）、0023 §決定 4、0025 的測試（範圍見 M3 design §12）」，證據放 `research/m3-adr-tests.md`。
  - 「登入」通過的定義：B 站 QR、網易 QR、YouTube App 內網頁登入；§8 不通過就以貼上 cookie 代替（`phase2-plan.md:238` 已定這條退路）。兩平台各一次。
  - 理由：M2 的做法已經被接受。
  - 文件：`milestones.md` 更正，不需要 ADR。
- **#5 B 站分 P**
  - 建議：
    - 新匯出 `multiPart({id}) → {parts:[{cid,title,durationMs,index}]}`。
    - 搜尋列在使用者展開時才呼叫（舊 `_PageTile`，`search_page.dart:1082`）。
    - 每個分 P 各自是一首曲目（ADR 0005，曲目鍵含 cid），顯示「影片標題 · P2 分 P 標題」，以既有 `TrackKey.formatGroup` 分組。
    - 多選照舊版。
  - 慣例：舊版行為；PiliPlus 的分 P 列表。
  - ADR：DTO 寫進 ADR 0028。
- **#7 頁面位置**
  - 建議：
    - 帳號＝設定頁第一個區塊（舊版 `features.md:201`）。
    - 插件＝設定頁區塊「插件」（MusicFree 的「插件管理」、LX Music 的「自訂源」都在設定裡）。
    - Debug＝設定頁最後，只在開發者模式出現（`0025:75`）。
    - 電台的導覽入口見丙類 #3。
  - ADR：ADR 0024 一行更正（矛盾 12）。
- **#8 `login` 契約**
  - manifest：`login: {methods: ('qr'|'webView'|'cookie')[], webView?: {url, userAgent: 'desktop'|null, cookieHosts[], doneCookies[]}, refresh?: 'onStartup'|null}`。WebView 由宿主開，網址、UA、要取哪些 cookie 由 manifest 宣告，宿主沒有任何音源分支。
  - 匯出：
    - `loginQrStart() → {qrText, token}`
    - `loginQrPoll(token) → {status:'waiting'|'scanned'|'expired'|'done', credentials?}`
    - `loginVerify(credentials) → {userId, displayName, avatar?}`：宿主在三種方式之後都先呼叫它，通過才寫入（`0012:43`）。
    - `loginRefresh(credentials) → credentials|null`
  - 注入：
    - 宿主把憑證中的 cookie 合併進請求的 `Cookie`（同名以憑證為準，舊版就是合併；解決 M2 待辦 12）。
    - 需要從 cookie 算出的標頭（YouTube `SAPISIDHASH`）由插件放在 `HttpRequest.authHeaders`；只有宿主判定要帶憑證時才送出，並登記到遮蔽函式。
    - 這樣帶不帶憑證仍只由 `auth` 標記這一處決定。
  - 失效判定：插件以 `CredentialInvalid` 回報（ADR 0013：錯誤在音源內轉換）。宿主在插件呼叫層單飛刷新後，重跑該呼叫一次，取代 dio `QueuedInterceptor` 那一層，因為判定在 JS 內、dio 層看不到。ADR 0012 §決定 5 要加一行「由 ADR 0029 細化」，列入確認清單。
  - B 站刷新要 RSA-OAEP、網易 eapi 要 AES：宿主 `crypto` 只有 md5／sha256，所以由插件內附純 JS 實作，不擴充宿主 API（YouTube.js 補 Web API 的先例，`0014:59`）。
  - 慣例：ytmusicapi 的瀏覽器 cookie 與 SAPISIDHASH；PiliPlus 的 QR 輪詢。
  - ADR：新 ADR 0029。
- **#9 `live`、`mix` 的 DTO**
  - `liveStatus({roomId}) → {status:'live'|'offline', title, artwork, online?}`。查詢失敗一律拋錯，宿主顯示「查詢失敗」，不能回 `offline`（D10）。收聽中的直播間資訊也用同一個函式（1 分鐘工作）。
  - `resolveLive({roomId}) → StreamResult`，`expiresAt` 可空（舊版沒有期限）。
  - `mix({seed} | {mixId, cursor}) → {mixId, tracks[], cursor|null}`。
  - `checks.json` 見矛盾 9。
  - 網易播放與網易歌詞（M7）用同一個插件 `netease`，多宣告 `lyrics` 能力即可（`0014:38-39`：能力屬於插件）。
  - ADR：0028。
- **#10 v1 何時凍結**
  - 建議：到 M9 對外發佈才凍結，M3 照常在 v1 內加選填欄位。
  - 理由：現在只有擁有者的 dev 版會讀 index，沒有相容負擔。
  - ADR：0014 一行（矛盾 11）。
- **#11 被取代請求的取消**
  - 建議：取消做在控制器層。被取代的 `resolveStream`／`live` 結果以代際檢查丟掉，不再發新的解析；已送出的 HTTP 讓它跑完。
  - 理由：YouTube.js 的請求經插件內的 fetch 補丁發出，QuickJS 沒有 AsyncLocalStorage，宿主無法把 `fmp.http.request` 對回是哪一次呼叫。
  - ADR 0018 §決定 9「開直播取消進行中的音樂請求」的測試改成：音樂結果不會被播出，也不再發解析。
  - ADR：0018 §決定 6 加一行更正，列入確認清單。
- **#12 語意冪等的 POST**
  - 建議：`HttpRequest.idempotent?: boolean`，預設依方法。
  - 慣例：gRPC 的 per-method `idempotency_level`；RFC 9110 §9.2.2；ADR 0013 本來就允許「音源標為可重試者」（`0013:43-44`）。
  - ADR：0028，0013 §決定 4 加一行指過去。
- **#14 Android 時長未知的前瞻**
  - 建議：在 YouTube 插件 PR 實機確認 YouTube 串流有沒有時長；時長未知時不排前瞻，以 `completed` 換歌（只失去無縫）。
  - `live` 模式只有一項，不用前瞻。
  - ADR：不需要；這是後端差異，寫進 `AudioBackend` 的 dartdoc（ADR 0018 §決定 3）。
- **#15 `index.json` 格式與託管**
  - 格式：`{indexVersion:1, plugins:[{id,name,author,description,version,apiVersion,capabilities,allowedHosts,url,sha256}]}`。
  - 託管：`fmp-plugins` 的 `main` 分支，經 `raw.githubusercontent.com` 讀取。index 與 `.js` 在同一個 commit 由腳本產生，CI 檢查 index 是最新的。
  - SHA 不符就拒裝，提示「插件庫剛更新，請稍後再試」。
  - 官方網址放 `lib/core/endpoints.dart`（`fmp_url_literal`）。
  - 每個已安裝插件記住它來自哪個 index，只從那裡更新；加自訂 index 時提示「非官方來源」。
  - 慣例：Obsidian `community-plugins.json`（raw.githubusercontent，一個插件一個來源）；MusicFree 的訂閱 JSON。
  - 不選 GitHub Pages：要改 repo 設定，而且同樣有 CDN 快取延遲。
  - ADR：新 ADR 0030。
- **#16 插件庫 CI 與版本**
  - 建議：
    - workflow 以 `FMP_REF`（FMP 的 commit SHA）checkout FMP，對每個插件目錄跑契約測試，並檢查 index。
    - 宿主 API 變了就開 PR 改 `FMP_REF`。
    - 插件版本用 semver；`.js` 一有改動，CI 要求版本號提高。
  - 慣例：GitHub Actions 以 SHA 釘版本。
  - ADR：0030。
- **#17 啟用／停用**
  - 建議：
    - `installed_plugins.enabled`（預設開）。
    - 停用＝不載入，不出現在搜尋 chip、健康檢查、排程器（`0017:41`）；佇列裡的曲目照「音源未安裝」跳過並標示；憑證保留。
    - 「沒有回應」只是執行期狀態，到重啟為止（`0014:66`），不存資料庫；插件頁可直接把它停用（M2 待辦 10）。
  - 慣例：VS Code 的擴充功能啟用／停用；MusicFree 的「禁用」。
  - ADR：0030。
- **#18 安裝、更新、移除**
  - 安裝：先確認，列出能力、網域與警告（`0014:50`）；dev 入口照舊跳過確認。
  - 更新：semver 只升不降；`apiVersion` 不相容時顯示「需要更新 FMP」並停用按鈕；同 id 更新保留 storage 與憑證。
  - 移除：確認 → 關閉 runtime → `CredentialStore` 刪除 → 刪該網域的 WebView cookie → 刪 `plugin_storage`（cascade）→ `CacheStore.removePlugin` → 移除排程工作 → 刪 `installed_plugins` 列。
  - 曲目保留，顯示「音源未安裝」（取代目前顯示插件 id 的做法）。
  - ADR：0030。
- **#19 首次啟動引導**
  - 觸發：沒有任何具 `search` 能力的已安裝插件。
  - 呈現：在搜尋頁就地顯示空狀態，不做精靈（`0024:118`「就地說明」）。列出官方 index 的插件，預設全勾，一次確認後一起安裝。
  - 離線時顯示離線空狀態（`0016:48`）；略過後的空狀態附「前往插件頁」。
  - dev flavor 已有測試插件就不出現。
  - 慣例：MusicFree 沒有插件時的空狀態引導。
  - ADR：0030。
- **#20 插件頁**
  - 「已安裝」：版本、標記（開發中／已停用／沒有回應）、能力、網域、啟用開關、更新、移除、登入連結。
  - 「可安裝」：官方與自訂 index。
  - 工具列：檢查更新、全部更新、從檔案安裝（`file_picker`）、從網址安裝、管理 index。
  - 健康狀態留在 Debug 頁。
  - 慣例：VS Code 的 Extensions 檢視（已安裝／市集）。
  - ADR：0030；版面寫在 design。
- **#21 登入 WebView 套件與能力**
  - 建議：`flutter_inappwebview` 6.1.5（最新 stable，2024-10-08；不用 6.2.0-beta.3）。
    - 舊版在 Android 與 Windows（WebView2）都用過（舊 `pubspec.yaml:66`）。
    - context7 確認 `CookieManager.getCookies／deleteCookies` 在 Windows 可用，`userAgent` 可設。
  - 其他候選：
    - `webview_flutter` 4.14.1 沒有 Windows。
    - `webview_windows` 0.4.0（2024-02）只有 Windows。
    - `desktop_webview_window` 0.3.0 是獨立視窗，取 cookie 的能力待查。
  - 能力欄位 `loginWebView`（Android、Windows 為真）；QR 不需要平台能力。
  - 網易、B 站只提供 QR，YouTube 提供網頁登入加貼上 cookie（`0012:42`）。這拿掉了舊版 B 站與 Android 網易的 WebView 分頁，列入確認清單。
  - 風險：兩年沒有 stable，由 R1 在 Flutter 3.47 實測建置。
  - ADR：0029。
- **#23 帳號與每音源設定表**
  - `accounts(plugin_id PK, user_id, display_name, avatar_url, status: active|invalidated, logged_in_at, last_refresh_at, last_refresh_result)`。
  - `source_settings(plugin_id PK, browse_as_logged_in 可空)`。
  - 是否登入只看 `CredentialStore`（`0012:38`）。啟動時有帳號列、沒有憑證就刪列；「暫時無法讀取」只在記憶體。
  - 不存 VIP：沒有讀它的功能。
  - 診斷包的登入狀態取自 `CredentialStore`，不含帳號名稱（`0011:43`）。
  - ADR：0029。
- **#25 排程器**
  - 位置：新頂層 `lib/scheduler/`。`core` 不准 import `data`，排程器又要存「上次成功時間」；app 沒有 `services/`。
  - lint 允許清單：`lib/scheduler/`、`lib/playback/`。
  - 表：`scheduler_runs(job_id PK, last_success_at)`。
  - 設定：M3 只加電台間隔 `radio_status_interval_minutes`，放「網路」組（M2 `design.md:203` 的歸類）。排行與匯入歌單的間隔跟 M4 的工作一起加，因為現在沒有讀它們的人；這和 M2 `design.md:65`「三組都在 M3」不同，列入確認清單。
  - ADR：不需要新的；寫進 `app/AGENTS.md` 與 spec。
- **#26 「關於」最小內容**
  - 建議：M3 只做版本列（版本、flavor），連點 7 次開啟開發者模式；其餘照 `0024:117`，在 M9 做。
  - 文件：`milestones.md` 一行（矛盾 4）；列入確認清單。
- **#27 插件開發工具**
  - 只在桌面（`pluginDevTools`：Windows 真、Android 假）；adapter 移進 `lib/core/network/`（矛盾 10）。
  - fixture 在 Windows 錄進插件資料夾，提交到 `fmp-plugins`。
  - Android 不做 App 內重播：實機驗證用測試插件 `fmp-test`（`0027:36`），改到插件時用最少的真實連線。
  - M3 的請求都是 `userPreference`，匿名就能錄（命令列即可，`0015:69`）。
- **#28 診斷包**
  - 套件：`archive` 4.3.0（舊版 `^4.2.0`）、`share_plus` 13.3.1、`file_picker` 13.1.0（矛盾 2）。
  - `dataDirectory`：遮蔽函式把使用者家目錄登記為已知值、換成 `~`（Finamp 的已知值替換，`0011:36`）。
  - 「不再提醒」存「開發者」組欄位 `report_reminder_dismissed`。組只是存放位置，一般使用者也會讀到。
- **#29 錯誤回報**
  - 一律開 `1morr/FMP` 的 `issues/new?template=bug_report.yml`。報告含插件 id 與版本，插件的問題由維護者用 GitHub 的 Transfer issue 移到 `fmp-plugins`（同一擁有者）。慣例：NewPipe 只有單一回報目標。
  - 開網址用 `url_launcher` 6.3.3（舊版在用）。
  - `bug_report.yml` 用繁中（根 `AGENTS.md:31-33`），欄位：描述、重現步驟、錯誤報告（貼上）、版本、平台；標籤 `bug`。
  - 新增 `lib/core/endpoints.dart`；dev flavor 也顯示回報。
- **#30 播放狀態欄位**
  - 建議：另開唯讀的 `PlaybackDiagnostics` 快照（選中候選的容器、編碼、位元率；後端；輸出裝置；`Retrying` 時的下次重試時間），由 session 提供。
  - sealed `PlaybackState` 的形狀不動，`QueueState` 照舊分開（`0018:33-34`）。
  - 放在 Debug 播放狀態那個 PR。
- **#31 重設與備份**
  - 用資料庫檔副本（矛盾 1）。
  - 「孤兒曲目數」照做（`tracks` 在 M2 就有）；「檔案遺失的下載數」等 M6 才出現。
  - 慣例：SQLite 官方的 `VACUUM INTO`。
  - ADR：0025 一行；列入確認清單。
- **#32 官方 id 與 lint**
  - id 用 `youtube`、`netease`，與舊版相同（`lib/data/models/source_ids.dart:17-18`），M5 對照不用轉換。
  - 在各自插件的 PR 加進 `officialPluginIds`。
  - `fmp_periodic_timer_owner` 在排程器 PR 加，附雙向變異測試，同步 `app/AGENTS.md` 規則表與 `.trellis/spec/app/lints/index.md`。

### 丙、擁有者決定（5 條；清單見最後一節）

#2、#3、#4、#22＋#33（併一題），連同「M3 要不要拆」。

## 3. M3 要不要拆

見丙類第 1 題。

## 4. PR 順序草案（假設丙1 選拆分）

| PR | 內容 | 依賴 | 要先接受的 ADR | 備註 |
|---|---|---|---|---|
| 0 | 規劃檔、ADR 更正、`milestones.md` | 核准 | 0028–0031 | |
| R1 | YouTube App 內網頁登入實測（`app/` 外的暫時專案，`flutter_inappwebview` 6.1.5，兩平台） | — | 無（研究，不寫 `app/`） | **最高風險，核准設計前做**；結果決定 0029 |
| **M3a** | | | | |
| 1 | YouTube 插件 search＋resolveStream；`idempotent`；Android 時長未知；id lint | 0 | 0028 | 曳光彈；真實（匿名） |
| 2 | 網易插件 search＋resolveStream＋`previewOnly`；`X-Real-IP` 實測 | 0 | 0028 | 純 JS AES；高風險 |
| 3 | `fmp-plugins`：CI、`index.json`、B 站修正（HTML 實體、封面尺寸、版本） | 1、2 | 0030 | 另一個 repo |
| 4 | 插件生命週期：`enabled`、移除流程、index 讀取與 SHA 驗證、更新比對 | 0 | 0030 | |
| 5 | 插件頁與設定頁區塊；從檔案安裝 | 3、4 | 0030 | |
| 6 | 首次啟動引導 | 5 | 0030 | |
| 7 | `CredentialStore`、帳號表、每音源設定表、注入與 Cookie 合併、登出、遮蔽登記 | 0 | 0029 | |
| 8 | QR 登入（B 站、網易）、帳號頁、`login` 契約 | 7 | 0029 | |
| 9 | YouTube 網頁登入（`loginWebView`）＋貼上 cookie | 8、R1 | 0029 | |
| 10 | 失效與刷新（B 站啟動刷新、單飛重跑、提示附「登入」） | 8 | 0029 | |
| — | M3a 驗收 | 1–10 | | |
| **M3b** | | | | |
| 11 | 開發者模式、關於版本列、Debug 路由與概覽 | 0 | （0025） | |
| 12 | Log 與錯誤歷史、網路區塊 | 11 | （0025） | |
| 13 | `ErrorReport`、詳細頁、GitHub 回報、`bug_report.yml`、`endpoints.dart` | 11 | （0023） | |
| 14 | 播放狀態、資料庫、重設資料 | 11 | 0025 更正 | |
| 15 | 診斷包 | 13 | 0025 更正 | |
| 16 | 健康檢查、插件開發工具（adapter 移進 `lib/`） | 11、4 | 0015 更正 | |
| 17 | `BackgroundScheduler`、lint | 0 | （0017） | |
| 18 | `live`、`playLive`、`QueueMode.live`、電台 | 17 | 0028、0031 | |
| 19 | Mix | 1 | 0028、0031 | |
| 20 | B 站分 P | 0 | 0028 | |
| 21 | `trackDetail`（丙5 選 a 時） | 1、2 | 0028 | |
| — | M3b 驗收 | 11–21 | | |

- 可以平行的：1、2、4、7 一開始就能同時做；不拆的話，11、17、20 隨時可開。
- 最長的鏈：0 → 1／2 → 3 → 5 → 6，以及 0 → 7 → 8 → 9。
- 高風險先做：R1、1（800 KB 插件在 QuickJS isolate 的效能、時長未知）、2（eapi 加密、`X-Real-IP`）。

## 5. 需要的新 ADR

| ADR | 決定什麼 | 依賴的丙類 |
|---|---|---|
| 0028 宿主 API v1 的 M3 擴充 | `live`、`mix`、`multiPart`、（`trackDetail`）的 DTO；`idempotent`；`checks.json` 擴充與 `requiresLogin`；Mix 身分；凍結點；取消語意 | 丙3、丙4、丙5 |
| 0029 登入、憑證與帳號 | `login` 契約與匯出；`authHeaders`；Cookie 合併；失效在插件呼叫層單飛；WebView 套件與 `loginWebView`；帳號表與每音源設定表 | 丙2（R1 結果） |
| 0030 插件庫與插件生命週期 | `index.json` 格式與託管；CI 與 `FMP_REF`；semver；啟用／停用；安裝、更新、移除；首次引導；插件頁 | 無 |
| 0031 電台與 Mix 的使用者入口與資料 | 電台清單表、頁面與導覽、「加為電台」、狀態工作；Mix 入口與規則 | 丙3、丙4 |

另外是一行更正：0012（§決定 1、§決定 5）、0013 §決定 4、0014 §決定 5、0015 §決定 6、0018（§決定 6、§決定 9）、0024 §決定 6、0025（§決定 7、§決定 9、§決定 10）、0026 §決定 3（若拆分）。

## 丙類問題清單（依重要性）

1. **M3 要不要拆**：a 不拆／b 拆成 M3a「三音源與帳號」（PR 1–10）與 M3b「開發工具、排程器、電台、Mix、分 P」（PR 11–21），M4 依賴 M3b／c 拆三個／d 不拆但 Debug 與開發工具移到 M4 之後。建議 b：M3a 做完就是「三個音源都能搜尋、播放、登入」，兩半各約 10 個 PR。
2. **真實帳號與真實連線的使用規則（#22、#33）**：a 主帳號、兩平台／b 擁有者另開 Google 測試帳號做 R1 與 YouTube 登入，B 站與網易用擁有者指定的帳號，平常插件 PR 只用匿名真實連線／c R1 只測 Windows。建議 b、兩平台都測；R1 失敗就只提供貼上 cookie（`phase2-plan.md:238`）。
3. **電台的範圍與入口（#3）**：a 對齊舊版主體（導覽「電台」、清單、以網址新增、排序、刪除、搜尋頁「加為電台」、狀態輪詢、播放頁直播版；粉絲勳章匯入與首頁區塊到 M4）／b 最小（不存清單）／c 完整含粉絲勳章匯入。建議 a；代價是手機底部導覽變 4 項，M4 加音樂庫要重排。
4. **Mix 在 M3 的入口（#4）**：a YouTube 曲目選單「開始 Mix」，規則照舊版／b 整個移到 M4／c 兩個入口都做。建議 a。
5. **`trackDetail` 歸哪個里程碑（#2）**：a M3b 最後一個 PR／b M4／c 擁有者需要時再排。建議 a：三個插件都在 M3 寫，順手做最便宜。

## 擁有者決定（2026-10-08）

丙類五題都照建議：

1. **拆分**：拆成 M3a「三音源與帳號」（PR 1–10）與 M3b「開發工具、排程器、電台、Mix、分 P」（PR 11–21），M4 依賴 M3b。
2. **帳號**：擁有者另開 Google 測試帳號，做 R1 與 YouTube 登入 PR；B 站、網易用擁有者指定的帳號；平常插件 PR 只用匿名真實連線、最少操作；兩平台都測。登入時由擁有者自己輸入密碼或掃 QR。
3. **電台**：對齊舊版主體（導覽「電台」、清單、以網址新增、排序、刪除、搜尋頁「加為電台」、狀態輪詢、播放頁直播版）；粉絲勳章匯入與首頁區塊到 M4。
4. **Mix**：YouTube 曲目選單「開始 Mix」，規則照舊版。
5. **`trackDetail`**：M3b 最後一個 PR。
