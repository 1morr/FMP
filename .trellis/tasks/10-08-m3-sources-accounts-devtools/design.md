# M3 設計

各項行為以 ADR 0008–0027 為準；M3 新增的跨模組決定在 ADR 0028–0031（2026-10-08 擁有者核准，已採納）。這份只寫：

- 跨 PR 的結構（模組邊界、資料表、宿主 API 的擴充）；
- ADR 留給「開工時決定」的技術選擇；
- 擁有者決定（`prd.md`「擁有者的決定」，下稱「決定 n」）的落地方式；
- `research/m3-scope-digest.md` §7 的矛盾（下稱「矛盾 n」）與 §8 的 33 條未定之處（下稱「§8.n」）的決定。甲、乙類的理由在 `research/m3-decisions.md`，這裡只寫結論與落地，必要時補理由。

套件與 API 的事實在 2026-10-08 查證：版本以 pub.dev API（`/api/packages/<名稱>`）的 `latest`（stable）為準；`flutter_secure_storage`、`flutter_inappwebview` 的行為以 context7（`/juliansteenbakker/flutter_secure_storage`、`/pichillilorenzo/flutter_inappwebview`）查證。加依賴時再核對一次（§14）。

## 0. 未定之處對照

| §8 | 題目 | 決定在 |
|---|---|---|
| 1 | M3 驗收的範圍 | `prd.md` 驗收；`implement.md` § M3a、M3b 驗收 |
| 2 | `trackDetail` 的里程碑 | 決定 5；§11.2 |
| 3 | 電台的資料、頁面、入口 | 決定 3；§9 |
| 4 | Mix 的入口與規則 | 決定 4；§10 |
| 5 | B 站分 P | §11.1 |
| 6 | 「以登入身分瀏覽與播放」 | §6.2、§6.7 |
| 7 | 帳號、插件、電台、Debug 頁的位置 | §6.7、§7.5、§9.3、§12.1 |
| 8 | `login` 契約 | §4.3、§6.3–§6.5 |
| 9 | `live`、`mix`、`multiPart`、`trackDetail` 的 DTO 與 `checks.json` | §4.4–§4.8 |
| 10 | v1 何時凍結 | §4.1 |
| 11 | 被取代請求的取消 | §4.9 |
| 12 | 語意冪等的 POST | §4.2 |
| 13 | 候選備援順序、`previewOnly` | §5.2 |
| 14 | Android 時長未知的前瞻 | §5.4 |
| 15 | `index.json` 格式與託管 | §7.1 |
| 16 | 插件庫 CI 與版本 | §7.2 |
| 17 | 啟用與停用 | §7.3 |
| 18 | 安裝、更新、移除 | §7.4 |
| 19 | 首次啟動引導 | §7.6 |
| 20 | 插件頁 | §7.5 |
| 21 | 登入 WebView 套件與能力 | §6.4 |
| 22 | YouTube 網頁登入的實測條件 | 決定 2；`implement.md` § R1 |
| 23 | 帳號與每音源設定表 | §3.1、§6.2 |
| 24 | 啟動時的帳號檢查與刷新 | §6.5 |
| 25 | 排程器的位置、設定、表 | §2、§3.1、§8 |
| 26 | 「關於」的最小內容 | §12.1 |
| 27 | 插件開發工具的平台與錄製 | §12.5 |
| 28 | 診斷包 | §12.4 |
| 29 | 錯誤回報 | §13 |
| 30 | 播放狀態欄位 | §12.3 |
| 31 | 重設與備份 | §12.2 |
| 32 | 官方 id 與 lint | §2.2、§5 |
| 33 | 實機驗證的模式與帳號 | 決定 2；`implement.md` § 通用規則 |

## 1. 範圍

### 1.1 M3 範圍對照

| 範圍（`milestones.md` § M3 與決定 1–5） | 節 | PR（`implement.md`） | 半 |
|---|---|---|---|
| YouTube 插件 | §5.1、§5.4 | 1 | M3a |
| 網易雲插件 | §5.2 | 2 | M3a |
| 宿主 API：`idempotent`、`authHeaders`、`login` | §4.2、§4.3、§6 | 1、7、8 | M3a |
| `fmp-plugins` 的 CI、`index.json`、B 站修正 | §5.3、§7.1、§7.2 | 3 | M3a |
| 插件生命週期（啟用、安裝、更新、移除） | §7.3、§7.4 | 4 | M3a |
| 插件頁、設定頁的「插件」「帳號」區塊 | §7.5、§6.7 | 5、8 | M3a |
| 首次啟動引導 | §7.6 | 6 | M3a |
| `CredentialStore`、帳號表、每音源設定表、注入、登出 | §6.1–§6.3、§6.6 | 7 | M3a |
| QR 登入、帳號頁 | §6.4、§6.7 | 8 | M3a |
| YouTube 網頁登入、貼上 cookie | §6.4 | 9 | M3a |
| 失效與刷新 | §6.5 | 10 | M3a |
| 開發者模式、「關於」版本列、Debug 路由與概覽 | §12.1 | 11 | M3b |
| Log 與錯誤歷史、網路 | §12.3 | 12 | M3b |
| `ErrorReport`、詳細頁、GitHub 回報 | §13 | 13 | M3b |
| 播放狀態、資料庫、重設資料 | §12.2、§12.3 | 14 | M3b |
| 診斷包 | §12.4 | 15 | M3b |
| 健康檢查、插件開發工具 | §12.5 | 16 | M3b |
| `BackgroundScheduler`、`fmp_periodic_timer_owner` | §8 | 17 | M3b |
| `live`、`playLive`、`QueueMode.live`、電台 | §4.4、§9 | 18 | M3b |
| Mix | §4.5、§10 | 19 | M3b |
| B 站分 P | §4.6、§11.1 | 20 | M3b |
| `trackDetail` | §4.7、§11.2 | 21 | M3b |

### 1.2 M3 不做的事

| 項目 | 理由與去處 |
|---|---|
| 排行、匯入歌單的刷新間隔設定 | 沒有讀它們的人；跟 M4 的工作一起加（§8.4，§16 第 5 條） |
| Mix 的歌單形態（`playlists.kind = mix`）、歌單卡「Mix 播放」、匯入 Mix 簡寫 | M4（ADR 0019 §決定 1）；M3 只有曲目選單的入口（決定 4） |
| 粉絲勳章匯入電台、首頁的電台區塊 | M4（決定 3） |
| `importPlaylist`、`libraryRead`、`libraryWrite`、`charts` | M4 |
| 新格式的備份與還原（E16） | M4；M3 的重設資料用資料庫檔副本（§12.2，矛盾 1） |
| 舊憑證匯入、舊資料對照 | M5（ADR 0010、0026 §決定 2）；§3.4 說明 M3 的格式怎麼對得上 |
| Debug 頁的「檔案遺失的下載數」 | M6 才有下載紀錄 |
| 網易歌詞源 | M7；與播放同一個插件 `netease`，屆時多宣告 `lyrics`（§5.2） |
| 「關於」頁的完整內容 | M9（ADR 0024 §決定 9）；M3 只有版本列（§12.1，§16 第 6 條） |
| Android 的插件開發工具 | 需要 SAF 讀目錄，另立 ADR（ADR 0025 §後果）；平台層宣告 `pluginDevTools` 為假 |
| 自動檢查插件更新 | ADR 0014 否決 |
| B 站 geetest 驗證互動 | ADR 0013 的待辦 |
| M2 驗收沒實機驗的項目（鎖定畫面、實體媒體鍵等） | 與 M3 範圍無關（digest §2 第 20 條） |

### 1.3 各節的實機驗證方式

閘門（自動測試）寫在各節末尾；實機驗證照 ADR 0027 與 `verify-on-device` skill，每個使用者看得到的 PR 都在 Android 模擬器與 Windows 各驗一次，回報寫平台與模式。帳號規則見決定 2。

| 節 | 模式 | 怎麼驗 |
|---|---|---|
| §5 三個插件 | 真實（匿名，最少操作） | 每個插件各一次搜尋、一首播放；PR 1 另看 Android 時長事件與載入時間；PR 2 另做 `X-Real-IP` 兩種各一次 |
| §6 帳號 | 真實（擁有者的帳號，擁有者自己掃 QR 或輸入密碼） | 每個音源各登入一次 → 一次帶憑證的搜尋（網路紀錄 `credentials: true`）→ 開關關掉再搜尋一次（`false`）→ 登出 → 重啟後帳號頁與憑證一致；Windows 另以 log 確認沒有憑證值 |
| §7 插件庫與生命週期 | 真實（`raw.githubusercontent.com`；插件本身的請求最少） | 首次啟動引導裝三個官方插件；停用與啟用；更新與「能力增加要確認」以 `fmp-plugins` 的暫時分支當自訂 index：先從它安裝，再在分支上升版號（另一次加一個網域）、回插件頁檢查更新，驗完刪分支（`implement.md` PR 5）；移除後資料都不在 |
| §8 排程器 | 重播（測試插件 `fmp-test` 加 `live`） | 把間隔設 1 分，最小化（Windows）或切到背景（Android）時 log 沒有工作執行、回來後到期的跑一次；飛航模式時不跑 |
| §9 電台 | 重播為主；B 站直播真實一次 | 測試插件的直播間：加為電台、以網址新增、排序、刪除、播放、停止回佇列、提前結束重連；B 站真實：一個開播中的直播間播 30 秒 |
| §10 Mix | 真實（YouTube 匿名） | 開始 Mix → 播到倒數第二首觸發補歌一次 → 禁止的操作停用 → 重啟後仍是 Mix → 清空退出 |
| §11 分 P、詳細 | 真實（B 站匿名一次）＋重播 | 一支多 P 影片展開、點 P2 播放；三個音源的詳細各看一次 |
| §12 Debug 頁 | 重播 | §8 的 Debug 頁實測（Windows release）；Android 看各區塊、匯出與分享診斷包 |
| §13 錯誤回報 | 重播（測試插件的 `fail` 關鍵字） | 開發者模式下「詳細」、一般模式下 `UnexpectedError` 的「回報」、「在 GitHub 回報」開的網址（不送出 issue） |

## 2. 模組與 lint

### 2.1 新增的模組與目錄

```
lib/
  app/
    diagnostics/                    # 診斷包的組裝與 zip（§12.4）
  core/
    endpoints.dart                  # 官方 index、GitHub 回報網址（fmp_url_literal 的唯一檔）
    errors/error_report.dart        # ErrorReport（§13）
    network/
      fixture_adapters.dart         # 從 test/plugins/contract/ 移來（§12.5，矛盾 10）
      fixture.dart                  # FmpFixture 的解析，adapter 依賴它，一起移來（§12.5）
      host_fetch.dart               # 讀 index、下載插件與 checks.json（§7.1）
  data/repositories/                # accounts、source_settings、radio_stations、scheduler_runs、plugin_indexes 等
  platform/
    secure_storage/                 # flutter_secure_storage（§6.1）
    login_webview/                  # flutter_inappwebview（§6.4）
    files/                          # file_picker：選資料夾、存檔（§12.4、§12.5）
    share/                          # share_plus（§12.4）
    url_opener/                     # url_launcher（§13）
  plugins/
    accounts/                       # CredentialStore、AccountService、單飛刷新（§6）
    repository/                     # index 讀取、比對、安裝與更新流程（§7）
    health/                         # 健康檢查；checks.json 的解析與案例期望（§12.5）
    dev/                            # 插件開發工具：資料夾載入、模式切換（§12.5）
  playback/
    mix_session.dart                # Mix 的補歌與修剪（§10）
    playback_diagnostics.dart       # 播放狀態快照（§12.3）
  radio/                            # 電台清單、以網址新增、狀態工作（§9）
  scheduler/
    background_scheduler.dart       # BackgroundScheduler（§8）
  settings/
    developer_settings.dart         # 「開發者」組（§3.3）
  ui/
    accounts/  plugins/  radio/  debug/  error_report/  about/
.github/ISSUE_TEMPLATE/bug_report.yml
```

- **`lib/scheduler/`、`lib/radio/` 是新的頂層目錄**：
  - 排程器要存「上次成功時間」（`data/`）並看網路狀態（`core/`），而 `core/` 不准 import `data/`；`app/` 沒有 `services/`（§8.25，`m3-decisions.md` 的建議）。
  - 電台要用資料（電台表）、插件（`live`）、排程器（狀態工作），不屬於任何既有層；放 `ui/` 會讓背景工作依賴介面，放 `scheduler/` 會讓排程器認得電台。
- **帳號放 `lib/plugins/accounts/`**：帳號以插件 id 為鍵，登入的每一步都是插件呼叫；`plugins/` 本來就可以 import `data/`。`CredentialStore` 實作 `core/network/auth.dart` 的 `CredentialSource`，經 provider 注入網路層（M1 留好的介面）。
- **診斷包放 `lib/app/diagnostics/`**：它要讀設定、帳號狀態、插件清單與 log，只有組裝層可以全部 import。

### 2.2 lint 的改動

| 規則 | 改動 | PR |
|---|---|---|
| `fmp_layer_imports` 的 `platformPackages` | 加 `share_plus`、`url_launcher`（只准在 `lib/platform/`；PR 15、13 加）。`flutter_secure_storage`、`flutter_inappwebview`、`file_picker`、`package_info_plus` 在 M1 就已列入，不必改 | 15、13 |
| `fmp_layer_imports` 的 `externalPackageOwners` | `qr_flutter: lib/ui/accounts`、`archive: lib/app/diagnostics`、`pub_semver: lib/plugins/repository` | 8、15、4 |
| `fmp_layer_imports` 的 `forbiddenLayerImports` | `core/`、`domain/`、`data/` 不 import `scheduler/`、`radio/`；`scheduler/`、`radio/` 不 import `ui/`；`scheduler/` 不 import `radio/`、`plugins/` | 17、18 |
| `fmp_layer_imports` 的 `restrictedImports` | `lib/core/network/fixture_adapters.dart`、`fixture.dart` 只給 `lib/plugins/dev/`（`fixture.dart` 另給 `fixture_adapters.dart`；測試不受限） | 16 |
| `fmp_source_id_literal` 的 `officialPluginIds` | 加 `youtube`（PR 1）、`netease`（PR 2）；與舊版 `lib/data/models/source_ids.dart:17-18` 相同，M5 對照不轉換（§8.32） | 1、2 |
| 新規則 `fmp_periodic_timer_owner` | `Timer.periodic`、`Stream.periodic` 只准在 `lib/scheduler/`、`lib/playback/`（ADR 0017 §如何確認、ADR 0018 §決定 11）。ADR 0021 的桌面歌詞查游標在 M7 加進允許清單，現在不預留 | 17 |

- 每條都照 `.trellis/spec/app/lints/index.md` 寫雙向變異案例，在 `tool/lint_sentinel.dart` 加違規行；同步 `app/AGENTS.md` § Lint 的表。
- `fmp_periodic_timer_owner` 的變異：`lib/radio/` 裡的 `Timer.periodic` 報、`lib/scheduler/` 不報；改名成 `Timer.periodicLike`（同名前綴的自訂方法）不報、`Timer.run` 不報；`Stream.periodic` 一樣兩向。
- M2 現況 `lib/` 唯一的 `Timer.periodic` 在 `lib/playback/queue_store.dart:217`，加規則時不會有違規（M2 design §1.2 已預留）。

## 3. 資料

### 3.1 主資料庫的新表與欄位

列舉存 `converters.dart` 寫死的字串、時間存 UTC epoch 毫秒（`app/AGENTS.md` § 資料層）。

| 表 | 欄位 | 說明 | PR |
|---|---|---|---|
| `installed_plugins`（既有） | 加 `enabled` bool（預設真）、`source_index_url` text?、`checks_json` text? | 啟用（§7.3）；來自哪個 index（空＝從檔案或網址安裝，§7.4）；從 index 安裝時一併存的檢查案例（§12.5） | 4 |
| `plugin_indexes` | `url` text 主鍵、`added_at` int | 使用者加的自訂 index；官方 index 不存，在 `endpoints.dart` | 4 |
| `accounts` | `plugin_id` text 主鍵、`user_id` text、`display_name` text、`avatar_json` text?、`status` text（`active`／`invalidated`）、`logged_in_at` int、`last_refresh_at` int?、`last_refresh_result` text?（`refreshed`／`unchanged`／`failed`） | 帳號的非機密顯示資訊（ADR 0012 §決定 3）。不存 VIP（沒有讀它的功能） | 7 |
| `source_settings` | `plugin_id` text 主鍵、`browse_as_logged_in` bool? | 每音源設定表（ADR 0011 §決定 7）；空＝manifest 宣告的預設（§6.2） | 7 |
| `developer_settings`（單列） | `developer_mode` bool?、`log_level` text?、`plugin_dev_folder` text?、`report_reminder_dismissed` bool? | 「開發者」組（§3.3） | 11 |
| `scheduler_runs` | `job_id` text 主鍵、`last_success_at` int | 排程器的上次成功時間（ADR 0017 §決定 2） | 17 |
| `radio_stations` | `id` int 自增主鍵、`plugin_id` text、`room_id` text、`title` text、`host_name` text?、`artwork_json` text?、`sort_order` int、`added_at` int、`live_status` text?（`live`／`offline`）、`live_title` text?、`status_checked_at` int?；唯一（`plugin_id`、`room_id`） | 電台清單（§9.1）。最後一次查到的直播狀態也存這裡，啟動時先顯示（ADR 0017 §決定 3「先顯示快取」） | 18 |
| `network_settings`（既有） | 加 `radio_status_interval_minutes` int? | 電台狀態刷新間隔（§8.4） | 18 |
| `player_state`（既有） | 加 `mode` text?（空或 `queue`／`mix`）、`mix_plugin_id` text?、`mix_id` text?、`mix_title` text?、`mix_cursor` text? | ADR 0018 §決定 10 的「模式」「Mix 身分」（M2 design §7.7 留給 M3）。`temporary`、`live` 不持久化（§9.4、§10） | 19 |

- **不建外鍵到 `installed_plugins`**：插件移除後曲目、電台都保留並標「音源未安裝」（ADR 0014 §決定 8、§16 第 10 條），`plugin_id` 只是字串。
- **`accounts` 沒有「已登入」欄位**：是否登入只看 `CredentialStore`（ADR 0012 §決定 3）。啟動時有帳號列卻沒有憑證就刪那一列；憑證「暫時無法讀取」只在記憶體（§6.2）。
- **`plugin_storage`** 已有 cascade（M1），移除插件時隨 `installed_plugins` 列刪掉。開發資料夾的插件也要有一列才寫得進 storage（§12.5）。

### 3.2 schema 版本與測試

- 依 PR 合併順序遞增：v7（PR 4：`installed_plugins` 三欄、`plugin_indexes`）→ v8（PR 7：`accounts`、`source_settings`）→ v9（PR 11：`developer_settings`）→ v10（PR 17：`scheduler_runs`）→ v11（PR 18：`radio_stations`、`network_settings` 一欄）→ v12（PR 19：`player_state` 五欄）。實際號碼以合併順序為準。
- 每次都照 `.trellis/spec/app/data/index.md` § 改 schema：快照、`stepByStep`、三種 migration 測試（空資料升級、資料完整性、不改使用者設定過的值）。
- `installed_plugins.enabled` 升級時既有列為真；測試斷言升級前裝好的 B 站插件升級後仍啟用、`manifest_json` 與 `script` 不變。
- `player_state` 加欄位後，既有列的 `mode` 是空（＝`queue`），M2 的佇列恢復行為不變；閘門是 M2 的恢復測試不改期望全綠。

### 3.3 設定組（ADR 0026 §決定 2「在引入該組的里程碑定案」）

「開發者」組 `developer_settings`：欄位全部可空，空＝沒設定過，預設只在 Notifier 套用（`app/AGENTS.md` § 設定）。

| 欄位 | 設定名 | 預設 | 說明 | PR |
|---|---|---|---|---|
| `developer_mode` | 開發者模式 | prod 關、dev 開 | ADR 0025 §決定 1 | 11 |
| `log_level` | log 層級 | `info` | `debug`／`info`；開發者模式關閉時同一筆寫入清空 | 11 |
| `plugin_dev_folder` | 插件開發資料夾 | 空 | 只有宣告 `pluginDevTools` 的平台寫；開發者模式關閉時清空（卸載） | 16 |
| `report_reminder_dismissed` | 「送出前請檢查」不再提醒 | 關 | GitHub 回報與診斷包共用（ADR 0023 §決定 4、ADR 0025 §決定 10）。存在這一組只是位置，一般使用者回報時也讀它（§8.28） | 13 |

- 整張表在 PR 11 一次建好，欄位清單在本設計已定案，只做一次 migration；Notifier 的 setter 跟著用到它的 PR 加（M2 播放組的做法）。
- 「網路」組 `network_settings` 加「電台狀態刷新間隔」：關閉／1／3／5／10 分，空＝5 分（ADR 0017 §決定 6）。放「網路」組照 M2 design §3.3 的歸類。
- 每音源設定表 `source_settings` 不是設定「組」，沒有 Notifier 的單列形狀，而是以插件 id 讀寫的 repository；設定頁不列它，開關在帳號頁（§6.7）。

### 3.4 M5 匯入的對應

| 舊（`docs/audit/data.md`、`accounts-network.md`） | 新 |
|---|---|
| `Account`（userId、userName、avatarUrl、isLoggedIn、isVip、sessionExpired、loginAt、lastRefreshed） | `accounts`：`user_id`、`display_name`、`avatar_json`（以 `[{url}]`）、`status`（`sessionExpired` → `invalidated`）、`logged_in_at`、`last_refresh_at`；`isVip` 不匯入；是否登入看匯入的憑證 |
| secure storage 的憑證（10.x） | `CredentialStore`（11.x），由 `legacy_import` 讀舊格式轉成 §6.1 的形狀（ADR 0010） |
| `Settings` 的「用登入狀態播放」 | `source_settings.browse_as_logged_in`（ADR 0012 §決定 6：照舊值） |
| `RadioStation`（url、title、thumbnailUrl、hostName、sourceType、sourceId、sortOrder、createdAt） | `radio_stations`：`plugin_id`＝`sourceType` 的音源 id、`room_id`＝`sourceId`、`artwork_json`＝`[{url: thumbnailUrl}]`、`sort_order`、`added_at`＝`createdAt`；`hostAvatarUrl`、`hostUid`、`isFavorite`、`lastPlayedAt` 不匯入（沒有讀它的功能） |
| `PlayQueue.isMixMode` 與 Mix 欄位 | `player_state.mode = mix` 與 `mix_*`（`mixPlaylistId` → `mix_id`）；`mix_cursor` 空，恢復後由插件以 `mixId` 重新取（§4.5） |

## 4. 宿主 API v1 的擴充（ADR 0028、0029）

### 4.1 原則

- **都在 v1 內，`hostApiVersion` 維持 1**：新增的都是選填欄位與新的匯出；宿主 API 還沒發佈。
- **凍結點**：`app/` 第一個 prod 版本對外發佈（M9 切換）時凍結 v1；之後加欄位就是 v2（ADR 0014 §決定 5 加一行，矛盾 11）。現在只有擁有者的 dev 版讀 index，沒有相容負擔。`fmp-plugins` 與 FMP 同一輪跟上。
- **同步點**：每加一個欄位或匯出，同一個 PR 改 `fmp-plugin.d.ts`、`manifestShapes`／`sourceDtoShapes`／`hostApiShapes`、`SourcePlugin` 的 Dart 方法、`FmpChecks`；閘門是 `type_definitions_test.dart`（M1）。
- **`SourcePlugin` 只在引入的 PR 加方法**（檔頭的規則）：`login*`（PR 8）、`liveSearch`／`liveStatus`／`resolveLive`／`liveRoomFromUrl`（PR 18）、`mix`（PR 19）、`multiPart`（PR 20）、`trackDetail`（PR 21）。

### 4.2 `HttpRequest` 的兩個欄位與 `HttpResponse` 的一個欄位

| 欄位 | 內容 | PR |
|---|---|---|
| `idempotent?: boolean` | 空＝依方法（GET、HEAD 等冪等方法才自動重試，現況）；`true` 讓語意冪等的 POST（YouTube innertube、網易查詢）也重試。慣例：gRPC 的 per-method `idempotency_level`、RFC 9110 §9.2.2；ADR 0013 本來就允許「音源標為可重試者」。ADR 0013 §決定 4 加一行指到 ADR 0028 | 1 |
| `authHeaders?: Record<string, string>` | 只在宿主判定要帶憑證（`decideAuth` 為 `attach`）時才加上的 header，例如 YouTube 從 `SAPISID` 算出的 `Authorization: SAPISIDHASH …`。名稱一律加進遮蔽的 header 名單（值是時間相關的雜湊，逐字登記沒有用）。帶不帶憑證仍只由 `auth` 一處決定 | 7 |
| `HttpResponse.credentialsAttached?: boolean` | 宿主告訴插件這次請求有沒有真的帶憑證（`decideAuth` 為 `attach` 才為真；`omit`、`refuse` 與 `auth: 'never'` 為假）。插件的「憑證無效」判定（§6.5）只在它為真的回應上成立：未帶憑證的 401、`-101` 是匿名請求被拒，不是憑證失效，不判定就不會誤標 `invalidated`。選填、v1 內的擴充（§4.1）；定義在 ADR 0028 | 7 |

- `idempotent: true` 只影響重試，不影響 `auth`、限流、網路紀錄。網路紀錄的 `retry` 欄位照常記。
- 閘門：`source_http_client_test.dart` 的 `retry` 群組加「`idempotent` 的 POST 重試、沒標的 POST 不重試」；`auth` 群組加「`authHeaders` 只在 attach 時出現、omit 與 refuse 時不出現」「`credentialsAttached` 只在帶了憑證時為真（attach 為真；omit、refuse、`auth: 'never'`、已失效為假）」。
- **`fmp-plugin.d.ts` 要改的清單**（同步點，§4.1）：`HttpRequest.idempotent`（PR 1）；`HttpRequest.authHeaders`、`HttpResponse.credentialsAttached`、`fmp.credentials.get()` 的回傳型別 `FmpLoginCredentials | null`（PR 7）；manifest 的 `login`、`FmpLoginCredentials`、四個 `login*` 匯出（PR 8）。各欄位同一個 PR 改 `hostApiShapes`／`manifestShapes`。

### 4.3 `login`（細節在 §6，ADR 0029）

manifest：

```ts
login?: {
  methods: ('qr' | 'webView' | 'cookie')[];
  webView?: {                       // methods 含 'webView' 時必填（§6.4）；UA 由平台層決定，不在這裡
    url: string;                    // 登入頁，網域在 allowedHosts
    cookieHosts: string[];          // 取 cookie 的網址（每個在 allowedHosts）
    doneCookies: string[];          // cookieHosts 的 cookie 裡這些都出現就算登入完成
  } | null;
  refresh?: 'onStartup' | null;     // 宣告支援刷新與時機（ADR 0012 §決定 5）
  browseAsLoggedInDefault?: boolean | null;  // 「以登入身分瀏覽與播放」的預設，空＝開
  automationRisk?: boolean | null;  // 真：開關旁顯示「以登入身分大量請求可能被視為自動化行為（推測）」
} | null;
```

匯出（宣告 `login` 能力時）：

| 匯出 | 簽章 | 何時呼叫 |
|---|---|---|
| `loginQrStart` | `() → {qrText, token}` | 使用者按「QR 登入」（methods 含 `qr`） |
| `loginQrPoll` | `(token) → {status: 'waiting'\|'scanned'\|'expired'\|'done', credentials?}` | QR 畫面開著時每 2 秒（UI 的一次性 `Timer` 接力，不是週期計時器；舊版間隔） |
| `loginVerify` | `(credentials) → {userId, displayName, avatar?: Artwork[]}` | 三種方式拿到憑證之後、寫入之前（ADR 0012 §決定 4） |
| `loginRefresh` | `(credentials) → credentials \| null` | 宣告 `refresh` 的插件：啟動時（§6.5）與失效時；`null`＝不需要或沒有新的；刷新失敗拋 `CredentialInvalid` |

- **憑證的形狀**：`FmpLoginCredentials = {cookies: Record<string, string>, extra?: Record<string, string> | null}`。`cookies` 是 cookie 名稱對值；`extra` 給不是 cookie 的東西（B 站刷新用的 `refresh_token`）。`fmp.credentials.get()` 回傳這個形狀或 `null`（現在回 `Record<string, string> | null`）。名稱不用 `FmpCredentials`：`fmp-plugin.d.ts` 裡它已是 `fmp.credentials` 那個宿主 API 物件的 interface。
- **`loginVerify`／`loginRefresh` 自己帶憑證**：這兩個呼叫時新憑證還沒寫入，宿主沒得注入；插件以傳進來的 `credentials` 自己組 `Cookie` header，請求標 `auth: 'never'`。宿主在呼叫前就把這組憑證的值登記到遮蔽函式，失敗也不取消登記（值本來就是秘密）。
- **QR 的 `done`**：插件從輪詢回應的 `Set-Cookie`（`HttpResponse.headers['set-cookie']`）取出憑證回傳。
- **`login*` 執行期間，該插件的 client 不把回應的 `Set-Cookie` 存進 cookie jar**（`loginQrStart`、`loginQrPoll`、`loginVerify`、`loginRefresh`）：登入回應設的 cookie 是憑證，只經 `CredentialStore` 與注入送出，不能落在 jar 裡繞過 `auth`（§6.3）。插件仍讀得到回應的 `Set-Cookie` header。登入期間插件只做登入，同一個 client 上其他請求的 `Set-Cookie` 一併不存可以接受；B 站的匿名 `buvid3` 在插件自己的 storage（§5.3），不受影響。

### 4.4 `live`（ADR 0028）

| 匯出 | 簽章 | 說明 |
|---|---|---|
| `liveSearch` | `({keyword, page, status?: 'live'\|'offline'\|null}) → {items: LiveRoom[], hasMore}` | 搜尋頁的「直播間」模式（§9.5）；`status` 是舊版的「全部／開播中／未開播」篩選 |
| `liveRoomFromUrl` | `({url}) → {roomId} \| null` | 「以網址新增」：不是這個插件的網址回 `null`；可以發請求（短網址） |
| `liveStatus` | `({roomId}) → LiveRoom` | 電台狀態工作與收聽中的 1 分鐘工作（§8、§9.2）。**查詢失敗一律拋錯**，宿主顯示「查詢失敗」，不能回 `offline`（D10） |
| `resolveLive` | `({roomId, formats}) → StreamResult` | 取直播流；`expiresAt` 可空（舊版沒有期限） |

`LiveRoom = {roomId, title, hostName?, artwork?: Artwork[], status: 'live'|'offline', online?: number}`（`online` 是舊版每分鐘刷新的人數）。

- `live` 的請求都是 `userPreference`（ADR 0012 §決定 2「電台」）。
- 能力屬於插件（ADR 0014 §決定 4）：只有宣告 `live` 的插件出現直播間模式與電台入口，宿主不認得 B 站。

### 4.5 `mix`（ADR 0028）

| 匯出 | 簽章 |
|---|---|
| `mix` | `({seed: {sourceId, cid?}} \| {mixId, cursor}) → {mixId, title, tracks: TrackSummary[], cursor: string \| null}` |

- **Mix 身分**＝（插件 id, `mixId`）。M3 存在 `player_state.mix_*`；M4 的 `playlists.kind = mix` 存同一對值（矛盾 8），ADR 0019 不改。
- `cursor` 是插件自己的不透明字串；`null` 表示這個 Mix 沒有更多，宿主下一次改以佇列最後一首當 `seed` 開新的一批（Mix 身分換成回傳的新 `mixId`；舊版的無限續播也會換種子）。
- 去重由宿主做：補來的曲目鍵已在 Mix 佇列裡就丟掉（§10）。

### 4.6 `multiPart`（ADR 0028）

- `TrackSummary` 加選填 `partCount?: number`（搜尋結果就知道的分 P 數；B 站搜尋回應的 `page`）。
- 匯出 `multiPart({sourceId}) → {parts: [{cid, title, durationMs?, index}]}`。`index` 從 1 起。
- 每個分 P 是一首曲目（ADR 0005：曲目鍵含 cid）；顯示「影片標題 · P2 分 P 標題」。

### 4.7 `trackDetail`（ADR 0028）

匯出 `trackDetail({sourceId, cid?}) → TrackDetail`：

```ts
TrackDetail = {
  description?: string | null;
  publishedAt?: number | null;            // UTC epoch 毫秒（同 StreamCandidate.expiresAt）
  uploaderAvatar?: Artwork[] | null;
  album?: string | null;                  // 網易
  stats?: {kind: 'view'|'like'|'favorite'|'comment'|'share'|'danmaku'|'coin', count: number}[] | null;
}
```

- 欄位取自舊版詳細面板（`lib/data/models/video_detail.dart`）有顯示的資料；熱門評論不放（§16 第 13 條）。`kind` 是封閉 union，宿主依它挑圖示與翻譯，不顯示插件給的文字。

### 4.8 `checks.json` 的擴充

- 每個新能力一個鍵，案例格式與 `search` 相同（`input`＋`expect`）。`login` 能力的案例是 `loginVerify`（重播時輸入是 fixture 裡已遮蔽的假憑證，不需要真登入）；`live` 是 `liveStatus`；`mix`、`multiPart`、`trackDetail` 各一條。
- **`requiresLogin: true`**：案例要登入才有意義。M3 只有 `login` 能力的案例（`loginVerify`）標它。每個能力只有一條案例，不另外為「登入後才有的行為」加案例：它會擠掉該能力匿名的那一條（例如 `resolveStream`）。
  - 契約測試照常重播 fixture（不需要真登入）。
  - 健康檢查與 App 內錄製（§12.5）遇到 `requiresLogin`：該插件**已登入**就用已存的憑證跑（`loginVerify` 的輸入取 `CredentialStore` 的憑證，不用案例裡的假憑證）；**未登入**標「略過」（ADR 0025 §決定 6）。
  - 命令列錄製略過它（命令列沒有憑證，ADR 0015 §決定 7）。
- `FmpChecks` 型別與 `checks_test.dart` 同步；「只收 `SourcePlugin` 已有方法的能力」照舊，所以每個能力的案例跟著它的方法同一個 PR 加。

### 4.9 被取代請求的取消（§8.11）

- **做在控制器層**：被取代的 `resolveStream`、`resolveLive` 的結果以代際檢查丟掉，不會播出，也不再因它發新的解析；已送出的 HTTP 讓它跑完。
- **理由**：YouTube.js 的請求經插件內的 fetch 補丁發出，QuickJS 沒有 AsyncLocalStorage，宿主無法把 `fmp.http.request` 對回是哪一次插件呼叫；要做就得要求每個插件手動傳呼叫 id，插件作者容易漏。代價只是被取代的請求多跑完幾百毫秒的流量。
- ADR 0018 §決定 6 加一行更正；§如何確認的「開直播取消進行中的音樂請求」改成「開直播後，進行中的音樂解析結果不會被播出，也不再發解析」（§16 第 2 條）。
- 閘門：控制器測試以會延遲完成的假插件：解析中開直播 → 解析完成後後端只收到直播流、`resolveStream` 呼叫次數不變。

## 5. 三個插件與 `fmp-plugins`

公開 repo，擁有者自己的（全域指示）；以該 repo 自己的 PR 合併，本機 clone 在與 FMP 同層的 `fmp-plugins/`。插件邏輯以舊 Dart 程式碼為規格、用 JS 重寫（ADR 0014 §決定 2）。

### 5.1 YouTube（`youtube`，PR 1 起）

- YouTube.js 18.1.0（探針版）以 esbuild 打成單一插件檔，Web API 以 `fmp.http.request` 補（M1 探針，`.trellis/tasks/archive/2026-09/09-30-youtubejs-probe/research/youtubejs-probe.md`）。打包腳本與 YouTube.js 的版本釘在 `fmp-plugins/youtube/`，產物與原始碼一起提交（index 只認單一 `.js`）。
- `resolveStream`：先匿名（VISIONOS 等不需要 PO token 的 client），依 `formats` 與 `quality` 挑 opus／aac；`expiresAt` 從網址的 `expire` 參數讀（取代舊版寫死的 1 小時，D9）；`checks.json` 的 `expiresAtPattern` 是 `[?&]expire=(\d+)`。
- innertube 的 POST 標 `idempotent: true`（§4.2）。
- 錯誤對應表（ADR 0013 §決定 2，插件目錄內）：「確認你不是機器人」→ `VerificationRequired`；`LOGIN_REQUIRED`（年齡限制）→ `Unavailable(age)`；`UNPLAYABLE` 地區 → `Unavailable(region)`；429 由網路層轉 `RateLimited`。「憑證無效」判定表在 PR 10 加：帶憑證的請求（`HttpResponse.credentialsAttached` 為真）回 401，或回應的 `responseContext` 表示已登出。
- 遮蔽名單：Google 帳號 cookie 名（`SAPISID`、`__Secure-1PSID`、`__Secure-3PSID`、`__Secure-3PAPISID`、`LOGIN_INFO` 等）與 `googlevideo.com` 的簽名參數已在 M1 的內建名單（`lib/core/redaction/redaction_lists.dart`），插件不必追加。
- **`googlevideo.com` 的 `expire` 從內建的簽名參數移除**（PR 1）：它在內建名單裡，錄 fixture 時整個參數被拿掉（`redactor_test.dart` 的 googlevideo 案例），重播時插件讀不到期限，`expiresAtPattern` 的契約檢查必紅。`expire` 是公開的到期時間、不是憑證，與 B 站 `deadline` 不遮的理由相同（`redaction_lists.dart` 的註解）。閘門：`redactor_test.dart` 的 googlevideo 案例改成 `expire` 保留、`sig`、`ip` 等照拿掉。
- 效能風險：約 800 KB 的插件在 QuickJS isolate 的載入時間，PR 1 以 `plugin_runtime_benchmark_test.dart` 兩平台量一次，寫進 PR 描述；超過 3 秒再談（延遲載入或縮小打包）。

### 5.2 網易雲（`netease`，PR 2 起）

- 舊 `lib/data/sources/netease_source.dart` 為規格：搜尋（`/api/cloudsearch/pc`，舊版收了 `order` 沒用的問題不帶過來）、取流 eapi `/song/enhance/player/url/v1`。
- **eapi 的 AES-128-ECB 與 MD5**：宿主 `crypto` 只有 md5／sha256，AES 由插件內附純 JS 實作（不擴充宿主 API，YouTube.js 補 Web API 的先例，ADR 0014 §決定 10）。授權相容的實作（MIT）打包進插件檔。
- **`previewOnly`**：只拿到試聽片段（回應的 `freeTrialInfo` 不為空）時回 `previewOnly: true`；修掉舊版把試聽當完整歌曲播的 D4。
- **候選備援順序不升為規範**（§8.13）：輸出本來就是「依優先序排好的候選串流」（ADR 0014 §決定 5），順序由各插件決定。
- **`X-Real-IP`**（舊版對寫入請求附偽造的 `118.88.88.88`，B3）：PR 2 以匿名真實連線各測一次「不帶」與「帶」的搜尋與取流，結果寫進 PR 描述與插件 README；處理見 §16 第 14 條。
- 音質對應 `high`→`exhigh`、`medium`→`standard`、`low`→`standard`（舊版的 `lossless` 需要 VIP，M3 不送；登入後的 VIP 音質之後再談）。
- 錯誤對應：`code: -460`（風控）→ `VerificationRequired`；`code: 404`／空 `url` → `Unavailable`（原因依 `fee`）；「憑證無效」判定表（PR 10）：帶憑證的請求（`credentialsAttached` 為真）回 `code: 301`。
- 同一個插件之後（M7）多宣告 `lyrics` 就是網易歌詞源（能力屬於插件，ADR 0014 §決定 2、4）。

### 5.3 B 站（既有，PR 3、8、10、18、20、21 跟著改）

- PR 3：標題解 HTML 實體（`&#x27;` 等，M2 驗收留下）；封面回傳多尺寸（hdslb 的 `@160w`、`@480w` 後綴，宿主 `pickArtwork` 已會挑）；manifest 版本照 semver 升到 1.0.0（§7.2）。
- PR 8：`login`（QR，舊 PiliPlus 慣例）；PR 10：刷新（RSA-OAEP＋`correspond`＋`refresh_csrf`，純 JS 實作；舊 `bilibili_crypto.dart` 為規格）與「憑證無效」判定表（`code: -101`）；PR 18：`live`（`/room/v1/Room/playUrl` 取 `durl` 第一個、`qn=80`，舊版 `bilibili_live_client.dart`）；PR 20：`multiPart`；PR 21：`trackDetail`。
- 匿名 cookie（`buvid3`）照舊由插件存 `plugin_storage`；登入後的 Cookie 以憑證為準合併（§6.3，ADR 0012 §決定 1 加一行，矛盾 6）。

### 5.4 Android 時長未知的前瞻（§8.14，M2 待辦 2）

- PR 1 實機確認 YouTube 串流（`googlevideo` 的 webm／m4a）在 just_audio 有沒有時長事件；有就沒事。
- 沒有時：`PlaybackSession` 對時長未知的前瞻不排（不送 `setNext`），這一首以 `completed` 換歌，只失去無縫。這是後端差異，寫進 `AudioBackend` 的 dartdoc（ADR 0018 §決定 3），不改 ADR。
- `live` 模式只有一項，不排前瞻（§9.4）。
- 閘門：`playback_session_test.dart` 以假後端回報時長為空，斷言不呼叫 `setNext`、`completed` 時換到下一首。

## 6. 帳號與憑證（ADR 0012、0029）

### 6.1 `CredentialStore` 與平台層的 secure storage

- **套件**：`flutter_secure_storage` 11.2.0（ADR 0012 §決定 3 的 11.x，2026-09-16 發佈）。
  - Android：RSA-OAEP 包 AES-GCM 的金鑰（11.x 的預設）。**`AndroidOptions(resetOnError: false)`**：套件預設讀取失敗時清空，違反 ADR 0012「讀取失敗時不刪除」。
  - Windows：值以 AES-GCM 加密存在 application support 目錄的 `.secure` 檔，金鑰在 Credential Manager（`flutter_secure_storage_windows` 4.2.2 的 README）。所以沒有 Credential Manager 單筆約 2.5 KB 的限制，YouTube 的整組 cookie 放得下。
  - dev 與 prod 分開（ADR 0015 §決定 8）：Android 以 `applicationIdSuffix` 自然分開；Windows 的 application support 目錄依 ProductName 分開。PR 7 實機確認兩個 flavor 的檔案在不同目錄，另以鍵前綴 `fmp-dev.`／`fmp.` 再保險一次（`AndroidOptions.storageNamespace` 為 `fmp-dev`／`fmp`）。
  - **鍵只用檔名安全的字元**（小寫英數、`.`、`-`）：Windows 實作直接以鍵當 `<鍵>.secure` 的檔名，不做跳脫（`flutter_secure_storage_windows` 的 `Write`／`Read`），`:` 在 NTFS 是替代資料流的分隔，`readAll` 也列不到。插件 id 只有小寫英數與 `-`，可以直接放進鍵。
- **平台層** `lib/platform/secure_storage/`：介面 `SecureStorage { read(key), write(key, value), delete(key), deleteAll() }`（`deleteAll` 只刪自己前綴的鍵，不呼叫套件的全刪），宣告 `PlatformCapabilities.secureStorage`（Android、Windows 真）。`flutter_secure_storage` 只准在平台層（§2.2）。
- **`CredentialStore`**（`lib/plugins/accounts/credential_store.dart`）：唯一憑證來源，鍵 `credentials.<pluginId>`（加上 §6.1 的前綴），值是 §4.3 `FmpLoginCredentials` 的 JSON。
  - 讀取：啟動時每個裝了 `login` 插件各讀一次放記憶體；之後請求只讀記憶體。
  - **讀取失敗**：該插件狀態為「暫時無法讀取」（記憶體），不刪除、不帶憑證，30 秒後重讀一次（一次性 `Timer`），帳號頁顯示「暫時無法讀取，稍後重試」。
  - 載入或寫入時把每個 cookie 值與 `extra` 值登記到遮蔽函式；登出或移除時取消登記。短於 `Redactor.minimumSecretLength`（4）的值不登記：`registerSecret` 對它們拋 `ArgumentError`，而 B 站這類網站會一起回 `home_feed_column=5` 之類的短值，不略過的話登入整個失敗。這種值也不是秘密（真正的憑證 cookie 都更長）。
- 實作 `CredentialSource`（`core/network/auth.dart`）。介面**不回傳拼好的 `Cookie` 字串**，改回傳材料，合併在網路層做（§6.3）：
  - `credentialMaterial(pluginId)` → `({Map<String, String> cookies, Map<String, String> headers})?`：`cookies` 是 cookie 名稱對值，`headers` 是要附加的標頭（M3 的官方插件用不到，留給憑證不是 cookie 的音源；`authHeaders` 仍來自請求）。`status == invalidated`、沒有憑證或暫時無法讀取時回 `null`（已失效：保留憑證、停止帶它，ADR 0012 §決定 5）。取代 M1 的 `credentialHeaders(pluginId)`。
  - `credentialCookieNames(pluginId)` → `Set<String>`：憑證裡有的 cookie 名稱，**已失效時照樣回傳**（保留的憑證名稱仍不准從 cookie jar 送出，§6.3）；沒有憑證回空集合。
  - `browseAsLoggedIn(pluginId)` 照舊。

### 6.2 帳號表與每音源設定

- `accounts` 一列＝一個登入過的插件；`status`：`active`／`invalidated`。
- **啟動對齊**：有 `accounts` 列卻讀到沒有憑證（不是讀取失敗）→ 刪那一列；有憑證卻沒有列（寫入中斷）→ 刪憑證。兩者都記 warning。
- **「以登入身分瀏覽與播放」**（ADR 0012 §決定 6，§8.6）：名稱就是這句；`source_settings.browse_as_logged_in` 空＝manifest 的 `login.browseAsLoggedInDefault`（空＝開）。三個官方插件都不宣告（＝開），YouTube 宣告 `automationRisk: true`，開關旁顯示說明。宿主沒有音源分支。
- 診斷包的登入狀態（是／否）取自 `CredentialStore`，不含帳號名稱（ADR 0011 §決定 6）。

### 6.3 注入、Cookie 合併、遮蔽

- 認證攔截器照 `decideAuth`：`attach` 時取 `credentialMaterial` 的 `cookies` 合併進請求的 `Cookie` header，再加上 `headers` 與請求的 `authHeaders`。`HttpResponse.credentialsAttached`（§4.2）由同一處設定。
- **合併規則**（M2 待辦 12）：插件自己送的 `Cookie`（例如匿名 `buvid3`）、cookie jar 裡的、憑證的三者，**同名以憑證為準**，其次是插件 header，最後是 jar。實作上認證攔截器先合併前兩者，cookie 攔截器併 jar 時跳過 header 已有的名稱。舊版就是合併（`accounts-network.md` §1）。
- **憑證的 cookie 只經注入送出，不經 cookie jar**（ADR 0029 §決定 4）。`dio_cookie_manager` 的 `loadCookies` 把 jar 的 cookie 接在每個請求上、不看 `auth`；憑證若落進 jar，B 站 QR 登入後 `auth: 'never'` 的請求，或「以登入身分瀏覽與播放」關掉時的 `userPreference` 請求，仍會帶出 `SESSDATA`，違反 ADR 0012。兩條規則一起守：
  1. **登入時不存**：`login*` 匯出執行期間（§4.3），該插件的 client 不把回應的 `Set-Cookie` 存進 jar。
  2. **送出時跳過**：cookie 攔截器併 jar 時，跳過 header 已有的名稱，**也跳過 `credentialCookieNames(pluginId)` 的名稱**——不論這次請求有沒有帶憑證（`auth: 'never'`、開關關閉、已失效都一樣）。非登入請求的回應若設了同名 cookie 照樣會存進 jar（`_OwnHostCookieJar` 的規則不變），但送出時被跳過。
  - 實作位置（子類覆寫 `_OwnHostCookieManager` 的 `saveCookies`／`loadCookies`，或在 `_OwnHostCookieJar` 加過濾）與「登入中」旗標怎麼傳到 client，PR 7、8 決定；旗標的範圍是 client 層，不要求辨識是哪一次插件呼叫（§4.9 同樣的理由）。
- `omit` 與 `refuse` 時 `authHeaders` 整個丟掉。
- 網路紀錄的 `credentials` 欄位照舊記是否帶了憑證。
- 閘門（`auth_test.dart`、`source_http_client_test.dart`）：
  - `AuthRequirement` 三種 × 未登入／已登入開關開／已登入開關關（ADR 0012 §如何確認；把現有 `NoCredentials` 版本換成假的 `CredentialStore`）；
  - 同名 cookie 三方來源的合併結果；`authHeaders` 只在 attach；
  - **cookie jar 送出時不含憑證名稱的 cookie**（jar 裡先放一個與憑證同名的 cookie，`attach`、`omit`、已失效三種都斷言送出的 `Cookie` 沒有 jar 的那一個）；**`auth: 'never'` 的請求在登入後不帶憑證 cookie**（PR 7）；
  - **jar 不存登入回應的 cookie**：`login*` 執行期間回應的 `Set-Cookie` 不進 jar，執行結束後的一般回應照常存（PR 8，`login*` 匯出在這個 PR 才有）；
  - 已失效時不帶；
  - 媒體 client 在已登入時仍不帶任何 `Cookie`／`Authorization`（M1 已有，三個插件的契約都跑）。

### 6.4 三種登入方式（ADR 0012 §決定 4）

UI 顯示「manifest `login.methods` ∩ 平台有能力」：`qr`、`cookie` 不需要平台能力；`webView` 要 `PlatformCapabilities.loginWebView`。

| 音源 | methods | 依據 |
|---|---|---|
| B 站 | `qr` | ADR 0012「B 站、網易以 QR 為主」；PiliPlus |
| 網易 | `qr` | 同上 |
| YouTube | `webView`、`cookie` | ADR 0012 §決定 4；ytmusicapi 的瀏覽器 cookie |

這拿掉了舊版 B 站的 WebView 分頁與 Android 網易的 WebView（§16 第 4 條）。

- **QR**：`loginQrStart` → 以 `qr_flutter` 4.1.0 畫出 `qrText`（舊版用的套件；2023-05 後沒有新版，但 2.1M 次／30 天下載，功能完整；壞掉時換 `pretty_qr_code` 3.6.0，兩者都只依賴 `qr`）→ 每 2 秒 `loginQrPoll`，`scanned` 顯示「已掃描，請在手機上確認」，`expired` 顯示「已過期」與「重新產生」→ `done` 取得憑證 → `loginVerify` → 寫入。離開畫面停止輪詢。
- **App 內網頁登入**（R1 通過，`research/r1-youtube-login.md`；ADR 0029 §決定 9）：
  - 套件 `flutter_inappwebview` 6.2.0-beta.3（釘死；2026-10-08 擁有者決定）。6.1.5 的 Android 部分在 AGP 9.1.0 要靠會被拿掉的暫時旗標才建得起來，beta.3 原樣能建、API 相容。兩者的 Windows 都要在 `app/windows/CMakeLists.txt` 加 `add_definitions(-D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)`（MSVC 14.51 的 STL1011）。其他候選見 ADR 0029。
  - 平台層 `lib/platform/login_webview/`：`LoginWebView { Widget build(LoginWebViewSpec spec, {onCookies}); Future<Map<String,String>> cookies(List<Uri> hosts); Future<void> clear(List<Uri> hosts); Future<void> clearAll(); }`；宣告 `PlatformCapabilities.loginWebView`（Android、Windows 真）。`clear` 對每個網址 `getCookies` 後逐一以名稱、domain、path 刪除（`getCookies(accounts.google.com)` 也回 `.google.com` 的 cookie）。
  - **UA 由平台層決定**：Android 取 `InAppWebViewController.getDefaultUserAgent()` 拿掉 `; wv`（也處理沒有空白的 `;wv`），其餘不動；Windows 不設。R1：Android 的桌面 Chrome UA 被擋在 `/v3/signin/rejected`；Windows 的預設與桌面 UA 都能登入。
  - Windows 以 `WebViewEnvironment.create(settings: WebViewEnvironmentSettings(userDataFolder: <資料目錄>/webview))`，dev 與 prod 的 WebView 資料跟著資料目錄分開，「重設資料」能整個刪。
  - 流程：開 manifest 的 `webView.url` → 每次 `onLoadStop` 讀 `cookieHosts` 的 cookie → `doneCookies` 都出現時關頁 → `loginVerify` → 寫入。取到的 cookie 只交 `loginVerify`，不進 log。**不以網址判定完成**：Android 登入後會先插入 `gds.google.com` 的提示頁，最後落在 `m.youtube.com`；Google 帳號的同名 cookie 在 `.google.com`、`SetSID` 之前就出現，所以只看 `cookieHosts`。
  - **跳轉卡住**（R1 在 Windows 看到，原因未明）：`url` 的網域已有 cookie、`cookieHosts` 的 `doneCookies` 15 秒內仍沒齊時，顯示「登入沒有完成」與「重試」；重試在 Windows 重建 `WebViewEnvironment`（同一個使用者資料目錄）再開登入頁，Android 重建 WebView。仍不行就提示重開 App（R1 驗證過：重開後登入狀態還在，再開登入頁就完成）。
- **貼上 cookie**：多行輸入框，接受瀏覽器 DevTools 複製的 `name=value; name2=value2` 或 Netscape `cookies.txt`；宿主解析成 `cookies` 表 → `loginVerify` → 寫入。輸入框的內容不進 log、不進錯誤報告。說明文字附「如何取得」的通用步驟（不指名音源）。
- 三種方式之後都是「`loginVerify` 通過才寫入」：先寫 `CredentialStore`，成功後寫 `accounts`（`status = active`、`logged_in_at`），再登記遮蔽。`loginVerify` 拋錯就不寫，顯示錯誤（ADR 0013 的呈現表）。

### 6.5 失效與刷新（ADR 0012 §決定 5，§8.24）

- **判定在插件**：每個插件的「憑證無效」判定表在插件目錄內（§5），**只在 `HttpResponse.credentialsAttached` 為真的回應上判定**（§4.2；匿名請求被拒不是憑證失效）；判定成立時插件拋 `CredentialInvalid`。網路錯誤、限流、風控碼不算（ADR 0013）。
- **單飛刷新在插件呼叫層**（不是 dio 的 `QueuedInterceptor`）：判定在 JS 內、dio 層看不到（§16 第 1 條）。
  - `lib/plugins/accounts/` 的 `AccountGuard` 包住對插件的每次呼叫：呼叫丟 `CredentialInvalid` 時，同一插件只有一個刷新在跑（`Future` 共用）。
  - 插件宣告 `refresh`：`loginRefresh(目前憑證)` → 拿到新憑證就寫入（`last_refresh_result = refreshed`）並**重跑原呼叫一次**（新的呼叫會帶新憑證，等同「以新憑證重建請求」）；回 `null` 或拋錯 → 標 `invalidated`。
  - 沒有宣告 `refresh`：直接標 `invalidated`。
  - 標 `invalidated`：保留憑證、之後不帶、提示一次「{音源}的登入已失效」附「登入」（ADR 0013 §決定 5 的呈現表）；重跑不發生，原呼叫的錯誤照常往上。重新登入（回到 `active`）後下一次失效會再提示。
- **啟動刷新**：宣告 `refresh: 'onStartup'` 且有憑證的插件，在第一幀之後、網路狀態第一次是 `Online` 時呼叫一次 `loginRefresh`（ADR 0016「離線中不發背景請求」）。不登記成排程器工作（不是週期工作），也不進啟動維護清單（那份是一次性的本機維護）；由 `AccountService` 自己聽網路狀態，跑過就不再跑。
- **不做全面驗證**：啟動時不對每個帳號打帳號資訊 API（舊版的 `verifyAllAccountStatuses`）；只有帶了憑證的請求才可能觸發失效（ADR 0012）。
- **「需要重新登入」的入口**：帳號頁該列（狀態與「重新登入」）、失效提示的「登入」動作；搜尋 chip 不加標記。
- 閘門：
  - 刷新後重跑的那次請求帶的是新憑證（ADR 0012 §如何確認）；同時三個呼叫失效只刷新一次；
  - 每個音源的「憑證無效」判定表（契約 fixture：401／-101／301 各一，`credentialsAttached` 為真；另各一條 `credentialsAttached` 為假的同樣回應，不判定）；限流與網路錯誤不標失效；
  - 啟動刷新在 `noInterface` 時不發、變 `Online` 後發一次。

### 6.6 登出、移除插件、重設資料

| 動作 | 清什麼 |
|---|---|
| 登出（帳號頁，確認框） | 該插件的 `CredentialStore` 項目、`accounts` 列、遮蔽登記、該插件的記憶體 cookie jar、WebView 中 `login.webView.cookieHosts` 的 cookie（有 WebView 時）。`source_settings` 保留 |
| 移除插件 | 上一列全部，加上 §7.4 的移除流程 |
| 重設資料（Debug 頁，§12.2） | 資料庫、`SecureStorage.deleteAll()`、WebView 全部資料（`clearAll`）、快取 |

- 閘門：登出與重設後 `CredentialStore` 為空、之後的 `userPreference`／`required` 請求不帶憑證（ADR 0012 §如何確認）；WebView 的清除以假 `LoginWebView` 斷言被呼叫（真的清除在 PR 9 實機驗）。

### 6.7 帳號頁

- **位置**：設定頁的第一個區塊「帳號」（舊版 `features.md:201`），每個宣告 `login` 的已啟用插件一列。設定頁的區塊順序：帳號、外觀、播放、網路、插件、關於；開發者模式下最後多一個 Debug（ADR 0024 §決定 6 加一行，矛盾 12）。
- **一列的內容**：插件圖示與名稱；未登入時是登入方式的按鈕（「QR 登入」「網頁登入」「貼上 cookie」）；已登入時是頭像、名稱、狀態（正常／已失效／暫時無法讀取）、最後刷新時間與結果（宣告 `refresh` 時）、「以登入身分瀏覽與播放」開關（`automationRisk` 時附說明）、「登出」。已失效時多「重新登入」。
- 離線時頁面照常可用（本機資料），登入按鈕照送（ADR 0016 §決定 7 的更正），失敗才顯示離線空狀態。
- 閘門：widget 測試（三種 methods 與平台能力的交集；已失效列；離線；guideline 400／1000 寬）。

## 7. 插件庫與生命週期（ADR 0030）

### 7.1 `index.json` 與讀取

```json
{
  "indexVersion": 1,
  "plugins": [
    {
      "id": "youtube", "name": "YouTube", "author": "1morr", "description": "…",
      "version": "1.0.0", "apiVersion": 1,
      "capabilities": ["search", "resolveStream", "login"],
      "allowedHosts": ["youtube.com", "googlevideo.com"],
      "url": "https://raw.githubusercontent.com/1morr/fmp-plugins/main/youtube/youtube.js",
      "sha256": "…",
      "checksUrl": "https://raw.githubusercontent.com/1morr/fmp-plugins/main/youtube/checks.json",
      "checksSha256": "…"
    }
  ]
}
```

- **託管**：`fmp-plugins` 的 `main` 分支，經 `raw.githubusercontent.com` 讀。index 與 `.js` 在同一個 commit 由腳本產生，CI 檢查 index 是最新的。慣例：Obsidian `community-plugins.json`、MusicFree 的訂閱 JSON。不用 GitHub Pages（要改 repo 設定，同樣有 CDN 延遲）。
- **官方網址**放 `lib/core/endpoints.dart`（`fmp_url_literal`）。
- **SHA-256 不符就拒裝**，提示「插件庫剛更新，請稍後再試」（raw 的 CDN 快取約 5 分鐘，index 與 `.js` 可能短暫不一致）。
- **`checksUrl`／`checksSha256`**（本設計新增）：從 index 安裝或更新時一併下載並存進 `installed_plugins.checks_json`，健康檢查用它（§12.5，§16 第 12 條）。驗證不過就照樣安裝插件、只是不存 checks（健康檢查顯示「沒有檢查案例」）。
- **欄位封閉**：不認得的欄位整個拒收（同 manifest 的規則），`indexVersion` 不是 1 就拒絕讀並提示「需要更新 FMP」。
- **讀取用的 client**（`lib/core/network/host_fetch.dart`）：宿主自己的請求（index、插件檔、checks），以媒體 client 的規則為底（不帶憑證、沒有 cookie、只准 `https`、大小上限、逾時、網路紀錄），允許網域是「該網址自己的 host」，轉址不得換 host（GitHub raw 不轉址；使用者給的網址會轉到別處就失敗並說明）。上限：index 1 MiB、插件檔 8 MiB、checks 256 KiB。網路紀錄的 `pluginId` 為空、`client` 是 `host`（log 格式加一個值，`network log` 群組一起改）。
- **自訂 index**：加入時提示「非官方來源：這個清單的插件沒有經過 FMP 審查」，確認才存 `plugin_indexes`。每個已安裝插件記住來源 index（`source_index_url`），只從那裡更新；不同 index 有同 id 時，「可安裝」清單各自列出並標來源，已安裝的那個只看自己的來源。

### 7.2 `fmp-plugins` 的 CI 與版本

- **workflow**（`fmp-plugins/.github/workflows/ci.yml`）：以 repo 變數 `FMP_REF`（FMP 的 commit SHA）checkout FMP，對每個插件目錄跑 `FMP_PLUGIN_DIR=… flutter test test/plugins/contract/contract_test.dart`（重播），再跑 `tool/build_index.dart --check`（index 是最新的）。宿主 API 變了就開 PR 改 `FMP_REF`。慣例：GitHub Actions 以 SHA 釘版本。
- **index 產生腳本** `tool/build_index.dart`（Dart，不加 Node 依賴）：讀每個目錄的 `.js` 標頭 manifest，算 SHA-256，寫 `index.json`。改了 `.js` 沒重產 index，CI 紅。
- **版本**：semver；`.js` 一有改動（相對 `main`），CI 要求 manifest 版本比 `main` 的高。B 站從 0.1.0 升到 1.0.0（PR 3），YouTube、網易從 1.0.0 起。
- **冒煙測試**（`--live`）照 ADR 0015 §決定 4 不進 CI。

### 7.3 啟用與停用（§8.17）

- `installed_plugins.enabled`（預設真）。停用＝不載入 runtime：不出現在搜尋 chip、帳號頁、健康檢查、排程器（ADR 0017 §決定 5 立即移除它的工作）；佇列與 Mix 裡它的曲目照「音源未安裝」的方式跳過，標「音源已停用」（`pluginNameProvider`，PR 4）；電台列標「音源已停用」、點了提示；憑證與 storage 保留。
- **「沒有回應」**是執行期狀態（ADR 0014 的看門狗），到重啟為止，不存資料庫；插件頁直接把它停用（M1 follow-up：插件無限迴圈呼叫宿主 API 時只會一直 `NetworkError`、不會被看門狗停用，使用者手動停用解決）。
- 慣例：VS Code 的擴充功能啟用與停用、MusicFree 的「禁用」。
- 閘門：`plugin_registry_test.dart`：停用後 registry 沒有它、啟用後載入；`enabled` 跨重啟；排程器的工作被移除（PR 17 後補一條）。

### 7.4 安裝、更新、移除（§8.18）

- **安裝前確認**（ADR 0014 §決定 6）：對話框列出名稱、作者、版本、能力（翻譯過的名稱）、會連的網域，警告「此腳本會以你的登入身分存取這些網站」；從檔案或網址安裝另加「非官方來源」。
  - 從 index 安裝：先下載並驗過 SHA-256，**對話框的內容取自下載到的 `.js` 標頭 manifest**；它的 `id`、`version`、`apiVersion`、`capabilities`、`allowedHosts` 與 index 那一筆不同就拒裝。自訂 index 的 SHA 由同一份 index 提供，只驗得了「檔案是 index 說的那個」，驗不了 index 自己寫的能力與網域。更新時「新增的能力或網域」也以兩份 manifest 比。dev 的 `--fmp-dev-plugin` 入口照舊跳過確認（prod 不讀）。
- **更新**：只在打開插件頁或按「檢查更新」時比對 index（ADR 0014 §決定 7）；semver 只升不降（`pub_semver` 2.2.1，Dart 團隊維護）；`apiVersion` 不相容時顯示「需要更新 FMP」並停用按鈕。同 id 更新保留 storage 與憑證。**能力或網域比目前版本多時**，先列出新增的部分再確認（§16 第 11 條）；「全部更新」遇到這種插件就逐個問，沒有增加的直接更新。慣例：Chrome 擴充功能要求新權限時先停用等確認、Android 的權限變更提示。
- 更新後佇列與網址快取以新插件重新解析（M2 PR 7 的快取鍵含插件實例，`plugin_installer_test.dart` 已有；M3 實機第一次有入口，M2 待辦 8）。
- **移除**：確認框 → 關閉 runtime → `CredentialStore` 刪除與遮蔽取消登記 → 刪 WebView 中該插件 `cookieHosts` 的 cookie → 刪 `accounts`、`source_settings` 列 → `CacheStore.removePlugin`（M2 已有）→ 排程器移除工作（PR 17 起）→ 刪 `installed_plugins` 列（`plugin_storage` cascade）。中途失敗就停在那一步、記錯、提示；再按一次從頭跑（每一步都可重複）。
- **曲目保留**，顯示「音源未安裝」取代目前顯示插件 id 的做法（`pluginNameProvider`）；電台列同樣保留（§16 第 10 條）。
- **Redactor 去重**（M1 待辦 14）：插件更新與重新載入時，`Redactor` 的 `_mediaCdns` 以插件 id 為鍵取代，不再累加。
- 閘門：`plugin_installer_test.dart`：SHA 不符拒裝且不寫資料庫；index 的能力或網域與 `.js` manifest 不同時拒裝；semver 降版不顯示更新；`apiVersion` 不符；更新保留 storage 與憑證；能力或網域增加時回傳「需要確認」；移除後每一步的資料都不在（CredentialStore、accounts、cache 項目、storage、installed_plugins）；移除中途失敗後重跑可完成。

### 7.5 插件頁（§8.20）

- **位置**：設定頁區塊「插件」（MusicFree「插件管理」、LX Music「自訂源」都在設定裡）。expanded 以上照設定頁的 list-detail，右側是插件頁。
- **兩個分頁**（VS Code Extensions 的「已安裝／市集」）：
  - **已安裝**：每列名稱、版本、作者；標記（開發中／已停用／沒有回應／有更新）；展開看能力、網域、來源；動作：啟用開關、更新、移除、登入（連到帳號頁該列）。
  - **可安裝**：官方與自訂 index 的插件（已裝的標「已安裝」），點了走 §7.4 的確認。
- **工具列**：檢查更新、全部更新、從檔案安裝（`file_picker` 選 `.js`）、從網址安裝、管理 index（列表、加入、刪除自訂 index）。
- 健康狀態留在 Debug 頁（ADR 0025 §決定 6）。
- 離線：已安裝分頁照常；可安裝分頁讀 index 失敗時顯示共用的離線空狀態（ADR 0016 §決定 7）。
- 閘門：widget 測試（兩分頁、標記、啟用開關寫入、更新確認、離線；guideline 400／1000 寬）。

### 7.6 首次啟動引導（§8.19）

- **觸發**：沒有任何已啟用、具 `search` 能力的插件。
- **呈現**：搜尋頁就地的空狀態，不做精靈（ADR 0024 §決定 9「容易卡住處就地說明」）：說明一句、官方 index 的插件清單（預設全勾）、「安裝」一次確認（列出全部所選插件的能力與網域、一則共同警告）後依序安裝，失敗的列出、其他照裝。
- 離線（讀不到 index）時顯示離線空狀態與「重試」；略過（「稍後再說」）後的空狀態附「前往插件頁」。
- dev flavor 已有測試插件（`fmp-test` 有 `search`）就不出現。
- 慣例：MusicFree 沒有插件時的空狀態引導。
- 閘門：widget 測試（零插件時出現、裝好後消失、全部停用時再出現、離線、部分失敗）。

## 8. 背景排程器（ADR 0017）

### 8.1 `BackgroundScheduler`

- `lib/scheduler/background_scheduler.dart`，以 Riverpod Notifier 建立（ADR 0017 採用的慣例），由 `appLifecycleProvider`（M2）與 `networkStatusProvider`（M2）驅動。
- **工作**：`SchedulerJob {String id; String? pluginId; Duration? interval; Future<void> Function(JobContext) run;}`；`register`／`unregister`。`interval` 為空＝關閉。
- **一個計時器**：一次性 `Timer` 指向最早到期的工作；到期、狀態改變、登記變動時重算。排程器本身不用 `Timer.periodic`（允許清單仍包含它，ADR 0017 的字面）。
- **何時跑**：`resumed`／`inactive` 且 `Online`。`hidden`／`paused` 或不在線：取消計時器，進行中的工作跑完，不開新的。變可見或回到 `Online`：到期的工作各跑一次。App 啟動視同變可見（M3 唯一的工作電台狀態先顯示 `radio_stations` 存的狀態，§9.2）。
- **並行**：全域最多 2 個，同一 `pluginId` 依序；網路層的限流照常。
- **失敗與退避**：工作丟錯時 1、2、4… 分鐘退避，上限為該工作的間隔；`RateLimited.retryAfter` 優先。錯誤以 `log.report` 寫進錯誤歷史，不跳提示（ADR 0013 §決定 5「背景工作不跳 toast」）。
- **上次成功時間**：成功時寫 `scheduler_runs`；登記時讀它算下一次到期，重啟後照算。
- **手動刷新**：`runNow(id)` 不看間隔（電台頁的刷新鈕）；不在線時不發，回傳「離線」讓呼叫端顯示離線狀態。
- **取消**：`unregister`、插件停用或移除、間隔改成關閉時立即移除；每次執行帶代際，過期的結果由工作自己以 `JobContext.isCurrent` 丟掉。
- 時間一律以 `clock` 讀，測試用 `fakeAsync`。

### 8.2 閘門

ADR 0017 §如何確認的七項各一組單元測試（假時鐘、假生命週期、假網路狀態）：

1. 看不見與離線時不跑；
2. 恢復後到期的工作各跑一次（沒到期的不跑）；
3. 任何時刻待執行的計時器最多一個（`fakeAsync` 的 `pendingTimers`）；
4. 手動刷新不看間隔；
5. 移除或停用後不再跑，進行中的結果被丟掉；
6. 退避序列與上限、`retryAfter` 優先；
7. 上次成功時間重啟後生效（新的 Notifier 讀同一個資料庫）。

另有：同一插件依序、全域最多 2 個；lint `fmp_periodic_timer_owner` 的雙向變異（§2.2）。

### 8.3 位置與文件

- `app/AGENTS.md` 加 § 排程器（規則與閘門），`.trellis/spec/app/` 不另開一層：排程器只有一個檔，怎麼登記工作寫在 `app/AGENTS.md` 那一節。ADR 不需要新的（m3-decisions §8.25）。

### 8.4 設定

- M3 只加電台狀態間隔（§3.3）。排行與匯入歌單的間隔跟 M4 的工作一起加：現在加就是沒有讀者的欄位（M2 design §1.2 原本寫三組都在 M3，§16 第 5 條）。

## 9. 電台與直播（決定 3，ADR 0018 §決定 9、0031）

### 9.1 電台清單

- `lib/radio/radio_service.dart`：清單（依 `sort_order`）、新增、刪除、排序（拖曳後整批重寫 `sort_order`）、`watch`。
- **以網址新增**：輸入網址 → 依序問每個已啟用、宣告 `live` 的插件 `liveRoomFromUrl` → 第一個回 `roomId` 的插件 → `liveStatus` 取標題、主播、封面與狀態 → 寫入。都回 `null` 時提示「無法辨識這個網址」；同一個（插件, 房間）已存在時提示「已在電台清單」。
- **加為電台**（搜尋頁直播間結果的選單）：直接以 `LiveRoom` 寫入。

### 9.2 狀態工作

- 每個宣告 `live` 且清單裡有電台的插件一個工作 `radio-status:<pluginId>`，間隔是「電台狀態刷新間隔」（預設 5 分）；工作依序對該插件的每個電台呼叫 `liveStatus`，成功就更新 `live_status`、`live_title`、`status_checked_at`。
- 單一電台查詢失敗：那一列在記憶體標「查詢失敗」（D10），其他繼續；整個工作仍算成功（避免一個壞房間讓整批退避）。全部失敗才算失敗、進退避。
- **收聽中的直播間資訊**：`playLive` 時登記 `live-info`，固定 1 分鐘（ADR 0017 §決定 1），更新播放頁的標題、人數；停止直播時移除。
- 電台頁顯示：開播中、未開播、查詢失敗、還沒查過四種狀態；「查詢失敗」不當成未開播。

### 9.3 電台頁與導覽

- **導覽**：搜尋｜歷史｜電台｜設定（§16 第 8 條；舊版電台排在設定之前）。手機底部導覽變 4 項；M4 加音樂庫、首頁時再重排。
- **頁面**：清單（封面、標題、主播、狀態標記），點一下 `playLive`；拖曳把手排序；選單「刪除」；工具列「以網址新增」「刷新」（`runNow`）。空清單時說明怎麼新增（搜尋頁的直播間模式、以網址新增）。
- 離線：清單照常顯示存的狀態；刷新與播放失敗時顯示離線空狀態（ADR 0016 §決定 7）。
- 移除或停用插件的電台列保留並標示（§7.3、§16 第 10 條）。

### 9.4 直播播放（ADR 0018 §決定 9）

- **`PlaybackController.playLive(LiveTarget)`**：`QueueModel` 進 `live` 模式，記下佇列快照（同臨時播放：佇列目前位置、播放位置、是否在播）；經 `PlaybackSession` 開 `resolveLive` 的流；不排前瞻。
- **停止**：直播頁的「停止」或在佇列點選任一首 → 回到快照的佇列（照臨時播放回佇列的規則，不倒退）。**暫停＝停止串流**（舊版；直播沒有可回頭的位置），再按播放重新 `resolveLive`。
- **提前結束**（後端 `completed` 或中斷）：先 `liveStatus`，是 `live` 才以 1／3／9 秒重連 3 次（§16 第 3 條；ADR 0018 §決定 9 原文 1／3／10 秒）；不是就停在「直播已結束」。`liveStatus` 拋錯時顯示「查詢失敗」並停下（D10）。
- **取消**：開直播時進行中的音樂解析結果被代際丟掉（§4.9）。
- **不持久化**：`player_state` 不寫 `live`；直播中關 App，重開時回到快照的佇列（同臨時播放，M2 design §7.7）。
- **系統媒體控制**：`NowPlaying` 帶直播標題與封面，沒有時長、不能 seek；上一首、下一首鍵停用。
- **播放頁的直播版**：`mode == live` 時播放頁換成直播版（封面、直播標題、主播、「直播中」標記、已收聽時間（位置 stream）、人數、停止鈕；沒有進度條、佇列分頁照常顯示原佇列）。播放列同樣沒有進度條。
- 閘門：控制器測試（進入記快照、停止回佇列、暫停是停止、提前結束先問狀態、`offline` 不重連、`liveStatus` 拋錯顯示查詢失敗、重連 1／3／9 秒共 3 次、開直播丟掉進行中的解析）；`RecoveryPolicy` 的直播分支；widget 測試（播放頁直播版、播放列沒有進度條）。

### 9.5 搜尋頁的直播間模式

- 目前選的插件宣告 `live` 時，搜尋框下多一組分段鈕「曲目｜直播間」；直播間模式下再多「全部｜開播中｜未開播」篩選（舊版 `LiveRoomFilter`）。
- 結果列：封面、標題、主播、狀態、人數；點一下 `playLive`；選單「加為電台」。
- 閘門：widget 測試（只有宣告 `live` 的插件出現分段鈕；篩選傳進 `liveSearch`；「加為電台」寫入）。

## 10. Mix（決定 4，ADR 0018 §決定 4、0031）

- **入口**：曲目選單（搜尋、歷史、佇列的 `TrackRowMenu`）的「開始 Mix」，只在該曲目的插件宣告 `mix` 時出現（宿主沒有 YouTube 分支）。
- **開始**：`mix({seed})` → 以回傳的曲目**取代整個佇列**、進 `mix` 模式、從第一首播（舊版，§16 第 9 條）。`player_state` 寫 `mode = mix` 與 `mix_*`。
- **規則照舊版**（`playback.md` §3.11）：
  - 禁止隨機（隨機鈕停用並附說明）；禁止加入佇列、下一首播放、打亂（選單項目停用）；
  - 清空佇列＝退出 Mix（回到 `queue` 模式、空佇列）；
  - 跳過走下一首（ADR 0018 §決定 7，與佇列相同）；
  - 臨時播放照常可用，結束回到 Mix 佇列。
- **補歌**（`lib/playback/mix_session.dart`）：每首開始時，若之後只剩 ≤ 1 首，就 `mix({mixId, cursor})`（`cursor` 為空時改以佇列最後一首當 `seed`，見 §4.5）；回來的曲目以曲目鍵去重（已在佇列的丟掉）後附加，更新 Mix 身分與 `mix_cursor`。同時只有一個補歌在跑；失敗或去重後一首都沒有時記進錯誤歷史、不提示，到下一首開始時再試（不會在同一首裡連續重試）。佇列播到底而補歌還在跑時，等它完成再決定往下或停。舊版的「試 10 次、每次 1 秒」不實作，續播的來源交給插件的 `cursor`。
- **修剪**：已播超過 100 首時刪最舊的已播項目（ADR 0018 §決定 4），修掉舊版 Mix 佇列只增不減。修剪後的位置位移照 M2 佇列的差量寫入。
- **重啟**：`mode = mix` 時恢復 Mix 模式、Mix 身分與 `mix_cursor`，照常補歌（`mix_cursor` 為空時同上換種子，M5 匯入的舊 Mix 也走這條）。
- **插件停用或移除**：Mix 照佇列處理（曲目標「音源未安裝」跳過），補歌停止。
- 閘門：`QueueModel` 的 Mix 修剪（剛好 100 不刪、101 刪最舊的已播、目前這首與未播的不動）、禁止的操作回傳拒絕、清空退出；`MixSession` 的補歌時機、去重、`cursor` 為空時換種子、一首都沒補到時同一首內不重試、同時只有一個；持久化與恢復（含 v12 migration）；選單只在宣告 `mix` 時出現（ADR 0018 §如何確認的 Mix 修剪）。

## 11. 分 P 與曲目詳細

### 11.1 B 站分 P（§8.5，ADR 0028）

- 搜尋結果列：插件宣告 `multiPart` 且 `partCount > 1` 時，尾端有展開鈕（舊版 `_PageTile`）。展開時呼叫 `multiPart`，列出分 P（「P2 分 P 標題」、時長）；每個分 P 是一首曲目，點一下臨時播放、選單照曲目列。
- 點影片本身：臨時播放第一個分 P（舊版先播原曲目再載入分 P；新版 `TrackSummary` 不帶 cid 時插件 `resolveStream` 本來就取第一 P，行為相同）。
- 影片的選單（加入佇列、下一首播放）：分 P 數 > 1 時套用到全部分 P（舊版：有多個分 P 時動作套用到全部）。
- 佇列、歷史、播放頁顯示「影片標題 · P2 分 P 標題」，以既有 `TrackKey.formatGroup` 分組。
- 閘門：widget 測試（展開只在宣告且 > 1 時出現、展開呼叫 `multiPart`、選單套用全部分 P）；契約案例 `multiPart`。

### 11.2 `trackDetail`（決定 5）

- 播放頁「詳細」分頁與右側面板的 `TrackDetails`（M2 決定 6 留給 M3）：插件宣告 `trackDetail` 時，在現有資料下方多顯示簡介、發佈時間、上傳者頭像、專輯、統計（依 `kind` 的圖示與翻譯）。
- 每首在第一次顯示詳細時呼叫一次，結果以曲目鍵放記憶體 LRU（32 筆），不持久化；失敗只在詳細區顯示「無法取得詳細資料」與重試，不跳提示。
- 三個插件各實作（B 站 `wbi/view`、YouTube `getInfo`、網易 `song/detail`）。
- 閘門：widget 測試（沒有宣告時只顯示現有資料、有宣告時顯示、失敗顯示重試）；三個插件的契約案例。

## 12. Debug 頁與開發者模式（ADR 0025）

### 12.1 開發者模式、「關於」、路由

- **「關於」**（§8.26）：設定頁的最後一個區塊（開發者模式下 Debug 在它之後），M3 只有版本列（版本、flavor）；ADR 0024 §決定 9 的其餘內容在 M9（§16 第 6 條）。
- **開啟**：版本列連點 7 次；第 2 次起提示「再點 n 次即可開啟開發者模式」，離開頁面計數歸零（Firefox `SecretDebugMenuTrigger`）。開啟時寫 `developer_mode = true`。
- **關閉**：Debug 頁「概覽」最上方的總開關；同一筆寫入 `developer_mode = false`、`log_level` 清空、`plugin_dev_folder` 清空，並卸載開發中的插件（恢復已安裝版）。
- **控制的東西**：設定頁的 Debug 入口、錯誤提示的「詳細」（§13）、log 層級可調到 debug、Debug 路由、插件開發工具。
- **路由閘門**：開發者模式關閉時 Debug 路由一律 redirect 回設定頁。
- **版面**：沿用設定頁的 list-detail（ADR 0024），八個區塊照 ADR 0025 §決定 2 的表；全部用 token 與 slang 字串。
- **版本的來源**：平台層讀 `package_info_plus`（§14），版本號來自 pubspec（發版時等於 release-please manifest，ADR 0022）。
- **概覽**：總開關、log 層級、版本／flavor／平台／資料目錄（顯示時以 `~` 代換家目錄，§12.4）、快取用量連結（到設定頁「網路」）、診斷包（§12.4，PR 15 加）。
- 閘門：ADR 0025 §如何確認的開發者模式三項（連點 7 次寫入、關閉清空 `logLevel` 與卸載、dev flavor 預設開）；widget 測試（關閉時直接進 Debug 路由被 redirect、設定頁入口只在開啟時）。

### 12.2 資料庫、重設資料與備份（§8.31，矛盾 1）

- **備份格式**：SQLite 的 `VACUUM INTO` 把資料庫複製到資料目錄的 `backups/fmp-<UTC 時間>.db`（SQLite 官方的線上備份做法）。憑證不在資料庫（ADR 0012），所以備份不含憑證，還原後要重新登入。M4 的 E16 匯出格式另定（§16 第 7 條）。
- **重設資料**（ADR 0025 §決定 9）：① 備份 ② 對話框列出備份路徑、二次確認 ③ 清空資料庫（刪檔重建）、`SecureStorage.deleteAll()`、WebView 全部資料、快取（`CacheStore.clear()`）④ 重啟 App。**備份失敗就不清空**。不動 log 檔（與已下載檔，M6）。
- **重啟**：Windows 以同一個執行檔重新啟動自己再結束（單一實例鎖先釋放）；Android 以 `SystemNavigator.pop` 後由使用者再開（Android 沒有正規的「重啟自己」，舊版也沒有）。對話框寫明 Android 要手動重開。
  - **Android 要確認重開時 `main()` 真的重跑**：`SystemNavigator.pop` 只結束 Activity；`AudioServiceActivity` 的 cached engine 或 audio_service 的前景服務可能讓 process 活著，使用者重開時 `main()` 不重跑，App 會拿著已被刪掉重建的資料庫與已清空的狀態繼續跑。PR 14 實測確認重設後重開，log 出現新的 `App started`。
  - 沒重跑時改成：先停掉 audio_service（結束前景服務與 media session），再結束 process。實作在 PR 14 決定，寫進 `app/AGENTS.md`（含為什麼不能只靠 `SystemNavigator.pop`）。
- **資料庫區塊**：
  - 唯讀瀏覽：`allTables` 與筆數；點進表 `select(table)` 每頁 50 列；每個值經遮蔽函式；`plugin_storage` 的值整欄遮蔽。
  - 「檢查」只報告：`PRAGMA integrity_check`、`PRAGMA foreign_key_check`、孤兒曲目數（M2 的 `deleteOrphans` 同一個查詢的計數版）；「檔案遺失的下載數」在 M6。有問題時提供「從備份還原」與「重設資料」。
  - **從備份還原**：列出 `backups/` 的檔案（時間、大小）→ 選一個 → 確認 → 關閉資料庫、以該檔取代 `fmp.db`（原檔先改名留著）→ 重啟。
- 閘門：重設在備份失敗時不清空、成功時資料庫是空的且 `SecureStorage` 為空、log 檔還在；`VACUUM INTO` 的備份可以開啟且筆數相同；資料檢查（關外鍵寫一筆違規列再開，報告列出它；乾淨的資料庫無問題）；瀏覽的值經遮蔽（假 cookie 出現在 `plugin_storage` 時顯示 `***`）。

### 12.3 Log、網路、播放狀態（ADR 0025 §決定 3–5）

- **Log 與錯誤歷史**：預設看這次執行的記憶體歷史；「含之前的紀錄」在 isolate 解析 log 檔（最多 6 MB，壞行略過，M1 的讀回函式）；篩選層級、tag、文字；「只看錯誤」＝錯誤歷史，點一筆開 §13 的詳細頁；動作：複製已篩選、匯出 log 檔（走 §12.4 的存檔與分享）、「清除 log」同時清記憶體與檔案（排進 `LogFile` 的寫入佇列，同 M2 PR 6 的做法）。
- **網路**：資料來源是 tag `network` 的記錄（M1、M2 已寫，含 `client`）；清單欄位時間、方法、主機、路徑、狀態、耗時、大小、音源；篩選音源、狀態碼類別（2xx／3xx／4xx／5xx／失敗）、文字；單筆詳細含遮過的 query、錯誤類型、以 `networkRecordId` 對應的錯誤紀錄。
- **播放狀態**（§8.30）：唯讀的 `PlaybackDiagnostics` 快照（`lib/playback/playback_diagnostics.dart`），由 `PlaybackSession` 提供：選中候選的容器、編碼、位元率、來源類型（網路／asset）；後端名稱；輸出裝置；`Retrying` 時的下次重試時間（`Retrying.delay` 加開始時間）；加上控制器既有的狀態與 `QueueState`（總數、目前索引、前後各 5 首、隨機與循環）。sealed `PlaybackState` 的形狀不動，`QueueState` 照舊分開（ADR 0018 §決定 2）。位置每秒刷新（UI 讀進度 stream，不開計時器）。「複製快照」輸出 JSON，網址經遮蔽。
- 閘門：網路篩選（依音源與狀態碼類別）；log 清除後記憶體與檔案都空；播放快照的 JSON 不含假簽名網址（ADR 0025 §如何確認的遮蔽）。

### 12.4 診斷包（ADR 0025 §決定 10、ADR 0011 §決定 6，§8.28）

- **內容**：`diagnostics.txt`、`diagnostics.json`（版本、flavor、平台與版本、語系、各插件的 id／版本／啟用、各音源是否登入（是／否）、非敏感設定摘要（各組欄位，`plugin_dev_folder` 只寫有無））、目前的 log 檔。產生時組裝一次。不含帳號名稱、硬體識別、歌單內容。
- **資料目錄的使用者名稱**（M1 待辦 13）：遮蔽函式把使用者家目錄登記為已知值、換成 `~`（Finamp 的已知值替換，ADR 0011 §決定 3）；`App started` 的 `dataDirectory` 因此在 log 檔與診斷包都是 `~\…`。`Redactor` 現在只有換成 `***` 的 `registerSecret`，要加一個帶替換字串的登記；登記要在 `main()` 寫 `App started` 之前。
- **動作**：「複製」（純文字摘要）；「存檔」：`fmp-diagnostics-<時間>.zip`，以 `file_picker` 13.1.0 的 `saveFile(bytes:)`（桌面是存檔對話框；Android 走 SAF。`file_picker` 取代 ADR 0025 寫的 `file_selector`，矛盾 2）；「分享」：`share_plus` 13.3.1，只在宣告 `PlatformCapabilities.shareFiles` 的平台顯示（Android、Windows 都支援分享檔案，pub.dev 的平台表；Windows 的最低版本沒有寫明，PR 15 實機確認）。
- **zip**：`archive` 4.3.0（舊版用 4.2），在 isolate 壓。
- **第一次匯出**提醒「送出前請檢查」，與 GitHub 回報共用 `report_reminder_dismissed`。
- **暫存**：分享用的 zip 寫在快取目錄，分享後刪；殘留的由啟動維護清單的新項目「診斷包暫存」清掉（M2 design §6 留的登記點）。
- 閘門：診斷包不含假憑證、假簽名網址、帳號名稱、家目錄的使用者名稱（ADR 0011 的遮蔽測試加這四種）；zip 可以解開、三個檔都在；未宣告 `shareFiles` 的平台不顯示「分享」（widget）；啟動維護清單刪掉殘留的暫存 zip。

### 12.5 健康檢查與插件開發工具（ADR 0015 §決定 7、ADR 0025 §決定 6–7，§8.27）

- **健康檢查**：對已安裝且啟用的插件，以真實連線跑它的檢查案例；手動觸發「全部」或單一插件，一次跑一個插件。
  - 案例來源：從 index 安裝的插件用 `installed_plugins.checks_json`；開發中的插件讀資料夾的 `checks.json`；從檔案或網址安裝的顯示「沒有檢查案例」（§16 第 12 條）。
  - 結果：每案例通過／失敗、耗時、`AppError` 類別；`requiresLogin` 而未登入的標「略過」，已登入的用已存憑證跑（§4.8）。結果以 tag `health` 經 log 門面寫入，不另存。
  - `checks.json` 的解析（`test/plugins/contract/checks.dart` 的 `parseChecks`、`checkShapes`）與契約執行器的「案例期望」判斷（成功筆數、非空欄位、錯誤類別）從 `test/plugins/contract/` 移到 `lib/plugins/health/`：健康檢查要讀 `installed_plugins.checks_json`，解析目前只在 `test/`。契約測試改為引用它，判斷只有一份；`type_definitions_test.dart` 比對 `checkShapes` 的位置跟著改。
- **adapter 移進 `lib/core/network/fixture_adapters.dart`**（矛盾 10，M1 待辦 11）：錄製與重播的 `HttpClientAdapter` 從 `test/plugins/contract/fixture_adapters.dart` 移來，格式不變；它依賴的 `fixture.dart`（`FmpFixture` 的解析與 `fixtureShapes`）一起移到 `lib/core/network/`。`test/plugins/contract/` 改為引用它們。`restrictedImports` 只准 `lib/plugins/dev/` import（§2.2）。ADR 0015 §決定 6 的更正加一行。
  - `fixture.dart` 用 `lib/plugins/json_shape.dart` 的 `JsonShape`／`JsonFields`，而 `lib/core/` 不准 import `lib/plugins/`（`forbiddenLayerImports`）：`json_shape.dart` 先移到 `lib/core/`（它不依賴插件的任何東西），`lib/plugins/` 改 import 新位置。adapter 不能反過來放 `lib/plugins/dev/`：`dio` 只准在 `lib/core/network/`（`externalPackageOwners`）。
  - `SourceHttpClientFactory` 只接受一個外部給的 `HttpClientAdapter`，不 import `fixture_adapters.dart`；由 `lib/plugins/dev/` 建好 adapter 傳進去。
- **插件開發**（只在宣告 `pluginDevTools` 的平台：Windows 真、Android 假）：
  - 「選擇資料夾」以 `file_picker` 的 `getDirectoryPath`，路徑存 `plugin_dev_folder`；資料夾裡的插件目錄（`.js` 加 `checks.json` 加 `fixtures/`，和契約執行器同一格式）標「開發中」，本次執行取代同 id 的已安裝插件，卸載後恢復已安裝版。
  - **`installed_plugins` 要有一列**：`plugin_storage` 的外鍵指向它（M1），沒有這一列插件的 `fmp.storage.set` 寫不進去。載入開發資料夾的插件時，該 id 沒有已安裝列就補一列（manifest 與腳本取自資料夾、來源標開發資料夾、`source_index_url` 空、`enabled` 為真）；已有同 id 的已安裝列就沿用那一列，**不覆寫它的 manifest 與腳本**（卸載後要恢復的就是它），storage 也共用。移除開發資料夾（卸載、關閉開發者模式、換資料夾）時，只刪開發工具自己補的列，隨 `plugin_storage` cascade 清掉；沿用的已安裝列不動。來源標記的存放方式（記憶體集合或 `installed_plugins` 的欄位，後者要 migration）與 App 在載入中途結束後殘留列的清理，PR 16 決定。
  - 「重新載入」：拆掉該插件的 runtime 再重建（LX Music「切換＝銷毀重建」）。
  - 每插件的模式「真實｜錄製｜重播」：`SourceHttpClientFactory` 依模式掛 `fixture_adapters` 的錄製或重播 adapter，切換時重建該插件的 client。錄製的 fixture 經 `Redactor` 寫進資料夾的 `fixtures/<能力>/`（與命令列錄製同一個函式）。
  - 案例單跑或全跑，顯示已遮蔽的回傳值與錯誤；log 篩成該插件的 tag。
  - **以 App 內登入錄 fixture**（ADR 0015 §決定 7）：真實或錄製模式下，帶憑證的請求照常注入；寫檔前遮蔽，`fixture_scan_test.dart` 守提交進 `fmp-plugins` 的檔案。
- **Android 不做 App 內重播**：實機驗證照 ADR 0027 用測試插件 `fmp-test` 重播；改到插件時用最少的真實連線。YouTube、網易的 fixture 在 Windows 錄進插件資料夾、提交到 `fmp-plugins`。M3 的請求都是 `userPreference`，匿名就能錄，命令列錄製也可以（ADR 0015 §決定 7 的更正）。
- 閘門：健康檢查的「略過」、一次一個插件、結果寫 `health` tag；重播 adapter 在 `lib/` 後契約測試照常（M1 的 `contract_runner_test.dart` 全綠）；錄製經遮蔽（假上游的假憑證不出現在寫出的檔）；未宣告 `pluginDevTools` 的平台不顯示插件開發區塊（widget）；關閉開發者模式時開發資料夾卸載、已安裝版恢復。

## 13. 錯誤詳細頁與回報（ADR 0023 §決定 4，§8.29）

- **`ErrorReport`**（`lib/core/errors/error_report.dart`）：錯誤發生時組裝一次並經遮蔽：錯誤類型與原因、插件 id 與版本、使用者動作（呼叫端給的 i18n key）、請求摘要（以 `networkRecordId` 從記憶體歷史找網路紀錄：方法、已遮蔽網址、狀態碼、耗時）、stack trace、App 版本與 flavor、系統與版本、ISO 8601 時間。`Log.report` 寫錯誤歷史時一併存它的 id，Debug 頁的錯誤歷史以同一份開詳細頁。
- **誰看得到**：開發者模式下每則錯誤提示附「詳細」；一般使用者只有 `Unsupported`、`UnexpectedError` 附「回報」，開同一頁。dev flavor 一樣（開發者模式預設開）。
- **詳細頁**：全螢幕路由，文字可選取；「複製」（Markdown）；「在 GitHub 回報」：先複製，再以 `url_launcher` 6.3.3 開 `https://github.com/1morr/FMP/issues/new?template=bug_report.yml`（`endpoints.dart`）。**內容不放進網址**。第一次使用提醒「repo 是公開的，送出前請檢查內容」，可勾「不再提醒」（`report_reminder_dismissed`）。
- **回報目標**一律是 `1morr/FMP`（NewPipe 單一目標）。報告含插件 id 與版本，插件的問題由維護者以 GitHub 的 Transfer issue 移到 `fmp-plugins`（同一擁有者）。
- **`.github/ISSUE_TEMPLATE/bug_report.yml`**：繁中（根 `AGENTS.md` § Issues）；欄位：問題描述、重現步驟、錯誤報告（貼上「複製」的內容，`render: markdown`）、App 版本、平台；標籤 `bug`。
- 平台層 `lib/platform/url_opener/`：`UrlOpener.open(Uri)`，宣告 `PlatformCapabilities.urlOpener`（Android、Windows 真）；沒有時「在 GitHub 回報」只複製並顯示網址。
- 閘門（ADR 0023 §如何確認）：開發者模式與一般使用者的按鈕；`ErrorReport` 經遮蔽（假 cookie、token、簽名網址不出現在 Markdown）；開的 GitHub 網址等於 `endpoints.dart` 的常數、不含報告內容；詳細頁加進 `toast_layering_test.dart` 的路由案例（全螢幕頁上提示可見）。

## 14. 新增的依賴

2026-10-08 pub.dev API 的 `latest`；加依賴時再核對一次，裝當前 stable。

| 套件 | 版本 | 用途 | 擁有者 | PR |
|---|---|---|---|---|
| `flutter_secure_storage` | 11.2.0 | `CredentialStore`（ADR 0012 §決定 3） | `lib/platform/` | 7 |
| `qr_flutter` | 4.1.0 | QR 登入畫面 | `lib/ui/accounts` | 8 |
| `flutter_inappwebview` | 6.2.0-beta.3 | App 內網頁登入（ADR 0029 §決定 9；用 beta 的理由見 ADR 0029） | `lib/platform/` | 9 |
| `pub_semver` | 2.2.1 | 插件版本比對 | `lib/plugins/repository` | 4 |
| `file_picker` | 13.1.0 | 從檔案安裝插件、選開發資料夾、存診斷包（ADR 0009 §決定 6） | `lib/platform/` | 5 |
| `url_launcher` | 6.3.3 | 「在 GitHub 回報」 | `lib/platform/` | 13 |
| `archive` | 4.3.0 | 診斷包 zip | `lib/app/diagnostics` | 15 |
| `share_plus` | 13.3.1 | 分享診斷包 | `lib/platform/` | 15 |
| `package_info_plus` | 10.2.2 | 「關於」的版本列、`ErrorReport` 與診斷包的 App 版本（`lib/` 現在沒有任何讀版本的地方） | `lib/platform/`（M1 已列入 `platformPackages`） | 11 |

- 沒有選的：`file_selector`（ADR 0025 原寫，改用 ADR 0009 已定的 `file_picker`，矛盾 2）；`webview_flutter` 4.14.1（沒有 Windows）、`webview_windows` 0.4.0（2024-02，只有 Windows）、`desktop_webview_window` 0.3.0（獨立視窗，取 cookie 的能力沒查到）；`pretty_qr_code` 3.6.0（備案）。
- `flutter_inappwebview`：R1 實測 6.1.5 在 AGP 9.1.0 建不起來（`proguard-android.txt`），6.2.0-beta.3 可以；擁有者 2026-10-08 決定用 beta.3，6.2.0 出 stable 就換。從 beta 退回 6.1.5 時要連 `pubspec.lock` 一起還原（lockfile 會留著 beta 的 `_platform_interface`）。
- 加了原生插件的 PR（7、9、11、13、15，以及 5 的 `file_picker`）照 M2 的做法保留真正新增的 plugin registrant，並以 `zipalign -c -P 16` 確認 Android 新增的原生庫是 16KB 對齊（ADR 0010 §後果）。

## 15. 文件更正

只加一行補充或更正，不改決定（根 `AGENTS.md` § Decisions）。**擁有者核准本設計後，PR 0 一次加**（標「各 PR」的在用到它的 PR 加）；本規劃階段不動既有 ADR。

| 文件 | 更正 | 何時 |
|---|---|---|
| ADR 0012 §決定 1 | 補充（M3）：匿名 cookie 由插件存在自己的 storage（`plugin_storage` 表）；登入後的 Cookie 與插件自己送的同名 cookie 以憑證為準合併；憑證的 cookie 不經 cookie jar（登入時不存、送出時跳過憑證的名稱），所以 `auth: never` 與開關關閉時不帶（ADR 0029）（矛盾 6，§6.3） | PR 0 |
| ADR 0012 §決定 5 | 補充（M3）：「`QueuedInterceptor` 單飛」由 ADR 0029 細化：判定在插件內，單飛刷新與重送做在插件呼叫層，重跑整個插件呼叫（§6.5，§16 第 1 條） | PR 0 |
| ADR 0013 §決定 4 | 補充（M3）：音源以 `HttpRequest.idempotent` 標語意冪等的 POST（ADR 0028） | PR 0 |
| ADR 0014 §決定 5 | 補充（M3）：「發佈」指 `app/` 第一個 prod 版本對外發佈（M9 切換）；在那之前 v1 可加選填欄位與匯出，`fmp-plugins` 同一輪跟上（矛盾 11） | PR 0 |
| ADR 0015 §決定 6 | 更正（M3）：錄製與重播的 adapter 與 fixture 格式的解析移到 `lib/core/network/`、`checks.json` 的解析與案例期望移到 `lib/plugins/health/`（App 內開發工具與健康檢查使用），`app/test/plugins/contract/` 改為引用它們，格式不變；上一則更正的「放進 `lib/` 違反分層」只指 QuickJS 與零聯網的測試準備（矛盾 10） | PR 16 |
| ADR 0018 §決定 6 | 更正（M3）：被取代的請求不經宿主取消網路工作；控制器以代際檢查丟掉結果、不再發解析，已送出的 HTTP 讓它跑完（ADR 0028）。§如何確認的「開直播取消進行中的音樂請求」改為「開直播後，進行中的音樂解析結果不播出、不再發解析」（§4.9，§16 第 2 條） | PR 0 |
| ADR 0018 §決定 9 | 更正（M3）：「開直播必然取消進行中的音樂請求」照 §決定 6 的更正，指進行中的音樂解析結果被丟掉、不播出、不再發解析；直播重連改用 §決定 7 的 1／3／9 秒；1／3／10 是舊版 `RadioReconnectConfig` 的值，沒有刻意區分（矛盾 7，§4.9，§16 第 2、3 條） | PR 0 |
| ADR 0024 §決定 6 | 補充（M3）：設定頁除 ADR 0011 的設定組外，另有「帳號」（第一個）、「插件」、「關於」，開發者模式下最後一個是 Debug 頁入口；這些不是設定表（矛盾 12） | PR 0 |
| ADR 0025 §決定 7、10 | 更正（M3）：`file_selector.getDirectoryPath`／`getSaveLocation` 改用 ADR 0009 §決定 6 的 `file_picker`（13.1.0）的 `getDirectoryPath`、`saveFile`；「file_picker 沒有 SAF」不成立（13.x 有 Android SAF 選項），Android 插件開發仍另立 ADR（矛盾 2） | PR 0 |
| ADR 0025 §決定 9 | 更正（M3）：自動備份＝以 SQLite `VACUUM INTO` 把資料庫複製到 `backups/fmp-<時間>.db`；「從備份還原」＝換回該檔並重啟。憑證不在資料庫，還原後要重新登入。M4 的 E16 匯出格式另定（矛盾 1，§16 第 7 條） | PR 0 |
| ADR 0026 §決定 3 | 修訂（2026-10-08，M3 規劃時擁有者決定）：M3 拆成 M3a「三音源與帳號」與 M3b「開發工具、排程器、電台、Mix、分 P」，M4 依賴 M3b；明細見 `milestones.md` | PR 0 |
| ADR 0029 | 已依 R1 定案 App 內網頁登入的部分（套件、`login.webView` 欄位、UA 歸平台層、`loginWebView` 能力），狀態於 2026-10-08 核准時改「已採納」 | 已完成（R1 後、PR 0） |
| `milestones.md` § M3 | 拆成 M3a、M3b 兩節與兩列（依賴：M3a←M2、M3b←M3a、M4←M3b）；範圍加「設定『關於』區塊的版本列（開發者模式入口；其餘內容 M9）」（矛盾 4）；驗收照 `prd.md`（加 ADR 測試的項目，矛盾 13） | PR 0 |
| `09-26-fmp-rewrite/task.json` | 子任務清單加本任務 | 已在本規劃的 commit `f7736306` 加入 |
| `app/AGENTS.md` | § 網路「目前（M2）的認證來源是 `NoCredentials`」、§ 插件的 `checks.json`「只收兩個能力」、§ 資料層、§ 平台層、§ Lint 隨各 PR 改寫；加 § 排程器、§ 帳號、§ 電台 | 各 PR |
| `.trellis/spec/app/plugins/index.md` | 「寫一個插件」加 `login`、`live`、`mix`、`multiPart`、`trackDetail` 的寫法與 `requiresLogin` | 各 PR |
| `fmp-plugins/README.md` | 「目前沒有發佈版本」改寫成 index 與 CI 的說明 | PR 3 |

## 16. 需要擁有者明確確認的決定

這些改動到 ADR 的文字、舊版行為，或是本設計才提出的產品行為（標「新」），核准本設計時請逐條確認。前七條來自 `m3-decisions.md` 乙類標「列入確認清單」者。

**2026-10-08 擁有者確認：14 條全部照建議。**

1. **憑證失效的單飛刷新做在插件呼叫層**，重跑整個插件呼叫，不在 dio 的 `QueuedInterceptor`（判定在 JS 內、dio 看不到）；ADR 0012 §決定 5 加一行。建議：照做（§6.5）。
2. **被取代的請求不取消已送出的 HTTP**，由控制器以代際丟掉結果；ADR 0018 §決定 6 更正，「開直播取消音樂請求」的測試改成「結果不播出、不再解析」。建議：照做（§4.9；要真的取消就得讓每個插件手動傳呼叫 id）。
3. **直播重連改成 1／3／9 秒**（與音樂重試同一份），ADR 0018 §決定 9 的 1／3／10 秒更正。建議：照做（舊版常數沒有刻意區分）。
4. **登入方式**：B 站、網易只有 QR；YouTube 是 App 內網頁登入加貼上 cookie（R1 不通過時只有貼上 cookie）。拿掉舊版 B 站的 WebView 分頁與 Android 網易的 WebView。建議：照做（ADR 0012「以 QR 為主」；少一個 WebView 流程要維護）。
5. **排行與匯入歌單的刷新間隔設定延到 M4**，M3 只加電台狀態間隔（與 M2 design §1.2「三組都在 M3」不同）。建議：照做（沒有讀者的欄位）。
6. **「關於」在 M3 只有版本列**（版本、flavor，連點 7 次的入口），ADR 0024 §決定 9 的其餘內容在 M9；`milestones.md` 加一行。建議：照做。
7. **重設資料的備份是 `VACUUM INTO` 的資料庫檔副本**，「從備份還原」是換回並重啟；備份不含憑證，還原後要重新登入；ADR 0025 §決定 9 更正。建議：照做（ADR 0010 沒有定義備份格式，E16 在 M4）。
8. **（新）導覽順序：搜尋｜歷史｜電台｜設定**，手機底部導覽 4 項。建議：照做（舊版電台排在設定之前；M4 加音樂庫、首頁時再整體重排）。
9. **（新）開始 Mix 以 Mix 的曲目取代整個佇列**，原佇列不另存（舊版行為，決定 4「規則照舊版」的延伸）。建議：照舊版；若覺得太容易誤觸，替代案是佇列非空時先確認一次。
10. **（新）移除或停用插件時，它的電台保留並標「音源未安裝／已停用」**，不刪（與曲目一致，ADR 0014 §決定 8）。建議：照做；重新安裝後自動恢復。
11. **（新）插件更新若能力或會連的網域比目前多，先列出新增的部分再確認**；「全部更新」對這種插件逐個詢問。建議：照做（安裝前確認的延伸；Chrome 擴充功能與 Android 權限變更的慣例）。
12. **（新）健康檢查的案例在從 index 安裝時一併下載保存**（index 多 `checksUrl`、`checksSha256` 兩欄）；從檔案或網址安裝的插件沒有健康檢查，顯示「沒有檢查案例」。建議：照做（安裝單位仍是單一 `.js`，ADR 0014 的補充不變）。
13. **（新）`trackDetail` 不含熱門評論**（舊版詳細面板有）。建議：M3 不做；之後要加是 v1 的選填欄位，凍結前都能加。
14. **（新）網易的 `X-Real-IP`**：PR 2 先以匿名真實連線測「不帶」與「帶」；不帶也能搜尋與取流就不送；需要時只在必要的請求送，並寫進插件 README。建議：照做（舊版 B3 對寫入請求一律偽造固定 IP）。

## 17. 回滾

- 每個 PR 獨立合併；只動 `app/`、`docs/`、`.trellis/`、`.github/ISSUE_TEMPLATE/`、`.claude/skills/verify-on-device/`，以及 `fmp-plugins` repo。舊專案、`release.yml`、`ci.yml` 不動。
- **schema 變更**：App 還沒發版，revert 一個加表的 PR 等於回到上一版快照；dev 資料庫已升級的本機刪掉 dev 資料目錄重來（`app/AGENTS.md` § 資料目錄）。
- **憑證**：在 secure storage，不在資料庫；revert PR 7 之後殘留的 secure storage 項目沒有讀者，重設 dev 資料目錄時以 `SecureStorage.deleteAll()` 的開發入口清掉（或 Windows 刪 application support 下的 `.secure` 檔、Android 解除安裝 dev）。
- **WebView（PR 9）**：單獨 revert 後 YouTube 只剩貼上 cookie；manifest 的 `webView` 方法因平台沒有能力而不顯示，插件不必改。
- **fmp-plugins**：在該 repo 單獨 revert；index 以腳本重產。宿主 API 只加選填欄位，FMP 先 revert 時新插件的新匯出不被呼叫（能力與匯出一致的檢查只看 FMP 認得的能力名稱：revert 宿主的 `login` 時，宣告 `login` 的插件會被拒載，所以 fmp-plugins 要同步 revert 或 FMP 不 revert 到 PR 8 之前）。
- **排程器（PR 17）**：revert 後電台狀態只在手動刷新時更新（PR 18 若已合併要一起 revert）。
- **M3a 與 M3b 的界線**：M3a 驗收後才開 M3b 的 PR；M3b 整個不做時 M3a 仍是可交付的一半（三音源、帳號）。
