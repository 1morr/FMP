# PR 13a：CI 五平台建置與整合測試

M1 PR 13 的前半（2026-10-01 擁有者核准拆成 13a／13b；13b 是發版 workflow 與 sandbox）。
依據：ADR 0015 §決定 9（`app` job 的內容）、父任務 `implement.md` §13、design §5。

## 做什麼

1. **五平台建置**（`.github/workflows/ci.yml`，`app` 分流觸發）：
   - Android、Windows、Linux、macOS、iOS（`--no-codesign`）各一個 job，建 `--flavor prod --release`
     （發出去的是 prod；dev 由整合測試與本機建置涵蓋）。Android 的 release 暫時仍用 debug 簽名，
     正式簽名在 13b。
   - macOS 與 iOS 另建 `--flavor dev`：兩個 Xcode scheme 都是這個 PR 新加的，都要有 CI 守著。
   - 每個新 job 都列進 `CI Result` 的 `needs`；被路徑篩掉而跳過的仍算通過。
   - 舊專案的 job 與 `release.yml` 不動。
2. **Xcode scheme**：`app/ios`、`app/macos` 補 `dev`、`prod` 兩個 scheme 與對應的 build configuration
   （照 Flutter 官方 flavors 文件）；`default-flavor: dev` 讓不帶 `--flavor` 的 iOS／macOS 建置找得到 scheme。
   - 身分照 `app/AGENTS.md` § App 身分的原則：prod 的 bundle identifier 維持 `com.personal.fmp`，
     dev 是 `com.personal.fmp.dev`、顯示名稱「FMP Dev」。
   - 身分表與閘門：比照 `test/identity/` 既有的 Android、Windows 測試，為 iOS／macOS 的 bundle
     identifier 與顯示名稱加測試（含雙向變異），表格加列。
3. **Android 主 manifest 補 `INTERNET` 權限**（PR 10 的後續；現在只有 `debug/`、`profile/` 有，release 連不了網路）。
   `test/identity/android_identity_test.dart` 或同層測試斷言 main manifest 有它。
4. **Linux 與 Windows 的整合測試**（`app/integration_test/`，CI 以 `flutter test integration_test/<檔> -d linux|windows` 跑；Linux 在 xvfb 下）：
   - **從檔案安裝插件**：以 `PluginInstaller` 安裝測試插件的 `.js`，重建容器後從資料庫載入，搜尋得到結果。
   - **搜尋→播放**：在外殼搜尋、點第一首，`PlaybackController` 進入播放並交接到第二首。
   - 插件執行環境（QuickJS 背景 isolate）、安裝、資料庫都用真的；**音訊後端用假的**：CI runner
     沒有音訊裝置，Linux 平台尚未支援（`media_kit_libs_linux` 未加入）。真的後端由
     `integration_test/audio_backend_contract_test.dart` 在實機守。
   - 不連網：零聯網防線照常開著。
   - 既有的 `toast_layering_test.dart` 一起在兩個平台跑。
5. **文件**：`app/AGENTS.md` 的 CI／身分段、`.trellis/spec/app/testing/index.md`（整合測試怎麼寫、CI 怎麼跑）、
   根目錄 `AGENTS.md` 表格中 `ci.yml` 的描述（有新 job 時）；`verify-on-device` 的地雷若有新發現一併補。

## 不做

- 發版 workflow、release-please、簽名、Inno Setup、sandbox（13b）。
- Linux／macOS／iOS 的平台能力與播放後端（各自的平台任務）；這些平台的 App 仍只開「此平台尚未支援」。
- 舊專案 CI 的 libmpv 下載偶發失敗（只觀察到一次，沒有 repro；再出現才處理）。

## 驗收

- [ ] PR 的 CI：五個建置 job、兩個整合測試 job、既有 `app` job 全綠，`CI Result` 綠。
- [ ] 本機：`flutter build apk --flavor prod --release`、`flutter build windows --flavor prod --release` 成功；
      `flutter test integration_test/<新檔> -d windows` 通過（跑完照 `verify-on-device` 重建 dev 產物）。
- [ ] 身分測試涵蓋 iOS／macOS 與 INTERNET 權限，各自有「造違規會紅、無關改動不紅」的變異驗證。
- [ ] 通用驗證：format、build_runner 後沒有實質變動、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`、哨兵。
- [ ] 實機：沒有使用者看得到的改動，不另做實機驗證。prod 建置不執行：Windows prod 的資料目錄是使用者真實的
      `Documents\FMP`，模擬器上有舊版測試資料，都不碰。INTERNET 權限以 `aapt2 dump permissions`（或 `apkanalyzer`）
      檢查 prod release APK。
- [ ] CI 總時長與各 job 時間寫進 PR 描述。
