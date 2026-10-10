# M3 執行計畫

「design §n」指本任務的 `design.md`；「決定 n」指 `prd.md` 的擁有者決定；「§16 第 n 條」指 design 的確認清單。

## 通用規則（每個 PR 子任務）

- **開工**：
  - 從最新的 `main` 開分支；
  - 以 `task.py create "<標題>" --slug <slug> --parent .trellis/tasks/10-08-m3-sources-accounts-devtools --package app --no-start` 建子任務；
  - prd 只寫做什麼與驗收（ADR 0026 §決定 1），在已核准的範圍內直接做，遇到未定的事才問。
- **M3a 與 M3b 的順序**：M3b 的 PR（11–21）在 M3a 驗收合併之後才開（決定 1）。M3a 內 1、2、4、7 一開始就能平行。
- **合併條件**：
  - `app/` 可編譯、`flutter test` 全綠；
  - CI 彙總 job `CI Result` 通過；
  - PR 描述附 review 指南；動到 `fmp-plugins` 的附該 repo 的 PR 連結。
- **實機驗證**（ADR 0027，design §1.3）：
  - 使用者看得到的 PR 在 Android 模擬器與 Windows 都照 `verify-on-device` skill 驗，回報寫明平台與模式。
  - 預設重播（dev flavor＋測試插件 `fmp-test`）；`fmp-test` 隨各 PR 加 `login`、`live`、`mix`、`multiPart`、`trackDetail` 的假實作與關鍵字（寫進它的 README），讓 UI 能以重播驗。
  - 改動本身是插件、網路層、登入，或在錄 fixture 時才用真實連線，只做最少的操作，不批次、不迴圈。
- **真實帳號與真實連線**（決定 2）：
  - YouTube 登入（R1、PR 9、驗收）只用擁有者另開的 Google 測試帳號；B 站、網易用擁有者指定的帳號。
  - **代理不輸入、不讀取、不轉述任何密碼、cookie 值或 token**：登入畫面停下來交給擁有者自己輸入密碼或掃 QR；log、截圖、PR 描述、research 檔只寫 cookie 名稱與「有／沒有」，不寫值與帳號名稱、頭像。
  - 截圖前確認畫面沒有帳號名稱與頭像（帳號頁的那一列先收起，或只截其他區域）。
  - 平常的插件 PR 只用匿名真實連線。登入相關的實測兩平台都做。
- **改播放後端**（`lib/playback/backends/`）：照 `app/AGENTS.md` § 驗證在兩平台各跑一次 `integration_test/audio_backend_contract_test.dart`。
- **動到外殼、提示或新增全螢幕路由**：照 `app/AGENTS.md` § 驗證跑 `toast_layering_test.dart`，並把新的路由（帳號頁的登入畫面、錯誤詳細頁、Debug 頁、播放頁直播版）加進它的案例。
- **改 schema**：照 `.trellis/spec/app/data/index.md` § 改 schema 做完整流程，版本號以合併順序為準（design §3.2）。
- **收尾**：子任務 `finish` 與 `archive --no-commit --skip-branch-validation`；手動 commit；以 merge commit 合併。
- **文件**：
  - 每個 PR 更新 `app/AGENTS.md` 中自己那一層：只寫查不到的契約與有閘門的規則，每條寫出它的閘門；
  - 需要時更新 `.trellis/spec/app/<layer>/`；
  - design §15 的更正：標「PR 0」的在 PR 0 一次加，其他在對應的 PR 加。
- **套件版本**：以 design §14 為起點，加依賴時到 pub.dev API 核對一次 `latest`，裝當前 stable；與 design 不同時在 PR 描述說明。
- **lint**：新規則與表的改動照 `.trellis/spec/app/lints/index.md` 寫雙向變異案例，並在 `tool/lint_sentinel.dart` 加違規行。
- **子代理模型**（使用者全域規則：預設 sonnet；只有會做「影響後續的決定」的子代理用 opus）：
  - **判準**沿用 M2 的分法，但以「實作者要不要在計畫之外做決定」為界：
    - M2 把播放核心、網路、快取、資料、平台、介面都給 opus，因為當時 design 沒有寫到 UI 版面與很多實作期才定的細節；
    - M3 的 design 已把介面簽章、資料表、流程寫定，**照計畫寫程式與測試一律 sonnet**；
    - 只有兩種 PR 用 opus：**要自己定版面與互動的新頁面**（沒有定稿的 UI／UX 設計，全域規則的 opus 項）、**根因未知的調查**（PR 1 的 Android 時長未知）。
  - 交給 sonnet 的實作，prompt 附完整計畫（動哪些檔、介面簽章、驗收條件），並寫明：遇到計畫沒涵蓋的設計決定就停下回報，不自行拍板；由主對話決定，必要時再開 opus。
  - `trellis-check`（審查）一律 opus；研究代理一律 sonnet。
  - 各 PR 的模型寫在該節；理由一句寫在括號裡。

## 進度與交接（compact 後從這裡接）

- **狀態**（2026-10-10）：規劃已核准（ADR 0028–0031 已採納）；R1 通過。
- **擁有者決定**：1–9 在 `prd.md`；design §16 的 14 條全部照建議；R1 後：UA 歸平台層、`flutter_inappwebview` 6.2.0-beta.3。
- **已合併進 `main`**：PR 0（#220）；PR 1 的 FMP 端（#221）；PR 2 的 FMP 端（#222）與 fmp-plugins#5（網易）；PR 4（#223，schema v7）；PR 3 的 FMP 端（#224）與 fmp-plugins#6（index、CI、B 站 1.0.0、網易 1.0.1；`FMP_REF`＝`fcb52d28`；Version Bump 會紅已在 `214e01c` 證明並 revert；raw `index.json` 可讀、SHA 相符）；PR 7（#225，schema v8；secure storage 整合測試兩平台通過）。
- **進行中**（M3a 的實作 PR 全部開了，都在等擁有者）：
  - **FMP 的 stacked PR**（每個都 opus 審過、Android 重播實測通過；只有 base `main` 的 #226 跑 CI，其餘改 base 後才跑）：
    - #226 PR 5 插件頁（`feat/m3-plugin-page`，CI 綠；更新流程已實測）
    - #227 PR 6 首次引導（`feat/m3-onboarding`）
    - #228 PR 8 登入、QR、帳號區塊（`feat/m3-login`）
    - #229 PR 9 網頁登入、貼上 cookie（`feat/m3-web-login`；Linux 以 stub 取代 `flutter_inappwebview_linux`，Linux 建置要等 CI）
    - #230 PR 10 失效與刷新（`feat/m3-refresh`）
    - 任務 `10-09-m3-plugin-page`、`-onboarding`、`-login`、`-web-login`、`-refresh` 都還沒封存：各自合併前封存。
  - **fmp-plugins**：#7（draft，`feat/login-qr`：B 站、網易 QR 登入 1.1.0）→ #8（draft，`feat/login-refresh`，base `feat/login-qr`：B 站刷新、判定表 1.2.0）；#4（draft，`feat/youtube`：播放＋登入，到 `df0d756`，worktree `../fmp-plugins-yt`）。三個插件對 `feat/m3-refresh` 的契約重播都過。FMP 那串合併後：`FMP_REF` 改新 main、轉正式 PR、等 CI。
  - **合併順序**：#226 → #227 → #228 → #229 → #230（每個合併後下一個改 base 到 `main`、等 CI 綠）→ fmp-plugins #7 → #8 → #4。
  - **YouTube 播放**（2026-10-10 Windows 真實，擁有者的 Google 測試帳號）：先前的 403 與機器人標記沒再出現；登入後 player 回 400 是 VISIONOS 不收瀏覽器 cookie，#4 改成 player 請求不帶憑證（`df0d756` 為止），登入只影響搜尋與帳號資訊。收 cookie 的 client（`WEB_EMBEDDED`、`TV`）目前被 YouTube 拒絕，原型在 fmp-plugins 分支 `wip/youtube-cookie-clients`（不合併）。細節在 #4 的描述。
- **Windows 已實測**（擁有者同意自動化）：首次引導、從檔案安裝；B 站、網易真實 QR 登入、帶憑證搜尋、開關、登出；B 站啟動刷新（`unchanged`）；YouTube 網頁登入、登入中搜尋與播放、登出（WebView cookie 見「PR 9 留下的」第 8 條）；`fmp-test` 的 `expired`（刷新後成功、帳號頁「已更新憑證」）與 `expired-hard`（已失效、提示附「登入」、點了到帳號頁）。
- **等擁有者的實機與真實操作**：貼上 cookie（擁有者從瀏覽器複製）；Android 的 YouTube 網頁登入（擁有者輸入密碼）與登出後以 cookie 名稱確認 WebView cookie 刪掉（「PR 9 留下的」第 2 條）；`86095` 等刷新碼的實際行為（要等憑證真的過期）。
- **待擁有者回覆**：無（secret scanning 警告擁有者已手動關閉；PR 5 的暫時分支已同意並用完刪除）。
- **下一步**：擁有者回來後依上面的實機清單驗證、依合併順序合併，然後 M3a 驗收（本檔「M3a 驗收」）；M3b（PR 11 起）在 M3a 驗收合併後才開。
- **實機與真實連線的教訓**：真實連線驗播放時用「臨時播放」（點一首），不要在開了循環的佇列裡混本機測試曲目——連續跳過會被成功的那首重設，PR 1 因此打了 player 160 次。
- **斷電紀錄**：2026-10-09 機器斷電，未提交的檔案可能變成全 NUL（PR 4 有四個）；恢復後先跑 `<scratchpad>/nulscan.py <repo>` 掃描，不要只看檔案大小。
- **本機環境備忘**（M2 的備忘仍適用，見 `archive/2026-10/10-01-m2-full-playback/implement.md` § 進度與交接的「本機環境備忘」）：模擬器序號、`ANDROID_SERIAL`、整合測試會換掉 dev 的 apk／exe、送鍵前確認 FMP 在前景、`smtc_probe.ps1 -AppFilter fmp`、搜尋來源每次啟動回到第一個插件（重播前先點 `FMP Test Plugin` chip）。
- **每個 PR 的固定流程**：
  1. 從最新 `main` 開分支（Conventional Commits 的英文分支名，例如 `feat/app-plugin-lifecycle`）；
  2. `task.py create … --parent .trellis/tasks/10-08-m3-sources-accounts-devtools --package app --no-start`；
  3. 寫 prd（繁中，列做什麼與驗收）與 `implement.jsonl`／`check.jsonl`，把 design 的相關節、ADR 0028–0031 與 `.trellis/spec/app/<layer>/index.md` 列進去；
  4. `task.py start`；
  5. 依該節的模型派 `trellis-implement`。驗證清單固定為：
     - `dart format --output=none --set-exit-if-changed .`
     - `build_runner` 後沒有實質變動
     - `dart run slang`（動到翻譯時）
     - `dart analyze --fatal-infos`、`flutter analyze`、`flutter test`
     - `dart run tool/lint_sentinel.dart`（動到 lint 時）
     - 需要時建置（`flutter build apk --flavor dev --debug`、`flutter build windows --flavor dev`）
  6. 使用者看得到的改動，由主對話照 `verify-on-device` 實機驗證兩平台，回報含平台與模式；
  7. 派 opus `trellis-check`，要它試著攻破安全相關的部分（憑證、遮蔽、插件 API、安裝與 SHA、WebView cookie、診斷包、GitHub 網址）；
  8. 把後續待辦寫進本檔的「留下的後續」；
  9. `git checkout --` 還原只有換行差異的產生檔：**逐檔**以 `git diff --ignore-all-space --ignore-cr-at-eol` 確認是空的才還原；加了原生插件的 PR（5、7、9、11、13、15）有真正新增的註冊要保留；
  10. 分開 commit（subject ≤ 72 字元，Conventional Commits）；
  11. `task.py finish`，再 `archive <slug> --no-commit --skip-branch-validation`，把 archive commit 掉；
  12. push，`gh pr create`（繁中描述＋review 指南）——照已核可計畫做的 PR 直接 push（擁有者 2026-10-07 的規則），計畫外的先問；
  13. 背景跑 `gh pr checks --watch`；
  14. 全綠後 `gh pr merge --merge`，main 快轉。
- **fmp-plugins 的 PR**：
  - 在同層的 `fmp-plugins/` clone 開分支；
  - 改完以 FMP 的 `FMP_PLUGIN_DIR=<絕對路徑>/<插件> flutter test test/plugins/contract/contract_test.dart` 重播驗證（PowerShell 寫法見 `app/AGENTS.md` § 驗證，跑完刪環境變數）；
  - 錄 fixture 只錄不需要登入的案例（命令列 `record_test.dart`），人工逐檔看過沒有憑證；需要登入的案例在 PR 16 之後以 App 內工具錄；
  - 在該 repo 開 PR 並合併（擁有者的 repo）；PR 3 之後每次都要 `index.json` 重產、版本號升級（CI 擋）。
  - 依賴 FMP 新宿主 API 的插件 PR，先合併 FMP 的 PR，再把 `fmp-plugins` 的 `FMP_REF` 改到那個 commit。
- **地雷**（M1、M2 帶來的，仍適用）：
  - 文件或程式碼引用子任務的研究檔時，一律寫 archive 後的路徑。
  - CI 的 `app` job 工作目錄已經是 `app/`。
  - 子代理有時用不了 context7 或 WebFetch，改用 pub cache 原始碼查證是可以的。
  - 子代理因 API 403、rate limit、連線中斷而中斷時，用 SendMessage 對同一個 agent 續跑。
  - 桌面裝置一次 `flutter test` 只能跑一個整合測試檔。
  - Android 的 `MainActivity` 繼承 `AudioServiceActivity`：帶 `--fmp-dev-plugin` 前先確認 `provideFlutterEngine` 覆寫仍在。
- **M3 新的地雷**（預期）：
  - **secure storage 跨 flavor**：PR 7 實機確認 dev 與 prod 的憑證檔在不同位置（design §6.1）；驗證只用 dev。
  - **WebView 的 cookie 留在系統 WebView**：Android 的 `CookieManager` 是整個 App 共用的，dev 解除安裝才清得乾淨；登出的實機驗證要看 cookie 名稱真的不在。
  - **raw.githubusercontent.com 的 CDN 快取**：`fmp-plugins` 合併後約 5 分鐘內 index 與 `.js` 可能不一致，SHA 不符是預期的（design §7.1），等一下再驗。

## 順序與相依

| PR | 依賴 | 半 | PR | 依賴 | 半 |
|---|---|---|---|---|---|
| R1 | — | — | 11 | M3a 驗收 | M3b |
| 0 | 擁有者核准、R1 | — | 12 | 11 | M3b |
| 1 | 0 | M3a | 13 | 11、12 | M3b |
| 2 | 0 | M3a | 14 | 11 | M3b |
| 3 | 1、2 | M3a | 15 | 13、14 | M3b |
| 4 | 0 | M3a | 16 | 11、14 | M3b |
| 5 | 3、4 | M3a | 17 | M3a 驗收 | M3b |
| 6 | 5 | M3a | 18 | 17 | M3b |
| 7 | 0 | M3a | 19 | M3a 驗收 | M3b |
| 8 | 4、7 | M3a | 20 | M3a 驗收 | M3b |
| 9 | 8、R1 | M3a | 21 | 18、19、20 | M3b |
| 10 | 8 | M3a | | | |

- 可以平行的：M3a 的 1、2、4、7；M3b 的 11、17、19、20（不同目錄）。
- 最長的鏈：0 → 1／2 → 3 → 5 → 6，以及 0 → 7 → 8 → 9。
- 高風險先做：R1；PR 1（800 KB 插件在 QuickJS isolate 的效能、Android 時長未知）；PR 2（eapi 加密、`X-Real-IP`）。
- 同時開兩個以上動 schema 的分支時，各自的 schema 版本號在後合併的那個 PR 重排。

## R1. YouTube App 內網頁登入實測（研究，不寫 `app/`）——已完成（2026-10-08，通過）

結果與決定見 `research/r1-youtube-login.md`；已回填 ADR 0029、design §5、§6.4、§14、§15 與 `prd.md`。以下是當時的計畫。

目的：回答 `phase2-plan.md:238` 的 §8 實測「YouTube App 內網頁登入（桌面 UA）是否仍可用」，決定 ADR 0029 的 WebView 部分與 PR 9 的範圍。最高風險，核准設計前做（`m3-decisions.md` §4）。

- **執行者**：主對話（要擁有者在場手動登入）；建專案、寫探針頁可交給 sonnet 子代理。
- **位置**：`app/` 之外的暫時 Flutter 專案，放主對話的 session 暫存目錄 `<scratchpad>/r1-login-probe/`（不在 repo 內，不提交；session 結束就消失，所以結果當場寫進 research 檔）。WebView 的使用者資料目錄也放在它底下。
- **步驟**：
  1. **前置**：擁有者準備好 Google 測試帳號（決定 2）。查兩平台的 WebView 版本並記錄：Windows 以探針呼叫 `WebViewEnvironment.getAvailableVersion()`；Android 模擬器 `adb shell dumpsys webviewupdate`（記 WebView 套件與版本）。
  2. **建專案**：`flutter create --org com.personal.r1 --platforms=windows,android r1_login_probe`（Flutter 3.47.5，與 `app/` 相同）；`pubspec.yaml` 加 `flutter_inappwebview: 6.1.5`（釘死）。
  3. **建置**：`flutter build windows --debug`、`flutter build apk --debug`。記錄能不能建（Flutter 3.47 的 AGP、Kotlin、CMake 相容性）；失敗時記錯誤，最多花 1 小時試官方 issue 裡的繞法（例如 `dependency_overrides` 指到同版本的平台套件），試不出來就記為「建置失敗」並結束（結論＝只提供貼上 cookie）。
  4. **探針頁**（一頁）：
     - 三個 UA 選項：(a) WebView 預設；(b) 桌面 Chrome UA，版本號用實測當天 Chrome stable 的主版號；(c) Android 行動 Chrome UA（舊版做法：拿掉 `; wv`）。Windows 測 (a)、(b)；Android 測 (b)、(c)。
     - 開 `https://accounts.google.com/ServiceLogin?service=youtube&continue=https://www.youtube.com/`（舊版 `youtube_login_page.dart` 的網址）。
     - Windows 以 `WebViewEnvironment.create(settings: WebViewEnvironmentSettings(userDataFolder: <scratchpad>/r1-login-probe/webview-data))`。
     - 「檢查 cookie」鈕：`CookieManager.instance().getCookies(url: WebUri('https://www.youtube.com'))`，另查 `https://accounts.google.com`；**只印名稱、domain、httpOnly、值的長度**，不印值。判斷舊版的必要集合 `SAPISID`、`__Secure-1PSID`、`__Secure-3PSID`（`youtube_account_service.dart` 的 `requiredCookieNames`），另記 `__Secure-3PAPISID`、`LOGIN_INFO`、`SID` 在不在。
     - 「驗證」鈕：以取到的 cookie 與 `SAPISIDHASH`（`SHA1(<時間> <SAPISID> https://www.youtube.com)`）對 innertube `account/account_menu` 發**一次**請求（探針內用 `HttpClient` 直接發），只印狀態碼與「回應有沒有帳號區塊」的布林，不印帳號名稱。
     - 「清除」鈕：`CookieManager.deleteCookies` 刪 `youtube.com`、`google.com` 的 cookie，再「檢查」一次，確認名稱都不在（ADR 0012 §決定 5 的登出）。
  5. **擁有者手動登入**：每個平台 × UA 選項一次。代理在登入頁停下、交給擁有者輸入帳號密碼與兩步驟驗證；代理不操作輸入框、不截有帳號資訊的畫面。
  6. **記錄阻擋**：Google 的「此瀏覽器或應用程式可能不安全」（擋嵌入式瀏覽器）、要求改用瀏覽器、captcha、兩步驟驗證畫面、登入後停在哪一頁、`continue` 有沒有回到 youtube.com。
  7. **寫結果** `research/r1-youtube-login.md`：日期；Flutter、`flutter_inappwebview` 與兩平台 WebView 的版本；建置結果；每個平台 × UA 一列（能否登入、取到哪些 cookie 名稱、驗證請求的狀態、遇到的阻擋）；清除是否有效；結論（通過／不通過）與 ADR 0029 要定的值（`login.webView.url`、`userAgent` 是固定字串還是空、`cookieHosts`、`doneCookies`）。**只記 cookie 名稱，不記值**；不記帳號名稱與 email。
  8. **收尾**：刪掉 `<scratchpad>/r1-login-probe/`（含 WebView 資料）；Android `adb uninstall com.personal.r1.r1_login_probe`；請擁有者視需要在 Google 帳號的「安全性 → 你的裝置」登出這兩個工作階段。
- **通過的定義**：兩平台至少各有一個 UA 選項能登入、取到必要的三個 cookie、驗證請求回到帳號區塊、清除有效。只有一個平台通過時，`loginWebView` 只在那個平台宣告（PR 9）。
- **不通過**：YouTube 只提供貼上 cookie（決定 8）；PR 9 只做貼上 cookie、不加 `flutter_inappwebview` 與 `loginWebView`；ADR 0029 的 WebView 段改寫成「不採用，理由見 R1」。
- **之後**：把結論回填 ADR 0029 與 design §6.4、§14，`prd.md` 的「未決」第 1 條刪掉。
- 模型：主對話執行；探針程式交給 sonnet（照本節的步驟，沒有設計決定）。

## 0. 規劃檔、ADR 與文件更正

- [x] 本任務的 `prd.md`、`design.md`、`implement.md`、`research/`（含 R1）commit。
- [x] ADR 0028–0031：依確認結果修訂，狀態改「已採納」、日期改核准日。
- [x] design §15 標「PR 0」的更正（§16 已全部確認，全部加）。
- [x] `milestones.md` § M3 拆成 M3a、M3b（範圍、驗收、依賴）。`09-26-fmp-rewrite/task.json` 的子任務清單已在規劃時加入本任務。
- 驗證：`main` 上有本任務目錄；`milestones.md` 的 M3a／M3b 範圍與 design §1.1 一致；`git grep` 新 ADR 的引用都對得上檔名。
- 依賴：擁有者核准、R1。模型：sonnet（文件，照清單）。

## M3a 三音源與帳號

## 1. YouTube 插件與 `idempotent`（design §4.2、§5.1、§5.4）

- [ ] FMP：`HttpRequest.idempotent`（`fmp-plugin.d.ts`、`hostApiShapes`、`SourceHttpClient` 的重試判斷）；ADR 0013 §決定 4 的那一行已在 PR 0。
- [ ] FMP：`officialPluginIds` 加 `youtube`；`fmp_source_id_literal` 的案例。
- [ ] FMP：`googlevideo.com` 的 `expire` 從內建遮蔽的簽名參數移除（design §5.1；不然錄下的 fixture 沒有期限，`expiresAtPattern` 的契約檢查必紅），`redactor_test.dart` 跟著改。
- [ ] FMP：Android 時長未知的處理（design §5.4）：先實機看 YouTube 串流在 just_audio 有沒有時長事件；沒有就在 `PlaybackSession` 不排時長未知的前瞻，dartdoc 寫明。
- [ ] fmp-plugins：`youtube/`（打包腳本、YouTube.js 18.1.0、`youtube.js` 產物、manifest 1.0.0、`checks.json` 的 `search` 與 `resolveStream`（含 `expiresAtPattern`）、錯誤對應表、遮蔽名單）；以命令列錄 fixture（匿名，兩個案例）。
- 測試：
  - `source_http_client_test.dart` 的 `retry`：標 `idempotent` 的 POST 重試、沒標的不重試、`idempotent: false` 的 GET 不重試；
  - `type_definitions_test.dart`；
  - `playback_session_test.dart`：時長未知時不呼叫 `setNext`、`completed` 換下一首；
  - YouTube 的契約（`FMP_PLUGIN_DIR`）：DTO、媒體請求不帶憑證、`expiresAt`。
  - 錯誤對應：`fmp-plugins/youtube/test/errors.test.js`（`node:test`，`npm test`）。更正（PR 1 實作時）：原寫「手改的錯誤 fixture 走契約」與 ADR 0015 §決定 4「每能力最多一條案例」衝突，加錯誤案例就擠掉成功的那一條；改以插件 repo 內的 Node 測試守對應表，PR 3 的 CI 跑它。
- 實測（真實，匿名）：兩平台以 `--fmp-dev-plugin` 裝 `youtube.js`、搜尋一次、播一首到交接下一首（記 Android 有沒有時長、交接是否無縫）；兩平台各跑一次 `plugin_runtime_benchmark_test.dart` 量載入時間，寫進 PR 描述。
- 依賴：0。模型：opus（Android 時長未知是根因未知的調查：要在實機找載入訊號）。

## 2. 網易雲插件（design §5.2）

- [ ] FMP：`officialPluginIds` 加 `netease`。
- [ ] fmp-plugins：`netease/`（`search`、`resolveStream`、`previewOnly`、eapi 的純 JS AES 與 MD5、音質對應、錯誤對應表、manifest 1.0.0、`checks.json`、命令列錄的 fixture）。
- [ ] `X-Real-IP` 實測（design §5.2，§16 第 14 條）：匿名真實連線，「不帶」與「帶」的搜尋與取流各一次，結果寫進 PR 描述與插件 README，依 §16 第 14 條的確認結果實作。
- 測試：網易的契約（DTO、`previewOnly` 的 fixture、錯誤對應 `-460` → `VerificationRequired`、媒體請求不帶憑證）；`fmp_source_id_literal` 的案例。
- 實測（真實，匿名）：兩平台搜尋一次、播一首。一首只有試聽的歌在「跳過試聽片段」開與關各一次（M2 的行為：跳過並提示／標「試聽」播放）——更正（PR 2 實作時）：匿名拿不到試聽片段（VIP 歌回 `-110`、沒有 `freeTrialInfo`），延到登入後在 M3a 驗收做（第 3 步的帳號登入之後）。
- 依賴：0。模型：sonnet（舊 Dart 程式碼就是規格；eapi 加密或 `X-Real-IP` 的結果與計畫不同時停下回報）。

## 3. `fmp-plugins`：CI、`index.json`、B 站修正（design §5.3、§7.1、§7.2）

- [x] `tool/build_index.dart`：讀每個插件目錄 `.js` 的 manifest、算 `.js` 與 `checks.json` 的 SHA-256，寫 `index.json`（design §7.1 的欄位）；`--check` 模式比對。
- [x] `.github/workflows/ci.yml`：`FMP_REF` 變數 checkout FMP、Flutter 3.47.5、每個插件目錄跑契約、有 `package.json` 的插件目錄跑 `npm ci && npm test`（PR 1 起 YouTube 的錯誤對應表）、`build_index.dart --check`、`.js` 改了而版本沒升就失敗。
- [x] B 站：標題解 HTML 實體；封面多尺寸；manifest 升 1.0.0；fixture 重錄（匿名）。
- [x] README 改寫（index、CI、版本規則）。
- [x] FMP：`lib/core/endpoints.dart` 建檔，放官方 index 網址（`fmp_url_literal` 的允許檔第一次有內容）。
- 測試：`build_index.dart` 的單元測試（欄位、SHA、`--check` 對過時的 index 失敗）；CI 本身在 PR 上跑一次綠、再以一個故意沒升版本的 commit 證明會紅（之後 revert）。
- 實測：瀏覽器打開 raw 的 `index.json` 確認可讀；不涉及 App。
- 依賴：1、2。模型：sonnet（格式已定）。

## 4. 插件生命週期（design §3.1、§7.1、§7.3、§7.4）

- [ ] schema：`installed_plugins` 加 `enabled`、`source_index_url`、`checks_json`；`plugin_indexes` 表；repository 與 migration。
- [ ] `PluginRegistry`：只載入啟用的；`setEnabled`；移除流程（design §7.4 的順序，排程器那一步在 PR 17 加）；`Redactor` 的 `_mediaCdns` 以插件 id 為鍵取代（M1 待辦 14）。
- [ ] `lib/core/network/host_fetch.dart`（design §7.1 的規則）；`lib/plugins/repository/`：讀 index（欄位封閉、`indexVersion`）、SHA 驗證、`checksUrl` 下載、更新比對（`pub_semver`）、能力或網域增加時回傳「需要確認」。
- [ ] `pluginNameProvider` 找不到插件時顯示「音源未安裝」，停用時顯示「音源已停用」。
- 測試：
  - migration 三種（升級前裝好的插件升級後仍啟用、內容不變）；
  - `plugin_installer_test.dart`：design §7.4 閘門的每一條；
  - `host_fetch_test.dart`：不帶憑證、只准 `https`、轉址換 host 失敗、大小上限、網路紀錄 `client: host`；
  - index 解析：多出欄位拒收、`indexVersion` 不是 1；
  - `plugin_registry_test.dart`：停用不載入、跨重啟。
- 實測：沒有使用者看得到的改動（插件頁在 PR 5）；搜尋頁 chip 在停用時消失可以在 PR 5 一起驗。不做。
- 依賴：0。模型：sonnet（流程與欄位已定）。

## 5. 插件頁、設定頁的區塊、從檔案安裝（design §6.7 的區塊順序、§7.5）

- [ ] 平台層 `lib/platform/files/`（`file_picker` 13.1.0：`pickFiles` 選 `.js`；PR 15、16 再加 `saveFile`、`getDirectoryPath`），宣告 `PlatformCapabilities.files`。
- [ ] 設定頁的區塊：帳號（PR 8 填內容，這個 PR 先不顯示）、外觀、播放、網路、插件、關於（PR 11）；`SettingsGroup` 之外的區塊以同一個 list-detail 呈現。
- [ ] 插件頁：已安裝／可安裝兩分頁、工具列（檢查更新、全部更新、從檔案安裝、從網址安裝、管理 index）、安裝與更新的確認對話框、移除確認、「非官方來源」提示。
- [ ] 離線：可安裝分頁讀不到 index 時的離線空狀態。
- 測試：widget 測試（design §7.5 的閘門）；guideline 400／1000 寬；`platform_test.dart` 的 `files`；`install_search_play_test.dart` 若受影響照改。
- 實測（真實：`raw.githubusercontent.com`，插件請求最少）：
  - 兩平台：插件頁看到三個官方插件 → 安裝 YouTube（確認框列出能力與網域）→ 停用 B 站（搜尋 chip 消失）→ 再啟用 → 移除網易（帳號、storage、快取項目都不在：照 `verify-on-device` skill 的 `references/runtime-state.md` 讀 dev 的 `fmp.db`，Android 以 `adb exec-out run-as … cat files/fmp.db` 拉回來）→ 從檔案安裝 `fmp-test`（「非官方來源」）。
  - 更新流程：在 `fmp-plugins` 開暫時分支 `test/m3-update-flow`，把它的 raw `index.json` 加成自訂 index → 從它安裝一個插件 → 在分支上升版號 → 檢查更新、更新；再升一次並加一個網域 → 確認框列出新增網域。**push 這個暫時分支前先問擁有者**（計畫外的 push），驗完刪分支。
- 依賴：3、4。模型：opus（插件頁的版面與互動沒有定稿，要自己定）。

## 6. 首次啟動引導（design §7.6）

- [ ] 搜尋頁的空狀態：觸發條件、官方插件清單（預設全勾）、一次確認、依序安裝與部分失敗的呈現、「稍後再說」、離線與重試。
- 測試：design §7.6 的閘門；guideline。
- 實測（真實）：兩平台清掉 dev 資料目錄 → 啟動看到引導 → 全部安裝 → 搜尋 chip 有三個音源；Android 再清一次、開飛航模式看離線狀態，關掉後按「重試」。Windows 不停用網卡（擁有者 M2 的決定），離線狀態只靠 widget 測試。
- 依賴：5。模型：sonnet（版面沿用插件頁的列與共用空狀態元件；需要新的版面決定時停下回報）。

## 7. `CredentialStore`、帳號表、每音源設定、注入與 Cookie 合併（design §3.1、§6.1–§6.3、§6.6）

- [ ] 平台層 `lib/platform/secure_storage/`（`flutter_secure_storage` 11.2.0，`resetOnError: false`、鍵前綴與 `storageNamespace`），宣告 `secureStorage`。
- [ ] schema：`accounts`、`source_settings`；repository 與 migration。
- [ ] `lib/plugins/accounts/credential_store.dart`：讀取失敗的「暫時無法讀取」與 30 秒重讀、啟動對齊、遮蔽登記與取消、實作 `CredentialSource`（`credentialMaterial` 回 cookie 表與標頭、`credentialCookieNames`，不回拼好的 `Cookie` 字串，design §6.1；取代 `credentialHeaders`）；`fmp.credentials.get()` 回傳 `FmpLoginCredentials`（`d.ts` 與 shapes 同步）。
- [ ] 認證攔截器：Cookie 三方合併（同名以憑證為準）、`authHeaders` 只在 attach；`HttpRequest.authHeaders` 與 `HttpResponse.credentialsAttached` 進 `d.ts` 與 shapes（回應欄位由認證攔截器已有的 `credentialsAttached` 狀態帶出）；cookie 攔截器併 jar 時跳過 header 已有的名稱與 `credentialCookieNames` 的名稱（憑證的 cookie 不經 jar，design §6.3）。
- [ ] 登出的資料面（`AccountService.logout`：憑證、帳號列、遮蔽、記憶體 jar；WebView 那一步在 PR 9 接上）。
- [ ] `app/AGENTS.md` § 網路的認證段改寫；加 § 帳號。
- 測試：
  - `auth_test.dart`：三種標記 × 三種狀態，以假的 `CredentialStore`（取代 `NoCredentials` 版本）；
  - 合併規則（三方同名、只有 jar、只有插件 header）；`authHeaders` 在 omit 與 refuse 時不出現；`invalidated` 時不帶；
  - **jar 送出時不含憑證名稱的 cookie**（jar 先放同名 cookie，attach、omit、已失效三種都不從 jar 送出）；**`auth: 'never'` 的請求在登入後不帶憑證 cookie**；
  - `HttpResponse.credentialsAttached` 只在帶了憑證時為真（attach 為真；omit、refuse、`never`、已失效為假），`source_http_client_test.dart`；
  - `credential_store_test.dart`：讀取失敗不刪、30 秒後重讀、啟動對齊兩種、遮蔽登記（log 與網路紀錄不出現假 cookie 值；短於 `Redactor.minimumSecretLength` 的值略過、不讓寫入失敗）；
  - 登出後 `CredentialStore` 為空、之後的請求不帶憑證（ADR 0012 §如何確認）；
  - migration 三種；`platform_test.dart` 的 `secureStorage`。
- 實測：沒有使用者看得到的改動（登入在 PR 8）。新增 `integration_test/secure_storage_test.dart`（寫一筆假值、讀回、刪除、`deleteAll` 只刪自己的前綴），兩平台各跑一次；Windows 另確認 `.secure` 檔在 dev 的 application support 目錄、不在 prod 的。
- 依賴：0。模型：sonnet（介面與規則已定；安全面由 opus 審查攻）。

## 8. `login` 契約、QR 登入、帳號頁（design §4.3、§6.4、§6.7）

- [ ] 宿主：manifest 的 `login` 欄位（M1 整個拒收的那段改成驗證 design §4.3 的形狀）；`SourcePlugin` 的 `loginQrStart`、`loginQrPoll`、`loginVerify`、`loginRefresh`；`checks.json` 的 `login` 案例（`loginVerify`，標 `requiresLogin: true`）；`login*` 匯出執行期間該插件的 client 不把回應的 `Set-Cookie` 存進 cookie jar（design §4.3、§6.3）；`d.ts`、shapes。
- [ ] `AccountService.login`：三種方式共用「`loginVerify` 通過才寫入」；QR 流程（`qr_flutter` 4.1.0、2 秒輪詢的一次性 `Timer` 接力、離開停止）。
- [ ] 帳號頁（設定頁第一個區塊）：design §6.7 的列；登出確認；`automationRisk` 說明；離線。
- [ ] fmp-plugins：B 站 `login`（QR）與網易 `login`（QR）、`loginVerify`（帳號資訊 API）、`checks.json` 的 `login` 案例（手寫的假憑證 fixture，`meta.edited`）；YouTube 的 `login`（`cookie`；`webView` 等 PR 9）與 `loginVerify`。
- [ ] `fmp-test`：假的 QR 登入（固定在第二次輪詢 `done`）。
- 測試：
  - manifest 的 `login` 驗證（缺 `webView` 而 methods 含 `webView` 拒收等）；能力與匯出一致（宣告 `login` 沒匯出 `loginVerify` 拒載）；
  - `account_service_test.dart`：`loginVerify` 拋錯時什麼都不寫；成功時先憑證後帳號列；QR 的 `expired`、`scanned`、離開畫面不再輪詢（`fakeAsync` 下沒有待執行的計時器）；
  - 帳號頁的 widget 測試（methods ∩ 平台能力、已失效、暫時無法讀取、離線、guideline）；
  - 三個插件的契約（`loginVerify` 的 fixture、憑證欄位都遮蔽；案例標 `requiresLogin: true` 仍照常重播）；
  - **jar 不存登入回應的 cookie**：`login*` 執行期間回應的 `Set-Cookie` 不進 jar，結束後一般回應照常存（design §6.3 的閘門）；
  - 登入後 `auth: 'never'` 與開關關閉的請求不帶憑證 cookie（PR 7 的測試以真的 `login*` 流程再走一次，用 `fmp-test` 的假 QR）。
- 實測：
  - 重播：兩平台以 `fmp-test` 的假 QR 走完登入、登出。
  - 真實（擁有者的帳號，擁有者自己掃 QR）：兩平台各登入 B 站、網易一次 → 一次帶憑證的搜尋（網路紀錄 `credentials: true`）→ 關掉「以登入身分瀏覽與播放」再搜尋一次（`false`）→ 登出（再搜尋 `false`）。截圖避開帳號列。
- 依賴：4、7。模型：opus（帳號頁與登入畫面的版面與互動沒有定稿）。

## 9. YouTube 網頁登入與貼上 cookie（design §6.4）

網頁登入（R1 通過，design §6.4）：

- [ ] 平台層 `lib/platform/login_webview/`（`flutter_inappwebview` 6.2.0-beta.3 釘死；Windows 的 `WebViewEnvironment` 使用者資料在資料目錄的 `webview/`；`app/windows/CMakeLists.txt` 加 STL1011 的 define），Android 與 Windows 宣告 `loginWebView`。UA：Android 拿掉 `; wv`、Windows 不設。
- [ ] 登入畫面：開 manifest 的 `webView.url`、`cookieHosts` 的 `doneCookies` 齊了就關頁、`loginVerify`、寫入；跳轉卡住的提示與重試（design §6.4）。
- [ ] 登出與移除插件時清 `cookieHosts` 與 `url` 的 WebView cookie（PR 7 留的那一步）。
- [ ] fmp-plugins：YouTube manifest 的 `login.webView`：`url` `https://accounts.google.com/ServiceLogin?service=youtube&continue=https://www.youtube.com/`、`cookieHosts` `["https://www.youtube.com"]`、`doneCookies` `["SAPISID", "__Secure-1PSID", "__Secure-3PSID"]`。

另外：

- [ ] 貼上 cookie 的畫面：多行輸入、兩種格式的解析、通用的「如何取得」說明；輸入內容不進 log 與錯誤報告。
- [ ] YouTube 插件的 `SAPISIDHASH` 以 `authHeaders` 送出。
- 測試：cookie 字串與 `cookies.txt` 的解析（含壞行）；輸入內容不出現在 log（假 cookie 掃描）；`loginWebView` 宣告為假的平台不出現「網頁登入」；完成只看 `cookieHosts` 的 cookie（其他網域的同名 cookie 不算）；Android UA 轉換（`; wv`、`;wv`、沒有標記）；卡住提示的計時；WebView 的清除以假 `LoginWebView` 斷言；`platform_test.dart`。
- 實測（真實，擁有者的 Google 測試帳號，擁有者自己輸入密碼）：兩平台以網頁登入（beta.3 的登入在這裡第一次實測；登入有問題時退回 6.1.5 加 AGP 旗標 `android.r8.proguardAndroidTxt.disallowed=false`，連 `pubspec.lock` 一起還原）→ 貼上 cookie 一次（擁有者自己從瀏覽器複製貼上）→ 帶憑證的搜尋與播放各一次 → 登出 → 以 `CookieManager` 的名稱檢查（開發入口或 log 的名稱清單）確認 cookie 不在。**這就是 §8 的 YouTube App 內網頁登入實測**，結果寫進 PR 描述與 `research/m3a-acceptance.md`。
- 依賴：8、R1。模型：opus（平台層新能力加登入畫面的互動）。

## 10. 失效與刷新（design §6.5）

- [ ] `AccountGuard`：插件呼叫丟 `CredentialInvalid` 時的單飛刷新、寫入、重跑一次；不支援刷新或刷新失敗就標 `invalidated` 並提示一次附「登入」。
- [ ] 啟動刷新：第一幀後、第一次 `Online` 時，對宣告 `refresh: 'onStartup'` 的插件各一次；帳號頁的最後刷新時間與結果。
- [ ] fmp-plugins：B 站 `loginRefresh`（RSA-OAEP 純 JS、`correspond`、`refresh_csrf`）與「憑證無效」判定表（`-101`）；YouTube（401）與網易（`301`）的判定表；手寫的失效 fixture。注意（PR 1 發現）：契約每能力最多一條案例（ADR 0015 §決定 4），失效 fixture 不能和成功案例並存；照 PR 1 的做法以插件 repo 的 Node 測試守判定表（輸入回應與 `credentialsAttached`），或另提 ADR 0015 的修訂，在 PR 10 定。
- [ ] `fmp-test`：關鍵字 `expired` 回 `CredentialInvalid`，第二次成功（刷新路徑）。
- 測試：design §6.5 的閘門（刷新後重跑帶新憑證、三個並行只刷新一次、不支援刷新時標失效、只提示一次、重新登入後再提示、限流與網路錯誤不標失效、啟動刷新等 `Online`）；三個插件的判定表契約（`credentialsAttached` 為假的同樣回應不判定）。
- 實測：重播：兩平台以 `fmp-test` 的 `expired` 看刷新後成功與失效提示附「登入」；真實（擁有者的 B 站帳號）：重啟後啟動刷新跑一次（log 有 `loginRefresh` 的結果，帳號頁最後刷新時間更新）。
- 依賴：8。模型：sonnet（流程已定；B 站刷新流程與舊版規格對不上時停下回報）。

## M3a 驗收（10 之後）

### 兩平台端到端（Android 模擬器與 Windows 各一次，dev flavor）

- **模式**：真實（三個官方插件、擁有者指定的帳號；YouTube 用測試帳號），只做下列步驟；錯誤與離線用 `fmp-test`（重播）。
- **步驟**：
  1. 清掉 dev 資料目錄（含 secure storage：Android 解除安裝 dev 重裝；Windows 刪 dev 的 application support 與 WebView 資料）→ 啟動 → 首次啟動引導裝三個官方插件。
  2. 三個音源各搜尋一次、播一首（YouTube 的交接看一次）。
  3. 帳號頁：B 站 QR、網易 QR、YouTube 網頁登入各一次 → 各一次帶憑證的搜尋 → YouTube 關掉「以登入身分瀏覽與播放」再搜尋一次 → 網易登入後一首只有試聽的歌在「跳過試聽片段」開與關各一次（匿名拿不到試聽片段，PR 2）。
  4. 重啟 App：三個帳號仍登入、B 站啟動刷新跑過一次。
  5. 插件頁：停用網易（chip 消失、佇列裡的網易曲目標「音源已停用」並被跳過）→ 啟用；檢查更新（沒有更新時顯示已是最新）。
  6. 登出 YouTube（cookie 名稱不在）；移除網易（帳號列、storage、快取項目都不在；歷史裡的網易曲目標「音源未安裝」）。
  7. 失效（重播）：`fmp-test` 的 `expired` 刷新成功與失效提示。
  8. 離線：插件頁可安裝分頁、帳號頁登入失敗時的離線狀態。
- **證據**：`research/m3a-acceptance.md`（照 M2 `research/m2-acceptance.md` 的格式：平台、模式、真實請求清單、截圖不含帳號資訊）。

### ADR 的測試

| ADR | 項目 | 在哪個 PR |
|---|---|---|
| 0012 | 媒體請求不帶 Cookie／Authorization（三個插件的契約） | 1、2、7 |
| 0012 | `AuthRequirement` 三種 × 三種狀態的注入 | 7 |
| 0012 | 刷新後重送帶新憑證；三個音源的「憑證無效」判定表；限流與網路錯誤不標失效 | 10 |
| 0012 | 登出、移除插件後 `CredentialStore` 為空且請求不帶憑證（重設資料在 M3b PR 14） | 7、9 |
| 0013 | 三個音源的錯誤對應（錄下或手改的錯誤 fixture） | 1、2、10 |
| 0028 | `idempotent` 的 POST 重試、沒標的不重試；`credentialsAttached` 只在帶憑證時為真；`login` 的檢查案例格式與 `requiresLogin`；型別定義一致 | 1、7、8 |
| 0014 | manifest 能力與匯出一致（含 `login`）、`apiVersion` 不相容拒載 | 1、8 |
| 0014 | 三個插件的契約（遮蔽、媒體不帶憑證、錯誤對應）；lint `fmp_source_id_literal` 加兩個 id | 1、2、3 |
| 0015 §決定 6 | 插件庫 CI 以固定 FMP 版本跑契約；fixture 掃描 | 3 |
| 0016 | 插件頁、登入的離線狀態 | 5、6、8 |
| 0029 | Cookie 合併、`authHeaders`、jar 不存登入回應的 cookie（8）、jar 送出時跳過憑證名稱與 `auth: never` 不帶憑證 cookie（7）、`loginVerify` 通過才寫入、讀取失敗不刪 | 7、8 |
| 0030 | index 解析與 SHA、semver、啟用與停用、移除的每一步、能力增加要確認 | 4、5 |

- [ ] 上表逐項在 PR 描述或測試檔找到對應，寫進 `research/m3-adr-tests.md` 的 M3a 段。
- [ ] `milestones.md` 的 M3a 狀態與勾選。
- [ ] `app/AGENTS.md` 的網路、插件、帳號、資料層段落與實際一致（逐條有閘門或標明「沒有閘門，review 時看」），opus 審查一次。

## M3b 開發工具、排程器、電台、Mix、分 P

## 11. 開發者模式、「關於」、Debug 路由與概覽（design §3.3、§12.1）

- [ ] schema：`developer_settings`（四欄一次建好）；Notifier 的 `developerMode`、`logLevel` setter。
- [ ] 平台層讀 App 版本（`package_info_plus` 10.2.2，design §14）。
- [ ] 設定頁「關於」區塊：版本列（版本、flavor）、連點 7 次（第 2 次起提示、離開歸零）。
- [ ] Debug 路由與 redirect；設定頁的 Debug 入口；list-detail 的八個區塊骨架（其他 PR 填內容，這個 PR 只有概覽，其餘區塊不顯示，各 PR 加一個）。
- [ ] 概覽：總開關（關閉時同一筆寫入清空 `log_level` 與 `plugin_dev_folder`）、log 層級（`debug`／`info`，接 log 門面）、版本／flavor／平台／資料目錄（`~` 代換）、快取用量連結。
- 測試：ADR 0025 §如何確認的開發者模式三項；redirect；log 層級改成 debug 後 debug 記錄進記憶體歷史；migration 三種；guideline。
- 實測（重播）：§8 的前半：Windows **release** 版（`flutter build windows --flavor dev --release`）連點 7 次開啟 → 重啟後仍開啟 → 總開關關掉 → 入口消失；Android 同樣走一次（debug 建置）。
- 依賴：M3a 驗收。模型：opus（Debug 頁的 list-detail 版面與概覽的呈現沒有定稿）。

## 12. Log 與錯誤歷史、網路（design §12.3）

- [ ] Log 區塊：記憶體歷史、「含之前的紀錄」（isolate 解析、6 MB 上限）、篩選、只看錯誤、複製、清除（排進 `LogFile` 寫入佇列）；匯出 log 檔在 PR 15 接上存檔。
- [ ] 網路區塊：清單、篩選、單筆詳細、對應錯誤紀錄。
- 測試：網路篩選（ADR 0025 §如何確認）；清除後記憶體與檔案都空；壞行略過（M1 已有）；widget 測試。
- 實測（重播＋一次真實 B 站搜尋）：§8 的「Debug 頁看到一次搜尋的網路摘要」（Windows release）；Android 看篩選。
- 依賴：11。模型：sonnet（區塊版面沿用 PR 11 的骨架與清單元件）。

## 13. `ErrorReport`、錯誤詳細頁、GitHub 回報（design §13）

- [ ] `ErrorReport` 與 `Log.report` 的關聯；`Toaster` 的「詳細」（開發者模式）與「回報」（`Unsupported`、`UnexpectedError`）。
- [ ] 詳細頁（全螢幕路由）、複製 Markdown、「在 GitHub 回報」與第一次提醒（`report_reminder_dismissed` 的 setter）。
- [ ] 平台層 `lib/platform/url_opener/`（`url_launcher` 6.3.3），宣告 `urlOpener`。
- [ ] `endpoints.dart` 加 GitHub 新增 issue 網址；`.github/ISSUE_TEMPLATE/bug_report.yml`（繁中）。
- [ ] Debug 頁 Log 區塊的「只看錯誤」點一筆開詳細頁。
- 測試：ADR 0023 §如何確認的四項（按鈕、遮蔽、網址不含內容）；`toast_layering_test.dart` 加詳細頁；`bug_report.yml` 的結構測試（YAML 解析：必要欄位、`render: markdown`、標籤；`app/test/` 以讀檔測試守，`.github/**` 已觸發 `app` job）。
- 實測（重播）：兩平台 `fmp-test` 的 `fail` 關鍵字：開發者模式下「詳細」→ 複製 → 「在 GitHub 回報」開瀏覽器到範本頁（不送出）；關掉開發者模式後以會丟 `UnexpectedError` 的關鍵字看「回報」。
- 依賴：11。模型：sonnet（ADR 0023 與 design 已定版面要素）。

## 14. 播放狀態、資料庫、重設資料（design §12.2、§12.3）

- [ ] `PlaybackDiagnostics`（`PlaybackSession` 提供）與播放狀態區塊、複製快照。
- [ ] 資料庫區塊：唯讀瀏覽、檢查、從備份還原。
- [ ] 重設資料：`VACUUM INTO` 備份、二次確認、清空（資料庫、`SecureStorage.deleteAll`、WebView `clearAll`、快取）、重啟（Windows 自己重啟；Android 提示手動重開，並確認重開時 `main()` 重跑：`SystemNavigator.pop` 因 `AudioServiceActivity` 的 cached engine／前景服務沒重跑時，改成先停掉 audio_service 再結束 process，實作在這個 PR 決定、寫進 `app/AGENTS.md`，design §12.2）。
- 測試：ADR 0025 §如何確認的資料檢查兩項、重設兩項、遮蔽（播放快照、資料庫瀏覽）；從備份還原後資料等於備份；重設後 `CredentialStore` 為空且請求不帶憑證（ADR 0012 §如何確認的「重設所有資料」）。
- 實測（重播）：兩平台看播放狀態（重試中的下次重試時間）、瀏覽 `plugin_storage` 的值是 `***`、檢查乾淨；重設資料（先備份）→ 重開後是空的 → 從備份還原 → 資料回來、要重新登入。Android 另確認重設並重開後 `main()` 重跑（log 出現新的 `App started`、不是沿用舊 process），沒有就走上面的 audio_service 方案再驗一次。
- 依賴：11（重設要清的憑證與 WebView 在 M3a 已有）。模型：sonnet（ADR 0025 與 design 已定流程）。

## 15. 診斷包（design §12.4）

- [ ] `lib/app/diagnostics/`：組裝 `diagnostics.txt`／`.json`、zip（`archive` 4.3.0，isolate）。
- [ ] 平台層：`files` 加 `saveFile`；`lib/platform/share/`（`share_plus` 13.3.1），宣告 `shareFiles`。
- [ ] 概覽的診斷包：複製、存檔、分享；第一次匯出的提醒（共用 `report_reminder_dismissed`）；Log 區塊的「匯出 log 檔」接同一個管道。
- [ ] 遮蔽函式登記家目錄為已知值（M1 待辦 13）；啟動維護清單加「診斷包暫存」。
- 測試：design §12.4 的閘門；ADR 0011 的遮蔽測試加四種。
- 實測（重播）：§8 的「匯出的診斷包能以解壓工具打開」（Windows release，存檔後以 Windows 檔案總管或 `Expand-Archive` 打開、三個檔都在、`dataDirectory` 是 `~\…`）；Android 分享到檔案 App 一次。
- 依賴：13、14。模型：sonnet。

## 16. 健康檢查與插件開發工具（design §12.5）

- [ ] `lib/plugins/json_shape.dart` 移到 `lib/core/`；adapter 與 `fixture.dart` 移到 `lib/core/network/`、契約測試改引用；`restrictedImports`；ADR 0015 §決定 6 的更正（design §12.5）。
- [ ] `checks.json` 的解析與案例期望的判斷移到 `lib/plugins/health/`，契約執行器與 `type_definitions_test.dart` 改引用。
- [ ] 健康檢查區塊：全部或單一插件、一次一個、略過、`health` tag。
- [ ] 平台層：`files` 加 `getDirectoryPath`；宣告 `pluginDevTools`（Windows 真、Android 假）。
- [ ] 插件開發區塊：選資料夾、開發中標記、重新載入、真實／錄製／重播切換、案例單跑全跑、以 App 內登入錄 fixture。
- [ ] `plugin_dev_folder` 的 setter；關閉開發者模式時卸載。載入開發資料夾的插件時 `installed_plugins` 補一列（沒有同 id 的已安裝列才補；來源標開發資料夾、`enabled` 為真，`plugin_storage` 的外鍵才寫得進去），移除開發資料夾時刪這列（cascade 掉 storage）；有同 id 的已安裝列時沿用、不覆寫、不刪（design §12.5；來源標記的存放方式與殘留列的清理在這個 PR 決定）。
- [ ] fmp-plugins：以 App 內工具（已登入）重錄標 `requiresLogin` 的案例（M3 只有各插件的 `login` 案例）；fixture 的憑證欄位遮蔽後提交。
- 測試：design §12.5 的閘門；M1 的契約測試全綠；lint 的 `restrictedImports` 案例；`requiresLogin` 的案例在已登入時以已存憑證跑、未登入標「略過」；開發資料夾的插件寫得進 `plugin_storage`、移除資料夾後那一列與 storage 都不在，沿用已安裝列的情況卸載後已安裝版的 manifest、腳本與 storage 不變。
- 實測：Windows（重播＋真實各一次）：選 `fmp-plugins` 的本機 clone → B 站標「開發中」→ 重播模式全跑通過 → 改一行 log 重新載入看到新 log → 錄製模式跑 `search`（真實，一個案例）→ 檢查寫出的 fixture 沒有憑證 → 卸載；健康檢查全部跑一次（真實，三個插件各一輪，最少操作）。Android：插件開發區塊不出現、健康檢查跑一次 `fmp-test`。
- 依賴：11、14。模型：opus（插件開發工具的版面與模式切換的互動沒有定稿）。

## 17. `BackgroundScheduler` 與 `fmp_periodic_timer_owner`（design §8、§2.2）

- [ ] schema：`scheduler_runs`；repository。
- [ ] `lib/scheduler/background_scheduler.dart`：design §8.1 的全部規則。
- [ ] 插件停用與移除時移除該插件的工作（PR 4 的移除流程加這一步）。
- [ ] lint `fmp_periodic_timer_owner`；`forbiddenLayerImports` 的 `scheduler/`；哨兵；`app/AGENTS.md` § Lint 與 § 排程器。
- 測試：design §8.2 的七項加兩項；lint 雙向變異；migration 三種。
- 實測：沒有使用者看得到的改動（第一個工作在 PR 18），不做；PR 18 的實測涵蓋。
- 依賴：M3a 驗收。模型：sonnet（ADR 0017 與 design 已逐條寫定）。

## 18. 電台與直播（design §3.1、§4.4、§9）

- [ ] 宿主：`live` 的四個匯出（`SourcePlugin`、`d.ts`、shapes、`checks.json` 的 `live` 案例）。
- [ ] schema：`radio_stations`、`network_settings.radio_status_interval_minutes`；設定頁「網路」組加一列。
- [ ] `lib/radio/`：清單、以網址新增、加為電台、狀態工作（`radio-status:<pluginId>`）；收聽中的 `live-info` 工作。
- [ ] 播放：`QueueMode.live`、`playLive`、停止回佇列、暫停＝停止、提前結束先問狀態再以 1／3／9 秒重連、開直播丟掉進行中的解析、`NowPlaying` 的直播欄位、不持久化。
- [ ] 介面：導覽「電台」（搜尋｜歷史｜電台｜設定）、電台頁、搜尋頁的直播間模式與篩選、播放頁與播放列的直播版。
- [ ] ADR 0018 §決定 6、9 的更正已在 PR 0（確認後）；`forbiddenLayerImports` 的 `radio/`。
- [ ] fmp-plugins：B 站 `live`（四個匯出、`checks.json` 的 `liveStatus` 案例、匿名錄的 fixture）。
- [ ] `fmp-test`：`live` 的假實作（一個開播中、一個未開播、一個會「提前結束」再重連的直播間；`liveStatus` 拋錯的房間）。
- 測試：design §9.2、§9.4、§9.5 的閘門；ADR 0018 §如何確認更正後的「開直播後音樂結果不播出、不再解析」；`navigation per window class` 四個導覽項；離線（電台頁）；migration 三種。
- 實測：
  - 重播：兩平台以 `fmp-test`：搜尋頁直播間模式 → 加為電台 → 以網址新增 → 排序 → 播放 → 停止回到原佇列與位置 → 提前結束後重連 → 間隔設 1 分，背景／最小化時 log 沒有狀態工作、回前景後到期的跑一次 → 飛航模式時不跑。
  - 真實（B 站匿名）：一個開播中的直播間播 30 秒、看人數更新一次。
- 依賴：17。模型：opus（電台頁、直播間模式、播放頁直播版的版面與互動沒有定稿）。

## 19. Mix（design §3.1、§4.5、§10）

- [ ] 宿主：`mix` 匯出（`SourcePlugin`、`d.ts`、shapes、`checks.json`）。
- [ ] schema：`player_state` 的 `mode`、`mix_*`；`queue_store` 的持久化與恢復。
- [ ] `QueueModel` 的 `mix` 模式（禁止的操作、清空退出、100 首修剪）；`MixSession` 的補歌。
- [ ] `TrackRowMenu` 的「開始 Mix」（宣告 `mix` 時）；隨機鈕與禁止的選單項目在 Mix 中停用並附說明。
- [ ] fmp-plugins：YouTube `mix`（`RD<videoId>`、continuation 當 `cursor`）。
- [ ] `fmp-test`：`mix` 的假實作（每批 5 首、三批後 `cursor` 為空）。
- 測試：design §10 的閘門（ADR 0018 §如何確認的 Mix 修剪）；migration 三種（M2 的恢復測試不改期望全綠）。
- 實測：重播：兩平台以 `fmp-test` 開始 Mix → 補歌三次與換種子 → 禁止的操作 → 重啟後仍是 Mix → 清空退出。真實（YouTube 匿名）：開始 Mix、播到倒數第二首觸發補歌一次。
- 依賴：M3a 驗收（YouTube 插件）。模型：sonnet（規則照舊版與 design 已定；入口沿用 `TrackRowMenu`）。

## 20. B 站分 P（design §4.6、§11.1）

- [ ] 宿主：`TrackSummary.partCount`、`multiPart` 匯出、`checks.json`。
- [ ] 搜尋結果的展開、分 P 列、影片選單套用全部分 P；佇列、歷史、播放頁的「影片標題 · P2 分 P 標題」。
- [ ] fmp-plugins：B 站 `partCount`（搜尋回應的 `page`）與 `multiPart`（`/x/player/pagelist`）。
- [ ] `fmp-test`：一首三個分 P 的曲目。
- 測試：design §11.1 的閘門。
- 實測：重播：兩平台以 `fmp-test` 展開、點 P2、選單加入全部分 P。真實（B 站匿名）：一支多 P 影片展開、播 P2。
- 依賴：M3a 驗收。模型：sonnet（照舊版 `_PageTile`）。

## 21. `trackDetail`（design §4.7、§11.2）

- [ ] 宿主：`trackDetail` 匯出、`TrackDetail` DTO（`stats.kind` 封閉 union）、`checks.json`。
- [ ] `TrackDetails` widget 的詳細資料區、記憶體 LRU、失敗與重試。
- [ ] fmp-plugins：三個插件的 `trackDetail` 與契約案例（匿名錄的 fixture）。
- [ ] `fmp-test`：一筆完整的詳細資料與一筆會失敗的。
- 測試：design §11.2 的閘門；`type_definitions_test.dart`（`stats.kind` 的 union 對 Dart 列舉）。
- 實測：重播：兩平台播放頁詳細分頁與右側面板（Windows）。真實（匿名）：三個音源各看一次詳細。
- 依賴：18、19、20（M3b 最後一個，決定 5；三個插件的 fmp-plugins 改動依序合併）。模型：sonnet。

## M3b 驗收（21 之後）

### 兩平台端到端（Android 模擬器與 Windows 各一次，dev flavor；§8 那一段用 Windows release）

- **模式**：重播為主（`fmp-test`）；真實只做：B 站直播間播 30 秒、YouTube Mix 補歌一次、B 站多 P 影片一支、三個音源的詳細各一次、健康檢查一輪。
- **步驟**：
  1. 「關於」連點 7 次開啟開發者模式 → 重啟後仍開啟（Windows release，§8）。
  2. Debug 頁八個區塊各看一次：概覽、Log（含之前的紀錄、只看錯誤 → 詳細頁）、網路（一次搜尋的摘要，§8）、播放狀態、健康檢查（全部）、插件開發（Windows：選資料夾、重新載入、重播全跑）、資料庫（瀏覽、檢查）、重設資料（先備份 → 重設 → 從備份還原）。
  3. 診斷包：複製、存檔後以解壓工具打開（§8）、分享（Android）。
  4. 錯誤回報：`fail` 的「詳細」→「在 GitHub 回報」開範本頁（不送出）；一般模式下 `UnexpectedError` 的「回報」。
  5. 電台：搜尋頁直播間 → 加為電台 → 以網址新增 → 排序 → 播放（B 站真實）→ 停止回佇列 → 間隔 1 分時背景與離線不跑、回前景補跑一次。
  6. Mix：YouTube 曲目「開始 Mix」→ 補歌 → 禁止的操作 → 重啟仍是 Mix → 清空退出。
  7. 分 P：多 P 影片展開、播 P2、選單加入全部分 P。
  8. 詳細：三個音源的播放頁詳細分頁（Windows 另看右側面板）。
  9. 總開關關掉開發者模式：Debug 入口與「詳細」消失、開發資料夾卸載（§8）。
- **證據**：`research/m3b-acceptance.md`。

### ADR 的測試

| ADR | 項目 | 在哪個 PR |
|---|---|---|
| 0015 §決定 7 | 插件開發工具：資料夾載入、重新載入、模式切換、錄製經遮蔽 | 16 |
| 0017 | 排程器七項（看不見與離線不跑、恢復補跑、一個計時器、手動不看間隔、移除丟結果、退避與 `retryAfter`、上次成功時間）；lint `fmp_periodic_timer_owner` 雙向變異 | 17 |
| 0018 | `QueueModel` 的 Mix 修剪；開直播後音樂結果不播出、不再解析（§16 第 2 條更正後）；直播重連 | 18、19 |
| 0016 | 電台頁的離線狀態 | 18 |
| 0023 §決定 4 | 按鈕依開發者模式；`ErrorReport` 經遮蔽；網址不含內容；詳細頁在提示之下 | 13 |
| 0025 | 開發者模式三項；log 檔讀回與壞行；網路篩選；資料檢查；重設；遮蔽；redirect；`pluginDevTools` 與「分享」依宣告 | 11–16 |
| 0028 | `live`、`mix`、`multiPart`、`trackDetail` 的型別定義一致與契約案例；`requiresLogin` 的略過 | 16、18–21 |
| 0031 | 電台清單、以網址新增、狀態工作、Mix 入口只在宣告時出現 | 18、19 |

- [ ] 上表逐項在 PR 描述或測試檔找到對應，寫進 `research/m3-adr-tests.md` 的 M3b 段。
- [ ] `milestones.md` 的 M3b 狀態與勾選（ADR 0026 §如何確認：未打勾不能 archive）。
- [ ] `app/AGENTS.md` 的排程器、電台、播放、Debug、介面段落與實際一致，opus 審查一次。
- [ ] 本任務 `finish`、`archive`。

## 留下的後續

（每個 PR 收尾時補；格式照 M2 的「PR n 留下的」各節。）

### PR 9 留下的

1. **Linux 建置只能靠 CI 驗**：`flutter_inappwebview_linux` 以本機 stub（`app/packages/flutter_inappwebview_linux_stub`）取代，本機建不了 Linux；stacked PR 不跑 CI，整串回到 base `main` 時要看 Linux 建置與整合測試 job。Linux 的 WebView 在 Linux 平台任務決定（ADR 0012 §決定 8），定了就刪 stub。
2. **Android 的 WebView cookie 刪除**：套件的 `deleteCookie` 不帶 `Secure`，Chromium 拒收，改成送帶 `Secure` 的過期 cookie；只以原始碼推斷，**要在真實 Google 登入後以 cookie 名稱確認真的刪掉**。
3. **WebView 清不掉會擋住登出與移除**（照 design §7.4「失敗就停在那一步」）：登出時憑證已先刪，帳號列留著會在下次啟動對齊刪掉；但若 Windows 沒有 WebView2 會一直卡住。要不要改成記 warning、略過，實機遇到再決定。
4. **卡住判定**改成「`url` 讀得到的 cookie 已有全部 `doneCookies`、`cookieHosts` 仍沒齊」（照字面「`url` 網域有任何 cookie」會在使用者輸入密碼時就誤報）；design §6.4 的那句是筆誤等級，真實登入時確認 15 秒的門檻。
5. **APK 多了約 3.4 MB 的套件 asset**（`t-rex.html`、`web_support.js`）；要瘦身再看 `flutter_inappwebview` 的 asset 排除方式。
6. **`flutter_inappwebview` 的 debug log**：debug build 會以 `developer.log` 輸出 `onLoadStop` 網址與頁面 console（Google 跳轉網址可能帶 token），只到 VM service／IDE，不進 FMP 的 log、錯誤歷史、診斷包，release 不輸出。要關就在平台層設 `PlatformInAppWebViewController.debugLoggingSettings.enabled = false`。
7. **貼上 cookie 對話框在「驗證中」關掉**，驗證仍跑完並寫入（不跳成功提示），與 QR 一致；要不要在驗證中禁止關閉，之後決定。
8. **Windows 登出後 WebView 留下的 cookie**（2026-10-10 真實 YouTube 登入後登出，讀 WebView2 `Cookies` 資料庫的名稱欄）：`.google.com`（17）與 `accounts.google.com`（7）全清，`.youtube.com` 24 個清掉 20 個（含三個 `doneCookies`）。留下兩類：`.youtube.com` 4 個分區 cookie（CHIPS，`top_frame_site_key` 是 `https://youtube.com`；`VISITOR_INFO1_LIVE` 等訪客 cookie，以網址刪不到）；Google 登入時寫到地區網域的 `.google.com.tw` 10 個（`SID`、`__Secure-1PSID` 等工作階段 cookie），不在 `cookieHosts`、`url` 底下。後者不會送到 `accounts.google.com` 與 YouTube，但 Google 工作階段留在 WebView 資料裡。修法候選：登出時清全部 WebView cookie（平台層已有 `clearAll`；登入 WebView 只在登入時用，憑證另存），待擁有者決定。

### PR 8 留下的

1. **`cookie` 與 `webView` 的登入按鈕**：`availableLoginMethods` 目前只開 `qr`；PR 9 打開這兩種（`webView` 依 `PlatformCapabilities.loginWebView`）。
2. **最後刷新時間與結果**的顯示留給 PR 10。
3. **已啟用卻載入失敗的插件按登入只得到「預期外的錯誤」提示**：與 PR 5 留下的第 2 條同一個根源（registry 沒暴露載入失敗），一起處理。
4. **插件圖示**：帳號卡與插件頁都還沒畫 manifest 的 `icon`。
5. **插件端（fmp-plugins）**：B 站、網易的 QR 登入與 `loginVerify`，資料見 `archive/2026-10/10-09-m3-login/research/qr-login-apis.md`。網易 weapi 要純 JS 的 AES-CBC 與無 padding RSA，現有 `post()` 沒傳 `auth`、非 200 就拋、不回 headers。B 站 `businessError` 少 `-111`。

### PR 5 留下的

1. **「開發中」標記沒做**：它的來源是開發資料夾（design §12.5），PR 16 才有；`--fmp-dev-plugin` 裝的插件在資料庫裡與從檔案裝的沒有分別。PR 16 加上。
2. **已啟用卻載入失敗的插件沒有標記**：不在 registry 的插件清單、也不是停用，開關看起來是開著的。要做就由 registry 暴露載入失敗的狀態，插件頁加一個標記與測試。
3. **已安裝清單還沒讀好或讀失敗時，可安裝分頁對已裝的插件顯示「安裝」**：按下去會走成換來源（或降版）的更新。本機資料庫通常比 index 快，沒有 repro；要修就在已安裝清單讀好前停用可安裝分頁的按鈕。
4. **`plugins_page.dart` 的 `_install`、`_confirmFile` 只接 `AppError`**：`repository.byId` 拋 drift 的錯誤時變成沒人接的非同步錯誤。
5. **從檔案安裝沒有大小上限**（從網址安裝是 8 MiB）。
6. **沒有網域的插件（`fmp-test`）在詳細資料裡仍顯示空的「Sites it connects to」標題**（Android 實測看到）；確認框已經省略，詳細資料應比照。

### PR 7 留下的

1. **prod 與舊版 App 共用 secure storage 檔**：Windows 的 `%APPDATA%/com.personal/fmp/flutter_secure_storage.dat` 舊版（`flutter_secure_storage` 10.x）也在用；新版 prod 以鍵前綴 `fmp.` 區分，`deleteAll` 只刪自己的前綴。切換（M9）前確認舊版的鍵沒有 `fmp.` 開頭，並決定舊版憑證要不要遷移或清掉。
2. **`Redactor.unregisterSecret` 沒有引用計數**：兩個插件剛好有同一個 cookie 值時，一個登出會連帶取消另一個的遮蔽。機率低；要修就在 `Redactor` 加計數，並補測試。
3. **`PluginHost` 每個帶 `authHeaders` 的請求都呼叫 `Redactor.addRules`**，每次重新編譯 regex。YouTube 的 innertube 請求都會觸發；PR 9 實機若量到影響，改成名稱已登記就跳過。
4. **登出先刪憑證、後清 jar**：中間的極短窗口，jar 裡伺服器設的同名 cookie 可能送出一次。PR 8 加「登入期間 jar 不存」之後再評估要不要調換順序。
5. **`save` 寫入 storage 成功、帳號列寫入失敗**時，記憶體仍是舊憑證、storage 已是新的；下次啟動的對齊會把它收斂。PR 8 的登入流程要把這種失敗回報成登入失敗。
6. **插件更新的窗口裡 `clearCookies` 只清最新那個 client 的 jar**。
7. **「暫時無法讀取」時 `credentialCookieNames` 回空集合**：這段期間 jar 可能送出同名 cookie。PR 8 讓登入回應不進 jar 之後，jar 理論上不會有憑證 cookie。
8. **Linux CI 加了 `libsecret-1-dev`**：`flutter_secure_storage_linux` 的 CMake 要它。Linux 還沒宣告 `secureStorage`，Linux 平台任務再決定要不要開。

## 待升級

- `flutter_inappwebview`：6.2.0 出 stable 時評估升級（目前 6.1.5 是 2024-10 的版本）。
- `qr_flutter`：2023-05 後沒有新版；壞掉時換 `pretty_qr_code`（design §6.4）。
- M2 留下的：`analysis_server_plugin`、`analyzer`、`analyzer_testing` 的釘版；`smtc_windows`。

## 風險與回滾點

| 風險 | 處理 |
|---|---|
| Google 之後擋嵌入式瀏覽器登入（R1 時 Android 的桌面 UA 已被擋） | 決定 8：只提供貼上 cookie；YouTube manifest 拿掉 `webView` 即可，不必發 App |
| `flutter_inappwebview` 6.2.0-beta.3 的登入有問題、或之後的 Flutter／AGP／MSVC 建不起來 | 退回 6.1.5＋AGP 旗標（R1 建置過）；6.2.0 出 stable 就換；Windows 的 STL1011 define 在上游修好時拿掉 |
| Windows 登入後跳轉卡住或程序消失（R1 看到、原因未明） | design §6.4 的提示與重試；PR 9 與 M3a 驗收實測時盯著 |
| YouTube.js 約 800 KB 在 QuickJS isolate 載入太慢，或 YouTube 封鎖目前的 client | PR 1 量兩平台的載入時間；超過 3 秒再談延遲載入或縮小打包。client 被擋時只改插件（ADR 0014 §決定 10 的補充），不發 App |
| Android 上時長未知的串流前瞻接不上（M2 待辦 2） | PR 1 實機確認；不排前瞻、以 `completed` 換歌（design §5.4）。PR 1 的這一部分可單獨 revert |
| 網易 eapi 加密或 `-460` 風控讓匿名取流失敗 | PR 2 先以最少的真實連線確認；失敗時具名回報 blocker，網易在 M3a 驗收裡標「只驗到搜尋」並請擁有者決定（M1 遇到 B 站風控的同一做法） |
| `flutter_secure_storage` 的 Windows 檔案或 Android 金鑰在 dev／prod 間互相看得到 | PR 7 實機確認位置；再以鍵前綴與 `storageNamespace` 保險（design §6.1） |
| `resetOnError` 預設為真，讀取失敗會清掉憑證 | 一律 `resetOnError: false`；`credential_store_test.dart` 以假平台實作守「讀取失敗不刪」，平台層的設定值以 `platform_test.dart` 斷言 |
| 真實帳號在驗證時被風控（YouTube 自動化、B 站 412） | 決定 2：YouTube 用測試帳號；平常只用匿名；最少操作。卡住時改用 `fmp-test` 完成 UI 驗證，真實部分具名回報 |
| `raw.githubusercontent.com` 的 CDN 延遲讓 SHA 短暫不符 | 預期行為（design §7.1 的提示）；驗收在 `fmp-plugins` 合併後等 5 分鐘再做 |
| PR 數量多（22 個加 R1），兩個 repo 交錯 | 拆 M3a／M3b 分段驗收；依「順序與相依」平行開不同目錄的 PR；schema 版本號由後合併的 PR 重排；`fmp-plugins` 的 `FMP_REF` 跟著 FMP 的合併更新 |
| 被取代的請求不取消網路工作（§16 第 2 條）讓快速切歌時多跑幾個請求 | 代價是流量不是行為；控制器的代際檢查有測試。之後若量到問題，再設計讓插件傳呼叫 id 的方式（需要新 ADR） |
| Mix 補歌依賴插件的 `cursor`，YouTube 改版後續播中斷 | 只改插件；宿主在 `cursor` 為空時換種子（design §10），補不到就停在佇列尾端，不影響其他功能 |
