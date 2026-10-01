# M2 執行計畫

「design §n」指本任務的 `design.md`；「決定 n」指 `prd.md` 的擁有者決定。

## 通用規則（每個 PR 子任務）

- **開工**：
  - 從最新的 `main` 開分支；
  - 以 `task.py create "<標題>" --slug <slug> --parent .trellis/tasks/10-01-m2-full-playback --package app` 建子任務；
  - prd 只寫做什麼與驗收（ADR 0026 §決定 1），在已核准的範圍內直接做，遇到未定的事才問。
- **合併條件**：
  - `app/` 可編譯、`flutter test` 全綠；
  - CI 彙總 job `CI Result` 通過；
  - PR 描述附 review 指南。
- **實機驗證**：
  - 使用者看得到的 PR 在 Android 模擬器與 Windows 都照 `verify-on-device` skill 驗，回報寫明平台與模式（ADR 0027）。
  - 預設重播（dev flavor＋測試插件 `fmp-test`）。
  - 改動本身是插件、網路層，或要看真實封面、真實 CDN 時才用真實連線（B 站），只做最少的操作。
- **改播放後端**（`lib/playback/backends/`）：照 `app/AGENTS.md:18` 在 Windows 與 Android 模擬器各跑一次 `integration_test/audio_backend_contract_test.dart`。
- **動到外殼或提示**：照 `app/AGENTS.md:19` 跑 `toast_layering_test.dart`。
- **改 schema**：照 `.trellis/spec/app/data/index.md` § 改 schema 做完整流程（快照、`stepByStep`、三種 migration 測試），design §3.5 的版本號以合併順序為準。
- **收尾**：
  - 子任務 `finish` 與 `archive --no-commit --skip-branch-validation`；
  - 手動 commit；
  - repo 慣例以 merge commit 合併。
- **文件**：
  - 每個 PR 更新 `app/AGENTS.md` 中自己那一層：只寫查不到的契約與有閘門的規則，每條寫出它的閘門；
  - 需要時更新 `.trellis/spec/app/<layer>/`；
  - design §11 列的 ADR 更正在對應的 PR 加。
- **套件版本**：
  - 以 design 開頭與 `research/m2-scope-digest.md` §3 為起點，加依賴時到 pub.dev 核對一次；
  - 裝當前 stable（`audio_service_mpris` 的 beta 不用，Linux 不在 M2）。
- **lint**：新的匯入規則與擁有者表的改動，照 `.trellis/spec/app/lints/index.md` 寫雙向變異案例，並在 `tool/lint_sentinel.dart` 加違規行。
- **子代理模型**：
  - 實作用 sonnet：PR 0、5、6，以及里程碑驗收的文件更新。都是照既有模式的機械性工作。
  - 實作用 opus：其餘全部（播放核心、網路、快取、資料、平台、介面）。
  - `trellis-check` 一律 opus；研究代理一律 sonnet。

## 進度與交接（compact 後從這裡接）

- **狀態**：2026-10-01 擁有者核准（`prd.md` 決定 8，design §12 八條全部照設計）。
- **擁有者決定**：1–8 在 `prd.md`。
- **已合併進 `main`**：（無）
- **PR 0 完成**（#195）：規劃檔、ADR 一行更正、`milestones.md` 範圍調整。
- **PR 1 完成**（子任務 archive 到 `.trellis/tasks/archive/2026-10/10-01-playback-session-split/`）：`PlaybackSession`、`routePlaybackEvent`（純函數）從控制器拆出；`fmp_layer_imports` 的 `restrictedImports`；後端契約加「回報在呼叫回來之後才送達」；哨兵以 `_expectedMessages` 斷言新表有接上。
- **PR 1 已合併**：#196（`08449b17`）。
- **PR 2 進行中**（2026-10-01；分支 `feat/app-network-status`，子任務 `.trellis/tasks/10-01-network-status`，未 commit）：
  - 實作代理（opus）第一輪完成：`lib/platform/connectivity/`、`lib/core/network/network_status.dart`、`lib/app/app_lifecycle.dart`、`lib/ui/offline/`、共用 `lib/ui/empty_state/`；`connectivity_plus ^7.3.1`；`flutter test` 949 通過。
  - 範圍外的建置修正：`connectivity_plus` 原生碼的非 ASCII 字元在繁中 Windows（cp950）觸發 C4819，`/utf-8` 從 `windows/runner/CMakeLists.txt` 移到 `windows/CMakeLists.txt` 的 `APPLY_STANDARD_SETTINGS`。
  - 擁有者決定 9（`prd.md`）之後，同一個代理正在改：`noInterface` 時使用者的搜尋照送、任何回應就回 `online`；ADR 0016 §決定 7 一行更正；design §5.2／§5.4、`app/AGENTS.md` 同步；補建 Windows prod release（只建置）。
  - 代理回來後：主對話實機驗證（Android 模擬器飛航模式開關、背景切換後回前景；Windows 停用再啟用網路卡；看頂端提示、搜尋頁離線畫面、log tag `network-status` 的 `Network status changed`；模式：重播）→ 派 opus `trellis-check` → 還原只有換行差異的產生檔（`connectivity_plus` 的 Windows／macOS registrant 是真的新增，保留）→ 分開 commit → archive → PR。
  - `unreachable` 在實機難重現（`fmp-test` 不發 HTTP 請求），只有 widget 測試；PR 描述要寫明。
- **下一步**：PR 2 合併後 PR 3（媒體 client）；2–6 與 7、9、11 可並行。
- **本機環境備忘**（2026-10-01）：
  - 模擬器是 `Medium_Phone`，序號 `emulator-5556`（不是 5554）；`ax_flatten.py` 要加 `--device emulator-5556`，`adb` 指令加 `-s emulator-5556`。上面裝著 dev 與測試插件（`files/test.js`），介面語言是 English。
  - Windows 的 dev 產物在 PR 1 驗證後已重建；跑過整合測試要再 `flutter build windows --flavor dev --debug`，Android 要重裝 dev 並以 `run-as` 放回測試插件（skill 的 android.md）。
  - F6 焦點的實機讀法：`msaa_tree.ps1` 加上 `accState` 的 `STATE_SYSTEM_FOCUSED`（0x4）；做法記在 M1 的 `research/m1-acceptance.md` § F6。
- **每個 PR 的固定流程**：
  1. 從最新 `main` 開分支（Conventional Commits 的英文分支名，例如 `feat/app-queue-model`）；
  2. `task.py create … --parent .trellis/tasks/10-01-m2-full-playback --package app --no-start`；
  3. 寫 prd（繁中，列做什麼與驗收）與 `implement.jsonl`／`check.jsonl`，把 design 的相關節與 `.trellis/spec/app/<layer>/index.md` 列進去；
  4. `task.py start`；
  5. 依上面的模型分配派 `trellis-implement`。驗證清單固定為：
     - `dart format --output=none --set-exit-if-changed .`
     - `build_runner` 後沒有實質變動
     - `dart run slang`（動到翻譯時）
     - `dart analyze --fatal-infos`、`flutter analyze`、`flutter test`
     - `dart run tool/lint_sentinel.dart`（動到 lint 時）
     - 需要時建置（`flutter build apk --flavor dev --debug`、`flutter build windows --flavor dev`）
  6. 使用者看得到的改動，由主對話照 `verify-on-device` skill 實機驗證：Android 與 Windows，回報含平台與模式；
  7. 派 opus `trellis-check`，要它試著攻破安全相關的部分（媒體 client、遮蔽、快取目錄、manifest、插件 API）；
  8. 把後續待辦寫進本檔的「留下的後續」；
  9. `git checkout --` 還原只有換行差異的產生檔（`generated_plugin*`、`*.g.dart`、`GeneratedPluginRegistrant.swift`）。
     - **逐檔**以 `git diff --ignore-all-space --ignore-cr-at-eol` 確認是空的才還原；
     - 加了原生插件的 PR（4、13、16a、16b、2）有真正新增的註冊，整批還原會弄丟（M1 PR 10 踩過）；
  10. 分開 commit（subject ≤ 72 字元，Conventional Commits）；
  11. `task.py finish`，再 `archive <slug> --no-commit --skip-branch-validation`，把 archive commit 掉；
  12. push，`gh pr create`（繁中描述＋review 指南）；
  13. 背景跑 `gh pr checks --watch`；
  14. 全綠後 `gh pr merge --merge`，main 快轉。
- **fmp-plugins 的 PR**（PR 8）：
  - 在同層的 `fmp-plugins/` clone 開分支；
  - 改完以 FMP 的 `FMP_PLUGIN_DIR=<絕對路徑>/bilibili flutter test test/plugins/contract/contract_test.dart` 重播驗證（PowerShell 寫法見 `app/AGENTS.md:47`，跑完刪環境變數）；
  - 在該 repo 開 PR 並合併（擁有者的 repo，直接做）；
  - FMP 的 PR 描述附 fmp-plugins 的 PR 連結。
- **地雷**（M1 帶來的，仍適用）：
  - 文件或程式碼引用子任務的研究檔時，一律寫 archive 後的路徑 `.trellis/tasks/archive/<年-月>/<任務>/…`。
  - CI 的 `app` job 工作目錄已經是 `app/`，路徑不要再加 `app/`。
  - 子代理有時用不了 context7 或 WebFetch，改用 pub cache 原始碼查證是可以的。
  - 子代理因 API 403 或 rate limit 中斷時，用 SendMessage 對同一個 agent 續跑。
  - 桌面裝置一次 `flutter test` 只能跑一個整合測試檔（`app/AGENTS.md:30-32`）。
- **M2 新的地雷**：
  - PR 16a 之後 Android 的 `MainActivity` 繼承 `AudioServiceActivity`。實機驗證帶 `--fmp-dev-plugin` 的 `am start` 前，先確認 design §8.3 的 `provideFlutterEngine` 覆寫仍在。
  - 少了它，參數被靜默忽略、測試插件裝不上，看起來像插件壞了。

## 順序與相依

| PR | 依賴 | PR | 依賴 |
|---|---|---|---|
| 1 | 0 | 12 | 2、7、10、11 |
| 2 | 0 | 13 | 1、8 |
| 3 | 2 | 14 | 6、10、13 |
| 4 | 3 | 15 | 10、14 |
| 5 | 4 | 16a | 4、10 |
| 6 | 0 | 16b | 16a |
| 7 | 1 | 17 | 10、13 |
| 8 | 7 | 18a | 4、17 |
| 9 | 1 | 18b | 10、18a |
| 10 | 9 | 19 | 18a |
| 11 | 1 | | |

- 可以平行的：
  - 2–6 與 1、7、9、11（不同目錄）；
  - 15、16a、17 互不依賴。
- 最長的鏈是 1 → 9 → 10 → 12（或 13）→ 14 → 15。
- 同時開兩個以上分支時，各自的 schema 版本號在後合併的那個 PR 重排。

## 0. 規劃檔與文件更正

- [x] 本任務的 `prd.md`（補上 design §12 的確認結果）、`design.md`、`implement.md`、`research/` commit。
- [x] design §11 標「PR 0」的更正：
  - ADR 0025 §決定 5；
  - ADR 0026 §決定 3；
  - ADR 0019 §決定 1 與 ADR 0018 §決定 4（確認後）；
  - `milestones.md` § M2、§ M3（範圍、驗收的調整）。
- [x] `09-26-fmp-rewrite/task.json` 的子任務清單（目前工作區有未提交的改動，一併整理）。
- 驗證：`main` 上有本任務目錄；`milestones.md` 的 M2 範圍與 design §1 一致。
- 依賴：擁有者核准。模型：sonnet。

## 1. 播放核心拆分與兩條匯入規則（design §7.1、§2）

- [ ] 從 `PlaybackController` 拆出 `PlaybackSession`（唯一碰 `AudioBackend`）與 `PlaybackEventRouter`（純函數）；控制器仍是唯一入口與狀態寫入者。
- [ ] `fmp_layer_imports` 加 `restrictedImports` 機制：
  - `audio_backend.dart` 只給後端目錄、`playback_session.dart`、`playback_providers.dart`；
  - `backend_rules.dart`（結束原因）只給後端目錄與 `playback_event_router.dart`。
- [ ] `app/AGENTS.md` § 播放與 § Lint 改寫（拿掉「等 M2」那句）；`.trellis/spec/app/playback/index.md` 的實機驗證段改成指向 skill（M1 follow-up 6）。
- 測試：
  - 既有 `playback_controller_test.dart` 不改期望全綠（證明行為不變）；
  - `playback_event_router_test.dart` 逐一餵事件；
  - lint 的報與不報案例：同前綴的 `backends_helpers.dart` 也報；改名、註解裡提到不報。
- 實測：Windows 與 Android 各跑一次真後端契約（`app/AGENTS.md:18`）；從搜尋頁播兩首確認交接（重播）。
- 依賴：0。模型：opus。

## 2. 網路狀態與離線呈現（design §5）

- [ ] 平台層 `lib/platform/connectivity/`（`connectivity_plus`），宣告 `networkInterfaces`；`platform_test.dart` 每平台一個斷言。
- [ ] `lib/core/network/network_status.dart`：狀態機。`SourceHttpClient` 回報結果（PR 3 的媒體 client 接同一個入口）。
- [ ] `appLifecycleProvider`（`lib/app/`）；回到 `resumed` 時重查介面。
- [ ] 外殼的全域離線提示；共用的離線空狀態元件；搜尋頁的 `noInterface`／`unreachable` 行為（design §5.4）。
- 測試：
  - 狀態轉換表逐列；`fakeAsync` 下斷言沒有待執行的計時器；
  - 搜尋頁在兩種離線狀態下各一個 widget 測試（兩者都照送，失敗時才顯示離線空狀態；擁有者決定 9）；
  - 全域提示在離線時出現、回到 `online` 時消失；
  - guideline 測試加離線狀態。
- 實測：
  - Android 模擬器切飛航模式 → 全域提示與搜尋頁的離線狀態 → 關掉飛航模式恢復；
  - Windows 停用網路介面再啟用。
  - 模式：重播。
- 依賴：0。模型：opus。

## 3. 媒體 client（design §4.1，決定 1）

- [ ] `lib/core/network/media_http_client.dart`：
  - 每插件一個，不帶憑證、只有媒體標頭；
  - 每跳 `allowedHosts`、最多 5 跳；
  - `maxBytes`；連線 10、間隔 15、總計 30 秒逾時；
  - 錯誤對應；
  - 寫網路紀錄（加 `client` 欄位，`SourceHttpClient` 同步）；
  - 回報網路狀態。
- [ ] `PluginRegistry` 在插件載入時與 `SourceHttpClient` 一起建立。
- 測試（`test/core/network/`，假 adapter）：
  - 請求沒有 `Cookie`／`Authorization`（ADR 0012 §如何確認）；
  - 轉址出網域、`http`、第 6 跳失敗；
  - `Content-Length` 過大與串流中超過上限都中止，且不留暫存檔；
  - 逾時是 `NetworkError`；
  - `network log` 群組的欄位比對（含 `client`）；
  - 結果進網路狀態。
- 實測：沒有使用者看得到的改動（PR 4 才接上畫面），不做。
- 依賴：2。模型：opus。

## 4. 統一快取庫與封面磁碟快取（design §4.2–§4.4）

- [ ] 平台層 `lib/platform/cache_directory/`；宣告快取上限預設與記憶體 `ImageCache` 大小（Android 128 MB、100 張／50 MB；Windows 256 MB、200 張／80 MB）；`main()` 套用 `ImageCache`。
- [ ] `lib/data/cache/`：
  - `cache.db`（第二個 drift 資料庫、快照在 `drift_schemas/cache_database/`、自己的 `schema_test`、開不起來就重建、升級清空）；
  - `CacheStore`（寫入時淘汰、用量、清除、`removePlugin`）。
- [ ] `FmpImageCacheManager`：`flutter_cache_manager` 的 `CacheInfoRepository`、`FileSystem`、`FileService` 三個轉接。
- [ ] `artworkCacheManagerProvider(pluginId)`（`lib/plugins/plugin_artwork.dart`）。
- [ ] `ArtworkImage` 改用 `CachedNetworkImage`，多收 `pluginId`。
- [ ] `fmp_layer_imports`：
  - `flutter_cache_manager` → `lib/data/cache`；`cached_network_image` → `lib/ui/artwork`；
  - `cache_directory` 的限定匯入者。
- [ ] `app/AGENTS.md` § 介面的封面段、§ 網路的媒體 client 段改寫。
- 測試（ADR 0016 §如何確認）：
  - 跨類別淘汰到上限以下；
  - 檔案被刪視為未命中（含 `CacheStore` 不回傳不存在的檔）；
  - 清除後用量為 0；
  - 移除插件只刪它的項目；
  - 損壞的 `cache.db` 開啟時重建；
  - cache manager 的 `get`／`put`／`touched` 對到 `last_access`；
  - `ArtworkImage` 以假 cache manager 的 widget 測試；
  - lint 案例。
- 建置檢查：`flutter build apk --flavor dev --debug` 後以 `zipalign -c -P 16` 確認新增的原生庫（`sqflite` 經 `flutter_cache_manager` 帶入）仍是 16KB 對齊（design §8.3）。
- 實測（真實連線：改動是網路與快取，ADR 0027 §決定 2）：
  - 兩平台搜尋 B 站一次，封面顯示；
  - 重啟 App 後同一頁的封面不再發請求（網路紀錄沒有 `client: media` 的新紀錄）；
  - 檢查 `fmp_cache/` 下有檔案與 `cache.db`。
- 依賴：3。模型：opus。

## 5. 「網路」設定組：快取上限、用量、清除（design §3.3、§4.4、§9.8）

- [ ] `network_settings` 表（schema bump）、repository、Notifier（空＝平台預設）。
- [ ] 設定頁改成分組，expanded 以上 list-detail；「網路」組：快取上限、封面用量、「清除快取」（含 `ImageCache`）。
- [ ] 改上限時淘汰一次。
- 測試：
  - `.trellis/spec/app/settings/index.md` 第 6 步的五種；
  - migration 三種；
  - 清除後用量顯示 0；
  - 設定頁在 400／1000 寬的 guideline；
  - list-detail 的版面測試。
- 實測：兩平台改上限、看用量、清除後封面重新下載（真實連線，延續 PR 4 的最少操作）。
- 依賴：4。模型：sonnet。

## 6. 啟動維護清單與 log 保留 7 天（design §6）

- [ ] `lib/app/startup_maintenance.dart`：有序清單、第一幀後跑一次、各項失敗不影響下一項。
- [ ] 第一項：`logs/` 最後修改超過 7 天的 `fmp*.jsonl` 刪除（`lib/core/logging/` 提供函式）。
- 測試：
  - 順序、只跑一次、在第一幀之後（widget 測試以 `pump` 確認 `runApp` 當下未跑）；
  - 一項丟錯時下一項照跑且錯誤進錯誤歷史；
  - 超過 7 天的檔被刪、未滿 7 天的保留、目前的 `fmp.jsonl` 不刪，大小與天數同時作用（ADR 0025 §如何確認；`File.setLastModified` 造時間）。
- 實測：Windows 在 dev 資料目錄放一個改過修改時間的舊 log 檔，啟動後被刪（log 有一筆維護紀錄）；Android 以 `run-as` 做同樣的事。
- 依賴：0。模型：sonnet。

## 7. 串流網址快取（design §7.4）

- [ ] `StreamResolver` 內的記憶體快取：
  - 鍵＝曲目鍵＋音質＋格式偏好（PR 8 之前偏好固定），LRU 64；
  - `expiresAt − 5 分鐘`，空值 5 分鐘；
  - 播放失敗作廢；進行中的請求共用。
- [ ] `ResolvedStream.expiryMargin` 30 秒改成同一個 5 分鐘常數；控制器的前瞻刷新與交接檢查跟著改。
- 測試（ADR 0016 §如何確認）：
  - 安全邊界、`expiresAt` 為空、作廢、上限 64 的淘汰；
  - **預取後播放只解析一次**；
  - 前瞻解析慢於目前這首結束時只解析一次（M1 follow-up 4 的後半）；
  - `expiry` 群組改成 5 分鐘。
- 實測：Windows 與 Android 從搜尋頁連播兩首，log 的 `resolveStream` 次數＝曲目數（重播）。
- 依賴：1。模型：opus。

## 8. 音質與格式偏好、`expiresAt` 契約（design §7.4、§10，決定 4）

- [ ] `playback_settings` 表（design §3.3 全部欄位，一次 migration）、repository、Notifier（這個 PR 只接音質與格式偏好的 setter）。
- [ ] 設定頁「播放」組的兩列。
- [ ] `StreamRequest.quality`（可選）、依格式偏好重排 `formats`；`fmp-plugin.d.ts`、`sourceDtoShapes`。
- [ ] 契約執行器支援 `checks.json` 的 `expiresAtPattern`；`FmpChecks` 型別。
- [ ] `_bilibiliSigned` 拿掉 `deadline`；`app/` 內既有 fixture 照舊通過「再遮一次不變」。
- [ ] **fmp-plugins PR**：
  - B 站讀 `quality`；
  - `checks.json` 加 `quality` 與 `expiresAtPattern`；
  - 重錄 `resolveStream` fixture（真實連線，一個案例）；
  - 人工逐檔確認沒有憑證。
- [ ] ADR 0014 §決定 5 的一行補充。
- 測試：
  - settings 五種與 migration 三種；
  - 快取鍵含偏好（換偏好後重新解析）；
  - `formats` 的順序；
  - `type_definitions_test.dart`；
  - `contract_runner_test.dart` 的 `expiresAtPattern`（不一致會紅、改無關欄位不紅）；
  - `fixture_scan_test.dart`。
- 實測：兩平台把音質切到「低」播一首 B 站，`Opening stream` 的 `bitrate` 是最低層（真實連線：改動是插件）。
- 依賴：7。模型：opus。

## 9. 完整 `QueueModel`（design §7.2）

- [ ] 純 Dart。`QueueEntry(TrackInfo)`、`TrackInfo`（`lib/domain/`）與 `TrackSummary` 的轉換。
- [ ] 規則：
  - 模式 `queue`、`temporary`；
  - 循環三種；
  - 位置式隨機（開、關、拖曳、下一首播放、附加、跳到、一輪結束）；
  - 上一首 3 秒；
  - 10,000 上限整批拒絕；
  - 移除、清空；
  - 臨時播放的快照與回到佇列。
- 測試（ADR 0018 §如何確認的 `QueueModel` 部分，Mix 修剪除外）：
  - 隨機位置語意；
  - 拖進已播位置本輪不再播；
  - 連續「下一首播放」依加入順序；
  - 臨時播放保留最早快照；
  - 臨時播放中單曲循環仍回到快照；
  - 上限（剛好 10,000 可、10,001 整批拒絕）；
  - 以固定種子的隨機操作序列比對不變式（每個位置在一輪內恰好播一次）。
- 實測：沒有使用者看得到的改動，不做。
- 依賴：1。模型：opus。

## 10. 控制器的佇列操作、臨時播放與入口（design §7.2、§7.3，D1）

- [ ] 控制器 API：
  - `playTemporary`、`addToQueue`、`playNext`、`removeAt`、`move`、`jumpTo`、`clear`；
  - `setLoopMode`、`setShuffle`；
  - 上一首 3 秒；
  - 單曲循環以同一份解析結果當前瞻（design §7.6 末段）；
  - `events` stream 的 `QueueFull`。
- [ ] 刪 `queueTracksProvider`；播放列改讀 `QueueEntry` 的顯示資料。
- [ ] 搜尋頁：點一下＝臨時播放；選單「播放、下一首播放、加入佇列」（右鍵、長按、「⋯」）。
- [ ] `playback_settings` 的「記住播放位置」「臨時播放回佇列倒退秒數」接上 setter 與設定頁兩列。
- [ ] 改寫 `search_page_test.dart` 的 `tapping a result plays the whole list from it` 與 `install_search_play_test.dart` 的期望。
- 測試：
  - 臨時播放結束、按下一首、按上一首都回到佇列，倒退秒數與「記住播放位置」的四種組合，原本暫停時只載入不播；
  - 單曲循環不重解析；
  - 加入超過上限發 `QueueFull` 並由外殼提示；
  - 搜尋頁三個選單項目。
- 實測：
  - 兩平台：搜尋→點 A（臨時播放）→ 選單把 B、C 加入佇列 → 播放列下一首；
  - 回到佇列時位置與倒退正確；
  - 單曲循環兩圈；
  - 模式：重播。
- 依賴：9。模型：opus。

## 11. 後端契約補齊：前瞻失敗、HTTP 狀態碼（design §7.6，M1 follow-up 4）

- [ ] 兩個後端：前瞻開不起來時，目前這首照常播完並發 `SourceEnded`，失敗以前瞻的 id 回報；Windows 不卡在 Playing。
- [ ] `SourceFailed.httpStatus`：`backend_rules.dart` 從 ExoPlayer 例外與 mpv log 行解析。
- [ ] 控制器把前瞻失敗當成下一首的開流失敗（作廢快取，到那首時重解析）。
- 測試：
  - 契約的兩個新案例（假後端在 `flutter test`）；
  - 狀態碼解析以錄下的兩種錯誤文字做單元測試（含不含狀態碼的反例）。
- 實測：
  - Windows、Android 各跑真後端契約（`app/AGENTS.md:18`）；
  - 測試插件加一個關鍵字讓第二首的網址開不起來，連播時第一首完整播完、第二首走恢復（重播）。
- 依賴：1。模型：opus。

## 12. `RecoveryPolicy` 完成與播放提示（design §5.3、§7.5、§7.9，M1 follow-up 1、2、9）

- [ ] `decideRecovery`：
  - 加網路狀態、「跳過試聽片段」、重解析次數三個輸入；
  - 加 `WaitForNetwork`、`PlayAsPreview`、`ReResolve` 三種結論；
  - 10 秒歸零；
  - 緩衝飢餓 15 秒；
  - HTTP 403／404／410 的重解析與對應；
  - 跳過的去處依模式。
- [ ] `Retrying.delay` 可空（等網路）；`Unavailable.reason` 可空；ADR 0013 一行更正。
- [ ] `StreamResult.previewOnly`（可選）；測試插件加會回傳它的關鍵字；`d.ts`、shapes。
- [ ] 控制器的 `events`：`TrackSkipped`、`PlaybackStopped`、`PreviewPlaying`；外殼 listener 轉成 `Toaster`；M1 的 `Failed` 提示併入。
- [ ] 「跳過試聽片段」的設定頁一列；播放列的「重試中／等待網路連線／試聽」標示。
- 測試（ADR 0018 §如何確認的 `RecoveryPolicy` 部分）：
  - 每類錯誤的處理；
  - 離線暫停計數、恢復後立刻重試；
  - 正常播放 10 秒歸零（以位置前進，沒有計時器）；
  - 連續跳過停止並提示一次；
  - `temporary` 中跳過回到佇列；
  - 403 先重解析；
  - 試聽兩種設定；
  - 離線期間沒有提示；
  - `app_shell_test.dart` 的提示案例。
- 實測：
  - 兩平台：測試插件 `fail` 關鍵字的提示；
  - 播放中切斷網路 → 顯示等待網路 → 恢復後自動續播；
  - 試聽關鍵字在設定開與關各一次（重播）。
- 依賴：2、7、10、11。模型：opus。

## 13. E19：音量、速度、輸出裝置與 Android 音訊中斷（design §7.6，決定 3）

- [ ] `AudioBackend.setVolume`、`setSpeed`、`outputDevices`；`PlaybackSupport.outputDeviceSelection`（Windows 真、Android 假），組裝點的 `assert`。
- [ ] `JustAudioBackend`：
  - `handleInterruptions: false`；
  - 自己聽 `audio_session`：duck 內部減半；中斷與拔耳機發事件，由控制器暫停或續播；
  - `audio_session` 加為直接依賴，擁有者 `lib/playback/backends`。
- [ ] `MediaKitBackend`：音量、速度、裝置清單與選擇；`ao` 錯誤 → `OutputDeviceFailed` → 暫停並提示。
- [ ] 控制器 API：`setVolume`、`toggleMute`、`setSpeed`、`selectOutputDevice`。
- [ ] 偏好裝置存 `playback_settings`，裝置清單第一次就緒時套用一次。
- 測試：
  - 契約的音量、速度案例（開流前設定、換來源與交接後維持、速度夾取）；
  - 控制器的中斷事件 → 暫停與續播（只有暫停類中斷結束才續播）；
  - 拔耳機只暫停；
  - 宣告與 `outputDevices` 一致（`platform_test.dart`）；
  - 偏好裝置不在清單時用預設且不清掉偏好。
- 實測：
  - Windows：調音量、速度 1.5 跨兩首仍是 1.5、切換輸出裝置（有兩個裝置時；只有一個時記錄只驗了 `auto`）；
  - Android：調音量；以 `adb shell cmd media_session dispatch` 或另一個 App 播放觸發焦點中斷，確認暫停與續播；
  - 兩平台跑真後端契約；
  - 模式：重播。
- 依賴：1、8。模型：opus。

## 14. 佇列持久化與啟動恢復（design §3.1、§3.2、§7.7）

- [ ] `tracks`、`queue_entries`、`player_state` 表（schema bump）、repository（差量寫入、外鍵 `RESTRICT`）。
- [ ] `queue_store.dart`：
  - 佇列操作當下寫入；
  - 播放中每 10 秒；
  - 暫停、seek、`hidden`／`paused` 時寫位置；
  - 音量；
  - 臨時播放期間不覆寫快照。
- [ ] 啟動恢復：`Idle` 帶佇列與位置、按播放才解析、恢復後第一次不記歷史；「重啟恢復時倒退秒數」的 setter 與設定頁一列。
- [ ] 孤兒曲目登記到啟動維護清單。
- 測試：
  - repository 以固定種子的隨機操作序列比對 `QueueModel`；
  - 一萬筆整份取代的耗時上限（記錄數字，超過 500 ms 在 PR 描述說明）；
  - `RESTRICT` 反例；
  - migration 三種；
  - 恢復的四種組合（記住位置開關 × 倒退秒數）；
  - 臨時播放中重啟回到快照；
  - 孤兒清理只刪無人參照的列。
- 實測：
  - 兩平台：建一個五首的佇列、開隨機與循環、播到第三首中間 → 關掉 App → 重開，佇列、隨機順序、循環、音量、位置都回來，而且沒有發解析請求（log）→ 按播放從倒退後的位置開始；
  - 模式：重播。
- 依賴：6、10、13。模型：opus。

## 15. 播放歷史與「歷史」頁（design §7.8、§9.7，決定 5）

- [ ] `play_history` 表（schema bump）、repository（分頁查詢、裁切、刪一筆、全部清除）。
- [ ] 控制器在「開始一首」第一次 `ready` 時寫入。
- [ ] 「播放歷史保留筆數」的 setter 與設定頁一列（改小時當下裁切）。
- [ ] 外殼加「歷史」導覽項（搜尋｜歷史｜設定）。
- [ ] 歷史頁：日分組、臨時播放、選單、清除全部（確認框）。
- 測試：
  - 寫入時機：換歌、前瞻接上、單曲循環每圈各一筆；重試、換候選、啟動恢復、回到佇列不寫（ADR 0018 §如何確認「單曲循環每圈一筆歷史且不重解析」）；
  - 保留筆數的裁切；
  - 寫入失敗不影響播放；
  - migration 三種；
  - `navigation per window class` 三個導覽項；
  - 歷史頁的 guideline 與離線案例。
- 實測：兩平台播三首（其中一首單曲循環兩圈）→ 歷史頁有四筆、日分組正確 → 點一筆臨時播放 → 清除全部（重播）。
- 依賴：10、14。模型：opus。

## 16a. 系統媒體控制：Android 與返回鍵（design §8.1–§8.3、§9.1，決定 7）

- [ ] `lib/platform/media_controls/`：介面、Android 實作（`audio_service` 0.18.19），宣告 `mediaControls`（`supportsSeek: true`）；初始化失敗時宣告改為沒有。
- [ ] `NowPlayingPublisher`（`lib/playback/`）：
  - 只在改變時推、依序；
  - 按鈕依能力；
  - 封面經 `artworkCacheManagerProvider` 拿本機檔交 `file://`。
- [ ] `AndroidManifest.xml`：三個權限、`AudioService`、`MediaButtonReceiver`。
- [ ] `MainActivity` 繼承 `AudioServiceActivity`：
  - 覆寫 `provideFlutterEngine`（帶 `dart_entrypoint_args`）；
  - 覆寫 `popSystemNavigator`（`moveTaskToBack(true)`）。
- [ ] 外殼的 `PopScope`：不在第一個分頁時回到第一個分頁。
- [ ] `verify-on-device` 的 Android 參考若需要就改；`app/AGENTS.md` § App 身分或 § 平台層寫明兩個覆寫的理由。
- 測試：
  - `NowPlayingPublisher` 去重與排隊（假平台實作）；
  - 系統指令經控制器；
  - `android_manifest_test.dart`（XML 解析：權限、服務、receiver）；
  - `platform_test.dart`；
  - 外殼返回的三種情況（widget 測試以 `handlePopRoute` 模擬）。
- 實測（Android 模擬器）：
  - 以 `--fmp-dev-plugin` 啟動，確認測試插件仍裝得上（`provideFlutterEngine` 覆寫有效）；
  - 播放中下拉通知：曲名、封面、上一首／播放／下一首、進度條可拖；
  - 鎖定畫面控制；
  - 返回鍵：在「歷史」分頁按返回 → 回到「搜尋」→ 再按 → App 退到背景、音樂繼續 → 從最近使用回來，狀態不變；
  - 播放頁開著時（PR 18a 之後再驗一次）按返回只關播放頁；
  - `dumpsys media_session` 有 FMP 的工作階段；
  - 跑 `integration_test/audio_backend_contract_test.dart` 確認整合測試在 `AudioServiceActivity` 下照常執行。
  - Windows：沒有改動（只跑整合測試確認不受影響）。
  - 模式：重播。
- 依賴：4、10。模型：opus。

## 16b. 系統媒體控制：Windows SMTC（design §8.4）

- [ ] `media_controls_windows.dart`（`smtc_windows` 1.1.0），宣告 `supportsSeek: false`。
- [ ] 封面先試快取檔的 `file:///`，不行就交 `https` 原網址；交出前 `Uri.tryParse` 檢查。
- [ ] `app/AGENTS.md` § 驗證：Windows 建置需要 `rustup`。
- [ ] CI 的 Windows 建置與整合測試確認仍綠（runner 內建 Rust）；缺時才在 `ci.yml` 加步驟。
- 測試：`platform_test.dart`；Windows 實作的轉換函式（`NowPlaying` → SMTC 的 metadata 與 timeline、按鈕）單元測試。
- 實測（Windows）：
  - 播放中按鍵盤媒體鍵（播放／暫停、下一首）；
  - 音量浮層的媒體卡片有曲名、封面；
  - 暫停與恢復時卡片同步；
  - 記錄 `file:///` 封面是否可用，結論寫進 `app/AGENTS.md`。
  - 模式：重播（封面要真實 B 站時另做一次最少操作）。
- 依賴：16a。模型：opus。

## 17. 播放列三段與快捷鍵全表（design §9.2、§9.5）

- [ ] 播放列三段的完整控制項：
  - 隨機、循環；
  - 輸出裝置（依宣告）；
  - 音量滑桿／圖示＋彈出滑桿；
  - 靜音；
  - 「⋯」；
  - 點空白處開播放頁（PR 18a 前先接到一個佔位路由，或與 18a 同時合併時直接接）。
- [ ] `PlaybackShortcuts` 抽出共用；加 Ctrl+↑／↓、Ctrl+S、Ctrl+R、Esc、Ctrl+L／Q（播放頁的部分在 18a 接）；輸入框規則（導覽類有效、其餘讓出）。
- [ ] tooltip 附按鍵（翻譯檔 `*Tooltip`），三語言。
- 測試：
  - `controls per width` 的邊界與 Android 沒有輸出裝置鈕；
  - 曲名 ≥ 160dp；
  - golden 三段（`--update-goldens` 後人工看圖）；
  - `shortcuts` 群組的新鍵與輸入框案例；
  - guideline。
- 實測：
  - Windows：每個快捷鍵各按一次（含在搜尋框內按 Ctrl+S 不切隨機、Esc 有效）；
  - 拖寬視窗經過 600、840 兩個邊界，看控制項換段；
  - Android：三段在直向與橫向；
  - 模式：重播。
- 依賴：10、13。模型：opus。

## 18a. 播放頁 B（design §9.3、§9.6）

- [ ] 全螢幕路由；外殼得知它在最上層時提示貼底部安全區。
- [ ] 三種版面（手機與 medium、B 兩欄、extraLarge 三欄）；左欄控制；「⋯」的速度與右側面板切換。
- [ ] 歌詞空狀態；`TrackDetails`；毛玻璃（高對比時不透明）。
- [ ] `layout_state` 表（schema bump，含右側面板的兩欄）；分頁記憶。
- [ ] 頁內 F6 區、Esc 關閉、Ctrl+L／Q。
- [ ] ADR 0024 §決定 1 的一行更正。
- 測試：
  - guideline（淺色、深色 × 最淺、最深的測試封面）；
  - golden 1000、1400、1800；
  - Esc、F6、Ctrl+L／Q；
  - 分頁記憶（extraLarge 記住歌詞時的行為）；
  - `toast_layering_test.dart` 加播放頁；
  - migration 三種。
- 實測：
  - Windows：從播放列開播放頁、三種寬度、Esc 關閉、速度選單、在播放頁上觸發一個提示（`fail` 關鍵字）確認提示可見且貼底；
  - Android：手機版的封面與歌詞切換、返回鍵只關播放頁（補 16a 的那一項）；
  - 兩平台跑 `toast_layering_test.dart`；
  - 模式：重播。
- 依賴：4、17。模型：opus。

## 18b. 佇列分頁與底部面板（design §7.3）

- [ ] 播放頁的佇列分頁、手機與 medium 的底部面板：
  - 目前這首標示、點選跳到；
  - 拖曳把手重排、移除、下一首播放；
  - 清空（確認框）；
  - 隨機時的說明文字。
- [ ] 「切歌時捲到目前歌曲」的 setter 與設定頁一列。
- [ ] 一萬筆時以 `ListView.builder`／`ReorderableListView.builder` 不一次建出。
- 測試：
  - 各動作經控制器；
  - 隨機開啟時拖曳後的「接下來」與 `QueueModel` 一致；
  - 自動捲動開關；
  - guideline。
- 實測：
  - 兩平台：在佇列分頁或底部面板拖曳、移除、清空、點選跳到；
  - 開隨機後拖曳，確認接下來播的與畫面一致；
  - Windows 以鍵盤操作佇列（Tab、Enter）；
  - 模式：重播。
- 依賴：10、18a。模型：opus。

## 19. 右側「正在播放」面板（design §9.4，決定 6）

- [ ] 外殼在 expanded 以上的面板：
  - 展開、收起（標題列與播放頁「⋯」）；
  - 拖曳把手（鍵盤左右鍵也可）；
  - 寬度 320–視窗 × 0.4，預設 412、extraLarge 480；
  - 拖曳結束寫 `layout_state`；
  - 內容是 `TrackDetails`。
- [ ] 播放列橫跨內容與面板，分段依那個寬度。
- 測試：
  - 面板只在 ≥ 840 出現；
  - 收起與寬度記憶；
  - 夾取（資料庫裡的壞值）；
  - 開關面板不改變播放列的分段；
  - guideline 與 golden（1000、1800 的外殼）。
- 實測：
  - Windows：拖寬、收起、重啟後維持；
  - 縮到 < 840 面板消失、放大回來仍是記住的寬度；
  - Android（平板尺寸的模擬器或橫向大螢幕）至少看一次 expanded；
  - 模式：重播。
- 依賴：18a。模型：opus。

## 留下的後續

PR 1 留下的：

- [ ] `fmp_layer_imports` 不正規化含 `..` 的 package URI（`package:fmp/playback/../…`），既有限制，這次的 `restrictedImports` 一樣抓不到。
- [ ] `audioBackendProvider` 不經 import 也能 `ref.watch` 拿到後端實例；lint 只管 import，這半條沒有閘門（`app/AGENTS.md` § 播放已註明），review 時看。

（每個 PR 收尾時補；格式照 M1 的「PR n 留下的後續」各節。）

## 里程碑驗收（19 之後）

### 兩平台端到端（ADR 0026 §決定 1；Android 模擬器與 Windows 各一次，dev flavor）

- **模式**：
  - 主流程用 B 站插件（真實連線）：M2 的目標是「以單一音源像舊版一樣日常聽歌」；
  - 只做下列最少的操作，每平台約十首的解析與封面請求；
  - 離線與錯誤的步驟改用測試插件（重播）。
- **步驟**（兩平台相同，平台差異標在括號）：
  1. 清掉 dev 資料目錄，以 `--fmp-dev-plugin` 安裝 B 站插件並啟動。
  2. 搜尋一個關鍵字：點第一首（臨時播放）→ 以選單把另外四首加入佇列、其中一首用「下一首播放」。
  3. 播放列：下一首、上一首（3 秒內與外各一次）、拖進度條、開隨機、開循環「全部」、調音量、靜音再取消。
  4. 開播放頁：
     - 三種寬度（Windows）／直橫向（Android）；
     - 佇列分頁拖曳一首、移除一首；
     - 詳細分頁；
     - 速度 1.5 跨兩首仍是 1.5；
     - Esc／返回鍵關閉。
  5. 右側面板（Windows）：拖寬、收起、展開。
  6. 系統媒體控制：
     - Android 通知與鎖定畫面的上一首、暫停、下一首、拖進度；
     - Windows 鍵盤媒體鍵與媒體卡片。
  7. Android：
     - 「歷史」分頁按返回回到「搜尋」，再按返回 App 退到背景、音樂繼續；
     - 模擬一次音訊焦點中斷（暫停並在結束後續播）。
  8. Windows：切換輸出裝置（有兩個裝置時）。
  9. 單曲循環一首兩圈；歷史頁看到對應筆數並從歷史點一首臨時播放，結束後回到佇列原位置（倒退 10 秒）。
  10. 關掉 App 重開：
      - 佇列、目前這首、位置（倒退「重啟恢復時倒退秒數」）、隨機順序、循環、音量都在；
      - 啟動時沒有解析請求；
      - 封面從快取讀、沒有媒體請求。
  11. 設定：
      - 「播放」組每一列各改一次；
      - 「網路」組看封面用量、清除快取後封面重新下載；
      - 音質切到「低」播一首，`bitrate` 是最低層。
  12. 離線（改用測試插件）：
      - 播放中切斷網路 → 全域離線提示、播放列顯示等待網路、沒有提示洗版；
      - 恢復網路 → 自動續播；
      - 搜尋頁在沒有介面時顯示離線狀態。
  13. 錯誤（測試插件）：`fail` 關鍵字的提示、連續跳過到上限停止並提示一次、試聽關鍵字在兩種設定下的行為。
  14. 隔天（或把 log 檔修改時間改到 8 天前）重開：超過 7 天的 log 被刪。
- **證據**：寫在本任務 `research/m2-acceptance.md`。照 M1 `research/m1-acceptance.md` 的格式，記平台、模式、真實請求清單、截圖（不含個人資訊）。

### ADR 的測試（design §12 第 3 條確認後的範圍）

| ADR | 項目 | 在哪個 PR |
|---|---|---|
| 0016 | 串流網址快取的安全邊界、`expiresAt` 為空、作廢；**預取後播放只解析一次**（下載不走快取在 M6） | 7 |
| 0016 | 快取庫跨類別淘汰、檔案被刪視為未命中、清除後用量 0、移除插件刪項目 | 4、5 |
| 0016 | 網路狀態轉換且沒有計時器輪詢 | 2 |
| 0016 | 各頁離線狀態（M2 存在的畫面） | 2、15、18a |
| 0016 | 插件契約：`expiresAt` 與網址期限一致 | 8 |
| 0016 | lint：快取目錄只經快取模組 | 4 |
| 0017 | 啟動維護清單（排程器的七項在 M3，決定 2） | 6 |
| 0025 | log 保留 7 天與大小同時作用 | 6 |
| 0018 | `QueueModel`：隨機位置語意、拖曳、連續下一首播放、臨時播放快照、上限（Mix 修剪在 M3） | 9 |
| 0018 | `RecoveryPolicy`：每類錯誤、離線暫停計數、歸零、連續跳過停止 | 12 |
| 0018 | 預取後播放只解析一次；單曲循環每圈一筆歷史且不重解析（開直播取消音樂請求在 M3） | 7、10、15 |
| 0018 | 後端契約：同一份規則跑兩個實作與假後端（E19、前瞻失敗、HTTP 狀態碼） | 11、13 |
| 0018 | lint：結束原因型別、窄介面 | 1 |
| 0024 | 播放頁與播放列的 guideline、golden、快捷鍵與焦點 | 17、18a、18b、19 |

- [ ] 上表逐項在 PR 描述或測試檔找到對應。
- [ ] `milestones.md` 的 M2 狀態與兩個驗收勾選（ADR 0026 §如何確認：未打勾不能 archive）。
- [ ] `app/AGENTS.md` 的播放、網路、介面、資料層段落與 M2 的實際一致（逐條有閘門或標明「沒有閘門，review 時看」）。
- [ ] 本任務 `finish`、`archive`。

## 待升級

- `analysis_server_plugin`、`analyzer`、`analyzer_testing` 仍停在 M1 的釘版（`app/AGENTS.md:594-596`）；Flutter 放寬 `test_api` 後一起升。
- `smtc_windows` 最後一版 2025-08-18（digest §3）：M2 期間若 Flutter 或 `flutter_rust_bridge` 不相容，照 ADR 0009 §決定 6 以 git 依賴鎖 commit 並註明上游 issue。

## 風險與回滾點

| 風險 | 處理 |
|---|---|
| `AudioServiceActivity` 的共用引擎讓 `--fmp-dev-plugin`、`integration_test`、`flutter run` 的附加在 Android 失效 | design §8.3 的 `provideFlutterEngine` 覆寫，PR 16a 的實測第一步就驗。不行就先不用 `AudioServiceActivity`，照 `audio_service` 文件手動覆寫 `provideFlutterEngine` 與 `shouldDestroyEngineWithHost`。PR 16a 可單獨 revert |
| `smtc_windows` 要 Rust 從原始碼編譯，本機或 CI 缺工具鏈就建置失敗；套件 13 個月沒有新版 | 舊專案的 `windows-2022` CI 證明 runner 有 Rust；本機要求寫進 `app/AGENTS.md`。壞掉時 16b 單獨 revert，Windows 暫時沒有 SMTC，其餘不受影響 |
| `handleInterruptions: false` 後自寫的中斷處理漏掉情況（例如通話結束不續播），或與 M1 的音訊焦點契約衝突 | 只轉成事件交給控制器，邏輯照舊版 `just_audio_service.dart`；PR 13 實測焦點中斷，並以 `dumpsys audio` 確認換歌仍不放焦點 |
| 佇列一萬筆的差量寫入在 Android 太慢 | PR 14 量整份取代的耗時；超標時改成背景 isolate 的 drift 執行器（`NativeDatabase.createInBackground`），不改資料格式 |
| `flutter_cache_manager` 的 `CacheStore` 有自己的記憶體快取與清理計時器，和統一淘汰器互相干擾 | `getObjectsOverCapacity`、`getOldObjects` 回空；靠它「取檔前檢查存在」的行為（已讀原始碼）；PR 4 測「淘汰器刪檔後同一張圖重新下載」 |
| 拿掉 `deadline` 的遮蔽讓其他 fixture 的「再遮一次不變」紅掉，或被認為放寬遮蔽 | 只改這一個參數名；PR 8 的檢查要試著攻破；fmp-plugins 的 fixture 同一輪重錄。不接受時改回，ADR 0016 的契約檢查標為恆真並寫進 `app/AGENTS.md` 的已知限制 |
| B 站在錄 fixture 或驗收的真實連線時風控 | 最少操作；卡住時改用測試插件完成 UI 與播放驗證，B 站部分具名回報 blocker（M1 同一做法） |
| `tracks` 提前後 M4 的欄位需求和 M2 的形狀衝突 | M2 只放音源給的事實，欄位都可空或必有；M4 只加欄位與新表。擁有者不同意提前時，改成佇列與歷史各存快照，M4 再搬（design §3.1 的另一案） |
| PR 數量多（20 個），依賴鏈長（1 → 9 → 10 → 12 → 14 → 15） | 依「順序與相依」的圖平行開不同目錄的 PR；schema 版本號由後合併的 PR 重排 |
