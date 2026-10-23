# 啟動流程：找舊資料、dev 入口、進度與失敗頁、換上、結果對話框

## 目標

M5 PR 6（上層 `implement.md` § 6；design §2.2、§3.1、§4.1 第 1 步、§7.1–§7.3、§8.1、§9「首次啟動的中途失敗」「啟動流程」「dev 入口」「lint」）：把 PR 1–5 接起來。新 App 第一次啟動時（資料目錄沒有 `fmp.db`、找得到舊資料庫）自動匯入：進度畫面 → 讀、轉、寫暫存庫、驗證 → 暫存庫改名成 `fmp.db` → 寫憑證 → 正式 App 起來後顯示一次結果對話框。失敗頁有「重試」「匯出診斷」「以空白資料啟動」。`DatabaseErrorApp` 補「重試」與「匯出診斷」。dev flavor 以 `--fmp-legacy-dir` 讀副本。

**這是第一個使用者看得到的 M5 PR**：Android 模擬器與 Windows 都要實機驗證（`verify-on-device`）。

範圍、做法都已由擁有者核准（2026-10-23，design §11 第 7、8 條）。計畫沒涵蓋、會改變行為、範圍或對外介面的決定，停下回報，不自行拍板。

## 現況（以程式碼為準）

- `lib/main.dart`（148 行）：解析資料目錄（`platform.dataDirectory?.resolve()`，:43）→ Log → `openAppDatabase(directory)`（:86，失敗時 `runApp(DatabaseErrorApp(...))`，:94）→ `runApp(appProviderScope(overrides: [...]))`（:118）。dev 入口的先例：`devPluginPath(flavor, arguments, Platform.environment)`（`lib/plugins/install/dev_plugin_entry.dart`：`--fmp-dev-plugin=`／`FMP_DEV_PLUGIN`，prod 回 null，有 `prod reads neither …` 的測試）。
- `lib/data/database/open_app_database.dart`：`databaseFileName = 'fmp.db'`（:10）。
- `lib/app/database_error_app.dart`：`DatabaseErrorApp`，docstring 說重試與匯出診斷隨 M5 加。
- `lib/ui/plugins/plugin_onboarding.dart`：首次引導（安裝音源，ADR 0030 §12）。
- PR 1–5 已在 `main`：
  - `LegacyDatabaseReader(log:).read(File, Directory)`（log 是回呼 `LegacyReadLog`，接到 `Log`）、沒有設定列就讀取失敗；
  - `LegacyConverter.convert(snapshot, source:, now:, credentials:, importOutputDevice:)` → `LegacyConversion{bundle, credentials}`；
  - `StagingImport(log).write(bundle, file, now)`／`verify(...)`，失敗拋 `LegacyImportFailed(step, reason)`（`LegacyImportStep` 目前只有 `write`、`verify`）；
  - `LegacyImportsRepository`（`latestUnacknowledged`、`acknowledge`、`hasAny`）、`ImportSummary`（`collections` 的 read／written／skipped／notes、`unimportedSettings`、`reloginPlatforms`）；
  - `LegacyCredentialReader`（Windows、Android、`NoLegacyCredentialReader`）、`legacyCredentialKeys`、`CredentialStore.writeImported`。
- lint：`lib/legacy_import` 在 `sealedDirectories`；`restrictedImports` 的先例是 `lib/platform/cache_directory` 只准 `lib/main.dart`（`app/packages/fmp_lints/lib/src/rules/layer_imports.dart:118-138`）。
- 上層 `implement.md`「留下的後續」PR 1–5 列了本 PR 要接的事：讀取器 log 接 `Log`、換上後才失敗的憑證要補記進 `summary_json`、`accountWithoutId` 等略過理由與 `unimportedSettings` 的翻譯、Windows 才 `importOutputDevice`、Android 實機確認讀過之後 `shared_prefs` 不變、`Isar.open` 失敗後重試撞名（遇到才補關）。

## 需求

1. **lint**：`lib/legacy_import` 從 `sealedDirectories` 移到 `restrictedImports`，只准 `lib/main.dart` 從外面 import；目錄內部互相 import 照舊。雙向變異案例（`lib/main.dart` 可以、`lib/app/x.dart` 不行；改無關的格式不紅），`tool/lint_sentinel.dart` 加違規行。
2. **`LegacyImport` 介面**（`lib/app/legacy_import.dart`，design §2.2）：`locate()`、`stage(source, {progress})`、`writeCredentials(staged, {loggedInPluginIds})`。**`stageBackup` 不在這個 PR**（PR 7 有了呼叫端才加）。`LegacyStaged` 帶暫存庫路徑、記憶體裡的憑證（`toString` 不帶值）與摘要；`LegacyImportStep` 給進度畫面（讀取舊資料、轉換、寫入、驗證、完成）。provider 由 `main.dart` override；`lib/app` 與 UI 只認介面。
3. **`LegacyDataLocator`**（`lib/platform/legacy_data/`，design §4.1 第 1 步、§4.3）：
   - prod Windows：`<文件>\FMP\fmp_database.isar`，其次 `<文件>\fmp_database.isar`；憑證目錄是 application support（新舊 App 同一個）。
   - prod Android：`<app_flutter>/FMP/fmp_database.isar`，其次 `<app_flutter>/fmp_database.isar`；舊 prefs 檔 `<資料>/shared_prefs/FlutterSecureStorage.xml`。
   - dev：只看 `--fmp-legacy-dir`（第 4 條）；Windows 的憑證檔是那個資料夾裡可選的 `flutter_secure_storage.dat`；dev 的 Android 不讀憑證（`NoLegacyCredentialReader`）。
   - 找到的條件只是「舊資料庫檔存在」；壞檔走失敗頁（讀取器已會拒絕沒有設定列的庫）。
4. **dev 入口 `--fmp-legacy-dir=<資料夾>`**（design §8.1）：只在 dev 讀（參數優先，其次 `FMP_LEGACY_DIR`），prod 一律忽略，同 `devPluginPath`。資料夾等於或位於真實的舊資料位置（`<文件>\FMP`、`%APPDATA%\com.personal\fmp`、Android 的 `com.personal.fmp` 沙盒）時拒絕。閘門：prod 不讀參數與環境變數；真實位置被拒。
5. **`LegacyImporter`**（`lib/legacy_import/`，實作 `LegacyImport`）：`stage` = 讀舊庫 → 讀舊憑證 → 轉換（Windows 才 `importOutputDevice`）→ `StagingImport.write`＋`verify`，暫存檔在 `<資料目錄>/legacy-import/staging-<UTC>.db`；每一步失敗都轉成 `LegacyImportFailed`（擴充 `LegacyImportStep`：`read`、`convert`、`swap`、`credentials`）。`writeCredentials`：只寫 `loggedInPluginIds` 以外的平台，經 `CredentialStore.writeImported`；寫失敗的平台補記進那一列 `legacy_imports.summary_json` 的 `reloginPlatforms`（`LegacyImportsRepository` 加方法），回傳失敗的集合。讀取器的 log 接 `Log`（tag `legacy-import`）。
6. **`main()`**（design §3.1）：
   - 解析資料目錄、Log 之後，清掉 `legacy-import/` 的殘留（工作目錄、暫存檔）。
   - `fmp.db` 存在 → 照舊。不存在且 `locate()` 找到 → `runApp(LegacyImportApp)`：進度 → `stage()` → 成功：暫存庫 rename 成 `fmp.db`（同一個目錄）→ `writeCredentials()`（首次啟動沒有已登入的平台）→ 開庫 → `runApp(FmpApp)`。rename 失敗刪暫存、走失敗頁，什麼都沒寫。
   - 憑證在 rename 之後才寫（design §3.1 的理由），而且在 `CredentialStore` 載入之前。
7. **`LegacyImportApp`**（design §7.1、§7.2，同 `DatabaseErrorApp` 的獨立小 App，語言與主題跟隨系統）：五個步驟的清單；不可取消。失敗頁：哪一步、原因一句話＋「重試」（再跑 `stage()`）、「匯出診斷」（檔案對話框存文字檔：錯誤、步驟、各 collection 的筆數，經 `Redactor`，不含歌單名稱與憑證；連同 log 檔）、「以空白資料啟動」（建空庫照舊啟動；之後有 `fmp.db` 就不再自動匯入）；說明「舊資料沒有被改動，之後可以在設定頁再匯入」。
8. **`DatabaseErrorApp`**：加「重試」（重新跑開庫）與「匯出診斷」，共用第 7 條的匯出。
9. **結果對話框**（design §7.3）：正式 App 起來後，`legacy_imports` 有未看過的一列時顯示一次：匯入的筆數（歌單、曲目、歷史、電台、帳號）、需要重新登入的平台、未匯入的設定（`unimportedSettings`，每個 id 一條翻譯）、轉成本機歌單的平台歌單數（`notes` 的 `remoteNotRecognized`／`duplicateRemote`）；參照到未安裝插件時「安裝音源」按鈕（開首次引導）；「知道了」設 `acknowledged`。
10. **文案**：`lib/i18n/` 三個語言（zh-TW、zh-CN、en），沿用既有元件與版面，不新增頁面。
11. **文件**：`app/AGENTS.md` § 舊資料匯入（啟動流程、lint 例外、dev 入口）；verify-on-device 的 `references/runtime-state.md` 加 `--fmp-legacy-dir` 的帶法（Windows：直接給資料夾；Android：`adb push` 到 `/data/local/tmp` 再 `run-as com.personal.fmp.dev cp` 進 `files/legacy-copy/`，參數給那個路徑）。
12. **測試**（design §9）：
    - 首次啟動的中途失敗：在讀、轉、寫入、驗證、rename、寫憑證各步注入例外。rename 之前失敗 → 沒有 `fmp.db`、沒有暫存檔、舊檔不變；寫憑證失敗 → `fmp.db` 在、該平台補記為需要重新登入、`CredentialStore` 載入後是未登入、secure storage 沒有殘留。
    - widget：`LegacyImportApp` 的進度、失敗頁三個按鈕；空白啟動後不再自動匯入；結果對話框只出現一次、「安裝音源」開引導、「知道了」之後不再出現；`DatabaseErrorApp` 的兩個新按鈕。
    - dev 入口與 locator：prod 不讀；真實位置被拒；Windows／Android 的候選順序（路徑注入）。
    - lint 的雙向變異。
13. **實機驗證**（`verify-on-device`，回報寫平台、模式與請求）：
    - 合成舊庫：`dart run tool/legacy_fixture.dart <暫存目錄>/legacy-copy`；Windows 另以 `CryptProtectData` 做一份**假 cookie** 的 `flutter_secure_storage.dat`（寫個一次性腳本放 `<暫存目錄>`，不進 repo）。
    - Windows dev：**先備份 `userdata-dev`**，清空讓 `fmp.db` 不存在 → 以 `--fmp-legacy-dir` 啟動 → 看進度、結果對話框（帳號是假的，**不要裝插件也不要觸發任何網路請求**）→ 「知道了」→ 重開不再出現；做一次失敗頁（例如給一個壞的 `fmp_database.isar`）試三個按鈕。驗完還原 `userdata-dev`。
    - Android 模擬器 dev（`--flavor dev --no-uninstall` 的規矩照 skill；**不碰 `com.personal.fmp`、不裝 prod**）：清 dev 的資料 → 推合成舊庫 → 帶參數啟動 → 進度、結果對話框、首頁資料。
    - 只用合成資料，重播模式，不連網。

## 不做

設定頁的「從舊版匯入…」、`replaceWithImport`、舊 JSON 備份讀取器、`stageBackup`、設定頁的提示（PR 7）。**不讀擁有者的真實舊資料或憑證**（真實資料的驗收在 PR 7 之後，由主對話做）。

## 驗收

- 測試全綠；`dart run build_runner build --delete-conflicting-outputs` 與 `dart run slang` 後沒有實質變動、`dart format --output=none --set-exit-if-changed lib test tool integration_test`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`、`dart run tool/lint_sentinel.dart`、`cd packages/fmp_lints && dart test`。
- 兩平台的實機驗證照第 13 條，回報附觀察（log 行、語意樹節點；截圖存暫存目錄、不含個人資訊）。
- 回報：改了哪些檔、介面形狀、每一步失敗時的狀態、實機驗證的結果與略過的步驟、計畫沒涵蓋而做了判斷的地方。
