# 項目指令與文檔語料

本文件是本次總體架構與代碼一致性審查的語料索引。它不取代
`AGENTS.md` 或人類文檔，只記錄審查時使用的來源、信任等級與需用代碼驗證
的描述性假說。

## 發現的指令與文檔

### Agent / project instructions

- `AGENTS.md`: 根 agent 規則。明確要求先讀根文件再讀 scoped
  `AGENTS.md`（`AGENTS.md:7`, `AGENTS.md:10`），並列出各子系統 scoped
  文件（`AGENTS.md:15`, `AGENTS.md:16`, `AGENTS.md:17`,
  `AGENTS.md:18`, `AGENTS.md:19`, `AGENTS.md:20`）。
- `CLAUDE.md`: 只導入根 `AGENTS.md`（`CLAUDE.md:3`），不另作規則來源。
- `lib/services/AGENTS.md`: downloads、lyrics、account、import、radio、
  sub-window、thumbnail 行為規則。
- `lib/services/audio/AGENTS.md`: AudioController、FmpAudioService、
  QueueManager、stream handoff、retry、Mix mode 等音頻規則。
- `lib/data/AGENTS.md`: Isar model、repository、migration/default repair、
  database path 規則。
- `lib/data/sources/AGENTS.md`: source adapter、stream resolution、
  `SourceHttpPolicy`、source exception 語義規則。
- `lib/providers/AGENTS.md`: Riverpod provider pattern、invalidation、
  database startup/migration 規則。
- `lib/ui/AGENTS.md`: image loading、track actions、refresh invalidation、
  AppBar、ListTile、UI constants、database viewer、breakpoints 規則。

### Human-facing docs

- `docs/README.md`: 文檔地圖。它把 `AGENTS.md` 定義為 AI agent 權威規則
  （`docs/README.md:17`），把 `docs/development.md` 定義為 onboarding 摘要
  （`docs/README.md:18`），並標記 history 只作背景（`docs/README.md:20`）。
- `docs/development.md`: 人類貢獻者 onboarding。它明確說更細的 agent 規則在
  `AGENTS.md`（`docs/development.md:3`），其架構圖與資料模型清單屬描述性
  摘要，需用代碼驗證。
- `docs/build-guide.md`, `docs/build-and-release.md`,
  `docs/debugging-with-vm-service.md`: 由 `docs/README.md` 指向的核心文檔，
  分別覆蓋本地構建、CI/release、VM Service/Marionette 調試。
- `README.md`: 明確引用文檔地圖、構建指南、開發文檔
  （`README.md:121`, `README.md:122`, `README.md:123`）。功能介紹和 release
  下載資訊屬產品描述，不作架構規範。
- `docs/history/refactoring-log.md`: 由 `docs/README.md:13` 標記為歸檔，
  只能作背景，不作當前實作規範。

### Agent docs / memories

- `docs/agents/`: 本次發現不存在。
- `.serena/memories/update_system.md`: 更新系統補充描述。
- `.serena/memories/ui_coding_patterns.md`: UI/provider/image/loading patterns。
- `.serena/memories/refactoring_lessons.md`: 當前重構坑點索引；文件自身說它
  只保留仍會影響當前開發的坑點，且當前代碼和測試優先
  （`.serena/memories/refactoring_lessons.md:3`,
  `.serena/memories/refactoring_lessons.md:6`）。
- `.serena/memories/download_system.md`: 下載系統補充說明；文件自身說核心規則
  已合併到 `AGENTS.md`，此文件只記錄詳細實現和邊界情況
  （`.serena/memories/download_system.md:3`）。
- `.serena/memories/code_style.md`: 代碼風格與架構邊界摘要。

## 規範性要求

以下內容代表期望設計，審查時用來判定是否偏離：

- UI 播放控制必須調用 `AudioController`，不得繞過到 `FmpAudioService`
  （`AGENTS.md:99`, `AGENTS.md:109`, `lib/services/audio/AGENTS.md:28`）。
- Isar database 必須透過 `openFmpDatabase()` / `database_provider.dart` 路徑打開，
  不得走 ad-hoc path（`AGENTS.md:100`, `lib/data/AGENTS.md:58`,
  `lib/data/AGENTS.md:59`, `lib/providers/AGENTS.md:35`）。
- 不得在 Settings 加 hidden global enabled-source filter；search source selection
  屬 search page chips（`AGENTS.md:101`, `lib/providers/AGENTS.md:27`）。
- UI 不得直接用 `Image.network()` / `Image.file()`；應使用 `TrackThumbnail`、
  `TrackCover` 或 `ImageLoadingService`，且尺寸資訊要傳入 image loader
  （`AGENTS.md:102`, `lib/ui/AGENTS.md:10`, `lib/ui/AGENTS.md:11`）。
- playlist/detail/cover/download 聯動刷新應走
  `libraryInvalidationCoordinatorProvider`，UI 不應猜 provider family
  （`lib/providers/AGENTS.md:17`, `lib/providers/AGENTS.md:18`,
  `lib/providers/AGENTS.md:19`）。
- common track actions 必須用 `buildCommonTrackActionMenuItems()` /
  `buildTrackActionPopupMenuEntries()` 並交給 `TrackActionCoordinator`
  （`lib/ui/AGENTS.md:43`, `lib/ui/AGENTS.md:44`, `lib/ui/AGENTS.md:45`）。
- 修改 Isar model/schema/default 時，要同步 migration/default repair、generated
  output、database viewer 與指定測試（`AGENTS.md:79`, `lib/data/AGENTS.md:37`,
  `lib/data/AGENTS.md:52`, `lib/data/AGENTS.md:64`,
  `lib/providers/AGENTS.md:42`, `lib/ui/AGENTS.md:89`）。
- source exception 語義應統一走 `SourceApiException`；`AudioController` 統一處理
  source failures（`lib/data/sources/AGENTS.md:85`,
  `lib/data/sources/AGENTS.md:87`, `lib/data/sources/AGENTS.md:93`）。
- source API/media headers 應集中在 `SourceHttpPolicy`，download/audio 使用
  source-aware media headers，不依賴 `DownloadService` Dio defaults
  （`lib/data/sources/AGENTS.md:155`, `lib/data/sources/AGENTS.md:166`,
  `lib/services/AGENTS.md:18`, `lib/services/AGENTS.md:21`）。
- `AudioController` owns playback request、PlayerState、temporary play、retry、
  source-error UI decisions；`QueueManager` owns queue order/shuffle/loop/navigation
  （`lib/services/audio/AGENTS.md:38`, `lib/services/audio/AGENTS.md:47`）。
- playback retry 必須 generation/current-track aware，stale handoff 不得清掉新的
  retry state（`lib/services/audio/AGENTS.md:116`,
  `lib/services/audio/AGENTS.md:118`）。

## 描述性內容，需要代碼驗證

以下內容不是自動正確事實；本次報告只在代碼或測試可支持時採信：

- 根 `AGENTS.md` 的 provider 清單（`AGENTS.md:119` 到 `AGENTS.md:127`）。
- `docs/development.md` 的 UI -> Provider/Controller -> Service -> Data/Source
  分層描述（`docs/development.md:36` 到 `docs/development.md:43`）。
- `docs/development.md` 的 persisted Isar collection 表
  （`docs/development.md:68` 到 `docs/development.md:84`）。
- `lib/data/AGENTS.md` 的 current default-repaired fields 清單
  （`lib/data/AGENTS.md:69` 到 `lib/data/AGENTS.md:87`）。
- `lib/data/sources/AGENTS.md` 對各 source stream/auth/header fallback 的描述。
- `.serena/memories/*` 內的補充細節。這些文件可作坑點索引，但若與
  `AGENTS.md` 或當前代碼相衝突，優先相信 scoped `AGENTS.md` 和代碼。

## 初步代碼抽查事實

- `rg -n "Image\\.(network|file)\\(" lib\\ui lib\\core lib\\services` 只命中
  `lib/ui/AGENTS.md:10`，未在 UI 應用代碼中發現直接 `Image.network()` /
  `Image.file()`。
- `rg -n "audioServiceProvider|FmpAudioService|JustAudioService|MediaKitAudioService"
  lib\\ui lib\\providers lib\\services` 排除 `lib/services/audio`、`lib/services/radio`
  和 AGENTS 後沒有命中，初步支持 UI 未直接注入 audio backend；radio 是明確例外
  （`lib/services/AGENTS.md:99`, `lib/services/AGENTS.md:100`）。
- database schema registration 在 `lib/providers/database_provider.dart:28` 到
  `lib/providers/database_provider.dart:38`，database viewer 有對應 collection
  list 與各 collection view 類（`lib/ui/pages/settings/database_viewer_page.dart:32`,
  `lib/ui/pages/settings/database_viewer_page.dart:143`,
  `lib/ui/pages/settings/database_viewer_page.dart:1053`）。
- `SourceHttpPolicy` 是 source/media header 的集中點
  （`lib/data/sources/source_http_policy.dart:6`,
  `lib/data/sources/source_http_policy.dart:33`,
  `lib/data/sources/source_http_policy.dart:66`），download 和 audio 皆有調用
  （`lib/services/download/download_media_headers.dart:8`,
  `lib/services/audio/audio_stream_manager.dart:185`）。

## 不作當前規範的來源

- `docs/history/refactoring-log.md`：只作追溯背景。
- `README.md` 的功能/下載/截圖描述：可用於理解產品面，但不是架構邊界。
- `.serena/memories/`：只作窄補充或坑點索引；當內容成為核心規則時，根據
  `AGENTS.md:45` 到 `AGENTS.md:47` 應合併回 scoped `AGENTS.md` 並刪除重複記憶。
