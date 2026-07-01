# 01 — 重構與修復計劃（Action Plan）

> 本檔將 [`docs/review/`]() 的審查發現轉為可執行 roadmap。每個工作項交叉引用原 finding id（如 `D8`、`B1`），可回溯證據。優先序與風險分級已採納「對抗驗證」結果（A1 撤回、F1 Isar 主張更正、多筆 High→Medium）。
>
> 閱讀順序：[00-overview](00-overview.md) → **01-action-plan（本檔）** → [02–07 各面向證據]()。

## 0. 指導原則

1. **守住硬性邊界**（同時是不可逾越的紅線）：不推翻 `SourceManager`/Capability 核心抽象；UI 播放控制走 `AudioController`；不用 `Image.network/file`；不走 ad-hoc 路徑開/遷移 Isar（只 `openFmpDatabase()`）；不加隱藏全域搜尋音源過濾；帳號憑證不送 CDN byte 請求。
2. **先測後重構**：涉及 UI / schema / header policy 的重構（D2、D3、C1、C2）**之前**先補對應行為測試（F5、F3），避免回歸無捕捉。
3. **每階段保持可發布**：階段 exit 須通過 `flutter analyze` + `flutter test` + 雙平台 build smoke（`.github/workflows/ci.yml`）。
4. **不破壞既有資料**：動到 Isar schema/Settings 預設須走 `_migrateDatabase()` default repair 並 bump 對應測試；backup shape 改動須 bump `kBackupVersion` 並保持舊備份可讀。
5. **文件同步**：程式碼改動伴隨更新最近 `AGENTS.md`／`docs/`（依 root AGENTS.md 的 Documentation Maintenance 對照表）。
6. **證據導向、不湊數**：每項附 `file:line` 與可驗收條件；做完標記狀態。

## 1. 階段總覽

| Phase | 主題 | 工作項 | 風險 | 預估 | 可並行 |
|-------|------|--------|------|------|--------|
| **P0** | 速勝（文件飄移 + 現存可見 bug） | E3, E1, E2, D8 | 低 | S×4 | 是 |
| **P1** | 隱性 bug + 字串鍵統一（D 漸進式重構核心） | D1, D4, D7, D9, D13 | 低–中 | M×5 | 部分 |
| **P2** | 一致性主線（Dio / 例外 / 日誌） | B1, B2, B4 | 低–中 | M+L+M | 是 |
| **P3** | 資源治理（mem/disk 單調上升） | A3, A5, A4, A2 | 中 | M×3+L | 部分 |
| **P4** | 可維護性（過長方法 / 死碼） | C2, C3, C1 | 中 | M+M+L | 部分 |
| **P5** | 擴充性 UI 自動化（**選做，視新音源需求**） | D5, D6, D2 | 中–高 | L×3 | 否（須配套 widget 測試） |
| **P6** | 測試與成熟度 | F5, F3, F2, F4, F6 | 低–中 | M×5 | 是（建議**最先做 F5/F3** 解鎖 P1/P4/P5） |
| **追蹤** | 依賴衛生 | F1 | — | L（持續） | — |

> **關鍵排序邏輯**：P6 的 `F5`（安全邊界行為測試）應在 `P1/D3`（SourceHttpPolicy 改動）之前；`F3`（integration 測試）應在 `P4`/`P5` 重構之前。因此建議**先做 P0 + P6(F5/F3/F2)，再進 P1–P5**。

## 2. 各階段細節

### Phase 0 — 速勝（本周，低風險，純文件/一行修）

| ID | 動作 | 檔案 | 驗收 | 驗證 |
|----|------|------|------|------|
| **E3** | **delete** `.serena/memories/update_system.md`（或 rewrite 三個路徑 + robocopy/backup/rollback/canRequestPackageInstalls 描述並標註權威來源為 `lib/services/AGENTS.md`） | `.serena/memories/update_system.md` | memory 不再含錯路徑／xcopy 描述；或檔案不存在 | `rg "xcopy\|providers/update_provider\.dart" .serena` 無命中 |
| **E1** | **rewrite** `pubspec.yaml:2` description 補 Netease | `pubspec.yaml` | 與 `README.md:8`/`AGENTS.md:27-29` 三音源一致 | 人工比對 |
| **E2** | **rewrite** `docs/development.md:69` collection 註冊位置改指 `database_catalog.dart` | `docs/development.md` | 與 `lib/data/AGENTS.md:57-59` 對齊 | 人工比對 |
| **D8** | **fix** `play_history_page.dart:666-672` 改用 `getImportSourceIcon(history.sourceType)` | `lib/ui/pages/history/play_history_page.dart` | netease 歌曲顯示正確圖示（非 YouTube） | `flutter test test/ui` + `flutter analyze` |

> P0 完成後建議單獨一個 commit/PR，清掉一份誤導文件 + 一個現存可見 bug + 兩處文件飄移。

### Phase 1 — 隱性 bug + 字串鍵統一（D 漸進式重構核心）

目標：以 `SourceManager.registeredSourceTypes` 為單一真相，消除「編譯器抓不到、漏改會靜默失效」的字串／具名欄位 hardcode。**不動 exhaustive switch**（留給編譯器保護）、**不動 schema**。

| ID | 動作 | 檔案 | 依賴 | 驗收 |
|----|------|------|------|------|
| **D1** | `SourceCapability`（或新 `Disposable` 介面）暴露 `dispose()`；`SourceManager.dispose()` 改 `for (s in _sources) (s as Disposable?)?.dispose()` | `lib/data/sources/source_provider.dart:184-191`、`source_capabilities.dart` | — | `rg "is BilibiliSource\|is YouTubeSource\|is NeteaseSource" lib/data/sources` 無命中 |
| **D4** | `homeRankingSourceIds` 改由 `registeredSourceTypes.map(.name)` 衍生；normalize 對未知 id 記 warning 而非靜默丟棄（或補測試守護白名單） | `lib/data/models/settings.dart:72-108` | — | 含新 id 的設定不被丟棄；`test/providers` 補一條白名單同步測試 |
| **D7** | `loadVideoPagesForTrack` 與 `search_page` 分P守護改 `sourceManager.pagedVideoSource(track.sourceType) != null`；錯誤訊息用 `track.sourceType.name` | `lib/services/search/search_service.dart:146-159`、`lib/ui/pages/search/search_page.dart:837-839` | — | 新音源實作 `PagedVideoSource` 即自動可載入分P |
| **D9** | `SearchState.allDirectSources` 改由 `sourceManagerProvider.registeredSourceTypes` 衍生（或移除常數） | `lib/providers/search/search_provider.dart:35-39` | — | All 模式 local 過濾口徑與 `searchService` 一致 |
| **D13** | 下載副檔名改從 `AudioStreamResult.container` 推導；頭像 platform 子目錄改用 `sourceType.name`；掃描器 `.m4a` 過濾放寬 | `lib/services/download/download_path_utils.dart:38-45,216-233`、`lib/providers/download/download_scanner.dart:178-339` | — | 新音源容器非 m4a 時檔名副檔名正確；頭像不誤歸 youtube 目錄 |

> P1 風險低（不改 schema、不改 auth 邊界），但 D13 觸及下載檔名隱性契約——**建議先補 F5 行為測試 + download scenario 測試再改**。驗證：`flutter test test/services/download test/providers/download` + `flutter test test/data/sources`。

### Phase 2 — 一致性主線

| ID | 動作 | 檔案 | 依賴 | 驗收 |
|----|------|------|------|------|
| **B1** | 歌詞/匯入 Dio 改走 `SourceHttpPolicy.createApiDio`/`HttpClientFactory.create`，刪裸 `new Dio()`；可加 lint 禁止 `lib/` 內 `Dio(BaseOptions())` | `lib/services/lyrics/{netease,qqmusic,lrclib}_source.dart`、`lib/data/sources/playlist_import/{spotify,qq_music}_playlist_source.dart` | — | `rg "Dio\(BaseOptions\|dio \?\? Dio\(\)" lib` 命中歸零；timeout 與全域 10s/30s 一致 |
| **B2** | 歌詞源 exception 改 `extends SourceApiException` 並實作 `sourceType`/`kind`；`_handleDioError` 改呼叫 `classifyDioError`；移除分類器內 `logError` 副作用 | `lib/services/lyrics/{lrclib,qqmusic,netease}_source.dart`、`lyrics_auto_match_service.dart` | 建議與 B1 同 PR（同碰歌詞源） | 歌詞錯誤可用 `isRetryable`/`shouldSkipTrack` 語義決策；`rg "implements Exception" lib/services/lyrics` 無命中 |
| **B4** | 上述服務 `mixin Logging` 並把 `debugPrint` 換成 `logXxx`；加 lint 禁止 `lib/services` 內 `debugPrint`（`logger.dart` 除外） | `windows_desktop_service.dart`、`ranking_cache_service.dart`、`lyrics_window_service.dart` | — | `rg "debugPrint\(" lib/services` 僅命中 logger.dart |

> 驗證：`flutter test test/services test/data/sources` + `flutter analyze`。

### Phase 3 — 資源治理（防 mem/disk 單調上升）

| ID | 動作 | 檔案 | 依賴 | 驗收 |
|----|------|------|------|------|
| **A3** | `LyricsTitleParseCache.save()` 或啟動加 LRU/上限（保留最近 N 筆或近 X 天）；設定頁可加「清理歌詞解析快取」入口 | `lib/data/repositories/lyrics_title_parse_cache_repository.dart:19-45`、`lib/services/lyrics/lyrics_auto_match_service.dart` | — | 播放 2000 首後 collection 不超過上限；`_migrateDatabase()` 啟動清理仍運作 |
| **A5** | `_cleanupActiveTask`/`_finalizeTaskCleanup` 在不恢復續傳時刪 `task.tempFilePath`；`downloadServiceProvider.initialize()` 增孤立 `.part` 掃描清理 | `lib/services/download/download_service.dart:990-1036,766-780` | **建議與 C2、C3 同檔同 PR**（download_service 集中改動） | 模擬取消/崩潰後重啟，下載目錄無 `.part` 殘留 |
| **A4** | 歷史頁篩選/排序下推到 `queryHistory`（已有參數）；snapshot 改分頁增量 | `lib/data/repositories/play_history_repository.dart:253-267`、`lib/providers/library/play_history_provider.dart:9-18,81-102` | — | 歷史頁開啟時記憶體不再出現多份 1000 筆副本（DevTools snapshot） |
| **A2** | 首頁預覽改用精簡 summary provider（只 id/name/cover/trackCount） | `lib/providers/library/playlist_provider.dart:85-90,200-205` | — | 首頁不持有完整 trackId 清單 |

> 驗證：`flutter test test/services/download test/providers/download`（A5）、`test/providers`（A2/A4）。

### Phase 4 — 可維護性

| ID | 動作 | 檔案 | 依賴 | 驗收 |
|----|------|------|------|------|
| **C2** | `_startDownload` 拆 `resolve-stream`/`run-isolate`/`finalize` 三私有方法 + `_abortFinalizationCleanup(task)` 單行化（267 行→~80 行編排） | `lib/services/download/download_service.dart:695-961,870-928` | **與 A5、C3 同 PR**；先補 download integration 測試（F3） | `_startDownload` ≤ ~80 行；5 處重複清理收斂為 helper |
| **C3** | 移除 dead CancelToken 路徑（`_activeCancelTokens`、`debugRegisterLegacyActiveDownloadForTesting`、`getActiveTaskIds` 併入、dispose 相容迴圈）；連帶調整 phase1 測試改用既有 Isolate 測試 hook | `lib/services/download/download_service.dart:77,241-245,619-650,1008,1040,1426-1430` | C2（同檔） | `rg "_activeCancelTokens\|debugRegisterLegacyActiveDownloadForTesting"` 命中歸零；phase1 測試仍綠 |
| **C1** | 巨型 State 拆 private widget / helper（**優先 `lyrics_window`**：拆 `OffsetController`/`DisplayModeController`/`LyricsTextMeasurer`） | `lib/ui/windows/lyrics_window.dart:181-1430` | 先補 widget/golden 測試（F3） | 拆出後主 State 行數減半；偏移邏輯可獨立測試 |
| **C8** | 下載檔名提升為 const（`kCoverFileName` 等），下載端/掃描端/`track_extensions`/`playlist_service`/`track_detail_provider` 改引用 | 多檔（見 04-simplicity.md C8） | 可與 D13 同 PR（同碰下載檔名） | `rg "cover.jpg\|avatar.jpg\|metadata.json" lib` 僅命中常數定義處 |
| **C6** | radio 重試錯誤分類改型別：media_kit 定義 `StreamOpenFailedException`，`radio_controller` 改 `catch (StreamOpenFailedException)` | `lib/services/audio/media_kit_audio_service.dart:905-907`、`lib/services/radio/radio_controller.dart:534-538` | — | 重試不再依賴訊息子字串 |

> 驗證：`flutter test test/services/audio test/services/radio test/services/download` + `flutter analyze`。

### Phase 5 — 擴充性 UI 自動化（**選做**，僅當確定要新增第 4 個音源）

> 依 [05-architecture.md](05-architecture.md) 重構結論，這是「方案 2/3」的 UI 自動化部分。**若短期無新音源計畫，可略過本階段**——exhaustive switch 已提供編譯保護，UI 列舉屬 DRY 負擔而非靜默風險。

| ID | 動作 | 檔案 | 依賴 | 驗收 |
|----|------|------|------|------|
| **D5** | `explore_page`/`popular_provider`/`ranking_cache_service` 改遍歷 `registeredSourceTypes`（搭配 `Provider.family<SourceType>` 取 `tracksFor(type)`） | `lib/ui/pages/explore/explore_page.dart:38,63-120`、`lib/providers/search/popular_provider.dart:244-294`、`lib/services/cache/ranking_cache_service.dart:488-510` | widget 測試（F3） | 新源註冊即自動長出排行榜 tab |
| **D6** | 搜尋 chip 改遍歷 `registeredSourceTypes`；直播 `liveSource` 改遍歷找 `LiveSource`（或標註 Bilibili-only 刻意決策並寫進 AGENTS.md） | `lib/ui/pages/search/search_page.dart:184-231`、`lib/providers/search/search_provider.dart:746-747` | — | 新源自動出現在搜尋 chip |
| **D2** | per-source Settings/State 改資料驅動（`Map<SourceType,String>` 或由 `registeredSourceTypes` 衍生）；**先補 `neteaseStreamPriority` 進 `AudioSettingsState`** 修既有破窗 | `lib/data/models/settings.dart:185-191,269-275,586-608`、`lib/data/sources/base_source.dart:44-56`、`lib/providers/audio/audio_settings_provider.dart:14-15` | schema migration + `test/providers/database_migration_test.dart` | 新音源只需加 enum+中繼資料+adapter；`neteaseStreamPriority` 在 state/UI 可調 |

> ⚠️ D2 觸及 Isar schema — 須 bump migration test、評估 `kBackupVersion` 是否受影響、走 `build_runner --delete-conflicting-outputs`。

### Phase 6 — 測試與成熟度（**建議最先做 F5/F3/F2 解鎖其他階段**）

| ID | 動作 | 檔案 | 依賴 | 驗收 |
|----|------|------|------|------|
| **F5** | 補 `SourceHttpPolicy.mediaHeaders`/`MediaHandoff._prepareHeaders` **真實行為測試**（給定 netease CDN URL 斷言輸出無 Cookie/Authorization） | 新測試檔 under `test/data/sources`、`test/services/media` | — | 重構字串寫法不會繞過斷言 |
| **F3** | 新增 integration：fake 後端串流失敗→驗證 `PlaybackRecoveryCoordinator` 重試與換源；download→isolate→complete→DB 端到端 scenario；評估關鍵頁面 golden | `test/integration/`、`test/scenarios/` | — | 播放恢復與下載整鏈有自動化演練 |
| **F2** | CI 改 `flutter test --coverage` 並上傳；對 `audio_provider`/`download_service`/`youtube_source` 設最低覆蓋閘門 | `.github/workflows/ci.yml:55-56` | — | PR 可見 diff 覆蓋率；大檔有閘門 |
| **F4** | 備份還原改兩階段寬容解析（`DateTime.tryParse`、欄位缺失給預設/跳過、收集錯誤清單）+ transaction 包裹 | `lib/services/backup/backup_data.dart:57,200-215`、`backup_service.dart` | — | 匯入損壞 JSON 不留部分寫入；UI 回報具體失敗欄位 |
| **F6** | 更新資產 checksum 缺失即視為不可用；下載完成安裝前**必須** sha256 通過才放行 | `lib/services/update/update_service.dart:106,143-149,463-486` | — | 移除 manifest 某條 sha256 → 該 asset 更新不可用 |

### 持續追蹤 — F1（Isar 依賴衛生）

- **正確定性**：v3 是上游官方建議的生產版本（非 archived）；v4 尚不適合生產、無 v3→v4 遷移工具。**現階段不遷移**。
- **動作**：在 `AGENTS.md` 補註記「Isar 鎖定 v3 為刻意選擇，符合上游建議；追蹤 v4 stable 與遷移工具進度」；每次 release 前確認目標平台（Android NDK / arm64 Win）native libs 可用；長期可評估 drift/sqflite/objectbox 為備案。
- 驗收：文件明確記載；release checklist 含 native libs 可用性確認。

## 3. 工作項登錄表（Registry）

| ID | 標題 | 嚴重度 | 工作量 | 階段 | 依賴 | 主要檔案 |
|----|------|--------|--------|------|------|----------|
| E3 | 刪/改過時 `.serena/memories/update_system.md` | 🔴 High | S | P0 | — | `.serena/memories/update_system.md` |
| D8 | `play_history_page` netease 圖示 bug | 🟡 Med | S | P0 | — | `lib/ui/pages/history/play_history_page.dart` |
| E1 | `pubspec.yaml` description 補 Netease | 🟡 Med | S | P0 | — | `pubspec.yaml` |
| E2 | `docs/development.md` collection 註冊位置 | 🟡 Med | S | P0 | — | `docs/development.md` |
| D1 | `SourceManager.dispose` 改 Disposable | 🟡 Med | M | P1 | — | `source_provider.dart`、`source_capabilities.dart` |
| D4 | `homeRankingSourceIds` 衍生 + warning | 🟡 Med | M | P1 | — | `settings.dart` |
| D7 | 分P守護改能力判斷 | 🟡 Med | S | P1 | — | `search_service.dart`、`search_page.dart` |
| D9 | `allDirectSources` 衍生 | 🟢 Low | S | P1 | — | `search_provider.dart` |
| D13 | 下載副檔名/頭像目錄資料驅動 | 🟡 Med | S | P1 | F5 | `download_path_utils.dart`、`download_scanner.dart` |
| B1 | 歌詞/匯入 Dio 統一 policy | 🟡 Med | M | P2 | — | lyrics/*_source.dart、playlist_import/* |
| B2 | 歌詞 exception 繼承 SourceApiException | 🟡 Med | L | P2 | B1(同 PR) | lyrics/*_source.dart |
| B4 | 日誌收斂 Logging mixin | 🟡 Med | M | P2 | — | windows_desktop/ranking_cache/lyrics_window service |
| A3 | LyricsTitleParseCache LRU/上限 | 🟡 Med | L | P3 | — | lyrics_title_parse_cache_repository.dart |
| A5 | `.part` 暫存清理 + 啟動孤兒掃描 | 🟡 Med | M | P3 | C2/C3(同 PR) | download_service.dart |
| A4 | 歷史頁查詢下推 | 🟡 Med | M | P3 | — | play_history_repository/provider |
| A2 | 歌單精簡 summary provider | 🟡 Med | M | P3 | — | playlist_provider.dart |
| C2 | `_startDownload` 拆三階段 | 🟡 Med | M | P4 | F3、A5、C3 | download_service.dart |
| C3 | 移除 dead CancelToken 路徑 | 🟡 Med | M | P4 | C2 | download_service.dart + phase1 測試 |
| C1 | 巨型 State 拆分（lyrics_window 優先） | 🟡 Med | L | P4 | F3 | lyrics_window.dart |
| C8 | 下載檔名 const 收斂 | 🟡 Med | S | P4 | D13(可同 PR) | 多檔 |
| C6 | radio 重試改型別判斷 | 🟡 Med | S | P4 | — | media_kit_audio_service.dart、radio_controller.dart |
| D5 | explore/ranking UI 資料驅動 | 🟢 Low | L | P5* | F3 | explore_page.dart、popular_provider.dart、ranking_cache_service.dart |
| D6 | 搜尋 chip 資料驅動 | 🟡 Med | M | P5* | — | search_page.dart、search_provider.dart |
| D2 | per-source 設定資料驅動 | 🟡 Med | L | P5* | migration test | settings.dart、base_source.dart、audio_settings_provider.dart |
| F5 | 安全邊界行為測試 | 🟡 Med | M | P6(最先) | — | 新測試 |
| F3 | integration/golden 測試 | 🟡 Med | M | P6(最先) | — | 新測試 |
| F2 | CI coverage | 🟡 Med | M | P6 | — | ci.yml |
| F4 | 備份還原寬容解析 | 🟡 Med | S | P6 | — | backup_data.dart、backup_service.dart |
| F6 | checksum 缺失即拒絕 | 🟡 Med | S | P6 | — | update_service.dart |
| F1 | Isar 依賴衛生（追蹤） | 🟡 Med | L | 持續 | — | AGENTS.md、release checklist |

`P5*` = 選做，視新音源需求決定。

## 4. 依賴與排序重點

- **測試優先鏈**：`F5` → `D3`/`D13`（SourceHttpPolicy/下載檔名改動）；`F3` → `C1`/`C2`/`D5`/`D2`（重構）。建議把 F5/F3/F2 放在最前面。
- **同檔集中改動（合併 PR 降低衝突）**：
  - `download_service.dart`：`A5` + `C2` + `C3` 同一 PR。
  - 下載檔名：`D13` + `C8` 同一 PR。
  - 歌詞源：`B1` + `B2` 同一 PR。
- **schema 邊界**：`D2` 觸及 Isar schema → 須 `build_runner --delete-conflicting-outputs` + `database_migration_test.dart` + 評估 `kBackupVersion`。其餘 P1–P4 項目**不改 schema**。
- **不可並行**：P5 三項（D5/D6/D2）需配套 widget/migration 測試，建議循序而非並行。

## 5. 不要做什麼（Non-Goals / 紅線）

- ❌ 不推翻 `SourceManager`/Capability 核心抽象（D 重構只收斂外圍 hardcode）。
- ❌ 不為了「乾淨」把 exhaustive switch 改成字串派發（會失去編譯期保護）。
- ❌ 不在 UI 直接消費具體 source provider；不繞過 `AudioController`；不用 `Image.network/file`；不走 ad-hoc Isar。
- ❌ 不在 P1–P4 順帶改 schema/auth 邊界（留給獨立、有 migration 測試的 PR）。
- ❌ 不為了湊時程跳過階段 exit 閘門（analyze + test + 雙平台 build smoke）。
- ❌ 不遷移 Isar 4（v4 非生產可用、無遷移工具；v3 為上游建議）。

## 6. 階段驗收閘門（Exit Criteria）

每階段結束須全綠：

```bash
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64   # build smoke
flutter build windows --release                                 # build smoke (Windows 環境)
git diff --check                                                 # 文件/格式無尾空白
```

涉及生成碼/i18n 時追加：

```bash
flutter pub run build_runner build --delete-conflicting-outputs
dart run slang
```

涉及 schema/migration 時追加：

```bash
flutter test test/providers/database_migration_test.dart test/ui/pages/settings/database_viewer_page_coverage_test.dart
```

## 7. 風險登錄

| 風險 | 機率 | 影響 | 緩解 |
|------|------|------|------|
| D13/C8 改下載檔名導致舊掃描結果失效 | 中 | 中（已下載檔案可能需重掃） | 保持向後相容掃描（`.m4a` 與新副檔名並認）；提供一次性重掃 |
| D2 schema 變更破壞舊 backup 還原 | 低 | 高 | bump `kBackupVersion` + 寬容匯入（F4）+ migration test |
| C2 重構下載主流程引入回歸 | 中 | 高 | 先做 F3 download scenario；小步拆分、每步測試 |
| F5 行為測試誤判（誤擋合法標頭） | 低 | 中 | 測試針對 allowlist host 斷言「含」、非 allowlist 斷言「不含」 |
| 多人並行改 `download_service.dart` 衝突 | 中 | 低 | A5+C2+C3 強制同 PR；約定凍結期 |

## 8. 估計總覽（粗估）

| 階段 | S | M | L | 約當人日 |
|------|---|---|---|----------|
| P0 | 4 | — | — | ~1–2 日 |
| P6（F5/F3/F2 先做） | — | 3 | — | ~3–5 日 |
| P1 | 2 | 3 | — | ~4–6 日 |
| P2 | — | 2 | 1 | ~4–6 日 |
| P3 | — | 3 | 1 | ~5–7 日 |
| P4 | 2 | 3 | 1 | ~6–8 日 |
| P5*（選做） | — | 1 | 2 | ~5–8 日 |
| **合計（不含 P5）** | **8** | **14** | **3** | **~25–35 日** |

> 為約 4–6 週的漸進改善路線（不含選做的 P5 擴充性 UI 自動化）。P0 一周內可見效；核心阻礙（隱性 bug、一致性、資源治理）在 2–4 週內清除。

---

### 狀態追蹤（建議填寫欄位）

每個工作項建議在執行時補：`狀態`（待開工/進行中/已完成/已驗證）、`負責人`、`PR #`、`實際人時`。可將本檔轉為 GitHub Issue/Project board，每個 ID 一張 issue、標籤對應 Phase。
