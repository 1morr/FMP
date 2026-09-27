# 0015 — 測試與閘門：自寫 lint、預設零聯網、插件檢查案例一份四用、開發版獨立身分

- 狀態：已採納
- 日期：2026-09-27
- 影響範圍：`app/` 的測試、`app/packages/fmp_lints/`、`app/analysis_options.yaml`、`app/dart_test.yaml`、
  `.github/workflows/`、`1morr/fmp-plugins` 的插件目錄格式與 CI、開發者模式的插件開發工具、App flavor

## 背景

舊專案（`docs/audit/engineering.md` §3–§5）：約 1,849 個離線測試；25 支 static-rule 以正則比對原始碼，
部分是計次預算且沒守住（音源分支預算 9 處、實際 50 處）；`dart_test.yaml` 沒有預設跳過 `live`，裸 `flutter test` 會打真實 API；
行為測試依賴 75 個 `debug*` 測試掛鉤；開發版與正式版共用同一個單一實例鎖與同一份資料，開發時會碰到擁有者的真實資料（U9）。

ADR 0008–0014 各自留下「由測試策略 ADR 落實」的閘門：`app/` 不 import 舊專案、平台判斷只在平台層、Isar 只在舊資料匯入、
log 只經門面、禁止空 catch、音源 id 不得出現在 UI 與 service、插件契約測試。

擁有者的方向：測試不打真實 API；真實 API 只在 Debug 頁手動檢查或明確指定的冒煙測試；只保留守行為一致的必要測試；
使用者能以 AI Agent 生成自己的音源（ADR 0014）。

## 考慮過的選項

- **沿用正則 static-rule 測試**：否決。只比對字串、容易漏也容易誤報，且規則不會在編輯器裡即時出現。
- **`custom_lint`**：否決。repo 已於 2026-03 封存，依賴的舊 analyzer 插件協定在 Dart 3.13.2 棄用。
- **DCM（付費）或 DCL**：否決。只能表達 import 與呼叫限制；嚴格空 catch 與音源 id 規則仍要自寫，不值得多一個付費依賴。
- **現成 HTTP 錄製套件（`vcr`、`vcr2`、`dartvcr`）**：否決。`vcr` 系維護狀態查不到，`dartvcr` 基於 `package:http` 而非 dio，都沒有與正式遮蔽函式一致的遮蔽。
- **冒煙測試排程上 CI**：否決。B 站對機房 IP 回 412 風控、YouTube 自 2024 起擋機房 IP；排程只會固定觸發風控並暴露憑證。
- **插件只能以命令列開發與錄製**：否決。要裝 Flutter SDK 並手動貼 cookie，「使用者自己生成音源」實際上只剩會架開發環境的人做得到。
- **開發版一鍵從正式版複製快照**：否決。多一個只給開發用的功能，且下載紀錄指向正式版檔案，開發版刪除時可能刪到真實檔案。
- **CI 依「是不是程式碼」做路徑過濾**：否決。沿用舊 `ci.yml` 檔頭理由：文件承載規則，純文件改動不能跳過。

## 決定

1. **測試原則**：測試守契約與使用者看得到的行為，不守實作細節；行為變更同一個 PR 補測試，用能證明它的最低層。
   分層：單元、widget（provider override 注入假資料）、插件契約、整合（只挑搜尋→播放、從檔案安裝插件、舊資料匯入）、
   golden（只給設計系統共用元件，`alchemist` 的 CI golden）。不設覆蓋率門檻。正式程式碼不留測試掛鉤，一律經建構子或 provider 注入。
2. **lint 閘門**：以官方 `analysis_server_plugin` 自寫規則，放 `app/packages/fmp_lints/`：

   | 規則 | 內容 |
   |---|---|
   | `fmp_layer_imports` | 依賴方向表：`app/` 不 import 舊專案；`legacy_import` 不被 import、`isar_community` 只在其內；`drift` 只在資料層；平台套件只在平台層 |
   | `fmp_no_empty_catch` | catch 本體沒有陳述式即違規，變數名 `_` 不豁免 |
   | `fmp_log_facade` | `print`、`debugPrint`、`dart:developer` 的 `log`、`talker` 只在 log 門面 |
   | `fmp_source_id_literal` | 官方插件 id 字串只在 `legacy_import` 與測試 |
   | `fmp_url_literal` | `http(s)://` 字面值只在一個端點檔 |
   | `fmp_no_for_testing` | `lib/` 不得宣告 `*ForTesting` 成員 |
   | `fmp_http_client_owner` | `Dio(` 只在網路模組 |
   | `fmp_test_waits` | 測試內直接呼叫 `pumpEventQueue` 只在等待助手 |
   | `fmp_ignore_reason` | `// ignore: fmp_…` 同行必須寫理由 |
   | `fmp_platform_checks` | `Platform.isXxx`、`defaultTargetPlatform`、`Platform.operatingSystem` 只在平台層 |

   每條規則以官方 `analyzer_testing` 做雙向變異測試。`flutter analyze` 目前不顯示插件診斷並回報 No issues
   （flutter/flutter#193203），所以 CI 跑 `dart analyze --fatal-infos`，並以接線哨兵（暫放違規檔、斷言分析失敗且含規則名）證明規則接上了 `app/`。
3. **預設零聯網**：`app/dart_test.yaml` 對 `live` tag 設 `skip`、以 preset 解除；`app/test/flutter_test_config.dart` 以
   `HttpOverrides.global` 讓建立真實 `HttpClient` 直接失敗，要聯網的測試在自己的 zone 明確放行。JS 腳本只能經宿主 `http.request` 出網，同樣受限。
4. **檢查案例一份四用**：每插件每能力最多一條檢查案例（`checks.json`），同一份用於契約測試（重播 fixture，進 CI）、
   冒煙測試（真實連線，插件庫 `--live` 手動執行）、Debug 頁健康檢查（真實連線，App 內）、錄製（真實連線，遮蔽後存 fixture）。冒煙測試不進任何 CI、不排程。
5. **fixture**：錄製與重播在宿主網路層最底部的 dio `HttpClientAdapter`；一次請求／回應一個 JSON 檔（`meta`＋`request`＋`response`）。
   寫檔前一律經 ADR 0011 的正式遮蔽函式；重播比對 method＋排序後的 URL＋順序，被遮蔽的欄位不參與比對；比對不到就讓測試失敗。
   錯誤案例可手改 fixture 並標記。
6. **契約執行器**：一個通用套件以重播執行每個案例，斷言能力與匯出一致、DTO 驗證、案例期望、錯誤對到 `AppError` 類別（0013）、
   媒體請求不帶憑證（0012）、只連 manifest 網域、log 經遮蔽（0011）。插件庫 CI 以固定的 FMP 版本執行；`app/` 的 CI 對 `app/test/fixtures/plugins/`
   內的測試插件執行（合成資料、播放本機音檔），不依賴官方插件庫；同一個測試插件也供開發版離線開發。
7. **App 內插件開發工具**：開發者模式下從資料夾載入插件（先限桌面平台，由平台層宣告）、重新載入、跑案例看 log、
   以 App 內登入錄 fixture、每插件切換真實／錄製／重播。命令列只負責重播。版面由 Debug 頁的設計定。
8. **開發版**：flavor `dev`／`prod`，`pubspec.yaml` 設 `default-flavor: dev`，發版明確帶 `--flavor prod`。
   dev 的 Android `applicationIdSuffix ".dev"`、Windows AppUserModelID `com.personal.fmp.dev`、名稱「FMP Dev」與標記圖示、
   資料目錄／單一實例鎖／secure storage 命名空間加 `-dev`；prod 維持 ADR 0008 的身分。開發版資料預設空白，
   真實資料以舊資料匯入（選資料夾副本）或還原正式版備份帶入；開發版拒絕直接讀舊版正式資料位置。
   Android 開發版讀不到舊版私有資料，Android 的舊資料遷移驗證在模擬器以 prod flavor 做。
9. **CI**：`dorny/paths-filter` 依專案切分——`app/**` 與 `.github/**` 觸發 `app` 的 job，`app/` 以外的任何變動（含文件）觸發舊專案的 job；
   一個 `always()` 彙總 job 當唯一必要檢查。`app` 的 job：format、`dart analyze`、接線哨兵、`flutter analyze`、lint 規則測試、
   不加參數的 `flutter test`、契約執行器、Android／Windows／Linux／macOS／iOS（不簽名）建置、Linux 與 Windows 的整合測試。
   舊專案的 job 維持現狀，只在根目錄變動時跑，`app/` 的 PR 不被舊專案的不穩測試擋住。
10. **舊 static-rule**：原樣留在舊專案守舊程式碼，切換 PR 時一併刪除。概念在 `app/` 的去向（改 lint、改測試、刪除、由後續設計項決定）
    逐條列在 `.trellis/tasks/archive/2026-09/09-27-design-testing/design.md` §6。

採用的慣例：Dart 官方 `analysis_server_plugin` 與 `analyzer_testing`；`package:test` 的 tag 與 preset；VCR 錄製重播模式（自寫、接在 dio adapter）；
Flutter 官方 flavor 與 `default-flavor`；`dorny/paths-filter` 的 monorepo 切分；Flutter 官方測試總覽的權衡（單元與 widget 多、整合只挑重要情境）。

## 後果

- 好的：規則在編輯器裡即時出現且每條有雙向測試；裸 `flutter test` 保證不聯網；每個插件的錯誤、遮蔽、憑證邊界都用同一套案例驗證；
  使用者不裝開發環境也能在 App 內開發並錄製插件；開發時不再碰到真實資料；兩個專案的 CI 失敗不會互相誤導。
- 壞的：要維護自寫的 lint 套件；fixture 會隨上游改版過時，要重錄；Debug 頁多一塊插件開發工具；flavor 的 Windows 身分、鎖與資料目錄要自己接。
- 之後要注意：`flutter analyze` 的插件診斷 bug 修好後可以拿掉 `dart analyze` 的重複步驟，但接線哨兵保留；
  播放核心、歌詞、背景任務、UI、發版各自決定 `design.md` §6 標給它們的規則；`riverpod_lint` 是否已遷移到新插件系統在落地時查證。

## 如何確認

- `fmp_lints` 每條規則的 `analyzer_testing` 測試（違規會報、無關改動不報）；CI 的接線哨兵。
- 第一個里程碑實測：`dart analyze` 看得到插件診斷；契約執行器能否在 `flutter test` 內載入 QuickJS（不行改用桌面 `integration_test`）；
  dev 與 prod 同時開啟時身分、鎖、資料目錄各自獨立；一個故意聯網的測試在裸 `flutter test` 被跳過、解除 tag 後被 `HttpOverrides` 擋下。
- 測試：prod 的身分值與 ADR 0008 一致、dev 每一項都不同；開發版拒絕舊版正式資料路徑；掃描所有 fixture 不得有未遮蔽憑證。
- `AGENTS.md`（`app/`）列出的每條靜態規則都寫出對應規則名；沒有規則守的不寫進去。
