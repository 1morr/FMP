# current-state — 里程碑定稿的事實盤點

- 任務：`09-28-design-milestones`（Phase-2 第 7 項「重寫策略（里程碑定稿）」）
- 來源優先序：程式碼 > 測試 > 文件。本檔的事實都附 `file:line`。
- 用途：把 ADR 0008–0025、phase2-plan、parent prd、審計檔案中所有跟「里程碑怎麼切、切換條件是什麼」有關的事實攤平，**不決定**里程碑方案。
- 讀法：§1 是逐份 ADR 的盤點；§2 是 phase2-plan 的原話；§3 是切換條件；§4 是平台順序；§5 是矛盾與未定項。

---

## 1. ADR 0008–0025 逐份盤點

欄位說明：
- **模組／能力**：這份 ADR 引入什麼。
- **依賴 ADR**：文中明確以 `ADR 00xx` 字樣引用者（由 `grep -o "ADR 00[0-9][0-9]"` 收集，排序去重）。
- **里程碑歸屬**：文中指定屬於「第一個里程碑」或特定里程碑的項目（逐字或緊貼原文）。
- **如何確認（一行）**：該 ADR §如何確認 的閘門摘要。

| ADR | 模組／能力 | 依賴 ADR | 里程碑歸屬 | 如何確認（一行） |
|---|---|---|---|---|
| **0008** 新 App 同 repo | `app/` 新專案、main 分支、舊專案凍結；葉節點複製；App 身分沿用（`applicationId`/AppUserModelID/Inno AppId/簽名金鑰） | 0014, 0015 | 第一個里程碑＝tracer bullet：**一個音源能搜尋並播放，Android 與 Windows 跑通**（:44）。切換前的里程碑另加一項檢查：比對 `app/` 的 `applicationId`、AppUserModelID、Inno AppId 與現值一致（:73） | lint `fmp_layer_imports`（`app/` 不 import 舊專案）；測試斷言 prod flavor 身分值；切換 PR 的 review 指南逐項列 `features.md` 勾「保留」的功能與效能量測（:70-74） |
| **0009** 平台層＋能力宣告 | `app/lib/platform/`（每能力一目錄）、`PlatformCapabilities` 不可變宣告、Pigeon、平台套件只在實作檔、不寫空實作 | 0015, 0018, 0020, 0021, 0022 | 上線順序（決定 9，:55-57）：**Android、Windows 從第一個里程碑起全面驗證**；**Linux、macOS、iOS 從第一個里程碑起在 CI 編譯**（iOS 加模擬器測試）；**Linux 在第一個里程碑後開 child task** 於虛擬機實機驗證、之後每個里程碑冒煙測試；macOS／iOS 取得設備後各開 child task；各平台**實機驗證完成後才發佈**。CI 建置矩陣含 Linux／macOS／iOS（不簽名）從第一個里程碑起（:82） | lint `fmp_platform_checks` + `fmp_layer_imports`；每個平台 child task 驗收含「宣告為沒有的能力，UI 不出現入口」（:78-82） |
| **0010** drift 資料層＋legacy_import | drift＋sqlite3（native assets）；`legacy_import/` 一次性模組；schema 版本 `kFmpSchemaVersion` | 0002, 0005, 0008, 0009, 0015 | 第一個里程碑在 Android、Windows 實測：`isar_community` 與 `sqlite3` 兩套原生庫共存（若衝突，legacy import 改成新 App 啟動的獨立一次性小程式）；`sqlite3` 的 **Android 16KB page size 對齊**（用官方對齊檢查）（:71-72） | schema 快照＋每個 migration 升級測試在 CI；「migration 不改使用者設定值」專門測試；`fmp_layer_imports`（`legacy_import` 不被 import、DB 只由資料層存取）；切換前在擁有者真實資料副本跑完整匯入並把筆數比對附在切換 PR 的 review 指南（:75-79） |
| **0011** 設定＋log 門面 | 單一 log 門面＋單一遮蔽函式；設定 schema（新增音源不改 schema） | 0009, 0010, 0015, 0024, 0025 | **log 門面與遮蔽函式是第一個里程碑的基礎，含遮蔽測試**（phase2-plan §7 :224）。log 保留 7 天／JSON Lines／開發者模式持久化延到 ADR 0025（:55） | lint `fmp_log_facade`；遮蔽測試（每音源假憑證＋假簽名 URL，經 log 檔／記憶體歷史／診斷包／網路紀錄都不出現，**含 stackTrace**）；設定測試（使用者值不被新預設覆蓋）（:57-61） |
| **0012** 網路層＋帳號 | HTTP client、`CredentialStore`、`AuthRequirement` 單一宣告點、媒體請求不帶憑證 | 0009, 0010, 0011 | **YouTube App 內網頁登入是否可用 → 第一個加入 YouTube 登入的里程碑先實測**（:64）；Linux 沒有 keyring 時 secure storage 行為 → Linux child task（phase2-plan §8 :235） | 契約測試媒體請求不帶 Cookie／Authorization；`AuthRequirement` 三態（未登入／已登入開關開／已登入開關關）注入結果；刷新後重送帶新憑證；每音源「憑證無效」判定表（限流與網路錯誤碼不誤標失效）；登出／重設後 `CredentialStore` 為空（:68-72） |
| **0013** 統一錯誤模型 | sealed `AppError`；重試只在網路層（指數退避＋jitter、上限 2、尊重 `Retry-After`）；Riverpod retry 關閉 | 0011, 0012, 0015, 0018, 0023 | 無第一個里程碑專屬項；重試與錯誤對應表貫穿 | 契約測試錯誤 fixture 對到 `AppError` 類別；`ProviderScope` retry 關閉、只對冪等請求重試；lint `fmp_no_empty_catch`；UI 不得顯示 `toString()`（以只收 i18n key 的呈現 API 在型別上擋）（:72-77） |
| **0014** 腳本音源插件 | 插件為執行期 JS 腳本（flutter_js：QuickJS Android/Windows/Linux、JavaScriptCore iOS/macOS、ES2020）；manifest＋宿主 API v1；`apiVersion` 相容管理；無內建音源 | 0008, 0009, 0011, 0012, 0015, 0016, 0018, 0019, 0020, 0021 | **第一個里程碑變重**（要先有 JS 執行環境與宿主 API）（:65）。第一個里程碑實測：flutter_js 在 Android／Windows 的 **Promise／記憶體／啟動成本**；以「從檔案安裝」載入第一個腳本音源；**YouTube.js 可行性驗證（有時限，失敗則 YouTube 暫以 Dart 實作）**（:65、§7 :225）。**插件庫 repo 與插件頁的建立時程在里程碑規劃定**（:67）；§9：建 `1morr/fmp-plugins` repo／CI／`index.json`／App 插件頁與首次啟動引導**排入里程碑規劃，第一個里程碑不需要**（:247） | 結構測試 manifest 能力 vs 實際匯出函式、`apiVersion` 不相容拒絕載入；契約測試重播；宿主 HTTP 只准 manifest 網域；腳本無法讀其他插件的 storage／憑證；lint `fmp_source_id_literal`（:70-75） |
| **0015** 測試／閘門／開發環境 | `app/packages/fmp_lints/`（`analysis_server_plugin`）10 條 lint＋後續規則；flavor dev／prod 隔離；`dorny/paths-filter` CI 依專案切分；零聯網（`dart_test.yaml` live skip＋`HttpOverrides.global`）；`checks.json` 一份四用 | 0008, 0011, 0014, 0017, 0021, 0023, 0024, 0025 | 第一個里程碑實測：`dart analyze` 看得到插件診斷且接線哨兵會紅（比對 `flutter analyze`）；**契約執行器能否在 `flutter test` 內載入 QuickJS**（不行改用桌面 `integration_test`）；dev 與 prod 同時開啟時 AppUserModelID／單一實例鎖／資料目錄各自獨立；**零聯網兩道防線**（故意聯網的測試被跳過、解除 tag 後被 `HttpOverrides` 擋下）（:93-94、§7 :226）。`app` 的 CI job 內容列在 :9（決定 9） | 每條 lint 規則 `analyzer_testing` 雙向變異測試＋CI 接線哨兵；測試 prod 身分值、dev 每項都不同、開發版拒舊版正式資料路徑、掃描所有 fixture 無未遮蔽憑證（:31-96） |
| **0016** 快取與離線 | 統一快取庫（cache.db）、串流 URL 只放記憶體、`expiresAt`、離線判定以請求結果為準（不輪詢 DNS） | 0011, 0012, 0014, 0015, 0017, 0018, 0021 | 無第一個里程碑專屬項；B10「每 15 秒 DNS 偵測」在此拿掉（phase2-plan §5 :189） | 單元：串流 URL 快取安全邊界、`expiresAt` 空、作廢、下載不走快取、**預取後播放只解析一次**；快取跨類別淘汰到上限以下、移除插件刪其項目；網路狀態轉換且**沒有計時器輪詢**；widget 各頁離線狀態；插件契約 `expiresAt` 對 fixture 網址期限參數（:60-66） |
| **0017** 背景任務排程器 | 單一 `BackgroundScheduler`（一個計時器、指向最早到期）；只在可見且在線時跑；到期補跑；啟動維護清單 | 0010, 0011, 0013, 0015, 0016, 0018, 0021, 0022, 0025 | 啟動維護清單「第一個畫面後依序跑一次」（:33）；ADR 0025 加入 log 保留期限與診斷包暫存清理 | 單元（假時鐘／生命週期／網路）：看不見與離線不跑；恢復後到期工作各跑一次；只有一個計時器；手動刷新不看間隔；停用後丟過期結果；退避與 `retryAfter`；上次成功時間重啟後生效。lint `fmp_periodic_timer_owner`（ADR 0021 加桌面歌詞查游標允許擁有者）（:55-66） |
| **0018** 播放核心 | 單一 `PlaybackController`；兩後端（JustAudioBackend Android/iOS/macOS、MediaKitBackend Windows/Linux）；Dart 側 `QueueModel`；`RecoveryPolicy` | 0003, 0009, 0013, 0015, 0016, 0017, 0020 | **第一個里程碑實測：兩個後端的前瞻交接（gapless）；Android 換歌時不釋放音訊焦點**（:85）。蘋果平台 AVPlayer 對 B 站 DASH／HLS → iOS／macOS child task（§8 :236） | 單元：`QueueModel`（隨機位置語意、拖曳、連續下一首、臨時播放快照、Mix 修剪、上限）、`RecoveryPolicy`、開直播取消進行中音樂請求、預取後播放只解析一次、單曲循環每圈一筆歷史不重解析；後端契約測試同一份純規則跑兩實作＋假後端；lint `fmp_layer_imports` 依賴表（`just_audio`/`media_kit` 只在後端實作、結束原因型別只給後端與路由器、串流窄介面只給 `PlaybackSession`）（:72-85） |
| **0019** 音樂庫與同步 | 關聯表（外鍵）、匯入歌單刷新、共用匹配核心（`unorm_dart`／`opencc`／`string_similarity`） | 0005, 0010, 0012, 0013, 0014, 0015, 0017 | 無第一個里程碑專屬項；`opencc` native assets 要在各平台建置驗證（:78 後果） | 單元：刷新差異（新增／移除／順序／元資料／覆寫旗標／部分失敗不移除／重複影片保留／來源失效停止自動刷新／重新匯入不覆寫設定）；評分核心（全半形／繁簡／括號／時長／多歌手，自動與手動同分）；資料庫測試（外鍵連帶刪除、孤兒清理只刪無人參照、刷新中途失敗一致性）；插件契約 `importPlaylist` 分頁完整性、`libraryWrite` 錯誤對應（:81-87） |
| **0020** 下載與權限 | `background_downloader`；`PermissionGateway`；sidecar／內嵌標籤；對帳 | 0004, 0011, 0012, 0015, 0017, 0019, 0021, 0022 | **加入下載的里程碑實測**：`permission_handler` 在 Windows 是否使 FMP 出現位置權限清單（會就改 Android 專用自有 MethodChannel）；寫入的標籤能被常見播放器讀到；Android 以 `MANAGE_EXTERNAL_STORAGE` 搬移到使用者資料夾可行（:107-110） | 單元（假下載器）：並行上限、失敗任務跨重啟保留、網址過期重解析從頭下載、ETag 不符從頭下載、格式過濾、暫存→標籤→搬移任一步失敗不留半成品；對帳測試（檔案遺失不刪紀錄、從不刪檔）；路徑測試（檔名清理、Windows 長度、保留名）；權限流程測試（假 `PermissionGateway`）；`fmp_layer_imports`（`background_downloader` 只在下載模組、`permission_handler` 只在平台層）（:94-110） |
| **0021** 歌詞 | 多源歌詞（插件 `lyrics`／`aiAssist` 能力）、逐行／逐字、桌面歌詞視窗、Android 懸浮歌詞、iOS Live Activity；型別化訊息 | 0009, 0010, 0011, 0012, 0014, 0015, 0016, 0017, 0019, 0020, 0023, 0024 | **逐字渲染用 `flutter_lyric`（避開已撤回 3.0.5）或自寫 → 在第一個加入逐字的里程碑決定**（:143）；平台實測延後：桌面歌詞 macOS／Linux X11／Wayland 的穿透置頂定位、`window_manager` 在子 engine、`flutter_overlay_window` 記憶體與 Android 15 前景服務限制、iOS Live Activity 本機逐行更新（:161-165、§8 :237） | 單元（LRC 解析含 enhanced 字時間、翻譯 100ms 對齊、逐字→逐行降級、匹配流程各分支、偏移換算、顯示端外推）；插件契約 `lyrics`／`aiAssist`（AI 插件測試斷言 log 不含 payload）；宿主測試（AI 只含設定頁欄位、非 https 拒、網域確認）；型別化訊息序列化往返；lint `fmp_periodic_timer_owner` 加桌面歌詞查游標、`fmp_layer_imports`（`desktop_multi_window`／`window_manager`／`flutter_overlay_window` 只在平台層實作檔）（:145-160） |
| **0022** 發版與應用內更新 | release-please（dart strategy、manifest 模式）；首版 `Release-As: 2.0.0`；versionCode = major×1000000＋minor×1000＋patch；`appUpdate` 平台能力 | 0004, 0008, 0009, 0010, 0011, 0012, 0013, 0015, 0017, 0020 | 第一個里程碑：**release-please 的發版 PR 與同一 workflow 的建置、驗證、發布跑通（測試 repo 或 dry-run）**（§7 :227）。**切換 PR 前以舊版 v1.11.0 實際更新到新 App**（Android、Windows 安裝版與免安裝版）；Windows App 自下載安裝檔不帶 Mark of the Web；macOS 更新不帶 quarantine（平台任務）；Linux AppImage 改名替換（:139-143、§8 :240） | 單元（版本比較含 build number、依能力挑 asset 與 ABI 退回、checksums 解析／缺檔拒／digest 不符拒、RateLimited、狀態機與操作代際、清理只刪不大於目前版本、更新程式改名替換與失敗回復、zip-slip）；workflow 測試（release-please 輸出否時不建置、verify 檔名集合／checksums／別名／APK 版本／PE 標頭／舊版更新器相容、pubspec 版本等於 manifest）；`fmp_layer_imports`（:123-138） |
| **0023** 統一 Toast | 單一 `Toaster` 入口（provider 注入）、`ToastHost` 包住 Navigator、`ErrorReport`、錯誤詳細頁與 GitHub 回報 | 0011, 0013, 0015, 0021, 0025 | **第一個里程碑實測**：提示在全螢幕頁與對話框之上可見；**Windows Narrator 下提示不凍結無障礙樹**（:101）。之後注意：repo 目前**沒有 issue 範本**，落地時新增 `.github/ISSUE_TEMPLATE/bug_report.yml`（:89） | lint `fmp_toast_entry`（`SnackBar(`／`ScaffoldMessenger.of`／`showSnackBar`／`clearSnackBars` 只准在 toast 模組，雙向變異測試）；單元（去重視窗／取代／時長／開發者與一般使用者按鈕／`ErrorReport` 經遮蔽／GitHub 網址不含報告）；widget（全螢幕路由與對話框開啟時提示可見、底部位移依外殼發佈高度）（:91-101） |
| **0024** UI／UX 設計系統 | Material 3＋`AppTokens` ThemeExtension；五個 WindowClass 斷點；i18n slang base `zh-TW` 三語言；App 內快捷鍵（F6／Esc／space）；播放頁方案 B | 0009, 0011, 0015, 0021, 0023 | **第一個里程碑實測：輸入框內空白鍵不觸發播放；F6 焦點切換；Windows 繁中字形由正黑體顯示**（:159） | lint `fmp_design_tokens`（`lib/ui/`（theme 除外）不得在 `EdgeInsets.*`／`SizedBox` 寬高／`BorderRadius.circular`／`fontSize:` 用數字字面值（0 除外），不得寫 `Color(0x…)`／`Colors.*`）；widget（首頁／搜尋／歌單／播放頁／設定淺深主題通過 `labeledTapTargetGuideline` 與 `textContrastGuideline`、快捷鍵與焦點含輸入框內空白鍵、播放列三段寬度曲名 ≥160dp）；golden（alchemist 播放頁 B 在 1000／1400／1800 寬）；i18n 三語言 key 集合相同（:149-159） |
| **0025** Debug 頁與開發者模式 | 8 區塊 Debug 頁；開發者模式持久化於設定；log JSON Lines、2MB×3、7 天保留；診斷包 | 0009, 0010, 0011, 0012, 0015, 0016, 0017, 0018, 0019, 0020, 0023, 0024 | **加入 Debug 頁的里程碑實測**：Windows release 版開啟開發者模式、重啟後仍開啟、再從總開關關掉；Debug 頁看得到一次搜尋的網路摘要；匯出診斷包能以解壓工具打開（:207-210、§8 :239） | lint `fmp_platform_checks`（Debug 模組只讀平台層宣告，不寫 `Platform.isX`）；單元（開發者模式 7 連點／關閉清空／dev 預設開；7 天保留；JSON Lines 讀回一致且壞行略過；網路篩選；資料檢查外鍵報告；重設備份失敗不清空；遮蔽併入 0011）；widget（關閉時直進 Debug 路由會被 redirect、未宣告 `pluginDevTools` 不顯示插件開發區塊、未宣告檔案分享不顯示）（:187-206） |

補充依賴：ADR 0002 `repository-boundary` 引用 0008、0010；ADR 0007 `isar-stays-on-v3` 引用 0008、0010。舊 ADR 0001–0007 描述的是根目錄舊專案（phase2-plan §10 :252）。

---

## 2. phase2-plan 的原話（逐條引用）

檔案：`.trellis/tasks/09-26-fmp-rewrite/phase2-plan.md`

### §1 設計項目（:8-34）— 第 7 項與第 20 項

> `| 7 | 重寫策略（全新 vs 逐步、里程碑、分支、舊版 hotfix） | N1 hotfix 已選「重寫時處理」 |`（:21）

> `| 20 | 功能凍結待辦（新增，不設計，只記錄） | 均衡器、響度平衡；B 站 geetest 驗證互動（ADR 0013）；邊聽邊存、手動離線模式、已下載內容容量管理（ADR 0016）；來源失效時另存為本地歌單、曲目收藏、疑似換版本偵測（ADR 0019）；Android 狀態列歌詞、本機歌詞檔匯入（ADR 0021） |`（:34）

### §3 建議順序（:109-132）— 第 2 與第 20 列的里程碑說明

> `| 2 | 7 重寫策略（高層）（✅ 完成，ADR 0008；里程碑留到第 20 步定稿） | 「全新專案 vs 在舊碼上逐步替換」決定資料遷移、分支與每個里程碑的形狀。這裡只定方向，里程碑到最後才拆。 |`（:113）

> `| 20 | 7 重寫策略（里程碑定稿） | 所有設計確定後拆成可獨立驗證的里程碑與 child task。 |`（:131）

### §7 第一個里程碑的必要驗證（:219-230）

> `- ADR 0010：isar_community＋sqlite3 原生庫在 Android、Windows 共存；sqlite3 的 Android 16KB page size 對齊。`
> `- ADR 0009：CI 建置矩陣含 Linux、macOS、iOS（不簽名）。`
> `- ADR 0008：app/ 的 App 身分識別與舊版一致（開發版除外）。`
> `- ADR 0011：log 門面與遮蔽函式是第一個里程碑的基礎，含遮蔽測試。`
> `- ADR 0014：JS 執行環境（flutter_js）與宿主 API 最小集合；以「從檔案安裝」載入第一個腳本音源；flutter_js 在 Android、Windows 的 Promise／記憶體／啟動成本實測；YouTube.js 可行性驗證（有時限，失敗則 YouTube 暫以 Dart 實作）。`
> `- ADR 0018：兩個後端的前瞻交接（gapless）；Android 換歌時不釋放音訊焦點。`
> `- ADR 0015：fmp_lints 接上 app/，dart analyze 看得到插件診斷且接線哨兵會紅（比對 flutter analyze）；契約執行器能否在 flutter test 內載入 QuickJS（不行改用桌面 integration_test）；dev 與 prod flavor 同時開啟時 AppUserModelID、單一實例鎖、資料目錄各自獨立；零聯網兩道防線（故意聯網的測試被跳過、解除 tag 後被 HttpOverrides 擋下）。`
> `- ADR 0022：release-please 的發版 PR 與同一 workflow 的建置、驗證、發布跑通（測試 repo 或 dry-run）。`
> `- ADR 0023：提示在全螢幕頁與對話框之上可見；Windows Narrator 下提示不凍結無障礙樹。`
> `- ADR 0024：輸入框內空白鍵只輸入空格；F6 焦點切換；Windows 繁中字形由正黑體顯示。`

### §8 延後到特定里程碑的實測（:232-240）

> `- ADR 0012：YouTube App 內網頁登入（桌面 UA）是否仍可用——第一個加入 YouTube 登入的里程碑先實測；不可用則只提供貼上 cookie。`
> `- ADR 0012：Linux 沒有 keyring 時 secure storage 的行為——Linux child task。`
> `- ADR 0018：蘋果平台 AVPlayer 對 B 站 DASH 音訊與直播 HLS 的支援——iOS／macOS child task。`
> `- ADR 0020：加入下載的里程碑——permission_handler 在 Windows 是否使 FMP 出現在位置權限清單；寫入的標籤能被常見播放器讀到；Android 以 MANAGE_EXTERNAL_STORAGE 搬移到使用者資料夾。`
> `- ADR 0021：加入桌面歌詞的里程碑——macOS、Linux X11、Wayland 的穿透、置頂、定位；window_manager 在子 engine 設穿透作用在歌詞視窗。加入 Android 懸浮歌詞的里程碑——flutter_overlay_window 的記憶體與 Android 15 前景服務限制。加入逐字的里程碑——flutter_lyric 直接用或自寫。iOS 平台任務——Live Activity 本機逐行更新。`
> `- ADR 0025：加入 Debug 頁的里程碑——Windows release 版開啟開發者模式、重啟後仍開啟、再從總開關關掉；Debug 頁看得到一次搜尋的網路摘要；匯出的診斷包能以解壓工具打開。`
> `- ADR 0022：切換 PR 前以舊版 v1.11.0 實際更新到新 App（Android、Windows 安裝版與免安裝版）；Windows App 自行下載的安裝檔不帶 Mark of the Web。macOS 平台任務——App 自行下載的更新不帶 quarantine。Linux 平台任務——AppImage 的改名替換。`

### §9 功能凍結的例外與里程碑規劃備忘（:242-247）

> `- 腳本插件（ADR 0014）由擁有者明確納入重寫範圍（2026-09-27）。`
> `- 歌詞的逐字歌詞、桌面歌詞點擊穿透與鎖定、Android／iOS 懸浮歌詞由擁有者納入第 15 項（2026-09-28）。`
> `- 以上是功能凍結僅有的例外。`
> `- 建立 1morr/fmp-plugins repo、其 CI 與 index.json、App 插件頁與首次啟動引導：排入里程碑規劃（第 20 步）；第一個里程碑不需要。`

### §10 交接（:249-269，節錄）

> `- 分支：docs/audit（draft PR #173）。所有設計決定以 ADR 為準：docs/adr/0008–0025；舊 ADR 0001–0007 仍描述根目錄舊專案。`（:251）
> `- 每項的 prd／design／research 在 .trellis/tasks/archive/2026-09/09-2?-design-*。下一份 ADR 編號 0026。`（:254）
> `- 每項固定流程：建 child task（task.py create --parent .trellis/tasks/09-26-fmp-rewrite --no-start）→ 派研究子代理（sonnet，寫進 task 的 research/）→ 核對關鍵事實 → prd → 一次一問（附建議與取捨）→ design＋implement → 最終摘要 → 使用者「核准」後 task.py start、寫 ADR、更新本檔 §3 標記完成、task.py finish＋archive --no-commit --skip-branch-validation、commit＋push。`（:257）

---

## 3. 切換條件（ADR 0008 §決定 5）與「保留」清單的真實出處

### 3.1 ADR 0008 §決定 5（`docs/adr/0008-rewrite-as-new-app-in-same-repo.md:53-57`）

> `5. 切換：docs/audit/features.md 中勾「保留」的功能全部在 app/ 跑通、效能不低於 docs/audit/perf-baseline.md、舊資料自動遷移在真實資料副本上驗證過之後，以一個 PR 刪除根目錄舊專案與 docs/audit/，並把 release.yml、ci.yml、orca.yaml、tool/release/ 改指向 app/。新 App 的第一個正式版本號接在舊版之後，經應用內更新送達，首次啟動執行自動遷移。`

三個必要條件（切換 PR 的前提）：(a) 勾「保留」功能全部在 `app/` 跑通；(b) 效能不低於 `perf-baseline.md`；(c) 舊資料自動遷移在**真實資料副本**上驗證過。切換動作是一個 PR，同時刪舊專案與 `docs/audit/`、改四個檔案指向 `app/`。

### 3.2 「保留」清單的真實出處（**與 ADR 0008 的措辭不一致**）

- `docs/audit/features.md`（446 行，16 節）**沒有勾選欄**：全檔 `[x]` 出現 0 次（`grep -c -F '\[x\]'` = 0）；「保留」只出現 2 次、「刪除」14 次、「修改」1 次，都在敘述文字裡，不是決策標記。
- 實際的勾選在 `docs/audit/questions.md`（137 個 `[x\]`）。其中 §7 E 項（`:232-263`）自述：

> `完整清單在 features.md；這裡只列需要你表態的功能域。狀態欄沿用 features.md 的判定。`（:234）

→ 里程碑定稿時必須**以 `questions.md` 為勾選來源**，`features.md` 當功能清單。否則 features.md 有幾百條功能沒有去留標記。（列為 §5 待確認第 1 條。）

### 3.3 依 questions.md 的勾選統計（依 §節分組，附行號）

| 節 | 主題 | 已勾結果 | 行號 |
|---|---|---|---|
| §1 A1 | 目標平台 | **Android、Windows＝「重寫第一版就要」**；**Linux、macOS、iOS＝「之後加入」** | :31-35 |
| §1 A2 | 資料層是否更換 | **不確定**（保留 isar_community vs 更換都未勾） | :53 |
| §1 A3 | 資料相容 | 資料庫（歌單／曲目／歷史／設定／佇列）、登入憑證、已下載音檔與 sidecar、備份檔 **4/4＝「保留並自動遷移」**（備份檔另註「新版能匯入舊備份」） | :62-65 |
| §1 A6 | 發佈平台 | Android、Windows、Linux、macOS＝GitHub Release；**iOS 不確定**；另「維持自動發布」（推翻 ADR 0006 的選項未勾） | :95-99, :102 |
| §2 B項 | 對外寫入／第三方／自下載 | B1、B2 **保留**；B3–B14 **不確定** | :115-128 |
| §3 C項 | 安全與隱私缺陷 | C1–C7 **重寫時修正** | :140-146 |
| §4 M項 | 帳號與登入狀態播放 | M1–M13 **全部不確定** | :160-172 |
| §5 N項 | 下載與權限 | N1 **「先不修，重寫時處理」**；N2–N11 不確定 | :185, :190-198 |
| §6 D項 | 播放行為語意 | D1、D2、D7 **保留**；其餘不確定 | :212-223 |
| §7 E項 | 功能去留 | **E1–E17 保留（17/20）**；E18–E20 不確定 | :237-258 |
| §8 | 平台綁定功能在他平台去留 | 12 列**全部不確定** | :270-283 |
| §9 G項 | 架構與程式碼現況問題 | G1–G9 **重寫時處理** | :295-305 |
| §10 | 測試類別去留 | 7 列**全部不確定**；另勾「不管，重寫時處理」（main CI 現為紅） | :317-330 |
| §11 | i18n | **en、zh-CN、zh-TW 三語言保留** | :341-350 |
| §12 U項 | UI／UX 問題 | U1–U9 **重寫時處理**（U7 註「保留常駐」、U8 註「實作」、U9 註「開發版用獨立資料目錄」） | :360-370 |
| §13 J項 | 開發者模式與 log | J1 **保留**；J2–J4 不確定 | :380-385 |
| §14 §15 | ADR 逐份／CONTEXT.md 術語 | **全部未勾** | :397-405, :417-423 |

E 項 20 條功能域（`:237-258`）：E1 三音源搜尋播放、E2 B 站分 P、E3 音樂庫歌單、E4 匯入平台歌單＋定時刷新、E5 僅匯入外部歌單匹配、E6 帳號登入、E7 遠端歌單編輯、E8 下載、E9 多源歌詞、E10 AI 歌詞匹配、E11 桌面歌詞視窗、E12 電台直播、E13 Mix、E14 首頁排行、E15 播放歷史、E16 備份還原、E17 應用內更新 → 全「保留」；E18 托盤／快捷鍵／開機自啟／單一實例、E19 播放速度／音量／輸出裝置（無睡眠定時器與均衡器）、E20 使用者指南頁 → 不確定。

### 3.4 效能基準 `docs/audit/perf-baseline.md` 量了什麼

- 量測日 2026-09-26，分支 `docs/audit`，HEAD `6d78fe23`（:5）。環境：**Flutter 3.47.1 stable（framework `6655482ec0`、engine `11d79658c4`）、Dart 3.13.1**（:13）；profile build。

| 指標 | Android（AVD Medium_Phone） | Windows |
|---|---|---|
| 冷啟動到首幀 `timeToFirstFrameMicros`（3 次中位數） | **1239 ms** | **1731 ms** |
| 首幀完成光柵化 `timeToFirstFrameRasterizedMicros` | 1292 ms | 1752 ms |
| `am start -W` TotalTime（中位數） | 1482 ms | — |
| 首頁穩定後記憶體 | PSS **183,367 KB**（≈179 MB）／RSS 310,752 KB | Working Set **299.9 MB**／Private **440.6 MB** |
| 長列表捲動 UI thread `Animator::BeginFrame` 中位數／p99 | 1.00 ms／4.18 ms（歌單 154 首） | 0.45 ms／5.45 ms（佇列 1195 首） |
| 長列表捲動 raster `GPURasterizer::Draw` 中位數／p99 | 4.27 ms／21.62 ms | 1.96 ms／2.72 ms |
| 捲動中 >16.7 ms 的 raster 幀 | 43/302、17/306 | 0/312、0/316 |

（:28-36、:184-199。）Android AVD：`Medium_Phone` API 37（`android-37.2-beta3` google_apis_playstore ps16k x86_64）、4 vCPU、2048 MB RAM、1080×2400 @ 420 dpi（:15）。此檔自述「這份文件是重寫後的比較基準：每個數字都附量測命令與原始輸出摘錄，重寫後用同一組命令重量即可對照」（:5）。

---

## 4. parent prd 的里程碑約束與平台順序

檔案：`.trellis/tasks/09-26-fmp-rewrite/prd.md`

### 4.1 第 7 項原文（:130-132）

> `7. 重寫策略 —— 全新重寫 vs 逐步替換，給建議與理由；`
> `   拆成可獨立驗證的里程碑，每個里程碑結束時 App 都能正常運作。`
> `   說明分支與發版策略：重寫期間舊版的修正在哪裡做、使用者跳版升級時資料與憑證如何遷移。`

### 4.2 重構過程的約束（:198-206）

> `- 可 review 性優先：每個 child task 產出一個 PR，大小控制在我能 review 的範圍，太大就拆；每個 PR 附 review 指南（改了什麼、為什麼、我該看哪幾個檔案、怎麼實際驗證）；沒有經我確認的 ADR 的設計，不進代碼。`
> `- 功能凍結：重寫期間不加新功能，想到的記進 parent task 的待辦，不實作。`
> `- 完成定義：features.md 中我勾「保留」的功能全部在新架構上跑通，且效能不低於階段一記錄的基準。`
> `- 重寫期間不發布正式版本；舊版的緊急修正怎麼處理，在階段二的重寫策略中提出方案。`
> `- 參考其他開源專案時只參考設計；要複製代碼，先確認授權相容並告訴我。`

### 4.3 Trellis 任務管理（:208-212）

> `- 建立 parent task fmp-rewrite，把這整份 prompt 原文存成它的 prd.md。`
> `- 階段一建成它的第一個 child task audit（只寫 PRD，屬於輕量任務），然後開始執行。`
> `- 之後每個里程碑、每個新平台各是 fmp-rewrite 下的一個 child task，規劃時用 trellis-brainstorm 與我逐項確認，各自有 prd／design／implement。`

→ **每個里程碑是一個 child task；每個新平台也是一個 child task**，兩者都要有 prd／design／implement。

### 4.4 平台相關（第 10 項，:156 附近）

> Linux 早列為第三平台以驗證抽象；macOS／iOS 以 GitHub Actions macOS runner 做編譯檢查 ＋ iOS 模擬器，實機之後；每個平台是一個 child task 並註明需要的硬體／環境。

### 4.5 平台順序（ADR 0009 §決定 9 :55-57 ＋ questions.md A1 :31-35）

- **第一版就要**：Android、Windows。兩者從第一個里程碑起**全面驗證**。
- **之後加入**：Linux、macOS、iOS。三者從第一個里程碑起**在 CI 編譯**（iOS 加模擬器測試），但**實機驗證完成後才發佈**。
- Linux：第一個里程碑後開 child task，於虛擬機實機驗證，之後每個里程碑冒煙測試。
- macOS、iOS：取得設備後各開 child task。

---

## 5. 矛盾與未定項（「待確認」）

1. **勾選來源不一致**：ADR 0008 §決定 5（:53）與 parent prd 完成定義（:203）都寫「`features.md` 中勾『保留』的功能」，但 `features.md` 沒有任何勾選欄（0 個 `[x]`）；真正的勾選在 `questions.md`，其 §7 E 項（:232-263）自述「完整清單在 features.md；這裡只列需要你表態的功能域」。**里程碑定稿要指名以 questions.md 為準。**
2. **「切換前的里程碑」沒有編號**：ADR 0008 :73（身分比對）、ADR 0010 :79（真實資料副本匯入）、ADR 0022 :139-143（以 v1.11.0 實際升級）都說「切換前／切換 PR 前」，但沒有任何文件把「切換里程碑」命名或編號。里程碑切法要自己定。
3. **第一個里程碑的 CI 矩陣是 5 平台，第一版只發 2 平台**：ADR 0009 :82 要求 CI 從第一個里程碑起含 Linux／macOS／iOS 不簽名建置，而 questions A1 說那三個平台「之後加入」。不是直接矛盾（編譯 ≠ 發布），但里程碑驗收要寫清楚。
4. **第一個里程碑明顯偏重**：ADR 0014 :65 自陳「第一個里程碑變重（要先有 JS 執行環境與宿主 API）」，phase2-plan §7 又疊了 10 份 ADR 的實測項。§7 的項目是否全塞同一個里程碑、或再切成 tracer bullet ＋ 第二里程碑，尚無定論。
5. **功能凍結例外與里程碑規劃的掛勾**：phase2-plan §9 :247 把「建 `1morr/fmp-plugins` repo／CI／`index.json`／插件頁／首次啟動引導」排進里程碑規劃但「第一個里程碑不需要」；這些要有明確落點，否則會漏。
6. **ADR 0011 的未定項**：:55「各組設定的欄位清單在里程碑中依 `docs/audit/data.md` §7 定案」——里程碑計畫要承接這一項。
7. **啟動維護清單的跨 ADR 歸屬**：ADR 0017 :33 定義清單，ADR 0025 加入 log 保留期限與診斷包暫存清理；哪個里程碑實作未定。
8. **效能基準的可比性**：`perf-baseline.md` 用 Flutter 3.47.1（:13）；`app/` 會從當前 stable（3.47.5）起（見 `repo-mechanics.md`）。切換條件「效能不低於基準」要用同一組命令重量，引擎版本差異要先記錄。
9. **舊 ADR 與新 ADR 並存**：ADR 0001–0007 描述根目錄舊專案（phase2-plan :252），切換 PR 要刪 `docs/audit/`；這些舊 ADR 的去留未在同一處寫明。

---

## 查不到／推測

- **查不到**：任何「里程碑」的既有編號、名稱或數量。全部 ADR 只有「第一個里程碑」「加入下載的里程碑」「加入 Debug 頁的里程碑」這類描述性指稱，沒有 M1／M2 這種清單。
- **查不到**：`features.md` 的「保留」勾選欄。ADR 0008 與 parent prd 都指向它，但檔案裡沒有（見 §5 第 1 條）。
- **查不到**：切換里程碑的正式名稱或它在順序中的位置。
- **推測**：§3.3 的統計是依 `grep` 到的 `[x\]` 標記與表格欄位對位；`[x\]` 是轉義過的字面（`\[x\]`），一般 Markdown 檢視器可能不把它渲染成勾選框。
- **推測**：`perf-baseline.md` 的 Windows 數字是在同一台主機、載入 1195 首佇列與 Detail Panel 的狀態下量的（:139 自述），換到 `app/` 後若首頁預設狀態不同，數字不可直接比；需以「同一組命令、同一初始狀態」重測。
