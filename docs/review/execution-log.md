# 執行記錄

Phase 0–7 執行期（2026-09-02 ~ 09-08）每一輪開工前的重核與收工後的驗收。

**這是歷史，不是規則。** 每一輪記的是「開工當天發現先前的說法哪幾條已經失效或
當初就判斷錯了」，加上實機驗收看到了什麼。要知道**現在**該怎麼做，讀
`AGENTS.md`（根目錄與各子樹）；要知道某個架構決定為什麼這樣選，讀 `docs/adr/`。

**程式碼與 `AGENTS.md` 不得引用本檔。** 一份被引用的歷史快照不是歷史快照，是活
文檔，而它不會有人維護。要留下的事實請寫進它所描述的那個檔案裡。
`test/support/agents_docs_static_rule_test.dart` 守著這條規則。

節次編號沿用原本的 6.N —— 內文彼此交叉引用（「更正 §6.7 的一項」之類），改號會
把那些引用打斷。

## 索引

| 輪次 | 日期 | 子系統 | 這一輪推翻了什麼 |
|---|---|---|---|
| [6.1](#61-止血測試與-ci-基準重建2026-09-02) | 09-02 | 測試 / CI | 6 條 quick win 在開工前就已經是對的；`AGENTS.md` 的 317 個識別符裡只有 `playlistProvider` 真的不存在，其餘是語意層問題；測試基準 1220 而不是報告寫的 1241 |
| [6.2](#62-播放路徑與音源2026-09-02) | 09-02 | 播放 / 音源 | 兩條主張已被更早的 commit 修掉 |
| [6.3](#63-依賴天花板改用-isar_community2026-09-02) | 09-02 | 依賴 | — |
| [6.4](#64-資料層與-schema-治理2026-09-03--04) | 09-03/04 | 資料層 | `@Enumerated(EnumType.name)` 本來就寫字串，所以改字串 id 不動磁碟格式、不需要 migration —— 原本排進批次 schema 變更的理由不成立 |
| [6.5](#65-音訊系統媒體控制收進-nowplayingpublisher2026-09-05) | 09-05 | 音訊 | 三條說法被推翻 |
| [6.6](#66-音訊播放副作用拆成三個協作者2026-09-05) | 09-05 | 音訊 | 三條說法要更正 |
| [6.7](#67-音訊載入閂存與延後-seek2026-09-06) | 09-06 | 音訊 | 三條說法要更正；Phase 4 的驗收線需要重述 |
| [6.8](#68-音訊兩個寫不出來的拆分與檔案切分2026-09-06) | 09-06 | 音訊 | **計畫中的 F 與 G 寫不出來**（各要 15 / 26 個注入回呼），H 只有一半能寫；§6.7 的行數估算作廢 |
| [6.9](#69-音訊phase-14-收尾複審兩份佇列投影合一2026-09-06) | 09-06 | 音訊 | 十二個欄位同時存在於 `PlayerState` 與佇列狀態，沒有任何東西逼它們一致 |
| [6.10](#610-ui錯誤呈現收斂2026-09-06--07) | 09-06/07 | UI | 五條說法要更正；映射層早就存在，只是被關在播放層裡 |
| [6.11](#611-ui版面斷點與無障礙2026-09-07) | 09-07 | UI | 八條說法要更正 |
| [6.12](#612-狀態層riverpod-notifier-改寫2026-09-07) | 09-07 | 狀態層 | 十條說法要更正；**§6.8 預言「Notifier 改寫會把檔案降到 800 行」的那一半沒有兌現** |
| [6.13](#613-音訊交界推進交給後端gapless2026-09-07) | 09-07 | 音訊 | 十條說法要更正，其中兩條是介面本身：`setQueue(List)` 做不到，`supportsQueue` 兩個後端都會回 true |
| [6.14](#614-授權與揭露與一段被改寫的遠端歷史2026-09-07) | 09-07 | 授權 | Phase 7 執行時與計畫不符的地方；`origin/main` 落後 6 天 |
| [6.15](#615-測試固定圈數的-pumpeventqueueissue-43--552026-09-08) | 09-08 | 測試 | 三條說法要更正；**根因不是某一條測試，是一個形狀**；還有「條件在進入時就成立 = 一圈都沒推」這個陷阱 |
| [6.16](#616-分層邊界招牌規則失效範圍縮成結構修正2026-09-08) | 09-08 | 結構 | **Phase 6 的招牌機械規則已經死了**，而且不是命名問題；讓耦合誠實可見不需要搬 135 個檔案 |
| [6.17](#617-發版-v1100盤點推翻了三條說法2026-09-08) | 09-08 | 發版 | 「距上次發布 1134 個 commit」是錯的框法 —— 歷史重寫讓每個候選 tag 都給出同一個數字，真實的起點是 `c25d3cce`，237 個 commit |

---
### 6.1 止血：測試與 CI 基準重建（2026-09-02）

報告寫成之後樹上又動過，開工前逐條 `rg` 過一遍。**以下 6 條已失效或當初就判斷錯誤，
不可照抄**——記在這裡是為了讓後面幾個 Phase 開工時同樣先做這一步。

| 原條目 | 開工當天的實況 | 處置 |
|---|---|---|
| QW-2 `flutter pub run` → `dart run`（4 處） | `rg "flutter pub run" .github/` 零命中 | 撤銷，已是對的 |
| QW-2 補 `timeout-minutes` | `ci.yml:28,78,115` 與 `release.yml` 5 處都已有 | 撤銷，已是對的 |
| QW-2 test step 補 `--coverage` | `ci.yml:64` 已是 `flutter test --coverage --exclude-tags live` | 撤銷，已是對的 |
| QW-5 `docs/README.md` 的 `/qa` | 零命中 | 撤銷，已是對的 |
| QW-5 `refactoring-log.md` banner | 檔案已不存在 | 撤銷 |
| QW-5 `docs/build-and-release.md:293-295` 失效敘述 | 該檔引用的 6 個 `.dart` 路徑全部存在，找不到失效處 | 撤銷，原判斷有誤 |

另外三條需要修正描述，不是失效而是**當初判斷錯了**：

| 原條目 | 更正 |
|---|---|
| QW-8「`SourceManager` 5 個死方法」 | 實際零引用的只有 `parseUrlProvider` / `parsePlaylistProvider` 兩個 provider。`trackInfoSourceForUrl` **有內部呼叫**（`source_provider.dart:99,104`），不是死碼；`isPlaylistUrl` / `refreshAudioUrl` 只被測試呼叫；`needsRefresh` 零引用但**是 Phase 1.1 要復活的那段 5 分鐘邊界邏輯，不可刪** |
| QW-8「`mobilePlayerBufferSizeBytes` 是死常數」 | `media_kit_audio_service.dart:154` 有引用。但 `audio_provider.dart:3267` 的 `audioServiceProvider` 讓 mobile 一律走 `JustAudioService`，所以那個分支在生產環境**不可達**——是「有引用但走不到」，不是「無引用」。保留為防禦性 guard，已在 `lib/services/audio/AGENTS.md` 記明 |
| 01 P0-3 / QW-4「AGENTS.md 13 條錯誤斷言」 | 機械抽驗全部 `AGENTS.md` + `CONTEXT.md`：**317 個識別符裡只有 1 個真的不存在**（`playlistProvider`），**所有 `.dart` / `.json` 路徑引用零錯誤**。其餘問題是語意層的（數量過期、過度宣稱「is enforced by」、Key Paths 漏列 9 個 `lib/services/` 子目錄、`CONTEXT.md` 的 allowlist），符號檢查抓不到 |

**新測得的基準（`9bb0b8e5` 之後）**：`flutter test --exclude-tags live` = **1220 passed**，
連跑 3 次一致，耗時 31–33 秒。01/02/03 報告的 1241 / 1242 / 1234 全部作廢。

**執行到一半才發現的另外四條**（都是報告的判斷有誤，不是失效）：

| 原條目 | 更正 |
|---|---|
| QW-10「刪未使用的 `nav.explore` key」 | **有在用** —— `explore_page.dart:92` 的 `t.nav.explore`。不刪 |
| QW-9「`youtube_stream_test_page` 的 Cookie 探測加 `kDebugMode` gate」 | **指控不成立**。`_formatHeaderKeys()`（`:818`）只印 `key(長度)`，不印值；該頁還在 `developerOptionsProvider` 解鎖之後。加 gate 只會拿掉 release 版的診斷工具，不改 |
| QW-7「8 個 tooltip + 2 個播放鍵」 | 機械掃描全 `lib/ui`：**96 個 `IconButton` 裡 26 個缺 tooltip**，不是 10 個。已全部補上（`lyrics_title_bar.dart:188` 是掃描誤報，它用 `Semantics(label:)` 已經是可存取的） |
| QW-8「刪 6 個死依賴」只列了 Dart 層 | **Dart 零 import 不足以判定**。`windows/runner/flutter_window.cpp:8` 手寫 include 並註冊了 `dynamic_color` 的原生外掛，只有 **release build 才會抓到**（`error C1083`）。往後刪依賴必須兩平台各 build 一次 |

**Phase 0 的最終基準（`104bd8d3`）**：1222 passed（1220 + 新增的 `csrf` 遮蔽與
`isLocalOrPrivateHost` 分類器兩條測試），`flutter analyze` 全綠，
`flutter build apk` / `flutter build windows` 皆成功。

---

### 6.2 播放路徑與音源（2026-09-02）

同樣先逐條 `rg` 過現況。**兩條主張已經失效**（都是被更早的 commit 修掉了），
其餘成立但有多處行號位移：

| 原條目 | 開工當天的實況 | 處置 |
|---|---|---|
| 1.7 後半：`_shouldHandleTrackCompleted` 的 `duration == null` 直接放行 | **函式已不存在**（全庫零命中）。`056f20c3` 換成兩個後端各自的 `_classifyCompletion()`，`duration == null` 現在回 `EndedPrematurely` | 撤銷，已是對的 |
| P0-4「Android 播放期間的網路錯誤被完全丟棄」 | **已修**。`just_audio_service.dart:303-335` 把 `source error` 映射成 `TransportFailed(reset)` | 撤銷；T3 watchdog 仍要做（它管的是「引擎什麼都不說」的情況） |
| 1.3「`track.cid` 從不回寫」引用 `bilibili_source.dart:720, 819` | 那兩行是 `VideoPage.cid` 的建構。`Track.cid` 全庫唯一寫入點是 `import_service.dart:592` | 更正引用，結論不變 |
| 1.9 `stallsrv.py` / `holdsrv.py` 收進 repo | **全 git 歷史零命中**，只活在 scratchpad 裡 | 改成用 Dart 重寫 |

**執行中發現的三件事**（報告沒寫、實作時才浮現）：

| # | 發現 |
|---|---|
| 1 | **`Track.uniqueKey` 不含 `pageNum`**（`track.dart:334`）。解析快取只用它當 key 會把 Bilibili 分 P1 的 URL 餵給 P2 —— cid 還沒解析出來時兩者同 key。快取 key 必須另外併上 `pageNum` |
| 2 | **預取不可以落盤**。改成傳佇列實例之後若同時開 `persist: true`，這個 fire-and-forget 的寫入會撞上正在關閉的 Isar（測試 teardown 直接重現）。預取只寫記憶體，真正播放時才落盤 |
| 3 | **URL 沒過期不等於 URL 還能用**。短路必須配一個「播放失敗就作廢」的出口，否則被 CDN 403 掉但還沒過期的 URL 會在每次重試被交還回去，比不做快取還糟 |

**實機量到、需要你拍板的一項** —— **T1 = 6 秒讓 YouTube 在 bot 檢查下完全播不了**：

```
[YouTubeSource] Audio-only stream failed for s466YCiHfKw:
  Reason: Sign in to confirm you're not a bot
[PlaybackRequestSession] streamResolution exceeded its 6000ms budget
[AudioController] Failed to play track: JENNIE - FALLEN ANGEL
  Error: PlaybackTimeoutException: streamResolution exceeded 6s
（被放棄的解析在背景跑完）
[DefaultStreamResolutionService] Resolved stream for youtube:s466YCiHfKw
  in 22713ms (muxed, 446754bps)
```

逾時機制本身完全正確：6000ms 準時攔下、型別化例外、不跳歌、不進退避階梯、
畫面出現 `Cannot play "...": Connection timed out`。問題是**數值**：
androidVr 的 audio-only 被擋下之後，退到 muxed 實測要 22.7 秒（報告在 Windows 上量到 9.9 秒），
兩者都遠大於 6 秒。而 audio-only 被擋是常態不是例外。

**已定案並複驗：T1 = 25 秒，且整個請求共用一個總期限。**

逾時是「別無限等下去」的兜底，不是逼快的閘門，所以取值偏寬：太緊的代價是那些影片
一律播不出來，太鬆只是多轉一下才誠實失敗。20 秒實測仍會卡掉模擬器上 21.3–21.8 秒的
muxed 退路，25 秒才過。單獨放寬 T1 會讓最壞等待變成 (T1+T2)×2 —— 比原本要修的
Android 37.7 秒阻塞還糟 —— 所以同批加上每次請求一個 `budget.total` 期限，
fallback 只能用剩下的時間。

**實機複驗（Android 模擬器，`Medium_Phone`）**：

```
首次解析   Resolved stream for youtube:I-5e_J3LWS8 in 21137ms (muxed, 736575bps)
           Playback selection ready in 21167ms
重播同曲   Reusing resolved stream for youtube:I-5e_J3LWS8 (playback)
           Playback selection ready in 25ms
背景預取   Resolving stream for youtube:s466YCiHfKw (prefetch)
           Resolved stream for youtube:s466YCiHfKw in 19275ms
切下一首   Reusing resolved stream for youtube:s466YCiHfKw (playback)
           Playback selection ready in 32ms
```

P0-1 的兩半都成立：同一首歌重播從 21,167ms 降到 25ms；下一首因為預取寫回了佇列實例，
切歌時的解析從約 20 秒降到 32ms。

---

### 6.3 依賴天花板：改用 isar_community（2026-09-02）

仍然成立的：85 個檔案 `import 'package:isar/isar.dart'`（全庫只有這一種寫法）、
40 份複製的 `_resolveIsarLibraryPath()`（9 種拼法，行為完全一樣）、
analyzer 被釘在 5.13.0、`riverpod_annotation` 已在 Phase 0d 移除。

**兩條主張是錯的，五件事報告沒寫**：

| # | 原本的說法 | 實況 |
|---|---|---|
| 1 | 「slang 先、isar 後，拆成兩個獨立 commit」 | **這個順序做不出兩個可運作的中間狀態。** 反向也擋：`slang_build_runner >=4.4.2` 依賴 `dart_style >=2.3.7`，那需要 `analyzer ^6.5.0`，而 `isar_generator 3.1.0+1` 透過 `dart_style ^2.2.3` 把 analyzer 壓在 `<6.0.0`。真正的解法是**把 `slang_build_runner` 移除**：這個 repo 沒有 `build.yaml`，i18n 走 `slang.yaml` + `dart run slang` 的獨立 CLI，那個 build_runner shim 從來沒做過事。改成直接依賴 `slang`（它不依賴 analyzer / build / dart_style）之後，兩步就真的拆得開 |
| 2 | 「要改 `slang.yaml` 的 `output_file_name`」 | **`output_file_name` 在 slang 4 仍然有效且必填**（README 設定表）。4.0 移除的是 `output_format`，而 FMP 沒設過它。真正要加的是 `lazy: false` |
| 3 | （沒寫）`-Sync` 後綴 | 官方 MIGRATION.md 明說：4.0 預設非同步載入，**要讓 `setLocaleSync` / `useDeviceLocaleSync` 正常運作必須同時設 `lazy: false`**。只改後綴不改設定會拿到還沒載入的語言。FMP 只出 Android 與 Windows，兩者都不支援 deferred loading，`lazy` 換不到任何東西 |
| 4 | （沒寫）`intl` | slang 4 的生成碼直接 `import 'package:intl/intl.dart'`（`DateFormat` / `NumberFormat`）。Phase 0 把 `intl` 當死依賴刪掉了，這裡要加回來（`intl: any`，版本交給 `flutter_localizations`） |
| 5 | 「2.3 是純 `sed`，約 90 行變動」 | **低估。** 換 package 還牽動兩處原生設定：Windows 動態庫從 `isar.dll` 改名成 `libisar.dll`（`Abi.localName` 的回傳值也跟著改），plugin header 目錄變成 `<isar_community_flutter_libs/...>`，`windows/runner/flutter_window.cpp:8` 要跟著改。plugin class 與 registrar 名稱（`IsarFlutterLibsPlugin`）沒變 |
| 6 | 「11 collection 生成碼逐字相同」 | **逐字比對是 11 個檔全不同**，因為 analyzer 解禁把 dart_style 一起帶到 3.1.7，尾逗號排版整批改寫。但把空白、尾逗號、`version:` 字串正規化之後**完全一致** —— schema id hash、property id、index / link 定義一個都沒動。`CollectionSchema.version` 是 build-time 的 `assert(Isar.version == version)`，不是磁碟格式檢查 |
| 7 | （沒寫）解禁之後才看得見的東西 | analyzer 5.13 → 10.2 多出 **18 條新 lint**（13 條 `unnecessary_underscores`、5 條 `use_null_aware_elements`），而 CI 跑的是裸 `flutter analyze`（exit 1）；build_runner 2.15 **移除了 `--delete-conflicting-outputs`**，10 個檔案與兩支 workflow 都還寫著它 |

**驗收記錄**：

| 項目 | 結果 |
|---|---|
| analyzer 天花板 | `5.13.0 → 10.2.0`；`build 2.4.1 → 4.0.7`、`source_gen 1.5.0 → 4.2.4`、`build_runner 2.4.13 → 2.15.1` |
| `flutter analyze` | 全綠（修掉 18 條新 lint 之後） |
| 測試 | 1254 條全過，與 Phase 2 開工前的基準相同 |
| 生成碼 | 11 個 collection 正規化後逐字一致（見上表 #6） |
| 16 KB 對齊 | `libisar.so` 四個 ABI 的 LOAD align `0x1000 → 0x4000`（先在 pub cache 裡驗，再從建好的 APK 裡驗 3 個實際打包的 ABI）。APK 內其餘原生庫本來就是 `0x10000`，也合規 |
| 真實資料庫 | `Documents/FMP/fmp_database.isar`（5.2 MB）複製一份，用 isar_community 3.3.2 原地開啟：11 個 collection 共 **1,534 列**全部讀得出來、Track 反序列化正常、寫入 + 刪除來回一次成功 |
| Android 實機 | AVD 是 `sdk gphone16k`（`ro.boot.hardware.cpu.pagesize = 16384`）—— 正是會觸發對齊對話框的映像。app 正常啟動、Isar 開啟、YouTube 曲目播放成功並寫入播放歷史，logcat 沒有任何對齊抱怨 |
| slang 4 語系切換 | 設定頁選「繁體中文」後整棵 UI 立即切換（`setLocaleSync`）；`pm clear` + `cmd locale set-app-locales zh-TW` 之後重啟，通知頻道名稱是 **`FMP 音訊播放`**（zh-TW），裝置語系為英文時是 `FMP Audio Playback` —— 兩個方向都對，證明 `useDeviceLocaleSync()` 在 `AudioService.init()` 之前同步生效，P1-9 的修法沒被弄壞（若失效會落到 base locale 的 `FMP 音频播放`） |
| Riverpod 3 解鎖 | `flutter pub add --dry-run flutter_riverpod:^3.0.0` 解得開（會動 13 個依賴），不再 version solving failed。**實際升級仍留在 Phase 3**（03-D4 方案 A） |
| Windows | `flutter build windows` 成功（原生 include 改動有編譯與連結驗證）；跑起來開啟真實資料庫，關閉後 11 個 collection 列數與備份完全一致 |

**兩件據實記錄的事**：

1. **Windows 子視窗的執行期路徑沒有實際驅動過。** `flutter_window.cpp` 改的是給歌詞子視窗用的
   plugin 註冊，只有編譯 + 連結驗證（header 路徑錯會編不過，符號錯會連不起來），
   registrar 名稱沒變。要驅動它得先在 Windows 上成功播放一首歌，而這台機器目前
   被 Bilibili 限流（HTTP 412）、YouTube 擋 bot 檢查。Windows 端也沒有語意樹可用。
2. **開啟後資料庫檔案從 5,242,880 縮到 2,686,976 bytes。** 列數逐項不變（1,534），
   所以是回收空閒空間不是掉資料。縮的比例（約 1.95）與 FMP 自己既有的
   `compactOnLaunch(minRatio: 2.0)` 吻合，那段設定這一期沒動過。

---

### 6.4 資料層與 schema 治理（2026-09-03 / 04）

仍然成立的：`@Enumerated(EnumType.name)` 本來就寫字串所以 M5.5 不改磁碟格式、
Isar 的 `_requireNotInTxn()` 是 Zone 層級判斷所以匯入不能只加一層外層交易、
`docs/adr/` 是空的（這輪寫了頭兩份）。

**九條改變做法**：

| # | 原本的說法 | 實況 |
|---|---|---|
| 1 | 「備份今天沒有靜默遺失，缺的 3 個是刻意排除的裝置設定」 | **前提是錯的。** `Settings` 有 57 個持久化欄位，`SettingsBackup` 只涵蓋 44，缺 13。程式碼裡的註解只涵蓋裝置組與桌面平台閘控組；`railExpanded` / `detailPanelExpanded` / `detailPanelWidth` / `schemaVersion` **零說明**，而且每次匯入都被 `createBootstrapSettings()` 重設。前三個已補進備份 |
| 2 | 「M5.5 併進批次 schema 變更，邊際成本近零」（`:482`） | **前提不成立。** 這項改動不改磁碟格式、不需 migration、不碰備份格式與 catalog，它與那個批次共用的成本是 0。真正的理由是 Phase 9.1 前置 ＋ 修掉 **7 條**靜默改寫路徑（5 個 collection 的生成 reader 各一，加 `backup_service` 與 `download_scanner` 兩處手寫），不是 2 條 |
| 3 | 「`SettingsBackup` 把欄位手抄 4 遍」 | **6 處**。DTO 沒有 `fromSettings` / `applyTo`，那兩個方向被內聯進 `BackupService`。加一個欄位要改 2 個檔案 6 個地方 |
| 4 | 「守門測試掃 `settings.dart` 的欄位宣告」 | **會誤判。** `Settings.useAuthForPlay(String)` 是方法，`SourceSettingsEntry.useAuthForPlay` 是欄位，同名。改掃 `settings.g.dart` 的 `PropertySchema`，並限定在 `SettingsSchema` 區塊（該檔共 60 個，其中 3 個屬於 embedded 物件） |
| 5 | 「面板欄位跟桌面設定一樣做平台閘控」 | **錯的。** `_DesktopLayout` 由螢幕寬度斷點選出（`responsive_scaffold.dart:78`），不是平台；Android 平板在寬版面同樣會用到側欄與詳情面板。改成無條件還原 |
| 6 | 「`addTracks` 的交易本體 321 行」 | **129 行**（`:289-417`）。原本的量測把它跟後面的 `replaceTracksFromRemoteRefresh` 併在一起算了 |
| 7 | 「`Isar.isOpen` 存在」 | 是**實例 getter**（`isar.dart:148` 的 `bool get isOpen`），不是靜態成員 |
| 8 | 「#43 的根因是 `tearDown` 不 drain」（`:961` 的改判） | **只對一半，而且原 issue 的推測也只對一半。** 兩條根因獨立存在：(a) `audio_controller_phase1_test.dart:1310` 寫死的 `pumpEventQueue(times: 1)`，(b) `queue_manager.dart:212` 用 `Future.delayed(10s)` 排的孤立 track 清理沒有 handle 所以 `dispose()` 取消不了。兩條都修了 |
| 9 | 「3d 邊界收斂待驗收」 | 開工當天量測已經是 54（驗收線 < 60）。M6.2 之後降到 **19** |

**執行中發現，報告寫的時候不知道的**：

| # | 發現 |
|---|---|
| A | `backup_service.dart:502` 與 `:520` 兩筆交易只是在補償 `addTracks` 蓋掉的 `updatedAt` / `coverUrl`。補償邏輯仍然需要，但可以收進同一筆交易 |
| B | `existingHistoryKeys`（`backup_service.dart:534`）在迴圈內從不 `add`，同一份備份裡重複的播放紀錄會重覆插入。已修 |
| C | `kBackupVersion` 的說明註解只描述到 v3，M5.6 把常數改成 4 時沒更新。已補 |
| D | **本機 `dart format` 與 CI 的結果不一致**：同一套 Flutter 3.47.1 / Dart 3.13.1，本機判定 `lib/` 333 檔有 250 檔要重排（Dart 3.7 tall style），CI 的 `Check formatting` 卻是 success。已開 issue #53。在查清楚之前不要對舊檔跑整檔 `dart format` —— 這輪已經害過一次，那個 commit 被改寫掉了 |
| E | 全庫**沒有**單檔輪替的先例可沿用。`lyrics_cache_service` 的 `_evictOldest` 是多檔 LRU 淘汰，形狀不同 |
| F | `main.dart:51/66` 的錯誤處理器掛在 `ensureInitialized()`（`:71`）之前，而 `path_provider` 要等 binding。log sink 因此必須延遲初始化，並在掛上時回填記憶體緩衝 |

**驗收記錄**：

| 項目 | 結果 |
|---|---|
| `flutter analyze` | ✅ No issues found |
| `flutter test --exclude-tags live` | ✅ **1322 條全過**（Phase 3 前半結束時是 1289） |
| `dart run slang` | ✅ 重新生成後 analyze 仍綠 |
| repository 邊界 | ✅ 152 → **19**，且由 `isar_boundary_static_rule_test.dart` 釘住 |
| 真實資料庫副本 v1 → v2 | ✅ 11 個 collection 1,534 列不變，三筆 entry 值與舊欄位一致，舊欄位未被清空，連跑三次逐字相同 |
| M5.5 未知 source id（實機） | ✅ 用 VM Service 寫入 `sourceType: 'unknown'` 的 PlayHistory，冷關 app 後重啟讀回仍是 `unknown` |
| M5.6 每源設定（實機） | ✅ 三個音源的預設串流優先級與播放認證與 `kDefault*` 一致；改值後重啟保持 |
| M7 log 落盤（實機） | ✅ Android `app_flutter/FMP/logs/fmp.log` 與 Windows `Documents/FMP/logs/fmp.log` 都有內容，第一行是 sink 掛上前的啟動 log（緩衝回填有效），跨行程重啟 append（10,865 → 30,332 bytes），全檔無敏感 pattern |
| #43 的 `IsarError` 噪音 | ✅ 同一個測試檔從 33 筆降到 **0** |

**Phase 3 自己的實機驗收（`:325`）**：

| 項目 | 結果 |
|---|---|
| Android 背景播放 5 分鐘不中斷 | ✅ **5 分 14 秒**連續（03:28:12 → 03:33:26），`dumpsys media_session` 的 position 單調推進 6,547 → 135,548 ms，並在 03:31:22 掉回 6,751 —— **單曲循環的「播完→重播」轉換在完全沒有 UI 的情況下發生**。另一次獨立觀察：整首 5:42 在背景播到 `EndedNaturally()`。最後停止的原因是模擬器掉網（`BufferStarvationWatchdog` 偵測緩衝 15 秒 → 自動重試 → `網路連線失敗`），不是 out-of-view pause —— 而那套停滯偵測與重試本身也是在背景跑的 |
| Android 下載進度持續更新 | ✅ 觸發下載後立刻離開歌單頁，檔案 8 KB → 4,164 KB → 16,284 KB 完成落地，`已下載` 頁反映結果 |
| Windows 最小化到 tray 後播放不停 | ❌ **沒驗到**。縮到系統列本身成立（視窗數 0、行程存活、log `Minimized to tray`），但第一次嘗試時歌曲已在 04:10:36 自然播完（`No next track available`），我 04:11:13 才關視窗。後續三次都卡在 Windows GUI 驅動：用 Win32 `ShowWindow` 從托盤還原會讓 Flutter 停止繪製、熱重啟兩次讓 app 直接退出、`orca computer click` 的座標落到了其他視窗。**這是工具鏈阻塞，不是程式碼結論** |

**Windows 上的意外收穫 —— 真實生產資料庫**：

| 項目 | 結果 |
|---|---|
| v1 → v2 遷移 | ✅ `schemaVersion = 2`，`sourceSettings` 三筆的值與六個舊欄位**逐項一致**，而六個舊欄位**原封未動** —— 降級無損的保證在真實使用者資料上成立，不是在副本上 |
| M5.2 面板持久化 | ✅ `detailPanelWidth = 438.67`，是使用者自己拖出來的值，不是預設的 380 |
| M7 的實際價值 | log 檔是唯一讓人分辨「被托盤暫停」與「歌自然播完」的證據；沒有它只能看到位置停住 |

**三件據實記錄的事**：

1. **`bilibili_source_test` 有 2 條 `tags: 'live'` 的測試在本機是紅的。** 它們打真實
   B 站 API，這台機器被風控（HTTP 412）。專案的驗收指令本來就是
   `--exclude-tags live`，同檔其餘用 mock 的測試全過。
2. **#43 沒有證明修好。** 修掉兩條可證實的根因之後，失敗率從 19 次 3 次紅降到
   24 次 1 次紅，但沒有降到零，而且那一次的失敗細節沒抓到。issue 保持開啟。
3. **Windows 的三項驗證沒做到**：#42 的輸出裝置記憶、log 匯出、備份匯出。**備份匯入是刻意不做的** —— Windows 上跑的是使用者的真實音樂庫（1,194 首），匯入會實際寫進去。匯入的回滾行為由 `backup_service_test.dart` 涵蓋，而且那條測試做過反向驗證（把 track 寫入拆成獨立交易後它立刻紅）。
4. **log 匯出沒有在裝置上走完存檔。** 點按鈕會開啟 Android 系統目錄選擇器（證明
   Android 分支有跑到），但 `USE THIS FOLDER` 用合成點擊按不動。之後的寫檔是
   `File(path).writeAsString(...)`，與既有的備份匯出同一條路。輪替與落盤 redaction
   由單元測試涵蓋，沒有在裝置上用真實憑證驗過。

---

#### 6.4.1 Windows 驗收補完（2026-09-04 下午）

上面那張表把 Windows 的四項記成「工具鏈阻塞」。**其中「Windows GUI 驅動不了」這條
結論是錯的** —— 缺的只是一步：點擊之前要先把視窗提到前景。補上
`SetForegroundWindow`（用 `AttachThreadInput` 包住）之後，`orca computer click
--app pid:<n>` 的視窗座標一路都正確，四項全部驗完。做法記在
`.claude/skills/verify-on-device/SKILL.md`。

| 項目 | 結果 |
|---|---|
| Windows 最小化到 tray 後播放不停 | ✅ 14:07:02 `WM_CLOSE` → `Minimized to tray`、`IsWindowVisible` 轉 false、行程存活；隱藏期間 `PlayQueue.lastPositionMs` 從 76,771 走到 196,830，**牆鐘 120 秒、播放前進 120.1 秒**，零暫停事件；14:12:01 用使用者自己的 toggle 快捷鍵叫回視窗 |
| #42 輸出裝置記憶（還原半邊） | ✅ 在真實硬體上兩次獨立出現完整鏈路：`Restoring preferred audio device: wasapi/{2350b26b-…}` → `Setting audio device: … (喇叭 (Creative Stage SE))` → **`Audio device changed`（libmpv 自己回報切換成功）**。不是「程式碼有跑」，是輸出裝置真的換了 |
| 備份匯出 | ✅ 原生存檔對話框 → 828,868 bytes。`version = 4`；**M6.1a 的三個面板欄位都在**；`schemaVersion` 與 `preferredAudioDevice*` 正確不在 —— 與守門測試的排除清單逐項相符；`sourceSettings` 三個音源齊全 |
| log 匯出 | ✅ 原生存檔對話框 → 123,379 bytes，**等於磁碟上 `fmp.log` 的完整 1,228 行**；`Authorization` / `SAPISIDHASH` / `Bearer` / `Cookie:` / `SESSDATA` / `bili_jct` / `MUSIC_U` / `csrf` 掃描全為 **0**，`REDACTED` 出現 **11 次** —— 在有登入帳號的真實 session 上實際觸發過 |
| M7 日誌級別 UI | ✅ 開發者選項裡有「日誌級別 DEBUG」，副標「只影響這次執行，重啟後回到預設」 |

**#42 的另一半補的是測試，不是實機。** `4ca35a6d feat(audio): remember the chosen
output device` **一條測試都沒加**。本輪補上
`test/services/audio/audio_device_preference_test.dart`（6 條），涵蓋寫入、回到
auto、清單到齊時套用、裝置拔掉時不動也不清設定、只套用一次、沒存過就不動。做過反向
驗證：同時拿掉寫入與還原兩半之後，6 條裡有 3 條立刻紅。

**#42 的寫入半邊隨後也在實機上補驗了**（同日 14:44，上面那句「沒有用滑鼠點過裝置
選單」已不成立）：迷你播放器的輸出裝置選單 →「Realtek(R) Audio」，`Settings` 立刻寫入
`preferredAudioDeviceId = 'wasapi/{2698a574-…}'` 與
`preferredAudioDeviceName = '喇叭 (Realtek(R) Audio)'`，log 跟著出現
`Setting audio device` → `Audio device changed`；再點回「自動（跟隨系統）」兩個欄位都
回到 `null`，`Setting audio device to auto` → `Audio device changed: auto`。**issue #42
本輪關閉。**

驗這一項時另外修正了一條做法：`orca computer` 的 `--restore-window` 才是把視窗提到前景
的正確方式。我先寫進 skill 的 Win32 `SetForegroundWindow` 做法**時靈時不靈** —— 它在前景
鎖規則不允許時會靜默失敗，而接下來的 `get-app-state` 就會截到別的視窗（這次確實誤截了
使用者的另一個視窗一次，已刪除）。skill 已更正。

**仍然沒驗到的**：

1. **log 輪替沒有在裝置上驗**（要 2 MB，實測檔案只有 123 KB）。單元測試涵蓋。
2. **備份匯入仍然刻意不做** —— 理由同上：Windows 上是使用者的真實音樂庫。
3. **tray 測試期間三個音源都播不了**：Bilibili `playurl` 回 HTTP 412 `request was
   banned`、曲庫 1,194 首**沒有任何一首下載到本機**。tray 測試最後是用一段本機 WAV 走
   `_inspectLocalFiles` 的離線路徑跑的。這是環境限制，不是 FMP 的缺陷。（YouTube 稍後
   在 14:43 的裝置選單驗證裡是能正常播放的 —— 之前擋住的是評論 API，不是串流。）

**兩件據實記錄的事**：

- **redaction 有一個誤報**：`libmpv configured for audio-only mode (vid=no,
  sid=[REDACTED], …)`。那是 mpv 的字幕軌選項 `sid=no`，不是 session id。只影響 log
  可讀性，方向是安全的那一邊，本輪不改。
- **我弄丟了一筆資料**：佇列裡原本留著上一輪我自己建的測試曲目（唯一一首 youtube
  來源），把佇列換走之後被孤立清理刪掉了。使用者的 1,194 首 bilibili 曲目與 1 個歌單
  完好無損，已逐項核對。驗證期間改過的每一項（`minimizeToTrayOnClose`、
  `preferredAudioDevice*`、track 1 的 `playlistInfo`、佇列與循環模式）都已還原並確認。

**issue 動態**：本輪關掉兩張。**#44**（isar_community 遷移）—— 用 NDK 28.2 的
`llvm-readelf -l` 重量 release APK，三個 ABI 的 `libisar.so` 都從 `0x1000` 變成
`0x4000`，達到 issue 自己的驗收條件。**#42**（輸出裝置記憶）—— 寫入、清除、重啟還原
三條路徑都在真實硬體上走過，並補上原本缺席的 6 條測試。#43 與 #53 維持開啟。


---

### 6.5 音訊：系統媒體控制收進 NowPlayingPublisher（2026-09-05）

Phase 4 的順序是 E→B→D→C。E（`QueueCommands`）已於 `fe0ee475` 落地。這一節記
步驟 B（`NowPlayingPublisher` + `PlaybackCapabilities`）開工前的重核與執行中發現。

#### 開工重核：三條說法被推翻

| # | 原本的說法 | 實況 | 處置 |
|---|---|---|---|
| 1 | `:958`「seek/shuffle/repeat 事件沒到，是 `smtc_windows` 1.1.0 的 Dart wrapper 沒 export —— 只能改成不要對外宣稱有」 | **兩邊都錯。** wrapper **有** `shuffleChangeStream` / `repeatModeChangeStream`（`smtc_windows_base.dart:102-103`），Rust 端也接了 `ShuffleEnabledChangeRequested` / `AutoRepeatModeChangeRequested`（`smtc_internal.rs:226/245`）—— FMP 只是從沒訂閱。而且 `SMTCConfig` **根本沒有** shuffle/repeat 的開關欄位，所以「不宣告」這條路**不存在** | 修法反過來：**去接事件**。已實作並實機證實兩個事件都送達（見下） |
| 2 | issue #40 是「Windows SMTC 的兩個控制項」 | **Android 有同一個 bug，而且更多。** `_getControls()` 無條件回傳三顆按鈕；`systemActions` 的 `skipToNext`/`skipToPrevious` 也是 `const`；更糟的是電台**從不清掉** `onSetRepeatMode` / `onSetShuffleMode`，所以在 Android 上聽電台時按通知欄的循環／隨機鍵，會去改**音樂的** loop mode | 兩平台一起修 |
| 3 | issue #40 附帶：「`enable()` `:299`、`disable()` `:311`、`dispose()` `:323` 三個成員從未被呼叫」 | **已過期。** 檔案在 `481acda8` 之後重排，`enable()`/`disable()` 已不存在，`dispose()` **有**呼叫點 | 更新 issue 時撤下這段 |

另外兩件決定設計的事實：

- **`androidCompactActionIndices` 的正解是「不要設」，不是「算出來」。**
  `AudioService.java:614-617` 在該欄位為 `null` 時自己算 `[0..min(3, 按鈕數))`，
  而 `:641` 顯示 SDK 33+ 根本不讀它。寫死的 `[0,1,2]` 才是越界來源。
- **`AudioRuntimePlatform` 只有 `mobile` / `desktop`**，而 `WindowsSmtcHandler`
  在 `_smtc == null` 時每個方法自己早退。所以 publisher **完全不需要
  `Platform.isWindows`**，`desktop` 涵蓋 Linux/macOS 是安全的 —— 這正是 §4.3 說的
  「把平台知識從 `Platform.isX` 改成介面上的能力查詢」。

#### 執行中發現

1. **`AudioController.dispose()` 直接 dispose 掉 SMTC 是一個潛在 bug。**
   原生 session 只在 `main.dart` 建立一次、沒有任何程式碼會重建它，所以只要
   `audioControllerProvider` 重建過一次，SMTC 就在該 session 裡永久死掉。改成
   `release(music)`：解綁回呼、留著原生控制代碼。
2. **交還擁有權的舊路徑有一個吞噬式 `catch`。** 電台停止時呼
   `AudioController.restoreMediaControlOwnership()`，外面包著 `catch (e) {
   logDebug(...) }`（release 模式看不見）。加上能力之後，那個 catch 一旦觸發，
   後果會從「回呼沒重綁」升級成「能力永遠停在電台的全關狀態」。改成 publisher
   自己記住音樂綁定並還原，那條跨 controller 呼叫與那個 catch 一起刪除。
3. **「非現任擁有者的發佈要丟棄」不是潔癖，是修一個真 bug** —— 而且**實機拍到了**：
   `Ignored publishPlaybackState from radio; owner is music`。點歌之後立刻點電台，
   `RadioController` 只 `pause()` 音樂、不取消進行中的請求，那個請求完成後會把歌名
   蓋到電台的通知欄／SMTC 上。
4. **步驟 B 不可能是「純位移」，三處不對稱必須收斂**：載入狀態與三條 reset 路徑
   過去只送到 Android 通知欄不送 SMTC；`_onPlayerStateChanged` 送給通知欄的是
   effective 值、送給 SMTC 的是後端原始值。AGENTS.md 那條「控制器擁有的載入階段，
   後端 idle 事件不得覆蓋 loading 狀態」沒有理由只保護一個平台。

#### 實機驗收（Windows，2026-09-05）

用新寫的 `.claude/skills/verify-on-device/scripts/smtc_probe.ps1` 直接讀 WinRT 的
`GlobalSystemMediaTransportControlsSessionManager`，不截系統浮出視窗。**探針從任何
行程都讀得到，所以完全繞開 FMP 守不住前景的問題。**（必須跑在 `powershell.exe`
5.1，pwsh 7 沒有 WinRT 投影。）

| 時間點 | `IsNextEnabled` | `IsPreviousEnabled` | `IsPlaybackPositionEnabled` |
|---|---|---|---|
| 音樂（啟動後） | **True** | True | False |
| 電台播放中 | **False** | **False** | False |
| 電台停止後 | **True** | True | False |

路線圖的驗收條件是「電台播放時 `IsNextEnabled` 為 `False`」——**達成**。回程也驗了，
因為「離開電台後能力沒還原」是比 #40 本身更糟的失敗模式，而它只在回程出現。

- **禁用不只是視覺**：電台播放中用 `TrySkipNextAsync()` 送 next（WinRT 回
  `accepted=True`），FMP 的 log **沒有**任何 `SMTC button pressed` —— 按鈕真的是惰性的。
  同一時間送 stop 則拍到 `SMTC button pressed: PressedButton.stop`，證明通道本身是通的。
- **Q19 的前提複驗**：`IsPlaybackPositionEnabled` 在三個時間點都是 `False`，
  與 §12.13a 一致。timeline 的 `maxSeekTimeMs` 已改為 0。
- **Q20 兩個事件都送達，並且真的接上了**：
  `SMTC repeat mode requested: RepeatMode.list` → `Setting loop mode: LoopMode.all`；
  `SMTC shuffle requested: false` → `Toggling shuffle`。兩個死鍵現在是活的。
  （WinRT 會把「與現值相同」的請求吃掉，所以測試要送反向值才看得到事件。）
- **`IsShuffleEnabled` / `IsRepeatEnabled` 恆為 `True`**，因為 `SMTCConfig` 沒有這兩個
  旗標。這正是「不宣告」做不到、只能去接事件的證據。

**讀 log 的通道要換**：Windows 的 `flutter run` terminal 被 `AXTree` spam 洗掉 ——
本輪量到 1,714 行的 buffer 撐不到 4 分鐘。改讀 Phase 3 M7 落盤的
`Documents/FMP/logs/fmp.log`，那裡完整。

**清理**：驗證用的電台（Bilibili 房間 6）已從資料庫刪除，回到「還沒有電台」；
shuffle 被測試切掉之後已切回原本的 `true`（loop mode 原本就是 `all`，未改動）。

#### 實機驗收（Android 模擬器 `Medium_Phone`，2026-09-05）

判準是**通知欄實際的按鈕數**（`dumpsys notification --noredact` 的 `actions=`），
不是 media session 的 bitmask —— 後者被 `audio_service` 混了一堆固定值（見下）。

| 時間點 | 通知欄按鈕 | session 有 `SKIP_TO_NEXT` / `SKIP_TO_PREVIOUS` / `SEEK_TO` |
|---|---|---|
| 音樂（YouTube 播放中） | **3**（上一首／暫停／下一首） | 是 |
| 電台播放中 | **1**（只剩播放／暫停） | **否** |
| 播回音樂 | **3** | 是 |

- **`AUTO_ENABLED_ACTIONS` 是套件寫死的常數**（`AudioService.java:99-100`），
  無條件 OR 進 `ACTION_SET_REPEAT_MODE | ACTION_SET_SHUFFLE_MODE`。所以在 media
  session 這一層，FMP **收不回**這兩項 —— 與 Windows `SMTCConfig` 沒有對應旗標
  是同一種結構限制。但通知欄的按鈕與 `SKIP_TO_*` / `SEEK_TO` 都正確撤下，而且
  電台期間 `onSetLoopMode` / `onSetShuffleEnabled` 為 null，**跨模式改到音樂
  loop mode 的那個 bug 已經修掉** —— 只是「不宣告」在這一層做不到。
- **擁有權檢查在真機上兩個平台各拍到一次**。Android 這邊是
  `Ignored publishTrack from music; owner is radio` —— 沒有它，音樂請求完成時
  會把歌名蓋到電台的通知欄上。這正是加這道檢查的理由。
- `androidCompactActionIndices` 維持 `null`，按鈕數從 3 掉到 1 沒有任何越界。

**模擬器新陷阱**：Gboard 的「Try out your stylus」教學浮層會攔截
`adb shell input text`，字進了教學的輸入框、FMP 的欄位仍是空的 —— 看起來就像
點擊沒中。截圖才看得出來，按 Cancel 關掉後重打即可。已補進
`.claude/skills/verify-on-device/SKILL.md`。

### 6.6 音訊：播放副作用拆成三個協作者（2026-09-05）

步驟 D（把播放歷史、歌詞自動比對、Mix 預取摘出 `AudioController`）。commit
`76fe5abf`…`d3bed14b`。`audio_provider.dart` **3,436 → 3,209 行**（淨減 227）。

#### 開工重核：三條說法要更正

| # | 原本的說法 | 實況 | 處置 |
|---|---|---|---|
| 1 | `:342`：D 的價值是「把副作用從播放路徑上摘下來，**播放不再等它們**」 | **前提已經成立。** 三者當時都已非阻塞：歷史 `Future.microtask`、歌詞 `unawaited`、Mix `unawaited`。唯一 `await` 的是 `_advanceAfterPendingMixLoadMore()`（播到隊尾剛好有預取在飛就等它），那是**刻意的**，而且被 `audio_controller_mix_boundary_test.dart` 的 `completion at mix queue end waits for pending load-more tracks` 鎖住 | D **沒有**動那個 await。價值改述為：縮小 god class、讓三件事可單獨測、拆掉隱藏耦合 |
| 2 | 02 §8.1-D：`abstract interface class PlaybackObserver` ＋ `List<PlaybackObserver>` 廣播 | **三個方法只有一個有人實作。** 三者都只掛「播放請求成功」一個事件；`onTrackEnded` / `onQueuePositionChanged` 零實作。而且 Mix 必須對外曝露進行中的 `Future`，回傳 `void` 的 observer 做不到 | **介面未採用**，改成三個具體協作者，形狀照 `QueueCommands` / `NowPlayingPublisher`。02 §8.1-D 已標註 |
| 3 | — | **`PlaybackSessionCommand.recordHistory` 是死欄位。** 整個 `lib/` 沒有一處讀它；唯一的讀取者是測試裡一行「斷言它 round-trip 回自己」 | 連同那行斷言一起刪 |

另外兩件決定設計的事實：

- **`recordHistory` 這個名字在說謊。** 它同時閘住播放歷史**與**歌詞自動比對
  （`audio_provider.dart` 舊 `:2199`）。這個耦合是對的（重試與啟動還原都不算一次
  新的播放，兩者都不該重跑），但名字讓人以為它只管歷史。改名 `countsAsNewPlay`。
- **`_mixLoadMoreFuture` 與 `MixPlaylistHandler._current` 是兩組必須手動同步的狀態。**
  `_exitMixMode()` 與 `dispose()` 都得記得同時清兩邊。合併成 `MixSessionCoordinator`
  之後 `exit()` 一次做完，這個 bug 形狀消失。

#### 執行中發現

1. **`audio_controller_mix_boundary_test.dart` 的守門斷言差點被自己搬走。**
   它讀 `lib/services/audio/audio_provider.dart` 的原始碼字串，斷言其中不含
   `_queueManager.mixPlaylistId` 等四個 getter。Mix 程式碼搬到新檔之後，這個斷言
   會**變成恆真**——守門形同解除，而且測試照樣是綠的。已改成掃
   `lib/services/audio/` 整個目錄，並加一條 `expect(sources, isNotEmpty)` 防掃空。
   這正是 §Phase 6 那條「掃描型測試的路徑不得硬編」紀律要防的失效模式。
2. **播放歷史在 `AudioController` 這一層本來完全沒有測試。** repository 與 provider
   各有自己的單元測試，中間那條轉接沒有人守。D1 補上（4 條）。
3. **Isar 寫入不能用固定次數的 `pumpEventQueue` 當同步點。** 兩次 `record()` 排出
   兩個序列化的 `writeTxn`，單次 pump 只等得到第一筆 —— 這恰好證明了它不阻塞呼叫端，
   但也意味著測試要輪詢到落地為止。三個新測試檔都用這個模式。
4. **`startMixFromPlaylist` 的第一次抓取與預取用的是同一個 fetcher。** 為了不讓
   `MixTracksFetcher` 同時掛在 controller 與 coordinator 上，coordinator 開了
   `canFetch` / `fetch()`，controller 不再持有 fetcher。

#### 實機驗收（Android 模擬器 `Medium_Phone`，2026-09-05）

三個協作者都用新的 logger tag，實機拍到的就是新程式碼在跑。

| 要驗什麼 | 觀察到什麼 |
|---|---|
| 播放歷史真的有寫 | `[PlayHistoryRecorder] Recorded play history: Cardi B - AH HA…`；播放歷史頁 **11 → 13 首** |
| 啟動還原**不**重複記 | hot restart 走 `_prepareCurrentTrack`（`countsAsNewPlay: false`）→ 仍是 **13 首**，未增加 |
| 歌詞閘門（關閉） | `[LyricsAutoMatchCoordinator] Auto-match lyrics disabled in settings` |
| 歌詞閘門（開啟） | 暫時打開設定後：`[LyricsAutoMatchService] Auto-matching: "AH HA…" by "Cardi B"`，並依使用者的來源優先序打了 Netease |
| **Mix 預取** | `[MixSessionCoordinator] Mix mode: 0 tracks remaining, loading more…` → `Attempt 1/10: using last track as seed` → `adding 11 new tracks`；佇列頁 **25 → 36 → 54 → 67 首**，三輪都在畫面上確認 |
| Mix 還原路徑 | 持久化的 Mix 在 `initialize()` 還原到隊尾時自動排入預取，**不需要播放成功** |

**沒驗到的一項**：`isLoadingMoreMix` 的載入指示器渲染在佇列列表**底部**，而單次抓取
一輪就湊滿，視窗太短沒截到。它的 `[true, false]` 轉換由
`mix_session_coordinator_test.dart` 鎖住，同一組回呼的另一半（`onQueueChanged` →
佇列變長）則在畫面上確認了三次。

**當天的音源狀況（影響可驗範圍）**：Bilibili `playurl` 回 HTTP 412
`request was banned`；YouTube 的 **audio-only** 串流回 `Sign in to confirm you're
not a bot`，但**muxed 串流與所有 metadata API（排行榜、Mix 播放列表、Mix 追加）
完全正常**。所以 Mix 全程可驗，只有純音訊解析被擋。第一輪播放驗證改用本地已下載檔
（`_inspectLocalFiles`，無網路）。

**模擬器新陷阱**：從 snapshot 還原的 `Medium_Phone` 會整個卡死 —— 畫面凍結、
`orca emulator tap` 與 `adb shell input` 都沒有反應、`ax` tree 恆為 `nodes=0`，
連 hot restart 之後畫面都不變，logcat 只留下 `F/bluetooth … on_hardware_error
… code 0x42`。**`-no-snapshot-load` 冷開機即可**；不要在凍結的 snapshot 上耗時間。

**清理**：匯入的測試 Mix 歌單（`RDI-5e_J3LWS8`）已刪除，音樂庫回到原本只有
`DownloadProbe`；「自動匹配歌詞」已切回原本的關閉。**未還原**：驗證用的播放佇列
清空後沒有復原原本那 2 首（原佇列來自更早一輪的 YouTube 排行榜點擊），播放歷史多出
的紀錄也保留著 —— 那些是裝置上真的發生過的播放。

### 6.7 音訊：載入閂存與延後 seek（2026-09-06）

步驟 C（拆掉 `_PlaybackContext`，把載入閂存與延後 seek 收進一個協作者）。commit
`c19e505e`…`d8afc346`。`audio_provider.dart` **3,209 → 2,942 行**（淨減 267）。

#### 開工重核：三條說法要更正

| # | 原本的說法 | 實況（file:line） | 處置 |
|---|---|---|---|
| 1 | 「Phase 1 的逾時預算收斂到這裡的單一 `budget`」（`05:343`）、「`budget` 是唯一一個『多久算太久』的定義點」（`02:874`） | **已經做完了。** `PlaybackTimeoutBudget`（`app_constants.dart:191`，`total` 是 `streamResolution + mediaOpen` 的 getter）就是那個定義點；`PlaybackRequestSession` 的 `_budget:177`、`_requestDeadline:180`（`:523`/`:619` 設定）、`_withBudget:716`、`_remainingBudget:735` 已經讓原始一輪與 fallback 共用同一份。commit `262657bc` + `591cb2b0`，由 `playback_request_session_test.dart:500/520/549/593` 釘住 | **C 不碰逾時。** 這一項移出 C 的範圍 |
| 2 | 介面 `abstract interface class PlaybackSessionCoordinator { start / cancel / states }`（`02:866-871`） | **`PlaybackRequestSession` 已經是這個東西**（852 行）：`start:214`、`restore:282`、`cancelActive:206`、`isSuperseded:204`、`dispose:191`。再造一個同名類別只會變成「兩個都叫 session 的東西」；而 `Stream<PlaybackSessionState>` 只會有一個消費者 | **介面不採用**，理由與 D 相同。`02 §8.1-C` 已標註 |
| 3 | 「`_context` 整包搬走」（`02:861`） | **`_PlaybackContext`（`:120-185`）裝的是三件無關的事**：播放模式（28 處）、載入閂存（21 處）、臨時播放快照（21 處）。整包搬會把另外兩件拖進去 | 分三個歸屬：模式留成普通欄位、快照交給 `TemporaryPlayHandler`、閂存與延後 seek 合成 `PlaybackHandoffGate` |

#### 執行中發現

1. **`_context.activeRequestId` 與 `PlaybackRequestSession.activeRequestId` 是同一個
   計數器。** `_enterLoading()`（`playback_request_session.dart:463-470`）做
   `++_requestId` 後把 id 交給 `onLoadingStarted` → `_startSessionLoadingState` 原樣
   存起來。它是**閂存副本**，交接結束歸零 —— 回答「控制器現在為哪一次請求做投影」，
   不是「哪一次才是最新的」。兩者不可互換：`_clearMatchingSessionLoadingContext`
   是唯一以閂存為準的路徑，其餘一律問 `isSuperseded`。
2. **閂存與延後 seek 從來沒有分開改過。** 11 個寫入點（建構子的 `onLoadingFinished`
   閉包、四個起播前導、`_startSessionLoadingState`、`_exitLoadingState`、三個
   `_reset*`）每一個都同時動兩者。這正是 D 在 Mix 上消掉的形狀，所以合成一個
   `PlaybackHandoffGate` 而不是兩個類別。
3. **`state.currentTrack` 是 `playingTrack` 的別名**（`player_state.dart:114`），
   所以 seek 那三處 `?? state.currentTrack?.uniqueKey` 是死程式碼。拿掉之後 gate
   完全不需要 `PlayerState`，這才讓它符合既有協作者的形狀。
4. **`copyWith` 藏了兩個行為**，拆開時必須寫出來：`copyWith(mode: null)` 會保持原
   模式（重試與啟動還原靠它才不會把臨時播放或 Mix 打回 queue）；`clearSavedState`
   會覆蓋另外三個具名參數。兩者都在 commit `f02a2ef5` 裡顯式化。
5. **`_startSessionLoadingState` 刻意只清視窗、不清「下一次要穩定化」旗標**
   （`:1519` 直接 `= null` 而不是呼叫 `_clearSeekStabilizationWindow()`）。gate 因此
   把 `prepareForRequest`（不清旗標）與 `cancel`（清）分成兩個方法，並由
   `playback_handoff_gate_test.dart` 的
   `the stabilize-next flag survives beginRequest but not cancel` 釘住。
6. **`AudioController.seekForward` / `seekBackward` 是死程式碼**，`lib/` 與 `test/`
   都沒有呼叫者。連同 `FmpAudioService` 的兩個介面宣告、`JustAudioService` 與
   `MediaKitAudioService` 的實作、測試 fake 的樁與
   `AppConstants.seekDurationSeconds`，整條鏈都沒有入口 —— 六個檔案 70 行，已在
   第十一輪刪除。

   > **更正（第十一輪）**：本項原本斷言「`audio_handler.dart:59-60` 宣告了
   > `MediaAction.seekForward` / `seekBackward` 但 `FmpAudioHandler` 沒有覆寫
   > `fastForward()` / `rewind()`，所以通知列上那兩個動作按下去沒有任何反應」。
   > **這是錯的。** `FmpAudioHandler` 的宣告是
   > `extends BaseAudioHandler with SeekHandler`（`audio_handler.dart:16`），而
   > `SeekHandler`（`audio_service-0.18.18/lib/audio_service.dart:3220-3260`）
   > 已經實作了那四個方法，全部收斂到 `seek()` —— 而 `seek()` 正是
   > `FmpAudioHandler` 有覆寫的那個。系統動作是通的，能力宣告沒有缺陷。
   > `main.dart:125-126` 的 `fastForwardInterval` / `rewindInterval` 就是餵給
   > `SeekHandler._seekRelative` 的。已在 `audio_handler.dart` 就地加註，避免
   > 下一個讀者重蹈覆轍。

#### 新測試的變異驗證

`playback_handoff_gate_test.dart` 有 11 條在守同一件事：**任何作廢路徑都必須
`complete()`**，否則 `seekTo` 的呼叫端永遠 await 不到。把 `discardPending` 裡的
`pending.complete()` 拿掉重跑，**12 條中有 7 條失敗**（而且是掛住到逾時，不是斷言
失敗），確認這組測試真的守得住。

#### 實機驗收（Android 模擬器 `Medium_Phone`，`-no-snapshot-load` 冷開機）

| 要驗什麼 | 觀察到什麼 |
|---|---|
| 一般 seek（無交接） | 進度條點 75% → 位置 264101ms；點 25% → 87753ms。兩次都精確落在 351–352 秒曲目的對應比例上 |
| **交接期間的 seek 會延後** | `[PlaybackHandoffGate] Deferring seek to 0:01:56.367000 until playback request 2 is ready` |
| **穩定化視窗** | `[PlaybackHandoffGate] Stabilizing seeks for request 2 until …` → `Waiting 0:00:00.498569 before applying deferred seek`（500ms 視窗只剩 498ms） |
| **延後的 seek 落在新歌上** | `[PlaybackHandoffGate] Applying deferred seek to 0:01:56.367000 for request 2`，隨後 `dumpsys media_session` 讀到 132612ms（1:56 ＋ 已播的 16 秒） |
| 臨時播放快照 | `[TemporaryPlayHandler] Saved playback state: index: 0, position: 0:01:18.124453` 等三次，每次都與點擊前一刻的 `dumpsys` 位置吻合 |
| 步驟 D 的協作者沒被弄壞 | `[PlayHistoryRecorder] Recorded play history: …`、`[LyricsAutoMatchCoordinator] Auto-match lyrics disabled in settings` 照常 |

**沒在畫面上捕捉到的一項**：被新請求取代時的 `Discarding deferred seek`。要湊出
「延後中 → 立刻再切一次歌」需要兩次點擊都落在載入視窗內，而模擬器後段對合成點擊
的反應變得不穩（`ax` 樹正常但點擊不進 Flutter view）。這條由
`playback_handoff_gate_test.dart` 的四條作廢測試與既有的端到端
`audio_controller_phase1_test.dart:519` 覆蓋。

#### 順手發現的既有缺陷（**不是 C 造成的**）

**臨時播放按「下一首」返回佇列時，還原有機率卡在載入中**：mini player 的播放鍵變成
無限轉圈，通知列位置停在 0，`_restoreSavedState` 只印出 `started` 而沒有
`completed successfully`。log 停在
`PlaybackRequestSession: Restoring queue track` → `JustAudioService: File set` →
`playing=true, ready`，之後就沒有下文 —— `restore()` 的 future 沒有回來。

**A/B 驗證**：把工作區切到步驟 C 之前的 `29eaaad6` 熱重啟後跑同一組操作，
**症狀完全相同**（log 最後一行是舊的 `[AudioController] Saved playback state` tag，
證明跑的是舊 build；位置同樣停在 0、轉圈同樣不停）。所以這是既有缺陷，應另開 issue
追蹤，不在 C 的範圍。

#### 誠實的預期：Phase 4 的驗收線需要重述

**C 做完是 2,942 行，離 ≤800 還差 2,140 行，而路線圖的 A–E 五步到此就用完了。**
實測目前的行數分布（`AudioController` 本體）：

| 群 | ~行數 | 狀態 |
|---|---|---|
| 後端事件處理與失敗分類（`_onPlayerStateChanged` / `_onPositionChanged` / `_onTrackCompleted` / `_onPlaybackEnded` / `_onTransportFailure` / `_onBufferStarvation` / 輸出裝置） | 420 | 未規劃 |
| 起播命令與 transport（play\* / playAt / next / previous / 音量 / 靜音 / 循環 / 裝置） | 500 | 大部分該留 |
| 啟動與還原（`initialize` / `_prepareCurrentTrack` / `_restoreQueuePlayback` / `_restoreSavedState` / `returnFromRadio`） | 370 | 未規劃 |
| `_executePlayRequest` 與音源錯誤處理 | 215 | 未規劃 |
| 重試階梯投影 | 168 | 未規劃 |
| `PlayerState` / `QueueState` 投影助手 | 190 | 該留（就是投影本身） |
| Mix 起播與退出 | 156 | 該留 |
| 載入狀態投影與 publisher | 120 | 該留 |
| 錯誤 → toast 翻譯 | 91 | 未規劃 |
| 同檔案裡不屬於 controller 的（`QueueState` ＋ 12 個 provider） | 230 | **純檔案切分即可** |

要接近 800 至少還需要：

- **最便宜的 230 行根本不是重構** —— 把 `QueueState` ＋ `queueStateProvider` 移到
  `queue_state.dart`、12 個 provider 移到 `audio_providers.dart`，零行為變更，
  搬走的行數比 C 還多。建議優先做。
- **F — `PlaybackEventRouter`**（後端事件，約 −300）：注意它**無法照既有協作者的
  規矩寫** —— 那些 handler 本身就是 `PlayerState` 投影，要嘛讓它吐 typed intent 由
  controller 重播，那是新的設計決定，不是位移。
- **G — `PlaybackStartupRestorer`**（啟動與還原，約 −320）
- **H — `PlaybackErrorPresenter`**（錯誤翻譯，約 −140）

三步加檔案切分之後樂觀估計 **1,000–1,200 行**。**≤800 只有在投影本身被重構
（`02 §8.1-F` 的 `_project()`）之後才可能成立，Phase 4 的驗收線應該按這個重述。**

### 6.8 音訊：兩個寫不出來的拆分，與檔案切分（2026-09-06）

commit `b952ccdf`…`fd8a64b6`。`audio_provider.dart` **2,942 → 2,573 行**（淨減 369）。
測試 1,382 → 1,408。

#### 開工重核：F 與 G 都寫不出來，H 只有一半能寫

路線圖 §6.7 把剩下的三步估成 F −300、G −320、H −140。逐項量過之後：

| 步 | 原估 | 實際可搬 | 為什麼 |
|---|---|---|---|
| **H** | −140 | **−87** | 「錯誤 → 文案」可以整包搬；`_handleSourceError` 不行 —— 它跳下一首、停後端、寫 `state.error`，那是**用**結論不是**得出**結論 |
| **G** | −320 | **−16** | 見下表：345 行引用了 **41 個**控制器成員 |
| **F** | −300 | **−7** | 167 行引用了 **29 個**控制器成員 |

判準不是感覺，是「要注入幾個回呼」。既有五個協作者的實測值：

| 協作者 | 建構子注入的外部相依 |
|---|---|
| `EffectivePlaybackState` | 0（純值） |
| `PlaybackErrorPresenter` | 0（純函數） |
| `PlaybackHandoffGate` | 3 |
| `MixSessionCoordinator` | 5 |
| **`PlaybackEventRouter`（F，若要寫）** | **約 15** |
| **`PlaybackStartupRestorer`（G，若要寫）** | **約 26** |

15 個回呼的建構子不是邊界，是把控制器換個名字再傳一次。這兩步**不執行**，改成
只取其中真正獨立的部分。

#### 實際做了什麼

1. **issue #54 的根因與修法**（`b952ccdf`）—— 不是重構題目，是查步驟 C 的實機
   異常時挖出來的：`_waitForRequestOperation` 只在 `phase != null` 時套預算，而
   `_executeQueueRestore` 的 `setMedia` / `seekTo` / `play` **三個都沒傳**。後端
   任一個 future 不回來，`restore()` 就永遠不返回 → 呼叫端 `requestId` 停在
   `null` → `finally` 的 `_resetLoadingState` 不執行 → 轉圈到天荒地老。
   Phase 1 的 `637aa276` 只覆蓋了一般起播路徑。三條新測試各對一個等待點，把
   `phase:` 拿掉重跑會**各掛住 30 秒到逾時**。
2. **死路徑刪除**（`6175812d`）—— `seekForward` / `seekBackward` 從控制器、
   `FmpAudioService` 介面、兩個後端實作、測試 fake 到
   `AppConstants.seekDurationSeconds`，六個檔案 70 行，全鏈無呼叫者。
3. **純檔案切分**（`34daba59`，−244）—— `QueueState` ＋ `queueStateProvider` 出去
   成 `queue_state.dart`；5 個建構 provider 進
   `lib/providers/audio/audio_controller_provider.dart`；9 個衍生 provider 併入既
   有的 `audio_player_selectors.dart`。**沒有留 re-export**：43 個匯入端逐一改
   完，編譯器全程覆蓋。
4. **H —— `PlaybackErrorPresenter`**（`74c50fb0`，−87）。
5. **Mix 還原歸位**（`7d197130`，−16）—— `mixPlaylistId` / `mixSeedVideoId` /
   `mixTitle` 在 `MixSessionCoordinator` 之外的最後一個讀取點收掉了。
6. **F 唯一真正能抽的東西**（`fd8a64b6`）—— `EffectivePlaybackState`。

#### 更正 §6.7 的一項

§6.7 執行中發現第 6 項斷言通知列的快轉／倒退「按下去沒有任何反應」。**那是錯的**，
已就地更正：`FmpAudioHandler` mix 了 `SeekHandler`，那四個方法都有實作。原本要
為此開的 issue 沒有開。

#### 順手守到的兩個洞

- **`audio_error_kind_structure_test.dart` 會變成恆真**：它比對
  `audio_provider.dart` 裡的字面簽名，分類器搬走之後三條斷言全部失效而測試仍綠。
  改成掃整個 `lib/services/audio/` 找字串分類器，正向行為交給
  `playback_error_presenter_test.dart` 用真的例外物件釘。
- **`source_ownership_phase3_test.dart` 的檢查清單**：`mixTracksFetcher` 的接線
  搬到 `audio_controller_provider.dart` 之後，臨時 `new YouTubeSource(` 最可能長
  回來的地方變成它，已加進清單。

#### 沒有測試守著的一條規則，現在有了

`AGENTS.md` 的 Platform Split 寫著「控制器擁有的載入階段，後端 idle 事件不得覆蓋
loading 狀態」，程式碼註釋還記著「過去 SMTC 收的是後端原始值，這條只在 Android
成立」。**這條規則一個測試都沒有**，只活在 `_onPlayerStateChanged` 的三個區域變數
裡。抽成 `EffectivePlaybackState.from` 之後由 7 條測試釘住。

#### 實機驗收（Android 模擬器 `Medium_Phone`，`-no-snapshot-load` 冷開機）

| 要驗什麼 | 觀察到什麼 |
|---|---|
| **`EffectivePlaybackState` 把後端 idle 改寫成 loading** | 切歌時 log 連兩行 `PlayerState changed: playing=false, processingState=idle`（控制器自己的 `stop()`），同一時間 `dumpsys media_session` 連六次都讀到 **`state=CONNECTING(8), position=0`** —— 不是 `STOPPED`，位置也沒殘留上一首。這正是 `AGENTS.md` 寫了很久卻沒有測試的那條規則 |
| 交接完成後回到播放 | 22 秒後 `state=PLAYING(3), position=20696`；8 秒間隔的兩次取樣 34241 → 42041 |
| **檔案切分沒有拆斷投影** | 加三首進佇列 → 佇列頁渲染「正在播放第 3 首／共 3 首」與三個列項；mini player 的「上一首」「下一首」由 `click=False` 變 `click=True`（`QueueState.canPlayPrevious/canPlayNext` 經搬到 `queue_state.dart` 的 `queueStateProvider` 走完整條路） |
| **`PlaybackErrorPresenter.shouldRetrySource` 分類正確** | 飛航模式下播 YouTube 曲目 → `Scheduling retry 1/5` … `5/5` → `Max retry attempts reached`，退避階梯完整跑完 |
| 失敗後載入狀態有清掉 | 重試耗盡後 mini player 的轉圈變回 ▶（截圖），沒有卡住 —— issue #54 的症狀類別 |
| 錯誤 toast 有渲染 | 限流：橘色警告「請求過於頻繁，請稍後再試」（`rateLimited` 分支，不經 presenter，作為對照組）；離線：紅色「播放失敗: 这次是真玩爽了」 |

**沒能在裝置上構到的一項**：presenter 自己產的文案（`cannotPlay` /
`playbackFailed`）。網路錯誤是可重試的，走退避階梯，耗盡之後不經過
`_handleSourceError`；要觸發得有一支**地區限制或 VIP** 的影片，這台模擬器上沒有
穩定的來源。這條由 `playback_error_presenter_test.dart` 的 12 條測試覆蓋 ——
它們斷言的是「挑了哪一個 i18n key」，不是字面文字。

**Mix 還原（`7d197130`）沒有做實機驗收**，因為它對外行為零變化：原本的 `if` 也
是三個欄位缺一就整段不做，搬進 `MixSessionCoordinator.restoreFrom` 之後判斷完全
相同，由三條新測試逐欄位釘住。

裝置狀態已還原：佇列清空（確認顯示「播放佇列為空」）、飛航模式關閉、Orca 終端
關閉、`adb emu kill`、`adb devices` 為空且無殘留 emulator 行程。本輪驗收過程新增
的播放歷史列沒有清除。

#### 誠實的行數帳（取代 §6.7 的估算）

| 群 | ~行數 | 狀態 |
|---|---|---|
| 起播命令與 transport | 500 | 該留 |
| 啟動與還原 | 345 | **G 寫不出來**（41 個相依） |
| `PlayerState` / `QueueState` 投影助手 | 190 | 該留（就是投影本身） |
| 後端事件處理 | 167 | **F 寫不出來**（29 個相依） |
| 重試階梯投影 | 168 | 未評估 |
| Mix 起播與退出 | 140 | 該留 |
| `_executePlayRequest` | 130 | 該留 |
| 載入狀態投影與 publisher | 120 | 該留 |

**≤800 不可能靠繼續抽協作者達成。** 剩下的 2,573 行有 1,080 行是投影與 transport
命令 —— 它們就是 `AudioController` 這個類別的定義。要再往下只有兩條路，兩條都是
改變控制器**是什麼**，不是把東西搬出去：

- **拆 `PlayerState` 本身**（`02 §8.1-F` 的 `_project()`）：把播放狀態拆成幾個各自
  獨立的 notifier，投影助手才有地方去。
- **`StateNotifier` → `Notifier` 改寫**（路線圖同節已列）：Riverpod 3 的 `Notifier`
  可以把 `ref` 拿進來，起播 provider 的接線就不必全擠在 provider 工廠裡。

**Phase 4 的驗收線應該重述為：`AudioController` 不再持有任何可以獨立測試的規則。**
以行數計已經沒有意義 —— 這一輪搬走的 369 行裡，真正的邊界改善（H、Mix、
`EffectivePlaybackState`）只有 110 行，其餘 259 行是檔案切分與刪死碼。

### 6.9 音訊：Phase 1–4 收尾複審，兩份佇列投影合一（2026-09-06）

commit `eeca7dd5`…`312c803d`。全面複審 Phase 1–4 之後補的五件事。
`audio_provider.dart` 2,573 → 2,561 行，`player_state.dart` 222 → 163 行。
測試 1,408 → 1,409（`main` 基準；`feat/phase-5-ui-ux` 另有排行榜的 +2）。

#### 複審確認成立的部分

- **Phase 3 的驗收超標**：`rg "\bisar\.[a-z]|_isar\.[a-z]"` 在 repository 之外
  從 152 降到 **21**（目標 < 60），而那 21 筆全是 `import 'package:isar_community/isar.dart'`
  這種 import 行 —— 真正的 `isar.<method>` 呼叫是 **0**。
- **協作者模式統一**：11 個新檔的形狀一致，跨 6 個協作者共注入 13 個函數參數。
  11 個裡 10 個在 `lib/services/audio/AGENTS.md` 的 Ownership 有專屬條目。
- **偏離計劃有寫理由**：Riverpod 3 的 auto-retry，計劃寫「26 個 `FutureProvider`
  逐一決定」，實際是 `main.dart:192` 一個全域關閉，理由寫在程式碼註釋與
  `lib/providers/AGENTS.md:81`。

#### 補上的五件事

1. **階段章節從未標記已執行**（`eeca7dd5`）。§6.2–§6.8 共約 600 行執行記錄修正的
   是階段表的內容，但只有 Phase 2 有「已執行 ＋ 見 §6.3」的回指。Phase 1、3、4
   沒有，讀者翻到階段表看到的是原計劃，要往下 1,300 行才會知道被推翻過。
   三個章節補上標記。**Phase 4 的 ≤800 行驗收線改成刪除線 ＋ §6.8 的重述**，
   並註明本節列出但未開始的兩項（`Notifier` 改寫、`setQueue` / `supportsQueue`）。

2. **文檔說「兩個 request-id 述詞」，實際有三個**（`eeca7dd5`）。
   `AudioController._navRequestId`（`:76`、`:892-945`）就是一個 raw 計數器，而
   同一節寫著「不要新增 raw request-id 計數器」。它早於 session（`b9b4d6b2`），
   守的是 `next()` / `previous()` 在拿到 session id 之前的那段 await 視窗。
   `AGENTS.md` 補上它，並說明為什麼不併進來。

3. **控制器同時講簡體和繁體**（`1f7cb99b`）。Phase 4 寫了 11 個全繁體的協作者檔，
   留下的控制器是 190 簡 / 152 繁，相鄰的區塊標題用不同字體。133 行註釋轉繁，
   **只動註釋**。用語照 `lib/` 既有多數：佇列 86/23、網路 28/8、音訊 31/9、
   點擊 37/1、回呼 17/5、台 363/0。OpenCC `s2twp` 前五個對、最後一個錯
   （會轉成「臺」），並且會把「只」誤轉成「隻」—— 兩者一律還原。
   已經是繁體的註釋一律跳過，否則「回調」會被改成「回撥」。

4. **兩個抽取殘留**（`d240c431`）。`PlaybackHandoffGate.clearStabilizationWindow`
   在步驟 C 的計劃裡是公開 API，實際接線沒用到，四個呼叫者全在類別內 → 改私有。
   `onLoadingFinished` 用兩個並列 `if` 測同一個 `result.isSuperseded` → 一個
   guard ＋ 一個巢狀分支。

5. **★`QueueState` 是投影的第二份副本**（`312c803d`）。這是本次複審最實在的一項。

#### 第 5 項：兩份佇列投影

`QueueState` 的 12 個欄位**全部**同時存在於 `PlayerState`，零個獨有。
`_updateQueueState()` 一次寫兩份，而 `_createQueueStateFromCurrentState()` 是逐欄位
從 `state` 抄過去。消費端因此裂成兩邊：

| 讀 `queueStateProvider` | 讀 `PlayerState` |
|---|---|
| `queueProvider` `queueVersionProvider` `queueTrackProvider` | `isShuffleEnabledProvider` `loopModeProvider`、`mini_player.dart:329-337`、`player_page.dart:93-100`、`home_page.dart:1124/1173`、`track_detail_panel.dart:756` |

**這個重複早於 Phase 1**（`9f2bed8f:55` 就有 `class QueueState`），Phase 4 沒有製造
它，只是把它搬進獨立檔案。問題是搬的同時寫了一段程式碼並不支持的理由 ——
`queue_state.dart` 與 `AGENTS.md` 都說「Deliberately separate from `PlayerState`…
merging them would rebuild every queue list on the once-a-second position tick」。
它們不是分開的，是重複的；而且 `PlayerState` 仍帶著 `queue` 與 `upcomingTracks`，
那個效能理由沒有兌現。`QueueState.copyWith` 的 `clearMixTitle` 當時也沒有呼叫者。

修法採「刪掉舊路徑」而不是改文案：`PlayerState` 的 12 個欄位全部刪除，
控制器改持有 `QueueState _queueState` 並用 `_emitQueueState()` 單點寫入，
`_createQueueStateFromCurrentState()` 刪除。新增 `AudioController.queueState`
唯讀 getter 給不架 container 的呼叫端。選擇器補 `upcomingTracksProvider` 與
`queueControlStateProvider`（後者讓播放控制列一次讀完五個佇列欄位，
取代 mini player 原本的五次 `.select`）。

**順手修掉一個時序缺陷**：`toggleShuffle` / `setLoopMode` / `cycleLoopMode` 過去只寫
`PlayerState`，`queueStateProvider` 要等 `QueueManager.stateStream` 的下一次事件才會
跟上。現在是同步送出。

`analysis_options.yaml` 排除 `test/**`，所以 `flutter analyze` 全綠時 7 個測試檔仍
編不過 —— 這個陷阱又踩到一次，唯一的守門是實際跑測試。原本釘住這份重複的測試
（`queueProvider follows queueStateProvider instead of PlayerState queue`）改寫成
反向守門 `PlayerState declares none of the queue fields`。

#### 實機驗收（Android，`-no-snapshot-load` 冷開機）

`Medium_Phone`（1080×2400，繁中）：

| 要驗什麼 | 觀察到什麼 |
|---|---|
| `queueControlStateProvider` 的 shuffle / loop | mini player「順序播放」→ 點一下變「隨機播放」；「單曲循環」→ 點一下變「不循環」。這正是 `toggleShuffle` / `cycleLoopMode` 改成同步送出的那條路徑 |
| 播放頁讀同一份 | 展開播放頁顯示「隨機播放」「不循環」，與 mini player 一致 |
| `queueStateProvider.queue` / `currentIndex` | 佇列頁「正在播放第 1 首／共 2 首」＋兩個列項 |
| `upcomingTracksProvider` | 首頁「接下來播放」渲染佇列裡的兩首 |
| 脫離佇列分支 | 第三次點選誤中「播放」→ log `isPlayingOutOfQueue: true`，佇列投影與 playingTrack 刻意不一致，兩者各自正確 |
| `canPlayPrevious` / `canPlayNext` | 脫離佇列且佇列非空 → 上一首／下一首皆 `click=True` |

`Medium_Tablet`（2560×1600 橫向 = 1280dp，英文）：

| 要驗什麼 | 觀察到什麼 |
|---|---|
| 空佇列的能力投影 | 佇列只有 1 首時 `Previous` / `Next` 為 `click=False`；加到 3 首後翻成 `click=True` |
| **`track_detail_panel` 的下一首**（只在 desktop 佈局出現，≥1200dp） | 播 JENNIE、佇列有 3 首 → 右側面板渲染 `Next / DECO*27 - 洗脳 feat. 初音未来`，即 `queueStateProvider.upcomingTracks.first` |
| 佇列頁 | `Now playing #1 / 3 tracks` ＋三個列項 |

**沒能驗到的一項**：`radio_controller.dart:1004` 的
`_ref.read(queueStateProvider).currentIndex`。這台 AVD 沒有電台，而 Bilibili 整輪
都在 HTTP 412 `request was banned` 風控狀態（log 可見），加不了直播間，
電台返回那條路徑構不到。它是同一個值換讀取來源的一行改動，由編譯器覆蓋，
`queueStateProvider` 本身則由上面每一條驗證證明是活的。

另外，平板上的彈出選單 **uiautomator 取不到**（`orca emulator ax` 完全看不到
`MenuItem`，截圖裡選單是開著的），要靠截圖定座標再 `adb shell input tap` 驅動。
這一點記進 `verify-on-device` 的限制。

裝置狀態已還原：兩台的佇列都清空（確認顯示「播放佇列為空」／`Queue is empty`）、
旋轉設定復原、Orca 終端關閉、`adb emu kill`、`adb devices` 為空且無殘留
emulator 行程。本輪新增的播放歷史列沒有清除。

---

### 6.10 UI：錯誤呈現收斂（2026-09-06 / 07）

commit `0483bf8b`…`2421f73d`。測試 1,411 → 1,429。`flutter analyze` 全綠。
本輪清掉全部剩餘 P0（P0-2 / P0-3 / P0-4）並把原始例外擋在 UI 之外（P1-7）。

#### 五條說法要更正

| # | 原本的說法 | 實況 | 處置 |
|---|---|---|---|
| 1 | 「9 處 `.when(error:)` 吞錯誤，8 處連 log 都沒有」（`05:391`、`04 §4.2`） | `lib/` 共 **21** 個 `.when(error:)` 呼叫點：**10 個吞掉**（04 的表漏了 `add_to_playlist_dialog.dart:291`）、2 個是 provider 轉包、9 個有顯示給使用者（其中只有 3 個走共用 `ErrorDisplay`）。吞掉的 10 個裡有 2 個 `debugPrint` —— 而 `debugPrint` **進不了 App 內的日誌檢視頁**，只有 `AppLogger` 會 | 處理 10 個，`debugPrint` 一併改掉 |
| 2 | 「9 個檔把 `e.toString()` 直接顯示給使用者」（`05:391`、`04 §4.3`） | 追到真正的 UI sink 之後是 UI 層 27 處、provider 層 27 處、service 層 3 處，**合計約 54 個呼叫點、33 個檔** | 5g 從 M 改判為 **L**，拆成三個 commit |
| 3 | 「27 個 `IconButton` 缺 tooltip」「`semanticFormatterCallback` 缺」（5f ②③） | **已經不成立。** 97 個 `IconButton` 只有 1 個沒有 `tooltip:`，而那一個（`lyrics_title_bar.dart:188`）用 `ExcludeSemantics` + `Semantics(button:, label:)` 手動補齊。`semanticFormatterCallback` 在 `player_page.dart:529` 已經有了 | **5f 縮到只剩兩項**：迷你播放器手刻 seek bar（`mini_player.dart:147-253`，仍無 `Semantics`）＋ 一條 `meetsGuideline` 冒煙測試 |
| 4 | 「`app_theme.dart` 逐字重複約 85 行」「260 個 `EdgeInsets`」 | 重複區塊是 **71 行且逐位元組相同**（`:124-194` vs `:219-289`）；`EdgeInsets` 是 **312 個構造呼叫、79 個檔**，其中約 76% 的數值本來就落在 4/8/12/16/24/32 | 本輪不做 5b，數字改對，並補 §5.2 的 04-D10 |
| 5 | `lib/ui/AGENTS.md:16-18`：「三個版面欄位刻意**不**進備份」 | **與程式碼相反。** `6efcefc7` 已經把它們加進備份，理由寫在 commit message 裡，AGENTS.md 沒跟著改 | 規則檔過期比沒有規則危險，本輪改正 |

#### 設計上的一件事：映射層已經存在，只是被關在播放層

`PlaybackErrorPresenter.reasonFor` 是一個對 `SourceErrorKind` 的窮舉 switch，
接了 8 個翻譯鍵、有低訊號過濾與合成診斷抑制 —— 而登入頁、搜尋、匯入、歌單對話框
全都在問同一個問題卻各自 `e.toString()`。第二份會漂移，所以**措辭那一半搬到
`lib/core/errors/user_message.dart`**，presenter 只轉發。

這推翻了 presenter 自己在 Phase 4 步驟 H 寫下的理由（「拆開會讓下一次新增 kind
的人改一半就走」）：重試判斷本來就是 `SourceErrorKind.isRetryable` /
`.shouldSkipTrack` 兩個 getter，住在 `source_exception.dart` 的 enum 上，
presenter 只是轉發；而措辭的 switch 是窮舉的，少一個 kind 分析器會先擋下來。
註釋改寫成新的理由，不是刪掉。

`lib/core` 可以 import `lib/data`（既有 3 個檔這樣做）但從不 import
`lib/services`，所以映射層放 `lib/core/errors/` 拿得到 `SourceApiException`，
而 `ToastService`（也在 `lib/core/services/`）可以直接用它。

#### 實機驗收抓到的兩個漏網路徑

**只掃 `lib/ui` 的 sweep 是不夠的。** Android 模擬器上關掉網路搜尋，畫面印出的是：

```
bilibili: BilibiliApiException(-2): 網路連線失敗
netease: NeteaseApiException(-998): 網路連線失敗
youtube: YouTubeApiException(search_error): Search failed: ClientException with
SocketException: Failed host lookup: 'www.youtube.com' ... uri=https://www.youtube.com/results?search_query=hello
```

兩個成因都在 UI 之外：

1. `search_service.dart:113` 用 `errors.add('$type: ${e.toString()}')` 組出整段
   文字，而那段文字會原封不動畫進搜尋頁的 `ErrorDisplay`。
2. YouTube adapter 的搜尋 catch 把底層例外包成 `message: 'Search failed: $e'`，
   而 `sourceErrorReason` 會把 adapter 的 `message` 當成「有意義的診斷」照顯示。
   同一個檔案裡本來就有一個分類器（`_classifyStreamFallbackError`，只用在串流
   fallback），改名為 `_classifySourceError` 並讓搜尋也走它。

修完之後同一條路徑是 `bilibili: 網路連線失敗 / netease: 網路連線失敗 /
youtube: 網路連線失敗`，而完整原文（含 URL）仍在 log 裡。
**靜態規則因此擴大到掃整個 `lib/`**，不只 `lib/ui`。

第三個：電台播放失敗的 toast 是一整條五行的 `DioException`（含
`api.live.bilibili.com`）。那是一個沒有被任何 adapter 包成 `SourceApiException`
的裸 `DioException`，`userMessageFor` 認不得它而退回「未知錯誤」。Dio 是全 App
的 HTTP 層，裸的 `DioException` 逃到 UI 是常態不是例外，所以 `userMessageFor`
接上 `classifyDioError`（adapter 用的同一份），toast 變成
**「播放失敗: 網路連線失敗」**。

#### 靜態規則

新檔 `test/ui/static_rules/error_presentation_static_rule_test.dart`，三條：
`lib/ui` 的 async error 分支不得回傳 `SizedBox.shrink()`；`lib/` 全樹的
`t.x(error: …)` 不得收到原始例外；`lib/ui` 的 `ToastService.*` /
`ErrorDisplay(message:)` 引數不得含 `e.toString()`。
**三條都用刻意寫的違規檔驗證過會失敗**，不是「跑起來是綠的」就算數。

**沒有採用** 04 §10.5-1 的「`Center`+`Column`+`Icon`+`Text` 不得繞過
`ErrorDisplay`」：樹上還有 17 處手刻空狀態，那條規則上線就要嘛一次改完 17 處
（超出本輪），要嘛帶一份 17 筆白名單（AGENTS.md 明文反對的平行清單）。

#### 實機驗收

**Android（`Medium_Phone`，冷開機 `-no-snapshot-load`）** ——
錯誤路徑靠 `adb shell svc wifi disable && svc data disable` 誘發：

| 要驗什麼 | 觀察到什麼 |
|---|---|
| 搜尋失敗的錯誤區塊 | 修前：三段原文含 `ClientException`、`SocketException` 與完整 URL。修後：`bilibili: 網路連線失敗 / netease: 網路連線失敗 / youtube: 網路連線失敗` |
| 原文有沒有留下 | log 裡仍有完整的 `ClientException with SocketException: Failed host lookup: 'www.youtube.com' ... uri=…`，並帶 `[ERROR] [Search] Searching youtube failed` |
| 電台播放失敗的 toast | 修前：五行 `DioException [connection error] … api.live.bilibili.com`。修後：**「播放失敗: 網路連線失敗」** 一行 |
| 恢復網路後沒有回歸 | 同一條搜尋回 43 筆線上結果；首頁三個排行榜音源都在 |

**Windows（P0-4 是 Windows-only，Android 構不到）**：播一首沒有歌詞匹配的曲目
→ Detail Panel 切歌詞模式顯示「暫無歌詞」→ 開浮動歌詞視窗 →
**視窗同樣顯示「暫無歌詞」**，與面板一致（修前會永遠停在「等待歌詞…」）。

**驗不到的三項，照實記錄**：

- **P0-2**（下載管理員的 error 分支）要 `trackByIdProvider` 這一次 Isar 讀取真的
  拋例外才會出現，裝置上沒有安全的誘發方式（Isar 寫爆是 §4.8 那顆雷）。只有
  widget 測試覆蓋，實機只確認正常列沒有回歸。
- **P0-3 的三個區塊級分支**（首頁歌單／最近播放／播放歷史統計）讀的都是本地
  Isar，關網路對它們沒有作用，一樣構不到。同樣只有測試覆蓋。
- **P0-4 的反向情況**（有歌詞的曲目仍正常渲染歌詞）沒驗到：Orca 在會話中途丟失
  了 FMP 主視窗的 UIA handle，而 Win32 合成點擊送不進 Flutter view；能構到的
  排行榜曲目在這台機器上都沒有歌詞匹配。

順帶記進 `verify-on-device`：`adb shell am force-stop` 會把 `flutter run` 的連線
斷掉，之後每一次 hot restart 都是**靜默的空操作** —— 本輪因此拍到兩張修前行為的
截圖，差點被當成修不好。終端只印一次 `Lost connection to device.` 就沒了。

裝置狀態：Android 模擬器已 `adb emu kill`、`adb devices` 為空、無殘留行程，
網路已恢復。Windows 的 FMP 已 `q` 結束、視窗幾何還原成原本的 640,296 1280x800；
本輪在這台機器上播過兩首歌，播放佇列與播放歷史因此各多了記錄，未清除。
過程中誤點開了使用者的記事本設定頁，已導覽回文件，未更動任何設定。

### 6.11 UI：版面、斷點與無障礙（2026-09-07）

commit `81d8fc1f`…`063a5b73`。測試 1,429 → 1,459。`flutter analyze` 全綠。
本輪把 Phase 5 剩下的五個子項一次做完，Phase 5 收尾。

#### 八條說法要更正

| # | 原本的說法 | 實況 | 處置 |
|---|---|---|---|
| 1 | 5a① 是「改用容器級 `columnsFor(constraints.maxWidth)` —— 一行修法」，已由 `9557e03f` 完成 | **兩處都不對。** `columnsFor` 這個名字**全樹不存在**；`LayoutBuilder` + `constraints.maxWidth` 在 `9557e03f` **之前就有**（`git show 9557e03f^` 可證）。那個 commit 做的是「放不下換行而不是丟掉」＋把 inline 的斷點 switch 抽成具名的 `rankingColumnsFor`，而且註釋明說欄數刻意不改。容器級的「量測」是舊的，容器級的「函式名」是新的，它查的門檻仍然是視窗級的 600/1200 | 5c 要做的分離本輪才做 |
| 2 | 「312 個 `EdgeInsets`、79 個檔」 | 嚴格的構造呼叫是 **260 處 / 71 檔**（symmetric 99、all 74、only 48、fromLTRB 39）；312 = 260 + 52 個 `EdgeInsets.zero`。**76% 落在 4/8/12/16/24/32 是精確的**（347/457 個數值引數 = 75.9%） | 數字改對，04-D10 不變 |
| 3 | 5b 要建 `AppMotion`，因為有「13 個 inline `Curves.*`」 | **前提只成立一半。** 時長早就 token 化：`AnimationDurations` 被 19 個檔、36 處使用，`lib/ui` 只剩 17 處字面值而其中 10 處在同一個 debug 頁。曲線確實是 13 處、4 個值 | **不建。** 記為 04-D11 |
| 4 | 「`app_theme.dart` 逐字重複 71 行」，檔案在 `lib/core/theme/` | 檔案在 **`lib/ui/theme/app_theme.dart`**。重複的不只 71 行：`lightTheme` 與 `darkTheme` 兩個 93 行的函式**全文只差三行**，而其中兩行是同一個 `Brightness`（一次給 `_colorScheme`，一次多餘地給 `ThemeData`） | 不是抽 sub-theme，是整個函式體收成一個私有建構器（−97/+27） |
| 5 | 04 §5.2：「兩個全螢幕播放頁的主播放／暫停鍵完全沒有語意標籤」 | **已失效。** `PlayerPlayPauseButton` 的四個呼叫點現在都傳了 `tooltip` | 5f 只剩迷你播放器那一條進度條 ＋ 冒煙測試 |
| 6 | `repairSettingsInvariants` 會「夾住」不合法的面板寬度 | 它是**重設為預設值**，不是夾到邊界（`9999 → 380`），而 `database_migration_test.dart:370` 把這個行為釘住了 | 下限提到 320 時，停在 280–319 的使用者會被重設而不是變成 320 —— 本輪改成 clamp，並補兩條測試 |
| 7 | — | `LayoutSettingsState.isLoaded` **寫了但全樹沒有人讀** | 刪掉 |
| 8 | — | `responsive_scaffold.dart` 的註釋說收起寬度是 48/120，程式碼是 **36/54**（還重複了一行）；`Expanded(flex: 2)` 與播放頁的 `Expanded(flex: 3)` 都是各自 `Row`/`Column` 裡唯一的 flex child，flex 值無作用 | 順手改正 |

#### 執行中發現

- **`columnsFor` 的常數不是自由的。** `(w / 400).floor().clamp(1, 3)` 精確重現
  `home_ranking_sources_test.dart` 現有的四條斷言（1200→3、868→2、800→2、
  599→1），所以那六條測試一行不改就是這一步的驗收。04 §10.2 提的
  `idealColumn = 420` 會讓 800→1，直接弄紅測試。**唯一刻意的差異**在容器寬
  600–799 這一帶：2 欄變 1 欄（兩個 300dp 的排行榜欄位低於卡片的舒適寬度）。
- **「預設寬度 `min(412, 視窗寬/4)`」不需要存在。** 現有 schema 的
  `double detailPanelWidth = 380` 不可為 null，沒有「使用者從未選過」的哨兵值，
  而加一個欄位還會踩 `settings_backup_coverage_static_rule_test.dart`。但加上
  渲染期的 40% 夾擠之後這個公式就多餘了：存 412、在 840dp 視窗上渲染成 336
  （= 840 × 0.4），結果與公式一致。**所以不加欄位。**
- **`AppLayout` 搬進自己的檔案。** 面板界限同時被 UI 層（拖曳與渲染）和資料層
  （`repairSettingsInvariants`、備份 DTO）讀取，而 `ui_constants.dart` import
  了 `package:flutter/material.dart`。`lib/core/constants/app_layout.dart` 只
  import `dart:math`，資料層才共用得到同一組數字，不必再抄一份 280/500。
- **`Semantics(slider:)` 少了 `container: true` 會併進按鈕節點。** 沒有它，
  迷你播放器的語意樹上會出現**一個同時是 button 又是 slider、標籤是兩句話黏
  在一起**的節點（`label: "Open player\nPlayback progress"`）。實際 dump 出來
  才看到。順帶：`find.bySemanticsLabel` 找不到「不擁有節點」的標註，所以那條
  測試一開始怎麼寫都找不到東西。
- **兩條 guideline 都用刻意的回歸驗證過會失敗**：把迷你播放器高度從 64 改成
  20 → `androidTapTargetGuideline` 紅；拿掉 `label:` → `labeledTapTargetGuideline`
  紅。不是「跑起來是綠的」就算數。

#### 實機驗收（Android 模擬器）

`Medium_Phone`（411dp）與 `Medium_Tablet`（1280×800dp，並用
`adb shell wm size` + 重啟 App 覆蓋其餘級距）。**本輪沒有 Windows 專屬的改動**，
`_ExpandedLayout` 由寬度斷點選出、與平台無關，所以只驗 Android。

| 視窗 | WindowClass | 觀察到什麼 |
|---|---|---|
| 411 × 914 | `compact` | 底部導覽**五個**分頁（`第 N 個分頁 (共 5 個)`），沒有「設定」；首頁右上角的「設定」按鈕進得去設定頁，而且**高亮留在首頁**；迷你播放器的進度條在 uiautomator 上是 `android.widget.SeekBar`、`focusable=true`、`content-desc="0:52, 播放進度"` —— 改動前這個節點**完全不存在** |
| 720 × 600 | `medium` | 固定 72dp 導覽軌、無收合鍵、無面板（不變）；排行榜 1 欄（容器 648dp），三個音源全在 |
| 900 × 700 | `expanded`（**新的一段**） | 可收合導覽軌 ＋ 軌底的設定鍵 ＋ 右側 36dp 的面板收合條 —— 這一帶以前**完全拿不到面板**；排行榜 2 欄 |
| 1280 × 800 | `large` | 排行榜 3 欄；把把手拖到底停在 **512dp = 1280 × 0.4**（舊模型是絕對值 500）；面板吃到 512dp 之後內容區 672dp、排行榜收成 1 欄而**三個音源一個都沒有消失**；沒有歌詞的曲目播放頁是**單欄置中**（舊版會把 58% 畫面留給一句「暫無歌詞」） |
| 1700 × 800 | `extraLarge` | 面板上限 **682dp ≈ 1700 × 0.4**（舊模型仍是 500，只佔 29%）；面板拖到底時排行榜 2 欄，三個音源全在 —— 這正是路線圖驗收要的「1700 + 面板拖到上限，排行榜不變」 |
| 1200 × 500 | `large` 但矮 | 播放頁**維持單欄**。舊的 `width >= 1200` 會在這裡給雙欄；`height >= 520` 擋掉了（抄 Auxio 的 `layout-h520dp`） |

持久化：既有安裝（有舊資料庫）保留存下來的 380dp 與展開狀態；
`pm clear` 之後的全新安裝，面板是 36dp 的收合條 —— 決策 04-D2 的「預設收起」
只作用於新建的列，既有使用者的選擇沒有被改寫。

#### 順帶發現的一個既有缺陷（本輪不修）

1200 × **500dp** 時收合的導覽軌會 `OVERFLOWED BY 64` 像素。量到的每個目的地
高 64dp：新的軌需要 5 × 64 + 56（設定鍵）+ 65（漢堡鍵與分隔線）= 441dp，
舊的六個目的地需要 6 × 64 + 65 = 449dp，而可用高度是 500 − 64（迷你播放器）
− 24（狀態列）= 412dp。**兩者都放不下，新的還少 8dp**，所以這是矮視窗的既有
問題而不是本輪造成的。它屬於 P1-2 那一類（固定高度遇上空間不足），本輪沒有
處理短視窗，照實記在這裡。

#### 驗不到的

`detailPanelStoredMax`（1600）只有在手改資料庫或匯入壞掉的備份時才碰得到，
裝置上沒有誘發路徑；它只有單元測試覆蓋（`database_migration_test.dart` 三條）。

裝置狀態：模擬器已 `adb emu kill`，`adb devices` 為空，無殘留行程，
`wm size` 已 `reset`。**本輪沒有動使用者的 Windows 機器。**

---

### 6.12 狀態層：Riverpod Notifier 改寫（2026-09-07）

Phase 4 列出但從未開工的兩項裡的第一項。**這一輪是零行為變更**，但它動了
`lib/providers/` 底下的每一個檔案，以及 `lib/services/` 的四個。

#### 為什麼四輪 Phase 4 都沒做它

不是因為技術上做不到，也沒有任何文件記錄過「決定不做」。是**兩份文件互相矛盾**：
路線圖 Phase 4 寫「**同時做**」，而 `lib/providers/AGENTS.md` § Riverpod 3 寫
「Rewriting the remaining `StateNotifierProvider`s into `Notifier` is a separate,
later change — **do not start it opportunistically**」。`AGENTS.md` 是有約束力的
規則檔（根 `AGENTS.md` 明文），所以每一輪都被它擋住，而它自己從來沒有被排成
獨立的一輪。**本輪把那句話刪掉，換成「lib 已無 legacy，由靜態測試守著」。**

#### 十條要更正的說法

| # | 開工前的說法 | 實況 | 處置 |
|---|---|---|---|
| 1 | 「39 個 `StateNotifierProvider`」（03 §1217） | **43 個 legacy provider**：40 個 `StateNotifierProvider`（33 plain、5 `.autoDispose`、1 `.family`、1 `.autoDispose.family`）＋ 3 個 `StateProvider`，由 36 個 notifier 類別支撐。`lib` 裡 33 個檔 import `legacy.dart` | 全部改完；現況 43 個 `NotifierProvider`（36 plain、5 `.autoDispose`、2 `.family`）＋ 39 個 `Notifier` 類別 |
| 2 | `AGENTS.md` 列了 `StateController`、`ChangeNotifierProvider` | **兩者實際用量都是 0** | 規則檔的清單縮掉 |
| 3 | 本輪計畫：「兩個 `.family` 是唯一不機械的一組」，並準備了退路 | **不成立。** `NotifierProvider.family` 的 create 函式**吃 family 參數**（riverpod `builder.dart:669`），所以 id 照樣走建構子 | 兩個 family 都是機械翻譯，退路沒有用上 |
| 4 | 本輪計畫：A2 是 `lib/providers/settings/` 的「11 個」 | 該目錄只有 **10 個**；被誤算進去的 `audio_settings_provider` / `playback_settings_provider` 住在 `lib/providers/audio/` | 那兩個併進 A5 |
| 5 | — | **`ref.onDispose` 在「provider 即將 rebuild」時也會跑**（riverpod `ref.dart:513-518`）。這正是「每次 build 開的訂閱都成對關掉」成立的原因 | 寫進規則檔；`PlaylistImportNotifier` 的訂閱洩漏由 `notifier_rebuild_test.dart` 守著（拿掉 `ref.onDispose` 那條測試會紅，已實測） |
| 6 | — | **生命週期回呼裡不能碰任何別的 provider**：`state =` 與 `ref.invalidate` 都會撞上 `riverpod/src/core/ref.dart:235` 的斷言。`StateNotifier` 時代是允許的 | `downloadServiceProvider` 釋放時清空下載進度那一行改成排到回呼堆疊之外並加 `ref.mounted` 守衛；`RadioController._teardown` 要碰的兩個物件改在 `build()` 先抓在手上 |
| 7 | — | **provider 建立期間也不能改別的 provider**（`element.dart:804`）。把第 6 點那行搬到工廠開頭同樣被擋 | 只有「排出回呼堆疊」這一條路 |
| 8 | — | **最貴的一條**：`AudioController._teardown` 做的是**所有權釋放**（dispose 後端音訊服務、交還系統媒體控制）。`onDispose` 既然在 rebuild 前也跑，用 `ref.watch` 取協作者就等於「任何一個相依變動都會在控制器還活著的時候把播放器關掉」。實測症狀是 `Cannot add new events after calling close` | `AudioController.build()` 的協作者一律 `ref.read`。`RadioController` 相反 —— 它**需要** `watch`（等資料庫開好），而它的 teardown 只取消自己重建得回來的訂閱 |
| 9 | — | `Ref.mounted` 存在（`ref.dart:112`）；`Notifier.state` 是 `@protected @visibleForTesting`（`notifier_provider.dart:79-81`） | 13 個檔約 58 處 `mounted` 機械改成 `ref.mounted`（`AudioController` / `RankingCacheService` 保留自己的 `_isDisposed`）；`lib` 裡三處外部 `state =` 改成具名方法 |
| 10 | — | **`Notifier.new` 不吃參數**，所以每一處「測試用建構子注入」都要改。實際規模：**51 個直接 new 的呼叫點、15 處 `overrideWith`、9 個測試替身** | 見下 |

#### `Notifier.new` 不吃參數帶來的結構後果

這是本輪唯一真正改變了介面形狀的地方，全部都是被框架逼出來的，不是預先抽象：

- 三個窄 provider：`mixTracksFetcherProvider`、
  `optionalLyricsAutoMatchServiceProvider`、`homeRankingSettingsStoreProvider`。
  前兩個讓播放測試不必為了一個可選協作者把整條歌詞／設定鏈拉起來（那條鏈會碰
  secure storage，測試環境沒有實作）。
- `RankingCacheService` 拆出 `bindSources()`：初次載入與網路監聽以前寫在
  provider 工廠的 body 裡，測試直接 new 就能跳過；`NotifierProvider` 沒有 body，
  所以接線與啟動分成兩半，測試子類只呼叫前一半。
- 兩個測試支援檔：`test/support/audio_controller_harness.dart`（把
  `AudioController` 舊建構子的十個具名參數翻譯成 override）與
  `test/support/audio_settings_notifier.dart`。

#### 反過來拿掉的東西（§6.8 預言的那一半）

§6.8 說「`Notifier` 可以把 `ref` 拿進來，起播 provider 的接線就不必全擠在
provider 工廠裡」。實際兌現的：

- `audioControllerProvider` 的工廠從 **74 行變成 1 行**（8 個 `ref.watch`、
  3 個回呼接線、1 條訂閱 ＋ `ref.onDispose`、`Future.microtask` 全部進 `build()`）。
- `FileExistsCache` 的 `onEpochChanged` 回呼**整個刪掉** —— 它存在的唯一理由是
  `StateNotifier` 拿不到 `ref`。
- `RadioController.forLoading()` 這個第二建構子、`_DummyRadioRepository`、
  `_DummyAudioService` **三個一起刪掉**：資料庫還沒開的分支變成 `build()` 的一條
  早退路徑。（順帶解決了 Round B 原本要處理的「`_DummyAudioService` 的
  `noSuchMethod` 會靜默吞掉新介面成員」。）
- 七個類別不再需要在建構子吃 `Ref`。

規模：**69 個檔、+1601 / −1105**（lib +826 / −769，test +775 / −336）。

#### 驗收

`flutter analyze` 全綠；`flutter test --exclude-tags live` **1466 通過**
（基準 1459 ＋ 7 條新測試），九個 commit 每一個都跑過完整套件。

**實機（Android 模擬器 `Medium_Phone`，1080×2400）**：完整走過首頁、設定、
音訊品質、音樂庫、歌單詳情、播放、電台、搜尋、全螢幕播放頁。506 行 Dart log 裡
**零個** `LateInitializationError` / `UnmountedRefException` /
`Cannot use Ref` / 未處理例外。逐項證據：

| 觀察到的 | 證明了哪一批 |
|---|---|
| 首頁 YouTube／網易雲排行榜載入（Netease 50 首）、`[RankingCache] 網絡恢復監聽已設置` | A6 的 `bindSources()` ＋ 初次載入 ＋ 網路監聽 |
| `[ConnectivityNotifier] DNS polling started (interval: 15s)` | A6 |
| 設定頁主題／主題色／字體／語言四項都顯示已載入的值 | A2 |
| 音訊品質頁三組優先級都填好 | A5（`audioSettingsProvider`，會碰 secure storage 的那一個） |
| 音樂庫列出歌單、歌單詳情載入曲目與時長 | A4（`playlistListProvider` 的 Isar `watchAll()` 訂閱、`playlistDetailProvider` family） |
| 播放本機檔案成功，`dumpsys media_session` = `state=PLAYING(3), position=8389`；迷你播放器語意節點 `'0:07, 播放進度'` | A8 ＋ A1（`queueStateProvider` 投影）；順帶確認 Phase 5f 的 slider 語意沒有回歸 |
| `[RadioController] 載入 1 個電台` / `watchAll 觸發`，且**進電台頁時音樂持續播放** | A7 的 `build()` 分支；同時是第 8 點那個坑的反證 —— 沒有誤觸 `AudioController` 的 teardown |
| 搜尋紀錄「hello」顯示、搜尋回「線上結果 (60)」 | A3 |
| 曲目播完 → `playing=false, processingState=ready` | `_onTrackCompleted` 在單曲佇列末端暫停，行為未變 |

**本輪發現、未修的既有問題**（都與本輪無關，記在這裡以免下一輪重新診斷）：

1. ~~**`test/bilibili_source_test.dart` 有兩條真連網測試沒有標 `tags: 'live'`**
   （`should fetch audio URL for valid bvid`、`refreshAudioUrl should refresh
   audio URL for track with expired URL`；`:819` 的註釋自承「此测试需要网络连接」）。~~
   **這一條寫錯了，Round B 開工時更正**：被點名的那兩條**早就標了** ——
   `git blame` 顯示 `:849` 與 `:979` 的 `tags: 'live'` 來自 2026-09-01 的
   `598fce27`。真正沒標的是**另一條**：`should throw BilibiliApiException for
   invalid bvid`（`:851`），它同樣用 `setUp`（`:31`）建的無假 adapter
   `BilibiliSource()`，而且 `expect(() => ..., throwsA(...))`（`:854`）沒有
   `await expectLater`。→ **issue #56**。
2. **`test/services/audio/playback_handoff_gate_test.dart` 的
   `a seek right after navigation waits out the stabilization window`
   在完整套件負載下偶發失敗**，單獨跑通過。原因是 `stabilizationDelay` 是
   40ms 的真計時器（`:19`、`:29`），而 `settled()` 用固定 10 圈的
   `pumpEventQueue`（`:37`）去斷言「還沒完成」。與 issue #43 同一類。
   → **issue #55**。
3. 首頁的 Bilibili 排行榜在本輪實機期間一直是
   `BilibiliApiException(-352): 請求過於頻繁` —— 開發機的風控狀態，不是回歸。

**沒有做的**：`FmpAudioService` 的佇列語意（Round B）。Phase 4 按其本節定義仍差這一項。

---

### 6.13 音訊：交界推進交給後端（gapless）（2026-09-07）

Phase 4 列出但從未開工的兩項裡的第二項，也是本輪**唯一的行為變更**。介面落在
`setNextMedia(PreparedPlaybackMedia?)` ＋ `Stream<PreparedPlaybackMedia>
advancedToNext`，不是原本寫的 `setQueue(List)` ＋ `supportsQueue`。

#### 這是控制流倒轉，不是加兩個方法

一旦第二個媒體進了後端的播放清單，`ConcatenatingAudioSource` 與 mpv playlist
就會**自己**在交界處推進 —— 兩個套件都沒有「播到項目邊界就停」的模式。所以
「只做預緩衝、不倒轉控制流」這個中間選項不存在：控制器從「決定並發起下一首」
改成「決定下一首、交給後端、事後跟隨」。

#### 十條要更正的說法

| # | 開工前的說法 | 實況 | 處置 |
|---|---|---|---|
| 1 | 02 §6.3 階段 4 第 12 項：`setQueue(List<PreparedPlaybackMedia>)` | **這個簽名做不到。** 串流 URL 每首要一次網路解析、簽名有效期 1–2 小時、會被風控、未過期也可能 403（所以才有 `invalidateStream`）。佇列上限 1000 首 | 改成一次只交**一個**前瞻項目 |
| 2 | 02 §609：介面要加 `supportsQueue` 這類能力查詢 | **兩個後端都會回 `true`** | 不加。兩邊都真的布林是替想像中的第三個後端保留位置 |
| 3 | 「`supportsQueue` 可能該放進 `PlaybackCapabilities`」 | 不該。那個型別講的是「系統媒體鍵在當前播放模式下能做什麼」（`playback_capabilities.dart:13-45`），消費者只有 `NowPlayingPublisher` 與 SMTC，兩個後端都沒 import 它 | 軸不同，不放 |
| 4 | 「just_audio 用 `ConcatenatingAudioSource`」講得像現況 | **FMP 完全沒用它。** 四條開媒體路徑都是 `setAudioSource(AudioSource.uri(...))` 單一來源（`just_audio_service.dart:556-560` 等） | Android 後端改成「永遠一個 `ConcatenatingAudioSource`，平常只有一個 child」。**這本身就是行為變更**，B1 獨立成一個 commit 並上機驗過 |
| 5 | — | `ConcatenatingAudioSource` 的文件原文：「Playback between items will be **gapless on Android, iOS and macOS**」（`just_audio.dart:2544-2546`）；但 `add` / `insert` / `removeAt` 的註釋開頭都是 `/// (Untested)`（`:2597` 起） | 用了，並在實機上確認過（下方「實機」第 3 點） |
| 6 | 「media_kit 用 `Player.add` 追加即可」 | 對，但 `add()` 走 `loadfile <uri> append`（`native/player/real.dart:477`），**命令本身不帶 headers**。headers 是靠 mpv 的 `on_load` hook 從 `Media` 的全域 map 取出來設進 `http-header-fields`（`real.dart:2137-2180`），並在 `on_unload` 重設成 NONE | 與第 7 點直接衝突，成為本輪最大的風險 |
| 7 | — | **mpv 的 `--prefetch-playlist` 預設 `no`，media_kit 從沒設過它。** 手冊原文：「This merely opens the URL of the next playlist entry as soon as the current URL is fully read.」／「**This can give subtly wrong results if per-file options are used**…」／「**Highly experimental.**」 | 自己設 `yes`，並**先用實機把 header 問題問清楚**才往下做（結果見下方） |
| 8 | 計畫寫「B3 要同步 `PlaybackRecoveryCoordinator.clearForNewPlayback(track)`」 | **那個方法是死的**：完全沒用它的 `track` 參數，函式體與 `reset()` 逐字相同，production 零呼叫者 | 連同它的測試一起刪掉 |
| 9 | 計畫寫「在預取的掛點上把 `selectPlayback` 出來的 media 交給 `setNextMedia`」，並擔心預取快取是**單次使用**的 | 掛點手上確實沒有 media（`_prefetchNextIfRequested` 只吃一個 `bool`）。但**快取不是單次使用的** —— `_reusableResolution`（`stream_resolution_service.dart:325-341`）的 `remove` 後面緊接著 `_resolvedStreams[key] = cached`，那是更新 LRU 順序，不是取用即丟 | arm 時直接再呼叫一次 `selectPlayback` 就好，不必改串流層的管線。測試斷言下一首只解析一次 |
| 10 | — | **1 秒輪詢備援是全程開著的**（`initialize():352` 起，只在 `_teardown()` 停），而且它直接合成 `EndedNaturally`，**繞過兩個後端的 `_classifyCompletion`** | arm 期間讓路，但**不是無限期**：連續三格（3 秒）還停在結尾就收回推進權。那個備援本來就是為了「後台 completed 事件丟失」而存在的 |

#### 實機上才發現的一件事

**跟隨完成之後沒有人 arm 再下一首**，所以一條佇列只有**第一個**交界是 gapless。
平常的 arm 掛在 `PlaybackRequestSession` 的預取上，而跟隨路徑刻意不發請求（後端
已經在播了）。單元測試看不出來 —— 它們只驗一個交界。修在
`fix(audio): arm the boundary after the one just crossed`。

#### disarm 的網掛在哪裡

不在七個佇列命令上各掛一次，而是掛在 `_updateQueueState()` —— 佇列的每一次變動
（命令、shuffle、loop、Mix 補歌）都會經由 `QueueManager.stateStream` 走到那裡。
一個純比較（「現在的下一首還是不是當初交出去的那一個」）就夠了，不需要網路。
另外 `_startSessionLoadingState` 一定 disarm，因為 `_stopForRequest` 的無條件
`stop()` 本來就會清掉後端的播放清單。

不 arm 的條件：`LoopMode.one`（`getNextIndex()` 根本不看它，照著 arm 就是播錯歌）、
`_isPlayingOutOfQueue`（temporary / detached）、電台占用後端、Mix 正在補歌。

#### 驗收

`flutter analyze` 全綠；`flutter test --exclude-tags live` **1482 通過**
（Round A 之後的基準 1466 ＋ 16 條新測試）。三條守門測試各自用「刻意改壞再改回來」
確認會紅：loop-one 不 arm、佇列變動要 disarm、切到 loop-one 要 disarm。

**Windows（media_kit / 真 libmpv）**：用一個**要求 `Referer` 才給檔案**的本機
HTTP 伺服器直接驗 mpv 的行為，不動使用者的音樂庫（開發機當時正被 B 站風控擋，
而且問題本身與 B 站無關 —— 要問的是「header 有沒有跟著送出去」）。

| 量到的 | `prefetch-playlist=yes` | 沒有它（對照組） |
|---|---|---|
| 第二個 URL 何時被開啟（交界在 ≈6.0s） | **+937ms / +949ms** | **+5912ms / +5893ms**（交界當下才開） |
| 兩次請求都帶著 `Referer` / `Origin` | ✅ | ✅ |
| 交界處的時間軸接縫（對每一段的 `(wallclock, position)` 做最小平方擬合取截距） | **0.0ms / −0.1ms** | −199.9ms / −209.9ms |

→ **重核 #6 ＋ #7 那個風險不成立**：mpv 的 `on_load` hook 對被預先開起來的項目
**有跑**，per-file 的 `http-header-fields` 跟著送出去了。Windows 拿到完整的
gapless，不必退成「只對本機檔案 arm」。

**要誠實說的**：對照組那個 −200ms 是**方法的系統性偏差**（mpv 的 `completed`
比位置抵達名目時長早約 200ms 發出），不是「舊路徑比新路徑還快」。在**本機檔案**
上兩條路徑的接縫都在這個方法的解析度以內 —— 真正量得到的差別是**開流的提前量**
（提早約 5 秒），而那正是真實串流上 DNS / TLS / CDN 握手要花的時間。

**Android 模擬器（just_audio / 真 ExoPlayer）**：

1. B1 的單 child 包裝零回歸 —— 從 VM Service 讀到活著的
   `_playlist` 是 `ConcatenatingAudioSource`、`children.length == 1`、
   `useLazyPreparation == false`，同時 `dumpsys media_session` =
   `state=PLAYING(3), position=4862`。
2. arm 之後 `children.length == 2`（`ProgressiveAudioSource` ×2），
   `_nextMedia` 是 `LocalPlaybackMedia` —— 套件標「(Untested)」的 `add` 可用。
3. **連續五個交界**，每一個都是
   `[JustAudioService] Backend advanced to next medium` →
   `[AudioController] Following the backend across a gapless boundary` →
   `[FmpAudioHandler] Updated media item` → `Armed the next medium`。
   **其中後三個是在 app 被 HOME 鍵切到背景之後發生的**
   （`mCurrentFocus` = launcher），播放全程沒有中斷
   （`state=PLAYING(3)`）。
4. 整段 log 裡**零** `PlayerState changed: ... loading`、**零**
   `Track completed`、**零** `Position check triggered auto-next` ——
   交界沒有回到載入狀態，完成路徑與輪詢備援都沒有插手，沒有二次前進。

**沒有做的**：**沒有去驅動使用者在 Windows 上那個真的 FMP**（SMTC 的
`IsNextEnabled`）。理由是那會動到使用者真實的播放佇列與設定，而這一輪對
`PlaybackCapabilities` 與 `NowPlayingPublisher` 一行都沒改，交界處的發佈走的是
跟以前完全相同的 `_updatePlayingTrack` → `publishTrack`，而那條路已經在 Android
上驗過五次（`FmpAudioHandler Updated media item`）。後端本身則是用真的 libmpv
＋ 出貨用的那組參數驗的。**這是刻意留下的缺口，不是「測試通過」的代稱。**

#### 順帶發現、未修的既有問題

- **佇列還不存在時按迴圈按鈕，UI 會顯示新模式但實際沒有生效。**
  `QueueManager.setLoopMode`（`queue_manager.dart:712`）在 `_currentQueue == null`
  時直接 return，而 `AudioController.setLoopMode` 照樣
  `_emitQueueState(...)` 把新模式投影出去。本輪實機期間踩到：按了「列表循環」，
  按鈕變了，但 `PlayQueue.loopMode` 還是 `none`。與本輪無關。

---

### 6.14 授權與揭露，與一段被改寫的遠端歷史（2026-09-07）

本輪的起點不是程式碼：`origin/main` 停在 `598fce27`（2026-09-01），**Phase 0–5
的 143 個 commit 從來沒有推上去過**。先把它們落地，再做 Phase 7。

#### 一、落地時才浮出來的事

**1. issue #53 的根因找到了，而且 CI 當場就紅。**

`origin/main` 的 `sdk` 下界是 **3.5**，Phase 2 的 `3b1c7244`
（`chore(deps): move off the dormant isar to isar_community`）把它抬到 **3.9**。
`dart_style` 從語言版本 **3.7** 起改用 tall style —— 所以 formatter 的風格在
Phase 2 那個 commit 默默換過了，而 CI 從那之後就沒看過這棵樹。#53 當時比對的
「CI 上綠的 main」是抬升**前**的遠端 main，所以那份紀錄看起來自相矛盾。

PR #57 第一次讓 CI 看到這批程式碼，`Check formatting` 在 42 秒內失敗。

量到的兩個選項都不是零成本（553 個已追蹤的 `.dart`）：

| 風格 | 要重排的檔案 |
|---|---:|
| tall（語言版本 3.9 的實際預設） | **476** |
| short（`--language-version=3.6` 釘住） | **88** |

那 88 個全部是 Phase 0–5 期間手寫的 —— 因為 #53 當時的結論就是「不要跑
`dart format`」。**已定案：採用 tall style**（`eaa6870f`），並把兩個全樹重排
commit 寫進 `.git-blame-ignore-revs`。釘住 short style 只是把 #53 的陷阱留著：
任何人順手跑一次不帶 flag 的 `dart format` 還是會把檔案重排成另一種風格。

**2. 重排打掉 11 條測試，全部是同一類。** 靠原始碼字串比對的靜態規則測試釘的是
formatter 當下的換行決定，例如 `contains('playFile(path, track: track)')` 或
`contains('child: const PlayerPage(),')`。修法**不是**把新的排版重新釘一次，而是
改成不受換行影響的形式：單行的結構片段（`LocalPlaybackMedia(:final path, ...) =>
playFile(`）或帶 `\s*` 的 regex。另外 `app_layout.dart` 有一個 `if` 因為函式體被
移到下一行而觸發 `curly_braces_in_flow_control_structures`，補上大括號。

**3. `logger` 這個 dependabot PR（#49）本來就不該存在。** Phase 0 的 `364c7319`
已經把它移除，`pubspec.yaml` 與 `pubspec.lock` 都沒有它 —— dependabot 自己也在
main 落地後把 PR 關掉了。剩下六個已分流並逐一在 PR 上留了狀態，本輪不做任何實際
升級（`go_router` 14→18 是真正的遷移，`window_manager` 0.4→0.5 在 pub 語意下
等同破壞性變更）。

**4. 推之前掃到三行本機絕對路徑**（`docs/review/01-*.md`、`02-*.md`），含
Windows 帳號名。repo 是公開的，已遮成 `<user>`（`a9f32737`）。憑證類掃描
（SESSDATA / MUSIC_U / Bearer / VM Service token 形狀）命中的全是遮蔽機制的
說明文字與假測試值。

#### 二、Phase 7 執行時與計畫不符的地方

| # | 路線圖說 | 實況 |
|---|---|---|
| 1 | 7.3 要「CHANGELOG 記一筆」 | **`CHANGELOG.md` 不存在**，release note 由 `release.yml` 從 `git log` 動態產生。這一項刪掉，不為了它新建一個檔案 |
| 2 | 驗收要「`showLicensePage()` 之外另有一個第三方授權頁」 | 改用 **`LicenseRegistry.addLicense`** 併進現有的「開源授權」頁。那是 Flutter 為此設計的擴充點，零新頁面、零新 i18n 字串、零新入口，而使用者只要記一個地方 |
| 3 | 「206 個 Dart 依賴」 | `pubspec.lock` 現在是 **207**（42 direct main + 7 direct dev + 158 transitive；202 hosted + 5 SDK） |
| 4 | 7.1 要列「206 個依賴的授權清單」 | 全文不重抄 —— app 內的 `showLicensePage` 已經自動收錄每個 pub 套件自帶的 `LICENSE`。`THIRD_PARTY_LICENSES.md` 只給分佈與指路 |

**依賴授權重新逐檔清點**（讀本機 pub cache 每個 hosted 套件的 `LICENSE`，
202 個全部有檔、零 UNKNOWN）：

| 授權 | 套件數 |
|---|---:|
| BSD-3-Clause | 116 |
| MIT | 60 |
| Apache-2.0 | 19 |
| BSD-2-Clause | 6 |
| CC0-1.0 | 1 |
| **GPL / LGPL / MPL / AGPL** | **0** |

**libmpv / FFmpeg 的建置旗標這次是第一手讀的**，不是沿用 03 的紀錄：
`media-kit/libmpv-win32-audio-build`（master，已封存、無 LICENSE 檔）的
`packages/mpv.cmake:29` 是 `-Dgpl=false`，`packages/ffmpeg.cmake:34-36` 是
`--disable-gpl --disable-nonfree --enable-version3`。結論不變：**LGPL 不是 GPL**。

**7.2 沒有照譜系 A 抄，改寫成獨立表達。** 路線圖建議照 `AynaLivePlayer/miaosic`
（MIT）的寫法重寫，但那仍然要背一份 attribution。實際做法是用標準庫重寫：
`_k1` 那張十六進位對照表整張消失（`digest.bytes[i]` 就是那個位元組），手寫的
6 次 base64 迴圈換成 `base64.encode(...)` 加一次 `replaceAll(RegExp(r'[+/=]'), '')`
—— 等價性是可證的，因為原本的 `i == 5` 特判正是「尾端單一位元組產 2 字元、不補
`=`」。89 行降到 44 行。**等價性有兩層證據**：6 組從改寫前實作抓下來的 golden
向量（含空字串、CJK、長字串、真實 API payload），以及 2000 組隨機輸入的新舊交叉
比對，全部逐字元相同。

#### 三、實機驗證

| 平台 | 觀察到的 |
|---|---|
| Android 模擬器 | 設定 → 關於 → 開源授權：**`Protocol research` 在列**（`process_runner` 與 `pub_semver` 之間），內文含 `bilibili-API-collect`、`CC BY-NC 4.0` 與 netease 兩則。`l` 區是 `libjxl → libpng`，**沒有 `libmpv / FFmpeg`** —— 正確，Android 走 ExoPlayer，整包裡沒有 libmpv |
| Windows | 同一頁：**`libmpv / FFmpeg`（3 個授權）在 `libpng` 上方**，內文是建置旗標說明加上從 asset 載入的 **GNU LESSER GENERAL PUBLIC LICENSE Version 2.1** 全文 |

**驅動 Windows 時踩到的**：`--restore-window` 前三次都截到別的視窗（使用者正在用
這台機器，Windows 的前景鎖擋掉了 raise）。第四次才成功，而中途有一次 `scroll`
整個送到別的視窗去、FMP 完全沒動。**在 Windows 上每一次 click / scroll 之後都要
用截圖確認落在對的視窗**，不能假設指令送到了。

#### 四、順手處理與未處理

- `windows/runner/Runner.rc:96` 原本寫 `Copyright (C) 2026 com.personal. All
  rights reserved.` —— 「All rights reserved」與 MIT 直接矛盾，一併改掉。
  `CompanyName` 維持 `com.personal` 不動，它與 `AppUserModelID` 綁在一起。
- **`NOTICE` 與 `THIRD_PARTY_LICENSES.md` 只做一份**（後者）。兩份重疊的揭露文件
  一定會漂移，而路線圖本來就寫的是「`NOTICE` / `THIRD_PARTY_LICENSES.md`」二選一。
- `licenses/` 同時是 repo 目錄與 Flutter asset（`pubspec.yaml` 的 `- licenses/`），
  所以授權全文只有一份來源；`release.yml` 在打包**之前**把它與 `LICENSE`、
  `THIRD_PARTY_LICENSES.md` 複製進 `build\windows\x64\runner\Release`，可攜版 zip
  與 InnoSetup 安裝檔因此帶到同一批檔案。

#### 五、Phase 6 前置與註釋語言規則

這幾件事單獨看都很小，但都是「Phase 6 搬 124 個檔案之後會變貴」的那一類，
所以排在它前面。

**1. `test/support/riverpod_test_ref.dart` 是死的。** 零 import，唯一指向它的是
`lib/providers/AGENTS.md`。那條規則本身（`Ref` 在 Riverpod 3 是 sealed class，
測試做不出 fake）是對的且非顯而易見，所以**規則留下、指向拿掉**：做法直接寫進
規則裡，不再指向一個沒人呼叫的檔案。

**2. 只合併逐字相同的測試替身。** `test/` 底下同名私有 fake 出現 4 檔以上的有
9 種，本輪只動三種：

| 抽出 | 逐字相同 / 總數 | 去處 |
|---|---:|---|
| `_FakeIsar`（`extends Fake implements Isar {}`，單行） | 11 / 11 | `test/support/fakes/fake_isar.dart` |
| `_FakeSourceAuthContext`（無憑證版） | 11 / 16 | `test/support/fakes/fake_source_auth_context.dart` |
| `_FakeSettingsRepository`（記憶體版） | 5 / 7 | `test/support/fakes/fake_settings_repository.dart` |

25 個檔案、−385 / +144 行。**剩下的變體刻意留在原地**：五個 auth context 各自
記錄呼叫、提供 per-source header 或回答歌單授權；兩個 settings repository 一個是
超集（多一個 `getOverride`）、一個是子集（沒有 `update`）。把它們折進一個可配置的
共用替身，等於拿重複去換一個六個開關、沒人讀得懂的型別 —— 那不是進步。

同理**沒有動** `_FakeSourceManager`（9 檔）與 `_FakeSource`（6 檔）：最小版的
`_FakeSourceManager` 雖然有四份文字相同，但它持有 `_FakeSource`，而六份
`_FakeSource` **沒有任何兩份相同**。抽管理器就被迫先統一音源 fake，範圍立刻失控。
`_FakeHttpClientAdapter`（7 檔）尚未逐檔比對，本輪不賭。

> **踩到的**：機械替換順手清掉「只服務被移除宣告」的 import，但
> `source_auth_context.dart` 同時匯出 `AccountServiceAuthLoader`，
> `audio_auth_retry_phase4_test.dart` 還在用它。`analysis_options.yaml` 排除
> `test/**`，所以 `flutter analyze` 全綠 —— 是 `flutter test` 的編譯階段抓到的。
> **再一次印證：analyze 乾淨不代表測試編得過。**

**3. 三處文檔漂移就地更正**（不覆蓋原值，照 D3/D4 的既有風格標注）：

- **D1 決策列**：三個逾時值**都**沒有照那一列落地。引進它們的 `262657bc` 一開始
  就是 T1=6s / T2=8s / T3=15s，之後只有 T1 改成 25s 並在 §6.2 交代 ——
  **T2 與 T3 的差異從來沒有被記錄過**，這一輪才補上。
- **§9.1 標題**寫「已完成 1/3，剩下 2/3」，但它自己下面的表格三列全是 ✅。
- **「206 個 Dart 依賴」**兩處：現在是 207。

**4. 註釋語言定為繁體**（根 `AGENTS.md` 的 Hard Boundaries）。量到的現況是
`lib/` 底下 331 個手寫檔有 **199 個含簡體註釋**，且大量檔案簡繁並存
（`media_kit_audio_service.dart` 簡 238 / 繁 120，`settings.dart` 151 / 117，
`youtube_source.dart` 110 / 145）—— 原因是舊碼簡體、Phase 0–5 新寫的繁體，而
**沒有任何一份 AGENTS.md 說過該用哪個**。規則是「改到的行才轉，不做全庫轉換」：
全庫轉換會產生一個橫跨 199 檔、把任何真實變更都淹掉的 diff，而混用的代價是
可讀性不是正確性。數字放這裡，規則放 AGENTS.md，不互相重複。

---

### 6.15 測試：固定圈數的 pumpEventQueue（issue #43 / #55）（2026-09-08）

觸發點是 CI 而不是計畫：2026-09-07 一天內 CI 紅了 7 次，**其中 4 次是同一個檔案
的同一種毛病**，包含 `main` 上的一次（run `34120654888`，12:12–12:42 main 是紅的）。
另外兩次是 dependabot PR（go_router 18、package_info_plus 9）—— **那兩次的紅跟
升級毫無關係**，也是同一條抖動。也就是說這條抖動當時正在讓 CI 結果無法解讀。

#### 根因不是某一條測試，是一個形狀

```dart
await pumpEventQueue(times: 10);   // 等 10 圈事件迴圈
expect(toasts, isNotEmpty);        // 立刻斷言
```

`pumpEventQueue` 的實作（`test_api-0.7.13/lib/src/scaffolding/utils.dart:16`）只是
遞迴排零延遲的 `Timer`：

```dart
Future pumpEventQueue({int times = 20}) {
  if (times == 0) return Future.value();
  return Future(() => pumpEventQueue(times: times - 1));
}
```

**圈數換不到「進度」。** 背景 I/O、Isar 交易與真計時器什麼時候完成跟圈數無關。
機器滿載時同樣的圈數換到的進度更少（正向斷言掛掉，#43）；反過來，同樣的圈數耗掉
的牆鐘時間更多，「還沒發生」提早變成「已經發生」（反向斷言掛掉，#55）。
**兩個方向壞在相反的地方 —— 所以把圈數調大不是修，只是把競態換一邊。**

#### 三條要更正的說法

| # | 之前說 | 實況 |
|---|---|---|
| 1 | issue #43 的修法範圍是「同檔案所有 `pumpEventQueue(times: N)` 之後緊接斷言的地方」 | **不夠。** 本輪的基準壓力跑抓到第三條失敗，是 `prepareCurrentTrack prefetch` 那條：它的 pump 之後隔了幾行才斷言，按「緊接斷言」的規則會被判定為安全並留下來 |
| 2 | 只有 `pumpEventQueue(times: N)` 有問題 | 不帶參數的 `pumpEventQueue()` 就是 `times: 20`，同一個病。全庫另有 **27 處**，其中 19 處下一行就是 `expect(` |
| 3 | 「條件式等待」就是把固定圈數換成 `while (!condition)` | **輪詢的方式本身是承重的**，見下 |

#### 輪詢方式是承重的，這是量出來的不是選出來的

套件裡既有的區域 helper 自發收斂出兩種形狀，本輪先照抄了「睡 10ms」那一種，
結果連續踩到兩件事：

- **睡著取樣會整段錯過瞬間狀態，而且睡覺本身會改變被測程式的行為** —— 真計時器
  因此提早到期。`audio_controller_phase1_test` 的 `superseded source error` 那條
  在 10ms 輪詢下**永遠**等不到它要的狀態，而 5 圈 `pumpEventQueue` 等得到。
- **改成一圈一檢查（`pumpEventQueue(times: 1)`）又太細**：等待在更早的時點返回，
  呼叫端的下一步就落在不同的交錯上，同一條測試直接卡死（`resolves` 停在 2，
  狀態永遠不換手）。

最後的形狀是：前 50 輪用完整的 `pumpEventQueue()`（20 圈，**不耗牆鐘時間**），
之後改成睡 10ms。20 圈這個粒度不是挑的，是套件裡既有 helper 一直在用的。

#### 還有一個陷阱：條件在進入時就成立 = 一圈都沒推

`pumpUntil` 一進來就檢查條件，成立就返回。**如果條件在進入時已經成立，它會立刻
返回、一圈都沒推 —— 比它取代掉的固定圈數推進得更少。** 本輪有兩條測試因此變紅：

- `temporary restore replaces the queue copy`：條件寫成 `queueTrack.sourceId ==
  'restore-b'`，但那個 sourceId 從頭到尾都是 `restore-b`；真正會變的是佇列換上的
  **新實例**，所以條件要寫 `!identical(queueTrack, queueTrackBeforeTemporary)`。
- `superseded source error`：條件漏掉了最後才收斂的那一項。

規則因此寫進 `pumpUntil` 的文檔註釋：**條件必須是「進入時還不成立」的東西。**

#### 做了什麼

| 項目 | 數字 |
|---|---|
| `pumpEventQueue` 呼叫點移除 | **194**（167 個 `times: N` + 27 個不帶參數） |
| 換成 `pumpUntil`（條件式等待） | 182 處 |
| 換成 `drainEventQueue`（斷言缺席） | 58 處 |
| 收斂掉的區域 wait helper | 10 份 |
| 收斂掉的 `_CountWaiter` | 3 份 → `test/support/fakes/count_waiters.dart` |
| 動到的檔案 | 33 |

`drainEventQueue` 是刻意留的出口，不是妥協：「某件事不該發生」的斷言等不到任何
條件（條件在第 0 圈就成立）。首選是先用 `pumpUntil` 等一個**排在它之後**的里程碑
再斷言缺席；找不到里程碑時才用它，而 `reason` 讓 `rg drainEventQueue` 一次列出
全部「我們知道自己在斷言缺席」的地方 —— 註解做不到這件事。

順帶修掉一個既有缺陷：`mix_session_coordinator_test` 的區域 `_waitFor` **逾時後
靜靜返回**，不 `fail`。逾時會偽裝成後面那條斷言的失敗。

#### #55：把一條會競態的測試拆成兩條不會競態的

`playback_handoff_gate_test` 用固定 10 圈去斷言「seek 還沒送出」，對上 40ms 的真
計時器。**沒有用 `fakeAsync`** —— `PlaybackHandoffGate` 同時用
`Future.delayed`（`:209`）與 `DateTime.now()`（`:272`），`fakeAsync` 管不到後者，
要先把生產程式碼改成 `clock.now()`；為一條測試改生產程式碼的時鐘來源不成比例。
改成：一條用 30 秒的視窗（長到任何 pump 預算都追不上）驗「視窗內延後」，另一條用
短視窗加 `pumpUntil` 驗「視窗過後送出」。原本一條測試同時守這兩件事，正是它會
抖的原因。

> **第二條的第一版是錯的，而且是壓力跑抓到的。** 短視窗一開始寫成 1ms ——
> 那是同一種競態換了個方向：視窗可能在下一行的 `deferSeek` 被呼叫**之前**就關掉，
> `deferSeek` 回 `null`，`!` 直接炸。改動後的 20 次壓力跑抓到 1 次。改成 500ms：
> 這個數字不是「夠快」而是「夠慢」，需要的只是「視窗在下一行還開著」，500ms 對
> 相鄰兩行語句是四個數量級的餘裕。**這件事本身就是這一輪的論點** —— 任何拿牆鐘
> 時間當同步點的斷言都要問「餘裕有幾個數量級」，而不是「這樣應該夠吧」。

#### 守門

`test/support/wait_convention_static_rule_test.dart` 照
`isar_boundary_static_rule_test.dart` 的既有形狀：掃 `test/` 全部 `.dart`、
`expect(scanned, greaterThan(200))` 防掃空、外加「餵它合成違規要抓得到」與
「註解裡提到 API 不算違規」兩條自我測試。

規則是**完全禁止**呼叫 `pumpEventQueue`，不是只禁「pump 之後緊接斷言」——
上面第 1 條更正就是理由：本輪第三條抖動的斷言隔了幾行，窄規則抓不到。
豁免只有三個檔案：`pump_until.dart`（包裝它的那一層）、它自己的測試（需要原始的
固定圈數當對照），以及守門測試自己（合成樣本存在字串常量裡）。

#### 驗收

| 項目 | 結果 |
|---|---|
| 完整套件 | **1505 passed**（基準 1495；+5 `pump_until_test`、+4 守門測試、+1 #55 拆出來的那條） |
| `flutter analyze` | 乾淨 |
| `dart format lib test` | 577 檔 0 diff |
| 壓力跑（改動前） | **20 次 2 紅** —— 兩次都是 `prepareCurrentTrack prefetch` 那條 |
| 壓力跑（改動後） | **25 次 0 紅** |

壓力跑的方法：把 shell 的 `ProcessorAffinity` 限成 4 核（GitHub public repo runner
的規格），子行程繼承，跑
`audio_controller_phase1_test.dart` + `playback_handoff_gate_test.dart`。
兩組都跑在 `git worktree` 的獨立副本上，同一台機器、同樣負載。

三件據實記錄的事：

1. **改動後的第一輪 20 次有 1 紅，而且是本輪自己種下的** —— 上面 #55 那則引文說的
   1ms 視窗。修掉之後補跑，19 + 6 = **25 次 0 紅**。
2. 那 20 次裡另有 1 次在 **1 秒內**失敗、完全沒有測試輸出 —— 行程根本沒起來（當時
   主工作樹正在跑完整套件，推測是共用快取的競用）。那不是測試失敗，沒有計入
   25 次，也沒有計成紅。
3. 兩組的跑次都不是實驗室等級的控制：跑的期間這台機器上還有別的工作。這個方向
   對「改動後」是不利的，不是有利的。

> **這證明不了「已經沒有抖動」。** 既有基準是 24 次 1 紅，要證到 0 需要 70 次以上。
> 這裡證的是：已知的機制被移除了，而且改動前的失敗在改動後不再出現。

**不需要實機驗證** —— 純測試改動，沒有任何 user-visible 行為變更。

---

### 6.16 分層邊界：招牌規則失效，範圍縮成結構修正（2026-09-08）

Phase 6 原本要把 `lib/services/`（92 檔）與 `lib/providers/`（43 檔）合併成
`lib/features/`。開工當天的重核推翻了它的兩個核心前提，**當天決定縮範圍**。

#### 一、招牌的機械規則已經死了，而且不是命名問題

Phase 6 的賣點是這一條：

```bash
rg -l flutter_riverpod lib/features | rg -v '_providers\.dart$'   # 必須為空
```

量測：兩個目錄底下 import riverpod 的 **47** 個檔案裡，命名符合 `*_providers.dart`
的只有 **2** 個（34 個是單數 `_provider.dart`，11 個兩者皆非）。

但改名解決不了。**Phase 3a / 4 收尾的 `Notifier` 改寫讓業務邏輯類自己就是
`Notifier`** —— `AudioController`（3,400 行，住在 `audio_provider.dart`）、
`RadioController`、`RankingCacheService` 都必須 import riverpod。這條規則預設的是
`StateNotifier` 世界：邏輯類不碰 riverpod，只有裝配檔碰。**那個世界在 Phase 4 收尾
時就沒有了** —— 規則是被本專案自己的前一個 Phase 作廢的。

01 §5.3 的第二條規則「`ui/` 只讀 `features/*_providers.dart`」同樣不成立：`lib/ui`
有 61 檔正當地 import `services/` 的純型別檔（`lyrics_result.dart`、`lrc_parser.dart`
這類）。那不是業務決策外洩。

#### 二、「讓耦合誠實可見」不需要搬檔案

feature 身分就是子目錄名，兩個頂層目錄只是一個映射函式。在**現有佈局上**直接量：

| 佈局 | 跨 feature import |
|---|---|
| 重核當天 | **98 行 / 46 組配對** |
| 本輪之後 | **63 行 / 31 組** |
| 假如做完整搬移 | 48 行 / 19 組 |

98 行裡有 **34 行**指向 `providers/database/` —— 搬那 **4 個檔案**就全部消失。
也就是說，大搬移宣稱的「可見性」收益，四個檔案就兌現了三分之一。

> 順帶更正 §Phase 6 的一個估算：計畫寫「跨 feature 只有 14 行」。那個 14 只數了
> `providers/ → services/` 一個方向，漏掉 `services/ → services/` 與
> `providers/ → providers/`。真值是 98。

#### 三、剩下的價值撐不起 135 檔

大搬移獨有的收益只剩人體工學（一個功能一個目錄）與「讓未來誤放更難發生」。那是真的
收益，但不是可驗證的正確性，而代價（135 檔、~730 行 import、3 個靜態規則測試重寫、
2 份 AGENTS.md 拆散）沒有變。**改做約 10 檔的結構修正輪。**

#### 做了什麼

| 項目 | 數字 |
|---|---|
| `lib/` 相對 import → `package:fmp/` | **1666 行 / 274 檔**（`dart fix`，`always_use_package_imports` 永久開啟） |
| barrel 檔的裸相對 export → `package:` | 30 處 / 7 檔 |
| 檔案搬移 | **9**（7 個是 R100 純重新命名） |
| 全分支 | 313 檔、+2035 / −1799 |

四組歸位：

1. **`providers/database/` → `lib/data/database/`**（4 檔）。它不是 feature：沒有
   對應 UI、沒有 `services/database/`，是 Isar 開啟 + 註冊 + migration 的資料層裝配。
2. **兩個純型別檔往下搬**：`remote_playlist_id_parser.dart` → `lib/data/sources/`、
   `playlist_exceptions.dart` → `lib/data/repositories/`。兩者都只 import `data/`，
   卻被 `data/` 反向 import。搬完 **`lib/data/` 對上層的反向 import 歸零** —— 這是
   下面那條規則能成立的前提。
3. **歌單刷新歸位**：`providers/search/refresh_provider.dart` 裝的是
   `PlaylistRefreshState` / `RefreshManagerNotifier`，消費者全部與搜尋無關；
   `services/refresh/auto_refresh_service.dart` 只被 `app.dart` import，刷的是歌單。
   兩者都進 library，`services/refresh/` 這個單檔目錄消失。
4. **孤兒歸位**：`storage_permission_service.dart` 是唯一直接躺在 `services/` 根目錄
   的檔案，而 Key Paths 一直寫著它屬於 `platform/`。

#### 換上的兩條規則（`test/support/layer_boundary_static_rule_test.dart`）

- **規則 A（會擋東西的那條）**：`lib/core/` 與 `lib/data/` 不得 import
  `lib/services/` 或 `lib/providers/`。`data` 側是 **0 違規**；`core` 側有**一個**
  具名例外（`core/extensions/track_extensions.dart` → `providers/download/
  file_exists_cache.dart`），要修的是依賴方向不是檔案位置，本輪不動但也不讓它變成
  無聲的先例。規則附一條「例外仍然真實」的自我檢查，例外消失時會要求刪掉它。
- **規則 B（快照，不是白名單）**：31 組跨 feature 的邊存成快照，出現新的一組或
  舊的一組消失時都失敗。**刻意不逐筆寫理由** —— 31 筆機械生成的理由會是橡皮圖章，
  而 FMP 的歷史已經證明儀式性規則會腐爛。它要擋的只有一件事：一條新的 feature 對
  feature 的邊悄悄長出來。

#### 三個踩到的

1. **`always_use_package_imports` 不管 `export`。** `dart fix` 轉完 1658 個 import
   之後 `flutter analyze` 全綠，但 30 個裸相對 export 原封不動 —— 其中
   `playlist_service.dart` 的 `export 'playlist_exceptions.dart';` 在下一個 commit
   把該檔搬走時當場斷掉。lint 綠不等於「移動安全」。
2. **`isar_boundary_static_rule_test` 的豁免清單會反過來誤報。** 它硬編
   `lib/providers/database/{database_catalog,database_migration}.dart` 當「可以直接碰
   `isar.` 的兩個檔案」，比對的是掃描到的路徑字串。**檔案搬走而清單沒改，那兩個檔案
   會被判定成違規而讓 CI 紅**，不是靜靜變綠。這是本輪唯一一個「搬檔案本身製造假警報」
   的點。同批修的還有 `ui_consistency_static_rule_test` 的 provider 目錄斷言、
   `database_viewer_page_coverage_test` 的路徑常數、`docs/adr/0002`。
3. **5 條測試斷言在相對 import 字面值上。** `dart fix` 只改 `lib/`，而
   `startup_download_sync_provider_test`、`radio_player_backdrop_test`、
   `database_viewer_page_coverage_test`、`add_to_remote_playlist_dialog_structure_test`
   都在斷言「A 檔 import 了 B 檔」的**字串**。斷言的意圖存活，字面值要跟著改。
   `analysis_options.yaml` 排除 `test/**`，所以這 5 條是 `flutter test` 抓到的，
   不是 analyze —— **再一次印證 analyze 乾淨不代表測試編得過。**

#### 驗收

| 項目 | 結果 |
|---|---|
| 完整套件 | **1510 passed**（基準 1505，+5 是新規則測試自己） |
| `flutter analyze` | 乾淨（每個 commit） |
| `dart format lib test` | 578 檔 0 diff |
| 生成碼 | `dart run build_runner build` + `dart run slang` 之後 `git status` 空 |
| rename 偵測 | 9 個搬移裡 7 個是 R100；`git log --follow` 三個抽樣都穿過搬移接上舊歷史 |
| 規則武裝驗證 | 對三條規則各種一個合成違規：Isar 邊界、規則 A、規則 B 都逐項抓到並回報 file:line 或邊名 |

**不需要實機驗證** —— 純 rename / move 與測試新增，零行為變更、無持久化格式變更、
無對外介面變更。

#### 擱置而非取消

`features/` 大搬移的落點設計已經摸清楚並記在這裡，隨時可以續做：

- **126 檔進 12 個 feature**：account 18 / audio 35 / library 21（吸收 import 與
  歌單刷新）/ lyrics 17 / download 13 / settings 7 / backup 3 / desktop 3
  （`windows_desktop_service` + 它的兩個 provider）/ radio 3 / explore 2 / search 2 /
  update 2。**`search` 與 `explore` 是兩個 feature**：`search_provider.dart` 與
  `popular_provider.dart` 的 import 清單零交集。
- **features 之外**：`media_handoff.dart` 應該進 `lib/data/sources/` 而不是 01 §5.3
  說的 `core/media/` —— 它 import `data/sources/source_http_policy.dart`，放進 `core/`
  就是 `core → data` 的反向依賴。`connectivity_service.dart` 進 `core/network/`
  （`core/` 已經不是零 Riverpod：`toast_service.dart` 就 import 它）。
  `selection_provider.dart` 是純 UI 狀態，只被 4 個 UI 檔用，該進 `lib/ui/`。
- **會打到的測試**：23 個測試檔硬編 `'lib/services/` 或 `'lib/providers`。三個要特別
  處理：`isar_boundary_static_rule_test`（同上第 2 點）、
  `ui_consistency_static_rule_test` 的「providers live under semantic subdirectories」
  （前提整條消失，要重寫或刪除，不是改字面值）、`riverpod3_static_rule_test:71`
  的 `Directory('lib/providers')`（目錄消失會丟例外）。
- 本輪立的兩條規則跟著搬的成本接近零：規則 A 只要把 `services/`、`providers/` 換成
  `features/`，規則 B 的 feature 身分函式少一層映射。

---

### 6.17 發版 v1.10.0：盤點推翻了三條說法（2026-09-08）

上一次發版是 **v1.9.1（2026-07-08）**，之後兩個月做完 Phase 0–7 一次都沒發布。
發版前的盤點推翻了三條我自己先前講過的話。

#### 一、「距上次發布 1134 個 commit」是錯的框法

2026-09-01 的歷史重寫讓 v1.2.0–v1.9.1 全部脫離 `main` 的血緣：
`git merge-base --is-ancestor v1.9.1 main` 為假，共同祖先是 `ddbf0405`
（2026-02-12）。所以 1134 裡混著「2 月到 7 月、已經發布過、只是換了 hash」的工作，
我先前引的 241 feat / 279 fix 同樣受影響。

真正的起點是 `c25d3cce` —— 它與 v1.9.1 的 tip `cdc22b25` **同標題、同 author
date（2026-07-08）**，是重寫後的等價 commit。以它為界：

| 起點 | commits | 字元 |
|---|---|---|
| `v1.1.4..main`（`git describe` 會挑的） | 1134 | 97,785 |
| `v1.9.1..main` | 1134 | 97,785 |
| `ddbf0405..main`（共同祖先） | 1134 | 97,785 |
| **`c25d3cce..main`（真實的「v1.9.1 之後」）** | **237** | **17,821** |

前三個完全一樣，因為那些 tag 都落在共同祖先線上或以下 —— `git log A..main` 的結果
與挑哪個 tag 無關。237 的分佈是 16 feat / 3 perf / 52 fix / 62 refactor /
58 docs / 23 test；樹差異 688 檔、+67,600 / −42,428。

#### 二、「修 previous-tag 計算」修不了那面牆，而且那個偏差會自癒

我先前把它說成「修法很小」。實際上換任何 previous tag 都得到同一個 1134 行 body
（見上表），只留 feat/fix 也還有 532 行、49,688 字元。

而 `git describe` 挑到 v1.1.4 這件事**發完 v1.10.0 就自己好了** —— 下一版會
describe 到 v1.10.0，它在 `main` 上。**所以刻意不修它**：修了不改變 body，也不改變
未來。改的是 `release.yml` 的 body 組裝：`docs/release-notes/<tag>.md` 存在就由它
完全擁有 body，否則沿用自動產生（輸出與改動前逐字相同）。慣例記在
`docs/build-and-release.md` §4。

body 不是裝飾：`update_service.dart:472` 把它當成 `releaseNotes`，
`update_dialog.dart:113` 用 `maxHeight: 200` 的捲動框以**純文字**顯示（不渲染
markdown，`**Full Changelog**` 會照字面出現）。1134 行會進那個 200px 的框。

> 順帶查到一個本來會炸的東西：`_isNewerVersion`（`update_service.dart:689`）是逐段
> `int.tryParse` 的數值比較，所以 `1.10.0 > 1.9.1` 成立。**雙位數 minor 是專案史上
> 第一次**，字串比較的話 App 內更新會永遠看不到新版。

#### 三、遷移排練做不成 —— 這是缺口，不是通過

原計畫是拿真實資料庫的副本跑一次 v1.9.1 → v1.10.0 的遷移。前提失敗了：資料庫在
`Documents/fmp/fmp_database.isar`，目錄 9/4 建立，**已經被新版開過並遷移過**，舊路徑
（`Documents/` 根目錄）也沒有殘留檔。它不能當「v1.9.1 年代的樣本」。

要真的驗得建 v1.9.1 的工具鏈（舊 `isar` + analyzer <6.0.0，正是 Phase 2 換掉的那套）。
**本輪接受這個缺口並記錄**，理由是缺的是接合處而不是任一端：

- `3b1c7244` 已用真實資料庫驗過舊檔能在 `isar_community` 引擎開起來（磁碟格式仍是 v3）
- 28 條遷移測試覆蓋邏輯，含 `Isar.minLong` 那個在真實資料庫上量到的坑
- v1→v2 刻意保留舊欄位，讓降級無損

#### 四、版號取 v1.10.0 而不是 v1.9.2

- 樹差異 688 檔不是 patch 的量級（commit 數因為重寫不可用，見上）。
- 更新檢查是手動觸發的（`settings_about.dart:70` 是唯一呼叫點），版號因此是使用者
  **唯一**的風險訊號。
- 憑證側實質單向：v9 透過 Jetpack Security / EncryptedSharedPreferences 讀，v10 已把
  資料遷出到自訂 cipher，裝回 v1.9.1 很可能要重登三個站台。**這是從 upstream
  changelog 推的，沒有實測降級。** patch 版號會讓人以為可以隨手裝回去。

#### 五、發布後驗收：三條預測有兩條成立，第三條比預測更糟

發布於 2026-09-08 17:02 UTC，`draft: false` 所以直接對外。

| 項目 | 實測結果 |
|---|---|
| Release body | 與 `docs/release-notes/v1.10.0.md` **逐字相同**（各 4,118 字元），手寫檔確實完全擁有 body，沒有被 `## What's Changed` 前綴 |
| compare 連結 | `compare/v1.9.1..v1.10.0`（兩點），沒有退化成三點 |
| 產物 | 10 個 asset：4 個 ABI APK + universal + `fmp-latest-*` 三個別名 + windows zip + installer + checksums |
| Windows 安裝版 | 實裝成功，登錄檔 `DisplayVersion = 1.10.0+1010000` —— CI 依 tag 算出的 `versionCode`（major×1000000 + minor×1000 + patch）如實落到安裝包上 |
| Windows 可攜版 | zip 解壓後 `libisar.dll` 在、沒有殘留的舊名 `isar.dll`。這段改名落在未發布期間，而 zip/installer 打包不在 PR CI 的覆蓋範圍，所以只有這裡驗得到 |
| App 內更新（雙位數 minor） | **實測通過**：v1.9.1 的 Android 建置 → 設定 → 檢查更新 → 抓到 v1.10.0、x86_64、32.3 MB。§二的 `_isNewerVersion` 判讀原本只是讀原始碼推的，現在有實際觀察 |

第三段裡「1134 行會進那個 200px 的框」的預測沒有機會成立（手寫檔擋掉了），但**框本身
的問題比預測更嚴重**：4,118 字元的手寫 markdown 在對話框裡是純文字，`## FMP v1.10.0`
與 `### Playback` 照字面顯示，而 200px 只露得出前 8 行 —— 被蓋掉的內容裡包含這一版
唯一需要事前知道的那句（降級回 v1.9.1 要重登三個來源），而且框沒有任何捲動提示。
記為 issue #82。

> 這一輪在 Windows 端的截圖與點擊上損失了不少時間，兩個坑（`PrintWindow` 回傳凍結
> 畫格、驅動行程沒宣告 DPI awareness 導致座標差 1.5 倍）記在
> `.claude/skills/verify-on-device/SKILL.md` §Driving the Windows build。

