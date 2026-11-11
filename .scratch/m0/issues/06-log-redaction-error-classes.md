# 06: log 門面、遮蔽與錯誤分類

**What to build:** 新版的單一 log 門面，在四個平台都寫出 log 檔並輪替；單一遮蔽函式，cookie、token、簽名網址等敏感值一律變成 `***`；錯誤分類的 sealed 骨架，之後插件與播放的錯誤都轉成這些類別。這張票不做 Toast 與匯出診斷。

讀：brief §13、§14；plan §1.2、§1.3、§3；`AGENTS.md`〈公開 repo〉；spec〈共同規則〉

**Blocked by:** 02

**Status:** done

- [x] log 門面寫檔並輪替（2MB × 3），release 版保留 info 級；log 檔路徑由 `platform/` 提供，有測試。
- [x] 遮蔽函式涵蓋 cookie、Authorization 類 header、token、帶簽名參數的網址；log 寫入前一律經過它。單元測試列出每一類輸入與遮蔽後的樣子，也證明不該遮的內容不被改。
- [x] 錯誤分類照 brief §13：網路、限流、需登入、憑證失效、需驗證、不可用（地區、版權、需會員、只有試聽）、找不到、解析失敗、不支援。
- [x] 四平台實跑，啟動後在該平台的 log 路徑讀到 log 檔。
- [x] `dart run tool/check.dart` 完整版綠燈。

## Comments

### 決定與取捨

- **檔案**：`app/lib/core/log/log.dart`（門面 `Log`、`LogLevel`、`minimumLogLevel`）、`app/lib/core/redaction/redact.dart`（`redact`）、`app/lib/core/errors/app_error.dart`（sealed `AppError`）、`app/lib/platform/log_directory.dart`（`logDirectory()`）。`main.dart` 啟動時開 log，寫一行 `App started`。
- **log 套件**：用 `logger` 2.8.0 的 `AdvancedFileOutput`（大小輪替、保留份數），不自寫。2MB × 3 的意思是 `fmp.log` 加 2 份輪替檔，共 3 個檔。這個套件每分鐘才檢查一次大小，所以檔案會略超過 2MB；它也會刪掉 log 目錄裡最舊的「其他」檔案，所以目錄只放 log（行為與出處見 brief 事實 K12）。每筆都馬上交給檔案（`writeImmediately` 全部層級），不在記憶體裡等 2 秒，免得當掉前的最後幾筆遺失。debug 建置另外印到 console，印出去的也是遮過的內容。
- **log 格式**：一筆一行，`<UTC ISO 8601> <層級> <訊息>[ | <error>]`，stack trace 接在後面幾行。整筆組好後才經過 `redact`，檔案與 console 都只拿到遮過的內容；`logger` 只有 `core/log/` 能 import（依賴規則測試新增 `logPackageOutsideLogFacade`，雙向變異案例在 `dependency_rules_test.dart`），其他模組沒有繞過門面的路。
- **log 目錄**：`platform/` 經 `path_provider` 取 App 支援目錄，底下的 `logs/`。四平台的實際位置寫進 brief 事實 K13，讀法寫進 plan §2 各平台。單元測試換一個假的 `PathProviderPlatform`（path_provider 官方的測試做法，多了兩個 dev 依賴）。
- **遮蔽只用通用規則**：ADR 0038 寫明宿主不含音源專屬的邏輯，所以 Dart 端不列 `SESSDATA`、`bili_jct`、CDN 網域這類音源專屬名單。規則有：Cookie／Set-Cookie／Authorization 整段遮；名稱以 `token`、`secret`、`password`、`csrf`、`sid`、`session`、`auth`、`sig` 等結尾的值遮（`名稱: 值`、`鍵=值`、JSON 成員）；`Bearer <token>`；網址的帳密；帶簽名參數（名稱以 `sig`／`sign`／`signature`／`hmac` 結尾）的網址整段 query 值都遮，只留參數名稱，因為同一個網址裡的使用者 id、由 IP 算出的值各音源叫法不同。JSON 的值一律換成 `"***"`，遮過的 fixture 仍是合法 JSON（票 09 會用到）。很長的值用手寫掃描，不用「分組＋重複」的 regex，1MB 的值不會讓堆疊溢位。
- **錯誤分類**：只有骨架：9 個類別與「不可用」的 4 個原因（`region`、`copyright`、`membershipRequired`、`trialOnly`），`toString` 寫死類別名（release 混淆會改 `runtimeType`）。沒有欄位：插件錯誤代碼、`retryAfter` 這類由票 08 依實際需要加。名詞表沒有這些詞（技術用語，不是領域名詞），沒有補。
- **`generated_plugins.cmake` 多了 `jni`**：加 `path_provider` 後由 Flutter 自動產生（`path_provider_android` 帶進來的 FFI 外掛），Windows 建置正常。

### 已知的界線（code-review 後留下，不修）

- **遮不到的音源專屬名稱**：沒寫在 Cookie header 裡、單獨出現的 `SESSDATA=…`、`bili_jct=…`、`{"SESSDATA": …}`，YouTube 簽名參數 `s=`，以及 `key=`、`tokenValue` 這類不以敏感字結尾的名稱。還有網易雲的串流網址：簽名放在路徑裡，不在 query，`redact` 只看 query 的參數名稱，所以整段照原樣留著。目前 M0 只做匿名請求，也沒有網易雲，不會出現這些值。M2 登入時（例如 B 站掃碼回傳的 crossDomain 網址），由插件 manifest 宣告額外的敏感名稱再交給 `redact`；M1 加網易雲時，同樣由插件宣告它的網址哪一段帶簽名。這比較符合 ADR 0038。這個介面這張票不先做。
- **B 站 WBI 的 `w_rid`**：這是用公開的 `img_key`／`sub_key` 算出來的請求簽名，不是憑證，`redact` 不遮（「leaves alone」測試列著它）。`AGENTS.md` 寫「簽名網址的值寫成 `***`」，字面上可以讀成也包含它。票 09 檢查 fixture 時，請擁有者決定要不要也遮。
- **寧可多遮的副作用**：敏感名稱的 `名稱: 值` 一路遮到行尾，例如 `refresh token: expired` 會遮掉 `expired`；`Auth: failed`、`Login session: …` 同樣。一行裡有 Cookie 時，同一行後面的 error 也會被遮。
- **uncaught error 還沒接進 log**：`FlutterError.onError`、`PlatformDispatcher.onError` 不在票的範圍，留給之後需要的票（例如票 08 或 M1）。
- **`Log` 的取得方式**：`main.dart` 裡是區域變數。票 08 的宿主網路層要用時再決定怎麼注入（例如 `ProviderScope` override）。
- **Android 模擬器上的舊檔**：`files/logs/` 裡有 2026-11-04 上一輪重寫留下的 `fmp.jsonl`（同一個 applicationId），之後輪替時會被刪掉，無害。

### 四平台實跑（2026-11-11）

各平台啟動 debug 版，在 plan §2 寫的位置讀到這次啟動的那一行：

```text
macOS    ~/Library/Containers/com.personal.fmp.dev/Data/Library/Application Support/com.personal.fmp.dev/logs/fmp.log
         2026-11-11T09:30:58.390025Z INFO App started
iOS      <App 資料容器>/Library/Application Support/logs/fmp.log
         2026-11-11T09:31:51.565785Z INFO App started
Android  /data/data/com.personal.fmp.dev/files/logs/fmp.log（adb run-as）
         2026-11-11T09:33:09.403815Z INFO App started
Windows  %APPDATA%\com.personal.fmp\FMP Dev\logs\fmp.log
         2026-11-11T09:34:51.758214Z INFO App started
```

integration_test 在四平台也檢查同一件事。反向驗證：把 `main.dart` 的訊息改成 `App booted`，macOS 的 integration_test 會紅（`no fresh "App started" in fmp.log`）。

### 驗證輸出

`cd app && dart run tool/check.dart`（完整版，2026-11-11 code-review 修正後的第二次）：

```text
ok   i18n (slang)
ok   format
ok   analyze
ok   test                     # +122: All tests passed!
ok   doc gate
ok   build macos
ok   build ios
ok   build android
ok   build windows            # exit pubget=0、exit slang=0、exit build=0
ok   integration_test macos: integration_test/app_test.dart     # +2: All tests passed!
ok   integration_test ios: integration_test/app_test.dart       # +2: All tests passed!
FAIL integration_test android: integration_test/app_test.dart   # Bad state: No running android simulator/emulator found
FAIL integration_test windows: integration_test/app_test.dart   # error MSB8066
```

這兩個失敗都是環境造成的，照 plan §2 單獨重跑那一步：

- **Android**：跑閘門時，Mac 上的 adb daemon 被別處重啟，模擬器暫時看不到（plan §2〈多個 session 共用裝置〉）。等 `adb devices` 回到 `device` 後重跑 `flutter test integration_test/app_test.dart -d emulator-5554 --no-uninstall`，結果 `INFO App started`、`+2: All tests passed!`。
- **Windows**：`winpc` 的 Dart `frontend_server_aot` 編 kernel 時偶發當掉（存取違規 `-1073741819`），flutter_assemble 因此失敗，MSBuild 只報 `MSB8066`。用 `-v` 連跑，第 4 次抓到 `===== CRASH =====`。拿 main（沒有這張票的改動，也沒有插件）在 `winpc` 跑 `flutter build windows`，一樣以 `MSB8066` 失敗，所以跟這張票無關，已寫進 plan §2〈其他已知怪癖〉。重跑 `run_task.sh fmptest C:/fmp-wt/test.ps1 -File integration_test/app_test.dart`：第 1 次又失敗（log 被後面的重跑覆蓋，沒能確認是同一種當掉），第 2、3 次都是 `exit test=0`、`+2: All tests passed!`。第一次完整閘門的 Windows 也是這個失敗。
