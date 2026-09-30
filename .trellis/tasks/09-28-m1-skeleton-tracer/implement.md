# M1 執行計畫

## 通用規則（每個 PR 子任務）

- **開工**：
  - 從最新的 `main` 開分支；
  - 以 `task.py create "<標題>" --slug <slug> --parent .trellis/tasks/09-28-m1-skeleton-tracer --package app` 建子任務；
  - prd 只寫做什麼與驗收（ADR 0026 §決定 1），在已核准範圍內直接做，遇到未定的事才問。
- **合併條件**：
  - `app/` 可編譯、`flutter test` 全綠；
  - CI 彙總 job 通過；
  - PR 描述附 review 指南。
- **實機驗證**：使用者看得到的 PR 在 Android 模擬器與 Windows 都驗，回報寫明平台與模式（ADR 0027）。
- **收尾**：
  - 子任務 `finish` 與 `archive --no-commit --skip-branch-validation`；
  - 手動 commit；
  - repo 慣例是以 merge commit 合併。
- **文件**：
  - 每個 PR 更新 `app/AGENTS.md` 中自己那一層（只寫查不到的契約與有閘門的規則，ADR 0015 §如何確認）；
  - 需要時更新 `.trellis/spec/app/<layer>/`。
- **套件版本**：以 `research/m1-tooling-facts.md` 為起點，加依賴時再到 pub.dev 核對一次。
- **子代理模型**（擁有者 2026-09-29 核准）：
  - 實作用 sonnet：PR 1、11。都是機械性工作；PR 1 的內容刪減由主對話決定。
  - 實作用 opus：PR 2–10、12、13 與 YouTube.js 探針。
  - `trellis-check` 一律 opus；研究代理一律 sonnet。

## 進度與交接（2026-09-30 更新；compact 後從這裡接）

- **已合併進 `main`**：#173（設計文件）、#174（PR 1 指令檔分家）、#175（PR 2 骨架與 CI）、#177（PR 3 lint）、#178（PR 4 平台層）、#179（PR 5 drift）、#180（PR 6 log 與設定）、#181（PR 7 錯誤模型）、#182（PR 8 網路層）、#183（PR 9a JS 執行環境）、#184（PR 9b 契約執行器）、#185（PR 9c 紀錄）、#186（遮蔽修正）、#187（PR 10 播放核心）、#188（YouTube.js 探針結論）。#176 是 CI 路徑探測，已關閉。
- **isar／sqlite3 共存探針**：已完成，兩平台共存、全部 16KB 對齊（`research/isar-sqlite3-coexistence.md`，ADR 0010 已補）。
- **PR 9a 完成**（#183，子任務已 archive 到 `.trellis/tasks/archive/2026-09/09-30-js-runtime/`）：每插件一個背景 isolate 的 QuickJS、宿主 API v1、manifest、從檔案安裝與 dev 開發入口、測試插件 `fmp-test`；數字在該子任務 `research/notes.md` §4。
  - 實機：Windows dev 開發入口裝上、重啟後從資料庫載入、prod 不理會旗標；Android 模擬器 dev 的前兩項。模擬器上的 `com.personal.fmp` 是舊版 1.11.0，prod 沒裝上去驗；prod 那一段由單元測試守（`devPluginPath` 對 prod 一律回 `null`，有變異驗證）。
- **PR 9b 完成**（#184，子任務已 archive 到 `.trellis/tasks/archive/2026-09/09-30-plugin-contract/`）：fixture 錄製重播、`checks.json`、契約執行器；擁有者決定 8 讓執行器可在命令列做免登入的錄製（`live` tag），ADR 0015 §決定 7 已補更正。
- **PR 9c 完成**（子任務已 archive 到 `.trellis/tasks/archive/2026-09/09-30-bilibili-plugin/`）：公開 repo `1morr/fmp-plugins`，本機 clone 在與 FMP 同層的 `fmp-plugins/`；B 站插件由該 repo 的 #1 合併（`e2b224b`），`bilibili/bilibili.js` 只有 `search`、`resolveStream`。
  - 在 dev App 裝它：`fmp.exe --fmp-dev-plugin=<fmp-plugins>/bilibili/bilibili.js`（Android 照 9a 的 `run-as` 做法）。
  - 真實連線：兩次錄製共 8 個 GET，沒有遇到風控；fixture 人工逐檔檢查過。
- **遮蔽修正**：`hdnts`／`buvid` 進內建名單、同 host 的規則合併套用；fmp-plugins 的 B 站 fixture 同步重新遮蔽。
- **PR 10 完成**（#187，子任務已 archive 到 `.trellis/tasks/archive/2026-09/09-30-playback-core/`）：播放核心、兩個後端、前瞻交接。dev 入口 `--fmp-dev-playback`（可加 `=<曲目鍵>`）；實機數字在該子任務與 #187 描述。
- **YouTube.js 探針完成**：通過（VISIONOS client），M3 的 YouTube 走插件；程式碼在分支 `probe/youtubejs`（已 push，不合併），結論在 `.trellis/tasks/archive/2026-09/09-30-youtubejs-probe/`，ADR 0014 §決定 10 已補。Android 只驗到音訊系統層（模擬器 `-no-audio`）。
- **PR 11 完成**（子任務已 archive 到 `.trellis/tasks/archive/2026-09/09-30-verify-on-device/`）：`.claude/skills/verify-on-device/`；實機驗證一律照它做，回報含平台與模式。Windows 腳本以視窗標題 `FMP Dev` 比對，避免點到同名 `fmp.exe` 的舊版。
- **下一步**：12 UI → 13 五平台建置與發版 workflow → 里程碑驗收。
- **擁有者決定**：1–8 都在父任務 `prd.md`「擁有者的決定」。9a、9b 期間新增了三項：
  - 決定 6：插件安裝檔是單一 `.js`，開頭帶 `==FMP Plugin==` manifest；
  - 決定 7：插件在背景 isolate 執行；逾時先送存活探測，沒回應才停用到重啟；
  - 決定 8（9b）：M1 的 fixture 由契約執行器在命令列錄製，限免登入案例。
- **每個 PR 的固定流程**：
  1. 從最新 `main` 開分支；
  2. `task.py create … --parent .trellis/tasks/09-28-m1-skeleton-tracer --package app --no-start`；
  3. 寫 prd（繁中，列做什麼與驗收）與 `implement.jsonl`／`check.jsonl`；
  4. `task.py start`；
  5. 派 opus `trellis-implement`，驗證清單固定為：format、build_runner 後沒有實質變動、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`、哨兵、需要時建置；
  6. 使用者看得到的改動，由主對話照 `verify-on-device` skill 實機驗證（Android 與 Windows，回報含平台與模式）；
  7. 派 opus `trellis-check`，要它試著攻破安全相關的部分；
  8. 把後續待辦寫進本檔；
  9. `git checkout --` 還原只有換行差異的產生檔（`generated_plugin*`、`app_database.g.dart`、`GeneratedPluginRegistrant.swift`）——**逐檔**用 `git diff --ignore-all-space --ignore-cr-at-eol` 確認是空的才還原；加了原生插件的 PR 有真正新增的註冊，整批還原會把它們弄丟（PR 10 踩過，`flutter pub get` 可重新產生）；
  10. 分開 commit；
  11. `task.py finish`，再 `archive <slug> --no-commit --skip-branch-validation`，把 archive commit 掉；
  12. push，`gh pr create`（繁中描述＋review 指南）；
  13. 背景跑 `gh pr checks --watch`；
  14. 全綠後 `gh pr merge --merge`，main 快轉。
- **地雷**：
  - 文件或程式碼引用子任務的研究檔時，一律寫 archive 後的路徑 `.trellis/tasks/archive/2026-09/<任務>/…`。
  - CI 的 `app` job 工作目錄已經是 `app/`，路徑不要再加 `app/`。
  - 子代理有時用不了 context7 或 WebFetch，會改用 curl 或 pub cache 原始碼查證，這是可以接受的。
  - 子代理曾因 API 403（`oauth_org_not_allowed`）中斷，用 SendMessage 續跑就成功了。
  - 第 5 項的播放頁示意 Artifact 已被刪除，`phase2-plan.md` §10 的連結失效，決定仍以 ADR 0024 為準。

## 順序

### 0. 合併 #173（設計文件進 `main`）

- [ ] 本任務的規劃檔 commit 到 `docs/audit`，push。
- [ ] #173 轉為 ready，以 merge commit 合併；本機 `main` 更新。
- 驗證：`main` 上有 `docs/adr/0027-*.md` 與本任務目錄。

### 1. 指令檔分家（design §1）

- [ ] 根目錄 `AGENTS.md` 縮成共用部分；`lib/AGENTS.md` 收舊規則。
- [ ] `git mv` 舊 spec 到 `.trellis/spec/legacy/`，更新全部引用。
- [ ] `config.yaml` 宣告 `packages:`；兩個 active task 補 `"package": "app"`。
- [ ] `trellis-implement.md`、`trellis-check.md` 的驗證步驟改成照 package 讀對應的 AGENTS.md。
- [ ] skill 改名 `verify-legacy-on-device`。
- [ ] ADR 0015、0021、0027 的更正補充句；`docs/README.md` 地圖更新。
- 驗證：
  - `flutter test --exclude-tags live test/support test/workflows`；
  - 舊路徑搜尋歸零，archive 任務除外；
  - 新 session 的 SessionStart 只列 `guides` 與 `app` 的 spec 索引。

### 2. `app/` 骨架

- [ ] 本機 Flutter 升到 3.47.5；舊專案 `flutter test --exclude-tags live` 仍全綠。
- [ ] `flutter create`，加上：
  - pub workspace；
  - flavor dev／prod 與 `default-flavor: dev`；
  - App 身分（ADR 0008、0015 §決定 8）；
  - 資料目錄的 `-dev` 命名空間。
- [ ] 單一實例鎖（Windows）。
- [ ] 零聯網兩道防線：`dart_test.yaml`、`flutter_test_config.dart`。
- [ ] `material_ui` import 路徑的決定。
- [ ] `app/AGENTS.md`；第一個 `.trellis/spec/app/<layer>/index.md`（不建 `spec/app/index.md`，design §1）。
- [ ] `trellis-check.md`、`trellis-implement.md` 第 2 步的 format／analyze 指令依 package 分流（`app` 在 `app/` 內跑）。
- [ ] `ci.yml` 以 paths-filter 分兩半，加 `app` 的 format／analyze／test 與 `always()` 彙總；合併後在 ruleset 設彙總 job 為必要檢查。
- [ ] `orca.yaml` 加入 `app/` 的 setup。
- 測試：
  - prod 身分等於 ADR 0008、dev 每一項都不同；
  - dev 拒絕舊版正式資料路徑；
  - 故意聯網的測試被跳過，解除 tag 後被擋。
- 實測（§7）：
  - dev 與 prod 同時開啟時，身分、鎖、資料目錄各自獨立（Windows）；
  - Android 裝 dev 與 prod 兩個 App。

### 3. `fmp_lints`

- [ ] `app/packages/fmp_lints/`：
  - 十條核心規則，加 `fmp_toast_entry`、`fmp_design_tokens`；
  - 每條都用 `analyzer_testing` 做雙向變異測試。
- [ ] 接線哨兵；CI 加 `dart analyze --fatal-infos`。
- [ ] `riverpod_lint` 接上新插件系統。
- 實測（§7）：`dart analyze` 看得到插件診斷、`flutter analyze` 看不到（#187999），哨兵會紅。

### 4. 平台層

- [ ] `lib/platform/`：`PlatformCapabilities`、目錄規則、單一實例、字型 fallback 提供者；Android 與 Windows 實作，其他平台宣告「沒有」。
- 測試：能力宣告、目錄規則；`fmp_platform_checks` 已在 PR 3 生效。

### 5. drift

- [ ] `appearance_settings`、`installed_plugins`、`plugin_storage`：
  - `PRAGMA foreign_keys = ON`；
  - v1 schema 快照；
  - repository。
- [ ] `TrackKey`（`domain/`）照舊版格式，加測試。
- [x] 探針分支：`isar_community`＋`sqlite3` 共存、16KB 對齊，結論寫進本任務 `research/`（2026-09-29：兩平台共存、全部對齊，`research/isar-sqlite3-coexistence.md`；ADR 0010 已補）。
- 測試：快照一致；設定「使用者值不被新預設蓋掉」（ADR 0011）。

### 6. 設定與 log

- [ ] 設定的 Notifier 模式（外觀組），放在 `lib/settings/`。
- [ ] 第一次用 Riverpod：`main.dart` 包 `ProviderScope`，並在 `app/analysis_options.yaml` 重新開啟 `riverpod_lint` 的 `missing_provider_scope`（PR 3 暫時關閉）。
- [ ] log 門面、遮蔽函式；log 檔：JSON Lines、2MB×3、在 `logs/`。
- 測試：遮蔽，含 stackTrace（ADR 0011 §如何確認）；檔案輪替；壞行略過。

### 7. 錯誤模型

- [ ] sealed `AppError` 十個子類；`ProviderScope` retry 關閉；重試策略的純函數（退避、`Retry-After`、只重試冪等請求）。
- 測試：ADR 0013 §如何確認，M1 可測的部分。

### 8. 網路層

- [ ] API client 與媒體 client、攔截器順序、轉址規則（manifest 網域、最多 5 跳）、網路紀錄。
- [ ] `AuthRequirement` 型別與宣告點。
- [ ] 未捕捉錯誤若是 `AppError`，改走 `log.report` 帶出原因（PR 7 發現）。
- 記錄：冪等只看 HTTP 方法，YouTube innertube 與網易查詢是 POST、照規則不會重試；讓音源標記「語意冪等的 POST」屬 M3 加入這兩個插件時決定（RFC 9110 §9.2.2 允許），B 站的 M1 請求是 GET 不受影響。
- 測試：
  - 媒體請求不帶 Cookie／Authorization；
  - manifest 網域外的請求被拒；
  - 轉址超過 5 跳或出網域會失敗。

### 9. JS 執行環境與插件（拆成 9a、9b、9c 三個 PR）

- **9a** JS 執行環境、宿主 API v1、manifest 解析（安裝檔格式見 prd 擁有者決定 6）、`SourcePlugin` 轉接、從檔案安裝、測試插件；`flutter_js` 實測（含能否在 `flutter test` 內載入 QuickJS）。
- **9b** fixture 錄製與重播 adapter、`checks.json`、契約執行器（放在 `app/test/plugins/contract/`）、CI 步驟。
- **9c** 在 `1morr/fmp-plugins` 建 repo 與 B 站插件（`search`、`resolveStream`），錄一次 fixture；FMP 端無程式碼，或只有文件。

原清單：

- [x] 在 `lib/plugins/` 建 `flutter_js`（9a）：
  - 宿主 API v1 最小集；
  - manifest 驗證；
  - `apiVersion` 相容檢查；
  - 從檔案安裝。
- [x] TypeScript 型別定義（9a）。
- [x] 契約執行器、fixture 格式、`checks.json`（9b，`app/test/plugins/contract/`）。
- [x] `test/fixtures/plugins/test_plugin/`：合成資料、本機音檔（9a）。
- [x] （9c 沒觀察到，移到「9c 留下的後續」）接真實 B 站時觀察：伺服器回不合法的 `Set-Cookie` 是否讓請求變成 `UnexpectedError`（`dio_cookie_manager` 的 `ignoreInvalidCookies` 預設 false；PR 8 檢查提出，沒有重現案例前不改）。
- [x] 建立 `1morr/fmp-plugins`（9c）：
  - `bilibili/` 的 `search`、`resolveStream`；
  - 錄一次 fixture（真實連線，最少操作）。
- 實測（§7）：
  - `flutter_js` 在 Android、Windows 的 Promise、記憶體、啟動成本；
  - 契約執行器能否在 `flutter test` 內載入 QuickJS；決定後，CI 加入契約執行器。
- 測試：
  - 能力與匯出一致；
  - 讀不到其他插件的 storage；
  - fixture 掃描不得有未遮蔽的憑證。

9a 留下的後續：

- [ ] 探測的取捨：插件若無限迴圈地呼叫宿主 API，每次都回應探測，只會一直得到 `NetworkError`、不會被停用（PR 9a 檢查提出）。M3 插件頁若要讓使用者手動停用，一併處理。
- [ ] Android 的跨 isolate 成本：模擬器 debug 下每次宿主呼叫多約 7 ms，不經宿主的 `search` 也比純 Dart 對照慢，差額未查明。有實機時用 profile 模式重量（`integration_test/plugin_runtime_benchmark_test.dart`）。
- [ ] Android 上 prod 的開發入口實機驗證：需要一台沒裝舊版的模擬器或實機（PR 13 或 M9 前）。

9b 留下的後續：

- [ ] 錄製與重播的 adapter 現在在 `app/test/plugins/contract/`；M3 的 App 內開發工具要用時移進 `lib/core/network/`，格式不變。
- [ ] 執行器看不到插件自己吞掉的「網域不在清單」錯誤（網路層照樣不送出），也分不出插件自拋的 `ParseError` 與 DTO 驗證失敗；要看到前者得讓網路層替被拒的請求寫紀錄。
- [ ] 串流候選的網址本身（query 裡的 `access_key` 之類）不在憑證檢查內，現在只查 headers。9c 接 B 站時看要不要加。
- [ ] 9b 審查時有一次 `flutter test` 兩個契約測試檔卡在 loading（編譯階段，20 分鐘無進度），之後 14 次沒重現。CI 若出現同樣的卡住，從 flutter_tools 層查。

9c 留下的後續：

- [x] （遮蔽修正 PR）內建遮蔽名單缺 `hdnts`（Akamai）與 `buvid`（`app/lib/core/redaction/redaction_lists.dart` 的 `_bilibiliSigned`）；官方插件靠 manifest 補上，使用者自寫的插件會漏。
- [x] （遮蔽修正 PR）`Redactor` 只套用第一個符合的 `MediaCdn`（`redactor.dart` 的 `firstOrNull`），插件追加的 CDN 規則蓋不到內建已有的 host；應合併所有符合項的參數。
- [ ] 登入後 `_AuthInterceptor` 以 `headers.addAll` 注入 `Cookie`，會整個蓋掉插件送的匿名 `buvid3`；舊專案是合併。M3 登入任務決定合併或交給插件。
- [ ] B 站插件的 `rateLimit`（併發 2、間隔 300ms）沒有量測依據；`allowedHosts` 外的 PCDN（`szbdyd.com`、直接寫 IP 的節點）會被丟掉，舊專案不限制。M6 媒體 client 接上時一併看。
- [ ] PR 8 的 `ignoreInvalidCookies` 觀察：兩次錄製的回應都沒有 `Set-Cookie`，沒觀察到；留到會發 cookie 的端點（登入）。

PR 10 留下的後續：

- [ ] `app/android/app/src/main/AndroidManifest.xml` 沒有 `INTERNET` 權限（只有 `debug/`、`profile/` 有），release 建置連不了網路；PR 13 處理。
- [ ] 開不起來的串流在換過候選後對應 `Unsupported`，ADR 0013 會顯示成「視為 bug」的通用訊息；CDN 403 落到這裡不貼切，PR 12 做提示時再看。
- [ ] 前瞻開不起來時兩個後端的行為沒有契約案例（Android 會被當成目前這首中斷；Windows 可能卡在 Playing）；前瞻解析比目前這首播完還慢時會多解析一次。M2 補契約案例。
- [ ] 被取代的 `resolveStream` 只丟結果、不取消網路工作（`SourcePlugin` 沒有取消參數）。
- [ ] `.trellis/spec/app/playback/index.md` 的「實機驗證」段與 `verify-on-device` skill 的建置、安裝、`am start` 步驟重複；改成指向 skill（PR 12 動到播放時順手）。
- [ ] 媒體 CDN 的簽名參數目前是整個拿掉；內建名單每變嚴格一次，既有 fixture 就過不了「再遮蔽一次不變」的掃描（遮蔽修正 PR 時手動改了 fmp-plugins 的 24 個網址）。審查建議改成「值換成 `***`」：已遮過的不再誤紅、明文照樣紅。改動是 `_redactMediaUrl` 一行加既有測試期望，M3 插件庫 CI 上線前做。
- [ ] 插件每重新載入一次，`Redactor._mediaCdns` 就多一份相同規則（輸出不受影響，只是多掃）；M3 插件頁的重新載入出現時一併去重。

### 探針：YouTube.js（擁有者決定 3）

- [x] 9 合併後開一個子任務，時限約 2–3 個 session。
- [x] 分支不合併，結論寫進研究檔。
- [x] ADR 0014 補一句結論。

### 10. 播放核心最小集

- [ ] 播放核心：
  - `PlaybackController`；
  - sealed 播放狀態；
  - `AudioBackend` 與 `JustAudioBackend`、`MediaKitBackend`；
  - 兩首、只在記憶體的 `QueueModel`；
  - `StreamResolver` 直接呼叫插件。
- [ ] 前瞻交接：後端只持有「目前＋一個前瞻」。
- 測試：後端契約測試（純規則跑兩個實作與假後端）。
- 實測（§7）：
  - 兩個後端的 gapless 交接；
  - Android 換歌時不釋放音訊焦點。

### 11. `app/` 的 verify-on-device（design §6）

- [ ] 新 skill、`references/android.md`、`references/windows.md`、`references/runtime-state.md`。
- [ ] `app/AGENTS.md` 的驗證段（ADR 0027 §如何確認）。
- 驗證：用新 skill 在兩個平台啟動 dev 版到首頁。

### 12. UI（擁有者決定 2）

- [ ] 主題與字串：
  - `AppTokens`、`AppLayout`；
  - `WindowClass`；
  - 字型 fallback；
  - slang 三語言。
- [ ] `Toaster`、`ToastHost`。
- [ ] 接 slang 時收窄 `AppError.messageArgs` 的型別（目前 `Map<String, Object>`，插件可塞伺服器原文進 UI；PR 7 檢查發現），例如只收數字與已知的具名值。
- [ ] 外殼（兩個導覽項）、搜尋頁、設定頁的外觀組、播放列。
- [ ] 快捷鍵與 F6 三區。
- [ ] 設定頁的「跟隨系統」：`AppearanceSettingsRepository.write` 目前不能把欄位清回 `null`（PR 6 檢查發現），設定頁需要時補上並測試。
- [ ] 字形：`MaterialApp.locale` 帶介面語言（`zh-Hant-TW` 等帶 script 的形式）。Android 不指名字型，英文介面時歌名等漢字可能落到簡中字形（AOSP `fonts.xml` 的 `zh-Hans` 在前，PR 4 推論、未實測）：實測後決定是否在漢字文字上指定 `zh-Hant`。
- 測試：
  - 三語言 key 集合相同；
  - Toast 去重、取代與時長；
  - 全螢幕頁與對話框之上可見；
  - 空白鍵在輸入框只輸入空格；
  - F6 在三區之間移動；
  - 淺色與深色的點擊區、對比度 guideline。
- 實測（§7）：
  - Windows Narrator 下提示不凍結無障礙樹；
  - Windows 繁中字形由正黑體顯示；
  - 兩平台搜尋 B 站並連續播兩首（真實連線，最少操作）。

### 13. 五平台建置與發版 workflow（擁有者決定 4）

- [ ] CI 加入：
  - Linux、macOS、iOS（不簽名）建置；
  - Linux 與 Windows 的整合測試：搜尋→播放、從檔案安裝插件，用測試插件。
- [ ] `default-flavor: dev` 讓 iOS、macOS 建置需要 `dev`／`prod` 兩個 Xcode scheme，這個 PR 補上（PR 2 發現）。
- [ ] `app-release.yml`（只有 `workflow_dispatch`）與 release-please 設定：
  - `app/CHANGELOG.md`；
  - manifest；
  - `dart` 策略。
- [ ] 建立私人的 `1morr/fmp-release-sandbox`，完整跑一次後封存，結果寫進研究檔。
- 測試：ADR 0022 §如何確認中的 workflow 檢查（檔名集合、checksums、舊版更新器相容）。

## 里程碑驗收（13 之後）

- [ ] Android、Windows 端到端操作。
- [ ] 逐項勾 phase2-plan §7，在 PR 描述或研究檔找到每項的實測紀錄。
- [ ] 更新 `milestones.md` 的 M1 狀態與勾選；開 Linux 平台任務。
- [ ] 本任務 `finish`、`archive`。

## 待升級

- `analysis_server_plugin`、`analyzer`、`analyzer_testing` 停在 0.3.18／13.3.0／0.3.2：Flutter 3.47.5 的 `flutter_test` 釘 `test_api 0.7.12`，把 analyzer 限制在 14 以下（PR 3 發現）。Flutter 放寬後三個一起升到最新。

## 風險與回滾點

| 風險 | 處理 |
|---|---|
| QuickJS 無法在 `flutter test` 內載入 | ADR 0015 的退路：契約執行器改用桌面 `integration_test`，CI job 改在 Windows／Linux |
| isar 與 sqlite3 原生庫衝突 | ADR 0010 的退路：legacy import 改成獨立一次性小程式；M5 前決定 |
| `flutter_js` 在 Android 的記憶體或啟動成本過高 | 實測數字交擁有者，必要時另開 ADR 討論引擎 |
| B 站限流或風控擋住錄製 | 錄製只做最少操作；卡住時改用測試插件完成 UI 與播放驗證，B 站部分具名回報 blocker |
| PR 1 的搬家讓 Trellis hook 或舊工作流壞掉 | PR 1 單獨 revert |
