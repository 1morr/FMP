# M5 設計

「研究 L」「研究 T」「研究 S」分別指 `research/legacy-sources.md`、`research/target-schema.md`、`research/secure-storage-compat.md`；「§11 第 n 條」指本檔的確認清單。

## 0. 研究的矛盾與處理

### 0.1 舊憑證不用 10.x 讀（ADR 0010 §決定 4、ADR 0012 §3）

ADR 0010 寫「用與舊版相同的 secure storage 版本（10.x）讀憑證」，但 `app/` 已是 `flutter_secure_storage` 11.2.0（ADR 0012 §3），同一個 App 不能解析兩個版本；兩版也共用同名的 MethodChannel（研究 S §3）。所以改成：

- **Android**：11.2.0 的預設加密（RSA-OAEP 包 AES-GCM、prefs 名 `FlutterSecureStorage`、無 namespace）與 10.3.1 相同（研究 S §1）。另開一個**不帶 `storageNamespace`**、`resetOnError: false`、`migrateOnAlgorithmChange: false` 的實例，讀的就是舊版那組檔案與 Keystore 金鑰；新版自己的實例帶 `storageNamespace: 'fmp'`，不會互相干擾。
  - 研究 L §6.2 說「11.x 讀不出沒跑過 10.x 的 Android 密文」，與上一條不矛盾：舊版在 v1.10.0（2026-09-09，commit `5efd6cde`）從 9.2.4 升到 10.3.1，10.x 第一次讀取時把 9.x 的 EncryptedSharedPreferences 搬到新格式。跑過 v1.10.0 以後版本的安裝讀得到；從 v1.9.x 以前直接跳到新 App 的讀不到，照 ADR 0010 標為「需要重新登入」。
  - 規劃時已在模擬器以一次性的測試 App（`dev.fmp.securestorageprobe`，不碰 `com.personal.fmp`）實測（`research/android-credentials-compat.md`）：
    - 10.3.1 寫四個鍵，升級成 11.2.0、以上述選項讀回，四個都相同；
    - 讀取前後 `shared_prefs` 的檔案與內容逐位元組相同；
    - 改壞一個鍵的密文：那個鍵拋 `AEADBadTagException`，其他三個照常讀到，XML 不變；
    - 同樣的壞鍵以預設選項（`resetOnError: true`）讀：那個鍵被靜默刪掉，回 `null`，與「從沒登入」分不出來。
    - 推論：
      - 只要有一個壞條目，`readAll()` 就整批拋錯，所以逐鍵 `read`；
      - `checkUpgradeStatus` 看不出單一條目壞掉，不拿它判斷。
    - 沒測到的：Keystore 金鑰遺失、PKCS1／CBC 的更舊格式、其他 API level。這些都落在「讀不出」，標為需要重新登入。
- **Windows**：實際的機制以磁碟實況與原始碼為準。擁有者的 `%APPDATA%\com.personal\fmp\` 只有 `flutter_secure_storage.dat`，沒有 `.secure` 檔；10.3.1 解析到的 `flutter_secure_storage_windows` 4.1.0 走 Dart FFI 的 `DpapiJsonFileMapStorage`：整份 JSON 以 DPAPI（`CryptProtectData`，無 entropy）加密存成單一檔案（`flutter_secure_storage_windows_ffi.dart:234-345`）。研究 L §6.3 讀到的 `.secure`＋AES-GCM＋Credential Manager 是 C++ 的向後相容路徑，只在 `useBackwardCompatibility` 為真時走。
  - 套件的 `load` 解不開或 JSON 壞掉時**整個檔刪掉**，沒有開關（同檔 :339-345）。所以匯入不經套件：在 `lib/platform/` 以 `win32` 的 `CryptUnprotectData` **唯讀**解開檔案（約 40 行；`win32` 已在 lock 檔裡，是 `flutter_secure_storage_windows` 的依賴），檔案路徑可以指定，dev 才能讀副本。
- 研究 S 也指出 ADR 0029 對 Windows 的描述（AES-GCM、金鑰在 Credential Manager）與原始碼不符，§10 更正。

### 0.2 `lib/legacy_import/` 被 lint 封住（研究 T §9）

`fmp_layer_imports` 的 `sealedDirectories` 讓 `lib/legacy_import/` 外的檔案都不能 import 它，包括 `lib/main.dart`。匯入總要有人呼叫，所以：

- **只開放 `lib/main.dart`**（組裝點）import `lib/legacy_import/`；`lib/app/` 定義介面 `LegacyImport`（§2.2），由 `main.dart` 以 provider override 注入實作，設定頁只認介面。lint 照 `cache_directory` 的先例（`restrictedImports`，只准 `lib/main.dart`，`layer_imports.dart:134-138`）：`lib/legacy_import` 從 `sealedDirectories` 移到 `restrictedImports`，目錄內部互相 import 照舊可以；雙向變異案例照 `.trellis/spec/app/lints/index.md`。
- `legacy_import` 不能直接用 `drift`、`sqlite3`、`flutter_secure_storage`、`path_provider`（套件擁有者是 `lib/data`、`lib/platform`）：寫庫走 `lib/data/` 公開的型別，讀憑證與找檔走 `lib/platform/`。這正好是 §2 的分層。
- 官方插件 id 與舊憑證鍵名（`account_bilibili_credentials` 等）只能寫在 `lib/legacy_import`（lint `fmp_source_id_literal`）：`lib/platform/legacy_data/` 與 `lib/data/import/` 的 API 以參數收鍵名，不自己寫字面值。

### 0.3 Isar 沒有唯讀模式（研究 L §9）

Isar 的開啟必經原生 `isar_instance_create`，會建 lock 檔、依傳入 schema 與庫內 schema 的差異改寫檔案；沒有唯讀選項。所以**一律先把舊資料庫檔複製到工作目錄、開副本**，舊檔一個位元組都不碰；開副本時傳完整的 11 個 collection schema（只傳一部分可能刪掉其他 collection 的資料）。

### 0.4 擁有者真實資料的事前觀察

2026-10-22 經擁有者授權（「如有需要可以直接從用戶文件夾中獲取」）：

- 只列了 `Documents\FMP\`、`%APPDATA%\com.personal\fmp\`、`%LOCALAPPDATA%\com.personal\fmp\` 的檔名；
- 把 `fmp_database.isar` 複製到 session 暫存目錄，只統計 `https?://` 字串的網域與路徑形狀（數字與長 id 遮掉，不輸出歌單名稱或 id），隨即刪除副本。

結果：平台歌單只有一張 B 站收藏夾（`space.bilibili.com/<mid>/favlist?fid=<id>`），其餘網址都是過期的串流網址（不匯入）。所以平台歌單的網址換算只要認官方插件能離線認的形式（§5.3），認不出的轉本機歌單（§11 第 4 條）。

## 1. 範圍

### 1.1 M5 匯入的

| 舊 | 新 | 節 |
|---|---|---|
| `Track`（被歌單、佇列、歷史參照的） | `tracks` | §5.2 |
| `Playlist`（本機、平台、Mix） | `playlists`、`playlist_remote`、`playlist_entries` | §5.3 |
| `PlayQueue` | `queue_entries`、`player_state` | §5.4 |
| `PlayHistory` | `play_history`（快照補進 `tracks`） | §5.5 |
| `RadioStation` | `radio_stations` | §5.6 |
| `Track.originalSongId`／`originalSource` | `track_origins`（id 格式與新插件相同的才寫） | §5.7 |
| `Account`＋舊憑證 | `accounts`＋`CredentialStore` | §5.8 |
| `Settings` 有落腳處的欄位 | 外觀、播放、網路設定組、`source_settings`、`layout_state` | §5.9 |
| 舊 JSON 備份（v1–v5） | 同上（沒有佇列、帳號、憑證） | §4.2 |

### 1.2 留給之後里程碑的（舊資料保留，由各自補匯）

ADR 0026 §決定 2：「每個新增資料表的里程碑，同時補上那張表的舊資料匯入」。M5 的讀取器（§4.1）讀出全部 11 個 collection，之後的里程碑在轉換器加自己的部分：

| 舊 | 里程碑 | M5 要保證的 |
|---|---|---|
| `DownloadTask`、`Track.playlistInfo[].downloadPath`、下載設定（`customDownloadDir`、並行數、附帶圖片） | M6 | 舊資料庫留在原處；讀取器讀出 `playlistInfo`；舊 `Track.id` 到新鍵可以從舊庫重算（`Track` 列本身有鍵的三段），但**舊 `Playlist.id` 到新歌單 id 重算不出來**（使用者之後會改名、刪除、重排，研究 L §8.3），所以 M5 存對照表 `legacy_playlist_ids`（§6.4） |
| `LyricsMatch`、歌詞設定、AI 端點與模型、`lyrics_ai_api_key`、`lyricsWindow*` | M7 | 舊憑證檔裡的 `lyrics_ai_api_key` 不讀不刪 |
| `minimizeToTrayOnClose`、`enableGlobalHotkeys`、`hotkeyConfig`、`launchAtStartup`、`launchMinimized` | M8 | 讀取器讀出這些欄位 |

已經匯入過的使用者（擁有者的 dev 試用）在 M6–M8 之後要拿到這些部分：各里程碑決定「補匯」的入口（例如設定頁的從舊版匯入只補自己的表）。M5 不預先做。所以**「刪除舊版資料」移到 M9**（§11 第 7 條）：在那之前舊資料庫一定要在。

### 1.3 不匯入的（列在結果裡）

| 舊 | 理由 |
|---|---|
| `primaryColor`、`fontFamily` | 新版沒有這兩個設定（主色是編譯期常數，字型由平台層依語言決定，研究 T §5.1）；§11 第 2 條 |
| `sourceSettings[].streamPriority` | 新版的串流選擇在插件內，宿主只送全域音質（研究 T §5.4）；§11 第 2 條 |
| `maxCacheSizeMB`、`maxLyricsCacheFiles` | ADR 0016 §決定 3 已定不匯入 |
| `homeRankingSourcePriority`、`disabledHomeRankingSources` | 新版的排行設定以（插件, 榜單 id）為單位，榜單 id 要插件裝好才知道；§11 第 2 條 |
| `railExpanded` | 新版沒有可收合的側欄設定 |
| `SearchHistory` | 新版沒有搜尋歷史功能；§11 第 3 條 |
| `Playlist.notifyOnUpdate`、`useAuthForRefresh`、`mixPlaylistId`；`RadioStation.hostAvatarUrl`、`hostUid`、`isFavorite`、`lastPlayedAt`；`Track.viewCount`、`isVip`、`bilibiliAid`、`unavailableReason`、`ownerId`、`channelId`、`pageCount`；`Account.isVip` | M3、M4 已定（沒有讀者或 ADR 否決，研究 T §3.5、M3 design §3.4、M4 design §3.4） |
| 推導值與過期值：`audioUrl`、`audioUrlExpiry`、`uniqueKey` 等被持久化的 getter、`LyricsTitleParseCache`、`schemaVersion` | 研究 L §1 |
| `Track.originalSource = spotify` | 新 Spotify 插件的 `sourceId` 是 `spotify:track:<id>`，舊版存 hex `uid`，對不上（M4 implement「留下的後續」） |

### 1.4 M5 不做的事

- 不自動安裝音源插件：匯入後首頁、搜尋頁照 ADR 0030 §12 顯示首次引導；未安裝前曲目照現有行為標「音源未安裝」（ADR 0014 §決定 8 的「提示一鍵安裝」由引導滿足，§7.3 的結果對話框加一個「安裝音源」按鈕跳到引導）。
- 不做合併式匯入：舊版的 JSON 匯入是合併（同名歌單略過），新版一律取代（§11 第 6 條）。
- 不在匯入時連網（刷新平台歌單、驗證憑證、解析短網址）。

## 2. 模組與分層

### 2.1 目錄

| 目錄 | 內容 | 可 import |
|---|---|---|
| `lib/legacy_import/isar/` | 舊 11 個 collection 與 2 個 embedded 的模型（自舊 `lib/data/models/` 複製，只留欄位與 Isar 註記）與提交的 `*.g.dart` | `isar_community` |
| `lib/legacy_import/` | `LegacySnapshot`（讀出的舊資料，純值）、`LegacyDatabaseReader`、`LegacyBackupReader`、`LegacyConverter`（snapshot → `ImportBundle`）、`LegacyImporter`（流程）、`LegacyImport` 的實作 | `lib/data`、`lib/platform`、`lib/domain`、`lib/core`、`lib/app` 的介面 |
| `lib/data/import/` | `ImportBundle`（新格式的匯入包，純值）、`StagingImport`（寫暫存庫、驗證）、`legacy_imports` 的 repository | `drift`、`sqlite3` |
| `lib/platform/legacy_data/` | `LegacyDataLocator`（舊資料庫與憑證檔在哪）、`LegacyCredentialReader`（Windows DPAPI、Android 舊設定實例） | `path_provider`、`flutter_secure_storage`、`win32`、`ffi` |
| `lib/app/` | `LegacyImport` 介面與 provider、`LegacyImportApp`（啟動時的進度與失敗頁）、結果對話框 | — |

`ImportBundle` 在 `lib/data/` 而不在 `legacy_import`：`lib/data` 不能 import 封住的目錄，寫入端只能認自己的型別。`ImportBundle` 以新版的語彙寫（`TrackInfo`、`PlaylistKind`、設定的值型別），沒有任何舊版概念。

### 2.2 `LegacyImport` 介面（`lib/app/legacy_import.dart`）

```dart
abstract interface class LegacyImport {
  /// 找舊資料：首次啟動與設定頁都用。沒有時回 null。
  Future<LegacySource?> locate();
  /// 讀、轉換、寫暫存庫、驗證；不換上。progress 給進度畫面。
  Future<LegacyStaged> stage(LegacySource source, {void Function(LegacyImportStep) progress});
  /// 舊 JSON 備份檔（設定頁）。
  Future<LegacyStaged> stageBackup(Uint8List bytes, {void Function(LegacyImportStep) progress});
  /// 換上之後寫憑證（只寫 staged 帶著的、且這台目前沒有登入的平台）；失敗的平台回報「需要重新登入」。
  Future<Set<String>> writeCredentials(LegacyStaged staged, {required Set<String> loggedInPluginIds});
}
```

`LegacyStaged` 帶暫存庫的路徑、要寫的憑證（記憶體，不落地）與結果摘要。`main.dart` 以 `legacyImportProvider.overrideWithValue(...)` 注入；測試注入假實作。

### 2.3 依賴

- `isar_community` 3.3.2、`isar_community_flutter_libs` 3.3.2（M1 已證實與 `sqlite3` 共存，ADR 0010 後果）；擁有者 `lib/legacy_import`（lint 表已有）。
- `win32`、`ffi`：直接依賴（目前只是 `flutter_secure_storage_windows` 的間接依賴），擁有者 `lib/platform`（加進 `platformPackages`）。版本與 lock 檔現有的相容。
- CI：`app/` 的單元測試只在 Linux 跑。DPAPI 的解密抽成可注入的函式，讀取邏輯（壞檔、缺鍵、檔案不變）在 Linux 以假的解密測；真的 `CryptUnprotectData` 往返放進 `integration_test/legacy_credentials_test.dart`，加進 CI 既有的 Windows 整合測試 job（與 `secure_storage_test.dart` 同一個 job，各一步）。
- `isar_community_generator` 不進 workspace（analyzer 衝突，ADR 0010 後果）：在 workspace 外的暫存 package 產生 `*.g.dart` 後提交（M1 探針的做法，研究 L §9.1）。產生步驟寫進 `lib/legacy_import/isar/README.md`；舊 schema 已凍結，之後不再產生。

## 3. 流程

### 3.1 首次啟動（`main()`）

```
解析資料目錄 → Log → 清掉殘留的工作目錄與暫存檔 →
  fmp.db 存在？ ── 是 → 照舊開庫、runApp(FmpApp)
        │否
  locate() 找到舊資料庫？ ── 否 → 照舊（建空庫）
        │是
  runApp(LegacyImportApp) ─ 進度畫面 ─ stage() ─ 成功 ─ 暫存庫改名成 fmp.db → writeCredentials() → 開庫 → runApp(FmpApp)，顯示結果對話框
                                         └ 失敗 → 失敗頁：重試｜匯出診斷｜以空白資料啟動
```

- **條件**：資料目錄沒有 `fmp.db`，且 `locate()` 找到舊資料庫（§11 第 8 條）。有 `fmp.db` 就不自動匯入（包括「以空白資料啟動」之後），之後從設定頁匯入（§3.2）；設定頁在找得到舊資料庫、且 `legacy_imports` 沒有任何紀錄時，在「從舊版匯入…」旁顯示一句提示。
- **同時開著舊版**：prod 的新舊 App 用同一個單一實例 mutex（`Local\FMP_MainInstance`，舊 `windows/runner/main.cpp:13`、新 `app_identity.cmake:17`），Android 是同一個 applicationId，兩者不會同時執行；dev 讀的是副本。複製後仍以讀到的筆數與 Isar 開檔成功為準，副本壞了就是失敗頁。
- **進度畫面**在 `runApp` 之前沒有 Riverpod 的 App 組裝：`LegacyImportApp` 是獨立的小 App（同 `DatabaseErrorApp` 的做法，語言與主題跟隨系統），完成後 `main()` 再 `runApp(FmpApp)` 換掉根。
- **資料庫先換、憑證後寫**：首次啟動沒有已開的資料庫，暫存庫直接 rename 成 `fmp.db`（同一個目錄）；rename 成功後才 `writeCredentials`。
  - rename 失敗：刪暫存、走失敗頁，什麼都沒寫。
  - 寫憑證失敗（或寫到一半 App 被結束）：已換上的庫裡有帳號列、secure storage 沒有憑證；`CredentialStore` 載入時把沒有憑證的帳號列刪掉（`credential_store.dart:176-185`），結果是「需要重新登入」，不留孤兒的 cookie。反過來的順序（先寫憑證）在換檔失敗時會留下沒有帳號列的 cookie，而 `CredentialStore` 只載入已安裝插件與有帳號列的 id（`:117-121`），首次啟動還沒有插件，那份 cookie 會一直留著。
- **失敗頁**（§7.2）：
  - 重試：再跑一次 `stage()`；
  - 匯出診斷：以檔案對話框存一份文字檔（錯誤、步驟、各 collection 的筆數；經 `Redactor`，不含歌單名稱與憑證）與 log 檔；
  - 以空白資料啟動：建空庫、照舊啟動。之後從設定頁可再匯入（ADR 0010）。

### 3.2 設定頁的「從舊版匯入…」

選「舊版資料庫」（`locate()` 找到時才能選）或「舊版備份檔（.json）」→ `stage()`／`stageBackup()`（進度對話框）→ 確認框（§7.4）→ `DatabaseBackups.replaceWithImport`（§6.3）→ 重啟。

**不走 ADR 0034 的還原路徑**：還原是「整份換成另一台的資料」，`carryOver` 會清空 `backupExcludedTables`、只留開發標記的插件列、把 `browse_as_logged_in` 全部設成空再只對暫存庫裡已安裝的插件寫回（`database_backups.dart:662-671,688-694,747-755`）；`_stage` 一開始還會刪掉 `backups/` 裡所有 `staged-` 開頭的檔（`:189,490`）。舊資料沒有插件、插件設定、排行設定，照還原的語意換上會把這台裝好的插件與設定一起丟掉。所以舊版匯入是**取代音樂庫與舊資料有的設定，保留這台的插件、插件設定與登入**（§11 第 6 條），由 `lib/data/` 的專用方法做；共用的只有「自動備份」與「關庫、換檔、重啟」兩段。

## 4. 讀舊資料

### 4.1 舊資料庫（`LegacyDatabaseReader`）

1. `LegacyDataLocator` 給出舊資料庫檔的路徑：
   - Windows prod：`<文件>\FMP\fmp_database.isar`，其次 `<文件>\fmp_database.isar`（極舊版本放在 documents 根目錄，研究 L §3.1）；
   - Android prod：`<app_flutter>/FMP/fmp_database.isar`，其次 `<app_flutter>/fmp_database.isar`（`getApplicationDocumentsDirectory()`）；
   - dev：只看 `--fmp-legacy-dir`（§8.1）。
2. 複製到 `<資料目錄>/legacy-import/work-<UTC>/fmp_database.isar`（lock 檔不複製）。
3. 以實例名 `fmp_database`、完整 11 個 schema、`maxSizeMiB: 2048`、不壓縮開副本，`findAll` 每個 collection，關閉，刪工作目錄（成功與失敗都刪）。
4. 每個 collection 讀成 `LegacySnapshot` 的純值（不帶 Isar 型別出去）；推導值與過期值不讀。

讀到的原始值照 Isar 的型別預設（非空 int 缺欄是 `minLong`、double 是 NaN、bool 是 false，研究 L §1.0）。舊 App 每次啟動都會跑 migration 與 `repairSettingsInvariants`，所以 `schemaVersion = 4` 的庫已經是修好的值；**`schemaVersion < 4`**（從 v1.9.x 以前直接跳來，研究 L §5.2）時，讀取器在 snapshot 上以純函式重做舊版的 0→4 與 `repairSettingsInvariants`（照 `lib/data/database/database_migration.dart` 移植，只改 snapshot 的 `LegacySettings`，不碰檔案）。否則 1→2 沒跑時 `sourceSettings` 是空的、缺欄的 bool 讀成 false 會被當成「使用者關掉」。之後轉換器再把「不在合法值域」當作「沒設定」（§5.9）。測試：v0、v1、v3 的合成設定各一例。

### 4.2 舊 JSON 備份（`LegacyBackupReader`）

- 版本 1–5，缺鍵一律走舊版的預設；比 5 新的拒絕（舊版自己也擋）。逐鍵容錯：同一個版本號的檔案欄位集合可能不同（研究 L §4.2）。
- 時間是沒有時區的本機時間字串，以匯入裝置的本機時區解讀（與舊版相同，研究 L §4.1）。
- v3 以前的六個每源鍵照舊版 `_readSourceSettings` 折疊（研究 L §4.5）。
- 曲目以 `trackKeys`（`TrackKey` 字面）參照，直接對上；`trackKeys` 找不到曲目的項目略過並計數。
- 讀成同一個 `LegacySnapshot`（佇列、帳號、憑證、下載為空）。

### 4.3 舊憑證（`LegacyCredentialReader`，`lib/platform/legacy_data/`）

讀四個舊鍵：`account_bilibili_credentials`、`account_youtube_credentials`、`account_netease_credentials`（`lyrics_ai_api_key` 留給 M7，M5 不讀）。每個鍵的結果是「有值／沒有／讀不出」。

- Windows：讀 `<目錄>\flutter_secure_storage.dat` 的位元組，`CryptUnprotectData`（無 entropy）→ UTF-8 → JSON map，取上面三個鍵（值是 JSON 字串）。整檔讀不出時三個鍵都是「讀不出」。prod 的目錄是 application support（`%APPDATA%\com.personal\fmp`），dev 是 `--fmp-legacy-dir`。**不寫、不刪檔案**。解密是注入的函式（§2.3 的 CI 安排）。
- Android（只有 prod）：先看舊 prefs 檔（`<資料>/shared_prefs/FlutterSecureStorage.xml`）在不在，不在就三個鍵都是「沒有」、不建立實例（11.x 在沒有舊資料時會建金鑰與標記，研究 S §4）；在的話以 §0.1 的舊設定實例 `read(key)`，拋例外當「讀不出」。dev 讀不到 prod 的沙盒，不讀。
- 讀出的值只在記憶體，轉成新形狀（§5.8）後交給 `writeCredentials`，log 只寫鍵名與「有／沒有／讀不出」。

## 5. 轉換（`LegacyConverter`：`LegacySnapshot` → `ImportBundle`）

純 Dart、沒有 I/O，每一筆略過都帶理由（`SkipReason`）並計數，結果摘要（§6.4）從這裡來。

### 5.1 通則

- **音源 id**：舊 `sourceType`／`platform`／`importSourceType` 的 `bilibili`、`youtube`、`netease` 與新官方插件 id 字面相同，不轉換（M3 design）；其他值的列略過（理由 `unknownSource`）。
- **時間**：Isar 的 `DateTime` → UTC epoch 毫秒；JSON 照 §4.2。
- **TrackKey**：`TrackKey.format(sourceType, sourceId, cid: cid)`，與舊版逐字相同（`app/lib/domain/track_key.dart`），**B 站單 P 例外**：
  - 舊版播放時替每首 B 站曲目補 cid（`backfillCid`，研究 L §2.2；ADR 0005），單 P 影片的鍵因此是三段；新 B 站插件對單 P 影片只回兩段（`fmp-plugins/bilibili/src/plugin.js` 的 `itemsOfMedia`：`pages <= 1` 時不帶 cid）。照原樣匯入，同一首歌會有兩個鍵：搜尋與刷新得到的那首和匯入的那首對不上，B 站收藏夾第一次完整刷新會把匯入的項目全部刪掉再重加。
  - 規則：B 站曲目 `pageCount` ≤ 1，或 `pageCount` 空且 `pageNum` 空或 1 且 `parentTitle` 空時，視為單 P、**去掉 cid**；同一支影片的兩段與三段單 P 鍵因此合併成一列（§5.2 的重複處理）。歷史與佇列裡的鍵經同一張「舊鍵 → 新鍵」對照；歷史裡出現、`Track` 裡沒有的 B 站鍵沒有 `pageCount` 可看，照原樣（記 `unverifiedPart`）。
  - PR 3 以 B 站插件 1.10.0 的搜尋、收藏夾、分 P 程式碼再對一次規則；§11 第 12 條。
- **封面**：單一網址 → `[{url}]`；空字串或不是 `http(s)` 的略過。

### 5.2 曲目

- 只寫被歌單、佇列、歷史參照到的曲目（沒人參照的會被啟動維護當孤兒刪掉）；未被參照的略過（`unreferenced`）。
- 欄位：`title`、`artist` → `uploader`、`durationMs`、`thumbnailUrl` → `artwork`、`cid`、`pageNum` → `part_index`、`parentTitle` → `parent_title`（M3 PR 20 已定）。
- `part_index`、`parent_title` 只給分 P 曲目（正規化後還帶 cid 的，§5.1）：新版只有分 P 曲目有這兩欄（`app/AGENTS.md` § 資料層），而擁有者的舊庫 1195 首裡有 1193 首帶 `pageNum`、只有 299 首帶 cid（`research/isar-copy-spike.md`），單 P 的 `pageNum = 1` 照搬會讓顯示標題多出「P1」。
- 舊庫沒有唯一鍵，同一個鍵（正規化後，§5.1）可能有多列：取 `updatedAt ?? createdAt` 最新的一列；其餘計 `duplicateTrack`。舊 `Track.id` 一律先對到它的鍵，所以參照到被併掉那一列的歌單項目仍然接得上。
- 歷史快照補的曲目（§5.5）只在鍵還沒有時寫，不蓋過 `Track` 來的那一列。

### 5.3 歌單

先依舊 `sortOrder`、再依 `id` 排，`sort_order` 重寫成 0..n-1；`created_at`、`updated_at` 照舊值（`updatedAt` 空時用 `createdAt`）。

| 舊 | 新 |
|---|---|
| `isMix` | `kind = mix`、`mix_plugin_id = youtube`、`mix_seed_source_id = mixSeedVideoId`；種子空時略過（`mixWithoutSeed`）；沒有曲目 |
| `sourceUrl` 非空且認得（下表） | `kind = imported`＋`playlist_remote` |
| `sourceUrl` 非空但認不出，或（插件, 遠端 id）與先前一張重複 | `kind = local`，保留曲目；記 `remoteNotRecognized`／`duplicateRemote`（§11 第 4 條） |
| 其他 | `kind = local` |

- 共用：`name`、`description`、`coverUrl` → `artwork_json`。
- `playlist_remote`：
  - `plugin_id` 取自網址辨識的結果（不信 `importSourceType`，兩者不同時以網址為準並記一筆）；
  - `owner_name = ownerName`；
  - `writable`：`ownerUserId` 等於該平台舊 `Account.userId` 時為真（M4 design §3.4）；
  - `artwork_overridden = hasCustomCover`；
  - `refresh_interval_hours = refreshIntervalHours`（原樣，空＝不自動刷新，ADR 0017 §決定 6）；
  - `last_refreshed_at = lastRefreshed`，`last_result`、`status` 用預設（空、`active`）。
- 項目：依 `trackIds` 順序寫 `position`；指到不存在曲目的 id 略過（`danglingTrackId`）；平台歌單裡 `Track.isAvailable` 為假的項目 `unavailable = true`（M4 design §17 第 11 條）；`remote_item_id` 空、`seen_generation` 0（下一次完整刷新以（曲目鍵, 第 k 次出現）比對，研究 T §3.3）。

**網址辨識**（`lib/legacy_import/remote_playlist_url.dart`，只認不需要連網的形式；規則照官方插件的 `playlistFromUrl`，PR 3 寫下對照的插件版本）：

| 插件 | 認得的形式 | `remote_id` |
|---|---|---|
| `bilibili`（1.10.0 `plugin.js:412`） | B 站網域；query 的 `fid=<數字>`，或路徑整段 `ml<數字>` | 那串數字 |
| `youtube`（1.6.0 `playlist.js:30`） | YouTube 網域的 `list=<id>`（`importable(id)` 為真的；Mix 的 `RD…` 不算） | `list` 的值 |
| `netease`（1.7.0 `plugin.js:300`） | 網易網域的歌單網址（`playlist?id=<數字>`、`#/playlist?id=`、`/m/playlist?id=`）；短網址 `163cn.tv` 要連網，認不出 | `id` 的值 |

閘門：每個插件一組「網址 → 結果」的表格測試，表格的期望值逐條取自該插件的單元測試或原始碼（測試檔註明插件版本）。兩個 repo 沒有自動的一致性檢查，插件改了 `playlistFromUrl` 的輸出形狀時要回頭改這裡：寫進 `fmp-plugins` 的 README「宿主的依賴」一節。

### 5.4 佇列與播放狀態

M2 design §3.6、M3 design §3.4：

- 項目的自然順序：`isShuffleEnabled` 且 `originalOrder` 非空時用 `originalOrder`，否則用 `trackIds`；指到不存在曲目的略過。
- `current_position`：`trackIds[currentIndex]` 在自然順序裡的位置（同一首出現多次時取第 k 次對第 k 次）；越界或略過了就空。
- `shuffle_enabled = isShuffleEnabled`，`shuffle_rank` 匯入時重新產生（M2 design §3.6：等同舊版重啟時的行為）。
- `loop_mode`：`none` → `off`、`all`、`one`；`position_ms = lastPositionMs`（負值當 0）；`volume = lastVolume` 夾在 0–1，NaN 或「整列都是型別預設」時 1.0；`muted = false`。
- Mix：`isMixMode` 且 `mixPlaylistId`、`mixTitle` 都有值時 `mode = mix`、`mix_plugin_id = youtube`、`mix_id = mixPlaylistId`、`mix_title = mixTitle`、`mix_cursor` 空；缺任一個就當一般佇列。

### 5.5 播放歷史

依 `playedAt` 由新到舊，保留到播放歷史上限（§5.9 換算後的值），多的略過（`overHistoryLimit`）；曲目以快照補（§5.2）；`played_at` 照舊值。

### 5.6 電台

M3 design §3.4：`plugin_id = sourceType`、`room_id = sourceId`、`title`、`host_name = hostName`、`artwork = [thumbnailUrl]`、`added_at = createdAt`；依舊 `sortOrder` 排。（`plugin_id`, `room_id`）重複的略過（`duplicateStation`）。

### 5.7 外部匯入的來源

`originalSource ∈ {qqmusic, netease}` 且 `originalSongId` 的格式與新插件的 `sourceId` 相同時，寫 `track_origins(track_key, origin_plugin_id, origin_id)`；不同或 `spotify` 略過（`originIdFormat`）。不寫 `match_results`（舊版沒有分數與候選）。PR 3 對照兩個插件的 `sourceId` 格式，寫進測試。

### 5.8 帳號與憑證

- 每個平台：舊憑證「有值」且能轉成新形狀時，寫一列 `accounts`＋一份 `LoginCredentials`（兩者成對，否則 `CredentialStore` 的對齊會刪掉另一半，研究 T §4.4）。
- 帳號列：
  - `user_id = Account.userId`，空時取憑證裡的 id（B 站 `dedeUserId`、網易 `userId`、YouTube `datasyncId`），都沒有就不匯入該平台（`accountWithoutId`）；
  - `display_name = userName ?? user_id`；
  - `avatar_json = [avatarUrl]`；
  - `status = active`（舊版 `sessionExpired` 時憑證已被刪，不會走到這裡）；
  - `logged_in_at = loginAt ?? 匯入時間`；
  - `last_refresh_at = lastRefreshed`。
- 憑證形狀（ADR 0029、研究 T §4.2；cookie 名稱在 PR 4 對照插件的登入程式碼再確認一次）：

| 平台 | 舊欄位 → 新 cookie | `extra` | 必要（缺就算讀不出） |
|---|---|---|---|
| bilibili | `sessdata` → `SESSDATA`、`biliJct` → `bili_jct`、`dedeUserId` → `DedeUserID`、`dedeUserIdCkMd5` → `DedeUserID__ckMd5` | `refreshToken` → `refresh_token` | `SESSDATA`、`bili_jct`、`DedeUserID` |
| netease | `musicU` → `MUSIC_U`、`csrf` → `__csrf` | — | `MUSIC_U` |
| youtube | `sid`、`hsid`、`ssid`、`apisid`、`sapisid`、`secure1Psid`、`secure3Psid`、`secure1Papisid`、`secure3Papisid`、`loginInfo` → `SID`、`HSID`、`SSID`、`APISID`、`SAPISID`、`__Secure-1PSID`、`__Secure-3PSID`、`__Secure-1PAPISID`、`__Secure-3PAPISID`、`LOGIN_INFO` | — | `SAPISID`、`__Secure-1PSID`、`__Secure-3PSID` |

  空字串的欄位不寫成 cookie。
- 讀不出或缺必要 cookie 的平台：不寫帳號，結果列「需要重新登入」（ADR 0010 §決定 4）。
- 匯入不驗證憑證（不連網）。B 站插件的 `refresh: onStartup` 在插件裝好後的啟動自己檢查。
- **寫入只經 `lib/plugins/accounts`**：`credentials.<id>` 的鍵與 `LoginCredentials` 的編碼現在是 `CredentialStore` 的私有細節（`credential_store.dart:102`），匯入端不另抄一份。PR 4 在 `CredentialStore` 加一個公開的靜態方法 `writeImported(SecureStorage, pluginId, LoginCredentials)`（共用 `_key` 與編碼），`LegacyImport.writeCredentials` 呼叫它。閘門：往返測試，寫入後以真的 `CredentialStore` 載入（帳號列在暫存庫），帳號與憑證成對、`isLoggedIn` 為真。

### 5.9 設定

**通則**（§11 第 5 條）：

- 只寫使用者在舊版改過的值，也就是不等於舊版預設的值；等於舊版預設、或不在合法值域（Isar 的型別預設、`minLong`、NaN）的，新版欄位保持空，讓新版自己的預設生效（ADR 0011：空＝沒設定過）。
- 舊值不在新版的選項裡時，取最接近的選項（等距取大的）；播放歷史上限取「不小於舊值的最小選項」，上限 50000，避免匯入時就把歷史裁掉。

| 舊 | 新 |
|---|---|
| `themeModeIndex` 1／2 | `appearance_settings.theme_mode` `light`／`dark`（0＝跟隨系統，空） |
| `locale` `zh_TW`／`zh_CN`／`en` | `locale` `zh-TW`／`zh-CN`／`en` |
| `audioQualityLevelIndex` 0／1／2 | `playback_settings.audio_quality` `high`／`medium`／`low` |
| `audioFormatPriority` | `audio_format_priority`（字面相同） |
| `rememberPlaybackPosition` | `remember_position` |
| `tempPlayRewindSeconds`、`restartRewindSeconds` | `temp_play_rewind_seconds`、`restart_rewind_seconds`（選項 0／3／5／10／15／30） |
| `playHistoryLimit` | `play_history_limit`（選項 1000／5000／10000／50000） |
| `autoScrollToCurrentTrack` | `auto_scroll_to_current` |
| `preferredAudioDeviceId`／`Name`（只在 Windows） | `output_device_id`／`output_device_name` |
| `radioRefreshIntervalMinutes` | `network_settings.radio_status_interval_minutes`（選項 0／1／3／5／10） |
| `rankingRefreshIntervalMinutes` | `chart_refresh_interval_minutes`（選項 0／30／60／120／240） |
| `sourceSettings[].useAuthForPlay` | `source_settings.browse_as_logged_in`（ADR 0012 §決定 6：照舊值；舊版 v3→v4 強制打開的 B 站值照現值，ADR 0010 §決定 4） |
| `detailPanelExpanded`、`detailPanelWidth` | `layout_state.panel_expanded`、`panel_width`（夾在 ≤ 1600；只在舊資料庫匯入時寫，備份檔不帶版面） |

`browse_as_logged_in` 的「舊預設」以音源為準（B 站、網易開，YouTube 關），與新版預設（三個都開）不同：舊值等於舊預設時仍要寫（否則 YouTube 的「關」會變成新版的「開」）。所以這一欄例外，**三個音源都照舊值寫**。

## 6. 寫入、驗證與換上（`lib/data/import/`）

### 6.1 寫暫存庫（`StagingImport.write`）

- 在 `<資料目錄>/legacy-import/staging-<UTC>.db` 建庫（不放 `backups/`：`DatabaseBackups._stage` 一開始會刪掉 `backups/` 裡所有 `staged-` 開頭的檔，`database_backups.dart:189,490`）。啟動時清掉 `legacy-import/` 的殘留（§3.1）。
- 首次啟動：以 `AppDatabase` 建全新的庫（`user_version` = 目前 schema）。設定頁：先 `VACUUM INTO` 目前的庫得到副本，再在副本上清掉要取代的部分（§6.3）。之後同一個 transaction 寫完整個 `ImportBundle`。
- 直接用 drift 的表寫，不經 repository：要保留 `created_at`、`updated_at`、`played_at`、`added_at`、`last_refreshed_at` 的原值，批次寫歷史（一萬筆一次寫），寫 `playlist_entries` 的 `unavailable`；repository 都沒有這些入口（研究 T §10）。寫入後以 repository 讀回做 §6.2 的抽樣比對。
- 同一個 transaction 寫一列 `legacy_imports` 與 `legacy_playlist_ids`（§6.4）。

### 6.2 驗證（`StagingImport.verify`）

全部通過才算成功，任何一項失敗刪暫存檔並拋 `LegacyImportFailed(step, reason)`：

1. **筆數**：匯入的每張表，列數等於「`ImportBundle` 的筆數＋取代後留下的列數」（首次啟動時後者為 0）。
2. **抽樣**：曲目、歌單（含項目順序）、歷史、電台各隨機抽 50 筆（不到 50 筆就全部），以 repository 讀回比對每個欄位。
3. **完整性**：`PRAGMA integrity_check` 為 `ok`、`PRAGMA foreign_key_check` 為空（`DatabaseInspector.check`）。
4. **孤兒**：沒有未被參照的曲目（`TracksRepository` 的孤兒查詢為 0）。

### 6.3 換上

- **首次啟動**：§3.1 的 rename。
- **設定頁**（`DatabaseBackups.replaceWithImport(File staging)`，§3.2）：
  1. 自動備份（`create()`，失敗就停，同還原）；
  2. 在 §6.1 的副本上取代：
     - 清空音樂庫：`playlist_entries`、`playlist_remote`、`playlists`、`legacy_playlist_ids`、`match_results`、`track_origins`、`play_history`、`queue_entries`、`player_state`、`radio_stations`、`tracks`；
     - 設定組只覆寫 `ImportBundle` 有值的欄位，其他欄位保留這台的值；`source_settings.browse_as_logged_in` 以匯入值為準（三個音源）；`layout_state` 保留這台的值（版面只在首次啟動匯入）；
     - 帳號：這台有登入的平台保留這台的列，其餘寫匯入的列（§11 第 9 條），`writeCredentials` 只寫後者；
     - 保留不動：`installed_plugins`、`plugin_storage`、`plugin_indexes`、`chart_settings`、`developer_settings`、`scheduler_runs`、`legacy_imports` 的舊列（新增一列）。
  3. 寫入、§6.2 驗證；
  4. 關庫、換檔：抽出 `restoreStaged` 的「舊檔改名成 `fmp.db.before-restore-<UTC>`、暫存檔改名成 `fmp.db`、失敗改回」成共用的私有方法，還原與舊版匯入都呼叫它；
  5. 寫憑證，重啟（`AppRestarter`；Android 不會自己起來，照還原現有的提示）。
- 測試：取代後插件、插件設定、排行設定、`browse_as_logged_in` 的值；帳號合併的三種情況（只有這台、只有匯入、兩邊都有）；還原的既有測試照舊通過（共用的換檔方法）。

### 6.4 匯入紀錄（schema v19）

**`legacy_imports`**：

| 欄位 | 型別 | 說明 |
|---|---|---|
| `id` | int PK | 自增 |
| `source` | text | `database`／`backup`（converter 寫死字串） |
| `imported_at` | epoch ms | |
| `legacy_schema_version` | int? | 舊 `Settings.schemaVersion`（資料庫來源） |
| `backup_version` | int? | 備份檔的 `version` |
| `summary_json` | text | 每個 collection 的 `read`／`written`／`skipped{理由: 筆數}`、不匯入的設定清單、需要重新登入的平台 |
| `acknowledged` | bool | 結果對話框看過了 |

**`legacy_playlist_ids`**（給 M6 的下載紀錄對歌單，§1.2）：`legacy_import_id`（FK `legacy_imports`，CASCADE）、`legacy_playlist_id` int、`playlist_id`（FK `playlists`，CASCADE：歌單刪了對照就沒了）；PK（`legacy_import_id`, `legacy_playlist_id`）。只有資料庫來源寫（JSON 備份的歌單沒有舊 id）。

- 備份格式歸類：兩張都進 `backupExcludedTables`（這台的事件，不跟著備份走；`backup_format_test.dart` 強制歸類）。設定頁的取代不經 `carryOver`，所以不會被清掉（§6.3）。
- 讀者：結果對話框（§7.3）、設定頁的提示（§3.1）、驗收的筆數比對；`legacy_playlist_ids` 的讀者是 M6（M5 只寫，閘門是寫入測試）。

## 7. 介面

文案進 `lib/i18n/` 三個語言；版面沿用既有元件（`DatabaseErrorApp`、`RestoreConfirmDialog`、設定頁的按鈕列），不新增頁面。

### 7.1 進度畫面（`LegacyImportApp`）

標題「正在從舊版匯入資料」，五個步驟（讀取舊資料、轉換、寫入、驗證、完成）以清單顯示目前步驟；不可取消（一般幾秒；中途結束 App 不留半套資料：暫存檔下次啟動清掉）。

### 7.2 失敗頁

同一個 `LegacyImportApp`：錯誤摘要（哪一步、原因的一句話）＋三個按鈕：「重試」「匯出診斷」「以空白資料啟動」；說明「舊資料沒有被改動，之後可以在設定頁再匯入」。`DatabaseErrorApp` 也加「重試」與「匯出診斷」（它的 docstring 說隨 M5 加）。

### 7.3 結果對話框

正式 App 起來後，`legacy_imports` 有未看過的一列時顯示一次：

- 匯入的筆數（歌單、曲目、歷史、電台、帳號）；
- 需要重新登入的平台；
- 未匯入的項目（§1.3 有值的才列）與轉成本機歌單的平台歌單數；
- 有參照到未安裝插件時，「安裝音源」按鈕（開啟首次引導，ADR 0030 §12）；
- 「知道了」：設 `acknowledged`。

### 7.4 設定頁「備份與還原」區

- **從舊版匯入…**：選「舊版資料庫」（找得到時）或「舊版備份檔（.json）」；確認框說明「會取代目前的歌單、曲目、歷史、佇列與電台，以及舊版有的設定；保留已安裝的插件、插件設定與這台目前的登入；取代前自動備份」，列出要匯入的筆數；之後 §3.2。舊 JSON 備份不含佇列，取代後佇列是空的（確認框寫明）。
- 找得到舊資料庫、且 `legacy_imports` 沒有紀錄時（例如首次匯入失敗後以空白資料啟動），按鈕旁一句提示。
- **刪除舊版資料不在 M5**（§11 第 7 條）：M6–M8 還要從舊資料庫補匯（§1.2），提早刪會讓之後的補匯拿不到資料。移到 M9（切換），那時所有補匯都已存在。M9 實作時要刪：
  - `fmp_database.isar` 與 `fmp_database.isar-lck`（鎖檔的實際後綴見 `research/isar-copy-spike.md`；舊程式碼的常數寫 `.isar.lock`，兩個都刪）；
  - 舊 log、舊快取的中繼檔；
  - 三個舊帳號憑證鍵與 `lyrics_ai_api_key`。

  不刪下載的音檔。刪除與讀取用同一個注入的路徑，dev 刪的是副本。

## 8. 開發入口與實機驗證

### 8.1 `--fmp-legacy-dir=<資料夾>`

- 只在 dev flavor 讀（參數優先，其次環境變數 `FMP_LEGACY_DIR`），prod 一律忽略，同 `--fmp-dev-plugin`（`dev_plugin_entry.dart`）。閘門：`prod reads neither …` 形式的測試。
- 資料夾內：`fmp_database.isar`（必要）、`flutter_secure_storage.dat`（可選，Windows）。
- 資料夾等於或位於真實的舊資料位置（`<文件>\FMP`、`%APPDATA%\com.personal\fmp`、Android 的 `com.personal.fmp` 沙盒）時拒絕：dev 只讀副本（同 `LegacyDataLocationException` 的理由）。
- Android：先 `adb push` 到 `/data/local/tmp`，再 `run-as com.personal.fmp.dev cp` 進 dev App 的 `files/legacy-copy/`，參數給那個路徑（步驟寫進 verify-on-device 的 `references/runtime-state.md`）。

### 8.2 驗收的做法（§11 第 10 條）

- **Windows**：
  1. 先備份 `userdata-dev`，再清空它（讓 `fmp.db` 不存在）；
  2. 把擁有者的 `fmp_database.isar` 與 `flutter_secure_storage.dat` 複製到 `<暫存目錄>/legacy-copy/`；
  3. 以 `--fmp-legacy-dir` 啟動 dev，看進度、結果對話框；
  4. 用同一份副本跑讀取器的計數工具（`tool/legacy_counts.dart`，只印每個 collection 的筆數），與 `legacy_imports.summary_json` 比對（2026-10-22 那份副本的筆數記在 `research/isar-copy-spike.md`）；
  5. 確認匯入的帳號仍是登入狀態：裝好官方插件後，帳號頁的帳號資訊每個平台讀一次。擁有者的舊庫有 B 站、網易兩個帳號，所以是真實連線 2 個請求。
- **B 站的 refresh token**：B 站插件 `refresh: onStartup` 會在需要時換 cookie，換了之後另一份的 `refresh_token` 失效（`fmp-plugins/bilibili/src/plugin.js` 的刷新流程）；舊版也會換。真實憑證同時在舊版與 dev 裡用，先刷新的一邊會讓另一邊登出（§11 第 10 條）。
- **Android 模擬器**：只放資料庫副本（dev 讀不到 prod 的 Keystore），比對筆數；憑證以 `research/android-credentials-compat.md` 的實測為證。
- 驗收結束：刪暫存目錄的副本。Windows 的 dev 資料留著（擁有者日常試用要用），在驗收紀錄寫明位置。
- 回報與研究檔只寫筆數與略過理由，不寫歌單名稱、曲目、帳號名稱、cookie 值。

## 9. 測試與閘門

| 對象 | 測試 |
|---|---|
| 舊 schema 沒被改到 | `test/legacy_import/legacy_schema_test.dart`：提交的 `*.g.dart` 的 collection 名、schema id、property 名與型別等於凍結的 `test/legacy_import/fixtures/legacy_schema.json`（由舊專案的 `*.g.dart` 產生一次）；變異：改一個 property 名會紅 |
| 讀取器不寫舊檔 | 在暫存目錄以舊模型寫一份合成的舊庫，記下檔案的 SHA-256 與修改時間 → 讀 → 兩者不變、工作目錄已刪 |
| 讀取器讀全 | 合成舊庫（每個 collection 幾筆，含缺欄的型別預設值、重複鍵、懸空 id、兩段與三段的 B 站鍵）→ snapshot 筆數與值 |
| 舊 migration 的補做 | `schemaVersion` 0、1、3 的合成設定 → 補做後的值等於舊版跑完 migration 的值 |
| 轉換器 | 純 Dart：§5 每一列對照表、每個略過理由各一例、B 站單 P 去 cid 與合併、分 P 欄位只給分 P、設定的「只寫改過的值」與選項換算、`browse_as_logged_in` 例外、網址辨識表 |
| 暫存庫 | 寫入後筆數、時間原值；注入壞資料（讓外鍵檢查失敗、讓抽樣比對不符）→ 拋錯且暫存檔已刪 |
| 首次啟動的中途失敗 | 在寫入、驗證、rename、寫憑證各步驟注入例外：rename 之前失敗 → 沒有 `fmp.db`、沒有暫存檔、舊檔不變；寫憑證失敗 → `fmp.db` 在，`CredentialStore` 載入後該平台是未登入，secure storage 沒有殘留 |
| 設定頁的取代 | §6.3 的測試；換檔方法抽出後，還原的既有測試照舊通過 |
| 憑證的往返 | `CredentialStore.writeImported` 寫入 → 真的 `CredentialStore` 載入 → 帳號與憑證成對 |
| JSON 備份 | v1、v2、v4、v5 各一份手寫的合成檔（含沒升版就加的鍵、缺鍵、v3 以前的六個每源鍵）→ snapshot |
| 舊憑證（Windows） | 單元（Linux，假的解密）：缺鍵、壞 JSON、解密失敗 → 結果與「檔案不變」；整合（CI 的 Windows job）：以 `CryptProtectData` 加密合成 JSON → 讀回 |
| 舊憑證（Android） | `research/android-credentials-compat.md` 的實測；單元測試只測選項（`resetOnError: false`、`migrateOnAlgorithmChange: false`、無 namespace）與「沒有舊 prefs 檔就不建立實例」 |
| 啟動流程 | widget 測試：`LegacyImportApp` 的進度、失敗頁三個按鈕、空白啟動後不再自動匯入（`fmp.db` 存在）；結果對話框出現一次 |
| 設定頁 | widget 測試：兩種匯入的確認框（JSON 那個寫明佇列會清空）、沒有紀錄時的提示 |
| dev 入口 | prod 不讀參數與環境變數；資料夾在真實舊位置時拒絕 |
| lint | `lib/main.dart` 可 import `lib/legacy_import/`；`lib/app/x.dart` 仍不行（雙向變異）；`win32`、`ffi` 只准 `lib/platform` |
| schema v19 | 照 `.trellis/spec/app/data/index.md` § 改 schema（快照、升級測試、新庫有表）；`backup_format_test.dart` 的歸類 |

測試裡開 Isar：`test/flutter_test_config.dart` 以絕對路徑載入 `isar_community_flutter_libs` 附的 `libisar.dll`／`libisar.so`（`Isar.initializeIsarCore(libraries: {Abi.windowsX64: …})`，key 是 `dart:ffi` 的 `Abi`；不下載），找不到就拋錯（同 QuickJS 的做法）。探針證實可行（`research/isar-copy-spike.md`）。

## 10. ADR 與文件

| 位置 | 改動 | PR |
|---|---|---|
| ADR 0010 §決定 4 | 補充（2026-10-22，M5 規劃）：舊憑證以 11.2.0 的舊設定實例（Android）與唯讀的 DPAPI 解密（Windows）讀，不用 10.x（§0.1）；舊資料庫先複製再開副本（§0.3）；自動匯入的條件（§3.1）；`lib/main.dart` 是唯一能 import `legacy_import` 的外部檔（§0.2）；匯入紀錄與歌單對照表（§6.4）；舊版匯入＝取代音樂庫、保留插件與登入（§11 第 6 條）；M6–M8 各自補匯、「刪除舊版資料」移到 M9（§1.2、§7.4） | 0 |
| ADR 0010 後果 | 「唯一依賴 `flutter_secure_storage` 10.x」改指上一條 | 0 |
| ADR 0012 §決定 3 | 補充：「以 10.x 讀入」改見 ADR 0010 的 M5 補充 | 0 |
| ADR 0029 | 更正：Windows 是 DPAPI 加密的單一 JSON 檔（`flutter_secure_storage.dat`），不是 AES-GCM＋Credential Manager；prod 的新舊 App 共用這個檔；套件解不開時會刪整個檔（記為已知風險，沒有 repro 不修） | 0 |
| ADR 0034「之後要注意」 | M5 的決定：舊資料另有入口「從舊版匯入…」，不走還原的 `carryOver`；共用自動備份與換檔 | 0 |
| `app/lib/platform/secure_storage/flutter_secure_storage_adapter.dart` 的 docstring | Windows 描述同 ADR 0029 更正 | 4 |
| `app/AGENTS.md` | 新節「舊資料匯入」：分層與 lint 例外、先複製再開、憑證的唯讀讀法、B 站單 P 的鍵、`--fmp-legacy-dir`、M6–M8 補匯的接點；§ 資料層加 `legacy_imports`、`legacy_playlist_ids` | 各 PR |
| `milestones.md` § M5、§ M9 | M5：狀態、範圍（加設定頁從舊版匯入與 dev 入口）、驗收證據的路徑；M9：範圍加「刪除舊版資料」 | 0、驗收 |
| `fmp-plugins` README | 「宿主的依賴」：`playlistFromUrl` 的輸出形狀與 B 站單 P 不帶 cid，FMP 的舊資料匯入依賴這兩點 | 3 |
| verify-on-device `references/runtime-state.md` | `--fmp-legacy-dir` 的帶法（Windows、Android） | 6 |

## 11. 確認清單

| # | 決定 | 建議 | 換一個選擇的代價 |
|---|---|---|---|
| 1 | M5 的匯入範圍 | §1.1：歌單、曲目、歷史、佇列、電台、有落腳處的設定、帳號與憑證、外部匯入來源（格式相同的）；下載、歌詞、桌面設定由 M6–M8 從保留的舊資料補匯（§1.2） | 若要 M5 一次匯完，得先替下載、歌詞、桌面建表，等於把 M6–M8 的資料層提前 |
| 2 | 新版沒有落腳處的舊設定 | 不匯入，在結果對話框列出：主色、字型、每音源串流優先、快取上限、首頁排行的順序與停用、側欄展開（§1.3） | 若要保留主色與字型，得先在新版加這兩個設定（UI 與主題），屬功能增補 |
| 3 | 搜尋歷史 | 新版沒有這個功能（重寫時漏了，不在任何里程碑；你的舊庫有 2 筆）。M5 不匯入；另開 issue 讓你決定要不要補功能，補的話從保留的舊庫匯入 | 若 M5 一起補，要加表、搜尋頁的歷史 UI 與刪除，約一個 PR |
| 4 | 認不出來源網址的平台歌單 | 轉成本機歌單、保留曲目，結果裡列出張數（你唯一的一張 B 站收藏夾認得出來） | 改成略過會丟掉歌單裡的曲目 |
| 5 | 設定值的換算 | 只寫舊版改過的值；不在選項內取最接近的，歷史上限取不小於舊值的選項；`browse_as_logged_in` 三個音源都照舊值；舊庫 `schemaVersion < 4` 時先補做舊版的 migration 再換算（§4.1、§5.9） | 改成全部照寫，之後新版改預設時這些值不會跟著變 |
| 6 | 設定頁「從舊版匯入」的語意（資料庫與 JSON 備份相同） | 取代歌單、曲目、歷史、佇列、電台與舊版有的設定；保留已安裝的插件、插件設定、排行設定與這台的登入；先自動備份；不做合併（§6.3） | 取代會丟掉新版裡建的歌單、外部匯入的配對結果與目前的佇列（JSON 備份沒有佇列，取代後是空的）。合併則要重做舊版的去重規則、處理與新資料的衝突，複雜度與風險都高 |
| 7 | 入口與刪除 | 設定頁「備份與還原」區加「從舊版匯入…」（選舊版資料庫或舊版備份檔）；**「刪除舊版資料」移到 M9**（§7.4） | 留在 M5 的話，M6–M8 補匯前就可能刪掉舊資料庫，下載紀錄、歌詞配對、快捷鍵就匯不回來 |
| 8 | 首次啟動 | 沒有 `fmp.db` 且找到舊資料庫就自動匯入；進度畫面；失敗頁三個按鈕；成功後結果對話框一次，提示以首次引導安裝音源（不自動安裝） | 改成先問「要不要匯入」多一步；自動安裝插件要連網與安裝確認（ADR 0030 §8），不適合在啟動前做 |
| 9 | 設定頁匯入時的登入 | 保留這台目前的登入；舊憑證只補目前沒登入的平台 | 改成以舊憑證覆蓋，會把這台在新版重新登入過的帳號換回舊 cookie |
| 10 | 驗收 | Windows：你的資料庫與憑證檔複製到暫存目錄，dev `--fmp-legacy-dir` 完整匯入、比對筆數，B 站與網易各一次帳號資訊請求確認登入（真實，共 2 個）；Android：只匯入資料庫副本；副本驗收後刪除，Windows 的 dev 資料留給你日常試用 | 真實憑證同時在舊版與 dev 用時，B 站換 cookie 後另一邊會被登出，要重新登入一次（§8.2）。不想要的話，Windows 改成只匯入資料庫、dev 的帳號另外登入，憑證匯入就只有合成資料的測試 |
| 11 | Windows 的舊憑證讀法 | 自己以 `win32` 的 `CryptUnprotectData` 唯讀解開（約 40 行，新增 `win32`、`ffi` 兩個直接依賴；真的解密只在 CI 的 Windows 整合 job 測） | 研究 S 原本建議經套件讀並先備份 `.dat`。但套件只讀 app-support 的那一個檔，dev 要讀副本就得蓋掉 dev 自己的 `.dat`；套件解不開時還會刪檔，要靠備份還原。自己讀是唯讀的，不需要這兩步 |
| 12 | B 站單 P 曲目的鍵 | 去掉舊版補上的 cid，與新插件的兩段鍵一致（§5.1；你的舊庫有 9 首） | 照原樣的話，同一首歌在新版有兩個鍵：搜尋結果對不上已在歌單裡的那首，收藏夾第一次完整刷新會刪掉再重加匯入的項目 |

## 12. 風險

| 風險 | 處理 |
|---|---|
| 舊庫的 schema 與複製的模型對不上（schema id 由名稱雜湊） | 探針已以擁有者資料副本開成功（`research/isar-copy-spike.md`）；§9 的凍結閘門；開副本，壞了也只壞副本 |
| 舊版從 v1.9.x 以前直接跳來的 Android 使用者讀不到憑證 | 標「需要重新登入」（ADR 0010 允許）；發行說明寫明（M9） |
| Windows 上新 App 自己的 `CredentialStore` 經套件載入共用的 `.dat`，解不開時套件刪檔（舊憑證一起沒了） | 首次匯入在 `runApp` 之前、`CredentialStore` 載入之前完成；ADR 0029 更正並記為已知風險；沒有 repro 不改套件行為 |
| 網址辨識、B 站單 P 的鍵與插件漂移 | 表格測試註明插件版本；`fmp-plugins` README 記「宿主的依賴」；認不出時退成本機歌單，不會壞資料 |
| 擁有者的舊版仍在使用，副本與之後的舊庫不同 | 驗收用當天的副本；之後重新匯入走設定頁 |
| 大資料量（一萬筆歷史、一萬首佇列）匯入太久 | 一個 transaction 批次寫；PR 2 以合成的一萬筆量時間寫進 PR 描述 |
| 進度畫面期間被結束 | `legacy-import/` 的工作目錄與暫存檔在下次啟動清掉；`fmp.db` 只在最後 rename 才出現 |
| schema v19 不能降版 | v19 只加兩張新表；PR 2 合併後要 revert 就另寫一個 v20 刪表的 migration（同其他 schema PR） |
