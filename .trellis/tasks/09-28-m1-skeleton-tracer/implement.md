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
- 測試：
  - 媒體請求不帶 Cookie／Authorization；
  - manifest 網域外的請求被拒；
  - 轉址超過 5 跳或出網域會失敗。

### 9. JS 執行環境與插件

- [ ] 在 `lib/plugins/` 建 `flutter_js`：
  - 宿主 API v1 最小集；
  - manifest 驗證；
  - `apiVersion` 相容檢查；
  - 從檔案安裝。
- [ ] TypeScript 型別定義。
- [ ] `packages/plugin_contract/`：契約執行器、fixture 格式、`checks.json`。
- [ ] `test/fixtures/plugins/test_plugin/`：合成資料、本機音檔。
- [ ] 建立 `1morr/fmp-plugins`：
  - `bilibili/` 的 `search`、`resolveStream`；
  - 錄一次 fixture（真實連線，最少操作）。
- 實測（§7）：
  - `flutter_js` 在 Android、Windows 的 Promise、記憶體、啟動成本；
  - 契約執行器能否在 `flutter test` 內載入 QuickJS；決定後，CI 加入契約執行器。
- 測試：
  - 能力與匯出一致；
  - 讀不到其他插件的 storage；
  - fixture 掃描不得有未遮蔽的憑證。

### 探針：YouTube.js（擁有者決定 3）

- [ ] 9 合併後開一個子任務，時限約 2–3 個 session。
- [ ] 分支不合併，結論寫進研究檔。
- [ ] ADR 0014 補一句結論。

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
