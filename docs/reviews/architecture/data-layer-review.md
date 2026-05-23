# Data layer review

## Findings

1. **High - `cleanupInvalidDownloadPaths()` 重建 `PlaylistDownloadInfo` 時遺失 `playlistName`。**
   理由：`PlaylistDownloadInfo.playlistName` 是 embedded persisted object 的一部分，model 註解明確說它用於下載路徑匹配與歌單重命名同步（`lib/data/models/track.dart:28`）。同一個 model 的 helper 在設定或清除下載路徑時都會保留 `playlistName`（`lib/data/models/track.dart:132`、`lib/data/models/track.dart:139`、`lib/data/models/track.dart:196`、`lib/data/models/track.dart:208`），但 `TrackRepository.cleanupInvalidDownloadPaths()` 重建物件時只寫回 `playlistId` 與 `downloadPath`（`lib/data/repositories/track_repository.dart:541`、`lib/data/repositories/track_repository.dart:549`、`lib/data/repositories/track_repository.dart:554`）。這和 model 對 embedded object 的 repository contract 不一致。
   風險：任何被 invalid-path cleanup 掃到的 track，都可能在保留歌單關聯的同時靜默丟失 playlist-name metadata。之後 `getDownloadPath()` / `isDownloadedForPlaylist()` 的 name-first matching 會變弱（`lib/data/models/track.dart:103`、`lib/data/models/track.dart:178`），歌單重命名或下載路徑 reconciliation 也會更依賴 fallback playlist id。
   建議方向：不要大改 repository 形狀，只要在 `cleanupInvalidDownloadPaths()` 的每個 `PlaylistDownloadInfo` 重建分支都複製 `info.playlistName`。補一個聚焦 repository regression test：建立含 `playlistName` 的 `playlistInfo`，讓 cleanup 清掉不存在的路徑，確認名稱仍存在。

2. **Medium - database viewer 遺漏 schema-visible/persisted 欄位。**
   理由：`Settings.allowPlainLyricsAutoMatch` 是 persisted field（`lib/data/models/settings.dart:184`），也存在於 generated schema（`lib/data/models/settings.g.dart:20`），但 settings viewer 的 lyrics 區塊列出相鄰 lyrics 欄位時沒有它（`lib/ui/pages/settings/database_viewer_page.dart:600`）。`PlayQueue.isNotEmpty` 是 schema-visible getter（`lib/data/models/play_queue.dart:67`），generated schema 也包含它（`lib/data/models/play_queue.g.dart:50`），但 viewer 只顯示 `length` 和 `isEmpty`，沒有顯示 `isNotEmpty`（`lib/ui/pages/settings/database_viewer_page.dart:383`）。
   風險：`lib/ui/AGENTS.md` 要求 persisted field、embedded object 或 schema registration 變更時同步維護 database viewer（`lib/ui/AGENTS.md:87`）。目前遺漏會降低開發者排查資料狀態時的可見性。
   建議方向：把 `allowPlainLyricsAutoMatch` 加到 settings lyrics 區塊，把 `isNotEmpty` 加到 PlayQueue basic/debug 區塊。這兩個修補都不需要改 persistence semantics；`allowPlainLyricsAutoMatch = false` 已符合 Isar bool upgrade default，因此不需要 migration repair（`lib/data/AGENTS.md:87`）。

3. **Medium - `database_viewer_page_coverage_test.dart` 的欄位覆蓋名稱比實際檢查更強。**
   理由：測試名稱寫的是 database viewer exposes current model fields and debug getters（`test/ui/pages/settings/database_viewer_page_coverage_test.dart:109`），但實作是手寫 token 清單（`test/ui/pages/settings/database_viewer_page_coverage_test.dart:113`）。這份清單能抓到部分歷史重點欄位，但沒有從 generated schema 或 model declaration 推導欄位。上面提到的 `allowPlainLyricsAutoMatch` 與 `isNotEmpty` 都能漏過，就是因為它們不在 expected tokens 裡。
   風險：指令要求 schema 或 persisted field 變更時更新 viewer（`lib/providers/AGENTS.md:42`、`lib/ui/AGENTS.md:89`），但自動化 guard 只有 collection registration 是完整推導（`test/ui/pages/settings/database_viewer_page_coverage_test.dart:56`），欄位檢查仍是選擇性清單，未來 schema drift 仍可能不破測試。
   建議方向：保留目前簡單測試風格，但增加小型 generated-schema token extraction，對每個 registered schema 比對 viewer keys；對 `playlistInfo (...)` 這類動態 label 用小型 allowlist，而不是維護寬鬆的手寫 token 清單。

## Evidence

指令/文檔語料分類：

- 規範性 agent instructions：root `AGENTS.md` 要求 model/schema/migration 變更時同步更新 `lib/data/AGENTS.md`、`lib/providers/AGENTS.md`，若 database viewer 改變也更新 `lib/ui/AGENTS.md`（`AGENTS.md:40`），並列出 Isar model 的驗證命令（`AGENTS.md:79`）。`lib/data/AGENTS.md` 定義 migration/default-repair 規則與 Isar upgrade defaults（`lib/data/AGENTS.md:39`、`lib/data/AGENTS.md:62`）。`lib/providers/AGENTS.md` 把 database startup/migration 指向 `database_provider.dart`（`lib/providers/AGENTS.md:32`）。`lib/ui/AGENTS.md` 要求 database viewer 對 collection、field、embedded object、schema registration 保持完整（`lib/ui/AGENTS.md:87`）。
- 人類開發文檔：`docs/development.md` 摘要 registered collections 位於 `database_provider.dart`、field 變更需檢查 migration/default repair 與 viewer、DB 檔案應透過 `openFmpDatabase()` 開在 documents 下的 `FMP/` 子目錄（`docs/development.md:68`、`docs/development.md:70`、`docs/development.md:160`）。這些內容和規範性指令一致，但我把它當作摘要，不當作獨立真相來源。
- 目前補充記憶：`.serena/memories/refactoring_lessons.md` 與 `.serena/memories/ui_coding_patterns.md` 強化 Isar watch/provider 模式（`.serena/memories/refactoring_lessons.md:24`、`.serena/memories/ui_coding_patterns.md:226`）；`.serena/memories/download_system.md` 強化下載進度應先留在 memory，完成/暫停/失敗時再落 DB（`.serena/memories/download_system.md:40`）。這些是補充語料，沒有覆蓋當前程式碼證據。

程式碼證據：

- Schema registration 對已記錄的 persisted collections 是集中且完整的：`fmpDatabaseSchemas` 包含 `Track`、`Playlist`、`PlayQueue`、`Settings`、`SearchHistory`、`DownloadTask`、`PlayHistory`、`RadioStation`、`LyricsMatch`、`LyricsTitleParseCache`、`Account`（`lib/providers/database_provider.dart:27`）。`openFmpDatabase()` 用同一份清單開啟 `resolveFmpDatabaseDirectory()` 指向的 DB（`lib/providers/database_provider.dart:288`、`lib/providers/database_provider.dart:294`），`databaseProvider` 開啟後會跑 `_migrateDatabase()`（`lib/providers/database_provider.dart:307`、`lib/providers/database_provider.dart:312`）。
- Startup/default repair 覆蓋目前文件列出的非 Isar defaults：settings 透過 `createBootstrapSettings()` 建立（`lib/providers/database_provider.dart:43`），invalid/empty settings 有修補（`lib/providers/database_provider.dart:85`、`lib/providers/database_provider.dart:138`、`lib/providers/database_provider.dart:156`），Netease auth priority 以 empty priority 判定修補（`lib/providers/database_provider.dart:173`），`LyricsTitleParseCache` 啟動時會清空（`lib/providers/database_provider.dart:186`），legacy queue volume 只在 legacy signature 下修補（`lib/providers/database_provider.dart:61`、`lib/providers/database_provider.dart:196`）。對應測試涵蓋這些路徑（`test/providers/database_migration_test.dart:42`、`test/providers/database_migration_test.dart:60`、`test/providers/database_migration_test.dart:154`、`test/providers/database_migration_test.dart:225`、`test/providers/database_migration_test.dart:264`）。
- Database path 行為和文檔一致：path resolution 會回傳 `FMP` 子目錄，legacy root-level Isar files 會移動，且不覆蓋已存在的新位置 DB（`lib/providers/database_provider.dart:223`、`lib/providers/database_provider.dart:255`、`test/providers/database_path_test.dart:9`、`test/providers/database_path_test.dart:20`、`test/providers/database_path_test.dart:60`）。
- Viewer collection coverage 與 schema registration 對齊：`_collections` 列出所有 registered collections（`lib/ui/pages/settings/database_viewer_page.dart:32`），`_buildCollectionData()` switch 覆蓋所有 collection（`lib/ui/pages/settings/database_viewer_page.dart:121`），coverage test 會從 `database_provider.dart` 推導 registered collection names（`test/ui/pages/settings/database_viewer_page_coverage_test.dart:43`、`test/ui/pages/settings/database_viewer_page_coverage_test.dart:68`）。

目前不建議改的地方：

- 不建議替 `allowPlainLyricsAutoMatch` 增加 migration repair；它的 business default 是 `false`，Isar bool upgrade default 也是 `false`，`lib/data/AGENTS.md` 已明確標註不需 repair（`lib/data/AGENTS.md:87`）。
- 不建議大幅重寫 `database_provider.dart`；open path、schema list、migration entry point、testing helper 都符合 repo 指令（`lib/providers/database_provider.dart:27`、`lib/providers/database_provider.dart:215`、`lib/providers/database_provider.dart:219`、`lib/providers/database_provider.dart:288`）。
- 不建議為了 embedded-object 問題新增抽象層或做 repository 大重構；問題侷限在 `TrackRepository.cleanupInvalidDownloadPaths()` 的單一重建區塊（`lib/data/repositories/track_repository.dart:541`）。
- 不應把歸檔歷史當成現行規範；`docs/README.md` 說歷史重構流水只作背景（`docs/README.md:13`），目前核心規則應在 `AGENTS.md` 或現行 memories（`docs/README.md:17`、`docs/README.md:19`、`docs/README.md:20`）。

## Risk

- 最高實務風險是 `Track.playlistInfo` metadata loss：cleanup 會修改 persisted data，且和 model helper 保留 `playlistName` 的 contract 衝突。
- 中等風險是 observability drift：viewer 和 coverage test 看起來覆蓋 database surface，但 schema-visible 欄位仍可漏掉。
- 較低風險是 `LyricsTitleParseCache` 文檔語意略模糊：它是 registered Isar collection，但 startup migration 每次都清空（`lib/providers/database_provider.dart:186`）。`docs/development.md` 稱它為 runtime AI title parse cache（`docs/development.md:83`），但 `lib/data/AGENTS.md` 只寫 AI-parsed title cache（`lib/data/AGENTS.md:29`）。

## Suggested direction

1. 在 `TrackRepository.cleanupInvalidDownloadPaths()` 重建 `PlaylistDownloadInfo` 時，一律複製 `info.playlistName`，包含有效路徑保留分支與清空路徑分支。
2. 增加一個聚焦 regression test，驗證 invalid download path cleanup 不會清掉 `playlistName`。
3. 在 `DatabaseViewerPage` 顯示 `allowPlainLyricsAutoMatch` 與 `isNotEmpty`，並擴充 `database_viewer_page_coverage_test.dart` 的 expected tokens。
4. 讓 viewer coverage 從 generated schema 或 model declaration 推導欄位，再用小型 allowlist 處理刻意動態的 labels。

## Instruction docs accuracy notes

- `AGENTS.md`、`lib/data/AGENTS.md`、`lib/providers/AGENTS.md`、`lib/ui/AGENTS.md` 對 Isar migration、schema registration、database path、viewer maintenance 的規則彼此一致（`AGENTS.md:40`、`lib/data/AGENTS.md:52`、`lib/providers/AGENTS.md:32`、`lib/ui/AGENTS.md:87`）。
- `docs/development.md` 對目前 registered collection list 與 database path rules 的摘要準確（`docs/development.md:68`、`docs/development.md:70`）。
- `lib/data/AGENTS.md` 可考慮補一句：`LyricsTitleParseCache` 雖是 Isar collection，但目前設計上是 runtime/ephemeral cache，因為 startup migration 會清空它（`lib/data/AGENTS.md:29`、`lib/providers/database_provider.dart:186`、`docs/development.md:83`）。
- `.serena/memories/ui_coding_patterns.md` 有些 UI 規則和 `lib/ui/AGENTS.md` 重疊，但資料層相關的 provider/watch 指引和 scoped instructions 一致（`.serena/memories/ui_coding_patterns.md:226`、`lib/providers/AGENTS.md:5`）。
