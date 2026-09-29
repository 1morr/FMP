# `app/` 骨架與 CI 分流（M1 PR 2）

父任務：`../09-28-m1-skeleton-tracer`（design §2、§3、§5；implement「2.」）。

依據：
- ADR 0008 §決定 2–3：App 身分；
- ADR 0009 §決定 7：目錄規則；
- ADR 0015 §決定 3：零聯網；§決定 8：開發版；§決定 9：CI 切分。

## 做什麼

1. **Flutter 專案**：`app/`，Flutter 3.47.5（Dart 3.13.4）。
   - 以 `flutter create --org com.personal --project-name fmp --platforms android,windows,linux,macos,ios app` 為起點。
   - `pubspec.yaml`：
     - 是 pub workspace 根（`workspace:` 先空，PR 3 加 `packages/fmp_lints`）；
     - `flutter: default-flavor: dev`；
     - 依賴只加本 PR 用得到的。
   - 範本 counter app 換成最小的 `MaterialApp`，只顯示 App 名稱與 flavor。UI 在 PR 12 做。
2. **flavor 與 App 身分**：

   | 項目 | prod（與舊版相同，ADR 0008） | dev（ADR 0015 §決定 8） |
   |---|---|---|
   | Android `applicationId` | `com.personal.fmp` | `com.personal.fmp.dev`（`applicationIdSuffix ".dev"`） |
   | Android App 名稱 | `FMP` | `FMP Dev` |
   | Windows AppUserModelID | `com.personal.fmp` | `com.personal.fmp.dev` |
   | Windows 單一實例 mutex | `Local\FMP_MainInstance` | `Local\FMP_MainInstance-dev` |
   | Windows 執行檔名 | `fmp.exe` | `fmp.exe`（flavor 只改身分，不改檔名） |
   | 資料目錄 | ADR 0009 §決定 7 | 同一規則加 `-dev` |

   - Android namespace 維持 `com.personal.fmp`。
   - Android 簽名：本 PR 只用 debug 簽名；release 簽名在 PR 13 接 `key.properties`，照舊版的做法。
   - Windows 怎麼依 flavor 設 AUMID 與 mutex，用 Flutter 3.47.5 官方支援的桌面 flavor 機制。先以 context7 或官方文件查證 `--flavor` 在 Windows 的支援方式，並把查證來源寫進 PR 描述。官方不支援時，改用 CMake 的 `FLUTTER_FLAVOR` 或 `--dart-define`，但 C++ 端要能在建立視窗前拿到值。
   - 單一實例：第二個實例把既有視窗帶到前景後結束，行為照舊版 `windows/runner/main.cpp:12-66`。
   - dev 的標記圖示：本 PR 只改名稱，圖示留到 PR 12。
3. **資料目錄**（`lib/platform/` 最小實作；完整的平台層在 PR 4）：
   - 擁有者 2026-09-29 決定：Windows Portable 版用程式旁的 `userdata/`（dev 為 `userdata-dev/`），不用 ADR 0009 原寫的 `data/`，因為它和 Flutter 的 `data/` 程式資源資料夾同名。
   - 只做「App 資料目錄」這一項能力：Android 私有目錄；Windows 安裝版 `%APPDATA%`、Portable 版程式旁 `data/`；dev 加 `-dev`。
   - **開發版拒絕舊版正式資料位置**：解析出的路徑若等於舊版資料位置或在它底下，直接拋錯。舊版位置要到舊專案 `lib/` 裡查（例如 `Documents\FMP`、舊 Android 私有目錄），寫進 dartdoc 並附檔名與行號。
4. **零聯網兩道防線**（ADR 0015 §決定 3）：
   - `app/dart_test.yaml`：`tags: live: skip:`，並用 preset 解除；
   - `app/test/flutter_test_config.dart`：以 `HttpOverrides.global` 讓建立真實 `HttpClient` 直接拋錯；
   - 測試：一個標 `live` 的測試在裸 `flutter test` 被跳過；以 preset 解除後，它被 `HttpOverrides` 擋下（斷言錯誤訊息）。
5. **測試**：
   - prod 身分的每一項等於上表，dev 的每一項都不同；
   - Android 讀 `build.gradle.kts` 產出的值，或以 Gradle task 檢查；Windows 讀 C++／CMake 設定的常數，方式不拘，但要能在 CI 的 Linux 跑；
   - 開發版拒絕舊版資料位置；
   - 零聯網兩道防線。
6. **`material_ui`**：查 3.47.5 的官方文件，決定 Material 元件的 import 路徑，寫進 `app/AGENTS.md`。
7. **`app/AGENTS.md`**（繁中）：
   - 只寫查不到的契約與有閘門的規則；沒有規則守的不寫；
   - 包含：
     - 驗證段：本 PR 起的指令；ADR 0027 的實機驗證三句（預設重播或測試插件、真實連線的條件、Android 與 Windows 每個使用者可見的 PR），skill 在 PR 11 前尚未提供，照實寫；
     - 身分表；
     - 零聯網；
     - `material_ui`。
8. **spec**：建 `.trellis/spec/app/testing/index.md`（繁中），寫零聯網與測試分層；不建 `.trellis/spec/app/index.md`（父任務 design §1）。
9. **CI**（`.github/workflows/ci.yml`）：
   - `dorny/paths-filter@v4`（釘 commit SHA，照現有 action 的寫法）；
   - 觸發：`app/**` 與 `.github/**` 跑 `app` 的 job，`app/` 以外有變動就跑舊專案的三個 job；
   - 舊 job 內容不動；
   - `app` job：`dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`，Flutter 3.47.5；
   - 最後一個 `always()` 彙總 job：needs 全部 job，被跳過的算通過，失敗或取消的算失敗；
   - 檔頭註解改寫：說明為什麼現在有路徑過濾，以及為什麼文件變更仍會跑舊 job。
10. **`orca.yaml`**：setup 加上 `app/` 的 `flutter pub get`（本 PR 還沒有 slang）。每行都要是 cmd 與 bash 共通的單一指令（照現有註解）。
11. **Trellis 本機 agent 檔**：`trellis-check.md`、`trellis-implement.md` 第 2 步的 format／analyze 指令依 package 分流：
    - `legacy` 維持現狀；
    - `app` 在 `app/` 內跑 `dart format --output=none --set-exit-if-changed .` 與 `flutter analyze`。
12. **根目錄 `AGENTS.md`**：地圖補上兩列：
    - `app/` 一列（規則讀 `app/AGENTS.md`）；
    - `.github/workflows/` 改寫成「`ci.yml` 依路徑分流兩個專案；`release.yml` 發舊專案」。
    
    只寫合併後為真的事。

## 驗收

- [ ] 在 `app/` 內 `flutter analyze` 零問題、`flutter test` 全綠；零聯網兩道防線的測試存在並通過。
- [ ] 舊專案 `flutter test --exclude-tags live` 在 Flutter 3.47.5 下仍全綠（本機）。
- [ ] Windows：
  - `flutter build windows --flavor dev` 與 `--flavor prod` 都能建置；
  - 同時開啟時兩個都在，各自的 AUMID 不同（主對話驗證）；
  - 同一 flavor 開第二次，會把第一個帶到前景。
- [ ] Android：`flutter build apk --flavor dev --debug` 與 `--flavor prod --debug`；兩個 App 能同時安裝在模擬器（主對話驗證）。
- [ ] PR 的 CI：
  - `app` job 與舊 job 都有跑（這個 PR 同時改到 `app/` 和根目錄）；
  - 彙總 job 綠；
  - 再以一個只改 `app/` 的 commit 驗證舊 job 被跳過、彙總仍綠（可在 PR 內做）。
