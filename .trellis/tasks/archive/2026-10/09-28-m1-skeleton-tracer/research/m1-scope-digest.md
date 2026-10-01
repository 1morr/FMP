# M1 骨架＋曳光彈：ADR 0008–0027 範圍摘要

> 目的：讓 planner 把 M1 拆成 PR 大小的 child task。本檔只彙整既有 ADR 與計畫的內容，不新增決定。
> 來源：`.trellis/tasks/09-26-fmp-rewrite/milestones.md` §M1、`phase2-plan.md` §7／§8／§9／§10、`docs/adr/0008`–`docs/adr/0027`。
> 格式：每則 ADR 分四段——(a) M1 要做的、(b) M1 的驗證、(c) 不在 M1、(d) ADR 已固定的具體名稱（路徑、類別、套件、檔名）。
> 只寫 ADR 有寫的；ADR 沒寫而由 milestones.md／phase2-plan 補的，來源標 milestones.md／phase2-plan。
> 標「與 M1 無關」者會寫明它屬於哪個里程碑，避免 planner 誤收。

## 0. M1 的權威定義

- **做完**：`milestones.md` §M1——「Android、Windows 上能搜尋 B 站並連續播放兩首。」
- **一句話性質**（ADR 0026 §決定 3 的表）：M1 = 「骨架＋曳光彈」；「接上所有基礎建設；YouTube.js 限時探針；`phase2-plan` §7 全部實測」。
- **範圍清單**：`milestones.md` §M1 的「範圍」七條，對應 ADR 0008、0015、0009、0010、0011、0012、0013、0014、0018、0023、0024、0022。
- **必要驗證**：`phase2-plan` §7「第一個里程碑的必要驗證（各項設計累積）」——「以下全部併入 M1（ADR 0026、`milestones.md`）」，共 10 則 ADR（0008、0009、0010、0011、0014、0015、0018、0022、0023、0024）。
- **驗收**（`milestones.md` §M1）：兩平台端到端操作；§7 全部項目。
- **限時探針**：YouTube.js 可行性；失敗就在 M3 以 Dart 實作 YouTube（ADR 0014 §決定 10、`milestones.md` §M1）。
- **之後**：開 Linux 平台任務（ADR 0026 §決定 4）。

**兩份清單的差異（planner 要注意）**：`milestones.md` 的「範圍」含 ADR 0012（網路層，不含登入）與 ADR 0013（錯誤模型），但這兩則不在 `phase2-plan` §7 的清單裡；§7 另含 ADR 0008／0009／0010 的實測。兩份合起來才是 M1 的完整範圍：

- 要建置的模組：0008、0009、0010、0011、0012、0013、0014、0018（最小集）、0023、0024、0015、0022。
- 只要在 M1「實測」的：0009（CI 矩陣）、0010（原生庫共存）、0011（遮蔽）、0014（`flutter_js` 與 YouTube.js）、0015（QuickJS 進 `flutter test`、dev／prod 隔離、零聯網兩道防線）、0018（前瞻交接、音訊焦點）、0022（release-please）、0023（提示層級、Narrator）、0024（空白鍵、F6、字形）。
- 完全不在 M1：0016、0017、0019、0020、0021、0025（各屬 M2／M4／M6／M7／M3）。

---

## 1. 逐 ADR 摘錄

### ADR 0008 — 同一 repo 的 `app/` 另建新專案

**(a) M1 要做的**
- 在**同一 repo 的 `main`**、子目錄 `app/` 建新的 Flutter 專案；這是它的永久位置，舊專案留在根目錄、凍結（ADR 0008 §決定 2）。
- `app/` 有自己的 `AGENTS.md`（ADR 0008 §決定 2）。
- App 身分沿用舊版：Android `applicationId` `com.personal.fmp` 與**同一把簽名金鑰**；Windows AppUserModelID `com.personal.fmp`；Inno Setup AppId（ADR 0008 §決定 3）。只有同身分 Android 才讀得到舊 App 私有目錄、舊版才能直接升級。
- 開發版另用身分，與正式版分開（ADR 0008 §決定 3；細節在 ADR 0015 §決定 8）。
- 搬運**非音源**的葉節點邏輯（ADR 0008 檔頭補充）：音源相關邏輯不搬 Dart，改以舊程式碼為規格用 JS 重寫（ADR 0014）；其他葉節點例如 `TrackKey` 格式照搬。
- 主幹開發、每個里程碑是可 review 的小 PR、直接合進 `main`（ADR 0008 §決定 1、§後果）。

**(b) M1 的驗證**
- `app/` 不得 import 根目錄舊專案：lint `fmp_layer_imports`（ADR 0008 §如何確認）。
- App 身分識別：測試斷言 prod flavor 的身分值與上列一致（ADR 0008 §如何確認、ADR 0015 §決定 8 的「prod 的身分值與 ADR 0008 一致」）。
- §7：`app/` 的 App 身分識別與舊版一致（開發版除外）。
- 切換前才加的檢查（比對 `applicationId`、AppUserModelID、Inno Setup AppId）屬 M9，不在 M1。

**(c) 不在 M1**
- 刪除根目錄舊專案、`docs/audit/`、ADR 0001–0007；`release.yml`／`ci.yml`／`orca.yaml`／`tool/release/` 改指向 `app/`——切換 PR，M9（ADR 0008 §決定 5、ADR 0026 §決定 5）。
- 舊版緊急修正在 `main` 上改根目錄舊專案、以 `vX.Y.Z` 發版——持續到切換（ADR 0008 §決定 4）。

**(d) ADR 已固定的名稱**
- 路徑：`app/`、`app/AGENTS.md`。
- 值：`com.personal.fmp`（Android `applicationId` 與 Windows AppUserModelID）；舊版檔案位置引用 `android/app/build.gradle.kts:29`、`windows/runner/main.cpp:43`、`pubspec.yaml:121-122`（ADR 0008 §決定 3 的引用）。
- lint：`fmp_layer_imports`（ADR 0015）。
- 葉節點型別：`TrackKey`（ADR 0008 檔頭補充）。

---

### ADR 0009 — 平台層與能力宣告

**(a) M1 要做的**
- 平台層目錄 `app/lib/platform/`，**每個能力一個目錄**，內含 `<能力>.dart`（介面與工廠）與 `<能力>_<平台>.dart`（實作）（ADR 0009 §決定 1）。
- 能力清單：托盤、視窗與標題列、全域快捷鍵、開機自啟、**單一實例**、桌面歌詞視窗、系統媒體控制、**目錄規則**、應用內更新、登入 WebView、執行期權限（ADR 0009 §決定 1）。
- 每個平台一份不可變的 `PlatformCapabilities`；UI 依它決定入口，service 只呼叫介面；執行期才能判斷的由實作在啟動時寫進宣告（ADR 0009 §決定 2）。
- 平台層以外**禁止** `dart:io` 的 `Platform.isX`、`defaultTargetPlatform`、`TargetPlatform` 與平台套件 import（ADR 0009 §決定 3）。
- **不寫空實作**：未驗證平台宣告全部能力為「沒有」、沒有實作檔（ADR 0009 §決定 4）。
- 新的 MethodChannel 一律用 **Pigeon**（ADR 0009 §決定 5）。
- 目錄規則：Android 私有目錄；Windows 安裝版 `%APPDATA%`、Portable 版程式旁 `data/`；Linux `~/.local/share`；macOS／iOS 沙盒 Application Support；開發版另用目錄（ADR 0009 §決定 7）。
- 外觀：Windows、Linux 用自訂標題列；macOS 保留系統紅綠燈；CJK 字型不內建、依平台 fallback（ADR 0009 §決定 8、ADR 0024 §決定 2）。
- 上線順序：Android、Windows 從 M1 起全面驗證；**Linux、macOS、iOS 從 M1 起在 CI 編譯**（iOS 加模擬器測試）（ADR 0009 §決定 9）。
- 系統媒體控制套件：`audio_service`（Android／iOS／macOS）＋ Windows SMTC＋ Linux `audio_service_mpris`；托盤／視窗／快捷鍵／多視窗沿用現有套件並擴到其他桌面平台；`connectivity_plus`、`file_picker`、`path_provider` 五平台共用；桌面套件需修補時用 git 依賴鎖 commit 並註明上游 issue（ADR 0009 §決定 6）。

**(b) M1 的驗證**
- 平台層以外禁平台判斷與平台套件 import：lint `fmp_platform_checks` 與 `fmp_layer_imports`（ADR 0009 §如何確認）。
- CI：從第一個里程碑起建置矩陣含 Linux、macOS、iOS（不簽名）（ADR 0009 §如何確認）。
- §7：CI 建置矩陣含 Linux、macOS、iOS（不簽名）。
- 每個平台 child task 的驗收含「宣告為沒有的能力，UI 不出現入口」——不是 M1（ADR 0009 §如何確認）。

**(c) 不在 M1**
- Linux／macOS／iOS 的實作檔（ADR 0009 §決定 4、附帶否決）。
- Linux 實機驗證（VMware 虛擬機）、macOS／iOS child task（ADR 0009 §決定 9、ADR 0026 §決定 4）。
- 桌面歌詞視窗、Android 懸浮歌詞、iOS Live Activity 的實作（ADR 0021，M7）。

**(d) ADR 已固定的名稱**
- 路徑：`app/lib/platform/`；`PlatformCapabilities`；`PermissionGateway`（ADR 0020 §決定 9；見 §3 矛盾表）。
- 套件：`tray_manager`、`window_manager`、`hotkey_manager`、`smtc_windows`、`audio_service`、`audio_service_mpris`、`connectivity_plus`、`file_picker`、`path_provider`。
- lint：`fmp_platform_checks`、`fmp_layer_imports`。
- 能力名（後續 ADR 定義，平台層要宣告）：`desktopLyrics`（`clickThrough`、`alwaysOnTop`）、`overlayLyrics`、`liveActivityLyrics`（ADR 0021 §決定 8–10）、`appUpdate`（ADR 0022 §決定 5）、`pluginDevTools`（ADR 0025 §決定 2）。

---

### ADR 0010 — drift（SQLite）＋舊資料匯入

**(a) M1 要做的**
- 選型：`drift` ＋ `sqlite3`（**native assets 自動打包五平台原生庫**）（ADR 0010 §決定 1）。
- 資料庫檔在 ADR 0009 定義的資料目錄；**只有資料層（repository）能存取資料庫**（ADR 0010 §決定 1）。
- Schema 原則：關係交給資料庫（外鍵、`ON DELETE`、唯一鍵）；曲目以 `TrackKey` 字串（含 cid，ADR 0005）為唯一鍵；只存事實；串流 URL 不進資料庫；下載紀錄獨立成表；**設定存在同一個資料庫的設定表**；時間存 UTC epoch 毫秒；音源 id 用字串（ADR 0010 §決定 2）。
- Schema 演進：每版以 `drift_dev schema dump` 存快照；每個 migration 有升級測試；migration 不得改寫使用者設定過的值；migration 失敗整個回滾、顯示錯誤頁（ADR 0010 §決定 3）。
- M1 只建「**最小 schema 與快照**」（`milestones.md` §M1）——ADR 未列舉最小集是哪幾張表（見 §3）。
- 目錄 `app/lib/legacy_import/` 是**唯一**依賴 `isar_community` 與 `flutter_secure_storage` 10.x 的地方（ADR 0010 §決定 4）。

**(b) M1 的驗證**
- Schema 快照與每個 migration 的升級測試在 CI 執行（ADR 0010 §如何確認）。
- 「migration 不改使用者設定過的值」有專門測試（ADR 0010 §如何確認）。
- 資料庫只由資料層存取、`legacy_import/` 不被其他模組 import：lint `fmp_layer_imports`（ADR 0010 §如何確認）。
- §7：`isar_community`＋`sqlite3` 原生庫在 **Android、Windows 共存**；`sqlite3` 的 Android **16KB page size 對齊**（ADR 0010 §後果「第一個里程碑在 Android、Windows 實測」）。
- 若共存衝突：legacy import 改成由新 App 啟動的獨立一次性小程式（ADR 0010 §後果）。

**(c) 不在 M1**
- 完整的舊資料匯入流程（唯讀開舊 Isar、暫存庫、筆數驗證、抽樣比對、外鍵完整後才換上正式庫、匯入紀錄、錯誤頁、舊備份檔匯入、「刪除舊版資料」）——M5（`milestones.md` §M5、ADR 0010 §決定 4）。
- 真實資料副本上完整跑一次匯入、筆數比對——M5／切換前（ADR 0010 §如何確認）。
- `isate_community`／舊 secure storage 的移除（保留到另立 ADR）（ADR 0010 §決定 4 最後一項）。

**(d) ADR 已固定的名稱**
- 套件：`drift`、`sqlite3`、`isar_community` 3.3.2、`flutter_secure_storage` 10.x（legacy import 用）／11.x（新憑證，ADR 0012）。
- 路徑：`app/lib/legacy_import/`；`drift_dev schema dump` 的 schema 快照。
- 表名（ADR 0019 才定義，M4）：`playlists`、`playlist_remote`、`playlist_entries`、`tracks`、`track_origins`、`match_results`；`downloads`（ADR 0020，M6）；`lyrics_matches`（ADR 0021，M7）；`cache.db` 為獨立索引（ADR 0016，M2）。
- 資料庫開啟：`PRAGMA foreign_keys = ON`（ADR 0019 §決定 1）。

---

### ADR 0011 — 單一日誌門面與單一遮蔽函式；設定依功能分組

**(a) M1 要做的**
- **日誌門面**：全 App 只有一個 log 入口，參數含訊息、tag（模組或音源 id）、error、stackTrace、結構化欄位；門面先遮蔽再交給 `talker`（只用它的歷史與分派）。門面以外禁 `print`、`debugPrint`、`developer.log` 與直接用 talker（ADR 0011 §決定 1）。
- **輸出**：記憶體歷史最近 1,000 筆；檔案在 ADR 0009 資料目錄的 `logs/`，**單檔 2MB、保留 3 個**，寫入失敗不影響 App；console 只在 debug build；release 預設層級 `info`，開發者模式可調 `debug`（ADR 0011 §決定 2）。
- **遮蔽函式**（唯一一個）依序：header 名單、key 名單（query 與 body）、已知媒體 CDN 的簽名參數去除、已知憑證值逐字替換（帳號層登記各音源實際憑證值）；套用在訊息、error 字串、stackTrace、結構化欄位；名單集中一處，音源插件可追加（ADR 0011 §決定 3）。
- **網路紀錄**：自己的 dio 攔截器，每請求一筆摘要（方法、主機、路徑、遮過的 query、狀態、耗時、大小、音源、錯誤類型），經門面寫入；**不記 body**（ADR 0011 §決定 4）。
- **錯誤歷史**：統一錯誤型別被處理時一律經門面以 `warning`／`error` 寫入（ADR 0011 §決定 5）。
- **設定**：依功能分組（播放、外觀、音樂庫與同步、下載、歌詞、網路、桌面、開發者），**每組一張單列表**、每個設定一個有型別的欄位、每組一個 Riverpod Notifier；**欄位為空＝使用者沒設定過**，讀取時套用程式預設；每個音源的設定另一張表以音源 id 為主鍵（ADR 0011 §決定 7）。
- M1 只要「log 門面、遮蔽函式、log 檔」（`milestones.md` §M1）；設定分組的表要建，但**各組的欄位清單在引入該組設定的里程碑才定案**（ADR 0011 §後果、ADR 0026 §決定 2）。

**(b) M1 的驗證**
- lint：門面以外禁 `print`／`debugPrint`／`developer.log`／import talker：`fmp_log_facade`（ADR 0011 §如何確認）。
- **遮蔽測試**：每個音源一組假憑證與假簽名 URL，斷言經 log 檔、記憶體歷史、診斷包、網路紀錄後都不再出現原值，**包括出現在 stackTrace 的情況**（ADR 0011 §如何確認）。
- 設定測試：寫入使用者值後改程式預設，斷言讀到的仍是使用者值；未設定的欄位讀到新預設（ADR 0011 §如何確認）。
- §7：log 門面與遮蔽函式是第一個里程碑的基礎，**含遮蔽測試**。

**(c) 不在 M1**
- 診斷包（純文字＋JSON、`diagnostics.txt`／`diagnostics.json`）——ADR 0011 §決定 6、ADR 0025 §決定 10，M3。
- Debug 頁的 log 檢視、錯誤歷史跨重啟、JSON Lines、保留 7 天——ADR 0025（M3）與 ADR 0017（M2）。
- 各組設定的欄位清單——各里程碑（ADR 0026 §決定 2）。

**(d) ADR 已固定的名稱**
- 路徑：`app/lib/core/logging/`、`app/lib/core/redaction/`；資料目錄下 `logs/`。
- 套件：`talker`（資料核心）。
- lint：`fmp_log_facade`。
- 設定分組八組名：播放、外觀、音樂庫與同步、下載、歌詞、網路、桌面、開發者。
- 參照實作：Finamp `censored_log.dart`；NewPipe 錯誤報告欄位；Spotube 的 drift 設定＋`watchSingle()`。

---

### ADR 0012 — 網路層與帳號

**(a) M1 要做的**（`milestones.md` §M1：「網路層（不含登入）」）
- **HTTP 層**：每個音源一個 **API client**（dio），該音源所有 service 共用；攔截器順序＝認證注入、cookie 管理、錯誤對應、限流與退避、網路紀錄（ADR 0011）（ADR 0012 §決定 1）。
- 另有**媒體 client** 專抓音訊位元組，只加媒體 headers（Referer、UA），**不掛認證攔截器與 cookie 管理**（ADR 0012 §決定 1）。
- 匿名用非機密 cookie（例如 B 站 `buvid`）存資料庫（ADR 0012 §決定 1）。
- 轉址：宿主 HTTP 跟隨轉址時每一跳都要在 manifest 網域內、**最多 5 跳**；媒體 client 跟隨轉址時每一跳只帶媒體 headers（ADR 0012 §決定 1）。
- **帶憑證的單一宣告點**：每個請求在音源插件的定義處宣告 `AuthRequirement`——`required`／`userPreference`／`never`（預設）；認證攔截器只依此標記注入；網路紀錄記錄每請求是否帶憑證（ADR 0012 §決定 2）。
- 舊原則併入：**憑證只用在向音源解析串流與 API 請求，抓音訊位元組的請求一律不帶憑證**（ADR 0012 §背景）。
- cookie 用 `cookie_jar` ＋ `dio_cookie_manager`（ADR 0012 §考慮過的選項、§採用的慣例）。
- 憑證存放 `CredentialStore`（`flutter_secure_storage` 11.x，以音源 id 為鍵）；讀取失敗狀態為「暫時無法讀取」並稍後重試、**不刪除**；憑證載入或更新時登記到遮蔽函式（ADR 0012 §決定 3）。

**(b) M1 的驗證**
- 契約測試：每個音源的媒體請求經媒體 client 發出後，**請求上不含任何 Cookie／Authorization**（ADR 0012 §如何確認）。
- 測試：`AuthRequirement` 三種標記在「未登入／已登入且開關開／已登入且開關關」下的注入結果（ADR 0012 §如何確認）。
- 測試：刷新後重送的請求帶的是新憑證；每個音源的「憑證無效」判定表；限流與網路錯誤碼不會把帳號標為失效；登出與重設後 `CredentialStore` 為空（ADR 0012 §如何確認）——**多數需要登入層，屬 M3**。
- 註：ADR 0012 **不在** `phase2-plan` §7 的清單裡；M1 對它的驗證要求來自 §決定 1、2 與 ADR 0014 §如何確認的契約測試（媒體不帶憑證、只連 manifest 網域）。

**(c) 不在 M1**
- 登入（QR、App 內網頁登入、貼上 cookie）、`CredentialStore` 的實際登入流程、帳號頁、刷新與失效判定表、登出——M3（`milestones.md` §M3：「帳號與 `CredentialStore`、`AuthRequirement`（ADR 0012，E6）」）。
- 「以登入身分瀏覽與播放」開關（ADR 0012 §決定 6）——M3。
- YouTube App 內網頁登入實測——§8，M3。
- Linux 沒有 keyring 時的 secure storage 行為——§8，Linux child task。
- 只能匯入的來源 Spotify／QQ 的 `never` 標記（ADR 0012 §決定 7）——M4。

**(d) ADR 已固定的名稱**
- 套件：`dio`、`cookie_jar`、`dio_cookie_manager`、`flutter_secure_storage` 11.x。
- 型別：`AuthRequirement`（`required`／`userPreference`／`never`）、`CredentialStore`、`QueuedInterceptor`。
- 舊版參照：`SourceUrlPolicy.resolveRedirects`（轉址做法）。

---

### ADR 0013 — 統一錯誤模型

**(a) M1 要做的**
- **分類**：一個 sealed `AppError`，成員 `NetworkError`、`RateLimited`、`AuthRequired`、`CredentialInvalid`、`VerificationRequired`、`Unavailable`（附原因：地區、版權、會員、年齡、只有試聽）、`NotFound`、`ParseError`、`Unsupported`、`UnexpectedError`（ADR 0013 §決定 1）。
- 共同欄位：音源 id、`retryable`、`retryAfter`、給使用者的 i18n 訊息 key 與參數、`expected`、原始 error 與 stackTrace（只進 log、經遮蔽）、對應的網路紀錄 id（ADR 0013 §決定 1）。
- **轉換位置**：網路層把傳輸錯誤轉成 `NetworkError`；**每個音源在自己的目錄內**以對應表把狀態碼與錯誤碼轉成 `AppError`；未知例外在音源邊界包成 `UnexpectedError`；音源邊界以上只看得到 `AppError`（ADR 0013 §決定 2）。
- **傳遞**：音源與 service 丟 `AppError`；Riverpod provider 以 `AsyncValue.error` 承接，UI 以 exhaustive `switch` 呈現；禁止空 catch 與靜默吞錯（ADR 0013 §決定 3）。
- **重試只有一層**：Riverpod 自動重試**全域關閉**；網路層依音源宣告策略重試——只重試冪等請求、只重試 `NetworkError`／`RateLimited`／音源標為可重試者、指數退避＋全抖動、尊重 `Retry-After`、**次數上限預設 2**；每音源有併發上限與最小請求間隔（ADR 0013 §決定 4）。
- **呈現**：ADR 0013 §決定 5 的類別表（網路／限流／需登入／憑證無效／風控驗證／無法取得／找不到／解析失敗／不支援）；訊息一律來自 i18n；部分成功要標出失敗音源；背景工作不跳 toast；同類別＋同音源短時間只提示一次；開發者模式下附「詳細」。

**(b) M1 的驗證**
- 契約測試：每個音源以錄下的錯誤回應 fixture，斷言對應到的 `AppError` 類別（ADR 0013 §如何確認）。
- 測試：`ProviderScope` 的 retry 為關閉；網路層只對冪等請求重試、尊重 `Retry-After`（ADR 0013 §如何確認）。
- lint：禁止空 catch（`fmp_no_empty_catch`）；禁止 UI 顯示 `toString()` 之類原文（以只接受 i18n key 的呈現 API 在型別上擋住）（ADR 0013 §如何確認）。

**(c) 不在 M1**
- 完整音源（YouTube、網易）的錯誤對應表——M3。
- 「詳細」頁與 GitHub 回報（`ErrorReport`、`.github/ISSUE_TEMPLATE/bug_report.yml`）——ADR 0023、M3（`milestones.md` §M3）。
- 播放層的跳過與停止條件（`RecoveryPolicy` 全表）——ADR 0018、M2。
- B 站 geetest 驗證互動——功能凍結待辦（ADR 0013 §考慮過的選項）。

**(d) ADR 已固定的名稱**
- 型別：`AppError` 及十個子類別（名稱如上）；欄位名 `retryable`、`retryAfter`、`expected`。
- lint：`fmp_no_empty_catch`。
- 設定：Riverpod 全域 `retry` 關閉。
- 參照：NewPipe `ErrorInfo`；AWS Exponential Backoff And Jitter；Finamp 的「類別＋來源」去重。

---

### ADR 0014 — 音源是執行期 JS 腳本插件

**(a) M1 要做的**
- 一套介面 `SourcePlugin`：App 其他部分只認介面與能力宣告，UI 與 service 沒有針對特定音源的分支（ADR 0014 §決定 1）。
- **JS 執行環境**：引擎 `flutter_js`（Android／Windows／Linux 用 QuickJS，iOS／macOS 用 JavaScriptCore），**ES2020**（ADR 0014 §決定 2）。
- manifest 欄位：`id`（字串音源 id）、名稱、版本、作者、`apiVersion`、能力、允許的網域、登入方式、重試與限流策略、遮蔽名單追加、預設值、圖示（ADR 0014 §決定 3）。
- 能力枚舉：`search`、`resolveStream`、`trackDetail`、`multiPart`、`importPlaylist`、`libraryRead`、`libraryWrite`、`charts`、`live`、`mix`、`lyrics`、`login`；可播放音源＝有 `resolveStream`（ADR 0014 §決定 4）。
- **宿主 API v1**（M1 的最小集）：`http.request`（經 ADR 0012／0013 網路層、只能連 manifest 網域）、`crypto`、每插件 `storage`、只讀自己音源的 `credentials`、`log`（經 ADR 0011 門面）、結構化錯誤（宿主轉成 `AppError`）；沒有檔案系統、任意 socket、其他插件的資料（ADR 0014 §決定 5）。
- 資料交換為以 `apiVersion` 版本化的 JSON DTO，宿主提供 **TypeScript 型別定義**（ADR 0014 §決定 5）。
- `resolveStream` 輸入含平台可播格式與用途（播放；下載 ADR 0020），輸出為依優先序排好的候選串流；回傳網址期限 `expiresAt`（插件從網址本身讀）；封面為多尺寸清單 `artwork`（ADR 0014 §決定 5、ADR 0016 §決定 4）。
- **M1 的載入方式**：以「**從檔案安裝**」載入第一個腳本音源（B 站）（`milestones.md` §M1、`phase2-plan` §7）。
- 匹配：宿主一份共用評分核心，歌單匯入與歌詞共用（ADR 0014 §決定 9）——實作屬 M4／M7。

**(b) M1 的驗證**
- 結構測試：每個插件的 manifest 能力與它實際匯出的函式一致；`apiVersion` 不相容時拒絕載入（ADR 0014 §如何確認）。
- 契約測試：以錄下的 HTTP 回應重播執行每個插件的檢查案例，涵蓋 ADR 0011（遮蔽）、0012（媒體請求不帶憑證、`AuthRequirement`）、0013（錯誤對應）；插件 repo 的 CI 與插件作者本機都能跑（ADR 0014 §如何確認）。執行器與 fixture 格式見 ADR 0015。
- 測試：宿主 HTTP 拒絕 manifest 網域以外的請求；腳本無法讀取其他插件的 storage 與憑證（ADR 0014 §如何確認）。
- lint：UI 與 service 不得出現音源 id 字串常數或特定音源的型別：`fmp_source_id_literal`（ADR 0014 §如何確認）。
- §7：JS 執行環境（`flutter_js`）與宿主 API 最小集合；以「從檔案安裝」載入第一個腳本音源；**`flutter_js` 在 Android、Windows 的 Promise／記憶體／啟動成本實測**；**YouTube.js 可行性驗證**（有時限，失敗則 YouTube 暫以 Dart 實作）。
- YouTube.js 探針的具體條件：YouTube.js 在 `flutter_js` 能否搜尋並解出串流（它官方只寫支援 Node.js、Deno、瀏覽器，需宿主提供 fetch 與 eval）（ADR 0014 §決定 10）。

**(c) 不在 M1**
- 插件庫 repo `1morr/fmp-plugins`、其 CI、`index.json`（含 SHA-256）、App 插件頁、首次啟動引導、一鍵更新——M3（ADR 0014 §決定 6–8、`phase2-plan` §9「第一個里程碑不需要」）。
- YouTube、網易雲插件——M3。
- Spotify／QQ 僅元資料來源——M4。
- 歌詞源與 `aiAssist`——M7（ADR 0021）。
- 匹配流程的實作——M4／M7。

**(d) ADR 已固定的名稱**
- 型別：`SourcePlugin`、`SourceCapability` 系列（舊版名，新介面為 `SourcePlugin`）。
- 引擎：`flutter_js`（QuickJS／JavaScriptCore）。
- 能力名：上列 12 個。
- DTO 欄位：`apiVersion`、`expiresAt`、`artwork`（`[{url, width?}]`）、`checks.json`（ADR 0015 §4）。
- lint：`fmp_source_id_literal`。
- repo 名（M3）：`1morr/fmp-plugins`。

---

### ADR 0015 — 測試與閘門、開發環境、CI

**(a) M1 要做的**
- **lint 套件** `app/packages/fmp_lints/`，以官方 `analysis_server_plugin` 自寫規則；`app/analysis_options.yaml`（ADR 0015 §決定 2）。
- 十條核心規則：`fmp_layer_imports`、`fmp_no_empty_catch`、`fmp_log_facade`、`fmp_source_id_literal`、`fmp_url_literal`、`fmp_no_for_testing`、`fmp_http_client_owner`、`fmp_test_waits`、`fmp_ignore_reason`、`fmp_platform_checks`（ADR 0015 §決定 2 的表）。
- 後續 ADR 新增的規則：`fmp_periodic_timer_owner`（ADR 0017；ADR 0021 加入桌面歌詞查游標的允許擁有者）、`fmp_toast_entry`（ADR 0023）、`fmp_design_tokens`（ADR 0024）（ADR 0015 §決定 2 末段）。**哪幾條屬 M1 未寫死**（見 §3）。
- 每條規則以官方 `analyzer_testing` 做**雙向變異測試**（違規會報、無關改動不報）（ADR 0015 §決定 2）。
- CI 跑 `dart analyze --fatal-infos`（因 `flutter analyze` 目前不顯示插件診斷，flutter/flutter#193203），並以**接線哨兵**（暫放違規檔、斷言分析失敗且含規則名）證明規則接上 `app/`（ADR 0015 §決定 2）。
- **預設零聯網**：`app/dart_test.yaml` 對 `live` tag 設 `skip`、以 preset 解除；`app/test/flutter_test_config.dart` 以 `HttpOverrides.global` 讓建立真實 `HttpClient` 直接失敗（ADR 0015 §決定 3）。
- **檢查案例一份四用**：每插件每能力最多一條檢查案例（`checks.json`），同一份用於契約測試（重播 fixture，進 CI）、冒煙測試（真實連線，插件庫 `--live` 手動）、Debug 頁健康檢查（M3）、錄製（ADR 0015 §決定 4）。
- **fixture**：錄製與重播在宿主網路層最底部的 dio `HttpClientAdapter`；一次請求／回應一個 JSON 檔（`meta`＋`request`＋`response`）；寫檔前一律經 ADR 0011 遮蔽函式；重播比對 method＋排序後的 URL＋順序（ADR 0015 §決定 5）。
- **契約執行器**：一個通用套件以重播執行每個案例；`app/` 的 CI 對 `app/test/fixtures/plugins/` 內的測試插件執行（合成資料、播放本機音檔），不依賴官方插件庫；同一個測試插件也供開發版離線開發（ADR 0015 §決定 6）。
- **開發版**：flavor `dev`／`prod`，`pubspec.yaml` 設 **`default-flavor: dev`**，發版明確帶 `--flavor prod`；dev 的 Android `applicationIdSuffix ".dev"`、Windows AppUserModelID `com.personal.fmp.dev`、名稱「FMP Dev」與標記圖示、資料目錄／單一實例鎖／secure storage 命名空間加 `-dev`；prod 維持 ADR 0008 的身分；開發版資料預設空白；**開發版拒絕直接讀舊版正式資料位置**（ADR 0015 §決定 8）。
- **CI 切分**：`dorny/paths-filter` 依專案切分——`app/**` 與 `.github/**` 觸發 `app` 的 job，`app/` 以外的任何變動（含文件）觸發舊專案的 job；**一個 `always()` 彙總 job 當唯一必要檢查**（ADR 0015 §決定 9）。
- `app` 的 job 內容：format、`dart analyze`、接線哨兵、`flutter analyze`、lint 規則測試、不加參數的 `flutter test`、契約執行器、Android／Windows／Linux／macOS／iOS（不簽名）建置、Linux 與 Windows 的整合測試（ADR 0015 §決定 9）。
- 整合測試只挑：搜尋→播放、從檔案安裝插件、舊資料匯入（ADR 0015 §決定 1）。
- 分層：單元、widget（provider override 注入假資料）、插件契約、整合、golden（只給設計系統共用元件，`alchemist` 的 CI golden）；**不設覆蓋率門檻**；`lib/` 不留測試掛鉤，一律經建構子或 provider 注入（ADR 0015 §決定 1）。

**(b) M1 的驗證**
- `fmp_lints` 每條規則的 `analyzer_testing` 測試；CI 的接線哨兵（ADR 0015 §如何確認）。
- **第一個里程碑實測**（ADR 0015 §如何確認、§7）：
  - `dart analyze` 看得到插件診斷；
  - **契約執行器能否在 `flutter test` 內載入 QuickJS**（不行改用桌面 `integration_test`）；
  - dev 與 prod 同時開啟時身分、鎖、資料目錄各自獨立；
  - 一個故意聯網的測試在裸 `flutter test` 被跳過、**解除 tag 後被 `HttpOverrides` 擋下**（零聯網兩道防線）。
- 測試：prod 的身分值與 ADR 0008 一致、dev 每一項都不同；開發版拒絕舊版正式資料路徑；掃描所有 fixture 不得有未遮蔽憑證（ADR 0015 §如何確認）。
- `AGENTS.md`（`app/`）列出的每條靜態規則都寫出對應規則名；沒有規則守的不寫進去（ADR 0015 §如何確認）。

**(c) 不在 M1**
- 舊專案的 static-rule：原樣留在舊專案守舊程式碼，**切換 PR 時一併刪除**（ADR 0015 §決定 10）。
- 舊專案的 job：維持現狀，只在根目錄變動時跑，`app/` 的 PR 不被舊專案不穩測試擋住（ADR 0015 §決定 9）。
- App 內插件開發工具（開發者模式、資料夾載入、真實／錄製／重播切換）——M3（ADR 0015 §決定 7、ADR 0025 §決定 7）。
- `fmp_periodic_timer_owner` 的實作（需 `BackgroundScheduler`）——M2。
- `riverpod_lint` 是否已遷移到新插件系統「在落地時查證」（ADR 0015 §後果）。

**(d) ADR 已固定的名稱**
- 路徑：`app/packages/fmp_lints/`、`app/analysis_options.yaml`、`app/dart_test.yaml`、`app/test/flutter_test_config.dart`、`app/test/fixtures/plugins/`。
- 檔名：`checks.json`。
- 規則名：上列 10＋3 條。
- flavor：`dev`／`prod`；`default-flavor: dev`；`applicationIdSuffix ".dev"`；AppUserModelID `com.personal.fmp.dev`；名稱「FMP Dev」。
- CI：`dorny/paths-filter`；`always()` 彙總 job；`dart analyze --fatal-infos`；接線哨兵。
- 套件：`analysis_server_plugin`、`analyzer_testing`、`alchemist`。
- 舊檔引用：`.trellis/tasks/archive/2026-09/09-27-design-testing/design.md` §6（舊 static-rule 去向的逐條清單）。

---

### ADR 0016 — 快取與離線

**與 M1 無關（主體屬 M2）**，但有兩個 M1 的鉤子要記：

- (a) ADR 0018 §決定 6 的串流解析順序是「本機下載檔 → **記憶體網址快取（ADR 0016）** → 插件 `resolveStream`」；ADR 0018 §決定 7 的恢復策略要「**不在 `Online` 時暫停計數（ADR 0016）**」。
- (c) `milestones.md` §M2 把「統一快取庫與離線狀態（ADR 0016）」整包放在 M2。
- 兩者的衝突見 §3。
- (d) 名稱（M2 才建）：快取模組、`cache.db`（獨立 drift 索引）、`getApplicationCacheDirectory()`、總上限 128MB／256MB／512MB／1GB、`connectivity_plus`、`cached_network_image`；串流網址記憶體快取上限 **64 筆**、有效到 `expiresAt − 5 分鐘`、為空時 5 分鐘內有效（ADR 0016 §決定 5、6）。
- ADR 0016 §如何確認的「**預取後播放只解析一次**」是 ADR 0018 §如何確認也列的一項——M1 做播放核心時就會碰到的行為，但完整快取庫在 M2。

---

### ADR 0017 — 背景任務排程器

**與 M1 無關（M2）。**

- (c) `BackgroundScheduler`、「啟動維護清單」（ADR 0025 加入 log 保留期限與診斷包暫存清理；**清單在 M2 實作**，`milestones.md` §M2）、`fmp_periodic_timer_owner` lint、排行／匯入歌單／電台刷新間隔設定——全部 M2。
- (b) M1 只碰到一件事：ADR 0018 §決定 11 說播放模組的位置檢查（每秒）與位置存檔（每 10 秒）是 `fmp_periodic_timer_owner` **允許的播放模組**——M1 的播放核心最小集若要持久化位置就會碰到這條 lint 的允許清單（但 lint 本身屬 M2）。
- log 保留 7 天（ADR 0011 §後果指向 ADR 0025，再由 ADR 0017 的啟動維護清單執行）——M2／M3。

---

### ADR 0018 — 播放核心（M1 取最小集）

**(a) M1 要做的**（`milestones.md` §M1：「播放核心最小集：兩個後端、兩首的佇列、前瞻交接」）
- `PlaybackController` 是 UI、系統媒體控制與直播的唯一播放入口；協作者（`QueueModel`、`PlaybackSession`、`StreamResolver`、`PlaybackEventRouter` 純函數、`RecoveryPolicy` 純函數、`NowPlayingPublisher`）只回報、不寫狀態（ADR 0018 §決定 1）。
- 一份 sealed 播放狀態：`Idle`、`Loading`、`Playing`、`Paused`、`Buffering`、`Retrying`、`Failed(AppError)`；位置等高頻資料走獨立 stream；`QueueState` 與播放狀態沒有共同欄位（ADR 0018 §決定 2）。
- **後端**：`AudioBackend` 介面，兩個實作——`JustAudioBackend`（Android、iOS、macOS）與 `MediaKitBackend`（Windows、Linux）；不能收斂的差異寫在介面 dartdoc，可收斂的規則（結束原因分類、直播邊緣 seek、前瞻計畫）是共用純函數並有契約測試；平台層宣告使用哪個實作與可播格式；**後端只持有「目前＋一個前瞻」**（＝前瞻交接／gapless 的機制）（ADR 0018 §決定 3）。
- **Android 換歌時不釋放音訊焦點**（ADR 0018 §決定 3）。
- 佇列真相在 Dart 端 `QueueModel`；模式為 `queue`、`temporary`、`mix`、`live`、`detached`；所有加入方式檢查 **10,000 首上限**（ADR 0018 §決定 4）——M1 只做「兩首的佇列」，其餘模式屬 M2。
- 串流解析：本機下載檔 → 記憶體網址快取（ADR 0016）→ 插件 `resolveStream`；輸入含分 P、用途與平台可播格式，輸出為依優先序排好的候選串流（網址、標頭、格式、`expiresAt`）；開流失敗換候選一次（ADR 0018 §決定 6）。
- 系統媒體控制：`NowPlayingPublisher` 唯一出口；轉接器 Android／iOS／macOS 用 `audio_service`、Linux 用 `audio_service_mpris`、Windows 用 `smtc_windows`（ADR 0018 §決定 8、ADR 0009 §決定 6）——M1 的「兩個後端」是否含系統媒體控制未寫死（見 §3）。

**(b) M1 的驗證**
- §7：兩個後端的**前瞻交接（gapless）**；**Android 換歌時不釋放音訊焦點**（ADR 0018 §如何確認、`phase2-plan` §7）。
- 後端契約測試：同一份純規則斷言跑兩個實作與假後端（ADR 0018 §如何確認）。
- lint `fmp_layer_imports` 的依賴表：`just_audio`、`media_kit` 只在後端實作目錄；結束原因型別只給後端與路由器 import；串流存取的窄介面只給 `PlaybackSession` import（ADR 0018 §如何確認）。這一組取代舊 `playback_event_routing`、`audio_seam`、`audio_backend_shared_rules` static-rule。
- 單元測試的完整清單（`QueueModel`、`RecoveryPolicy`、開直播取消音樂請求、預取只解析一次、單曲循環）——多數屬 M2。

**(c) 不在 M1**
- 完整 `QueueModel` 與 `RecoveryPolicy`——M2（`milestones.md` §M2）。
- 隨機、拖曳、臨時播放快照、Mix 修剪、單曲循環（D6）、播放歷史（E15）——M2。
- 開直播取消音樂請求、直播狀態輪詢、`D10` 區分——M2／M3（電台在 M3）。
- 位置持久化的完整規則（每 10 秒及暫停、seek、進背景時存）、速度不持久化（E19）——M2。
- 均衡器、響度、睡眠定時器——功能凍結待辦。
- 蘋果平台 AVPlayer 對 B 站 DASH 音訊與直播 HLS 的支援——§8，macOS／iOS child task。

**(d) ADR 已固定的名稱**
- 型別：`PlaybackController`、`QueueModel`、`PlaybackSession`、`StreamResolver`、`PlaybackEventRouter`、`RecoveryPolicy`、`NowPlayingPublisher`、`AudioBackend`、`JustAudioBackend`、`MediaKitBackend`；狀態列舉名如上；模式名 `queue`／`temporary`／`mix`／`live`／`detached`。
- 設定名：「記住播放位置」、「臨時播放回佇列倒退秒數」、新設定「跳過試聽片段」（預設開）（ADR 0018 §決定 7、10）。
- 套件：`just_audio`、`media_kit`、`audio_service`、`audio_service_mpris`、`smtc_windows`。

---

### ADR 0019 — 音樂庫與同步

**與 M1 無關（M4）。**

- (c) `playlists`／`playlist_remote`／`playlist_entries`／`tracks`／`track_origins`／`match_results` 表、刷新、遠端操作、僅元資料來源匯入、共用評分核心——全部 M4（`milestones.md` §M4）。
- M1 只借到兩件事：`TrackKey` 格式（ADR 0005，ADR 0010 §決定 2 引用為唯一鍵）、`PRAGMA foreign_keys = ON`（M1 建 schema 時的開啟方式）。
- §8：`opencc` native assets 在各平台建置——M4 驗收。
- (d) 匹配套件（M4）：`unorm_dart`（NFKC）、`opencc`（繁簡）、`string_similarity`（Dice）；`fuzzywuzzy` 已否決（GPL-2.0）。

---

### ADR 0020 — 下載與權限

**與 M1 無關（M6）。**

- (c) `background_downloader`、`downloads` 表、下載根目錄與檔名、內嵌標籤與 sidecar、啟動對帳、下載設定——全部 M6（`milestones.md` §M6）。
- (a) M1 只碰到平台層的 `PermissionGateway`（ADR 0009 §決定 1 把「執行期權限」列為平台層能力，ADR 0020 §決定 9 才定義它）——見 §3。
- (b) §8（M6）：`permission_handler` 在 Windows 是否使 FMP 出現在位置權限清單；寫入的標籤能被常見播放器讀到；Android 以 `MANAGE_EXTERNAL_STORAGE` 搬移到使用者資料夾。
- (d) 名稱（M6）：`PermissionGateway`；`MANAGE_EXTERNAL_STORAGE`、`POST_NOTIFICATIONS`、`REQUEST_INSTALL_PACKAGES`；根目錄 `Music/FMP`（Android）、`%USERPROFILE%\Music\FMP`（Windows）；檔名格式 `{根目錄}/{音源}/{標題} [{影片 id}].{副檔名}`、多分 P `P01 {分P標題}.{副檔名}`；標題截到 80 字。

---

### ADR 0021 — 歌詞

**與 M1 無關（M7），但有兩個 M1 的平台層鉤子。**

- (c) `lyrics`／`aiAssist` 能力、歌詞文件 DTO、`lyrics_matches` 表、`LyricsSession`、桌面歌詞視窗、Android 懸浮歌詞、iOS Live Activity——全部 M7（`milestones.md` §M7）。
- (a) M1 相關的只有平台層：能力名 `desktopLyrics`（`clickThrough`、`alwaysOnTop`）、`overlayLyrics`、`liveActivityLyrics` 要在 `PlatformCapabilities` 裡出現但未驗證平台宣告「沒有」（ADR 0009 §決定 2、4；ADR 0021 §決定 8–10）。
- (d) 套件（M7）：`desktop_multi_window`、`window_manager`、`flutter_overlay_window`、`flutter_lyric`（避開已撤回的 3.0.5，或自寫）；lint 允許：`fmp_periodic_timer_owner` 加入平台層桌面歌詞模組（查游標）、`fmp_layer_imports` 限制上述套件只在平台層實作檔。
- (c) `window_manager` 0.5.x 已停止維護（0.6.0 改建在 `nativeapi`）——M1 就要選版本，見 §3。

---

### ADR 0022 — 發版與應用內更新（M1 只做 dry-run）

**(a) M1 要做的**（`milestones.md` §M1：「`app/` 發版 workflow 以 release-please dry-run 驗證」）
- release-please 以 **manifest 模式、`dart` 策略**管理 `app/`：每次 commit 進 `main` 就維護一個發版 PR——依 Conventional Commits 算下一版、改 pubspec、寫 `app/CHANGELOG.md`（ADR 0022 §決定 1）。
- 合併發版 PR 是唯一人工動作；**同一個 workflow** 接著打 tag `v{版本}`、建置、驗證、上傳 asset 並轉為正式發布（GitHub 預設 token 建的 tag 不會觸發其他 workflow，所以放同一個 workflow）（ADR 0022 §決定 1）。
- `versionCode` 沿用 `major*1000000 + minor*1000 + patch`，由 workflow 從 tag 算出（ADR 0022 §決定 1）。
- 發版一律 `--flavor prod`（ADR 0022 §決定 1、ADR 0015 §決定 8）。
- **重寫期間不發版**（ADR 0022 §決定 1）——所以 M1 只能 dry-run 或測試 repo。

**(b) M1 的驗證**
- §7：release-please 的發版 PR 與同一 workflow 的建置、驗證、發布跑通（**測試 repo 或 dry-run**）。
- workflow 測試（ADR 0022 §如何確認）：release-please 輸出為否時不建置；verify 的檔名集合、checksums、別名一致、APK 版本、PE 標頭、舊版更新器相容；pubspec 版本等於 manifest。
- 依賴方向（`fmp_layer_imports`，ADR 0015）：安裝相關的平台呼叫只在平台層。
- 延後實測（ADR 0022 §如何確認、§8）：以舊版 v1.11.0 實際更新（M9）；Windows 安裝檔不帶 Mark of the Web（M9）；macOS quarantine、Linux AppImage 改名替換（平台任務）。

**(c) 不在 M1**
- 應用內更新的實作（檢查、下載、驗證、安裝、清理、`appUpdate` 能力、`fmp_updater.exe`）——M9（`milestones.md` §M9、ADR 0022 §決定 5–10）。
- `docs/user-guide.md` 與關於頁——M9（`milestones.md` §M9）。
- 舊 `pubspec_version_test` 改成「pubspec 版本等於 release-please manifest」——隨 `app/` 版本機制落地（ADR 0022 §決定 1）。
- 舊專案的 `release.yml` 不動（見 §4）。

**(d) ADR 已固定的名稱**
- 版本策略：release-please manifest 模式、`dart` strategy；`Release-As: 2.0.0`（第一版）；tag `v{版本}`；`versionCode` 公式。
- 檔名：`app/CHANGELOG.md`；發佈物 `fmp-v{版本}-android-{arm64-v8a,armeabi-v7a,x86_64,universal}.apk`、`fmp-v{版本}-windows-installer.exe`、`fmp-v{版本}-windows.zip`、`fmp-v{版本}-linux-x86_64.AppImage`、`fmp-v{版本}-macos.zip`、`fmp-v{版本}-checksums.sha256`、`fmp-latest-*`。
- 能力：`appUpdate`（`androidApk`／`windowsInstaller`／`windowsPortable`／`linuxAppImage`／`macosApp`／`none`）。
- 判斷方式：Windows 有 `unins000.exe` 為安裝版；Linux 有 `APPIMAGE` 環境變數。
- 入口：「設定 → 關於 → 檢查更新」。
- 套件：`pub_semver`。

---

### ADR 0023 — 統一 Toast

**(a) M1 要做的**（`milestones.md` §M1：「`ToastHost` 與 `Toaster`」）
- **單一入口 `Toaster`**（provider 注入，不需 `BuildContext`）：`success`、`info`、`warning` 收 i18n 字串；`error(AppError, {operation})` 只收 `AppError`；各自最多一個動作；背景工作不呼叫它；錯誤不論是否顯示提示都經 log 門面寫入錯誤歷史（ADR 0023 §決定 1）。
- **外觀**：Material `SnackBar`、`floating`、四種語意色加圖示；位置（手機在迷你播放列與底部導覽列之上、桌面在播放列之上置中**最寬 560px**、全螢幕頁貼底部安全區）；外殼版面發佈「底部被佔用的高度」；**一次一則、新的立刻取代**；時長（成功與資訊 **4 秒**、錯誤與警告 **6 秒**）；**去重：同類別＋同音源（非錯誤為同一訊息）5 秒內只顯示一次**（ADR 0023 §決定 2、ADR 0013 §後果）。
- **層級**：`ToastHost` 放在 `MaterialApp.builder`，以**一個 `ScaffoldMessenger` 與透明 `Scaffold` 包住 Navigator**，所以全螢幕頁、對話框、底部面板之上都看得到；子視窗與懸浮窗不顯示提示、錯誤以型別化訊息轉給主視窗；App 在背景不顯示、不發系統通知（ADR 0023 §決定 3）。
- **無障礙**：用 `SnackBar` 內建 live region；單獨朗讀用 `SemanticsService.sendAnnouncement(View.of(context), …)`，**不用已棄用的 `announce`**（ADR 0023 §決定 5）。

**(b) M1 的驗證**
- lint `fmp_toast_entry`：`SnackBar(`、`ScaffoldMessenger.of`、`showSnackBar`、`clearSnackBars` 只准在 toast 模組，依 ADR 0015 寫雙向變異測試；它取代舊 `error_presentation_static_rule_test.dart` 中「UI 不得自組錯誤文字」的部分（ADR 0023 §如何確認）。
- 單元測試：去重視窗、取代、時長（ADR 0023 §如何確認）。
- widget 測試：全螢幕路由與對話框開啟時送出提示、提示可見；底部位移依外殼發佈的高度（ADR 0023 §如何確認）。
- §7：提示在全螢幕頁與對話框之上可見；**Windows Narrator 下提示不凍結無障礙樹**（上游 #190357 類問題）。

**(c) 不在 M1**
- 詳細頁與 GitHub 回報（`ErrorReport` 內容、複製 Markdown、開 issue 頁、`.github/ISSUE_TEMPLATE/bug_report.yml`）——M3（`milestones.md` §M3、ADR 0023 §決定 4）。repo 目前沒有 issue 範本（`.github/` 只有 `dependabot.yml` 與 `workflows/`）。
- Debug 頁的錯誤歷史（ADR 0025）——M3。
- 系統層通知——不在 ADR 0023 範圍。

**(d) ADR 已固定的名稱**
- 型別：`Toaster`、`ToastHost`、`ErrorReport`（M3）。
- lint：`fmp_toast_entry`。
- 常數：4 秒／6 秒、5 秒去重、560px。
- 參照：Material 3 Snackbar 規範；Finamp／Immich／LocalSend 的 service 包 SnackBar；NewPipe `ErrorActivity`。

---

### ADR 0024 — UI／UX（M1 取 token、斷點、字型、slang 骨架、快捷鍵）

**(a) M1 要做的**（`milestones.md` §M1）
- **`AppTokens`（`ThemeExtension`）**：間距 **4、8、12、16、20、24、32、40、48**；圓角 **4、8、12、16、28**（M3 shape scale）；語意色成功、警告；焦點框 **2dp `primary`、外擴 2dp**（ADR 0024 §決定 1）。
- 字級只用 M3 `textTheme` 角色；元件固定尺寸（封面上限、面板寬度）放 theme 目錄的 **`AppLayout`**（ADR 0024 §決定 1）。
- 播放頁的毛玻璃（半透明表面色約 60–72%＋一般模糊、系統「減少透明度」或高對比時改不透明）——播放頁屬 M2，但 token 要先留（ADR 0024 §決定 1）。
- `material_ui` 的 import 路徑**在建立 `app/` 時依當時 stable 的官方建議決定**（ADR 0024 §決定 1）。
- **字型**：`fontFamilyFallback` 依目前語言排序、由平台層提供；繁中 Windows `Microsoft JhengHei UI`、`Microsoft JhengHei`，其他平台 `Noto Sans TC`；簡中 Windows `Microsoft YaHei UI`、`Microsoft YaHei`，其他平台 `Noto Sans SC`；英文清單把繁中放前（ADR 0024 §決定 2）。
- **斷點**：自有 `WindowClass`，與 M3 同值：**compact（< 600）、medium（600–839）、expanded（840–1199）、large（1200–1599）、extraLarge（≥ 1600）**（ADR 0024 §決定 3）。
- **i18n**：slang，**`base_locale: zh-TW`**，三語言（zh-TW、zh-CN、en）；新字串先寫繁中，缺字退回繁中；子視窗與懸浮窗字串經型別化訊息傳入（後者是 M7）（ADR 0024 §決定 7）。
- **無障礙與鍵盤**：只有圖示的按鈕都有 tooltip 與語意標籤；App 內快捷鍵固定、不可自訂、只在 FMP 為前景且焦點不在輸入框時有效——表列空白鍵、Ctrl+←／→、Shift+←／→、Ctrl+↑／↓、Ctrl+S、Ctrl+R、Ctrl+F、Ctrl+L／Ctrl+Q、Esc、F6、Ctrl+,（ADR 0024 §決定 8）。
- `FocusTraversalGroup` 分三區（導覽／內容／播放列），Tab 只在區內移動（ADR 0024 §決定 8）。
- 全域快捷鍵照舊：可自訂、預設關、預設 Ctrl+Alt+…；同一組按鍵時全域優先；錄製時與 App 內相同就提示（ADR 0024 §決定 8）——全域快捷鍵的實作屬 M8，M1 只需無衝突。

**(b) M1 的驗證**
- lint `fmp_design_tokens`：`lib/ui/`（theme 目錄除外）不得在 `EdgeInsets.*`、`SizedBox` 寬高、`BorderRadius.circular`、`fontSize:` 使用數字字面值（`0` 除外），也不得寫 `Color(0x…)`、`Colors.*`；依 ADR 0015 寫雙向變異測試（ADR 0024 §如何確認）。
- widget 測試：首頁、搜尋、歌單、播放頁、設定在淺色與深色主題下通過 `meetsGuideline(labeledTapTargetGuideline)` 與 `textContrastGuideline`；播放頁以最淺與最深的測試封面各測一次（ADR 0024 §如何確認）——播放頁屬 M2。
- 快捷鍵與焦點 widget 測試：空白鍵、Esc、F6，以及**輸入框內空白鍵只輸入空格**；播放列三段寬度的控制項集合、曲名不小於 160dp（ADR 0024 §如何確認）——播放列屬 M2。
- golden（`alchemist`，色塊字型）：播放頁 B 在 1000、1400、1800 寬、播放列三段寬度；只守版面結構、數量保持少（ADR 0024 §如何確認）——M2。
- i18n：三語言 key 集合相同（缺一條即紅）（ADR 0024 §如何確認）。
- §7：**輸入框內空白鍵只輸入空格；F6 焦點切換；Windows 繁中字形由正黑體顯示**。

**(c) 不在 M1**
- 播放頁方案 B、播放列三段、App 內快捷鍵**全表**、焦點三區——M2（`milestones.md` §M2）。**注意**：§7 又把「F6 焦點切換」放進 M1，見 §3。
- 右上「正在播放」面板、搜尋頁 chip 列、設定頁 list-detail、`intl` 的 `NumberFormat.compact`（ADR 0024 §決定 3、6）——隨各頁所屬里程碑。
- snake 導覽殼（bottom nav／NavigationRail／drawer）——ADR 0024 §決定 3 只給表；M1 是否建殼未寫死，見 §3。
- 使用者指南刪除與 `docs/user-guide.md`——M9（ADR 0024 §決定 9、`milestones.md` §M9）。
- dynamic color、液態玻璃、全 App 毛玻璃、各平台原生風格——皆否決（ADR 0024 §考慮過的選項）。
- Linux 是否內建 Noto CJK——Linux 平台任務（ADR 0024 §決定 2）。

**(d) ADR 已固定的名稱**
- 型別：`AppTokens`、`AppLayout`、`WindowClass`。
- 值：上列間距、圓角、斷點、字型名。
- 設定：`base_locale: zh-TW`；三語系 zh-TW／zh-CN／en。
- lint：`fmp_design_tokens`。
- 套件：`intl`、`slang`、`alchemist`。
- 檔案：`docs/user-guide.md`（M9）。

---

### ADR 0025 — Debug 頁與開發者模式

**主體屬 M3**（`milestones.md` §M3：「Debug 頁與插件開發工具（ADR 0025、0015 §7）」）。

- (a) M1 唯一相關：ADR 0011 §決定 7 的「開發者」設定組要被建出來（分組表在 M1 的 drift schema 裡），因為 ADR 0025 §決定 1 的 `developerMode`、`logLevel` 兩欄位住在那裡；但欄位清單按 ADR 0026 §決定 2「在引入該組設定的里程碑定案」——也就是 M3。
- (c) 八區塊 list-detail、log JSON Lines／保留 7 天、網路摘要檢視、播放狀態、音源健康檢查、插件開發工具、資料庫唯讀瀏覽與「檢查」、重設資料、診斷包——全部 M3（ADR 0025 §決定 2–10）。
- (b) §8（M3）：Windows release 版開啟開發者模式、重啟後仍開啟、再從總開關關掉；Debug 頁看得到一次搜尋的網路摘要；匯出的診斷包能以解壓工具打開。

---

### ADR 0026 — 里程碑與切換（定義 M1 的任務結構）

**(a) M1 要做的**
- **里程碑任務**：`fmp-rewrite` 的 child；開工時走 brainstorm，擁有者核准一次 prd／design／implement；implement 列出 PR 子任務與先後順序（Trellis 的 parent／child 不表達依賴）（ADR 0026 §決定 1）。
- **PR 子任務**：里程碑任務的 child；一個分支、一個 PR，合進 `main`；prd 只寫做什麼與驗收，PR 描述附 review 指南；合併後 `app/` 可編譯、測試全綠；在已核准範圍內直接做，遇到未定的事才問（ADR 0026 §決定 1）。
- **里程碑驗收**：Android 與 Windows 各做一次端到端實際操作，加上併入的實測項目（ADR 0026 §決定 1）。
- 排序原則：縱向切片，每個里程碑結束時多一件可以實際操作的事（ADR 0026 §決定 2）。
- 追蹤只用 Trellis 任務樹；清單與狀態在 `milestones.md`（ADR 0026 §決定 1）。

**(b) M1 的驗證**
- 每個里程碑任務 archive 前，`milestones.md` 的狀態欄與驗收項目逐項打勾；未打勾的不能 archive；**這是 review 點，不是自動閘門**（ADR 0026 §如何確認）。
- 里程碑的範圍若在開工時要大改，要回來修 `milestones.md` 並說明原因（ADR 0026 §後果）。

**(c) 不在 M1**
- M2–M9 的里程碑與平台任務（ADR 0026 §決定 3、4）。
- 切換放行條件（功能 E1–E17、效能 5%、資料比對、2 週試用）——M9（ADR 0026 §決定 5）。
- 加開 GitHub Milestones 或 Projects——否決（ADR 0026 §考慮過的選項）。

**(d) ADR 已固定的名稱**
- 任務結構：`fmp-rewrite` 的 child = 里程碑任務；里程碑任務的 child = PR 子任務。
- 清單檔：`.trellis/tasks/09-26-fmp-rewrite/milestones.md`。

---

### ADR 0027 — 實機驗證（M1 改寫 skill）

**(a) M1 要做的**
- **M1 時為 `app/` 改寫 verify-on-device skill**；**根目錄舊專案的 skill 維持原樣**，給緊急修正用，切換 PR 時移除（ADR 0027 §決定 4）。
- 預設模式是**重播**：實機驗證一律跑 **dev flavor**，每個插件切成「重播」，或使用 `app/` 的測試插件（ADR 0027 §決定 1）。
- 改用真實連線的條件：只在改動本身是插件、網路層、登入，或正在錄製 fixture 時；只做最少操作；回報寫明「模式：真實」與做了哪些請求（ADR 0027 §決定 2）。
- 平台分工：Android 模擬器與 Windows 都在**每個改到使用者看得到的 PR** 驗，**M1 加入 skill**（ADR 0027 §決定 3 的表）。
- 每個平台的操作說明沿用現在 skill 的閉環（啟動 → 執行 → 觀察 → 操作 → 收尾），放在 `references/<平台>.md`（ADR 0027 §決定 3）。

**(b) M1 的驗證**
- `app/AGENTS.md` 的驗證段寫明「預設重播、真實連線的條件、Android 與 Windows 每個 PR」；**這是 review 點，實機驗證無法寫成測試**（ADR 0027 §如何確認）。
- 實機驗證的回報格式包含「平台」與「模式：重播／真實」；PR review 指南缺這兩項就退回（ADR 0027 §如何確認）。
- 里程碑驗收表在 Linux 平台任務完成後才含「Linux 冒煙測試」一格（ADR 0027 §如何確認）。

**(c) 不在 M1**
- 現在就改寫根目錄舊專案的 skill（ADR 0027 §決定 4）。
- Linux（VMware Ubuntu 桌面，X11 與 Wayland）、macOS、iOS 模擬器的冒煙測試——各自平台任務（ADR 0027 §決定 3、ADR 0026 §決定 4）。

**(d) ADR 已固定的名稱**
- 檔名：`app/AGENTS.md`；skill 的 `references/<平台>.md`；`app/test/fixtures/plugins/` 的測試插件。
- 現有 skill 的字串：`references/android.md`、`references/windows.md`、`references/runtime-state.md`；`scripts/ax_flatten.py`、`scripts/msaa_tree.ps1`、`scripts/smtc_probe.ps1`。

---

## 2. 跨 ADR 的相依圖

以下為 M1 各項的建議建置順序（箭頭 = 「左邊要先有／先定，右邊才能做」）。順序依 ADR 0009–0014 與 phase2-plan §2、§3 的依賴，加上 M1 的實際需要；不是 ADR 明定的強制序。

1. `app/` Flutter 專案骨架 ＋ flavor `dev`／`prod` ＋ App 身分 ＋ `app/AGENTS.md`（ADR 0008 §決定 1–3、ADR 0015 §決定 8）
2. `fmp_lints` 套件骨架 ＋ `analysis_options.yaml` ＋ 接線哨兵 ＋ 首批規則（ADR 0015 §決定 2）→ 需 1
3. 平台層骨架 ＋ `PlatformCapabilities` ＋ 目錄規則 ＋ 單一實例鎖 ＋ dev／prod 身分與資料目錄隔離（ADR 0009 §決定 1、2、7；ADR 0015 §決定 8）→ 需 1
4. drift ＋ `sqlite3` ＋ 最小 schema ＋ schema 快照 ＋ 資料層邊界（repository）（ADR 0010 §決定 1–3）→ 需 3（資料庫檔在平台層定義的資料目錄）
5. `TrackKey` 格式（含 cid）＋ 測試（ADR 0008 檔頭補充、ADR 0005、ADR 0010 §決定 2）→ 需 4（`tracks` 的唯一鍵）
6. 設定分組表骨架（八組單列表）＋ Riverpod Notifier 模式（ADR 0011 §決定 7）→ 需 4
7. log 門面 ＋ 遮蔽函式 ＋ log 檔（`logs/`、2MB×3）＋ 網路紀錄攔截器（ADR 0011 §決定 1–4）→ 需 3（log 目錄）、6（log 層級設定）
8. `AppError` sealed 分類 ＋ 網路層重試策略（Riverpod retry 關閉、退避、`Retry-After`）（ADR 0013 §決定 1–4）→ 需 7（錯誤經門面寫入、遮蔽）
9. 網路層：API client ＋ 媒體 client ＋ 攔截器順序 ＋ 轉址規則 ＋ `AuthRequirement` 宣告點（ADR 0012 §決定 1、2）→ 需 7（網路紀錄）、8（錯誤對應）
10. JS 執行環境（`flutter_js`／QuickJS）＋ 宿主 API v1 最小集 ＋ manifest ＋ 從檔案載入 B 站插件（ADR 0014 §決定 1–5）→ 需 9（`http.request`）、8（結構化錯誤）、7（`log`）
11. 播放核心最小集：`PlaybackController` ＋ `AudioBackend` 兩實作 ＋ 兩首的佇列 ＋ 前瞻交接（ADR 0018 §決定 1–3、6）→ 需 10（`resolveStream`）、8（`RecoveryPolicy`）、3（後端與可播格式）
12. `Toaster` ＋ `ToastHost`（`MaterialApp.builder`、`ScaffoldMessenger`＋透明 `Scaffold`）（ADR 0023 §決定 1–3）→ 需 8（`error(AppError)`）、7（錯誤歷史）
13. UI token（`AppTokens`／`AppLayout`）＋ `WindowClass` 斷點 ＋ 字型 fallback ＋ slang 三語言骨架 ＋ 播放快捷鍵（ADR 0024 §決定 1、2、3、7、8）→ 需 3（字型 fallback）、12（phase2-plan §2：D3 → D5）
14. 零聯網兩道防線（`dart_test.yaml`、`flutter_test_config.dart` 的 `HttpOverrides`）＋ fixture 格式 ＋ 契約執行器 ＋ `checks.json` ＋ 測試插件（ADR 0015 §決定 3–6）→ 需 1、2、10（執行器要載入 QuickJS）
15. CI 切分（`dorny/paths-filter`）＋ `app` job（format／analyze／哨兵／lint 測試／`flutter test`／契約執行器／五平台建置）＋ `always()` 彙總（ADR 0015 §決定 9）→ 需 2、14
16. release-please 發版 workflow dry-run（`app/CHANGELOG.md`、manifest、`dart` strategy）（ADR 0022 §決定 1）→ 需 1、15
17. 為 `app/` 改寫 verify-on-device ＋ `app/AGENTS.md` 驗證段（ADR 0027 §決定 1–4）→ 需 11（可播的曳光彈）、12（可驗的 UI）
18. YouTube.js 限時探針（`flutter_js` 能否搜尋並解出串流）（ADR 0014 §決定 10）→ 需 10；可與 11–17 並行，失敗時把結論帶回 M3

張成單線（供 PR 排序參考）：

`1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11 → 12 → 13 → 14 → 15 → 16 → 17`，18 與 11–17 並行。

其他單向約束（不是上面的主線，但成立）：

- 7（log 門面）→ 9（網路層）：ADR 0011 §決定 4 的網路紀錄要經門面。
- 8（`AppError`）→ 10（宿主結構化錯誤）：ADR 0014 §決定 5。
- 3（平台層）→ 11（後端與可播格式）：ADR 0018 §決定 3、ADR 0009 §決定 2。
- 4（drift schema）→ 6（設定表）→ 7（log 層級設定）：ADR 0011 §決定 7、ADR 0025 §決定 1。
- 12（Toast）→ 13（UI）：phase2-plan §2 的 `D3 → D5`。
- 14（執行器）→ 15（CI 的契約執行器 job）：ADR 0015 §決定 6、9。

---

## 3. 未定或 ADR 之間矛盾之處

以下每一條都是 planner／brainstorm 要解掉的；沒有解掉就會在 implement 時卡住。

### 3.1 `app/` 的 spec 放哪
`phase2-plan` §10：「**M1 開工時要決定：`app/` 的 spec 放哪（Trellis `packages:` 或其他）。**」
現況：`.trellis/config.yaml:58-78` 的 `packages:` 整段是**註解掉的範例**，未啟用；`.trellis/spec/` 目前只有舊專案的六大目錄（`data`、`guides`、`services`、`shared`、`testing`、`ui`）。這同時影響 `trellis-implement`／`trellis-check` 子代理載入 spec 的路徑（`phase2-plan` §10）。

### 3.2 Flutter 版本：ADR 說「當時的 stable」，CI 卻必須釘一個版本
`milestones.md` §M1：「`app/` 新專案，Flutter 用當時的 stable」。
但 `.github/workflows/ci.yml:28` 現在釘的是 `FLUTTER_VERSION: '3.47.1'`（舊專案的 job），`.claude/skills/verify-on-device/SKILL.md:20-21` 也寫「Flutter 3.47.x」。既有的 `.github/workflows/release.yml:22` 同樣釘 `3.47.1`。**ADR 沒有指定 `app/` job 的 Flutter 版本**，也沒有說要不要跟舊專案同版。

### 3.3 指令檔分家尚未經擁有者核准
`phase2-plan` §10：「**M1 的第一個 PR：指令檔分家**（2026-09-28 盤點，**尚未問擁有者**，M1 brainstorm 時提出）。」
建議做法（同段）：根目錄 `AGENTS.md` 縮成共用部分；舊專案規則搬到 `lib/AGENTS.md`；`app/AGENTS.md` 用繁中；spec 以 Trellis `packages:` 分成舊專案與 `app`。**這是提案，不是已定決定。**

### 3.4 `AuthRequirement` 屬 M1 還是 M3
`milestones.md` §M1：「網路層（不含登入，ADR 0012）」；§M3：「帳號與 `CredentialStore`、`AuthRequirement`（ADR 0012，E6）」。
但 ADR 0012 §決定 2：「**帶憑證的單一宣告點**：每個請求在音源插件的定義處宣告 `AuthRequirement`」，且 ADR 0014 §如何確認要求契約測試涵蓋「`AuthRequirement`」。M1 的 B 站插件（從檔案載入）就會宣告它。→ M1 至少要落 `AuthRequirement` 的 enum 與攔截器掛鉤，登入流程仍屬 M3。

### 3.5 `PermissionGateway` 跨 0009（M1 能力）與 0020（M6 定義）
ADR 0009 §決定 1 把「執行期權限」列為平台層能力之一；ADR 0009 §決定 4：「**不寫空實作**：未驗證的平台宣告全部能力為『沒有』、沒有實作檔」。
ADR 0020 §決定 9 才定義 `PermissionGateway` 的四種權限與流程（M6）。
→ M1 的平台層是否要有 `PermissionGateway` 介面（空宣告）未寫死；M1 沒有任何需要權限的功能。

### 3.6 記憶體網址快取／離線狀態（ADR 0016）在 M1 還是 M2
ADR 0018 §決定 6：「本機下載檔 → **記憶體網址快取（ADR 0016）** → 插件 `resolveStream`」；§決定 7：「**不在 `Online` 時暫停計數（ADR 0016）**」。
但 `milestones.md` §M2 把「統一快取庫與離線狀態（ADR 0016）」整包列在 M2。
→ M1 的曳光彈（連播兩首）需不需要 64 筆的網址快取與網路狀態判定，ADR 沒說。

### 3.7 F6 焦點三區同時被列在 M1 與 M2
`phase2-plan` §7：「ADR 0024：輸入框內空白鍵只輸入空格；**F6 焦點切換**；Windows 繁中字形由正黑體顯示。」
`milestones.md` §M2：「播放頁方案 B、播放列三段、App 內快捷鍵全表、**焦點三區**（ADR 0024）」。
→ 「F6 焦點切換」在 §7（併入 M1）與 §M2（焦點三區）各出現一次，範圍重疊。

### 3.8 M1 的 log 檔格式：純文字行還是 JSON Lines
ADR 0011 §決定 2 只定「單檔 2MB、保留 3 個、寫入失敗不影響 App」，**沒定格式**。
ADR 0011 §後果：「**log 保留 7 天與 JSON Lines 格式**、Debug 頁見 ADR 0025」。
ADR 0025 §決定 3（M3）：「**檔案格式**：JSON Lines，一筆一行」；§後果壞的也寫「log 檔**改成** JSON Lines」。
→ M1 落地時要選：先用純文字行（M3 再改 JSON Lines），或一次到位。ADR 0011 §決定 3 的遮蔽要求兩者都成立。

### 3.9 `fmp_lints` 哪幾條規則進 M1
ADR 0015 §決定 2 的表列 10 條，末段又列 3 條後續 ADR 新增（`fmp_periodic_timer_owner`（0017，M2）、`fmp_toast_entry`（0023，M1）、`fmp_design_tokens`（0024，M1））。**ADR 沒說哪些在 M1 落地**。
依「閘門要對著現在還有人呼叫的東西」與 ADR 0015 §如何確認的「第一里程碑實測：`dart analyze` 看得到插件診斷」，`fmp_lints` 套件與至少部分規則在 M1；`fmp_periodic_timer_owner` 的消費點（排程器）在 M2。

### 3.10 drift「最小 schema」是哪幾張表
`milestones.md` §M1 只說「drift 最小 schema 與快照（ADR 0010）」。ADR 0010 §決定 2 給的是原則（關係、`TrackKey` 唯一鍵、只存事實、下載紀錄獨立表、設定表、UTC epoch 毫秒），**沒有列舉 M1 的表**。
ADR 0026 §決定 2 提供線索：「**各組設定的欄位清單**（ADR 0011），在引入該組設定的里程碑定案」。
→ M1 要自己定：設定表（八組）、`tracks`（`TrackKey`）、佇列持久化表（ADR 0018 §決定 10）等的最小集。

### 3.11 isar_community 與 sqlite3 共存怎麼在 M1 驗證
ADR 0010 §決定 4：「舊資料匯入（legacy import）… 位於 `app/lib/legacy_import/`，是**唯一**依賴 `isar_community` 與 `flutter_secure_storage` 10.x 的地方」。
`milestones.md` §M5 才做 `legacy_import`。
但 ADR 0010 §後果與 `phase2-plan` §7 都要求 **M1 在 Android、Windows 實測兩套原生庫共存**，以及 sqlite3 的 Android 16KB page size 對齊。
→ M1 要如何在 `legacy_import` 還不存在時證明共存（暫時的 spike／測試依賴，或提前建一個最小 `legacy_import`）未定。

### 3.12 release-please dry-run 怎麼做
ADR 0022 §決定 1：「**重寫期間不發版**」；§如何確認與 §7：「release-please 的發版 PR 與同一 workflow 的建置、驗證、發布跑通（**測試 repo 或 dry-run**）」。
→ 「測試 repo 或 dry-run」兩種都沒被選；且 ADR 0022 §後果：「release-please **草稿與建 tag 的確切選項在落地時以官方文件確認**」。
另外，舊專案的 `.github/workflows/release.yml` 必須留著（ADR 0008 §決定 4 的緊急修正），所以 M1 新增的 workflow **檔名未定**（`release.yml` 這個名字已被舊專案佔用）。

### 3.13 `material_ui` 的 import 路徑
ADR 0024 §決定 1：「**`material_ui` 的 import 路徑在建立 `app/` 時依當時 stable 的官方建議決定。**」
ADR 0024 §後果也把它列為「之後要注意：Material 拆成 `material_ui` 的遷移時程」。

### 3.14 `window_manager` 的版本（0.5.x 已停止維護）
ADR 0021 §後果：「**`window_manager` 0.5.x 已停止維護（0.6.0 改建在 `nativeapi`），換套件的成本落在平台層**。」
ADR 0009 §決定 6：「托盤、視窗、快捷鍵、多視窗**沿用現有套件**並擴到其他桌面平台」、「桌面套件需要修補時用 **git 依賴鎖 commit**，並註明上游 issue」。
→ M1 就要用 `window_manager` 做 Windows／Linux 自訂標題列（ADR 0009 §決定 8），選 0.5.x（停維護）或 0.6.0（換底層）未定。

### 3.15 契約執行器能否在 `flutter test` 內載入 QuickJS
ADR 0015 §如何確認：「第一個里程碑實測：… **契約執行器能否在 `flutter test` 內載入 QuickJS（不行改用桌面 `integration_test`）**」。
ADR 0015 §決定 9 的 `app` job 同時列了「契約執行器」與「Linux 與 Windows 的整合測試」。
→ 這是 M1 要**做出來的答案**，不是先驗條件；結果直接決定 CI 有哪些 job 與它們跑在什麼 runner 上。

### 3.16 M1 的「兩首的佇列」邊界
`milestones.md` §M1：「播放核心最小集：兩個後端、**兩首的佇列**、前瞻交接（ADR 0018）」；§M2 才是「完整 `QueueModel` 與 `RecoveryPolicy`」。
ADR 0018 §決定 4 的模式（`queue`／`temporary`／`mix`／`live`／`detached`）、§決定 5 的隨機、§決定 10 的持久化**哪些屬 M1 的「兩首」未寫死**。
→ 需要 planner 明定 M1 的佇列：是否持久化、是否只有 `queue` 模式、位置存檔要不要做。

### 3.17 M1 是否建導覽殼
`milestones.md` §M1：「token、斷點、字型、slang 三語言骨架、播放快捷鍵（ADR 0024）」——只提 token／斷點／字型／i18n／快捷鍵。
ADR 0024 §決定 3 的 `WindowClass` 表把導覽（底部導覽列／NavigationRail／常駐導覽抽屜）綁在斷點上。
→ M1 是只出 `WindowClass` enum，還是連導覽殼一起（曳光彈要有搜尋頁與播放入口）未寫死。

### 3.18 ADR 0026 的「一個 PR」與 M1 的大小
ADR 0026 §背景已記：parent prd 同時要求「每個里程碑是一個 child task」與「每個 child task 一個可 review 的 PR」，**第一個里程碑一個 PR 裝不下**；§決定 1 的解方是「里程碑任務底下開 PR 子任務」，§後果也寫「M1 很重」。這是給 planner 的前提：M1 必然是多個 PR。

### 3.19 舊 ADR 0001–0007 的適用範圍
`phase2-plan` §10：「所有設計決定以 ADR 為準：`docs/adr/0008`–`0027`；**舊 ADR 0001–0007 仍描述根目錄舊專案，於切換 PR 刪除**。」
M1 會用到的舊 ADR：0005（`TrackKey` 含 cid，確認沿用；`phase2-plan` §5「§14 ADR」列「0005 分 P 以 cid 區分：確認（也是舊資料遷移要用的格式）」）。0002、0007 由 0010／0009 取代；0003、0004 在 0018／0020 重新決定；0001、0006 已確認。→ 讀 M1 相關 ADR 時不要把 0001–0007 當現行規範。

---

## 4. 現況 repo 檔案：M1 要改或不要動

### `.github/workflows/ci.yml`
- **現況**：單一 workflow、**沒有路徑過濾**（`:3-7` 的註解刻意說明：純文件改動不能跳過 `validate`，因為文件承載規則）；三個 job——`validate`（`:33`）、`build-android`（`:87`）、`build-windows`（`:124`），全部是舊專案；`:28` 釘 `FLUTTER_VERSION: '3.47.1'`；`:64-68` 跑 `dart run build_runner build`＋`dart run slang`（Isar 與 slang）；`:71` `flutter analyze`；`:77` `flutter test --coverage --exclude-tags live`。
- **M1 要改**：ADR 0015 §決定 9 要求 `dorny/paths-filter` 依專案切分——`app/**` 與 `.github/**` 觸發 `app` 的 job，`app/` 以外的任何變動觸發舊專案的 job；**一個 `always()` 彙總 job 當唯一必要檢查**。`app` 的 job 另含 `dart analyze --fatal-infos`、接線哨兵、lint 規則測試、不加參數的 `flutter test`、契約執行器、五平台建置、Linux 與 Windows 整合測試。
- **M1 不要動**：舊專案的三個 job 維持現狀，只在根目錄變動時跑（ADR 0015 §決定 9：「舊專案的 job 維持現狀…`app/` 的 PR 不被舊專案的不穩測試擋住」）。`:3-7` 那段「不用 `paths-ignore`」的理由仍適用於舊專案那一半。
- 注意：`app/` 的零聯網用 `dart_test.yaml` 的 `skip`（ADR 0015 §決定 3），跟舊專案 `--exclude-tags live`（`:77`）是兩套。

### `.github/workflows/release.yml`
- **現況**：tag 驅動（`v*`）＋ `workflow_dispatch`；`prepare`（`:27`）解析 tag 與 `versionCode`；`build-android`（`:74`）、`validate`（`:180`）、`build-windows`（`:216`）、`verify`（`:361`）、`release`（`:419`）；以 `sed`／`pwsh` 手改 `pubspec.yaml` 版本（`:113-115`、`:239-244`）；checksums 產生（`:390-399`）；`draft: false` 直接發布（`:508-518`）；`:309-310` 把 AppUserModelID 寫進 Inno ISS。
- **M1 不要動**：ADR 0008 §決定 4 的舊版緊急修正要靠它；ADR 0026 §決定 5 的切換才把 `release.yml` 改指向 `app/`。ADR 0022 的 release-please 對 `app/` 是新的 workflow（檔名未定，見 §3.12）。
- 相關：`tool/release/verify_release_assets.dart`（`:406`）與 `inno_bundle` 設定（`pubspec.yaml:121-122` 的 AppId）都屬舊專案，切換 PR 才動（ADR 0008 §決定 5、ADR 0022 §決定 4 要沿用檔名與 Inno AppId）。

### `orca.yaml`
- **現況**：`worktree.sharedDirectories` 共用 `.trellis/workspace`（`:3-8`）；`setupAgentStartupPolicy: wait-for-setup`（`:11`）；`scripts.setup` 在 repo 根跑 `flutter pub get`、`dart run build_runner build`、`dart run slang`（`:18-21`）——全部針對舊專案。
- **M1 的關係**：`phase2-plan` §10 把它列在「舊內容會誤導在 `app/` 工作的 AI」的清單（「`orca.yaml` 的 setup…都只對舊專案」）。但 ADR 0008 §決定 5 把 `orca.yaml` 改指向 `app/` 排在切換 PR。
- → M1 至少要處理：在 `app/` 開 Orca worktree 時，setup 要在 `app/` 內跑（且 `app/` 的 codegen 只有 slang，沒有 Isar build_runner）；`orca.yaml` 目前沒有第二個專案的概念。這是未定項。

### 根目錄 `AGENTS.md`
- **現況**：全為舊專案——Verification 表（`:15-22` 的舊測試路徑）、`:24-32` 的 codegen 與 `flutter test --exclude-tags live`、`:34-39` 的 on-device 規則（指向舊 `verify-on-device`）、`:43-51` Conventions（Isar／`docs/development.md`）、`:53-97` Boundaries（`lib/` 路徑、`AudioController`、`Isar`、`test/*/static_rules/*`）、`:99-116` Trellis 段。
- **M1 要改**：`phase2-plan` §10 指出「Claude Code 以 repo 根目錄為工作目錄時，**每個 session 開頭都會載入它**；`app/AGENTS.md` 只在讀到 `app/` 裡的檔案時才載入」，建議把根目錄縮成共用部分、舊規則搬到 `lib/AGENTS.md`、`app/AGENTS.md` 用繁中。**尚未問擁有者**（§3.3）。
- **M1 不要動**：`lib/` 的規則本身（搬到 `lib/AGENTS.md` 是移動不是修改）；`:118-138` 的 Trellis managed block 由 `trellis update` 管。
- ADR 0015 §如何確認 要求 `app/AGENTS.md` 列出的每條靜態規則都寫出對應規則名；ADR 0027 §如何確認 要求 `app/AGENTS.md` 的驗證段寫「預設重播、真實連線的條件、Android 與 Windows 每個 PR」。→ `app/AGENTS.md` 的內容有兩則 ADR 的硬要求。

### `.claude/skills/verify-on-device/`
- **現況**：`SKILL.md` 是舊專案的閉環——Android 模擬器必要、Windows 只在 Windows 專屬改動（`:17-18`）；`:20-21` 記「Flutter 3.47.x」；`:23-27` 三個 `references/`；`:90` 的觀測表把「Live object fields, HTTP traffic, **Isar**」指向 `references/runtime-state.md`；`:117` 用 `com.personal.fmp` 當 launch 目標；`:79-81` 提到 Windows AXTree 凍結（`docs/troubleshooting.md`）。
- `references/`：`android.md`、`windows.md`、`runtime-state.md`；`scripts/`：`ax_flatten.py`、`msaa_tree.ps1`、`smtc_probe.ps1`。
- **M1 要改**：ADR 0027 §決定 4「**M1 時為 `app/` 改寫 skill**」；§決定 1–3：預設重播、跑 dev flavor、Android 與 Windows 每個使用者可見的 PR 都驗、`references/<平台>.md`。`runtime-state.md` 的 **Isar 檢查要改成 drift**（ADR 0009／0010）；`:117` 的 launch 目標要含 dev 身分（`com.personal.fmp.dev`，ADR 0015 §決定 8）。
- **M1 不要動**：**根目錄舊專案的 skill 維持原樣**，給緊急修正用，切換 PR 時才移除（ADR 0027 §決定 4）。→ 若改寫方式是就地改同一份 skill，會違反這條；較可能是新增一份 app 範圍的 skill 或在 skill 內分兩套指令，這未定。
- `scripts/` 三支工具與平台無關（AX／MSAA／SMTC），可沿用。

### 其他（`phase2-plan` §10 點名，風險較低）
- `.trellis/spec/` 20 檔描述舊專案；`session-start.py` 會列出 spec 索引，`trellis-implement`／`trellis-check` 依 `.trellis/spec/<package>/<layer>/` 載入。→ 與 §3.1 同一個未定項。
- `docs/building.md`、`development.md`、`build-and-release.md`、`troubleshooting.md`：只對舊專案，是按需讀的人類文件，風險較低（`phase2-plan` §10）。
- `.github/` 目前**只有** `dependabot.yml` 與 `workflows/`，**沒有** `ISSUE_TEMPLATE/`（ADR 0023 §後果明說「repo 目前沒有 issue 範本，落地時新增 `.github/ISSUE_TEMPLATE/bug_report.yml`」——屬 M3）。

---

## 5. 候選 PR 分組（供 planner 參考；非 ADR 決定）

依第 2 節的順序，把 M1 切成可 review 的 PR。**這是建議，不是 ADR 或計畫的決定**；擁有者核准 prd／design／implement 時再定案（ADR 0026 §決定 1）。

1. 指令檔分家＋`app/` 骨架：`app/` 專案、flavor、App 身分、單一實例鎖、`app/AGENTS.md`；根 `AGENTS.md` 縮成共用部分、舊規則搬到 `lib/AGENTS.md`；spec 的 `packages:` 決定（§3.1、§3.3；ADR 0008、0015 §決定 8、0027）。
2. `fmp_lints` 骨架＋接線哨兵＋首批規則（ADR 0015 §決定 2；批次見 §3.9）。
3. 平台層骨架＋`PlatformCapabilities`＋目錄規則（ADR 0009 §決定 1–8）。
4. drift＋`sqlite3`＋最小 schema＋快照＋`TrackKey`（ADR 0010 §決定 1–3；表集見 §3.10）。
5. 設定分組表＋log 門面＋遮蔽函式＋log 檔（ADR 0011；格式見 §3.8）。
6. `AppError`＋重試策略（ADR 0013）。
7. 網路層：API client＋媒體 client＋攔截器＋`AuthRequirement` 掛鉤（ADR 0012；掛鉤範圍見 §3.4）。
8. JS 執行環境＋宿主 API v1＋從檔案載入 B 站插件（ADR 0014 §決定 1–5）。
9. 播放核心最小集：兩個後端＋兩首的佇列＋前瞻交接（ADR 0018；邊界見 §3.16）。
10. `Toaster`＋`ToastHost`（ADR 0023 §決定 1–3、5）。
11. UI token＋斷點＋字型＋slang 骨架＋播放快捷鍵（ADR 0024；殼的範圍見 §3.17）。
12. 零聯網防線＋fixture＋契約執行器＋測試插件（ADR 0015 §決定 3–6；QuickJS 結論見 §3.15）。
13. CI 切分＋`app` job＋`always()` 彙總（ADR 0015 §決定 9）。
14. release-please dry-run workflow（ADR 0022 §決定 1；做法見 §3.12）。
15. `app/` 的 verify-on-device 改寫＋`app/AGENTS.md` 驗證段（ADR 0027）。
16. 限時探針任務：YouTube.js 可行性（ADR 0014 §決定 10）——可插在第 9–15 之間並行。

`milestones.md` §M1 的兩格驗收（「兩平台端到端操作」「§7 全部項目」）在第 15 個 PR 之後由擁有者實機確認，依 ADR 0026 §如何確認（review 點，不寫成測試）。
