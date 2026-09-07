# 03 — 資料層、狀態管理、平台與授權審查

- **審查日期**：2026-09-01
- **HEAD**：`754411eb`（`git status --short` 空，本輪未修改任何專案檔案；所有實驗都在 scratchpad 的獨立探針套件內進行）
- **範圍**：F（資料層與狀態管理）＋ G（平台、建置、發布、授權）＋ 補充面向 ＋ issue #35 / #39 / #44
- **環境**：Flutter 3.47.1 stable（revision `6655482ec0`, 2026-08-19）/ Dart 3.13.1 / Windows 11 主機。本輪以讀碼與查證為主，未動模擬器。
- **本輪只做審查與規劃**：未改碼、未刪文檔、未動 git 歷史、未關 issue。

> 標記約定：**【事實】**＝有 `file:line`、指令輸出或查證來源佐證；**【推論】**＝由事實推導；**【建議】**＝行動提案，附成本（S/M/L）、風險、可逆性；**【未驗證】**＝查不到或被阻塞。

---

## 目錄

1. [摘要](#摘要)
2. [現況：資料層](#1-現況資料層)
3. [現況：狀態管理](#2-現況狀態管理)
4. [現況：憑證與 auth 邊界](#3-現況憑證與-auth-邊界)
5. [現況：平台、建置、發布](#4-現況平台建置發布)
6. [現況：授權](#5-現況授權)
7. [補充面向](#6-補充面向)
8. [問題清單 P0–P3](#7-問題清單-p0p3)
9. [成熟做法對照](#8-成熟做法對照)
10. [建議方案](#9-建議方案)
11. [重寫 vs 漸進重構](#10-重寫-vs-漸進重構)
12. [需要你決策的點](#11-需要你決策的點)
13. [Quick wins](#12-quick-wins)
14. [issue #35 / #39 / #44 的裁決](#13-issue-35--39--44-的裁決)
15. [驗證記錄](#14-驗證記錄)

---

## 摘要

**0.（最重要）issue #44 的遷移步驟照著做會在第一步就失敗 —— 我在 scratchpad 用獨立探針套件實測了。**

issue #44 寫的三步驟是「換三個 pubspec 條目 → 85 檔機械替換 import → 重跑 build_runner」。實際跑 `flutter pub get`：

```
Because isar_community_generator >=3.3.1 depends on build ^4.0.0 and
slang_build_runner <4.8.0 depends on build ^2.2.1, isar_community_generator
>=3.3.1 is incompatible with slang_build_runner <4.8.0.
So, because resolve_probe depends on both isar_community_generator ^3.3.2 and
slang_build_runner ^3.31.0, version solving failed.
```

**遷移到 `isar_community` 的最小可行條件是「isar_community + slang 3.x → 4.x 大版本升級」兩件事一起做**，而 slang 4.0 有自己的 breaking changes。這一條 issue #44 完全沒寫。實測配方見 §14.2，slang 4 的實跑結果見 §6.4。

**訂正一條我上一版寫錯的**：我原本把「`supportedLocales` 移除」列為 breaking change。實測顯示 slang 4 移除的只是 **`LocaleSettings` 上那個已標 `@Deprecated` 的別名**（slang 3 `strings.g.dart:115-118` 就已經標了 deprecated）；正式的 `AppLocaleUtils.supportedLocales` 在 slang 4 仍然存在（探針生成檔 `:196`）。**FMP 用的正是後者**（`app.dart:46,71,128`），所以這三處不受影響。實際受影響的只有 §6.4 列出的那 4 個 `setLocale` / `useDeviceLocale` 呼叫點。

**1. 但這件事的價值遠比 issue #44 說的大 —— `isar_generator` 3.1.0 是整個 build 生態的天花板，而且它擋住了 Riverpod 3。**

`isar_generator 3.1.0+1` 的約束是 `analyzer: ">=4.6.0 <6.0.0"`（pub cache 原文）。結果整個專案被釘在 **analyzer 5.13.0 / build 2.4.1 / source_gen 1.5.0 / dart_style 2.3.2**，而目前 analyzer 最新是 14.1.0。`dart pub outdated` 的 **Resolvable 欄位**（＝「就算你改 pubspec 也拿不到更新」）證實了這點：analyzer、build、source_gen、dart_style、build_runner 全部 Resolvable = 現行版。`build_resolvers` 與 `build_runner_core` 的最新版更已標記 **(discontinued)**。

更關鍵的是：我實測 `riverpod_annotation ^3.0.0` + 現行 `isar_generator` 直接 **version solving failed**，pub 的結論句是「isar_generator >=3.0.1 is incompatible with build_runner >=2.4.10」。**換掉 Isar 是升 Riverpod 3 的前置條件**，不是兩件獨立的事。換完之後 analyzer 跳到 10.2.0，riverpod 拿得到 3.4.2（見 §14.2 的四組探針）。

**2. `Isar.open(maxSizeMiB: 64)` 把上限設成官方預設的 1/16，而全庫沒有任何一行處理「寫不進去」。**

`database_provider.dart:299` 是 `maxSizeMiB: 64`；Isar 3.1 的預設是 `Isar.defaultMaxSizeMiB = 1024`（`isar-3.1.0+1/lib/src/isar.dart:33`）。`rg "maxSizeMiB|Database full|IsarError"` 在 `lib/` 與 `test/` 的命中只有那一行設定本身 —— **沒有 catch、沒有告警、沒有測試**。同時 `PlayHistory` 沒有任何自動保留策略（`play_history_repository.dart` 只有手動 `deleteHistory`/`clearAllHistory`），`Track` 也不會自動清。這是一顆會隨使用時間長度自己引爆的雷。你這台機器上的 DB 目前是 5,242,880 bytes（5 MiB），離 64 MiB 還遠，所以還沒炸。

**3. 「migration」不是 migration，是每次啟動跑一遍的「值長得不對就改掉」啟發式。**

全庫搜不到 `schemaVersion` / `dbVersion` / `databaseVersion`（0 命中）。`_migrateDatabase()`（`database_provider.dart:212-214`）只呼叫 `initializeDatabaseDefaults()`，內容是一長串 `if (settings.maxCacheSizeMB < 1) { ... }` 這類範圍修復，加上兩個**靠資料形狀猜版本**的判斷式：`_hasLegacyPlaybackAndLyricsDefaultsSignature`（`:31-38`，要求 5 個欄位同時長得像預設值才認定是舊資料）與 `_hasLegacyQueueVolumeSignature`（`:40-52`）。

對照之下，**備份格式反而有版本號**：`kBackupVersion = 2`（`backup_service.dart:23`）＋ 匯入時的前向相容閘門（`:298-301` 拒絕更新的版本）。同一個 codebase 裡，離線檔案格式的版本治理比資料庫本體嚴謹 —— 這個不對稱本身就是訊號。

**4. repository 邊界沒有真的把 Isar 關住 —— `lib/` 裡有 152 個直接碰 Isar 實例的呼叫點落在 repository 之外。**

`rg "\bisar\.[a-z]|_isar\.[a-z]"` 排除 `lib/data/repositories/`、`lib/data/models/` 與生成碼後，共 **152 個呼叫點、15 個檔案**。最重的三個：`playlist_mutation_service.dart`（39）、`backup_service.dart`（36）、`data_integrity_service.dart`（20）。連 `lib/main.dart` 都有一處。這個數字直接決定了「換成 drift / objectbox」的成本量級 —— 不是改 11 個 repository，是改 26 個檔案加 40 個測試檔。

**5. `CONTEXT.md` 已經過時，而且是**本輪 HEAD 前一個 commit** 造成的。**

`CONTEXT.md:38` 仍寫「only allowlisted HTTPS Netease media hosts may receive Netease cookies」，`:47` 的範例對話也還在講「Media Request Credentials still have to pass the Netease allowlist」。但 `c09aec10`（`refactor(media): drop the Netease media credential path`，2026-09-01 23:29）已經把整個 allowlist 刪掉了 —— `rg "canAttachNeteaseMediaCredentials"` 全庫 0 命中，`media_handoff.dart` 只剩 67 行。那個 commit 更新了 `lib/data/sources/AGENTS.md` 與 `lib/services/AGENTS.md`，**漏了 `CONTEXT.md`**。

現行政策其實比文檔寫的更嚴格也更好：`SourceHttpPolicy.mediaHeaders(SourceType)` 只吃一個 enum，**簽名層面就塞不進 cookie**。文檔該改成描述這個事實。

**6. 三個 issue 的裁決：#44 保留但描述要補、#39 保留但根因描述錯了、#35 保留但真正的症狀點在別的檔案。另外發現一個沒有 issue 的真實 CI flake（P2-20）。**

- **#44** — 事實核對全對（85 個 `.dart` 檔、3.3.2 於 2026-03-23 發布、上游 `isar/isar` 最後一次 push 是 2025-06-14），但遺漏了 slang 連動升級這個硬條件，也低估了收益（它擋著 Riverpod 3 與整個 analyzer 生態）。
- **#39** — 症狀真實，但機制描述錯了。issue 說是 `isEnabled()` 判斷不精確；實際上 **`isEnabled()` 全庫 0 呼叫**，`state.enabled` 是直接讀 Isar 設定，跟登錄檔完全無關。真正的機制是「沒有任何程式碼會去核對登錄檔」＋「自我修復只在下次手動啟動時才會發生，而依賴自啟的人不會手動啟動」。
- **#35** — 4 個 `read()` 缺 try/catch 屬實（issue 只列了 3 個）。但 issue 猜的「帳號狀態永久 loading」不成立（帳號狀態走 Isar）；真正會卡死的是 `audio_settings_provider.dart:139` 的 `readApiKey()` —— 拋例外會讓音訊設定頁永久轉圈，而那正是 Auth For Play 三個開關所在的頁面。issue 還漏了最可操作的根因：`AndroidManifest.xml` 沒關 `allowBackup`，這正是 `flutter_secure_storage` 9.2.4 README 第 81-85 行點名的觸發條件。

**6b. issue #42 的第二條指控是錯的 —— 備份沒有在搬運那兩個死欄位。**

issue 標題寫「`preferredAudioDevice*` 是死欄位，**但備份仍照樣匯出匯入**」。第一條成立，第二條有三層互相獨立的反證（§13）：`backup_data.dart` 裡**根本沒有這兩個欄位**（grep 零命中）；`backup_service.dart:765-769` 賦值來源是 `currentSettings`（本機值）不是 `settingsBackup`，上一行還寫著 `// 设备相关设置 - 保留当前值`；被引為證據的那個測試，名字就是 `'...preserves device-specific ones'`，測的是相反的事。**備份層對這兩個欄位的處理反而是對的。**
不過那條指控**放在 `RadioStation.note` 上才成立** —— 它是死欄位，而且真的有進備份 DTO。

**6c. 另有 6 個死欄位與 1 個死索引，全是新發現。**

`Settings` 宣告了 6 個自訂色（`settings.dart:121-127`），但只有 `primaryColor` 活著 —— 只有它有轉換 getter、只有它被 `theme_provider.dart:60` 消費；其餘 5 個**連轉換器都沒有，UI 無從寫入**，而且**它們有進備份**，會在使用者之間往返搬運永遠為 null 的值。另外 `Track.sourceKey` 在 getter 上掛了複合索引，但生成的 `sourceKeyEqualTo` **全庫 0 命中** —— 而內容逐字相同的 `groupKey` 沒有索引，卻是 UI 分組實際在用的那一個。**有索引的沒人查、沒索引的大家用。**

**7. GPL-3.0 → MIT 沒有法律障礙，而且比想像中乾淨。**

貢獻者只有一個人（`ivanspwong@gmail.com`，`imoR`/`1morr` 是同一個 email 的兩個 display name），bot 的 54 個 commit 全是 README 下載連結版本號替換。206 個 Dart 依賴逐一讀 pub cache 的 LICENSE，**零 GPL / LGPL**。唯一的 copyleft 風險是 media_kit 在 Windows 動態連結的 `libmpv-2.dll` —— 我直接讀了它的建置腳本：`packages/mpv.cmake` 是 `-Dgpl=false`，`packages/ffmpeg.cmake` 是 `--disable-gpl --disable-nonfree --enable-version3`。**是 LGPL，不是 GPL**，而且是動態連結（`build/windows/x64/runner/Release/libmpv-2.dll` 是獨立檔案）。MIT 可以合法分發，但要補一份目前不存在的 `NOTICE`。

**7b. 但有一個檔案是例外，而且是本輪新發現的：`qq_music_sign.dart`。**

上一版寫「無法排除演算法結構摘自某個具名專案，但即使是 chaunsin 也是 MIT，不構成阻礙」。查完之後這句話對網易雲成立、對 QQ 音樂不成立。`qq_music_sign.dart` 是一支**無可用授權**的社群實作譜系的逐行移植 —— 不只常數相同，連「跳過 t2 先算 t3 的順序」「手寫 base64 的 6 次迴圈 + 第 5 次特判」「連 `=` 都一起漏掉的過濾集」都一致（P1-12）。同一個演算法有一支 **MIT** 的社群實作（`AynaLivePlayer/miaosic`）可以照著重寫，約 30 行。
順帶更正一條事實：README credit 的 `SocialSisterYi/bilibili-API-collect` **不是「無授權」，是 CC BY-NC 4.0** —— 上一版讀到的 `license: null` 是因為該倉庫 2026-01 收到 B 站律師函後被清空、歷史被重寫；貢獻者鏡像保留的 LICENSE 可追到 2020 年（§5.1.1）。

**7c. isar_community 的遷移風險，本輪從「推測很低」變成「實測為零」。**

三件事全部實跑驗證（§14.4）：① 我自己寫 ELF parser 量了 4 個 Android ABI，**現況 isar 3.1.0+1 全是 `0x1000`、isar_community 3.3.2 全是 `0x4000`**，而且 pub 套件裡的 `.so` 與 GitHub release 資產 **SHA-256 逐字節相同**；② `isar_community_generator` 對 11 個 collection 產出的生成碼與現況**逐字相同，只差 `version:` 一行**，**所有 collection 的 schema id hash 完全一致**；③ 拿**真實 DB 的副本**（1,195 首曲目、332 筆播放歷史）用新原生庫**原地開啟成功**，讀得出欄位值，也寫得進去。**零資料遷移。**

**8. 四個直接依賴根本沒被用到。**

`logger`（`AppLogger` 是自己寫的，`rg "package:logger" lib/ test/` **0 命中**）、`uuid`（0）、`intl`（0）、`flutter_reorderable_list`（0）。

---

## 1. 現況：資料層

### 1.1 Isar 使用面全圖【事實】

11 個 `@collection`，持久化屬性數由生成碼的 `CollectionSchema` 權威計算（`sed -n "/CollectionSchema(/,/estimateSize/p" | grep -c "^      id: [0-9]*,"`）：

| Collection | 檔案 | 持久化屬性 | Id 策略 | 索引 |
|---|---|---:|---|---|
| `Settings` | `settings.dart` | **57** | 固定 `Id id = 0`（單例，`:116`） | 無 |
| `Track` | `track.dart` | **30** | autoIncrement（`:55`） | 4 單欄位 + 2 複合（`sourceKey`、`sourcePageKey`） |
| `Playlist` | `playlist.dart` | 22 | autoIncrement（`:9`） | `name`(unique)、`sortOrder` |
| `PlayQueue` | `play_queue.dart` | 18 | autoIncrement（`:20`） | 無 |
| `RadioStation` | `radio_station.dart` | 14 | autoIncrement（`:10`） | `url`(unique) + 4 |
| `DownloadTask` | `download_task.dart` | 13 | autoIncrement（`:26`） | 4 |
| `PlayHistory` | `play_history.dart` | 10 | autoIncrement（`:11`） | 3 |
| `LyricsTitleParseCache` | `lyrics_title_parse_cache.dart` | 9 | autoIncrement（`:7`） | `trackUniqueKey`(unique, replace) |
| `Account` | `account.dart` | 8 | autoIncrement（`:13`） | 無 |
| `LyricsMatch` | `lyrics_match.dart` | 5 | autoIncrement（`:11`） | `trackUniqueKey`(unique, replace) |
| `SearchHistory` | `search_history.dart` | 2 | autoIncrement（`:8`） | `query`、`timestamp` |
| **合計** | | **188** | | |

另有 4 個非持久化 DTO 混在同一目錄：`hotkey_config.dart`、`live_room.dart`、`video_detail.dart`、`models.dart`（barrel）。

**關聯全部手刻。** `IsarLink` / `IsarLinks` 在 `lib/` 與 `test/` **0 命中**；生成碼裡的 `*QueryLinks` extension 全是空的（例：`track.g.dart:4189`）。取而代之的是手寫外鍵：`DownloadTask.trackId`、`Playlist.trackIds: List<int>`、`PlayQueue.trackIds: List<int>`，join 在應用層做。全庫唯一的 `@embedded` 是 `PlaylistDownloadInfo`（`track.dart:26`，3 欄位），透過 `playlistInfoElement(...)` 查詢（7 處）。

**這對遷移是好消息。** 沒有 `IsarLink` 就沒有 Isar 專屬的關聯語意要翻譯；外鍵已經是關聯式的形狀了。

**查詢 API 面窄。** 用到的只有：`where()`（111）、`filter()`（45）、`*EqualTo`（51）、`*Contains`（5）、`anyOf`（5）、`sortBy*`（25）、`offset`/`limit`（14）、`count()`（8）、`and/or/not`（10）、`group`（1）、`between`（1）、`startsWith`（1）。**`sumProperty` / `averageProperty` / `minProperty` / `maxProperty` 全部 0 命中** —— aggregate 只用到 `count()`。沒有用 Isar 的 full-text search。

**交易單純。** `writeTxn` 108 次（lib 71 / test 37），`writeTxnSync` 0，唯讀 `.txn()` 0，sync API 只有一處 `findFirstSync`（`account_provider.dart:225`）。**Isar 全程只在主 isolate**：`Isar.getInstance` 只有 1 處（`database_provider.dart:289`，冪等重用），`copyToFile` 0 次；下載用的 `Isolate.spawn`（`download_service.dart:787`）與各處 `compute()` 都只做檔案系統操作，不碰 Isar。

**響應式訂閱 9 處，其中 3 處沒有任何呼叫方**【事實】：`TrackRepository.watchDownloaded()`（`track_repository.dart:190`）、`RadioRepository.watchById()`（`radio_repository.dart:119`）、`SettingsRepository.watch()`（`settings_repository.dart:42`）—— 含測試在內都查不到呼叫端。

**生成碼 31,651 行對手寫 model 2,518 行，比例 12.6 : 1。** 最誇張的是 `settings.g.dart` 7,402 行 / `settings.dart` 644 行 = 11.5 倍。

### 1.2 開庫與所謂的 migration【事實】

```dart
// lib/providers/database/database_provider.dart:288-303
Future<Isar> openFmpDatabase() async {
  final existing = Isar.getInstance(fmpDatabaseName);
  if (existing != null) return existing;
  final databaseDir = await resolveFmpDatabaseDirectory();
  return Isar.open(
    fmpDatabaseSchemas,
    directory: databaseDir.path,
    name: fmpDatabaseName,
    maxSizeMiB: 64,
    compactOnLaunch: const CompactCondition(
      minFileSize: 8 * 1024 * 1024,
      minRatio: 2.0,
    ),
  );
}
```

三件事值得記錄：

**(a) `maxSizeMiB: 64` 是預設值的 1/16，且無任何溢位處理。** 見摘要第 2 條。

**(b) `fmpDatabaseSchemas` 是從**資料庫檢視器的 UI 目錄**推導出來的。** `database_catalog.dart:145-147`：

```dart
final List<CollectionSchema<dynamic>> fmpDatabaseSchemas = [
  for (final collection in fmpDatabaseCollections) collection.schema,
];
```

而 `fmpDatabaseCollections`（`:52-143`）每一項都同時攜帶 schema、查詢函式、標題／副標題渲染器，以及一組 `DatabaseViewerSection`（設定頁的資料庫檢視器要用的）。**「哪些 collection 會被註冊進 Isar」等同於「哪些 collection 出現在偵錯用的檢視器裡」**。這個檔案還 `import '../../i18n/strings.g.dart'`，讓持久化層的 schema 清單依賴 i18n 生成碼。

【推論】它現在是可運作的（`t.` 只出現在惰性求值的 section 回呼裡，schema 建構時不會碰到），而且確實達成了「單一真相來源」的效果 —— 但方向錯了：應該是 schema 清單驅動檢視器，不是檢視器驅動 schema 清單。新增一個不想暴露在檢視器裡的 collection，現在需要繞過這個結構。

**(c) migration 是啟發式的。** `_migrateDatabase()`（`:212-214`）就是 `initializeDatabaseDefaults()`。內容分三類：

1. **範圍修復** —— `if (settings.maxConcurrentDownloads < 1 || > 5) { = 3 }` 這類，約 10 組（`:64-140`）。冪等，安全。
2. **形狀猜版本** —— `_hasLegacyPlaybackAndLyricsDefaultsSignature(settings)`（`:31-38`）要求 `neteaseStreamPriority.isEmpty && !useNeteaseAuthForPlay && !rememberPlaybackPosition && tempPlayRewindSeconds == 0 && disabledLyricsSources.isEmpty` 同時成立才認定是舊資料。`_hasLegacyQueueVolumeSignature`（`:40-52`）要求 12 個欄位同時是零值。
3. **無條件清表** —— `await isar.lyricsTitleParseCaches.clear();`（`:186`），每次啟動都跑。AI 標題解析快取因此**從不跨啟動存活**。這在 `test/providers/database_migration_test.dart:143` 有測試守著（`'clears AI title parse cache during startup migration'`），所以是刻意的；但它讓這個 collection 本質上是 session cache 而非持久資料，卻仍佔著一個 Isar schema。

【推論】第 2 類是真正的問題。「5 個欄位同時是預設值」既可能是舊資料，也可能是使用者剛好把它們都設回預設。這種判斷式無法被證偽，而且每加一個新欄位就要重新思考一次它的預設值會不會污染既有的簽名。`test/providers/database_migration_test.dart`（414 行、18 個 test）裡有一半在測「重跑兩次不能蓋掉使用者的設定」（`preserves intentional modern playback and lyrics settings`、`preserves intentional NetEase opt-out on repeated migration runs`）—— **測試的存在本身就是在承認這個機制不安全**。

### 1.3 repository 邊界的實際滲透【事實】

11 個 repository（`lib/data/repositories/`，2,081 行）都遵守同一個形狀：建構子拿 `Isar`、存成 private `final Isar _isar`、回傳 domain model 或 `Stream`。**沒有一個 repository 在回傳型別或公開參數裡出現 `QueryBuilder` / `IsarLink` / `IsarCollection`** —— 這一半做對了。

但邊界只擋住了「型別外洩」，沒擋住「直接存取」。排除 `lib/data/repositories/`、`lib/data/models/` 與生成碼後：

| 檔案 | 直接碰 Isar 的呼叫點 |
|---|---:|
| `lib/services/library/playlist_mutation_service.dart` | 39 |
| `lib/services/backup/backup_service.dart` | 36 |
| `lib/services/database/data_integrity_service.dart` | 20 |
| `lib/providers/database/database_catalog.dart` | 12 |
| `lib/services/account/netease_account_service.dart` | 9 |
| `lib/providers/database/database_provider.dart` | 9 |
| `lib/ui/pages/settings/developer_options_page.dart` | 5 |
| `lib/services/account/youtube_account_service.dart` | 5 |
| `lib/services/account/bilibili_account_service.dart` | 5 |
| `lib/services/account/bilibili_favorites_service.dart` | 4 |
| `lib/providers/account/account_provider.dart` | 3 |
| `lib/services/import/import_service.dart` | 2 |
| `lib/ui/pages/settings/database_viewer_page.dart` | 1 |
| `lib/services/library/playlist_service.dart` | 1 |
| `lib/main.dart` | 1 |
| **合計** | **152**（15 檔） |

加上 `import 'package:isar/isar.dart'` 的檔案總數：**85 個 `.dart` 檔**（另有 1 個 markdown 命中，是上一輪報告）。issue #44 寫的「85 個檔案」精確無誤。

【推論】這意味著：`isar_community` 這種 API 相容的 fork，成本是機械式的（85 個 import 行）；但換成 drift / objectbox / sqlite3 這種語意不同的方案，要重寫的是 **11 個 repository（2,081 行）＋ 15 個檔案的 152 個呼叫點 ＋ 40 個測試檔的開庫樣板**，量級差一個數位。

**測試側的重複更嚴重**：40 個測試檔各自複製了一份 `_resolveIsarLibraryPath()`（讀 `.dart_tool/package_config.json` 找 `isar_flutter_libs` 的原生庫路徑，再 `Isar.initializeIsarCore`）。`test/support/` 目錄存在但只放 fake，沒有 Isar helper。換資料庫時這 40 份樣板全要重寫；就算不換，抽成一份 helper 也是零風險的收益。

### 1.4 備份格式【事實】

`lib/services/backup/`（`backup_data.dart` 896 行 + `backup_service.dart` 823 行），純手寫 `toJson`/`fromJson`，不用 code-gen。

```text
BackupData {
  version: int              // kBackupVersion = 2 (backup_service.dart:23)
  exportedAt: ISO8601
  appVersion: string
  playlists / tracks / playHistory / searchHistory / radioStations / lyricsMatches: [...]
  settings?: SettingsBackup  // ~57 欄位鏡射，每欄 fromJson 都有 ?? 預設值
}
```

做對的地方：
- **有版本號與相容性閘門**（`:298-301`）：`version > kBackupVersion` 直接回 `unsupportedVersion`，舊版靠各欄位的 `?? 預設值` 前向相容。
- **不盲目序列化整個 model**：`TrackBackup` 刻意不含 `audioUrl` / `audioUrlExpiry`（易失效）與 `playlistInfo`（本機下載路徑）。
- **`trackKeys` 用 `"sourceType:sourceId[:cid]"` 而非 Isar id**，所以匯入到另一台機器能重新比對。這是正確的做法。
- **不含任何憑證**：`_collectBackupData()` 只讀 7 個 collection，`_isar.accounts` 全檔 0 出現，建構子也沒有注入 secure storage —— 物理上讀不到。

不備份的 collection：`DownloadTask`、`PlayQueue`、`LyricsTitleParseCache`、`Account`。

【推論】備份層的版本治理比資料庫本體嚴謹得多。這給了一條低成本的路：**把備份格式當成事實上的「可攜資料模型」**，換資料庫時用它做匯出／匯入的橋。

---

### 1.5 死欄位與死索引【事實，我逐條複驗】

系統性掃描 11 個 collection 的全部持久化欄位，排除自身定義、`database_catalog.dart`（DB viewer 只是把每個欄位 dump 成字串，不是業務讀取）與 `lib/services/backup/`（備份只是原樣搬運）後，剩餘命中為 0 者即為死欄位。

| # | 項目 | 位置 | 進備份？ |
|---|---|---|---|
| 1 | `Settings.preferredAudioDeviceId` | `settings.dart:197` | ❌（刻意保留本機值，見 §13 的 #42） |
| 2 | `Settings.preferredAudioDeviceName` | `settings.dart:200` | ❌（同上） |
| 3 | `Settings.secondaryColor` | `settings.dart:123` | ✅ |
| 4 | `Settings.backgroundColor` | `settings.dart:124` | ✅ |
| 5 | `Settings.surfaceColor` | `settings.dart:125` | ✅ |
| 6 | `Settings.textColor` | `settings.dart:126` | ✅ |
| 7 | `Settings.cardColor` | `settings.dart:127` | ✅ |
| 8 | `RadioStation.note` | `radio_station.dart:55` | ✅ |
| 9 | `Track.sourceKey` 的複合索引 | `track.dart:279-280` | — |

**5 個自訂色是全新發現。** `settings.dart:121-127` 宣告了 6 個 `int?` 顏色欄位，但只有 `primaryColor` 活著 —— 只有它有 `primaryColorValue` 這組轉換 getter/setter（`settings.dart:322-330`），也只有它被消費（`theme_provider.dart:60,79-80` → `app_theme.dart` 的 `lightTheme({Color? primaryColor, ...})`）。其餘 5 個**連轉換器都沒有，UI 無從寫入**。我用 receiver-limited pattern 複驗（`settings.<name>` / `_settings!.<name>` / `..<name>`，排除 catalog / backup / models）：**5 個全部是 0 個業務讀取點**。

【推論】這是「當初打算做完整主題自訂，只做完主色」的殘留。而且**它們有進備份**，所以會在使用者之間往返搬運永遠為 null 的值。

**`RadioStation.note`** 同理 —— 全部引用只有 `backup_service.dart:200,630`、`backup_data.dart:470` 與 catalog，**沒有任何 UI 能編輯或顯示它**。它是真正「在往返搬運死資料」的那一個。

**`Track.sourceKey` 是死索引。** `track.dart:278-280` 在一個 getter 上掛了複合索引，但生成的 `sourceKeyEqualTo` / `sourceKeyEqualToAnySourceType` 在 `lib/` 與 `test/` **0 命中**（我複驗）。實際被查的是另一個 —— `track_repository.dart:102` 的 `sourcePageKeyEqualToAnyCid`。更荒謬的是 `track.dart:331` 的 `groupKey` 與 `sourceKey` **內容逐字相同**，而 UI 分組（`track_group.dart:39`）用的是**沒有索引**的 `groupKey`。**有索引的沒人查、沒索引的大家用**，每次 `tracks.put()` 都在維護一個從未被查詢的複合索引。

### 1.6 欄位語意一致性【事實 + 推論】

**做得好的三項：**

1. **時長單位在持久化層 4/4 一致** —— 全部毫秒、全部帶 `Ms` 後綴：`Track.durationMs`（`:79`）、`PlayHistory.durationMs`（`:32`）、`PlayQueue.lastPositionMs`（`:29`）、`LyricsMatch.offsetMs`（`:24`）。
2. **時間戳型別 15/15 一致** —— 全部是 `DateTime`，沒有任何 int epoch。
3. **7 個 `@Enumerated` 全用 `EnumType.name` 不用 ordinal** —— 對可讀性與遷移都有利。

**需要修的四項：**

**(a) 平台使用者 ID：4 個名字、2 種型別（最嚴重）**

| 概念 | 欄位 | 型別 | 位置 |
|---|---|---|---|
| B 站 UP 主 | `ownerId` | `int?` | `track.dart:73` |
| YouTube 頻道 | `channelId` | `String?` | `track.dart:76` |
| 歌單擁有者 | `ownerUserId` | `String?` | `playlist.dart:44` |
| 直播主 | `hostUid` | `int?` | `radio_station.dart:29` |
| 帳號使用者 | `userId` | `String?` | `account.dart:20` |

【推論】`Track` 用**兩個欄位**（int + String）表達「作者在平台上的 ID」，因為 B 站是數字、YouTube 是字串；但 `Playlist.ownerUserId`、`base_source.dart:182`、`youtube_source.dart:1536,2106` 都用**一個 `String?` 同時裝兩者**。同一個 repo 對同一個問題給了兩種答案，而 `Track` 的那個更貴 —— 多一個欄位、多一份索引空間、每次判斷要 if/else。

**(b) Track 識別鍵公式重複 7 次，而且它是持久化格式（風險最高）**

`'${sourceType.name}:$sourceId[:$cid]'` 的實作散落在：`track.dart:284-286`（`sourcePageKey`）、`track.dart:334-336`（`uniqueKey`）、`play_history.dart:42-44`（`trackKey`）、`track_repository.dart:27-29`、`play_history_repository.dart:25-27`（內聯）、`backup_data.dart:305-306`、`backup_data.dart:386-387`。兩段式版本（不含 cid）另重複 2 次且逐字相同：`track.dart:280`（`sourceKey`）與 `:331`（`groupKey`）。

【推論】這不只是程式碼重複，**它同時是資料庫外鍵與備份格式**：`LyricsMatch.trackUniqueKey`（`lyrics_match.dart:15`，`@Index(unique: true, replace: true)`）、`LyricsTitleParseCache.trackUniqueKey`（`:10`）、備份 JSON 的 `playlists[].trackKeys`（`backup_data.dart:171`）都是它。**改公式 = 同時破壞資料庫外鍵與所有既有備份檔，而目前沒有任何測試守住這 7 處必須產出相同字串。**

**(c) `VideoPage.duration` 的單位陷阱** —— `video_detail.dart:11` 叫 `duration` 但單位是**秒**（轉換點 `:38` `..durationMs = duration * 1000`），是全 repo 唯一不帶單位後綴又不是毫秒的時長欄位。同檔的 `VideoDetail.durationSeconds`（`:69`）反而有後綴。

**(d) 命名發散（成本低、收益也低）** —— 封面 URL 有 `thumbnailUrl`（3 處）對 `Playlist.coverUrl`（1 處）；排序位置有 `sortOrder`（2 處）對 `DownloadTask.priority`（1 處，語意相同）；時間戳命名有 4 套（`createdAt`/`updatedAt`、`lastXxx`、動詞+`At`、裸 `timestamp`）。

### 1.7 `SourceType` 不是雙軌，是四軌【事實】

上一輪報告提到的「字串雙軌」實際上是四軌：

| 軌 | 表示法 | 位置 |
|---|---|---|
| **1** | `SourceType` enum + `@Enumerated(EnumType.name)` | 7 處。但命名不一致：`Track`/`PlayHistory`/`RadioStation` 叫 `sourceType`，`Account` 叫 **`platform`**（`:16`），`Playlist` 叫 **`importSourceType`**（`:28`） |
| **2** | `int ...Index` + 手寫 switch | 5 個 Settings 欄位（`themeModeIndex:119`、`downloadImageOptionIndex:156`、`audioQualityLevelIndex:181`、`lyricsDisplayModeIndex:211`、`lyricsAiTitleParsingModeIndex:222`），轉換器手寫在 `settings.dart:296-587` |
| **3** | 逗號分隔字串 | 8 個 Settings 欄位（`audioFormatPriority`、`*StreamPriority` × 3、`lyricsSourcePriority`、`disabledLyricsSources`、`homeRankingSourcePriority`、`disabledHomeRankingSources`），解析在 `settings.dart:390-562` |
| **4** | 裸 `String` | `LyricsTitleParseCache.sourceType`（`:12`，**同名欄位，型別卻是 String**）、`LyricsMatch.lyricsSource`（`:19`）、`Track.originalSource`（`:269`）、`DownloadScannerTrack.sourceTypeName`（`:74`）、`LyricsTitleParseCacheRepository.save({required String sourceType})`（`:21`） |

【推論】軌 4 混了**三個不同的域**：音源（`SourceType`）、歌詞源（`lrclib`/`netease`/`qqmusic`）、原平台（`netease`/`qqmusic`/`spotify`）。三者值域重疊（都有 `netease`）卻沒有型別區分，`lyricsSource == 'netease'` 這種比較散落在 `lyrics_provider.dart:155`、`lyrics_auto_match_service.dart:635`。

**兩個靜默的 fallback 是主要風險**【事實】：`backup_service.dart:812-822` 的 `_parseSourceType` 與 `download_scanner.dart:87-90` 的 `SourceType.values.firstWhere` 都在遇到未知值時**靜默 fallback 成 `bilibili`**。而 `settings.dart:83-111` 的兩個 normalize 函式對同樣情境的選擇是**靜默丟棄** —— 同一個 repo 對「未知的 source 字串」給了兩種不同的行為，兩種都不留痕跡。

【推論】若未來加第四個音源，使用者把新版備份匯進舊版，所有新源的 `Track` / `PlayHistory` / `RadioStation` / `Playlist.importSourceType` 會被**靜默改寫成 bilibili**，沒有任何錯誤或警告。

**一個值得記錄的正面對照**【事實】：`settings.dart:75-79` 有一段品質很高的實作與註釋 ——

```dart
/// 單一真相衍生自 [SourceType.values]：新增音源（加 enum 值）後自動同步，
/// 不會因為忘了補 literal 而讓新源 id 被 normalize 靜默丟棄（D4）。
List<String> get homeRankingSourceIds =>
    [for (final SourceType t in SourceType.values) t.name];
```

**這是全 repo 對「字串軌道要跟著 enum 走」最正確的一個處理**，註釋還說明了它解決過的 bug。問題是這個做法只用在一個地方。

### 1.8 repository 層的細節【事實】

10 個 repository（**不是 11 個 —— `Account` 沒有 repository**），2,081 行、134 個方法。主流模式 10/10 遵守：建構子吃 `Isar` 存成 private field（不吃 `Ref`）、回傳 `Future`/`Stream` 的 domain 型別、不 try/catch 讓例外往上拋（僅 4 處 try 且全是「log 後 rethrow」）、寫操作包 `writeTxn`。

**三個最貴的 Isar 洩漏形式全都沒有**【事實】：`IsarLink`/`IsarLinks` 0、非生成碼的 `QueryBuilder` 0、134 個方法沒有一個回傳 Isar 型別或在方法簽名接受 `Isar`。關聯全部以純值表達。**這是本輪最重要的正面發現，它直接決定了換資料庫的成本結構。**

**偏離點：**

**(a) `PlayHistoryRepository` —— 最嚴重，而且是效能問題。** 6 個方法把該由資料庫做的事搬到 Dart 記憶體：`getPlayCount`（`:29-30`）、`getMostPlayed`（`:36`）、`getHistoryStats`（`:220`）、`deleteAllForTrack`（`:197-199`）、`getPlayCountByKey`（`:210-211`）全部是 `playHistorys.where().findAll()` 全表載入再過濾；`queryHistory`（`:302-356`）**只要帶任何 filter 就退化**成全表載入 + Dart 過濾 + 排序 + `sublist` 分頁。

【推論】根因單一：`PlayHistory.trackKey`（`play_history.dart:42-44`）是計算 getter 且**沒有 `@Index()`**。而 `Track.sourcePageKey`（`track.dart:283`）證明 Isar 支援索引 getter —— **同一個 repo 裡一個做了、一個沒做**。加上索引後這 6 個方法可直接改成索引查詢，422 行大概能砍到 250 行內，且無資料遷移。

**(b) 缺 `AccountRepository`。** `Account` 是 `models.dart:5` 匯出的持久化 collection，`lib/data/AGENTS.md` 的表格也列了它，但 `repositories.dart` 沒有對應項。結果是 5 個檔直接碰 `_isar.accounts`。**約 60 行的 `AccountRepository` 能一次消掉 5 個檔的直接存取 —— 這是投報比最高的單一改動。**

**(c) `RadioRepository.reorder`（`:82-92`）逐筆 `put()`**，直接違反 `lib/data/AGENTS.md` 自己寫的「bulk status changes should… call `putAll()` inside one write transaction instead of issuing per-row `put()`」。對照組 `PlaylistRepository.updateSortOrders`（`:70-78`）就是正確寫法。

**(d) `Logging` mixin 只有 3/10 用了，而且在 hot path 做字串插值** —— `track_repository.dart:239-244` 無條件構造 `track.playlistInfo.map(...).join(", ")`，即使 log level 過濾掉也付出構造成本（`:251-275`、`:277-278` 同樣）。

**兩處 Isar 進了公開型別**【事實】：`database_catalog.dart:28` 的 `final CollectionSchema<dynamic> schema;`（Isar 生成型別成為公開 API），與 `database_viewer_page.dart:124` 的 `final Isar isar;`（**資料庫型別成為 Flutter Widget 的建構子欄位**）。

### 1.9 備份層的補充【事實】

上面 §1.4 說「不盲目序列化整個 model」，這裡是具體證據 —— `SettingsBackup` 對 57 個 `Settings` 欄位做了**三層分類**：

| 類別 | 數量 | 處理 | 位置 |
|---|---|---|---|
| 一般設定 | 46 | 從備份匯入 | `backup_service.dart:687-719,739-764` |
| **桌面專屬** | 5 | **僅 `Platform.isWindows` 時從備份套用，否則保留本機值** | `:720-737` |
| **裝置局部** | 3（`customDownloadDir` + 2 個 `preferredAudioDevice*`） | **完全不進備份 DTO，一律保留本機值** | `:765-769` |

外加 `hotkeyConfig` 匯入前過 `_sanitizeHotkeyConfig`（`:798-809`）重新解析驗證、ranking 相關欄位匯出與匯入各正規化一次、`lyricsAi*` 在 DTO 層就做值域正規化（`backup_data.dart:518-528`）。**跨平台差異、裝置局部性、值域驗證三件事都想到了。**

**憑證靠「分開存放」而非「匯出時過濾」**【事實】：`rg -i "cookie|token|credential|apikey|secret|password|secureStorage" lib/services/backup/` **0 命中**。這比過濾清單可靠 —— 新增憑證欄位時不需要記得去更新任何 filter。

**但有兩個缺口：**

**(a) 新增 model 欄位而忘了加進 `SettingsBackup` 會靜默壞掉。**【事實】改**既有**欄位名會 compile error（`backup_service.dart:208-266` 與 `:685-769` 是逐欄位手寫存取，這 500 行樣板唯一的好處就是把 schema 漂移變成編譯期錯誤）。但**新增**欄位沒有任何機制阻止 —— 新欄位不會進備份 JSON，匯入時 `:683` 用 `createBootstrapSettings()..id = 0` 建全新物件，未被賦值的欄位一律是預設值，**使用者的該項設定會靜默遺失**。`test/services/backup/backup_service_test.dart`（803 行、15 個 test）守住了版本閘門、裝置欄位保留、憑證不外洩、v2 往返，**但沒有欄位覆蓋守門**。

專案裡已經有現成範本可抄：`test/ui/pages/settings/database_viewer_page_coverage_test.dart`（158 行）用「讀原始碼 + 正則」守住 DB viewer 的欄位覆蓋。同樣手法套到備份約需 40 行。

**(b) 匯入沒有原子性。**【事實】`importData` 有 **9 次 `writeTxn`**，其中 6 次在逐筆迴圈內（`:423,481,503,561,591,632,665`）。匯入 N 個項目 = N 個交易，**沒有外層交易**。中途失敗會留下半套資料，`ImportResult.errors` 只是收集錯誤繼續跑。

---

## 2. 現況：狀態管理

### 2.1 Provider 盤點【事實】

186 個 provider：`Provider` 111、`StateNotifierProvider` 39、`FutureProvider` 26、`StreamProvider` 7、`StateProvider` 3、`ChangeNotifierProvider` 0。修飾詞：`.autoDispose` 23、`.family` 19。

**`NotifierProvider` / `AsyncNotifierProvider` = 0，`@riverpod` = 0。** 整個可變狀態層 100% 建立在 Riverpod 2 的 legacy `StateNotifier` 家族上（35 個 `extends StateNotifier<...>` 類別），連 Riverpod 2 自己就已經推薦的 `Notifier` 都沒用過。

> **已失效（2026-09-07）**：改寫完成，現況反過來 —— legacy 家族 0，
> `NotifierProvider` 43、`Notifier` 類別 39。開工時的精確數字是
> 40 個 `StateNotifierProvider` ＋ 3 個 `StateProvider` / 36 個類別，
> 不是本行的 39 / 35。見 `05-roadmap.md` §6.12。

**`riverpod_annotation: ^2.6.1` 是死依賴**【事實，我獨立複驗】：`rg "riverpod_annotation|@riverpod" lib/ test/` → **0 命中**；`dev_dependencies` 裡沒有 `riverpod_generator`（`pubspec.yaml:90-98`）；沒有 `build.yaml`。它唯一的作用是把自己拖進依賴圖並多綁一個版本約束 —— 而這個約束**實測會擋住 `flutter_riverpod` 拿到最新的 3.4.2**（見 §14.2 探針 D）。

35 個 provider 定義散落在 `lib/providers/` 之外（`lib/services/audio/audio_provider.dart` 15 個、`lib/services/radio/radio_controller.dart` 7 個…），其中 1 個定義在 `lib/ui/` 底下（`network_status_banner.dart:28`）。

### 2.2 依賴圖【事實 + 推論】

282 條 provider→provider 邊、306 個呼叫點。

入度前五：`databaseProvider`（28）、`settingsRepositoryProvider`（19）、`sourceManagerProvider`（15）、`audioControllerProvider`（13）、`playHistoryRepositoryProvider`（11）。出度前三：`audioControllerProvider`（15）、`lyricsAutoMatchServiceProvider`（11）、`downloadServiceProvider`（10）。

【推論】骨架是健康的收斂樹 —— 入度前七全是基礎設施單例。唯一的雙向樞紐是 `audioControllerProvider`（入度 4、出度 1），這正是上一輪報告已經點名的 3,429 行 god provider。

值得記一筆的不一致：8 個 repository provider 用 `ref.watch(databaseProvider).valueOrNull`（`repository_providers.dart:8,17,26,35,44,54,63,72`），另有 15 處用 `.requireValue` —— **同一個 `FutureProvider` 的「DB 未就緒」處理有兩套策略並存**。

### 2.3 兩個 Riverpod 偵測不到的循環【事實】

Riverpod 只在 `watch` 鏈上拋 `CircularDependencyError`；`read` / `invalidate` 邊不受檢查。兩個循環都通過 `libraryInvalidationCoordinatorProvider`：

**循環 A（2-cycle）**
```
coordinator --invalidate--> playlistDetailProvider
            <----read------
```
- 去邊：`library_invalidation_coordinator.dart:155-156`（`ref.invalidate(playlistDetailProvider(playlistId))`）、`:170-171`/`:177-178`（`ref.exists(...)` + `ref.read(provider.notifier).refreshTracks()`）
- 回邊 4 處：`playlist_provider.dart:435,463,495,523`（我複驗過，`rg "libraryInvalidationCoordinatorProvider" lib/providers/library/playlist_provider.dart` 共 9 行命中）

**循環 B（3-cycle）**
```
coordinator --invalidate--> playlistCoverMapProvider --watch--> playlistListProvider --read--> coordinator
```
- `library_invalidation_coordinator.dart:158`、`playlist_provider.dart:555`、`playlist_provider.dart:105,139,157,171`

【推論】循環 B 有實際重入風險，目前不炸是因為 coordinator 的 `invalidate` 是同步的（延遲重建），且 `playlistListProvider` 由 Isar `watchAll()` 驅動而非由 coordinator 驅動。**靠時序僥倖成立，不是靠結構保證。**

### 2.4 `libraryInvalidationCoordinatorProvider` 是不是設計味【推論】

**是，但協調器本身不是那個味 —— 它是對味道的合理處置。**

協調器（`library_invalidation_coordinator.dart:18-193`）把 9 個失效動作用**函式注入**而非直接持有 `Ref`，所以能完全脫離 Riverpod 單元測試（`test/providers/library_invalidation_coordinator_test.dart` 用 `_InvalidationRecorder`，不需要 `ProviderContainer`）；它有 `ref.exists()` 守衛避免喚醒未載入的 detail，也有 id 去重。這是把不可避免的 imperative 失效**集中並可測試化**的正確做法。

真正的味道在下面兩層：

**(a) 快取層錯位。** `playlistListProvider`（Isar `watchAll()` 驅動，會自己更新）與 `allPlaylistsProvider` / `playlistCoverProvider` / `playlistCoverMapProvider`（`FutureProvider` 一次性快照）**讀同一份 Isar 資料，但只有一條線是 reactive**。協調器存在的根本原因，就是把自動那條發生的變更手動廣播給手動那幾條。最直接的證據：`playlistCoverMapProvider`（定義於 `:552`，`:555` 是 `ref.watch(playlistListProvider).playlists`）**已經**是 reactive 的了，卻同時又被協調器 `invalidate`（`library_invalidation_coordinator.dart:158`）—— 同一個 provider 被 reactive 依賴與 imperative 失效雙重驅動，這正是循環 B 的成因。

**(b) 協調器只覆蓋了三分之一的域。** 全庫 30 處 `ref.invalidate`，協調器內部佔 6 處，其餘 24 處散在 UI 層：
- `settings_backup.dart:326-338` —— 匯入備份後**手動 invalidate 12 個 settings provider**，其中 4 個還包在 `if (Platform.isWindows)` 裡。新增任何一個 settings provider，都要有人記得回來改這段 UI 檔案，編譯器與測試都不會提醒。同一個檔案 `:318` 卻又對 playlist 走協調器 —— 同檔內兩種策略並存。
- `lyrics_search_sheet.dart:167-169` 與 `:193-195` —— 完全相同的三連 `invalidate` 複製貼上兩次。

【推論】結論：協調器成功消滅了 playlist / download 域的散彈式失效（甚至有讀原始碼字串的靜態測試守著，`library_invalidation_coordinator_test.dart:116-135`），但 **settings 域與 lyrics 域原封不動**。這才是要修的地方。

### 2.5 Riverpod 2 → 3 的實際成本【事實】

Riverpod 3.0.0 於 2025-09-10 發布，最新穩定版 3.4.2（2026-07-28），已有 11 個版本。

逐條對照（用 rg 實測改動點）：

| Breaking change | FMP 影響 | 改動點 |
|---|---|---|
| legacy provider 移到 `flutter_riverpod/legacy.dart` | **最大項** | **35 個檔案**需加 import（lib 31 + test 4） |
| `.valueOrNull` → `.value` | 受影響 | **29 處**（我複驗：`rg -c valueOrNull` 總和 = 29） |
| `AutoDispose*` 介面移除 | 受影響 | 4 處型別標註（`selection_mode_app_bar.dart:31,225,253` + 1 測試） |
| `Ref<T>` 泛型移除 | 極小 | 1 處（`import_playlist_provider.dart:56`） |
| `ProviderObserver` 簽名改變 | **不受影響** | `rg ProviderObserver` **0 命中**（我複驗） |
| 錯誤包成 `ProviderException` | 低 | 唯一 provider 內 try/catch 是 `audio_provider.dart:3317-3321`，`catch (_)` 全捕 |
| **自動重試（預設開啟，200ms→6.4s 指數退避）** | **行為變更** | 26 個 `FutureProvider` + 7 個 `StreamProvider` 要逐一決定是否 `retry: (_, __) => null` |
| **離開畫面自動暫停（`TickerMode`）** | **風險最高** | 音樂播放器的 `audioControllerProvider` / `radioControllerProvider` / `connectivityProvider` / `downloadTasksProvider` 必須在 UI 不可見時繼續跑 |
| dispose 後用 `Ref` 拋 `UnmountedRefException` | 受影響 | `rg "ref.mounted"` **0 命中**；10 處 async-body `ref.read` 要檢（尤其 `startup_download_sync_provider.dart:22,24` 與 `playlist_provider.dart:572` 都在 `await` 之後） |

機械式改動小計約 **72 點跨 40 檔**；需逐一判斷的行為點約 43 處跨 25 檔。

測試側衝擊小：約 9 個改動點跨 6 檔；且 `rg "hasError|AsyncError" test/` **0 命中**，所以 auto-retry 不會讓測試超時。

---

## 3. 現況：憑證與 auth 邊界

### 3.1 `CONTEXT.md` 的宣稱逐條驗證

| 宣稱 | 判定 | 證據 |
|---|---|---|
| Source Auth Context 存在且被窄介面消費 | **【符合】** | `source_auth_context.dart:58-101` 切成 4 個窄介面；5 個消費端各自只依賴需要的那個（`stream_resolution_service.dart:95`、`audio_stream_manager.dart:43`、`download_service.dart:63`、`import_service.dart:114`、`track_detail_provider.dart:46`），**沒有一處拿完整 `SourceAuthContext`** |
| Media Request Credentials：只有 allowlist 上的 HTTPS Netease host 收得到 cookie | **【文檔過時】** | allowlist 已在 `c09aec10` 整段刪除。現行 `SourceHttpPolicy.mediaHeaders(SourceType)`（`source_http_policy.dart:39`）**只吃一個 enum，簽名層面塞不進 cookie** —— 政策比文檔更嚴格 |
| redirect 每一跳重算 header | **【符合，但註解過時】** | `download_service.dart:1709` 每跳呼叫 `prepareDownloadHop()`；但 `:1707` 的註解說「根据当前请求 URL 重新计算，避免重定向泄漏凭据」，而 `prepareDownloadHop` 現在根本不看 URL（`media_handoff.dart:58-66` 只用 `sourceType` 和 `rangeStart`） |
| Auth For Play 閘控 5 條路徑 | **【符合】** | `rg "authForPlay("` 全庫只有 5 個呼叫點，與 `CONTEXT.md` 列的五條一一對應，無遺漏無多餘 |
| Auth For Play **不**控制 import / refresh / search | **【符合】** | import 走 `playlistImportAuth(useAuth:)`、refresh 走 per-playlist 的 `Playlist.useAuthForRefresh`（`playlist.dart:47`）；**search 在型別層面就收不到憑證** —— `SearchSource.search()`（`source_capabilities.dart:118-125`）沒有 `authHeaders` 參數 |
| `parseUrl()` / `refreshAudioUrl()` 保持未認證 | **【符合】** | `source_provider.dart:103-110`、`:130-137` 完全不傳 `authHeaders` |

### 3.2 一條真實的繞過路徑【事實】

`lib/ui/pages/debug/youtube_stream_test_page.dart:740-750`（我逐字複驗）：

```dart
final appMediaHeaders = SourceHttpPolicy.mediaHeaders(SourceType.youtube);
final authMediaHeaders = <String, String>{
  ...appMediaHeaders,
  if ((authHeaders['Cookie'] ?? '').isNotEmpty)
    'Cookie': authHeaders['Cookie']!,
};
final headerCases = <String, Map<String, String>>{
  'none': const {},
  'app media': appMediaHeaders,
  'app media + Cookie': authMediaHeaders,
};
```

Stream Resolution Auth 的 Cookie 被手動塞進媒體 CDN 探測請求。**這條路徑在 release build 可達**：`router.dart:257` → `DeveloperOptionsPage` → `developer_options_page.dart:54-64`，開發者選項的解鎖條件是點版本號 7 次（`developer_options_provider.dart:29`），`rg "kDebugMode" lib/ui/pages/debug/ ...` **0 命中**。

【推論】實害有限（目標是 YouTube 自家的 `googlevideo.com`，HTTPS，而且這正是該診斷頁的目的）。但 `mediaHeaders()` 靠簽名建立的邊界被呼叫端手動繞掉了，而守門測試 `test/services/account/source_http_policy_usage_test.dart` 只覆蓋 6 個 account service，涵蓋不到 UI/debug 頁。

### 3.3 憑證儲存【事實】

4 個 secure storage key，17 個讀寫點：

| Key | 內容 |
|---|---|
| `account_bilibili_credentials` | `sessdata`、`biliJct`、`dedeUserId`、`dedeUserIdCkMd5`、`refreshToken` |
| `account_netease_credentials` | `musicU`（效期約 1 年）、`csrf`、`userId` |
| `account_youtube_credentials` | 11 個 Google cookie（`sid`/`hsid`/`ssid`/`apisid`/`sapisid`/`secure1Psid`/`secure3Psid`/…）—— 等於整個 Google 帳號 cookie jar，效期約 2 年 |
| `lyrics_ai_api_key` | 使用者自填的第三方 LLM API Key |

**Options 完全未配置**：`rg "AndroidOptions|IOSOptions|WindowsOptions"` **0 命中**，4 處全是無參數的 `const FlutterSecureStorage()`。這讓 9.2.4 的預設值生效：`encryptedSharedPreferences = false`、`resetOnError = false`（`flutter_secure_storage-9.2.4/lib/options/android_options.dart:14-16`）。

Windows 後端**不是 DPAPI**：`flutter_secure_storage_windows` 3.1.2 用 AES-GCM（CNG）加密，**金鑰存 Windows Credential Manager**，密文寫成 app support dir 下的檔案。【推論】所以可攜資料夾搬到另一台機器／另一個 Windows 帳號時，即使密文檔案跟著走，Credential Manager 裡的金鑰也不在 —— 解密必然失敗。比 DPAPI 更不可攜。

**Isar 的 `Account` collection 不含任何 cookie/token**（`account.dart:12-38`，只有 `platform`/`userId`/`userName`/`avatarUrl`/`isLoggedIn`/`lastRefreshed`/`loginAt`/`isVip`），註解與實作一致。`SharedPreferences` / `Hive` 全庫 0 使用。備份不含憑證（見 §1.4）。

**Log 遮蔽完整**：`logger.dart:133-159` 的 `redactSensitive()` 對 `message` 與 `error` 都套用，4 個結構化 pattern（`Authorization` / `SAPISIDHASH` / `Bearer` / `Cookie`）+ 25 個逐字 key（含 `SESSDATA`、`MUSIC_U`、`bili_jct`、`__csrf`、`DedeUserID`、`refresh_token`、`access_token` 與全部 11 個 Google cookie 名）。唯一理論缺口是裸 `csrf` / `csrf_token`（目前唯一使用點是空值，無實害）。`rg "\bprint\("` 對 `lib/` **0 命中**，`rg LogInterceptor` **0 命中**。唯一繞過中央遮蔽的是上面那個 debug 頁的私有 `_log()`（`:825-833`）。

**WebView 登入**：三個登入頁 URL 全部寫死官方網域（`passport.bilibili.com/login`、`music.163.com/#/login`、`accounts.google.com/ServiceLogin?service=youtube...`）。Bilibili / Netease 用**名稱白名單**只挑必要 cookie；**YouTube 整包撈**（`youtube_login_page.dart:130-132`），但持久化層有白名單只落地 11 個欄位。三頁都有 `_cleanupWebView()`；但**只有 YouTube 的 `logout()` 會清 WebView cookie**，Bilibili / Netease 的 logout 只清 secure storage 與 Isar。`rg "shouldOverrideUrlLoading|NavigationActionPolicy"` **0 命中** —— 沒有導覽攔截。

---

## 4. 現況：平台、建置、發布

### 4.1 平台現況【事實】

專案根目錄只有 `android/`（26 個 tracked 檔）與 `windows/`（15 個 tracked 檔），**沒有 `linux/` / `macos/` / `ios/` / `web/` 目錄**（`git ls-files` 各為 0）。兩個平台目錄的內容都是 `flutter create` 標準模板，沒有額外的第三方原始碼。

但 `lib/` 裡已經有 21 處指向不存在平台的分支：`Platform.isIOS` 10、`Platform.isLinux` 6、`Platform.isMacOS` 5（對照 `Platform.isWindows` 50、`Platform.isAndroid` 33）。`main.dart:123` 有一條 `Linux/macOS` 的 `_initializeWindowManager()` 路徑，`database_provider.dart:20` 的 `_isMobilePlatform()` 包含 `Platform.isIOS`。【推論】這些是「先寫好等平台開通」的預留分支，目前一行都跑不到 —— 它們既不是資產也不是負債，但會讓「還缺什麼」的判斷失真，因為看起來已經支援了。

### 4.2 CI【事實】

`.github/workflows/ci.yml`：`FLUTTER_VERSION: '3.47.1'`（與本機一致，零落差）、Java 17、actions 全部 SHA 釘選、`permissions: contents: read`。三個 job：

| Job | 內容 |
|---|---|
| `validate`（ubuntu, 15min） | `pub get` → **`dart format --output=none --set-exit-if-changed lib test`**（`:49`）→ `build_runner build` → `dart run slang` → **`flutter analyze`**（`:58`）→ **`flutter test --coverage --exclude-tags live`**（`:64`）→ 上傳 lcov artifact（14 天） |
| `build-android`（needs validate, 20min） | `flutter build apk --release --target-platform android-arm64`（純煙霧測試，不簽章） |
| `build-windows`（**windows-2022**, 20min） | `flutter build windows --release` |

`dart format` 刻意排在 codegen **之前**（此時 `*.g.dart` 因 gitignore 還不存在）。Windows runner 釘 `windows-2022` 而非 `windows-latest`，理由記在 `docs/build-and-release.md`：`flutter_inappwebview_windows 0.6.0` 在 VS2026/MSVC 14.51 下因 `<experimental/coroutine>` 棄用檢查會建置失敗。

**覆蓋率有收集但沒有門檻**，也沒接 Codecov 做 PR diff coverage —— lcov 只是存成 artifact，要看得自己下載。

**issue #38 的判斷正確，但問題已經修掉了**【事實】：`.gitignore:29` 確實有 `*.g.dart`，`git ls-files 'lib/**/*.g.dart'` 回傳 **0**，所以「Verify generated files are committed」的 `git diff --exit-code` 結構性不可能失敗。但 `rg "Verify generated|git diff --exit-code" .github/workflows/` 現在 **0 命中** —— 該步驟已在 `ce100d32`（`ci: delete a check that could not fail, and pin the actions`，2026-09-01 11:00，`git merge-base --is-ancestor ce100d32 HEAD` = YES）被移除，並用 `dart format --set-exit-if-changed` 取代。**issue #38 已過時但仍 OPEN。**

### 4.3 Release【事實】

`.github/workflows/release.yml`：tag `v*` 觸發或手動指定既有 tag（`prepare` job 會 `git rev-parse --verify` 確認 tag 存在，格式必須 `^v[0-9]+\.[0-9]+\.[0-9]+$`）。

- **版本號單一真相來源是 tag**：`versionCode = major*1000000 + minor*1000 + patch`，build job 用 `sed`（bash）/正則（PowerShell）覆寫 `pubspec.yaml` 的 `version:` 行。repo 裡的版本號平常不需要手動同步。
- **Android APK 分 4 個 ABI**（`arm64-v8a` / `armeabi-v7a` / `x86_64` / `universal`），另有 `fmp-latest-android-universal.apk` 穩定連結。
- **Windows 出 ZIP（免安裝）+ InnoSetup Installer**，各有 `latest` 別名。
- **簽章：Android 有**（4 個 repo secret，缺一即 `exit 1`）；**Windows 完全沒有 code signing**（`rg "signtool" .github/workflows/release.yml` 0 命中）→ SmartScreen 會出現未知發布者警告。
- **SHA-256 checksum manifest**：`fmp-vX.Y.Z-checksums.sha256`（`release.yml:370-375`），供 app 內更新驗證。
- **有一個防迴歸閘門值得記錄**：Windows installer 產出後有「Verify ISS patch applied (F8 regression gate)」步驟，專門防禦 `inno_bundle` 上游輸出格式變動導致 CI 的 regex 修補靜默 no-op。

**發布節奏**：最新 release 是 **v1.9.1（2026-07-16）**，距今 **47 天**，期間 main 持續有 `fix(audio)` / `refactor(sources)` / `refactor(media)` 合入。【推論】app 內的更新檢查打的是 GitHub Releases API，所以這 47 天對使用者而言是靜默過期的。

### 4.4 App 內更新機制【事實】

`lib/services/update/update_service.dart`：

- **只在使用者手動觸發**（`checkForUpdate()` 全 repo 只有 `settings_about.dart:74` 一個呼叫端，沒有 Timer、沒有啟動時檢查）。
- **雙層完整性校驗**：優先抓 `checksums.sha256` manifest 做 SHA-256 比對（`:794-822`）；**manifest 存在但該檔缺 checksum 時直接丟 `UpdateIntegrityException`，不放行**（`:767-776`）。manifest 不存在時退回檔案大小比對（相容舊 tag）。
- **降級攻擊已阻擋**：`_isNewerVersion()`（`:684-703`）只接受嚴格遞增。
- **Zip-slip 防護做對了**：`_safeZipEntryDestination()`（`:355-380`）拒絕 `..`／絕對路徑／磁碟機前綴。
- **Windows 可攜 vs 安裝版分流**：靠 `File('$appDir\unins000.exe').existsSync()`（`:53-58`）判斷；安裝版跑 `/SILENT /DIR=$appDir`（裝回原目錄），可攜版解壓後用 `robocopy` 就地替換，失敗時從備份 `/MIR` 回滾。

**真正的安全缺口**【推論】：checksum manifest 跟 artifact 來自同一個 GitHub Release，所以它防的是傳輸損毀／CDN 篡改，**防不了「發布流程本身被攻陷」**（攻擊者可以同時偽造兩者）。要防這一層需要離線簽章（GPG / minisign 對 manifest 簽名，app 內硬編公鑰），FMP 目前沒有；Windows 的 Authenticode 也沒有。


### 4.5 擴展到 Linux / macOS / iOS 的阻塞盤點

#### 套件平台支援矩陣【事實，pub.dev API 查證；lock 版本取自 `pubspec.lock`】

| 套件 | lock | 最新穩定 | Android | iOS | Linux | macOS | Windows | 備註 |
|---|---|---|:-:|:-:|:-:|:-:|:-:|---|
| `media_kit` | 1.2.6 | 1.2.6 | ✅ | ✅ | ✅ | ✅ | ✅ | 播放核心六平台全支援，需搭配對應平台的 `media_kit_libs_*` |
| `media_kit_libs_windows_audio` | 1.0.9 | 1.0.9 | ❌ | ❌ | ❌ | ❌ | ✅ | **`pubspec.yaml:32` 只有這一個 libs 套件。** 擴平台要換成傘包 `media_kit_libs_audio`，它會自動拉 linux / macos_audio / ios_audio |
| `just_audio` | 0.9.46 | 0.10.6 | ✅ | ✅ | ❌ | ✅ | ❌ | 落後一個 minor。iOS/macOS 原生支援 |
| `audio_service` | 0.18.18 | 0.18.19 | ✅ | ✅ | ❌ | ✅ | ❌ | **無 Linux/Windows**。Linux 要另裝 `audio_service_mpris` 0.2.1（不支援 Seek/Shuffle/Volume/TrackList） |
| `audio_session` | 0.1.25 | 0.2.4 | ✅ | ✅ | ❌ | ✅ | ❌ | 落後一個 major |
| `smtc_windows` | 1.1.0 | 1.1.0 | ❌ | ❌ | ❌ | ❌ | ✅ | Windows-only ffiPlugin（Rust/cargokit）。**無跨平台等價物** |
| `tray_manager` | 0.2.4 | 0.5.3 | ❌ | ❌ | ✅ | ✅ | ✅ | **套件早就支援 Linux/macOS**；限制在 `app.dart:90` 的 `Platform.isWindows` 分支。Linux 需 `libayatana-appindicator` |
| `window_manager` | 0.4.3 | 0.5.2 | ❌ | ❌ | ✅ | ✅ | ✅ | 同上；`main.dart:123` 已對 Linux/macOS 開放 |
| `hotkey_manager` | 0.2.3 | 0.2.3 | ❌ | ❌ | ✅ | ✅ | ✅ | Linux 需 `keybinder-3.0`。近 2 年未更新 |
| `flutter_inappwebview` | 6.1.5 | 6.1.5 | ✅ | ✅ | **❌** | ✅ | ✅ | **沒有 `flutter_inappwebview_linux`** —— Linux 唯一的套件層硬阻塞 |
| `launch_at_startup` | 0.5.1 | 0.5.1 | ❌ | ❌ | ✅ | ⚠️ | ✅ | macOS 要手動整合 `sindresorhus/LaunchAtLogin` Swift Package |
| `desktop_multi_window` | 0.3.0 | 0.3.1 | ❌ | ❌ | ✅ | ✅ | ✅ | 桌面三平台 |
| `isar_flutter_libs` | 3.1.0+1 | 3.1.0+1 | ✅ | ✅ | ✅ | ✅ | ✅ | Linux 二進位**僅 x86_64（無 aarch64）**；macOS 是 universal；iOS 含 arm64 + simulator |
| `flutter_secure_storage` | 9.2.4 | 11.0.0 | ✅ | ✅ | ✅ | ✅ | ✅ | 落後 2 個 major。Linux 走 `libsecret`，需要 keyring daemon 真的在跑 |
| `file_picker` | 8.3.7 | 12.1.3 | ✅ | ✅ | ✅ | ✅ | ✅ | 落後 4 個 major。**Linux 實作是呼叫外部 CLI**（`qarma`/`kdialog`/`zenity`） |
| `open_filex` | 4.7.0 | 4.7.0 | ✅ | ✅ | ❌ | ❌ | ❌ | pub.dev 只標 Android/iOS，但 FMP 在 Windows 上也在用且可跑 |
| `path_provider` | 2.1.5 | 2.1.6 | ✅ | ✅ | ✅ | ✅ | ✅ | federated，五平台齊全 |
| `package_info_plus` | 8.3.1 | 10.2.1 | ✅ | ✅ | ✅ | ✅ | ✅ | 落後 2 個 major |
| `url_launcher` | 6.3.2 | 6.3.2 | ✅ | ✅ | ✅ | ✅ | ✅ | 現有寫法已跨平台正確 |
| `dynamic_color` | 1.8.1 | 2.1.0 | ✅ | **❌** | ✅ | ✅ | ✅ | iOS 無系統取色 API，降級為靜態配色即可，非阻塞 |
| `cached_network_image` | 3.4.1 | 4.0.0 | ✅ | ✅ | ✅ | ✅ | ✅ | 純 Dart |
| `flutter_cache_manager` | 3.4.1 | 3.4.2 | ✅ | ✅ | ✅ | ✅ | ✅ | 依賴 `sqflite`（僅 android/ios/macos），Linux/Windows 退回 JSON 檔索引 |
| `qr_flutter` | 4.1.0 | 4.1.0 | ✅ | ✅ | ✅ | ✅ | ✅ | 純 widget，是 Linux 上 WebView 登入的降級關鍵 |
| `inno_bundle`（dev） | 0.11.2 | 0.12.0 | — | — | — | — | ✅ | Windows-only。Linux 對應 `fastforge`，macOS 對應 `create-dmg` |

#### 好消息：音訊層幾乎不用改【事實，我逐字複驗】

`lib/services/audio/audio_runtime_platform.dart` **現有的程式碼**已經把三個新平台分類好了：

```dart
AudioRuntimePlatform selectAudioRuntimePlatform(String platform) {
  switch (platform.toLowerCase()) {
    case 'android':
    case 'ios':
      return AudioRuntimePlatform.mobile;
    case 'windows':
    case 'linux':
    case 'macos':
      return AudioRuntimePlatform.desktop;
    default:
      return AudioRuntimePlatform.desktop;
  }
}
```

`audio_provider.dart:3266-3273` 的 `audioServiceProvider` 直接吃這個 enum 選 `JustAudioService` 或 `MediaKitAudioService` —— **擴展平台不需要改這段一行**。`main.dart:107` 的 `MediaKit.ensureInitialized()` 判斷已寫 `isWindows || isLinux || isMacOS`，`:120-123` 已有 Linux/macOS 的 `window_manager` 分支。

#### 壞消息：系統整合層全部寫死 Windows【事實】

`lib/core/utils/platform_utils.dart` 有 `isDesktopPlatform`（`isWindows || isMacOS || isLinux`），但只用在約 9 處**純 UI layout 判斷**。所有系統整合功能都繞過它直接寫 `Platform.isWindows`（全庫 `Platform.isWindows` 共 **50 處**）：

| 功能 | 位置 |
|---|---|
| 托盤 / 全域快捷鍵 / 開機自啟 / 自訂標題列 | `app.dart:90-98`、`:157` |
| SMTC 5 個呼叫點 | `audio_provider.dart:409,1645,1729,2856,2897` |
| 關閉視窗最小化到托盤 | `main.dart:181` |
| 桌面歌詞浮動視窗 | `lyrics_window_service.dart:37-54,162`（**底層 `desktop_multi_window` / `window_manager` 本來就支援 Linux/macOS**） |
| 應用內更新 | `update_service.dart:519-527`（非 Android/Windows 直接 `throw UnsupportedError`） |
| 備份還原的 5 個桌面設定欄位 | `backup_service.dart:721-735` |
| 系統字型 fallback | `app_theme.dart:71,97`（非 Windows 一律用 Android 字型名 `sans-serif` 等，Linux/macOS 上不存在） |

另有 21 處指向不存在平台的分支（iOS 10、Linux 6、macOS 5），目前一行都跑不到（P3-5）。`rg "dart\.library"` 在 `lib/` **0 命中** —— 完全沒有條件式匯入；48 個檔案無條件 `import 'dart:io'`，這對 Linux/macOS/iOS 不構成問題（三者都是 `dart:io` 平台），只有 Web 才會變成架構阻塞。

#### 逐平台結論

**Linux —— 硬阻塞 2 個，成本 L（約 14–22 人日）**
1. `flutter_inappwebview` 無 Linux 實作。三個登入頁都用它，而 **YouTube 只有 WebView 一種登入方式**。三個選項：`webview_cef` 0.6.2（體積大）／`desktop_webview_window` 0.3.0（用系統 WebKitGTK，cookie 抽取介面要重寫）／**降級：Linux 版隱藏 YouTube 登入，只提供匿名播放**（成本最低）。Bilibili / Netease 不受影響 —— 兩者已有 QR 登入 tab。
2. 媒體控制無 Linux 方案。要接 `audio_service_mpris` 0.2.1（純 Dart `package:dbus`，不需碰 `linux/my_application.cc`）。
軟阻塞：libmpv 靠系統套件管理器安裝（Flatpak 沙盒要自己從源碼編譯）、`file_picker` 需 zenity/kdialog/qarma、`tray_manager` 需 libayatana-appindicator、`hotkey_manager` 需 keybinder-3.0、`flutter_secure_storage` 需 keyring daemon、isar Linux 二進位僅 x86_64（ARM 不可行）、50 處 `Platform.isWindows` 要逐一分類、`windows/runner/main.cpp` 的單一實例 Mutex 與 multi_window 分流要在 `linux/my_application.cc` 等價重寫。

**macOS —— 套件層硬阻塞 0 個，成本 M（約 8–14 人日）**
FMP 需要的每個功能在 macOS 都有官方實作。真正的門檻是非技術的：需要 Mac 硬體或 macOS CI runner（開發機是 Windows）、Apple Developer Program $99/年（公證資格）。
最大的一塊架構工作是**讓 macOS 也走 `AudioService.init()`**（現在 `main.dart:86-104` 只在 `isAndroid || isIOS` 執行），把 `MediaKitAudioService` 的狀態接到 `FmpAudioHandler` 才能拿到控制中心／媒體鍵。**但不需要寫原生 Swift** —— Harmonoid 的 `macos/Runner/AppDelegate.swift` 只有 6 行、完全沒有 `MPNowPlayingInfoCenter` 程式碼，全交給 Dart 層的 `audio_service`。唯一要碰 Swift 的是 `launch_at_startup` 的手動整合。

**iOS —— 技術上最簡單，政策上幾乎封死，成本 L 且發行通路受限**
技術面：`audio_runtime_platform.dart` 已把 iOS 歸 mobile → `JustAudioService`，`Info.plist` 只需加 `UIBackgroundModes: [audio]`。要拿掉托盤／全域快捷鍵／開機自啟／桌面歌詞視窗／自訂標題列；下載要因應沙盒重做（`MANAGE_EXTERNAL_STORAGE` 無對應物）；應用內更新整段失效。
政策面【事實，App Store Review Guideline 5.2.3 原文】：

> Apps should not facilitate illegal file sharing or include the ability to save, convert, or download media from third-party sources (e.g. Apple Music, YouTube, SoundCloud, Vimeo, etc.) without explicit authorization from those sources.

FMP 三個音源全部是逆向的非公開介面，且下載會把音訊落地存檔 —— 正是這條第一句直接點名的行為。同類專案 **Spotube 從未在 App Store 正式上架**，2025 年初其開發者還收到 Spotify 的 cease-and-desist。可行途徑只剩側載（AltStore/SideStore）或 EU Web Distribution（後者是否規避 5.2.3 內容審查【未驗證】）。

#### 三個成熟專案的做法【事實】

| 專案 | 音訊後端 | 媒體控制 | Linux 打包 |
|---|---|---|---|
| **[Spotube](https://github.com/KRTirtho/spotube)**（六平台） | `media_kit` **全平台統一** | `audio_service`(Android/iOS/macOS/Web) + `audio_service_mpris`(Linux) + **`smtc_windows`(Windows)** | 自寫 Dart CLI 包 `fastforge package --targets=deb,appimage`；另有 Flathub manifest，沙盒內**從源碼編譯 libmpv** |
| **[Harmonoid](https://github.com/harmonoid/harmonoid)**（media_kit 作者本人） | `media_kit` | Linux 用自維護的 `mpris_service`（git 依賴）；**Windows 不用 pub.dev 的 `smtc_windows`，自己寫 win32 FFI 綁定** | libmpv 完全交給發行版套件管理器，`linux/CMakeLists.txt` 沒有任何 mpv 內容 |
| **[Namida](https://github.com/namidaco/namida)** | 行動端自 fork 的 `just_audio` + 桌面 `media_kit`（**與 FMP 現行架構最接近**） | Linux 用第三套 `anni_mpris_service`；托盤自實作 XDG StatusNotifierItem D-Bus | tar.gz + AUR + deb + rpm + Nix，**README 明文要求使用者自行裝 mpv** |

【推論】三個一致的訊號：
1. **媒體工作階段控制沒有單一跨平台套件。** `audio_service` 官方只覆蓋 Android/iOS/macOS/Web，Windows 一定要 `smtc_windows`、Linux 一定要另拼 MPRIS。**FMP 現行「Windows 用 smtc_windows」的架構本身就是業界標準做法的一半，只差 Linux 那一塊。**
2. **Spotube 用的組合與 FMP 現況重疊度最高**（`smtc_windows` + `audio_service`），可以直接沿用其模式補 Linux。
3. **Harmonoid 印證了 FMP 的一個既有決策是對的**：它也因為 `permission_handler_windows` 的問題改用社群 noop fork —— 與 `storage_permission_service.dart` 註解裡「避免把 permission_handler 帶進 Windows 桌面建置」的判斷不謀而合，兩個專案各自踩坑後得出同一結論。
4. Harmonoid 的 `lib/` 底下沒有任何以平台命名的資料夾 —— 平台差異全收斂在套件邊界，應用層維持單一 API 表面。**這正是 FMP 的 `AudioRuntimePlatform` + 兩個 `FmpAudioService` 實作已經在走的模式**，只是系統整合層還沒跟上。

#### 建議順序【推論】

**Linux → macOS → iOS**（若目前沒有 Mac，這是唯一能立即動工的順序）：
1. **Linux 先。** 零硬體與帳號成本；被迫要做的「50 處 `Platform.isWindows` 重新分類」會直接讓 macOS 受益（做完後 macOS 的重構項可壓到 0.5–2 人日）；唯一硬阻塞（YouTube WebView 登入）有低成本降級路徑。
2. **macOS 次之。** 套件層零阻塞，但需要 Mac 硬體 + $99/年，且「讓 `audio_service` 接管媒體控制」這塊在 Linux 階段攤提不到（Linux 走 MPRIS 是另一條路）。
3. **iOS 最後，或不做。** 技術上最簡單，但 5.2.3 讓正規發行路徑基本封死，投報比最差。

> 例外：**若已經有 Mac，順序應對調成 macOS → Linux → iOS** —— macOS 硬阻塞數是 0，`audio_service` 原生支援不需要引入任何第三方 MPRIS 套件，起步門檻反而更低。

---

## 5. 現況：授權

### 5.1 貢獻者【事實】

```
$ git shortlog -sne HEAD
  1033  imoR <ivanspwong@gmail.com>
   278  1morr <ivanspwong@gmail.com>
    54  github-actions[bot] <github-actions[bot]@users.noreply.github.com>
     2  imoR <31556702+1morr@users.noreply.github.com>
```

- `imoR` 與 `1morr` 共用同一個 email；`31556702+1morr@users.noreply.github.com` 是 GitHub 對帳號 ID `31556702`（即 `1morr`）自動產生的 noreply 信箱。**三者是同一個人，共 1,313 個 commit。**
- `git log --format=%B | rg -i 'co-authored-by'` → **空**。沒有隱藏共同作者。
- `github-actions[bot]` 的 54 個 commit 全是 `docs: update download links to vX.Y.Z`，抽查 5 個（`f0ba255a`、`ca330b6b`、`8f0a67af`、`2f9f742d`、`ff9b1c67`）確認 diff 只有 README 下載連結的版本號字串替換。【推論】純機械式資料代入，不構成可受著作權保護的表達，且沒有可徵求同意的實體。
- `rg "SPDX-License-Identifier" lib/ android/ windows/` → **0**；`rg "Adapted from|ported from|Based on" lib/` → **0**。`lib/` 底下沒有任何檔案帶授權標頭或來源出處註解。
- `git ls-files android/ windows/` 全部是 `flutter create` 模板；`windows/flutter/ephemeral/` 下的 Flutter BSD 標頭檔案未被 git 追蹤。

**結論【事實 + 推論】：切換 MIT 只需要 `ivanspwong@gmail.com` 一個人同意。**

#### 5.1.1 協定層加密的來源歸屬【事實 + 推論，本輪補查】

上一版這裡寫的是「無法百分之百排除…但不構成阻礙」。這一輪把它查完了，結論**部分推翻了原來的說法**。

**全 repo 的協定層加密 / 簽名共 5 處**，逐一盤點（`rg` 掃 `lib/`）：

| 位置 | 內容 | 硬編碼常數 | 來源註解 |
|---|---|---|---|
| `lib/core/utils/netease_crypto.dart:51-130` | 網易雲 weapi（雙層 AES-CBC + RSA 無 padding）、eapi（AES-ECB + MD5） | `:18` `0CoJUm6Qyw8W8jud`、`:21` `0102030405060708`、`:24` `e82ckenh8dichen8`、`:31-35` RSA 模數、`:43` `-36cd479b6b5-`、`:75` `nobody${url}use${text}md5forencrypt` | 無 |
| `lib/data/sources/playlist_import/qq_music_sign.dart:48-88` | QQ 音樂 `zzb` 簽名（MD5 → 取位 → XOR 置換 → 手寫 base64） | `:6-23` XOR 表、`:25-26` base64 字母表、`:28-45` hex 表、`:54-55` 兩組索引 | 無 |
| `lib/services/account/bilibili_crypto.dart:14-148` | Bilibili `correspondPath`（RSA-OAEP/SHA-256）+ 手寫 120 行 DER/ASN.1 解析器 | `:29-33` base64 SPKI 公鑰 | 無 |
| `lib/services/account/youtube_credentials.dart:96-102` | `SAPISIDHASH`（SHA-1 拼字串） | 無 | 無 |
| `lib/core/utils/innertube_utils.dart:14,20` | InnerTube API key / client version | `AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8` | **有**（`:10-13`，全 repo 唯一） |

確認**不存在**的項目：Bilibili WBI 簽名（`rg -i "wbi_img|img_key|sub_key|mixinKey|w_rid"` → 0 命中）、YouTube signature / n-param 解密（委派給 `youtube_explode_dart`，BSD-3-Clause）。

**更正一：`SocialSisterYi/bilibili-API-collect` 不是「無授權」，它是 CC BY-NC 4.0。**【事實】
上一版根據 `gh api` 的 `license: null` 判定為「偵測不到授權」。這是**誤讀**：該倉庫在 **2026-01-28 收到 B 站委託律師的警告信後被清空**（README 逐字說明此事），現在 `gh api` 回傳 `{archived: true, license: null, size: 220}`，且**整個 commit 歷史只剩 3 筆**（`4c00347d` / `fb3c3e46` / `0e149e2c`，全部是 2026-01-28~30 的 "deprecated"）—— 歷史被重寫了，所以查不到 LICENSE。
貢獻者的鏡像 [`pskdje/bilibili-API-collect`](https://github.com/pskdje/bilibili-API-collect)（描述自稱「仓库 SocialSisterYi/bilibili-API-collect 的贡献者复刻，基础内容同步在 master 分支于 2026 年 1 月 25 日」，即清空前）保留了完整歷史，其 `LICENSE` 首行逐字為 `Creative Commons Attribution-NonCommercial 4.0 International`，而 **LICENSE 的 commit 可追到 2020-07-31 與 2021-11-14** —— 證明原倉庫自 2020 年起就是 CC BY-NC 4.0。
同理，README Credits 的另一個連結 `Binaryify/NeteaseCloudMusicApi` 也已被清空（`{archived: true, license: null, size: 1}`），它的 `license: null` 同樣是清空造成的假象。**README 目前的兩個 Credits 連結指向的倉庫都已無內容。**

**更正二：`netease_crypto.dart` 確認無風險，但 `qq_music_sign.dart` 不是。**【事實 + 推論】

- **網易雲：無風險。** 常數逐字出自 music.163.com 自己出貨的 `core.js`（多個獨立逆向筆記逐字引用同一段 JS，包含那個非標準排序的 base62 字母表）。與 `Binaryify/NeteaseCloudMusicApi`（歷史 MIT）及 `chaunsin/netease-cloud-music`（MIT）做結構比對後，**沒有任何一行可對映**：對方是通用 `aesEncrypt(text, mode, key, iv, format)` 五參數分派、用 `node-forge` / PEM 做 RSA；FMP 是寫死 CBC 的三參數私有方法、自行 `BigInt.modPow` + 左補零。對方有 `linuxapi` / `eapiReqDecrypt` / 通用 `decrypt`，FMP 全部沒有。**只有「演算法步驟必然相同」，表達方式明顯不同。**
- **Bilibili：建議在 NOTICE 標註，不阻擋 MIT。** 借用的只有公鑰值、明文格式 `refresh_{ts}`、演算法選擇與輸出編碼 —— 全是協定事實。而該文檔提供的六份 Demo（JS/Python/Kotlin/Java/Go/Vercel）**全部用函式庫解析 PEM**，FMP 反而手寫了 120 行 DER 解析器，表達完全獨立。CC 的 BY 條款在此未被觸發，但 README 已有 credit，NOTICE 明確化成本極低。**需另外注意 NC 條款**：若日後商業化且屆時被認為構成衍生，NC 是獨立於 GPL/MIT 之外的限制。
- **QQ 音樂：這是本輪唯一的實質風險，見 P1-12。**

### 5.2 依賴授權【事實】

206 個 hosted 套件逐一讀本機 pub cache 的 `LICENSE` 檔頭：

| 授權 | 概略數量 | 代表 |
|---|---:|---|
| BSD-style（Dart/Flutter authors） | ~90 | `path`, `collection`, `meta`, `path_provider*`, `url_launcher*` |
| MIT | ~75 | `dio`, `riverpod`, `just_audio`, **`media_kit`**, **`media_kit_libs_windows_audio`**, `logger`, `slang*`, `smtc_windows`, `window_manager`, `tray_manager`, `hotkey_manager`, `launch_at_startup`, `pointycastle`, `youtube_explode_dart` |
| Apache-2.0 | ~15 | **`isar`**, `isar_flutter_libs`, `dynamic_color`, `flutter_inappwebview`, `rxdart`, `desktop_multi_window` |
| BSD-2/3（其他作者） | ~15 | `encrypt`, `archive`, `win32*`, `qr_flutter`, `flutter_secure_storage` |
| CC0 | 1 | `simple_icons` |
| **GPL / LGPL / copyleft** | **0** | — |

`pointycastle` 雖是 Bouncy Castle 的 Dart 移植，授權是 **MIT**，不是 Bouncy Castle License，也不是 copyleft。

### 5.3 唯一的 copyleft 面：libmpv / FFmpeg【事實，讀原始建置腳本查證】

`media_kit` 與 `media_kit_libs_windows_audio` 的 Dart 層都是 MIT（pub cache 的 LICENSE 檔頭：`MIT License / Copyright (c) 2021 & onwards Hitesh Kumar Saini`）。但實際播放音訊的是**建置時才下載**的二進位：

```cmake
# media_kit_libs_windows_audio-1.0.9/windows/CMakeLists.txt:69
set(LIBMPV_URL "https://github.com/media-kit/libmpv-win32-audio-build/releases/download/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z")
```

我直接讀了 `media-kit/libmpv-win32-audio-build` 的建置腳本（該 repo 已封存、無 LICENSE 檔）：

| 檔案 | 關鍵 flag | 意義 |
|---|---|---|
| `packages/mpv.cmake` | **`-Dgpl=false`** | mpv 建為 **LGPL-2.1-or-later** 模式，停用所有 GPL-only 功能 |
| `packages/ffmpeg.cmake` | **`--disable-gpl --disable-nonfree --enable-version3`** | 排除所有 GPL-only 元件；`--enable-version3` 使部分元件為 LGPL-3。同時 `--disable-encoders --disable-muxers --disable-programs`，純解碼 |

**結論【事實】：是 LGPL-2.1/3-or-later，不是 GPL。** 而且是**動態連結** —— `build/windows/x64/runner/Release/` 底下 `libmpv-2.dll` 是獨立檔案，不是靜態編進 `fmp.exe`。

Android 側完全不涉及 libmpv（走 `just_audio` → ExoPlayer/Media3，Apache-2.0），所以只有 Windows build 有這個面。

**MIT 專案能不能合法分發含 LGPL 二進位的 build？可以，條件是**【建議】：

1. 維持動態連結（現況已符合，不要改成把 mpv 靜態編進 exe）。
2. 隨 distribution 附 LGPL 全文與該元件的原始碼取得方式（media-kit 的建置腳本 repo 是公開的，附連結即可，不需要自己重新發布 mpv/FFmpeg 原始碼）。
3. 保留 libmpv/FFmpeg 自身的著作權聲明。
4. 不用技術手段阻止使用者反組譯以確認合規（FMP 沒有這類限制）。

以上都不要求 FMP 自己的原始碼變成 LGPL/GPL。

### 5.4 現況的揭露缺口【事實】

`settings_page.dart:184` 有 `showLicensePage(...)`。但這個 Flutter 內建機制只收錄 **pub 套件目錄裡的 `LICENSE` 檔**（例如 `media_kit_libs_windows_audio` 的 MIT），**不會**收錄建置時才下載、動態連結進來的 libmpv/FFmpeg 的 LGPL 授權文字。repo 內 `ls NOTICE THIRD_PARTY*` → **不存在**。

【推論】**這是現況既有的缺口，跟切不切 MIT 無關** —— 即使維持 GPL-3.0，對 LGPL 元件的揭露義務目前也沒有完全滿足。

---

## 6. 補充面向

### 6.1 啟動路徑【事實】

`main()` 到 `runApp()` 之間跨平台恆為 **2 個頂層 `await`** 加 1 個同步初始化：

| 行 | 動作 | try/catch |
|---|---|---|
| `main.dart:50-61` | `FlutterError.onError`（debug 紅屏、release 靜默記 log） | — |
| `:63` | `runZonedGuarded(...)`，`onError` 在 `:146-148` | — |
| `:69` | `await _preloadThemeSettings()` → 內部 `openFmpDatabase()` + 讀 `Settings` | **有**（`:198` 的 `catch (_) {}`，**完全靜默**） |
| `:75-83` | `PaintingBinding.instance.imageCache` 上限（行動 100 張/50MB、桌面 200 張/80MB） | — |
| `:87` / `:114` / `:123` | 平台分支：`AudioService.init()` / `Future.wait([_initializeSmtc(), _initializeWindowManager()])` / `_initializeWindowManager()` | **無** |
| `:108` | `MediaKit.ensureInitialized()`（同步，桌面） | **無** |
| `:137` | `LocaleSettings.useDeviceLocale()` | — |
| `:139-145` | `runApp(ProviderScope(...))` | — |
| `:131-134` | `addPostFrameCallback` 啟動 `RadioRefreshService` | **背景**，不阻塞首幀 |

`app.dart:33-146` 用 `dbAsync.when(loading/error/data)` 三態，帳號檢查、下載同步、自動刷新等都在 `data` 分支 —— 這部分的延後做對了。

**實測【事實，本輪補做】。** `flutter run -d windows --profile --trace-startup --no-resident`，跑 5 次，讀 `build/start_up_info.json`。DB 是真實使用中的資料（**1,195 首曲目、332 筆播放歷史、2 個帳號**，見 §14.4），不是空庫。

| 次 | `timeToFrameworkInit` | `timeToFirstFrame` | `timeAfterFrameworkInit` |
|---|---|---|---|
| 1（建置後首跑，OS 檔案快取冷） | 1,238 ms | **1,827 ms** | 589 ms |
| 2 | 2,088 ms | 2,462 ms | 374 ms |
| 3 | 1,857 ms | 2,308 ms | 451 ms |
| 4 | 1,787 ms | 2,140 ms | 353 ms |
| 5 | 1,717 ms | **2,072 ms** | 355 ms |
| **中位數** | **1,857 ms** | **2,140 ms** | **374 ms** |

`WidgetsFlutterBinding.ensureInitialized()` 在 `main.dart:64`，也就是 `main()` 幾乎最開頭（前面只有 `FlutterError.onError` 的賦值），所以這兩段可以乾淨地切開：

- **`timeToFrameworkInit`（中位數 1.86 s）＝ 引擎 + Dart VM + snapshot 載入**。這段 **FMP 一行程式碼都碰不到**。
- **`timeAfterFrameworkInit`（中位數 374 ms）＝ `main.dart:69-145` 的全部工作 + 首幀 build/layout/paint**。這才是 FMP 自己的部分。

**【推論】這推翻了一個直覺**：`_preloadThemeSettings()` 同步開 Isar、`MediaKit.ensureInitialized()`、SMTC 初始化 —— 這些看起來很重的東西**加起來只佔首幀時間的 17%**。把它們全部搬到首幀之後，最多省 374 ms 中的一部分，而 1.86 s 的引擎啟動一動不動。**啟動時間的優化空間不在 FMP 的 `main()` 裡。**

真正有槓桿的反而是 §6.4 那個 687 KB 的 `strings.g.dart` —— 它會被編進 snapshot，直接墊高 `timeToFrameworkInit`。slang 4 把它拆成每語言一檔並對非基準語言用 `deferred` 載入（見 §6.4），是唯一一個會作用在那 1.86 s 上的改動。**但這個效果本輪未量測**（要實際完成 slang 4 遷移後重跑同一組 `--trace-startup` 才能得出）。

**issue #37 的宣稱【證實】**：`MediaKit.ensureInitialized()` 仍在 `main.dart:108`、仍無 `try/catch`；`_initializeSmtc()`（`:151-156`）與 `_initializeWindowManager()`（`:158-184`）內部也都沒有。任何一個 throw，`runZonedGuarded` 的 `onError` 只 `AppLogger.error('Uncaught async error', ...)` 記一行，**`runApp()` 永遠不會被執行，結果是無視窗、無提示**。而此時 log 只在記憶體（見 §6.3），使用者連 log 頁面都打不開。

`PlatformDispatcher.instance.onError` **0 命中** —— 官方建議的三層錯誤處理只做了兩層。

**`_preloadThemeSettings()` 的 `catch (_) {}` 沒有任何 log**（`:197-199`）。開庫第一次失敗完全不可見，要等 `databaseProvider` 再失敗一次才會在 UI 上顯示，而那時看到的是第二次的錯誤。

### 6.2 記憶體【事實】

25 個 `StreamSubscription` 建立點（19 檔）逐一核對，**全部**在對應的 `dispose()` 或明確清理路徑呼叫 `.cancel()`。`addListener` 10 次對 `removeListener` 11 次，逐檔核對全部配對。`AppLogger._logBuffer` 是有界的 `Queue`（500 條上限，超過 `removeFirst()`）。**未找到明確的記憶體洩漏點。** 這一塊做得相當嚴謹。

**實測【事實，本輪補做】。** Windows profile build，啟動後閒置（**未播放任何音訊**）約 5 分鐘，`Get-Process fmp`：

| 指標 | 值 |
|---|---|
| Working Set | **276.3 MB** |
| Private Bytes | **411.8 MB** |
| Peak Working Set | 336.9 MB |
| Handles | 1,412 |
| **Threads** | **223** |

**【推論】兩個值得注意的地方**：

1. **閒置 276 MB / private 412 MB，對一個沒在播放的音樂播放器偏高。** 靜態掃描找不到洩漏（上面那段），所以這不是洩漏，是**常駐佔用**：Flutter 引擎 + Impeller/ANGLE、libmpv、WebView2、Isar 的 mmap（`maxSizeMiB: 64`）、以及 §6.3 那個 200 張 / 80 MB 的 `imageCache` 上限。**要判斷哪一塊佔大頭需要 heap snapshot（`docs/debugging-with-vm-service.md` §3.2），本輪未做。**
2. **223 個執行緒**是這次量測最意外的數字。Flutter 引擎本身約 5–8 個，其餘來自外掛的原生執行緒池（libmpv 的解碼/網路、WebView2、`desktop_multi_window` 的第二個 engine、Isar）。這個數字本身不一定是問題，但**沒有任何一個既有測試或監控會發現它變成 400**。

### 6.3 圖片快取與日誌【事實】

**圖片這塊是專案做得最好的部分之一。** `rg "Image\.network|Image\.file" lib/` 只有 2 個命中，都是文檔文字（`image_loading_service.dart:31` 的註解與 `lib/ui/AGENTS.md:30` 的規則本身）——**硬規則零違規**。

- 唯一入口 `ImageLoadingService`（`lib/core/services/image_loading_service.dart`）包 `CachedNetworkImage`；本地圖走 `FileImage` + `ResizeImage`（`:312-317`）。
- 縮圖 URL 多檔位降級（`thumbnail_url_utils.dart`）：Bilibili `@{200,400,640,1280}w.jpg`、YouTube `mqdefault`/`maxresdefault`、Netease `?param={100,200,400,800}y{n}`。
- 自訂 `_FmpImageCacheManager`（`network_image_cache_service.dart:431-444`）：`stalePeriod` 7 天、`maxNrOfCacheObjects = (maxCacheSizeMB * 1024 / 100).clamp(100, 3000)`；磁碟上限行動端 16MB、桌面 32MB，使用者可調。另有一層自建的主動 trim（每 30 張檢查一次，或達 90% 立即觸發，用 `compute()` isolate 掃描目錄按最舊優先刪除）。
- **記憶體解碼降採樣做到位**：`memCacheWidth` / `memCacheHeight` 明確設為 `cacheExtent`（`image_loading_service.dart:674-675`）。列表小封面不會用全解析度解碼。
- `maxWidthDiskCache` 刻意只留給 precache 路徑，主顯示路徑移除，理由寫在 `:426-430` 與 `:676-678`（避免 `flutter_cache_manager` 同時存原圖與 PNG 重編碼副本）——**是刻意取捨，不是遺漏**。

**跟成熟專案的對照【事實，本輪補查】：FMP 在這件事上比同類專案更講究，不是更隨便。**

| 專案 | `imageCache.maximumSize` | `imageCache.maximumSizeBytes` | 磁碟快取 |
|---|---|---|---|
| Flutter 預設 | 1000 | 100 MiB | — |
| **Harmonoid** (`lib/main.dart:33-34`) | 1000（＝預設） | **200 MiB**（調**高**） | 自製 `AsyncFileImage`，靜態 `HashMap` 記憶體快取，**無 TTL、無容量上限** |
| **Spotube** | **完全沒碰**（`imageCache` / `maximumSize` / `maximumSizeBytes` / `PaintingBinding` 四個關鍵字 `gh api search/code` 全部 `total_count: 0`） | 同左 | `DefaultCacheManager()` 未傳自訂 `Config`，吃套件預設：**30 天 stale、最多 200 個物件** |
| **FMP** (`main.dart:74-82`) | 行動 100 / 桌面 200 | 行動 50 MB / 桌面 80 MB（調**低**） | `_FmpImageCacheManager`：7 天 stale、上限使用者可調、**外加一層 isolate 主動 trim** |

**FMP 是三者中唯一按平台分開設定、唯一把上限調低於 Flutter 預設、也是唯一有主動 trim 的。** Harmonoid 調高到 200 MiB 是桌面優先的取捨（它主要是本地音樂播放器，封面來自本地檔案）；Spotube 則完全沒管。**§6.2 量到的 276 MB 閒置佔用不能歸咎於 imageCache 設定 —— 這裡的上限比誰都保守。**

**日誌是可觀測性最大的缺口。**

- `AppLogger` 是**自己寫的**（`lib/core/logger.dart`），只 import `flutter/foundation.dart`。`logger: ^2.5.0` 這個依賴 `rg "package:logger" lib/ test/` **0 命中**。
- **log 只在記憶體**（500 條 `Queue` 加一個 broadcast stream）。**沒有寫檔、沒有輪替、沒有崩潰上報**（`rg -i "sentry|crashlytics|bugsnag"` 0 命中）。App 重啟後全部消失。
- 唯一匯出手段是 `log_viewer_page.dart` 的「複製到剪貼簿」（`:87-91`），沒有存檔或分享。
- release 行為：`AppLogger._minLevel = kDebugMode ? debug : info`（`:56`），沒有 `kReleaseMode` 分支。
- 繞過 `AppLogger` 的 `debugPrint` 只有 3 處（`create_playlist_dialog.dart:386`、`play_history_page.dart:264`、`youtube_stream_test_page.dart:826`）。

【推論】把 §6.1 的靜默啟動失敗與這裡合起來看：**最需要 log 的情境（app 開不起來），恰好是 log 一定拿不到的情境。**

**可直接抄的對照組【事實，本輪補查】：Immich 行動端的日誌功能，整套設計正好補上 FMP 缺的每一塊。**

| 面向 | FMP 現況 | Immich 行動端 |
|---|---|---|
| 儲存 | 記憶體 `Queue`，500 條，重啟即失 | **獨立的 drift 資料庫**（`mobile/lib/data/db/logger/database.dart`，與主庫分開），表 `logger_messages`，欄位 `message / details / level / createdAt / logger / stack` |
| 保留策略 | 500 條上限 | `kLogTruncateLimit = 2000`（`mobile/lib/constants/constants.dart:6`），**啟動時**由 `LogRepository.truncate()` 裁掉舊紀錄 |
| 寫入節流 | 無 | `LogService`（`mobile/lib/domain/services/log.service.dart`）監聽 `Logger.root.onRecord`，**記憶體緩衝 5 秒再批次寫入**，明確為了減少 NAND 磨損 |
| UI | `log_viewer_page.dart`，只能「複製到剪貼簿」 | `AppLogPage`（`mobile/lib/pages/common/app_log.page.dart`）+ 詳情頁 `app_log_detail.page.dart`，AppBar 有清除與分享兩個按鈕 |
| 匯出 | 無 | `ImmichLogger.shareLogs()` 寫成 `Immich_log_<ISO時間>.log` 暫存檔，用 `share_plus` 叫系統分享面板 |
| 入口 | 設定頁深處 | 個人檔案抽屜，**且登入頁也放了同一個路由**（讓使用者連登入失敗都能取 log） |

**「登入頁也放入口」這一條特別值得抄** —— 它正是為了 FMP 現在拿不到 log 的那類情境設計的。這份對照是 D11 的具體實作參考。

### 6.4 i18n【事實】

3 個語言（`zh-CN` base、`zh-TW`、`en`），41 個 namespace JSON 每語言，flatten 後各 **1,231 個 key**。`dart run slang analyze` 與獨立腳本雙重驗證：**0 個缺翻譯、0 個多餘 key**。生成的 `lib/i18n/strings.g.dart` 是 **18,272 行 / 687 KB 的單檔**。

CI 三個 job 都跑 `dart run slang`，且因為生成檔被 gitignore，CI 永遠拿最新 JSON 重生成，結構上不可能出現「JSON 改了但生成檔沒更新」。

硬編碼字串幾乎沒有，但有一個真正的例外【事實】：`lib/ui/windows/lyrics_window.dart:33-97` 的 `_LyricsWindowStrings` class 有 **31 個欄位全部硬編碼簡體中文**（`等待歌词...`、`上一首`、`播放`、`暂停` 等）。這是 `desktop_multi_window` 建立的**獨立 Flutter engine 入口**，拿不到主視窗的 `t.`，所以設計上靠 `updateFrom(Map<String, dynamic>)`（`:67-97`）從主視窗同步。**同步到達之前，或同步失敗時，非中文使用者會看到硬編碼簡體中文。**

另有一處值得記錄的技術債：`fmp_audio_device_selector.dart:104` 的 `RegExp(r'喇叭\s*\((.+)\)$')` —— 用中文字樣解析 Windows 音訊裝置名稱，在非中文 Windows 上匹配不到。

slang 目前 3.32.0（lock），最新 **4.19.0**。

**實測【事實，本輪補做】：slang 4.19.0 對 FMP 的 JSON 零改動即可生成，但輸出結構是**破壞性**的。** scratchpad 探針（`probe-slang4`）複製 `lib/i18n/**` 的 123 個 JSON 與 `slang.yaml`（**未改一個字**），裝 slang 4.19.0 跑 `dart run slang` → `Translations generated successfully`，`Strings: 3693 (1231 per locale)`，與現況逐字相符。

**但生成檔的形狀完全變了：**

| | slang 3.32.0（現況） | slang 4.19.0 |
|---|---|---|
| 檔案數 | **1 個** `strings.g.dart` | **4 個**：`strings.g.dart`（7 KB 門面）+ `strings_zh_CN.g.dart`（`part`）+ `strings_en.g.dart` / `strings_zh_TW.g.dart`（**`deferred as`**） |
| 總行數 | 18,272 | 13,410 |
| 非基準語言載入 | 全部編進主 snapshot | **`import ... deferred as l_en;` 延遲載入** |
| `LocaleSettings.setLocale` | `AppLocale`（同步） | **`Future<AppLocale>`**（另提供 `setLocaleSync`） |
| `useDeviceLocale` | `AppLocale` | **`Future<AppLocale>`**（另有 `useDeviceLocaleSync`） |
| `LocaleSettings` 基底 | 無（自帶 `instance`） | `extends BaseFlutterLocaleSettings<AppLocale, Translations>` |
| `TranslationProvider` | 自寫 class | `extends BaseTranslationProvider<...>` |

FMP 受影響的呼叫點只有 **4 個**（`rg` 全查）：`main.dart:137` `LocaleSettings.useDeviceLocale()`、`locale_provider.dart:22,36` `setLocale(...)`、`locale_provider.dart:24,38` `useDeviceLocale()`。四處都是 fire-and-forget，改成 `*Sync` 變體即可零語意變更通過；要拿到 `deferred` 的好處則需改成 `await`。`AppLocale` / `TranslationProvider.of(context)` / `t.*` **全部不變**（`app.dart:45,70,127`、`number_format_utils.dart:8-30`、`settings_appearance.dart:448-456` 不用動）。

**兩件順帶確認的事**：① 生成檔從 1 個變 4 個，但 `.gitignore:29` 是全域的 `*.g.dart`（`git check-ignore -v lib/i18n/strings.g.dart` → `.gitignore:29:*.g.dart`），新增的 3 個檔**自動被涵蓋，不需要改 `.gitignore`**；② §6.1 提到的 snapshot 體積 —— `deferred` 讓 en / zh-TW 不再進主 snapshot，這是唯一一個會作用在那 1.86 s `timeToFrameworkInit` 上的改動，**但實際效果本輪未量測**。

升級的其餘 breaking changes 見 §9.1。

---
## 7. 問題清單 P0–P3

### P0

**P0-1 — `maxSizeMiB: 64` 沒有溢位處理，而資料無保留策略。**【事實 + 推論】
`database_provider.dart:299` 設 64，Isar 3.1 預設是 1024（`isar-3.1.0+1/lib/src/isar.dart:33`）。`rg "maxSizeMiB|Database full|IsarError"` 在 `lib/` 與 `test/` 除了那行設定本身之外 0 命中 —— 沒有 catch、沒有告警、沒有測試。`PlayHistory` / `Track` / `LyricsMatch` 都沒有自動保留策略。到達上限後每一次 `writeTxn` 都會拋，而使用者看到的會是散落各處、互不相關的失敗（存不了播放歷史、加不進歌單、下載狀態寫不回去），沒有任何一條訊息指向真正的原因。
**成熟對照**：Immich 遇到過一模一樣的問題 —— PR [immich#17372](https://github.com/immich-app/immich/pull/17372)（merged 2025-04-04）標題就是 `fix(mobile): bump isar maxSize`，body 寫「Increase the maximum size limit of Isar to **2GiB** to accommodate users with large number of assets」。FMP 現在是 64 MiB。
**成本 S / 風險低 / 完全可逆**：把 64 提高（Isar 的 `maxSizeMiB` 是 mmap 上限，不是預先配置的磁碟空間，調大幾乎沒有代價），並在開庫與寫入路徑補上明確的錯誤分類。

**P0-2 — `runApp()` 之前的任何例外 = 無視窗、無提示、無 log。**【事實，= issue #37】
`main.dart:87` / `:108` / `:114` / `:123` 四個初始化點都沒有 `try/catch`（`MediaKit.ensureInitialized()`、`AudioService.init()`、`_initializeSmtc()`、`_initializeWindowManager()`）。任一 throw → `runZonedGuarded` 的 `onError`（`:146-148`）記一行 log 就結束，`runApp()` 永不執行。而 log 只在記憶體（§6.3），使用者連 log 頁面都打不開 —— **最需要診斷資訊的情境，恰好是診斷資訊一定拿不到的情境**。
**成本 S / 風險低 / 可逆**：`onError` 裡判斷 `runApp` 是否已執行，未執行則 `runApp()` 一個最小錯誤畫面（含可複製的錯誤文字）。

### P1

**P1-1 — `isar_generator` 3.1.0 是整個 build 生態的天花板，並且擋住 Riverpod 3。**【事實，實測】
約束 `analyzer: ">=4.6.0 <6.0.0"` 把 analyzer 釘在 5.13.0（最新 14.1.0）、build 2.4.1（最新 4.0.10）、source_gen 1.5.0（最新 4.3.0）、dart_style 2.3.2（最新 3.1.13）。`build_resolvers` 與 `build_runner_core` 的最新版已標 **(discontinued)**。實測 `riverpod_annotation ^3.0.0` 直接 version solving failed（§14.2 探針 C）。
**成本 M / 風險中 / 可逆（改回 pubspec 即可）**。

**P1-2 — 沒有 schema 版本號，migration 靠資料形狀猜。**【事實 + 推論】
`rg "schemaVersion|dbVersion|databaseVersion"` 0 命中。`_hasLegacyPlaybackAndLyricsDefaultsSignature`（`database_provider.dart:31-38`）與 `_hasLegacyQueueVolumeSignature`（`:40-52`）用「N 個欄位同時是預設值」推斷版本。這種判斷式不可證偽，且每新增一個持久化欄位都要重新檢查它會不會污染既有簽名。`test/providers/database_migration_test.dart` 有一半的 test 在守「重跑兩次不能蓋掉使用者設定」—— 測試的存在就是在承認機制不安全。
**成本 M / 風險中 / 部分可逆**（一旦寫進 `Settings` 一個 `schemaVersion` 欄位就回不去了，但那正是要做的事）。

**P1-3 — repository 邊界只擋住型別外洩，擋不住直接存取：152 個呼叫點在邊界外。**【事實】
見 §1.3 的表。最重的是 `playlist_mutation_service.dart`（39）、`backup_service.dart`（36）、`data_integrity_service.dart`（20）。這直接決定了「換非相容資料庫」的成本量級。
**成本 L / 風險中 / 可逆**。

**P1-4 — `libraryInvalidationCoordinatorProvider` 有兩個 Riverpod 偵測不到的循環，而它只覆蓋了三分之一的域。**【事實 + 推論】
循環見 §2.3。散彈式失效在 `settings_backup.dart:326-338`（12 個手動 `invalidate`，4 個還包在 `if (Platform.isWindows)` 裡）與 `lyrics_search_sheet.dart:167-169` / `:193-195`（同樣三連 invalidate 複製貼上兩次）。
**成本 M / 風險低 / 可逆**。

**P1-5 — `CONTEXT.md` 已經與程式碼分歧，而它是領域語言的權威文件。**【事實】
`CONTEXT.md:38` 與 `:47` 仍描述已被 `c09aec10` 刪除的 Netease media allowlist。同時 `download_service.dart:1707` 的註解也描述了已不存在的行為。
**成本 S / 風險無 / 完全可逆**。

**P1-6 — `youtube_stream_test_page.dart:740-750` 把 Stream Resolution Auth 的 Cookie 塞進媒體 CDN 請求，且 release build 可達。**【事實】
`mediaHeaders()` 在簽名層面建立的邊界被呼叫端手動繞過。守門測試 `source_http_policy_usage_test.dart` 只覆蓋 6 個 account service，涵蓋不到 UI/debug 頁。
**成本 S / 風險低 / 可逆**：加 `kDebugMode` gate，並把守門測試的掃描範圍擴到 `lib/ui/`。

**P1-7 — secure storage 的 4 個 `read()` 沒有 try/catch，其中一個會讓音訊設定頁永久轉圈。**【事實，= issue #35，但症狀點與 issue 描述不同】
`netease_account_service.dart:391` / `:461`、`bilibili_account_service.dart:516`、`youtube_account_service.dart:515`、**`lyrics_ai_config_service.dart:83`（issue 未列）**。最後一個被 `audio_settings_provider.dart:139` 在建構子的 fire-and-forget `_loadSettings()` 裡呼叫，且整個方法沒有 try/catch → `state` 永不更新 → `isLoading` 卡在 `true`（`:61` 的預設值，而 `:160` 的 `isLoading: false` 永遠到不了）→ `audio_settings_page.dart:17` 永久 spinner。**而 Auth For Play 的三個開關就在那一頁**，使用者連自救都做不到。
另外 `AndroidManifest.xml:25-29` 沒有 `android:allowBackup="false"` —— 這正是 `flutter_secure_storage` 9.2.4 README 第 81-85 行點名的 `InvalidKeyException: Failed to unwrap key` 觸發條件。
**成本 S / 風險低 / 可逆**。**注意：不可以把 `PlatformException` 併進現有的 `_discardMalformedCredentials()`** —— 那會在暫時性 Keystore 失敗時永久刪掉使用者憑證。

**P1-8 — 開機自啟在可攜版搬動資料夾後靜默失效，且自我修復只在手動啟動後才會發生。**【事實，= issue #39】
見 §13 的 #39 段。
**成本 S / 風險低 / 可逆**。

**P1-9 — 更新機制沒有離線簽章，Windows 沒有 code signing。**【事實 + 推論】
SHA-256 manifest 與 artifact 來自同一個 GitHub Release，防的是傳輸損毀，防不了發布流程被攻陷。`rg "signtool" .github/workflows/release.yml` 0 命中。
**成本 M（簽章要處理金鑰保管與 CI secret）/ 風險中 / 可逆**。

**P1-11 — Track 識別鍵公式重複 7 次，而它同時是資料庫外鍵與備份格式，且零守門測試。**【事實 + 推論】
`'${sourceType.name}:$sourceId[:$cid]'` 散落在 `track.dart:284-286`、`track.dart:334-336`、`play_history.dart:42-44`、`track_repository.dart:27-29`、`play_history_repository.dart:25-27`、`backup_data.dart:305-306`、`backup_data.dart:386-387`。兩段式版本另重複 2 次（`track.dart:280` 與 `:331`，內容逐字相同）。而 `LyricsMatch.trackUniqueKey`（`@Index(unique: true, replace: true)`）、`LyricsTitleParseCache.trackUniqueKey`、備份的 `playlists[].trackKeys` 都存著它的輸出。**任何一處改動不同步，就同時破壞資料庫外鍵與所有既有備份檔，而目前沒有任何測試守住這 7 處必須產出相同字串。**
**成本 S / 風險低 / 可逆**：抽 `TrackKey` value object，7 處改為呼叫，加一個「同輸入產出同字串」的測試。

**P1-12 — `qq_music_sign.dart` 是一份「無可用授權」社群實作的逐行移植，是 MIT 化前唯一需要處置的檔案。**【事實 + 推論】

社群對 QQ 音樂 `zzb` 簽名存在**兩支命名譜系**。譜系 A（`AynaLivePlayer/miaosic`，**MIT**）用 `head` / `tail` / `ol` / `hexMap` + 標準庫 base64。譜系 B 最早見於 2022-09-05 的知乎文章，用 `k1` / `l1` / `t` / `t1` / `t2` / `t3` / `ls2` / `ls3` / `x1`–`x7`，手寫 base64。

`qq_music_sign.dart` 是**譜系 B**，而且不只是常數相同：

| 譜系 B 的表達特徵（非演算法必然） | FMP |
|---|---|
| 變數名 `k1` / `l1` / `t` | `:28` `_k1`、`:6` `_l1`、`:25` `_t` |
| 中間變數 `t1` `t3` `ls2` `ls3` `x1`–`x7` `t2` 同名同角色 | `:54,55,58,60-63,67,74-78,82` 全部命中 |
| 順序：先算 t1 再算 **t3**（跳過 t2），最後才算 t2 | `:54-55` 然後 `:82` |
| `x3 = (x1 * 16 ^ x2) ^ l1[i]` 的括號寫法 | `:62` 逐字相同 |
| `for i in range(6)` + `if i == 5` 特判用 `ls2[-1]` 而非 `ls2[15]` | `:68-72` 用 `ls2[ls2.length - 1]` |
| 過濾集 `[\/+]` —— **漏掉 `=`**（jixun 的 JS 版是 `[\/+=]`） | `:82` `RegExp(r'[\/+]')`，同樣漏 `=` |

**常數是協定事實沒問題，但「手寫 base64 的 6 次迴圈拆解 + 第 5 次特判 + x4–x7 的分解順序 + 連 `=` 都一起漏掉的過濾集」不是演算法必然，是特定作者的表達選擇。** 譜系 B 的所有已知來源都沒有可用授權：知乎文章是平台預設的「保留所有權利」，同譜系的 `keylin/TestMusic` 是 `license: none`。

**這是全 repo 唯一一處判定為「結構明顯搬運」的程式碼。** 兩個處置方向見 D14。
**成本 S（約 30 行）/ 風險低 / 完全可逆**。

**P1-10 — LGPL 元件（libmpv / FFmpeg）在 app 內完全未揭露，現況即已不合規。**【事實】
`showLicensePage()` 收不到建置時才下載的二進位；repo 沒有 `NOTICE`。**這跟切不切 MIT 無關**，維持 GPL-3.0 也一樣缺。
**成本 S / 風險無 / 完全可逆**。

### P2

| # | 問題 | 證據 | 成本 |
|---|---|---|---|
| P2-1 | `fmpDatabaseSchemas` 由**資料庫檢視器的 UI 目錄**推導，方向反了 | `database_catalog.dart:145-147`，且該檔 import `strings.g.dart` | S |
| P2-2 | 40 個測試檔各自複製一份 `_resolveIsarLibraryPath()` | `rg -l "_resolveIsarLibraryPath" test/` = 40 | S |
| P2-3 | 4 個直接依賴完全沒被用到：`logger` / `uuid` / `intl` / `flutter_reorderable_list` | `rg "package:<name>" lib/ test/` 各 0 命中 | S |
| P2-4 | `Settings` 是 57 欄位的單例巨型 collection，`settings.g.dart` 7,402 行 | `settings.g.dart` schema 屬性計數 | M |
| P2-5 | `_LyricsWindowStrings` 31 個欄位硬編碼簡體中文，是同步到達前的 fallback | `lyrics_window.dart:33-97` | M |
| P2-6 | 3 個 `watch*` repository 方法沒有任何呼叫方（含測試） | `track_repository.dart:190`、`radio_repository.dart:119`、`settings_repository.dart:42` | S |
| P2-7 | `databaseProvider` 的「未就緒」處理兩套策略並存：8 處 `.valueOrNull`、15 處 `.requireValue` | `repository_providers.dart:8,17,26,35,44,54,63,72` vs `download_providers.dart:33` | S |
| P2-8 | 47 天沒發版（v1.9.1 於 2026-07-16），期間 main 持續有 fix 合入；app 內更新對使用者靜默過期 | `gh release list` | — |
| P2-9 | Bilibili / Netease 的 `logout()` 不清 WebView cookie（只有 YouTube 清） | `bilibili_account_service.dart:283-292`、`netease_account_service.dart:275-281` vs `youtube_account_service.dart:124-144` | S |
| P2-10 | 下載 isolate 的 redirect 只檢查 scheme，沒過 `SourceUrlPolicy.parseTrustedHttpUrl()` / `isLocalOrPrivateHost()` | `download_service.dart:1699-1704`、`:1740` | S |
| P2-11 | `usesCleartextTraffic="true"` 全 app 開放明文 HTTP（Netease eapi 回 `http://` 的必要條件，但代價是全域的） | `AndroidManifest.xml:29` | M |
| P2-12 | CI 對純文檔 commit 也跑完整三個 job（15–20 分鐘） | `ci.yml` 無 path filter | S |
| P2-13 | 沒有覆蓋率門檻，lcov 只存成 artifact | `ci.yml:64` | S |
| P2-14 | `PlayHistoryRepository` 有 **6 個方法全表載入再用 Dart 過濾**，根因是 `PlayHistory.trackKey` 是計算 getter 卻沒有 `@Index()`（而 `Track.sourcePageKey` 證明 Isar 支援索引 getter） | `play_history_repository.dart:29,36,197,210,220,302` | M |
| P2-15 | **8 個死欄位 + 1 個死索引**（見 §1.5）。其中 6 個還有進備份，會在使用者之間往返搬運永遠為 null 的值 | `settings.dart:123-127,197,200`、`radio_station.dart:55`、`track.dart:279-280` | S |
| P2-16 | **缺 `AccountRepository`** —— `Account` 是唯一沒有 repository 的 collection，導致 5 個檔直接碰 `_isar.accounts` | `repositories.dart` | S |
| P2-17 | 備份沒有欄位覆蓋守門：**新增 `Settings` 欄位而忘了加進 `SettingsBackup`，使用者的該項設定會靜默遺失**，零測試失敗（改既有欄位名反而會 compile error） | `backup_service.dart:683`、`test/services/backup/` | S |
| P2-18 | `SourceType` 有**四種表示法**，且 `backup_service.dart:812-822` 與 `download_scanner.dart:87-90` 對未知值**靜默 fallback 成 `bilibili`**，而 `settings.dart:83-111` 對同樣情境是**靜默丟棄** —— 同一問題兩種行為，兩種都不留痕跡 | 見 §1.7 | M |
| P2-19 | 匯入備份**沒有原子性**：9 次 `writeTxn`、6 次在逐筆迴圈內、無外層交易，中途失敗留下半套資料 | `backup_service.dart:423,481,503,561,591,632,665` | M |
| P2-20 | **CI 有一個真實的 flaky test，會讓純文檔 commit 失敗**：`tearDown` 沒有 drain 進行中的非同步工作就 `isar.close(deleteFromDisk: true)`，播放鏈的 `_persistQueue` 落在關閉後的 Isar 上（根因與證據見 §14.4） | `audio_controller_phase1_test.dart:236-240`；CI run `30280237603` | M |

### P3

| # | 問題 | 證據 |
|---|---|---|
| P3-1 | `download_service.dart:1707` 的註解描述已不存在的行為（「根据当前请求 URL 重新计算」，但 `prepareDownloadHop` 不看 URL） | `media_handoff.dart:58-66` |
| P3-2 | `_preloadThemeSettings()` 的 `catch (_) {}` 沒有任何 log，第一次開庫失敗完全不可見 | `main.dart:198-200` |
| P3-3 | log 遮蔽清單有 `__csrf` 但沒有裸 `csrf` / `csrf_token`（目前無實害） | `logger.dart:81-107` |
| P3-4 | 3 處 `debugPrint` 繞過 `AppLogger` | `create_playlist_dialog.dart:386`、`play_history_page.dart:264`、`youtube_stream_test_page.dart:826` |
| P3-5 | 21 處指向不存在平台的 `Platform.is*` 分支（iOS 10 / Linux 6 / macOS 5） | 見 §4.1 |
| P3-6 | `RegExp(r'喇叭\s*\((.+)\)$')` 用中文字樣解析 Windows 音訊裝置名 | `fmp_audio_device_selector.dart:104` |
| P3-7 | issue #38 描述的問題已在 `ce100d32` 修掉，但 issue 仍 OPEN | `git merge-base --is-ancestor ce100d32 HEAD` = YES |
| P3-8 | `dependabot.yml` 沒有 `groups`，一次 run 開 6+ 個 PR 各觸發一次完整 CI | `.github/dependabot.yml` |
| P3-9 | `LyricsTitleParseCache` 每次啟動 `clear()`，本質是 session cache 卻佔一個 Isar schema | `database_provider.dart:186` |
| P3-10 | `PlatformDispatcher.instance.onError` 未設（官方三層錯誤處理只做兩層） | `rg` 0 命中 |
| P3-11 | `RadioRepository.reorder` 逐筆 `put()`，直接違反 `lib/data/AGENTS.md` 自己寫的 `putAll()` 規則（對照組 `PlaylistRepository.updateSortOrders:70-78` 是正確寫法） | `radio_repository.dart:82-92` |
| P3-12 | `VideoPage.duration` 叫 `duration` 但單位是**秒**，是全 repo 唯一的單位陷阱（同檔 `VideoDetail.durationSeconds` 反而有後綴） | `video_detail.dart:11`，轉換點 `:38` |
| P3-13 | 平台使用者 ID 用了 4 個名字、2 種型別；`Track` 用 int + String 兩個欄位，`Playlist` / source 層用一個 `String?` 裝兩者 | `track.dart:73,76`、`playlist.dart:44`、`radio_station.dart:29`、`account.dart:20` |
| P3-14 | `Logging` mixin 只有 3/10 個 repository 用，且在 hot path 無條件做字串插值（log level 過濾掉也照付構造成本） | `track_repository.dart:239-244,251-275` |
| P3-15 | 兩處 Isar 型別進了公開 API：`CollectionSchema<dynamic>` 成為 catalog 的公開欄位、`Isar` 成為 Widget 的建構子欄位 | `database_catalog.dart:28`、`database_viewer_page.dart:124` |

---

## 8. 成熟做法對照

### 8.1 Immich：真實發生過的 Isar → drift 遷移【事實，逐一查證 PR】

[`immich-app/immich`](https://github.com/immich-app/immich) 的 Flutter mobile app 是規模相近、且**實際完成了這條路**的對照。時間線（全部經 `gh api` 查證 merge 時間）：

| 日期 | PR | 意義 |
|---|---|---|
| 2025-04-04 | [#17372](https://github.com/immich-app/immich/pull/17372) `fix(mobile): bump isar maxSize` | 把上限提到 **2 GiB**。body：「to accommodate users with large number of assets」。**FMP 現在是 64 MiB。** |
| 2025-07-17 | [#19953](https://github.com/immich-app/immich/pull/19953) `feat: add toggle to switch between Isar and Sqlite` | **兩套資料庫並存，用一個執行期開關切換。** 這是整個遷移策略的核心。 |
| 2025-07-21 | #20062 `chore: graceful(not) disposal Isar` | 過渡期的 Isar 生命週期問題 |
| 2025-10-07 | [#22738](https://github.com/immich-app/immich/pull/22738) `chore: use isar immich fork` | **過渡期間自己維護一份 Isar fork**（因為上游停更） |
| 2025-10-08 | #22757 `chore: use hosted isar flutter libs` | |
| 2026-04-17 | [#27913](https://github.com/immich-app/immich/pull/27913) `chore: remove stale mobile/.isar submodule entry` | **Isar 徹底移除** |

現在 `mobile/pubspec.yaml` 的資料層是：`drift: ^2.34.0`、`drift_sqlite_async: 0.3.1`、`sqlite3: ^3.4.0`、`sqlite_async: 0.14.2`、`sqlite3_connection_pool: ^0.2.7`、`drift_dev: ^2.34.0`（dev），**沒有任何 isar**。

**可以直接抄的四條**【推論】：
1. **雙寫/雙讀並存 + 執行期開關**（#19953）。不是 big bang，是讓兩套資料庫在同一個 build 裡共存，用開關切，出問題可以立刻切回去。整個過渡期約 **9 個月**。
2. **上游停更就自己 fork**（#22738）。FMP 現在有更好的選擇 —— `isar_community` 已經有人在維護了，不必自己 fork。
3. **drift 搭 `package:sqlite3` 而不是 `sqflite`**。這也是 drift 官方現行推薦（`drift_sqflite` 已 3 年未更新）。
4. **他們也踩過 `maxSize` 這個坑**，而且是在使用者資料長大之後才踩到 —— 正是 P0-1 描述的失效模式。

### 8.2 drift 的 migration 機制對照【事實】

drift 有顯式的 `schemaVersion` + `MigrationStrategy`（`onCreate` / `onUpgrade` / `beforeOpen`），以及官方的 schema 版本快照工具（`drift_dev schema dump` / `schema generate`），可以對「從版本 N 升到 N+1」寫測試。

對照 FMP 現況：**沒有版本號、沒有升級腳本、靠資料形狀猜**（P1-2）。這不是 Isar 的錯 —— Isar 3 的自動 schema 演進只負責「新欄位取型別預設值」，「型別預設值不等於商業預設值」這一層本來就該由應用層用**版本號**而非**啟發式**來處理。**即使不換資料庫，這一條也該修。**

Immich 目前的 drift migration 甚至還在收斂（[#31039](https://github.com/immich-app/immich/pull/31039) `fix: save user_version in migration transaction`、#29664 `fix: wrap migrations in transaction` 都是 2026 年的 open/closed PR）—— 這說明**顯式 migration 也有它自己的坑**，但那些坑至少是可命名、可測試、可修的。

### 8.3 mpv 自己的 relicensing 先例【事實】

FMP 透過 media_kit 綁的那個播放引擎，自己就走過 relicensing：[`mpv-player/mpv` issue #2033](https://github.com/mpv-player/mpv/issues/2033)，GPLv2+ → LGPLv2.1+，2015-06 啟動、2017-10 大致完成。做法分三階段：廣泛徵詢每一位送過 patch 的人 → 逐一檢視約 44,000 個 commit（commit message 顯示程式碼來自他人的另外聯繫）→ **只對已取得同意的檔案逐檔切換**。即使如此，仍有少數檔案至今維持 GPL。

VLC / libVLC（GPLv2+ → LGPLv2.1+，2007 啟動、2012 完成）的[官方新聞稿](https://images.videolan.org/press/lgpl-libvlc.html)寫出了實務門檻：「99% 以上開發者同意，涵蓋 99.99% 的程式碼」，唯一拒絕回應的開發者其程式碼被直接重寫。

**FMP 與這些案例的差異是量級的**：mpv/VLC 難在著作權人有數十到數百位；FMP 只有一位（§5.1）。上述流程中最貴的環節在本案完全不適用。

### 8.4 Riverpod 3 的 legacy 路徑【事實】

Riverpod 3 把 `StateNotifierProvider` / `StateProvider` / `ChangeNotifierProvider` 移到 `package:flutter_riverpod/legacy.dart` **並繼續完整支援** —— 這正是官方為「大量 legacy provider 的既有專案」設計的升級路徑。FMP 有 39 個 `StateNotifierProvider` + 35 個 `StateNotifier` 類別，走 legacy import 只要在 35 個檔案各加一行。

**所以「升 Riverpod 3」和「把 StateNotifier 改寫成 Notifier」是兩件可以分開做的事**，不該綁在一起（§9.2）。

### 8.5 CI 的路徑感知【事實】

Immich 用自製的 [`immich-app/devtools` 的 `actions/pre-job`](https://github.com/immich-app/devtools) 做 path filter，`static_analysis.yml` / `test.yml` 裡的 `mobile-dart-analyze` / `mobile-unit-tests` 只在 `mobile/**` 有變動時觸發。FMP 現在對純文檔 commit 也跑滿三個 job（P2-12）。

Immich 也有 `codeql-analysis.yml` 與 `org-zizmor.yml`（zizmor 專掃 GitHub Actions workflow 的安全反模式）—— FMP 兩者皆無。

---

## 9. 建議方案

### 9.1 資料庫路線

**四條路的評估：**

| 路線 | 改動量 | 資料 migration 風險 | 對備份格式影響 | 附帶收益 | 判斷 |
|---|---|---|---|---|---|
| **(a) 維持 `isar` 3.1.0** | 0 | 無 | 無 | 無 | **不建議** —— 上游 `isar/isar` 最後一次 push 是 2025-06-14（14 個月前），且它正在把整個 build 生態往下拖（P1-1） |
| **(b) 換 `isar_community` 3.3.2** | 85 檔 import + slang 4.x 連動 | **無**（資料庫格式不變） | **無** | analyzer 5.13 → 10.2、解鎖 Riverpod 3、修 Android 16KB 對齊 | **建議** |
| **(c) 換 drift / `package:sqlite3`** | 11 repository（2,081 行）+ 152 個邊界外呼叫點 + 40 個測試檔樣板 + 31,651 行生成碼全部作廢 | **高**（要寫 Isar → SQLite 的一次性資料轉換，且要能回滾） | 中（可用備份格式當橋） | 顯式 migration、六平台支援、跳出停更生態 | **不建議現在做**，見下 |
| **(d) 換 objectbox** | 與 (c) 同量級 | 高 | 中 | 五平台 | **不建議** —— 核心原生庫是 closed-source 的自訂 Binary License，換一個停更風險去換一個授權風險，而且正要切 MIT |

**建議：走 (b)，並把 (c) 保留為明確的長期選項，但不是現在。**

理由：
1. **(b) 的資料風險是零** —— issue #44 說「資料庫格式無變更」，這點與 `isar_community` 的定位（v3 的維護型 fork，README 明文「focusing primarily on bug fixes and small updates for version 3」）一致，且 changelog 沒有任何 schema 相關的 breaking change。
2. **(b) 解鎖的東西不只 16KB 對齊** —— 它是 Riverpod 3 的前置條件（實測，§14.2），也是整個 analyzer/build 生態的解鎖鍵。
3. **(c) 現在做會踩到 P1-3**：152 個邊界外呼叫點意味著 drift 遷移不是「換 repository」，是「先把邊界收乾淨，再換」。**應該先做 P1-3，再談 (c)。**

**`isar_community` 的維護風險要據實說**【事實】：`isar-community/isar-community` 最後一次 commit 是 2026-07-03（合併一個 query impl 的記憶體洩漏修復 PR），最新 release 3.3.2 是 2026-03-23（5 個月前）。整個 fork 只有 5 個 release（2025-11 兩個、2026-03 兩個 + 3.3.0）。**它是「有人維護」而不是「活躍開發」**。舊的 `isar-community/isar` repo 已封存（2025-08-18）並指向新 repo，這是一次正常的搬遷不是棄坑。pub.dev 顯示 79.5k 週下載、160 likes、pub points 140。

**(b) 的完整步驟**【建議，實測配方見 §14.2】：

| 步 | 內容 | 成本 | 風險 |
|---|---|---|---|
| 1 | 先刪 `riverpod_annotation`（死依賴，P2-3） | S | 無 |
| 2 | **`slang_flutter` / `slang_build_runner` 3.31 → 4.19**（issue #44 漏掉的硬條件）。實際要改的：`slang.yaml` 的 `output_file_name`（4.x 移除 `output_format`，一律多檔輸出）、`main.dart:137` 與 `locale_provider.dart:22,24,32,36,38` 的 `setLocale` / `useDeviceLocale`（4.x 回傳 `Future`，同步版要用 `-Sync` 後綴）、`app.dart:46,71,128` 的 `AppLocaleUtils.supportedLocales`。約 8 個呼叫點 | **M** | 中 —— slang 是大版本跳，要對照官方 MIGRATION.md 逐條核 |
| 3 | `isar` → `isar_community` 三個 pubspec 條目 + 85 個檔案的 import | S（機械） | 低 |
| 4 | `pubspec.yaml:8` 的 SDK 下限 `>=3.5.0` → `>=3.9.0`（`isar_community` 3.3.2 的要求；不改不會擋住解析，但下限會是假的） | S | 無 |
| 5 | `dart run build_runner build --delete-conflicting-outputs` + `dart run slang` | S | 低 |
| 6 | 驗證：`flutter analyze`、`flutter test`（基準 **1234 條**）、重建 APK 量 `lib/*/libisar.so` 的 LOAD align 應為 `0x4000` | S | — |

**(b) / (c) / (d) 的成本量化**【事實 + 推論】：

手寫 Isar 耦合總量約 **1,250 行**（108 行 model 標註 + 226 行 repository + 152~214 個非 repository 呼叫點 + 698 行 test），相對於約 39,000 行的資料層。

| | (b) `isar_community` | (c) drift / sqlite3 | (d) objectbox |
|---|---|---|---|
| 手寫變動行 | **~90**（一條 `sed`） | ~5,900 | ~4,000 |
| 影響檔案 | 88（純 import 替換） | 89（實質重寫） | 89（實質重寫） |
| 資料遷移碼 | **零（實測，§14.4）** | 必寫 ~500 行 | 必寫 ~500 行 |
| **對備份格式影響** | **零** | **零** | **零** |
| schema 版本工具 | 無（同現況） | `schema dump` + `SchemaVerifier` + `stepByStep` | 官方自承沒有（`objectbox-dart#391`） |
| 可補齊缺失唯一性約束 | ❌ | ✅ | ✅ |
| 風險 / 可逆性 | 低 / **完全可逆** | 高 / 低 | 中高 / 低 |

(c) 要重寫的三個結構性項目：`Playlist.trackIds` / `PlayQueue.trackIds` 的 `List<int>` → join 表（中）、`Track.playlistInfo` 的 `@embedded` list → 關聯表（高，`track.dart:107-220` 的 8 個 helper 邏輯要從 model 移到 repository）、兩個「getter 上的複合索引」→ generated column 或寫入時具體化（其中 `sourceKey` 可直接刪，§1.5 已證明是死索引）。

**但因為從沒用過 `IsarLink`，這三處本來就是「用 `List<int>` 手工模擬外鍵」—— 轉成真 join 表是把既有的隱式約束顯式化，不是重新設計關係。**

(c) 的附帶收益也真實：`PlayHistoryRepository` 那 6 個全表掃描方法（P2-14）全變成一行 `GROUP BY` / `COUNT(*)`；`DataIntegrityService`（373 行）一半邏輯被 UNIQUE 約束取代而變簡單；41 處測試的 `Isar.open` → `NativeDatabase.memory()`，不再需要 `Isar.initializeIsarCore()` 與 native libs（順帶消掉 P2-2 的 40 份樣板）。

(d) 有一個要據實記錄的陷阱：objectbox 的「自動 schema migration」**不等於不用寫 migration**。改名必須手動帶 UID（否則**舊資料直接被丟棄，這是官方預設行為**），改型別官方明說「不支援自動搬資料」。對照專案 BlueBubbles 另建了一整套版本化遷移（`database.dart:18` `static int version = 9;` + `while (currentVersion < version)` 逐版 switch），且其 `objectbox-model.json` 的 `retiredPropertyUids` 已累積到 **112 個**（現存 entity 只有 10 個）—— 這份檔案的維護成本隨專案年齡線性上升。

(d) 還有一個上一版沒查的授權面向【事實，本輪補查】：**objectbox 的 Dart binding 是 Apache-2.0，但實際打包進 release 的原生庫是自訂的專有 EULA。** `objectbox-dart` 的 `README.md:182-183` 自己就寫了範圍限制：「Note that this license applies to the code in this repository only.」；`flutter_libs/ios/objectbox_flutter_libs.podspec:14` 直接把雙授權寫進 podspec：`s.license = 'Apache 2.0, ObjectBox Binary License'`。
[ObjectBox Binary Licence](https://objectbox.io/0209-ob-binary-license/) 第 2a 條逐字：「a non-exclusive, non-transferable, non-sublicensable, **revocable**, limited, royalty-free licence」——免費、無資料量／裝置數／營收門檻，但**禁止修改與逆向工程、不可轉讓／再授權、可被單方撤銷**，且第 2b(vi) 條有「不得用於開發競品」的條款。
**這不阻擋 FMP 改 MIT**（MIT 不管內含第三方元件用什麼授權），但打包它等於讓終端使用者同時受這份 EULA 約束，**必須在 NOTICE 裡列成獨立一項**，且第 2b(iv) 條強制不得移除其既有商標／著作權標示。**對一個要走 MIT 的開源專案，這是 (d) 相對 (b)/(c) 的一個額外負擔** —— isar_community 是 Apache-2.0、drift 是 MIT，兩者都沒有這個問題。

**Immich 的共存策略是唯一可抄的實作，但有一條 FMP 不能抄**【事實 + 推論】：他們的共存期約 12.5 個月（drift 進 tree 2025-04-02 → Isar 移除 2026-04-15），使用者可見的雙軌期約 9 個月；開關存在自家 key-value store（`StoreKey.betaTimeline`）；共存期用**臨時介面 + 雙實作**（`abstract class IStoreRepository` + `IsarStoreRepository` / `DriftStoreRepository`，註解直白寫「Temporary interface until Isar is removed」）。他們按「重建成本」分類：設定/token **複製**、本機資產 checksum **複製**、server cache **丟棄後重新同步**。
**FMP 不能用最後那一項** —— Immich 敢丟掉 5 萬張照片的中繼資料，是因為 system of record 在 server；**FMP 的 `Playlist` / `Track` / `PlayHistory` 是唯一副本**。FMP 只能全部複製。

**還有一條反向的教訓**【事實】：Immich 在 2025-06 用 20+ 個 PR（#19331–#19355、#19415）**把 `domain/interfaces/` 整個抽象層刪掉**，現在的 repository 就是 drift DAO 本身。**所以不要為了「將來可能換 DB」預先加一層 `abstract interface class Repository`** —— 真的要換時他們用的是撐 3 個月的臨時介面，不是長期抽象層。FMP 現有的 10 個 repository 已經是一層薄抽象，在不換引擎的前提下再包一層只是空轉。

**順帶要做的兩件事（跟換不換資料庫無關，但都在這一層）**：
- **P1-2 的 schema 版本號**：在 `Settings` 加一個 `schemaVersion` int 欄位，把現有的形狀猜測改寫成「版本 N → N+1 的具名遷移步驟」。既有使用者的資料沒有版本號，所以第一版遷移要保留現有的形狀啟發式當作「推斷 v0」的一次性入口，之後就永遠走版本號。**成本 M、風險中、部分不可逆。**
- **P0-1 的上限與保留策略**：`maxSizeMiB` 調高（Immich 用 2048），並補上「寫入失敗」的明確錯誤路徑；`PlayHistory` 加一個可設定的保留上限。**成本 S。**

### 9.2 Riverpod 2 → 3

**建議：方案 A（相容式升級），排在資料庫遷移之後。**

- **不做** 39 個 `StateNotifierProvider` → `NotifierProvider` 的改寫。官方就是為此提供 `flutter_riverpod/legacy.dart`（§8.4），35 個檔案各加一行 import 即可。
- 機械改動約 72 點跨 40 檔（§2.5）。
- **真正要花時間的是三個行為變更**：
  1. **out-of-view pause**（風險最高）—— FMP 是音樂播放器，`audioControllerProvider` / `radioControllerProvider` / `connectivityProvider` / `downloadTasksProvider` 在 UI 不可見時必須繼續跑。**這一項 `flutter test` 涵蓋不到，必須實機驗證背景播放、下載進度、Windows 最小化到 tray。**
  2. **auto-retry 預設開啟** —— 26 個 `FutureProvider` + 7 個 `StreamProvider` 要逐一決定是否 `retry: (_, __) => null`。高風險的是 `databaseProvider`（入度 28）與兩個帳號 provider。
  3. **`UnmountedRefException`** —— `rg "ref.mounted"` 0 命中；10 處 async-body `ref.read` 要檢，重點是 `startup_download_sync_provider.dart:22,24` 與 `playlist_provider.dart:572`（都在 `await` 之後）。
- **估算：2–4 人日**（M）。測試側衝擊小（約 9 個改動點跨 6 檔）。
- **附帶**：刪掉 `riverpod_annotation` 之後可以拿到 `flutter_riverpod 3.4.2`（最新）而不是 3.0.3（實測，§14.2 探針 D）。

`StateNotifier` → `Notifier` 的改寫應該綁在 `audio_provider.dart` 的拆分計畫上（上一輪報告 §8.1 的 B–F），**不要當成升級的一部分**。單那兩個類別（`AudioController` 約 3,000 行、`RadioController` 約 900 行）就佔了改寫工作量的一半以上。

### 9.3 協調器與失效

**建議順序**：
1. **短期（S，零風險）**：把 `settings_backup.dart:326-338` 的 12 個 invalidate 與 `lyrics_search_sheet.dart` 的兩組三連 invalidate，各抽成一個與現有協調器同型的**注入式**協調器，並加上同款的原始碼靜態規則測試（照 `library_invalidation_coordinator_test.dart:116-135` 的寫法）。
2. **中期（M）**：讓 `allPlaylistsProvider` 從 `playlistListProvider` 衍生（`Provider((ref) => ref.watch(playlistListProvider).playlists)`）。這一步同時消掉協調器的 `invalidateAllPlaylists`、循環 B 的一條邊、以及一個手動快取。
3. **長期**：`fileExistsCache` 的 epoch 機制（`file_exists_cache.dart:250`）在 Riverpod 3 可以用 `Notifier` + 正常依賴取代。

### 9.4 GPL-3.0 → MIT

**建議：可以做，全部是 S 級成本。**

| 步 | 內容 | 成本 | 風險 |
|---|---|---|---|
| 1 | 著作權人書面同意（就是你本人；留在 commit message 或 issue 裡備查） | S | 低 |
| 2 | `LICENSE` 換成 MIT 全文 | S | 低 |
| 3 | 檔頭清查 —— **不需要做**，`rg "SPDX-License-Identifier"` 全庫 0 命中 | — | — |
| 4 | `README.md` 與 `README.zh-Hant.md` 各 2 處（`README.md:10` 的 badge、`:151` 的 License 段） | S | 低 |
| 5 | `pubspec.yaml` —— **不需要做**，`publish_to: 'none'` 沒有 `license:` 欄位 | — | — |
| 6 | GitHub repo 的 license 標記會在 push 後自動重新索引，不需手動改設定 | S | 低 |
| 7 | **新增 `NOTICE`（或 `THIRD_PARTY_LICENSES.md`）**，揭露 libmpv/FFmpeg 的 LGPL-2.1/3-or-later 全文與來源連結（§5.3 的四個條件）。**這是現況本來就缺的（P1-10），不是 MIT 造成的** | **M** | 低 |
| 8 | CHANGELOG 記一筆（`chore(license): relicense project from GPL-3.0 to MIT`） | S | 低 |
| 9 | 順手在 `netease_crypto.dart` / `qq_music_sign.dart` 頂端加一行「參考公開逆向工程協定重新實作」的說明註解（非必要，降低未來稽核成本） | S | 無 |

---
## 10. 重寫 vs 漸進重構

逐模組給結論。**本輪範圍內沒有任何一塊我建議重寫。**

| 模組 | 建議 | 理由 |
|---|---|---|
| **Isar 資料層本體** | **漸進（換 fork）** | 11 個 collection、188 個持久化屬性、零 `IsarLink`、窄查詢面（沒有 aggregate、沒有 full-text）。這是一個**乾淨、關聯已經手刻成外鍵**的資料層 —— 沒有任何 Isar 專屬語意需要翻譯。既然如此，把它換成 API 相容的 `isar_community` 是 85 個 import 行的機械操作，而換成 drift 是重寫 2,081 行 repository 加 152 個邊界外呼叫點。**在拿到相同的維護性收益的前提下，選便宜的那個。** |
| **migration 機制** | **換掉機制，但漸進** | 這是唯一我建議「換掉現有做法」的地方。形狀猜測（`_hasLegacy*Signature`）本質上不可證偽，而且每加一個欄位就多一份心智負擔。改成 `Settings.schemaVersion` + 具名遷移步驟。**但要漸進**：既有使用者的資料沒有版本號，所以第一版遷移必須保留現有的形狀啟發式當作「推斷 v0」的一次性入口，之後永遠走版本號。 |
| **repository 邊界** | **漸進收斂** | 152 個邊界外呼叫點集中在 3 個檔案（39 + 36 + 20 = 95，佔 63%）。先把 `playlist_mutation_service` / `backup_service` / `data_integrity_service` 三個收進 repository，就消掉三分之二。這是可以分次做、每次都留下可運作 repo 的工作。 |
| **備份格式** | **不動** | 有版本號、有相容性閘門、刻意排除易失效欄位、用 `sourceType:sourceId[:cid]` 而非 Isar id 當跨機器識別 —— 這一塊設計是對的。**它反而應該當成換資料庫時的資料橋。** |
| **狀態管理（Riverpod）** | ~~**漸進（走 legacy import）**~~ **已全數改寫（2026-09-07）** | 官方就是為此提供 `flutter_riverpod/legacy.dart`。~~39 個 `StateNotifierProvider` 改寫成 `Notifier` 是 12–20 人日~~，而且其中一半的工作量在兩個上一輪已經點名要拆的 god provider 裡 —— **那是拆分計畫的事，不是升級的事。** 後半段說對了：那兩個類別確實是最後、最貴的兩個 commit。見 `05-roadmap.md` §6.12 |
| **失效協調** | **漸進擴展 + 一次結構性收斂** | 協調器本身寫得好（函式注入、可脫離 Riverpod 測試、有 `ref.exists()` 守衛）。要做的是把 settings 域與 lyrics 域也納進來，以及讓 `allPlaylistsProvider` 從 `playlistListProvider` 衍生（一步同時消掉一條循環邊與一個手動快取）。 |
| **平台層** | **需要一次結構性重構，但不是重寫** | 50 處 `Platform.isWindows` 需要重新分類成「真 Windows 專屬」與「桌面通用」。但架構方向已經是對的 —— `AudioRuntimePlatform` + 兩個 `FmpAudioService` 實作，正是 Harmonoid 用的那個模式。**要補的是把同樣的抽象套到系統整合層**（托盤、媒體控制、自啟、更新），不是推倒重來。 |
| **repository 抽象層** | **不要加** | Immich 在 2025-06 用 20+ 個 PR 把 `domain/interfaces/` 整層刪掉，現在的 repository 就是 drift DAO 本身。真的要換 DB 時他們用的是撐 3 個月的臨時介面，不是長期抽象層。FMP 現有的 10 個 repository 已經是一層薄抽象 —— 在不換引擎的前提下再包一層只是空轉。**該做的是把 152 個邊界外呼叫點收進現有的 repository，不是再蓋一層。** |
| **CI / release** | **漸進補強** | 現況比我預期的好 —— actions SHA 釘選、checksum manifest、Zip-slip 防護、ISS patch 的 F8 迴歸閘門都在。缺的是路徑感知、覆蓋率門檻、Windows 簽章、離線簽章。全部是加法。 |

**一句話**：這個 codebase 的資料層與狀態層都不是「爛到要重寫」，而是**卡在一個停更的依賴上**，而那個依賴同時是整個 build 生態的天花板。優先處理依賴，其他的按 P0→P1 順序做。

---

## 11. 需要你決策的點

（先列出來，不是現在問你。）

**D1 — `isar_community` 遷移要不要做，什麼時候做？**
它綁著 slang 3.x → 4.x 的大版本升級（實測，非選配）。做完解鎖 analyzer 5.13 → 10.2、Riverpod 3、Android 16KB 對齊。不做的話這三件事都動不了。

**D2 — 要不要導入 `Settings.schemaVersion`？**
這會在持久化格式上新增一個欄位，寫下去就回不去了（可以刪欄位，但已寫入的值救不回）。收益是把不可證偽的形狀猜測換成可測試的版本遷移。

**D3 — `maxSizeMiB` 調到多少？`PlayHistory` 要不要加保留上限？**
Immich 的答案是 2048。調高幾乎零成本。但「保留上限」會**主動刪掉使用者資料**，需要一個設定項與明確的預設值 —— 這是產品決策不是技術決策。

**D4 — Riverpod 3 升級走方案 A 還是 B？時機？**
A（legacy import，2–4 人日）／B（完整改寫成 `Notifier`，12–20 人日）。我建議 A，並把 B 併進 `audio_provider.dart` 的拆分計畫。但這取決於你打不打算做那個拆分。

**D5 — repository 邊界收斂（P1-3）要不要做？**
L 成本。它本身有價值（可測試性、單一資料存取路徑），同時也是未來換 drift 的前置。如果確定永遠不換非相容資料庫，這件事的優先度會降一級。

**D6 — GPL-3.0 → MIT 要不要切？**
沒有法律障礙，全部 S 成本。但這是產品／社群決策：MIT 允許閉源商業衍生。

**D7 — `NOTICE` 要不要補？**
**這一項獨立於 D6。** 現況即已缺（LGPL 的 libmpv/FFmpeg 完全未揭露），維持 GPL 也一樣缺。

**D8 — 平台擴展：你有沒有 Mac？**
有 → macOS 先（硬阻塞 0 個）。沒有 → Linux 先（但 Linux 的 YouTube 登入要選降級或引入 `webview_cef`）。這個答案會直接改變順序。

**D9 — `youtube_stream_test_page.dart` 的 Cookie 探測怎麼處置？**
(a) 加 `kDebugMode` gate（診斷能力在 release 消失）／(b) 保留但在 UI 上明示風險／(c) 整個 debug 頁 debug-only。

**D10 — Windows code signing 與更新的離線簽章要不要做？**
兩者都有持續成本（憑證費用、金鑰保管、CI secret 輪替）。不做的話 SmartScreen 警告與「發布流程被攻陷」的風險就留著。

**D11 — log 要不要落盤？**
現況 log 只在記憶體，而最需要它的情境（P0-2 的靜默啟動失敗）恰好拿不到。落盤要處理輪替、大小上限、以及「使用者匯出時會不會夾帶隱私」。

**D12 — issue #38 要不要關？**
問題已在 `ce100d32` 修掉。我沒有關（本輪規則），但它現在是過時的 OPEN issue。

**D13 — 6 個死欄位要不要刪？**
刪掉 5 個自訂色（`settings.dart:123-127`）與 `RadioStation.note` 是**持久化 schema 的破壞性變更**，而且要同步移除 `SettingsBackup` / `RadioStationBackup` 的對應欄位。技術上很安全 —— Isar 刪欄位不需要 migration（舊資料的該欄位直接被忽略），舊備份檔匯入時多餘的 key 本來就會被靜默忽略。但依你的規則，持久化格式的破壞性變更要先告知，所以列在這裡。
另一個選擇是保留 `RadioStation.note` 並**把 UI 做出來**（電台備註是合理的功能），只刪 5 個色。

**D14 — `qq_music_sign.dart`（P1-12）要重寫還是保留加 NOTICE？**
(a) **重寫**（我的建議）：照譜系 A 的表達改寫，`AynaLivePlayer/miaosic` 是 **MIT** 可直接參考，約 30 行，一併消除來源疑慮；(b) **保留 + NOTICE**：主張常數是協定事實、30 行的表達極薄（merger doctrine）。(b) 站得住但屬判斷而非確定；(a) 的成本低到不值得為此賭。
順帶：無論選哪個，`netease_crypto.dart` 與 `bilibili_crypto.dart` **不需要動**。

**D15 — MIT 化時要不要一併補 `NOTICE` 檔？**
`rg --files -g "*NOTICE*" -g "*THIRD*" -g "*COPYING*"` → **0 命中**，專案現在完全沒有第三方授權揭露檔。它需要涵蓋三件互相獨立的事：P1-10 的 libmpv/FFmpeg（LGPL，現況即已不合規，跟 MIT 無關）、5.1.1 的協定常數來源、以及 206 個 Dart 依賴的授權清單。**這是「補現有缺口」而不是「MIT 化的代價」**，但兩件事一起做最省。

---

## 12. Quick wins

（發現但本輪未動手的小問題。編號接上一輪的 Q34。）

| # | 內容 | 位置 |
|---|---|---|
| Q35 | 刪 4 個完全沒被使用的直接依賴：`logger`、`uuid`、`intl`、`flutter_reorderable_list` | `pubspec.yaml` |
| Q36 | 刪 `riverpod_annotation`（死依賴，且實測擋著 `flutter_riverpod` 拿到 3.4.2） | `pubspec.yaml:19` |
| Q37 | 修 `CONTEXT.md:38` 與 `:47` 的 Netease allowlist 敘述 —— 改成描述現行的「`mediaHeaders(SourceType)` 簽名層面零憑證」 | `CONTEXT.md` |
| Q38 | 修 `download_service.dart:1707` 的註解（描述了已不存在的「根据当前请求 URL 重新计算」行為） | — |
| Q39 | 抽出 `test/support/isar_test_harness.dart`，消掉 40 個測試檔各自複製的 `_resolveIsarLibraryPath()` | `test/` |
| Q40 | `_preloadThemeSettings()` 的 `catch (_) {}` 補一行 log —— 現在第一次開庫失敗完全不可見 | `main.dart:198-200` |
| Q41 | `maxSizeMiB: 64` 調高（Immich 用 2048），並在開庫路徑補上明確的錯誤分類 | `database_provider.dart:299` |
| Q42 | 刪 3 個沒有任何呼叫方的 `watch*` repository 方法 | `track_repository.dart:190`、`radio_repository.dart:119`、`settings_repository.dart:42` |
| Q43 | `youtube_stream_test_page.dart` 的 Cookie 探測加 `kDebugMode` gate；並把 `source_http_policy_usage_test.dart` 的掃描範圍擴到 `lib/ui/` | — |
| Q44 | log 遮蔽清單補上裸 `csrf` / `csrf_token`（目前只有 `__csrf`） | `logger.dart:81-107` |
| Q45 | Bilibili / Netease 的 `logout()` 補上清 WebView cookie（照 YouTube 的做法） | `bilibili_account_service.dart:283-292`、`netease_account_service.dart:275-281` |
| Q46 | `AndroidManifest.xml` 加 `android:allowBackup="false"`（或用 `dataExtractionRules` 排除 secure storage 的 SharedPreferences） | `AndroidManifest.xml:25-29` |
| Q47 | 3 處 `debugPrint` 改走 `AppLogger` | `create_playlist_dialog.dart:386`、`play_history_page.dart:264` |
| Q48 | `dependabot.yml` 加 `groups`，避免一次 run 開 6+ 個 PR 各觸發一次完整 CI | `.github/dependabot.yml` |
| Q49 | CI 加 path filter，純文檔 commit 不跑 `build-android` / `build-windows` | `.github/workflows/ci.yml` |
| Q50 | 在 issue #38 留言指向 `ce100d32` 並關閉 | GitHub |
| Q51 | 統一 `databaseProvider` 的「未就緒」處理（現在 8 處 `.valueOrNull` 對 15 處 `.requireValue`） | `repository_providers.dart` 等 |
| Q52 | 補 `NOTICE` 揭露 libmpv/FFmpeg 的 LGPL（**現況即已缺**，與是否切 MIT 無關） | 專案根目錄 |
| Q53 | 下載 isolate 的 redirect 補上 `SourceUrlPolicy.parseTrustedHttpUrl()` / `isLocalOrPrivateHost()` 檢查（與 playlist import 路徑一致） | `download_service.dart:1699-1704,1740` |
| Q54 | 在 issue #42 撤下「備份仍照樣匯出匯入」那一條（三層反證見 §13），並把那條指控改指向 `RadioStation.note` | GitHub |
| Q55 | 刪 5 個死的自訂色欄位 + `RadioStation.note` + `Track.sourceKey` 的死索引（同步移除 `SettingsBackup` / `RadioStationBackup` 的對應欄位；`fromJson` 對舊備份的多餘 key 本來就靜默忽略，不需特別處理） | `settings.dart:123-127`、`radio_station.dart:55`、`track.dart:279-280` |
| Q56 | 補備份的欄位覆蓋守門測試（約 40 行，照抄 `database_viewer_page_coverage_test.dart` 的「讀原始碼 + 正則」手法） | `test/services/backup/` |
| Q57 | 補 `AccountRepository`（約 60 行，一次消掉 5 個檔的直接 `_isar.accounts` 存取） | `lib/data/repositories/` |
| Q58 | `PlayHistory.trackKey` 加 `@Index()` —— 讓 6 個全表載入方法變成索引查詢，422 行可砍到 250 行內。重跑 `build_runner`，無資料遷移 | `play_history.dart:42-44` |
| Q59 | `RadioRepository.reorder` 改用 `putAll()`（照 `PlaylistRepository.updateSortOrders:70-78` 的寫法） | `radio_repository.dart:82-92` |
| Q60 | `VideoPage.duration` 改名為 `durationSeconds`（純 DTO，零風險） | `video_detail.dart:11` |
| Q61 | 在 `BackupData` 類註釋補「不匯出哪 4 個 collection 與原因」—— 目前一行說明都沒有 | `backup_data.dart` |
| Q62 | 把 `_parseSourceType` 提升為 `SourceType.tryParse(String)` 回傳 `SourceType?`，讓兩個呼叫端各自明確決定 fallback 或報錯（至少讓備份的失敗進 `ImportResult.errors`），並把 `LyricsTitleParseCache.sourceType` 從 `String` 改成 `@Enumerated(EnumType.name) SourceType`（存的內容不變，無資料遷移） | `backup_service.dart:812-822`、`download_scanner.dart:87-90`、`lyrics_title_parse_cache.dart:12` |

---

## 13. issue #35 / #39 / #44 的裁決

### issue #44 —— **保留，但描述要補兩段**

**事實核對**（逐條）：

| issue 的宣稱 | 核對結果 |
|---|---|
| 官方 isar 3.1.0+1 自 2023 年起停止維護 | **【證實】** `gh api repos/isar/isar` → `pushed_at: 2025-06-14`（14 個月前），未封存但實質停滯；pub.dev 上 3.1.0+1 是 3 年前發布，另有 4.0.0-dev.14 prerelease |
| `isar_community` 3.3.2，2026-03-23 發布 | **【證實】** `gh api repos/isar-community/isar-community/releases` → `3.3.2` published `2026-03-23`。**日期精確無誤** |
| 3.2.0-dev.1 的 CHANGELOG 記載 "Added support for Android 16KB page size issue" | **【證實】** pub.dev changelog 逐字相符 |
| API：3.1.x 至 3.3.2 之間無破壞性變更 | **【證實】** changelog 唯一標 Breaking 的是「套件改名」 |
| 資料庫格式 / schema 無變更 | **【推論，一致】** changelog 沒有任何 schema 相關條目，且該 fork 的定位就是 v3 維護（README 原文「focusing primarily on bug fixes and small updates for version 3」） |
| 85 個檔案的 `package:isar` → `package:isar_community` | **【證實】** `rg -l "package:isar"` = 86 個命中，其中 1 個是 `docs/review/01-...md`，**Dart 檔正好 85 個** |
| 非緊急，側載分發不受 Google Play 政策約束 | **【同意】** |

**要補的兩段**：

1. **遷移步驟不完整 —— 照著做會在 `flutter pub get` 就失敗。** 缺少 `slang_flutter` / `slang_build_runner` 3.31 → 4.19 這個連動的大版本升級（實測輸出見 §14.2）。slang 4.0 自己有 breaking changes（`output_format` 移除改多檔輸出、`setLocale`/`useDeviceLocale` 改回傳 `Future`、`supportedLocales` 移除），FMP 受影響的約 8 個呼叫點：`slang.yaml` 的 `output_file_name`、`main.dart:137`、`locale_provider.dart:22,24,32,36,38`、`app.dart:46,71,128`。另外 `pubspec.yaml:8` 的 SDK 下限應從 `>=3.5.0` 提到 `>=3.9.0`。
2. **價值被低估了。** issue 說「真正的價值在於脫離已停更兩年的官方 isar，16 KB 對齊屬附帶收穫」—— 方向對，但沒說出關鍵的一條：**`isar_generator` 的 `analyzer >=4.6.0 <6.0.0` 把整個 build 生態釘在 2023 年的版本，而且它是 Riverpod 3 升級的硬阻塞**（實測 version solving failed）。這讓 #44 從「非緊急的維護性改善」升格為「其他兩件事的前置條件」。

**一個要據實記錄的風險**：`isar_community` 是「有人維護」而非「活躍開發」—— 最後一次 commit 2026-07-03，最新 release 3.3.2 是 5 個月前，整個 fork 只有 5 個 release。它解決的是「完全沒人管」，不是「回到活躍」。

**2. 兩條原本標「推論 / 一致」的宣稱，本輪實測轉為「證實」。**【事實，§14.4】

| issue 的宣稱 | 上一版 | 本輪實測 |
|---|---|---|
| 修了 Android 16 KB page size | 【證實 changelog 有這條】，但**沒量過 binary** | **【實測證實】** 自寫 ELF parser 量 4 個 ABI：現況全 `0x1000`、community 全 `0x4000`；且 pub 套件內的 `.so` 與 GitHub release 資產 SHA-256 逐字節相同 |
| 資料庫格式 / schema 無變更 | 【推論，一致】 | **【實測證實】** 11 個 collection 的生成碼逐字相同（只差 `version:` 一行）、schema id hash 全同；真實 DB 副本（1,195 曲目）用新原生庫**原地開啟、讀出欄位、寫入成功** |

**所以 issue #44 該補的第二段是：資料遷移成本是零，這一點現在有實測而不只是 changelog 背書。** 唯一還沒實測的是 Android 上的實際開啟（§14.5 A-4）。

### issue #39 —— **保留，但根因描述錯了一半**

**能重現：能（靜態分析即可完整推演）。**

**issue 的機制描述不正確。** issue 說「`LaunchAtStartupNotifier` 讀回來的狀態仍是 `true` 是因為 `isEnabled()` 只查鍵值存在」。實際上：

- **`rg "isEnabled(" lib/` 全庫 0 命中** —— FMP 從來沒有呼叫過 `launch_at_startup` 的 `isEnabled()`。
- `LaunchAtStartupNotifier._load()`（`desktop_settings_provider.dart:102-112`）的 `state.enabled` 直接讀 **Isar 的 `settings.launchAtStartup`**，跟登錄檔完全無關。
- 所以「設定頁開關仍顯示為開」的原因更簡單：**根本沒有任何程式碼會去核對登錄檔**，不是「用了一個不夠精確的 API」。

**真正的機制**（我用套件原始碼複驗）：`launch_at_startup` 0.5.1 在 FMP 的用法下（從不傳 `packageName`）恆走 `AppAutoLauncherImplWindows`，也就是寫 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`，**值是絕對路徑字串**（`app_auto_launcher_impl_windows.dart:48-64`）。所以：

1. 使用者在路徑 A 啟用 → 登錄檔寫入 `<路徑A>\fmp.exe`。
2. 搬資料夾到路徑 B。
3. **下次開機**：Windows 執行路徑 A → 檔案不存在 → 靜默失敗（這是 Run key 機制本身的行為，非 FMP 可控）。App 沒被啟動，所以 `_load()` / `_applyToSystem()` 都不會執行，登錄檔永遠不會被修正。
4. 只有當使用者**手動**啟動 app 時，`app.dart:96` 的 `ref.watch(launchAtStartupProvider)` 才觸發 `_applyToSystem()`（`:136-152`），它會無條件用**當下**的 `Platform.resolvedExecutable` 重新 `disable()` → `setup()` → `enable()`，**把登錄檔修好** —— 而且完全靜默，使用者不知道曾經壞過。

**症狀窗口精確地存在於「搬完資料夾」到「下一次手動啟動」之間。而依賴開機自啟的人，正是最不會手動啟動的人** —— 對他們而言這個窗口是無限長的。

**未驗證**：本機 `HKCU:\...\Run` 與 Startup 資料夾都沒有 FMP 項目（這份 checkout 從未啟用過自啟），所以沒有既存登錄檔項目可交叉驗證。

**處置：保留。** 但修法建議要調整 —— issue 提的「啟動時比對路徑並重新註冊」其實**已經有一半存在**（`_applyToSystem()` 就是無條件重註冊），缺的是：(a) **先讀登錄檔現值做比對**（`win32_registry` 已是 `launch_at_startup` 的傳遞依賴），(b) **偵測到漂移時告知使用者**，把現有的靜默修復變成有回饋的修復。

**成熟做法對照**：VS Code 與 Obsidian 的可攜版**都不提供開機自啟功能**，理由與此 issue 命中的問題完全一致 —— 路徑不穩定的可攜版本來就不適合綁定寫死路徑的機碼。FMP 現況其實比它們做得更進一步（可攜版也支援自啟、且有啟動時自我修復），只是修復是靜默的、且只在手動啟動後才會發生。把它「浮出水面」是最小的正確修正。

### issue #35 —— **保留，但描述要改三處**

**能重現：能。** 4 個 `read()` 沒有 try/catch（issue 列了 3 個），且 `rg "PlatformException" test/` **0 命中** —— 完全無測試覆蓋。`resetOnError` 預設 `false`（`android_options.dart:16`），不會自動復原。

**要改的三處**：

| 項目 | issue 寫的 | 應改為 |
|---|---|---|
| Android 機制 | 「Keystore + `EncryptedSharedPreferences`」 | 四處都用無參數的 `const FlutterSecureStorage()`，`encryptedSharedPreferences` 維持預設 **`false`**，所以走的是舊式自訂 cipher（RSA 在 Keystore 包金鑰 + AES-GCM 加密值，密文 base64 存進**普通的** SharedPreferences XML）。**Jetpack Security 根本沒被啟用。** |
| Windows 機制 | 「DPAPI，密文綁使用者設定檔」 | `flutter_secure_storage_windows` 3.1.2 用 **AES-GCM（CNG）+ 金鑰存 Windows Credential Manager + 密文寫成 app support dir 下的檔案**。結論方向對（搬機器解不開），但**比 DPAPI 更不可攜** —— 需要「密文檔案」與「Credential Manager 條目」兩份 artifact 同時對上。 |
| 影響路徑 | 「帳號狀態初始化 → 帳號相關路徑整條炸掉」 | **帳號狀態走 Isar**（`account_provider.dart:214-241` 用 `findFirstSync()` + `watch()`），不碰 secure storage；`isLoggedIn()` 三處也都走 Isar。啟動路徑的兩個 `FutureProvider` 都已有 try/catch（`account_provider.dart:124-135`、`:187-203`）。**真正的永久 loading 在 `audio_settings_provider.dart:137-162`** —— `readApiKey()`（`lyrics_ai_config_service.dart:83`，issue 未列的第 4 處）拋例外會讓 `_loadSettings()` 中斷，`state` 永不更新，`isLoading` 卡在 `true`（`:61`），`audio_settings_page.dart:17` 永久 spinner。**而 Auth For Play 的三個開關就在那一頁**（`audio_settings_page.dart:88-95`）。 |

**要補的一項（issue 最有價值卻缺席的部分）**：`flutter_secure_storage` 9.2.4 的 README 第 81-85 行明確寫：

> _Note_ By default Android backups data on Google Drive. It can cause exception `java.security.InvalidKeyException: Failed to unwrap key`.
> - disable autobackup / exclude sharedprefs `FlutterSecureStorage` used by the plugin

而 `android/app/src/main/AndroidManifest.xml:25-29` 的 `<application>` 標籤**沒有 `android:allowBackup="false"`、沒有 `fullBackupContent`、沒有 `dataExtractionRules`**（預設 `allowBackup="true"`）。**FMP 精確踩中了上游 README 點名的觸發條件，而且這是 repo 裡一行就能修的設定。**

**處置：保留，不要併入其他重構。** 這是獨立的錯誤處理缺口，不依賴任何進行中的架構調整。

**修復方向的一個警告**：**不可以**把 `PlatformException` 併進現有的 `on FormatException` / `on TypeError` → `_discardMalformedCredentials()` 分支 —— 那會在暫時性的 Keystore 失敗時**永久刪掉使用者憑證**。這正是 issue 主張「必須區分『沒有憑證』與『存取憑證失敗』」的原因，那個主張是對的。

### 順帶處置（本輪掃到但不在指定範圍的）

- **issue #37**（`runApp()` 前的靜默失敗）—— **【證實】**，見 P0-2。`MediaKit.ensureInitialized()` 仍在 `main.dart:108` 無保護。現況比 issue 撰寫時略好（`_preloadThemeSettings()` 已有 try/catch），其餘風險點原封不動。**建議保留。**
- **issue #42**（`preferredAudioDevice*` 是死欄位，但備份仍照樣匯出匯入）—— **第一條成立，第二條是錯的，應從 issue 中撤下。**
  第一條（功能缺口）**【證實】**：`settings.dart:197,200` 兩個欄位在排除 `database_catalog.dart`（viewer dump）與 `backup_service.dart` 後**零讀寫點**；選裝置路徑 `audio_provider.dart:1451` → `media_kit_audio_service.dart:617` 不寫 `Settings`。
  第二條（備份在搬運死資料）**【推翻】**，三層互相獨立的反證，我逐條複驗：
  1. **`backup_data.dart` 裡完全沒有這兩個欄位** —— `grep -n "preferredAudioDevice\|customDownloadDir" lib/services/backup/backup_data.dart` **零命中**。JSON 裡不會出現這兩個 key。
  2. **`backup_service.dart:765-769` 是「保留本機值」不是「搬運備份值」** —— 賦值來源是 `currentSettings`（`:682` 的 `await _isar.settings.get(0)`，即本機現有設定），不是 `settingsBackup`，而且上面就有一行註解 `// 设备相关设置 - 保留当前值`。
  3. **那個測試的名字寫著它在測相反的事** —— `backup_service_test.dart:145` 是 `'importData restores new settings fields and **preserves device-specific ones**'`；`:150-151` 把 `'device-1'` / `'USB DAC'` 寫進**本機 DB**，`:265-266` 斷言匯入後**仍然**是這兩個值。那兩個值從頭到尾沒有進過 `BackupData`。這是保留測試（preservation），不是往返測試（round-trip）。

  **備份層對這兩個欄位的處理反而是正確的** —— 它已經把它們歸類為「裝置局部、不該跨裝置搬運」（§1.9 的三層分類）。**修 #42 不需要動備份。**
  順帶：issue #42 那條指控**放在 `RadioStation.note` 上才成立**（`radio_station.dart:55`）—— 它是死欄位、**而且真的有進備份 DTO**（`backup_service.dart:200,630`、`backup_data.dart:470`）。

- **issue #38**（CI 的 Verify generated files 名不副實）—— 技術判斷**【證實】**（`git ls-files 'lib/**/*.g.dart'` = 0），但**問題已在 `ce100d32` 修掉**（該步驟已從 `ci.yml` 移除，並用 `dart format --set-exit-if-changed` 取代）。**建議留言指向該 commit 後關閉**（Q50）。

---

## 14. 驗證記錄

### 14.1 基準【事實】

| 項目 | 結果 |
|---|---|
| `git status --short` | 空（工作樹乾淨，本輪未修改任何專案檔案，除了本報告本身） |
| HEAD | `754411eb`（2026-09-01 23:29:58 +0800） |
| `git rev-list --count HEAD` | 1367 |
| `flutter --version` | Flutter 3.47.1 stable / Dart 3.13.1 / revision `6655482ec0` |
| `flutter analyze` | **No issues found!**（4.6s） |
| `flutter test --exclude-tags live` | **All tests passed! — 1234 條**（59s） |
| `lib/` 規模 | 311 個 `.dart`（不含 `.g.dart`）、**94,537 行** |
| `test/` 規模 | 185 個檔、**46,716 行** |
| 生成碼 | `lib/data/models/*.g.dart` 11 檔 **31,651 行**；`lib/i18n/strings.g.dart` **18,272 行 / 687 KB** |
| 本機 Isar DB | `~/Documents/FMP/fmp_database.isar` = 5,242,880 bytes（5 MiB） |

### 14.2 依賴解析探針【事實，scratchpad 內的獨立探針套件，未觸碰專案 pubspec】

方法：把 `pubspec.yaml` 複製到 scratchpad、改名為 `resolve_probe`、砍掉 `flutter:` 區塊，跑 `flutter pub get`。依賴解析只看 pubspec，不看原始碼，所以這是對真實遷移的忠實模擬。

| 探針 | 改動 | 結果 |
|---|---|---|
| **baseline** | 無 | ✅ 解析成功，`analyzer 5.13.0` / `build 2.4.1` / `build_runner 2.4.13` / `source_gen 1.5.0` / `dart_style 2.3.2` —— **與專案 `pubspec.lock` 完全一致，探針有效** |
| **C：只升 Riverpod** | `flutter_riverpod`/`riverpod_annotation` → `^3.0.0` | ❌ **version solving failed**：「resolve_probe depends on both riverpod_annotation ^3.0.0 and flutter_test from sdk, **isar_generator >=3.0.1 is incompatible with build_runner >=2.4.10**」 |
| **issue44-verbatim：完全照 issue #44 的步驟** | `isar`→`isar_community` 三個條目，其他不動 | ❌ **version solving failed**：「`isar_community_generator >=3.3.1` depends on `build ^4.0.0` and **`slang_build_runner <4.8.0` depends on `build ^2.2.1`**」 |
| **issue44 + slang4（最小可行配方）** | 上一項 + `slang_flutter`/`slang_build_runner` → `^4.19.0` | ✅ **解析成功**。`analyzer 10.2.0`、`build_runner 2.15.1`、`isar_community 3.3.2`、`slang 4.19.0`、`flutter_riverpod` 維持 2.6.1。SDK 下限維持 `>=3.5.0` 不影響解析 |
| **全套 + build_runner 拉到最新** | 再加 `build_runner: ^2.16.0` | ❌ **failed**：「`isar_community_generator >=3.3.2` depends on `analyzer >=8.0.0 <11.0.0` and `build_runner >=2.15.2` depends on `analyzer >=13.3.0 <15.0.0`」→ **`build_runner` 必須 `<2.15.2`** |
| **全套（isar_community + slang4 + riverpod3）** | `build_runner` 退回 `^2.4.13` | ✅ **解析成功**。`analyzer 10.2.0`、`build 4.0.7`、`source_gen 4.2.4`、`dart_style 3.1.7`、`isar_community 3.3.2`、`slang 4.19.0`、**`flutter_riverpod 3.0.3`** |
| **D：再刪 `riverpod_annotation`** | 從上一項移除該行 | ✅ **解析成功**，**`flutter_riverpod 3.4.2`（最新）** —— 證實那個死依賴會把 riverpod 卡在 3.0.3 |

**結論**：issue #44 的步驟不完整；最小可行配方是 **isar_community + slang 4.x**；完整現代化配方再加 **riverpod 3 + 刪 riverpod_annotation**，且 `build_runner` 必須釘在 `<2.15.2`。

### 14.3 子代理結論的抽驗【事實】

本輪派了 7 個子代理（1 個因 opus session 限流中斷後恢復）。抽驗了以下關鍵結論，全部通過：

| 抽驗項 | 我的複驗方式 | 結果 |
|---|---|---|
| issue #38 已在 `ce100d32` 修掉 | `git merge-base --is-ancestor ce100d32 HEAD` → YES；`rg "Verify generated\|git diff --exit-code" .github/workflows/` → 0 命中；`git ls-files 'lib/**/*.g.dart'` → 0 | ✅ |
| `riverpod_annotation` 零使用、`ProviderObserver` 零使用、`.valueOrNull` 29 處 | `rg -c` 三組 | ✅ 全部相符 |
| 協調器循環 A 的去邊與回邊 | 逐字讀 `library_invalidation_coordinator.dart:149-195` 與 `rg "libraryInvalidationCoordinatorProvider" lib/providers/library/playlist_provider.dart`（9 行命中） | ✅ |
| `CONTEXT.md` 因 `c09aec10` 過時 | `grep -n "allowlist" CONTEXT.md` → `:38`、`:47`；`git show --stat c09aec10` → 只改了兩個 `AGENTS.md` 與兩個 `.dart`，**沒有 `CONTEXT.md`** | ✅ |
| `youtube_stream_test_page.dart` 的 Cookie 繞過 + 無 `kDebugMode` gate | 逐字讀 `:738-755`；`rg "kDebugMode"` 於 debug 頁與 developer options 三檔 → 0 命中 | ✅ |
| `AndroidManifest.xml` 未關 `allowBackup` | `sed -n '20,35p'` 逐字讀 `<application>` 標籤 | ✅ |
| libmpv/FFmpeg 是 LGPL 非 GPL | 自行 `gh api` 讀 `packages/mpv.cmake`（`-Dgpl=false`）與 `packages/ffmpeg.cmake`（`--disable-gpl --disable-nonfree --enable-version3`） | ✅ 與授權子代理的結論獨立吻合 |
| `audio_runtime_platform.dart` 已支援三個新平台 | 逐字讀全檔 | ✅ |
| 各 collection 持久化屬性數 | 從生成碼的 `CollectionSchema` 直接數（`grep -c "^      id: [0-9]*,"`），而非數手寫檔的欄位行 | ✅ 修正了初步 grep 的高估（Settings 實際 57 而非 108） |
| **issue #42 的第二條指控是錯的**（推翻既有 issue，所以三層全驗） | ① `grep "preferredAudioDevice\|customDownloadDir" backup_data.dart` → 零命中；② 逐字讀 `backup_service.dart:763-770` 確認賦值來源是 `currentSettings` 且有 `// 保留当前值` 註解；③ 讀 `backup_service_test.dart:145` 的 test 名稱與 `:150-151`/`:265-266` 的斷言 | ✅ |
| 5 個自訂色是死欄位 | 對每個欄位跑 receiver-limited pattern（`settings.X` / `_settings!.X` / `..X`）並排除 catalog / backup / models → 5 個全部 0 個業務讀取點；對照 `primaryColorValue` 有 5 個命中 | ✅ |
| `Track.sourceKey` 是死索引 | `rg -c "sourceKeyEqualTo" lib/ test/ --glob '!*.g.dart'` → 0 命中 | ✅ |
| 平台層的 SMTC 5 個呼叫點與各 Windows 分支 | 逐一 `grep -n "Platform.isWindows"` 於 `audio_provider.dart`（409/1645/1729/2856/2897）、`app.dart:88-99`、`update_service.dart:517-528`、`app_theme.dart:69-73,95-99` | ✅ |
| **`qq_music_sign.dart` 的譜系 B 特徵**（授權子代理的核心指控，逐條驗） | `grep -nE "_k1\|_l1\|_t\b\|t1\|t3\|ls2\|ls3\|x[1-7]\|RegExp\|zzb"` → `:6,25,28,54,55,58,60-63,67,74-78,82,83` 全部命中，含 `RegExp(r'[\\/+]')` 確實**不含 `=`** | ✅ |
| 網易雲 6 個常數 | `grep -nE "0CoJUm6Qyw8W8jud\|0102030405060708\|e82ckenh8dichen8\|36cd479b6b5\|nobody\|00e0b509f6259df8"` → `:18,21,24,32,43,75` | ✅ |
| **bilibili-API-collect 是 CC BY-NC 4.0 而非無授權**（推翻我上一版的結論，所以查到歷史層） | `gh api repos/SocialSisterYi/bilibili-API-collect` → `{archived:true, license:null, size:220}`；`commits` → **只剩 3 筆**（2026-01-28~30 "deprecated"），歷史已被重寫；鏡像 `pskdje/bilibili-API-collect` 的 `LICENSE` 首行逐字為 `Creative Commons Attribution-NonCommercial 4.0 International`，且其 **LICENSE commit 可追到 2020-07-31 / 2021-11-14** | ✅ |
| 專案沒有 NOTICE / THIRD_PARTY / COPYING | `rg --files -g "*NOTICE*" -g "*THIRD*" -g "*COPYING*"` → 0 命中 | ✅ |
| Harmonoid 的 `imageCache` 設定值 | `gh api repos/harmonoid/harmonoid/contents/lib/main.dart` 解碼後 `grep` → `:33 maximumSize = 1000`、`:34 maximumSizeBytes = 200 * 1024 * 1024` | ✅ |
| slang 4 的生成檔會不會被誤 commit（我自己寫進報告的推測） | `git check-ignore -v lib/i18n/strings.g.dart` → `.gitignore:29:*.g.dart` | ❌ **推測錯誤，已更正**：ignore 規則是全域 glob，新增的 3 個檔自動涵蓋 |

**一次子代理失效**：平台阻塞的子代理第一次回傳只有一句「參考專案 fork C 還在執行中」，沒有任何內容。用 `SendMessage` 要求它「不要等子代理、把已查到的整理出來」後拿到完整報告。**這是它自己 fan-out 出去的第三層子代理沒回來所致，不是查證失敗。**

### 14.4 實跑探針【事實，全部在 scratchpad，未觸碰專案檔案】

上一版有 8 條「未驗證」。這一輪把其中 5 條實跑掉了，結果如下。

#### 14.4.1 `isar_community` 的 Android 16 KB 對齊 —— 自己量，不引用 issue

issue #44 引用了它自己的量測。我沒有採信，改成下載 binary 用自寫的 ELF program-header parser（`scratchpad/isar-so/elfalign.py`，純 Python `struct`，讀 `PT_LOAD` 段的 `p_align`）逐個量：

| ABI | isar 3.1.0+1（現況，pub cache） | isar_community 3.3.2（pub 套件內） | 16 KB 相容 |
|---|---|---|---|
| arm64-v8a | `0x1000` ×4 段 | **`0x4000` ×4 段** | ❌ → ✅ |
| armeabi-v7a | `0x1000` ×4 | **`0x4000` ×4** | ❌ → ✅ |
| x86_64 | `0x1000` ×4 | **`0x4000` ×4** | ❌ → ✅ |
| x86 | `0x1000` ×4 | **`0x4000` ×4** | ❌ → ✅ |

兩個補強確認：① **pub 上 `isar_community_flutter_libs` 3.3.2 內的 4 個 `.so` 與 GitHub release 資產 SHA-256 逐字節相同**（例如 arm64 兩邊都是 `beb34e20…68d78`），所以量 release 資產等同量實際會被打包的檔；② `android/build.gradle` **不含任何下載邏輯**（`grep -nE "download|http|url"` → 0 命中），`.so` 是直接 bundle 在 `android/src/main/jniLibs/` 的，不會在建置時被換掉。

順帶一筆與 Android 無關但值得記錄的：`isar_community_flutter_libs` 的 **`linux/libisar.so` 仍是 `0x1000`**。Linux 沒有 16 KB 頁面要求，不影響，但如果未來要做 Linux 平台擴展（§4）需要知道這件事。

#### 14.4.2 生成碼等價性 —— `isar_community_generator` vs `isar_generator`

`scratchpad/probe-cm-codegen`：複製 `lib/data/models/` 的 15 個手寫檔（`sed` 把 `package:isar/isar.dart` 換成 `package:isar_community/isar.dart`），把 `number_format_utils.dart` 與 i18n 換成 stub（generator 只看回傳型別，不看實作），跑 `dart run build_runner build`。

- ✅ **11 個 collection 全部生成成功**，`wrote 22 outputs`。
- ✅ 把生成檔的 import 正規化回 `package:isar/isar.dart` 後與專案現有的 `.g.dart` 逐檔 diff：**每檔恰好 2 行差異，全部是同一行** —— `version: '3.1.0+1'` → `version: '3.3.2'`。腳本逐檔排除該行後**零剩餘差異**。
- ✅ **11 個 collection 的 schema `id` hash 完全相同**（例如 `Track` 兩邊都是 `6244076704169336260`）。這是 Isar 在磁碟上比對 collection 身分用的值。

那個 `version` 欄位不是裝飾：`isar-3.1.0+1/lib/src/schema/collection_schema.dart:24` 是 `assert(Isar.version == version)`。也就是說**換套件必須重跑 `build_runner`**（否則 debug build 會斷言失敗），但這本來就是遷移步驟的一部分。

#### 14.4.3 真實資料庫原地開啟 —— 這條是關鍵

前兩項只證明「生成碼一樣」，不證明「舊檔打得開」。所以直接測：把 `~/Documents/FMP/fmp_database.isar`（**5 MB，真實使用中的資料**）**複製**到 scratchpad（原檔全程唯讀，未觸碰），用 `isar_community_flutter_libs` 3.3.2 的 `libisar.dll` + 上一步生成的 schema 開啟。

```
IsarCore using libmdbx: v0.13.8-temp-upstream-fix
COUNTS={tracks: 1195, accounts: 2, playlists: 1, playQueues: 1, settings: 1,
        searchHistorys: 2, downloadTasks: 0, playHistorys: 332,
        radioStations: 0, lyricsMatchs: 0, lyricsTitleParseCaches: 0}
SETTINGS_READ=themeMode=ThemeMode.system primaryColor=null audioFormatPriority=opus,aac
TRACK_READ=SourceType.bilibili:BV1pWNFzvEa7 title=踊り子(舞女) / Vaundy ：MUSIC VIDEO
WRITE_BACK_OK=1
```

三件事同時成立：**開得起來**（無 schema 不符錯誤）、**讀得出欄位值**（`@Enumerated` 的 `SourceType`、`ThemeMode`、`List<String>` 都正確反序列化）、**寫得進去**（`writeTxn` 成功且立即查得到）。

**結論：`isar_community` 的資料遷移成本是零 —— 不是「推測為零」，是實測。** 這也順帶推翻了「換 DB 一定要寫 migration」的直覺在 (b) 方案上的適用性。

**這條的邊界要說清楚**：測的是 **Windows x64** 的原生庫。Android 的 `.so` 我只量了 ELF 對齊（14.4.1），**沒有在 Android 上實跑開啟**。因為兩邊是同一份 Rust 原始碼、同一個 libmdbx 版本、磁碟格式與平台無關，我推論 Android 同樣成立，但這一步標**未驗證**。

#### 14.4.4 CI 那筆「純文檔卻失敗」的 run —— 是 flaky test，根因具體

run `30280237603`（commit `90d2b5a8` `docs(debugging): correct the vm service guide against measured behaviour`，2026-07-27）。`gh run view --log-failed` 的結果是 **`1239 tests passed, 1 failed, 1 skipped`**，失敗的是：

`test/services/audio/audio_controller_phase1_test.dart` → `superseded playback-starting callback does not stop the newer request`

三段連續錯誤（逐字）：

```
[ERROR] [AudioController] Failed to play track: Callback First Track
  Error: IsarError: Isar instance has already been closed
  #2  GetPlayQueueCollection.playQueues (package:fmp/data/models/play_queue.g.dart:13:52)
  #3  QueueRepository.save.<anonymous closure> (queue_repository.dart:30:39)
  #7  QueuePersistenceManager.persistQueue (queue_persistence_manager.dart:89:5)
  #8  QueueManager._persistQueue (queue_manager.dart:828:5)
  #9  QueueManager.playSingle (queue_manager.dart:402:5)
  #10 AudioController.playSingle (audio_provider.dart:704:26)
Bad state: Condition was not met after 50 event pumps
Bad state: Tried to use AudioController after `dispose` was called.
```

**根因【推論，證據是上面的 stack + tearDown 原始碼】**：`audio_controller_phase1_test.dart:236-240` 的 `tearDown` 是

```dart
tearDown(() async {
  controller.dispose();          // 不 await 進行中的播放鏈
  toastService.dispose();
  await isar.close(deleteFromDisk: true);   // 立刻關掉 Isar
  ...
});
```

`controller.dispose()` **不會 drain 正在飛的 `playSingle → _persistQueue → writeTxn` 鏈**，`isar.close()` 緊接著執行。於是一個測試啟動的非同步工作可以跨越測試邊界，落在已關閉的 Isar 上。這正是 **P2-2**（40 份重複的 Isar 測試樣板）在生產環境的具體代價。

**復現嘗試**：本機連跑該檔 10 次，**10/10 全部通過**（`flutter test test/services/audio/audio_controller_phase1_test.dart`）。所以這是低頻 flake，只在 CI 的 Linux runner（較慢、資源競爭）上偶發。**它不是那個 docs commit 造成的** —— 該 commit 只改 `docs/`，不可能影響這個測試。

---

### 14.5 本輪未完成 / 未驗證

上一版列了 8 條，本輪關掉 5 條（§14.4 與 §5.1.1、§6.1–6.4）。以下是**剩下的**，加上本輪新產生的。

**A. 需要實機 / 特定環境，本輪確實做不到**

1. **Riverpod 3 的三個行為變更未實機驗證。** out-of-view pause（`TickerMode`）對背景播放、下載、tray 的影響，以及 `==` 過濾對 6 個回傳新集合的 `Provider<List<Track>>` selector 的 rebuild 次數變化。這兩件 `flutter test` 涵蓋不到，要在模擬器與 Windows build 上量，而且必須先實際完成升級。
2. **平台擴展的建置未驗證。** `smtc_windows` 留在 `pubspec.yaml` 時 `flutter build linux` / `macos` 能否乾淨通過。沒有 Linux / Mac 環境。
3. **issue #39 的登錄檔狀態無法交叉驗證。** 本機 `HKCU:\...\Run` 與 Startup 資料夾都沒有 FMP 項目（這份 checkout 從未啟用過自啟），而啟用它會改動你的系統，本輪不做。
4. **`isar_community` 在 Android 上實際開啟舊 DB 未測**（§14.4.3 的邊界）。Windows 已實測成功，Android 只量了 `.so` 對齊。

**B. 本輪新產生的、值得後續量的**

5. **slang 4 的 `deferred` 對啟動時間的實際效果未量測。** §6.1 量到 `timeToFrameworkInit` 中位數 1.86 s 主宰整個啟動，而 slang 4 拆檔 + 延遲載入是唯一會作用在那一段的改動。要得出數字必須先完成遷移，再重跑同一組 `--trace-startup`。**這是本輪唯一一個「已知該量、但必須先改碼才量得到」的項目。**
6. **§6.2 的 276 MB 閒置佔用，組成未拆解。** 要用 heap snapshot（`docs/debugging-with-vm-service.md` §3.2）才知道 Flutter 引擎 / libmpv / WebView2 / Isar mmap / imageCache 各佔多少。223 個執行緒的來源同樣未逐一歸屬。
7. **P2-20 的 flake 未在本機復現**（10 次全過）。根因診斷建立在 CI 的 stack trace 與 `tearDown` 原始碼上，屬**推論**。要證實需要在 CI 或加壓環境下反覆跑。

**C. 查證到極限、剩下的部分查不到**

8. **`qq_music_sign.dart` 的確切轉錄來源無法斷定。** 知乎原文（2022-09-05）、`keylin/TestMusic`（2026-01 建庫）與 FMP 該檔（commit `4e781d9b`，2026-02-10）時間上都容許。只能斷定屬同一表達譜系 —— 而該譜系的**所有已知來源都無可用授權**，所以 P1-12 的裁決不受影響。也**沒有窮舉 29 個公開實作的完整時間線**，理論上可能存在更早且有明確授權的譜系 B 實作。
9. **ObjectBox Binary Licence 的第 4–6、9 條未取得逐字全文**（頁面很長，抽取只回傳被查詢導向的片段）。已取得的第 2、7、10 條足以支撐 §9.1 的結論（免費商用、無資料量門檻、禁止修改/逆向、可撤銷、需列入 NOTICE）。
10. **Immich 的 Discord 公告查不到**（不對外索引、需登入）。已確認 blog、release notes、GitHub PR 與 Discussion 四個管道**都沒有**一句話說明離開 Isar 的原因；`mobile/README.md` 到 2026-09 仍寫著在用 Isar（過時文檔）。所以「為什麼離開 Isar」**只能從行為推論**，這一點維持不變。
11. **bilibili-API-collect 原倉庫被清空前的 LICENSE 未從 Wayback Machine 直接驗證。** 證據鏈是：原倉庫歷史只剩 3 筆（已重寫）→ 貢獻者鏡像自述同步於清空前 → 鏡像的 LICENSE commit 可追到 2020-07-31。這已經很強，但嚴格說是間接證據。

**D. 已由其他途徑閉合，不再列為未驗證**

- ~~libmpv 二進位本身是 LGPL 還是 GPL 建置~~ —— 授權子代理標為未驗證，但我在 §5.3 已直接讀了建置腳本（`packages/mpv.cmake` 的 `-Dgpl=false`、`packages/ffmpeg.cmake` 的 `--disable-gpl --disable-nonfree --enable-version3`），是 LGPL。
- ~~Spotube / Harmonoid 的 `imageCache` 設定值~~ —— §6.3 已補齊並抽驗。
- ~~Immich 行動端有沒有 log 頁面~~ —— §6.3 已補齊（有，且設計完整）。

---

**最後，本輪的產出狀態**：報告未 commit（本輪規則），工作樹除 `docs/review/03-data-platform-license.md` 外乾淨。15 個決策點（D1–D15）與 28 條 Quick wins（Q35–Q62）都只記錄、未動手。scratchpad 保留了 9 個探針套件（6 個依賴解析 + `isar-so` + `probe-cm-codegen` + `probe-slang4`）供複核。
