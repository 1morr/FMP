# Documentation Alignment Review

## Findings

### 1. `.serena/memories/ui_coding_patterns.md` is too broad and now conflicts with scoped UI rules

理由：根指令要求 `.serena/memories/` 只保留 narrow supplemental notes，核心規則應合併到相應 `AGENTS.md` 後刪除重複記憶（`AGENTS.md:45`-`AGENTS.md:47`，`docs/README.md:19`）。但 `.serena/memories/ui_coding_patterns.md` 長達多個章節，重複 AppBar、圖片載入、track action、provider reload、UI 常量等現行規則，例如 AppBar 規則在 `.serena/memories/ui_coding_patterns.md:53`、`.serena/memories/ui_coding_patterns.md:691` 重複了 `lib/ui/AGENTS.md:56`-`lib/ui/AGENTS.md:61`。更重要的是，它在 `.serena/memories/ui_coding_patterns.md:698` 說新代碼禁止所有 UI hard-coded values，但目前 scoped rule 只要求重複或 design-system 值優先用 `ui_constants.dart`，並明確允許 one-off local layout/animation literals（`lib/ui/AGENTS.md:71`-`lib/ui/AGENTS.md:82`）。

風險：agent 若把 memory 當作等同於 scoped `AGENTS.md` 的硬規範，會把合法的局部尺寸與動畫常數改成大規模樣式 churn。這和現有代碼也不一致，例如 `lib/ui/pages/queue/queue_page.dart:127` 的本地 `smallMoveDuration`、`lib/ui/widgets/vip_badge.dart:13` 的局部圓角、`lib/ui/windows/lyrics_window.dart:542` 的局部動畫時長，都符合 scoped rule 的「one-off」例外，但會被 memory 判成違規。

建議方向：不要把整份 UI memory 搬回 `lib/ui/AGENTS.md`。保留 `lib/ui/AGENTS.md` 作為權威規則，只把 `.serena/memories/ui_coding_patterns.md` 修剪成真正補充性的頁面模式索引；刪除或改寫 `.serena/memories/ui_coding_patterns.md:692`、`.serena/memories/ui_coding_patterns.md:698` 這類比 scoped rule 更嚴格的語句，改成連回 `lib/ui/AGENTS.md:69`-`lib/ui/AGENTS.md:85`。

### 2. `docs/development.md` contains a dead or stale root `AGENTS.md` anchor

理由：`docs/development.md:60` 指向 `../AGENTS.md#file-structure-highlights`，但根 `AGENTS.md` 現有標題是 `## Architecture Map`（`AGENTS.md:105`）和 `## Key Paths`（`AGENTS.md:161`），沒有 `File Structure Highlights`。同一句還說 provider rules 在該 anchor 中，但根 `AGENTS.md` 只把 provider 細節委派到 `lib/providers/AGENTS.md`（`AGENTS.md:129`），實際 provider/migration 規則在 `lib/providers/AGENTS.md:5` 和 `lib/providers/AGENTS.md:32`。

風險：新貢獻者或 agent 會點到不存在的段落，然後錯過 scoped provider 規則。這不是架構錯誤，但會降低 onboarding 與修改資料庫/provider 相關代碼時的可導航性。

建議方向：更新該行時不要複製 provider 規則到 `docs/development.md`。應改成兩個明確連結：文件結構連到 `AGENTS.md#key-paths`，provider 規則連到 `../lib/providers/AGENTS.md`。這符合 `docs/README.md:18` 不重複維護每條 agent rule 的要求。

### 3. `docs/development.md` route summary omits current settings subroutes

理由：`docs/development.md:123` 說重要 route constants 在 `lib/ui/router.dart`，但 `docs/development.md:129` 的設定路由摘要只列出 `/settings/audio`、`/settings/lyrics-source`、`/settings/download-manager`、`/settings/account`、`/settings/developer`。現行 router 還有 `/settings/user-guide`（`lib/ui/router.dart:51`）、`/settings/account/bilibili-login`（`lib/ui/router.dart:56`）、`/settings/account/youtube-login`（`lib/ui/router.dart:57`）和 `/settings/account/netease-login`（`lib/ui/router.dart:58`），並且實際註冊在 `lib/ui/router.dart:220`、`lib/ui/router.dart:251`、`lib/ui/router.dart:256`、`lib/ui/router.dart:261`。

風險：這會讓人誤以為 account login 是非路由化流程，或漏掉 user guide route。風險低於代碼行為錯誤，因為 `lib/ui/router.dart` 仍是明確 source of truth，但 onboarding 文檔的架構地圖不完整。

建議方向：若 `docs/development.md` 想維持摘要，將表格標成「常用/主路由」並明確說完整清單以 `lib/ui/router.dart` 為準；若保留「重要路由」語氣，則補上 user guide 與三個 login 子路由。

### 4. `.serena/memories/code_style.md` is partly style, partly duplicated architecture rules

理由：`.serena/memories/code_style.md:3` 自稱只保留 coding style details，架構、文件結構、資料模型、命令等權威資訊請看根 `AGENTS.md`。但 `.serena/memories/code_style.md:29`-`.serena/memories/code_style.md:34` 又列出音訊邊界、Riverpod 分工、Isar migration 與 build-time provider mutation 等規則；其中音訊邊界已由 `AGENTS.md:99`、`AGENTS.md:109`-`AGENTS.md:113` 規範，migration 規則已由 `lib/data/AGENTS.md:35`-`lib/data/AGENTS.md:67` 和 `lib/providers/AGENTS.md:32`-`lib/providers/AGENTS.md:49` 規範。

風險：目前內容大多不是錯的，但它建立了第二份規則入口。未來若 `AGENTS.md` 或 scoped `AGENTS.md` 更新，這個 memory 很容易落後，造成 agent 在「style memory」和權威指令之間取錯優先級。

建議方向：不要把這些規則再搬回根 `AGENTS.md`，因為權威位置已存在。應把 `.serena/memories/code_style.md` 修剪到命名、import order、語言/style 這類真正 coding style 補充；架構邊界改成一行連結到 `AGENTS.md` 和相關 scoped `AGENTS.md`。

## Evidence

### 項目指令與文檔語料

- 根指令：`AGENTS.md:7`-`AGENTS.md:23` 定義根與 scoped `AGENTS.md` 的讀取順序，`AGENTS.md:31`-`AGENTS.md:58` 定義文檔維護與 history/memory 邊界。
- Scoped 指令：`AGENTS.md:15`-`AGENTS.md:20` 明確列出 `lib/services/AGENTS.md`、`lib/services/audio/AGENTS.md`、`lib/data/AGENTS.md`、`lib/data/sources/AGENTS.md`、`lib/providers/AGENTS.md`、`lib/ui/AGENTS.md`。
- 人類文檔地圖：`docs/README.md:9`-`docs/README.md:13` 指向 `docs/development.md`、`docs/build-guide.md`、`docs/build-and-release.md`、`docs/debugging-with-vm-service.md`、`docs/history/refactoring-log.md`。
- 權威來源與拆分規則：`docs/README.md:17`-`docs/README.md:20` 把 `AGENTS.md`、`docs/development.md`、`.serena/memories/`、`docs/history/` 的責任分開；`docs/README.md:24`-`docs/README.md:28` 定義各類變更該更新哪份文檔。
- `.serena/memories/` 目前存在 `update_system.md`、`download_system.md`、`refactoring_lessons.md`、`ui_coding_patterns.md`、`code_style.md`。沒有發現 `docs/agents/` 目錄。
- `docs/history/refactoring-log.md:3` 已明確標為歸檔，並說不是當前實作規範。

### 代碼抽查結果

- 音訊邊界與平台 split 基本準確：根文檔要求 UI 走 `AudioController` 而不是 `FmpAudioService`（`AGENTS.md:99`、`AGENTS.md:109`-`AGENTS.md:113`）；現行 provider 在 `lib/services/audio/audio_provider.dart:2970`-`lib/services/audio/audio_provider.dart:2975` 選擇 `JustAudioService` 或 `MediaKitAudioService`，`audioControllerProvider` 在 `lib/services/audio/audio_provider.dart:3017` 建立。
- 資料模型清單基本準確：`docs/development.md:72`-`docs/development.md:84` 列出的 collection 與 `lib/providers/database_provider.dart:28`-`lib/providers/database_provider.dart:38` 註冊的 schema 相符；各 model 也有 `@collection`，例如 `lib/data/models/track.dart:50`、`lib/data/models/settings.dart:73`、`lib/data/models/account.dart:11`。
- DB 開啟/遷移描述準確：`docs/development.md:70`、`lib/data/AGENTS.md:55`-`lib/data/AGENTS.md:60`、`lib/providers/AGENTS.md:35`-`lib/providers/AGENTS.md:40` 和代碼中的 `resolveFmpDatabaseDirectory()` / `openFmpDatabase()`（`lib/providers/database_provider.dart:250`-`lib/providers/database_provider.dart:294`）一致。
- 來源例外抽象描述準確：`docs/development.md:105` 和 `lib/data/sources/AGENTS.md:84`-`lib/data/sources/AGENTS.md:99` 說三個來源例外繼承 `SourceApiException`；代碼在 `lib/data/sources/source_exception.dart:33`、`lib/data/sources/bilibili_exception.dart:5`、`lib/data/sources/youtube_exception.dart:5`、`lib/data/sources/netease_exception.dart:5` 符合。
- Build/release 文檔與 workflow 大致一致：`docs/build-and-release.md:197`-`docs/build-and-release.md:215` 描述多 ABI Android、Windows ZIP/installer 和 release job；`.github/workflows/build.yml:4`-`.github/workflows/build.yml:7`、`.github/workflows/build.yml:151`-`.github/workflows/build.yml:193`、`.github/workflows/build.yml:265`-`.github/workflows/build.yml:278` 支持該描述。

## Risk

最高風險是指令入口分裂，而不是架構本身不一致。`AGENTS.md` 和 scoped `AGENTS.md` 的權威邊界目前清楚；問題在於 `.serena/memories/ui_coding_patterns.md`、`.serena/memories/code_style.md` 把已經進入 scoped instructions 的規則再複製一份，且 UI constants 規則已出現實質語義差異。這會讓後續 agent 做不必要的格式或 UI churn。

次要風險是 onboarding 文檔導航錯誤。`docs/development.md:60` 的 dead anchor 會直接降低可用性；route table 漏項則可能讓人低估 settings/account/login flows 的路由化程度。

`docs/history/refactoring-log.md` 的風險目前可控，因為 `docs/history/refactoring-log.md:3`、`AGENTS.md:56`-`AGENTS.md:58`、`docs/README.md:20` 都清楚說它是歷史資料，不是當前規範。不建議把 history 裡的大量舊教訓合併回 `AGENTS.md`，除非某條已被驗證仍是當前核心規則且尚未存在於 scoped `AGENTS.md`。

## Suggested direction

1. 優先修剪 `.serena/memories/ui_coding_patterns.md`，把它降回補充索引。保留頁面對照、特殊互動案例等真正窄補充；刪除與 `lib/ui/AGENTS.md` 重複或衝突的硬規範。
2. 修正 `docs/development.md:60` 的 dead anchor，分別連到 `AGENTS.md#key-paths` 與 `../lib/providers/AGENTS.md`。不要在 `docs/development.md` 內展開 provider rules。
3. 更新 `docs/development.md:121`-`docs/development.md:130` 的路由表，使其名稱符合實際意圖：若是摘要，明講完整清單以 `lib/ui/router.dart` 為準；若是重要路由清單，補上 `/settings/user-guide` 和三個 account login 子路由。
4. 修剪 `.serena/memories/code_style.md` 的架構規則重複。命名與 import order 可以留在 memory；音訊邊界、Isar migration、provider side-effect 等改成連到 `AGENTS.md`、`lib/data/AGENTS.md`、`lib/providers/AGENTS.md`。
5. 不建議搬動或合併的內容：`docs/history/refactoring-log.md` 應保持歸檔；`docs/development.md` 不應吸收完整 agent 規則；`docs/build-guide.md` 和 `docs/build-and-release.md` 目前有清楚讀者和維護責任，不需要併入 `AGENTS.md`；`update_system.md`、`download_system.md` 可保留作補充，但應避免複製已在 `lib/services/AGENTS.md` 的硬規範。

## Instruction docs accuracy notes

- `CLAUDE.md:3` 只匯入 `AGENTS.md`，符合 `AGENTS.md:22`-`AGENTS.md:23` 的避免重複策略。
- `docs/README.md:17` 把 `AGENTS.md` 定為 agent 權威規則，和根/ scoped `AGENTS.md` 的實際拆分一致。
- `docs/development.md:3`、`docs/development.md:157` 都說自身只摘要，詳細規則看 `AGENTS.md`；這個定位正確，不建議把所有 scoped rules 複製進 development 文檔。
- `lib/services/audio/AGENTS.md:36`-`lib/services/audio/AGENTS.md:50` 的 audio internals ownership 和代碼中的 `AudioController`、`PlaybackRequestExecutor`、`AudioStreamManager`、`QueueManager` 命名一致；本次未發現應更新的 audio 架構描述。
- `lib/data/AGENTS.md:15`-`lib/data/AGENTS.md:33` 與 `docs/development.md:62`-`docs/development.md:94` 的 persisted collection / DTO 分類一致；本次不建議搬動。
- `lib/services/AGENTS.md:30`-`lib/services/AGENTS.md:69` 與 `docs/development.md:107`-`docs/development.md:119` 的 lyrics 概覽一致；development 保持摘要即可。
- `docs/history/refactoring-log.md:3` 已正確標為歷史；應繼續只作追溯背景，不作 current implementation guidance。
