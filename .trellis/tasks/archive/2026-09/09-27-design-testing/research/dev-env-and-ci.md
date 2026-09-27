# 研究：開發版／正式版分離、CI 矩陣與測試比例

> 對應 `.trellis/tasks/09-27-design-testing` 研究第 4、5、6 點：Flutter
> flavor 機制（尤其 Windows／Linux 現況）、GitHub Actions 費用與
> iOS／Linux 建置需求、單一 repo 兩個 Flutter 專案的 CI 路徑過濾、
> 單元／widget／整合測試比例的官方指引、golden test 是否值得採用。
> 查證方式：Flutter 官方文件（WebFetch）、GitHub 官方文件與第三方
> 定價站交叉核對（WebSearch）、repo 內 `.github/workflows/ci.yml`
> 原始碼直讀。查不到的一律寫「查不到」，推論一律標「推測」。
> 查證時間 2026-09-27。

---

## 第 4 點：開發版與正式版分離

### 重要前提修正：Windows／Linux 現在都有官方 flavor 支援

任務原始描述預設「Windows 過去沒有官方 flavor 支援」，這個前提
**已經過時**。查證結果：

- **Windows**：官方文件明講「Windows 的內建 flavor 支援需要
  **Flutter 3.47 或以後**」
  （<https://docs.flutter.dev/deployment/flavors-windows>）。
- **Linux**：官方文件同樣要求 **Flutter 3.47 或以後**
  （<https://docs.flutter.dev/deployment/flavors-linux>）。
- FMP 的 `ci.yml` 目前釘的版本是 `FLUTTER_VERSION: '3.47.1'`
  （`.github/workflows/ci.yml:28`）——**剛好在支援門檻之上**，`app/`
  可以直接用官方 `--flavor` 機制，不需要任何 `--dart-define` 式的
  手刻繞路方案。

### 機制與 FMP 需要的四項隔離：App 身分、資料目錄、單一實例、視窗標題

Windows 與 Linux 的機制幾乎一致，都是把 flavor 名稱寫進
`generated_config.cmake` 的 `FLUTTER_APP_FLAVOR`（在
`add_subdirectory(${FLUTTER_MANAGED_DIR})` **之後**才可見，寫在
之前的 `if(DEFINED FLUTTER_APP_FLAVOR)` 判斷會被靜默略過，兩個
平台的官方文件都特別提醒這個順序陷阱）。建置輸出會落在各自的
flavor 子目錄（例如 `build/windows/<arch>/staging/runner/Release/`、
`build/linux/<arch>/staging/release/bundle/`），Dart 端可讀到
`appFlavor` 常數。

逐項對照 FMP 的需求（沿用 ADR 0008 決定 3「開發版另用身分，與正式版
分開」）：

| 需求 | Windows 做法 | Linux 做法 |
|---|---|---|
| App 身分（AppUserModelID／類似識別） | 官方文件本身**沒有涵蓋** AppUserModelID 這類識別碼的逐 flavor 設定，只示範視窗標題／圖示／`FileDescription`／`ProductName`（`windows/runner/CMakeLists.txt` 用 `configure_file` 產生 `main.cpp`／`Runner.rc` 的 `.in` 樣板，依 `FLUTTER_APP_FLAVOR` 切換字串）。FMP 現有 `windows/runner/main.cpp:43` 寫死 `com.personal.fmp` 這個 AppUserModelID，要讓開發版另用身分，需要**在同一份 `.in` 樣板機制內，額外把 AppUserModelID 字串也做成依 flavor 切換的變數**——這是文件沒有直接示範、但同一套「樣板 + CMake 變數替換」機制天然可以延伸支援的用法，屬於**推測**：官方沒有反例說「不能」，但也沒有把 AppUserModelID 列為官方支援項目之一，落地時要自己加、自己測。 | Linux 的圖示不內嵌在執行檔，來自 `.desktop` 檔與圖示主題，官方文件建議透過打包格式（Snap／Flatpak／Debian）分流，這代表 Linux 上的「App 身分」更多是打包層級的事，不是像 Windows 那樣有一個單一「AppUserModelID」欄位。 |
| 資料目錄 | 不是 flavor 機制直接管的範圍；FMP 現有資料目錄邏輯（通常經 `path_provider` 取得使用者資料夾）**需要自己依 `appFlavor` 值組出不同的子路徑**，例如正式版用 `com.personal.fmp`、開發版用 `com.personal.fmp.dev` 當作資料夾名稱的一部分。 | 同左，`appFlavor` 常數可讀到，路徑組合邏輯要自己寫。 |
| 單一實例（single-instance）互斥鎖 | FMP 若原本用具名 mutex／window class 判斷「是否已有一個實例在跑」，這個名稱字串同樣要依 `appFlavor` 加後綴，讓開發版與正式版的互斥鎖不互相干擾——**這部分官方文件完全沒有涵蓋**（不屬於 flavor 機制本身，是 FMP 自己的單例邏輯要接上 `appFlavor`），標記為需要 `implement.md` 階段自行設計。 | 同左。 |
| 視窗標題 | 官方文件直接示範：改 `windows/runner/CMakeLists.txt` 在 `if(FLUTTER_APP_FLAVOR STREQUAL "staging")` 分支設 `WINDOW_TITLE`，透過 `.in` 樣板注入 `main.cpp`。 | 官方文件示範用 `add_definitions(-DFLUTTER_APP_FLAVOR="...")` 把 flavor 字串傳進 C++ 端的 `my_application.cc`，用 `#ifdef`／`g_strcmp0` 判斷分支設標題。 |

**結論**：Flutter 官方 flavor 機制解決的是「建置輸出隔離」與「視窗
標題／圖示這類展示層」的部分，FMP 真正在意的「App 身分識別
（AppUserModelID）、資料目錄、single-instance 互斥鎖」三項**都不是
flavor 機制原生涵蓋的範圍，而是要在同一個 `appFlavor` 常數／
`FLUTTER_APP_FLAVOR` CMake 變數的基礎上，自己把這三個字串／路徑做成
依 flavor 切換**——**flavor 機制提供的是「一個可靠的、建置期就決定
好的字串（`appFlavor`）」，FMP 自己的程式碼要負責「拿這個字串去組出
App 身分、資料目錄、mutex 名稱」，這件事本身沒有官方文件可以照抄，
需要在 `design.md`／`implement.md` 階段設計。

### Android

Android 的官方 flavor 機制（`productFlavors`、
`applicationIdSuffix`）是最成熟、行之有年的方案，**本研究未重新查證
細節**（沿用先前研究結論：Android 用 `applicationIdSuffix` 可以讓
開發版與正式版是完全不同的 `applicationId`，天生就有獨立的資料目錄
與獨立安裝，Android 系統層級保證兩者不會互相干擾單例——這點是
Android 平台本身的沙盒機制決定的，不需要 FMP 自己實作單例互斥判斷）。

---

## 第 5 點：CI 矩陣與成本

### GitHub Actions 對公開 repo 免費、無實質分鐘數上限

- 官方文件確認：公開 repo 使用標準 GitHub-hosted runner（含
  Linux／Windows／macOS）完全免費，沒有分鐘數上限，只受一般的
  合理使用政策約束（來源：GitHub 官方帳單文件
  <https://docs.github.com/billing/managing-billing-for-github-actions/about-billing-for-github-actions>，
  經 WebSearch 摘要交叉核對多個第三方定價站的說法一致）。
- 分鐘數配額與 OS 倍率（Linux 1x／Windows 2x／macOS 10x）**只影響
  私有 repo**，FMP（`1morr/FMP`）是公開 repo，這點對 FMP 不構成
  限制。
- 2026 年的計費調整（2026-01-01 生效的降價、`self-hosted` runner
  收費一度宣布又在 48 小時內撤回等變動）**都明確排除公開 repo**——
  多個來源一致確認「公開 repo 的標準／self-hosted runner 使用維持
  免費」。這部分屬於第三方站台的整理與 GitHub 官方文件的交叉比對，
  非單一權威來源逐字引用，但方向一致，可信度高。

**結論**：FMP 在 CI 矩陣設計上**不需要顧慮 runner 分鐘數費用**，可以
放心加入 macOS（跑 iOS 建置）與額外的 Linux 建置 job，不必為了省
分鐘數而犧牲涵蓋範圍。

### iOS 建置與 Linux 建置需求

- `flutter build ios --no-codesign` 需要在 `macos-latest` runner 上
  跑（iOS 建置工具鏈只存在於 macOS，這是 Xcode 的限制，非 GitHub
  Actions 特有）。可以額外用 `--config-only` 只產生 Xcode 專案而不
  真正編譯，用於更輕量的「專案設定正確性」檢查；若要更完整驗證，
  搭配 iOS Simulator（`xcrun simctl` 或 `flutter test -d
  <simulator-id>`）跑 `integration_test`（見下方第 6 點的桌面／
  模擬器支援現況）。
- Linux 建置需要 GTK 開發套件（`libgtk-3-dev` 等，Flutter 官方
  `flutter build linux` 的前置需求），**本研究沿用先前已確認的
  結論、本次未重新逐條查證套件清單**，落地時建議直接抄 Flutter
  官方 Linux 桌面設定文件當下列出的套件清單，而非憑記憶列舉，
  避免版本間套件名稱變動（例如 GTK3 與 GTK4 過渡期的套件名稱
  差異）。

### CI 如何只跑「被改到的那個 Flutter 專案」——路徑過濾設計

**先重新檢視舊 `ci.yml` 的「不做路徑過濾」理由是否仍然成立**：

`.github/workflows/ci.yml:3-7` 原文（逐字）：

> No path filter. Markdown carries rules that tests enforce -- the
> agent instruction files most of all -- so a prose-only commit is
> exactly the one that must not skip `validate`. `paths-ignore` is
> trigger-level and cannot skip only the build jobs; measured run
> time is 23 minutes total (validate 7, Android 6, Windows 10),
> which is not worth a changed-files job to avoid.

這段推理成立的前提是「**單一 Flutter 專案**」：`validate`／
Android／Windows 三個 job 全部針對同一份程式碼，唯一要回答的問題是
「這次改動要不要跑 CI」，答案是「除非確定完全不影響任何被測試強制
的規則，否則都要跑」——純文件改動（尤其是 agent 指令檔，它們本身
承載被測試強制執行的規則）沒有這種確定性，所以不排除。**這個結論
不變**，`app/` 加入後，「純 markdown 改動要不要跳過所有 CI」的答案
仍然是不要。

但這個舊理由**沒有回答、也不需要回答**一個新問題：一旦 repo 裡有
**兩個獨立的 Flutter 專案**（根目錄舊專案＋`app/`），**改動只涉及
其中一個專案時，另一個專案的 job 該不該跑？** 這是舊理由誕生時
（單一專案）根本不存在的情境，不能用「23 分鐘不值得」這句話簡單
帶過——因為現在的問題不是「省 CI 分鐘數」，而是「兩個專案的 CI
邏輯已經不同（不同的 `pubspec.yaml`、不同的 lint 設定、`app/`
之後會有 `analysis_server_plugin` 而舊專案不會），把它們**混在
同一個 job 矩陣裡本身就會讓失敗原因難以歸因**（例如 `app/` 的 lint
regression 會被誤讀成整個 repo 出問題）。

**建議**：對「兩個專案之間」做路徑過濾（`app/` 變動只跑 `app/` 的
job；根目錄變動只跑根目錄舊專案的 job；`.github/workflows/`／
repo 層級設定檔變動兩者都跑），但**維持「不對 markdown／文件類
變動做排除」的舊原則**——也就是說路徑過濾的切分軸是「這是哪個
專案的程式碼」，不是「這是不是程式碼」。標準做法：

- `dorny/paths-filter`（GitHub Marketplace 上維護活躍的路徑過濾
  action，本研究沿用先前查證、本次未重新確認其最新版本號，落地
  時建議直接查 <https://github.com/dorny/paths-filter> 的 releases
  頁面取得當下最新版本並用 commit SHA pin，與 FMP 現有 `ci.yml`
  已經對 `actions/checkout` 採用 commit SHA pin 的慣例一致）在
  一個獨立的 `changes` job 裡宣告兩組路徑過濾規則（`app/**`
  一組、根目錄舊專案的路徑一組，兩者互斥），下游的 `validate-app`／
  `validate-legacy` 等 job 用 `if:
  needs.changes.outputs.app == 'true'` 之類的條件決定要不要跑；
  用一個 `always()` 的彙總 job 把所有條件 job 的結果收斂成單一
  必要狀態檢查（branch protection 只認一個 job 名稱時常見的模式），
  避免「被跳過的 job」被 GitHub 誤判為「必要檢查未通過」。
- 這個 `changes`／彙總 job 的寫法屬於社群廣泛使用的標準
  monorepo 模式，非 FMP 特有設計，落地時可直接抄 `dorny/paths-filter`
  官方 README 的範例。

---

## 第 6 點：測試比例與 golden test

### 官方對單元／widget／整合測試比例沒有給數字

Flutter 官方測試總覽頁（<https://docs.flutter.dev/testing/overview>，
2026-09-27 查證）明講不給比例，只給定性權衡：

> "Generally speaking, a well-tested app has many unit and widget
> tests, tracked by code coverage, plus enough integration tests to
> cover all the important use cases."

權衡表（原文逐項對照）：

| | 單元測試 | Widget 測試 | 整合測試 |
|---|---|---|---|
| 信心程度 | 低 | 較高 | 最高 |
| 維護成本 | 低 | 較高 | 最高 |
| 依賴數量 | 少 | 較多 | 最多 |
| 執行速度 | 快 | 快 | 慢 |

**結論**：FMP 要採用的具體比例（例如「每個 service 至少 N 個單元
測試」「每個關鍵使用者流程一個整合測試」）**是團隊／擁有者的選擇，
不是 Flutter 官方的硬性規定**——這點應該列入最終報告的待決策清單，
而不是本研究替擁有者下決定。可以參考的方向：官方的建議精神是
「單元＋widget 測試盡量多、用 code coverage 追蹤；整合測試只挑
『重要使用情境』，不要求全覆蓋」。

### `integration_test` 套件桌面支援現況（2026-09 官方文件）

- 官方 <https://docs.flutter.dev/testing/integration-tests>
  （頁面更新時間 2026-07-31，對應 Flutter 3.47 世代文件）確認
  Windows／macOS／Linux 桌面平台都是**第一方支援**，用法是在
  專案根目錄跑 `flutter test integration_test/app_test.dart`，
  若跳出裝置選擇提示就選桌面平台；也支援 `flutter test
  integration_test -d <platform>` 直接指定裝置，不需互動選擇。
- **限制**：`integration_test` 無法自動化「原生系統 UI」——作業系統
  層級的權限對話框、通知、原生元件——這點官方文件與套件測試文件
  （<https://docs.flutter.dev/testing/testing-plugins>）都明確
  說明。若 FMP 需要測到原生對話框層級的互動，**Patrol** 套件是
  常見的擴充方案，但 Patrol **目前只支援 Android／iOS／macOS／
  web，不支援 Windows／Linux**——這代表 FMP 在 Windows／Linux 上
  若真的需要原生 UI 層級互動測試，`integration_test` 是唯一選項，
  沒有現成的「加強版」可用；反過來說，FMP 目前已知的驗證需求
  （音源搜尋播放、UI 頁面渲染）多半不涉及原生系統對話框，
  `integration_test` 本身應該足夠。
- **建置限制**：桌面應用必須在對應的作業系統上建置（Windows 建置
  要在 Windows 上跑、macOS 在 macOS、Linux 在 Linux），CI 上代表
  每個平台各自需要一個 runner——這與第 5 點的 CI 矩陣設計直接相關，
  不是額外的新限制，只是重申。

### golden test 是否值得採用——建議採用，但用 `alchemist` 而非
`golden_toolkit`

- **`golden_toolkit`（eBay Motors）已停止維護**：最後版本
  0.15.0，多個開源專案已經開 issue 要遷移離開（例如
  `wger-project/flutter#732`「目前用的 golden_toolkit 已被放棄，
  雖然只用在少數地方，也應該換成沒被放棄的東西」），第三方文章
  指出它三年沒更新（來源：WebSearch 摘要，未逐一核對每篇文章的
  發布時間，但多篇獨立來源結論一致）。
- **`alchemist`（Betterment ＋ Very Good Ventures）是目前主流遷移
  目標**：pub.dev <https://pub.dev/packages/alchemist>，最低
  Flutter 版本需求 3.32.0（低於 FMP 的 3.47.1，相容），下載量與
  分數（219 個 like、160 分、33 萬+ 下載，查證當下 libraries.io
  快照）顯示採用度高。核心設計正好解決「跨平台字型渲染差異」這個
  任務原始描述關心的問題：
  - **CI golden**：用 Ahem 字型（把所有文字渲染成方塊），文字內容
    不影響像素輸出，**在任何作業系統上跑都應該得到位元完全相同的
    圖片**，適合進版控、適合在 Linux CI 上跑而不用擔心字型渲染
    差異導致跨平台假陽性失敗。
  - **Platform golden**：用真實字型渲染，只適合在同一台機器／同一
    作業系統上比較（例如本機開發者自己驗證畫面），**建議
    gitignore、不進版控**，因為換一台機器（不同字型渲染引擎）比
    對就會失準。
  - 兩種各自用 `AlchemistConfig` 設定，API 是 `goldenTest`／
    `GoldenTestGroup`／`GoldenTestScenario`，與舊
    `golden_toolkit` 的 `multiScreenGolden`／`screenMatchesGolden`
    不同，若日後任何舊程式碼（根目錄舊專案）已經用
    `golden_toolkit`，遷移到 `app/` 時需要重寫（但 ADR 0008 本來
    就是複製葉節點邏輯、不 import 舊專案，golden test 屬於測試
    程式碼、且是 UI 層，本來就不在「複製葉節點」的範圍內，等於
    在 `app/` 從零開始寫）。
- **建議**：FMP 的 UI 元件（尤其 ADR 提到的「圖片載入語意元件」、
  `ScopedSlider` 這類有明確規格、容易被意外破壞外觀的共用元件）
  適合用 alchemist 的 CI golden（Ahem 字型版本）進版控，作為
  「這個元件的視覺結構沒有意外跑掉」的低成本回歸防護；不建議對
  「每一個頁面的每一種狀態」都上 golden test，golden test 的
  維護成本（UI 微調就要重新產生 golden 圖）與整合測試接近「較高」
  的那一檔，過度使用會拖慢日常開發，這點與官方測試金字塔的精神
  （widget/整合測試維護成本較高、應該挑重要案例）一致。

---

## 待補查項（誠實列出）

- Windows AppUserModelID 是否能透過 flavor 樣板機制（`.in` 檔
  變數替換）乾淨地依 flavor 切換，本研究只確認「機制上看起來可以
  延伸」，**標記為推測**，未在真實 FMP `windows/runner/main.cpp`
  上實際試做一次，落地前必須動手驗證一次「開發版與正式版是否真的
  各自有獨立的 AppUserModelID、且互不觸發對方的單一實例判斷」。
- Linux 建置所需的確切套件清單（GTK 版本、其他系統相依套件）本次
  未重新查證，沿用先前研究結論，落地前應直接參照 Flutter 官方
  Linux 桌面文件當時列出的清單。
- `dorny/paths-filter` 目前最新版本號與其官方 README 目前確切的
  monorepo 範例語法，本次未重新開啟該 repo 逐字核對，落地前需要
  直接查最新 release 並抄它當時的範例，而非依賴本研究記憶中的
  慣例寫法。
- Android `productFlavors`／`applicationIdSuffix` 的細節本次未重新
  查證（沿用先前研究），若擁有者對 Android 開發版身分有更細節的
  要求（例如是否也要像 Windows 一樣處理視窗標題等價物、圖示），
  需要另外針對 Android 官方 flavor 文件查證。
