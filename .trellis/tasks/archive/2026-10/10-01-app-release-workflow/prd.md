# PR 13b：發版 workflow 與 sandbox 實跑

M1 PR 13 的後半（2026-10-01 擁有者核准拆分；13a 是 CI 建置與整合測試，#192 已合併）。
依據：ADR 0022 §決定 1、3、4 與 §如何確認的 workflow 測試；父任務擁有者決定 4；design §5。

## 做什麼

1. **release-please**（manifest 模式、`dart` 策略，只管 `app/`）：
   - repo 根的 `release-please-config.json`、`.release-please-manifest.json`；`app/CHANGELOG.md` 由它產生。
   - 第一版以 `Release-As: 2.0.0` 指定（ADR 0022 §決定 1）；設 `bootstrap-sha`（或等效）讓它不去掃 `app/` 出現以前的整段歷史。
     選項以 release-please 官方文件為準（ADR 0022 §之後要注意）。
   - `app/test/` 加「`app/pubspec.yaml` 版本等於 manifest」測試（ADR 0022 §決定 1 的替代；舊專案的 `pubspec_version_test` 不動）。
2. **`.github/workflows/app-release.yml`**：**只有 `workflow_dispatch`**（擁有者決定 4，M9 才開自動觸發）。
   - 同一個 workflow：release-please → 輸出為否就停 → 從 tag 算 versionCode（`major*1000000 + minor*1000 + patch`）→
     建置 → 驗證 → 上傳 asset 並轉為正式發布。一律 `--flavor prod`。
   - 發佈物照 ADR 0022 §決定 3：Android 四個 APK（`arm64-v8a`、`armeabi-v7a`、`x86_64`、`universal`）；
     Windows `fmp-v{版本}-windows-installer.exe`（Inno Setup，AppId 沿用舊版 `BAF6CE8D-E1C8-4C29-AE0B-EDE98D5F8FAA`，ADR 0008）與
     `fmp-v{版本}-windows.zip`（內容就是完整程式目錄）；`fmp-v{版本}-checksums.sha256`；`fmp-latest-*` 別名與版本化檔逐位元相同。
     Linux、macOS 的發佈物由各自的平台任務加入，這裡不做。
   - Android 簽名：`app/android/app/build.gradle.kts` 接 release 簽名（secrets 名稱沿用舊 `release.yml`：`KEYSTORE_BASE64`、
     `KEYSTORE_PASSWORD`、`KEY_PASSWORD`、`KEY_ALIAS`），缺 secret 時 release 建置失敗並說缺哪個；本機與 CI 的非發版建置維持 debug 簽名。
   - Inno Setup 的做法以舊 `release.yml` 為參考（舊版用 `inno_bundle`，含 AppUserModelID 修補），選擇與理由寫進 PR 描述；
     新 App 的 AppUserModelID 是 `com.personal.fmp`（`app/AGENTS.md` § App 身分）。
   - **verify job**（ADR 0022 §如何確認）：檔名集合、checksums 與每個檔一致、別名與版本化檔逐位元相同、APK 的
     versionName／versionCode 與 applicationId、PE 標頭、**舊版更新器相容**——以舊版 `lib/services/update/update_service.dart`
     的選檔 regex 與 checksums 解析規則跑本次產物。舊版會在切換 PR 刪除，所以規則移植到 `app/tool/`（或 `app/test/`），
     註明來源檔與行；移植本身要有測試對著舊版的已知檔名案例。
3. **workflow 測試**（`app/test/workflows/` 或同等位置，讀 `../.github/workflows/app-release.yml`）：
   - 觸發只有 `workflow_dispatch`；
   - release-please 輸出為否時建置 job 不跑；
   - 一律 `--flavor prod`；發佈物檔名集合與 ADR 0022 §決定 3 一致。
   參考舊專案 `test/workflows/release_workflow_test.dart`、`release_assets_verification_test.dart` 的做法；靜態規則要在測試檔內做雙向變異驗證。
4. **sandbox 實跑**（擁有者決定 4）：
   - 建私人 repo `1morr/fmp-release-sandbox`，推入本分支內容；sandbox 專屬的一個 commit 加 push 觸發。
   - 以臨時產生的 keystore 設 secrets（不進任何 repo、用完刪檔）；repo 設定允許 Actions 建 PR。
   - 完整跑一次：release-please 開發版 PR → 合併 → 建置、verify、正式發布；下載發佈物核對檔名、checksums、APK 簽名是臨時金鑰。
   - 結果（run 連結、各 job 時間、發佈物清單、遇到的問題）寫進本任務 `research/sandbox-run.md`，然後封存 sandbox（archive）。
5. **文件**：`app/AGENTS.md`（發版契約中查不到的部分）、根 `AGENTS.md` 的 `.github/workflows/` 那列、`.trellis/spec/app/` 需要時。

## 不做

- 在 FMP 觸發 `app-release.yml`（重寫期間不發版）；開 `main` 的自動觸發（M9）。
- App 內更新模組、`fmp_updater.exe`、平台能力 `appUpdate`（之後的里程碑）。
- Linux AppImage、macOS zip（平台任務）。
- 舊專案的 `release.yml` 與其測試。

## 驗收

- [ ] sandbox 的完整一次發版成功，研究檔有 run 連結與發佈物核對結果；sandbox 已封存。
- [ ] FMP 的 `app-release.yml` 只有 `workflow_dispatch`，由測試守著（含雙向變異）。
- [ ] 舊版更新器相容檢查在 verify job 內跑過，移植的規則有對著舊版已知案例的測試。
- [ ] 通用驗證：format、build_runner＋slang 無實質變動、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`、哨兵；actionlint。
- [ ] 本機 `flutter build apk --flavor prod --release`（沒有 key.properties 時仍用 debug 簽名）成功；不安裝、不執行 prod 建置。
- [ ] 臨時 keystore 沒有進任何 commit 或 log；PR 描述與研究檔不含金鑰內容或個人路徑。
