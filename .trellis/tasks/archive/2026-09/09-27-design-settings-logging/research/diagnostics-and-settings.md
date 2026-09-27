# 研究：診斷包內容、設定分組與儲存

範圍對應 task brief 項目 3、5。規則：版本 / 平台 / 維護狀態一律附 URL；查不到寫「查不到」；推測寫「推測」。全文繁體中文，程式識別碼保留原文。

---

## 3. 診斷包（diagnostic bundle）內容調查

調查對象：Spotube、Finamp、Jellyfin 系列 client、NewPipe。四者皆為開源 Flutter/Kotlin 媒體類 app，與 FMP 定位相近，適合作為「診斷包該裝什麼」的實例參照。

### 3.1 NewPipe（最完整、最適合當結構範本）

Source: https://raw.githubusercontent.com/TeamNewPipe/NewPipe/dev/app/src/main/java/org/schabi/newpipe/error/ErrorActivity.kt

NewPipe 的錯誤回報畫面（`ErrorActivity`）用**同一組欄位**同時產出三種格式：畫面上顯示的面板、可分享的 Markdown、以及 JSON——三種格式共用一份資料模型，這件事本身就是一個值得抄的設計（避免「畫面顯示的」和「匯出檔案裡的」欄位兜不起來）。欄位清單：

- `user_action`：使用者當下在做什麼操作觸發了這個錯誤（例如「正在播放串流」）
- `request`：觸發錯誤的請求描述
- `content_language` / `content_country`：使用者設定的內容語言/地區
- `app_language`：app UI 語言
- `service`：來源服務名稱（對應 FMP 就是 bilibili/youtube/netease）
- `package`：app 的 package name
- `version`：app 版本號
- `os`：作業系統字串
- 時間戳：ISO-8601 格式
- `exceptions`：例外陣列（可能不只一個）
- `user_comment`：使用者在送出回報前可自行填寫的說明文字

**明確排除**：裝置型號、硬體資訊——NewPipe 刻意不收集這些。

**與 FMP 遮罩需求的關聯**：`request` 欄位若是 FMP 場景，就是「觸發錯誤的那個 HTTP 請求」，必須經過第一份文件（`logging-and-redaction.md`）第 2 節的同一個遮罩函式再放進診斷包——這正是 owner 要求「Toast、Debug 頁、診斷包、logs 走同一個遮罩函式」的具體落地點之一：診斷包的 `request` 欄位如果繞過遮罩直接塞原始 `RequestOptions.toString()`，就是一個獨立於 log 檔案之外的第二個洩漏出口。

### 3.2 Finamp（提供遮罩－匯出的具體管線範例）

Sources:
- https://raw.githubusercontent.com/finamp-app/finamp/legacy/lib/services/finamp_logs_helper.dart
- https://raw.githubusercontent.com/finamp-app/finamp/legacy/lib/services/censored_log.dart

Finamp 沒有 NewPipe 那種多欄位結構化診斷包，做法更單純：一份「已遮罩的純文字 log」。管線是：

1. 記憶體中維護 `List<LogRecord> logs`，上限 1000 筆，超過就丟掉最舊的（`addLog` 方法內邏輯）。
2. `getSanitisedLogs()` 逐筆取 `log.censoredMessage`（`censored_log.dart` 定義的 extension，內含本文件姊妹篇第 2.1 節描述的「已知值替換」遮罩），組成一個純文字 `StringBuffer`。**直接讀原始碼確認：這個函式本身不附加任何 metadata header（裝置資訊/版本號/時間戳）——只有逐行遮罩後的訊息**，本輪之前的一份基於間接 WebSearch 推論的筆記主張這裡有 metadata header，經直接讀原始碼後**予以撤回**：以本次直接讀取的原始碼為準，不採用先前間接來源的說法。
3. `shareLogs()` 把上述字串寫進暫存檔 `finamp-logs.txt`，用 `Share.shareXFiles` 分享出去，分享完刪除暫存檔。
4. `copyLogs()` 提供另一條路徑：直接複製到剪貼簿（`FlutterClipboard.copy`），不經過檔案。

這個管線印證的設計原則：**遮罩必須在「組字串」那一步完成，而不是在「分享/匯出」那一步**——`shareLogs()`/`copyLogs()` 兩個不同出口都呼叫同一個已經遮罩過的 `getSanitisedLogs()`，而不是各自兜一份字串再各自遮罩，避免兩個出口的遮罩邏輯漏同步。

### 3.3 Spotube

Source: 前次研究已確認 Spotube 有「Logs 頁面」與 clipboard 複製（未附出處 URL，屬於前次研究成果，本輪未重新查證，若要在設計文件中引用需要重新取得原始碼路徑確認；本輪聚焦在其設定/資料庫遷移，見下方第 5 節）。屬於三者中最簡化的基準線：僅「看 log + 複製」，沒有結構化診斷包也沒有已知的遮罩管線說明。**此段落標記為推測/待補證據**，不建議直接引用其遮罩實作細節。

### 3.4 Jellyfin 系列 client

本輪與前次研究皆未能取得 Jellyfin 官方 client 或其他第三方 Jellyfin client（非 Finamp）的診斷包原始碼與具體欄位清單。**查不到**具體證據，故本文件不對 Jellyfin 系列做超出「以 Finamp 為代表」以外的單獨陳述（Finamp 本身就是一個 Jellyfin client，已在 3.2 節詳細覆蓋）。

### 3.5 對 FMP 診斷包設計的建議結構

綜合 NewPipe（欄位結構）與 Finamp（遮罩管線）：

- 欄位面向抄 NewPipe：app 版本、平台（OS 字串）、UI 語言、觸發時的使用者操作、觸發時的請求（經遮罩）、例外與 stack trace（經遮罩，見姊妹篇 2.2 節 stackTrace 需要遮罩的結論）、時間戳；明確**不收集**裝置型號等硬體資訊（跟隨 NewPipe 的隱私取捨，且 owner brief 未要求裝置資訊）。
- 遮罩時機抄 Finamp：診斷包產生函式呼叫同一個頂層遮罩函式組字串，Debug 頁的「匯出」按鈕只是把這個已經遮罩過的字串包成檔案分享，不在匯出那一步才做遮罩。
- 三種輸出格式（畫面顯示 / 匯出檔案 / 未來若要 JSON 上傳）共用同一份資料模型，抄 NewPipe 的架構，避免 owner 要求的「單一遮罩函式」被繞過在某個格式專屬的字串拼接路徑上。

---

## 5. 設定分組與儲存

比較對象：Spotube（Hive → Drift 遷移後的現況）、Finamp（現況仍為 Hive），並對照 FMP 自身 ADR 0010（drift 資料層）與 Riverpod 配對方式。

### 5.1 Spotube：Drift 單列寬表（single-row-multi-column）

證據取得方式：`gh api repos/KRTirtho/spotube/git/trees/master?recursive=true` 找到檔案路徑後，直接 fetch 兩支原始碼確認。

**Schema 設計**（`lib/models/database/tables/preferences.dart`）：一張 `PreferencesTable`，`id` 是唯一的 `IntColumn`（`autoIncrement()`），實際運作時**永遠只有 `id = 0` 這一列**，其餘每個設定項各佔一個獨立型別的欄位（`BoolColumn`/`TextColumn`/`IntColumn`），共約 24 個設定欄位：

| 欄位 | 型別 | 預設值/備註 |
|---|---|---|
| albumColorSync | Bool | true |
| amoledDarkTheme | Bool | false |
| checkUpdate | Bool | true |
| normalizeAudio | Bool | false |
| showSystemTrayIcon | Bool | false |
| systemTitleBar | Bool | false |
| skipNonMusic | Bool | false |
| closeBehavior | Text（`textEnum<CloseBehavior>()`） | close |
| accentColorScheme | Text（`text()`，自訂 `SpotubeColorConverter` 轉換） | "Slate:0xff64748b" |
| layoutMode | Text（`textEnum<LayoutMode>()`） | adaptive |
| locale | Text（JSON，`LocaleConverter` 轉換） | 系統語言/地區 |
| market | Text（`textEnum<Market>()`） | US |
| searchMode | Text（`textEnum<SearchMode>()`） | youtube |
| downloadLocation | Text | "" |
| localLibraryLocation | Text（`StringListConverter`） | "" |
| themeMode | Text（`textEnum<ThemeMode>()`） | system |
| audioSourceId | Text（nullable） | — |
| youtubeClientEngine | Text（`textEnum<YoutubeClientEngine>()`） | youtubeExplode（**注意**：程式碼裡另有 `defaults()` 靜態方法在非 iOS 平台改用 `newPipe`，與 SQL column default 不一致，屬於 Spotube 自己程式碼裡的一個小瑕疵，設計 FMP 時要避免「SQL 層預設值」與「Dart 層預設值」兩處各自維護造成分歧） |
| discordPresence | Bool | true |
| endlessPlayback | Bool | true |
| enableConnect | Bool | false |
| connectPort | Int | -1 |
| cacheMusic | Bool | true |

**Riverpod 配對方式**（`lib/provider/user_preferences/user_preferences_provider.dart`）：

- `build()` 同步先回傳 `PreferencesTable.defaults()`（讓 UI 立刻有值可用，不必等資料庫回應），接著非同步查 `id = 0` 那一列；查無則 insert 一列預設值（含平台相關的下載路徑計算）。
- 用 drift 的 `watchSingle()`（針對 `id = 0` 的 reactive stream）持續監聽，每次資料庫變動都會重新 emit，然後把 `state` 設成新值——**資料庫是唯一事實來源，provider 只是鏡射**。
- 寫入一律走同一個 `setData(PreferencesTableCompanion(...))` 方法，內部是 `db.update(db.preferencesTable)..where((t) => t.id.equals(0))` 再 `.write(companion)`；因為 drift 的 companion 只帶「有指定的欄位」，未指定的欄位不會被覆寫，所以每個設定項的 setter 只需要包一個單欄位的 companion。
- `reset()` 用 `query.replace(PreferencesTableCompanion.insert(id: const Value(0)))` 整列換成全新的 insert companion，所有欄位回到 table 預設值。
- 錯誤處理：訂閱 `watchSingle()` 的錯誤導到 `AppLogger.reportError`（Spotube 自己的錯誤上報，非本研究重點）。
- `ref.onDispose` 時取消 stream 訂閱。

### 5.2 Finamp：Hive 單一物件（現況仍非 drift/SQLite）

Sources:
- https://raw.githubusercontent.com/finamp-app/finamp/legacy/lib/services/finamp_settings_helper.dart
- https://raw.githubusercontent.com/finamp-app/finamp/legacy/lib/models/finamp_models.dart

**確認後的實際形狀**（先前一份基於記憶/未直接查證的筆記說法已由本輪直接讀取原始碼驗證，可視為確認而非推測）：

- `FinampSettings` 是一個 `@HiveType(typeId: 28)` 的**扁平物件**，`@HiveField(0)` 到 `@HiveField(26)`，共 27 個欄位，全部平鋪，沒有拆子物件分組（欄位清單含 `isOffline`/`shouldTranscode`/`transcodeBitrate`/`sleepTimerSeconds`/`bufferDurationSeconds` 等播放與同步相關設定，也有 3 個標記 deprecated 但仍保留欄位位置的舊設定，例如 `downloadLocations`→改用 `downloadLocationsMap`）。
- 儲存位置：單一 Hive box，box 名稱與 box 內的 key 都寫死是字串 `"FinampSettings"`（`Hive.box<FinampSettings>("FinampSettings").get("FinampSettings")!`），也就是整個設定物件只有唯一一筆記錄，用一個固定 key 存取——形狀上等同 Spotube drift 表的「永遠只有一列」，只是儲存引擎不同（Hive 物件序列化 vs. SQL 列）。
- 寫入模式是「整包讀出、改一個欄位、整包寫回」：`finampSettingsTemp = finampSettings; finampSettingsTemp.xxx = newValue; box.put("FinampSettings", finampSettingsTemp);`——與 drift 用 companion 只送「有變更的欄位」不同，Hive 這邊每次都要重新序列化整個物件。
- 對 UI 的曝光是 `ValueListenable<Box<FinampSettings>>`（Hive 原生機制），不是 Provider 或 Riverpod，UI 端要包 `ValueListenableBuilder`。
- 原始碼裡有作者自己留的風險註解，坦承 box 在啟動時才建立、目前用 `!` 強制解包「以後可能會出問題」，以及 `resetTabs()` 方法疑似忘記呼叫 `put()` 導致變更未落盤——這兩點是 Hive 單物件模式在缺乏型別安全交易保護下容易犯的錯誤類型，供 FMP 設計 drift 版本時引以為戒（drift 的 `update().write(companion)` 本身是一個明確的資料庫操作，比「改記憶體物件後要記得手動 put」更不容易漏寫）。

### 5.3 對 FMP 的建議（呼應 ADR 0010 drift 決定）

**單列多欄（single-row-multi-column）優於 key-value 表**，理由：

1. **兩個實例佐證同一個方向**：Spotube 選 drift 單列寬表；Finamp 雖然是 Hive，但本質也是「單一物件、扁平欄位」——兩個獨立專案在不同儲存引擎下收斂到同一種資料形狀（一筆記錄、每個設定各自一個具名欄位），沒有一個看到的先例是用 key-value table（`key TEXT, value TEXT` 那種形狀）存應用設定。
2. **型別安全**：drift 的具名欄位配合 `textEnum<T>()` 或自訂 `TypeConverter`，讓每個設定在 Dart 端直接是強型別（enum/bool/int），比 key-value 表「value 欄位存字串、讀出來自己 parse」更不容易在遷移或多處讀寫時出現型別不一致。
3. **Riverpod 配對模式現成可抄**：Spotube 的 `build()` 先給同步預設值、`watchSingle()` 做 reactive 更新、寫入統一走一個 `setData(companion)` 方法——這一整套模式可以直接對應到 FMP 的 `audioControllerProvider` 之類「資料庫是事實來源、provider 是鏡射」的既有慣例（`AGENTS.md` Boundaries 段落描述的 provider 分工原則），架構上一致。
4. **key-value 表的已知缺點**（本節為基於一般資料庫設計常識的推論，非本輪直接找到反例佐證，標記**推測**）：每加一個設定就要多一列，型別要另外編碼（例如塞 JSON 字串或加一個 type 欄位做 tagged union），migration 時「這個 key 的值格式要換」不像 drift 的 column migration 那樣有型別檢查與遷移工具鏈支援；查詢單一設定值也變成要 `WHERE key = ?` 而非直接讀欄位。

**建議的 FMP 分組方式**：跟隨 Spotube「一張 preferences 表 + 其他 per-domain 表分開」的思路（Spotube 除了 `preferences.dart` 外還有 `audio_player_state.dart`/`authentication.dart`/`history.dart` 等各自獨立的表），而不是把所有設定通通塞進一張表——這與 owner brief 提到的「settings grouping」直接對應：日誌/診斷相關設定（log level、輪替策略、是否啟用網路請求記錄）可以是 preferences 表裡的欄位，也可以視規模拆一張專屬的 `logging_settings` 表，這屬於設計階段（`design.md`）要決定的細節，本研究只確認「單列寬表」這個整體形狀的方向。

**待 owner 定案的開放問題**：
- preferences 表是否要為了未來擴充性拆成多張（例如 UI 設定 vs. 播放設定 vs. 日誌設定各一張表，皆單列），還是维持 Spotube 那種「一張大表」——drift 的 migration 機制對兩種形狀都支援,不構成技術障礙,純粹是模組化 vs. 簡單性的取捨,需要 owner 對照 ADR 0010 已定的方向決定。
- FMP 是否需要 Spotube 那種「先同步回傳預設值、非同步才 seed 資料庫」的模式，或者可以接受啟動時等資料庫 ready 才顯示設定頁——取決於 FMP 現有啟動流程的 UX 要求，非本研究範圍。
