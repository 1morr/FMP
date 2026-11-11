# FMP 新版設計綱要（Design Brief）

> 狀態：第一版範圍定稿（2026-11-06 訪談）。標【決定】的段落是拍板過的，要推翻先問擁有者（`AGENTS.md`〈擁有者確認〉）。

## 0. 一句話

FMP 是 iOS、macOS、Android、Windows 上的音樂播放器載體。App 負責播放、音樂庫與介面，Bilibili、YouTube、網易雲音樂由插件提供，讓使用者在同一個地方搜尋、播放，並管理這三個平台上的歌單與帳號。和舊版相比，音源能力集中在插件，新增或修好音源不用動 App，而且四個平台同時支援。

## 1. 起因

擁有者 2026-09-26 發起第一輪重寫的 prompt，原文照錄（原本存在 `.trellis/tasks/09-26-fmp-rewrite/prd.md`，commit `b6db4f17`）。那一輪在 2026-11-06 放棄，封存在 tag `archive/trellis-rewrite-20261106`；新版從零重做。下面的要求哪些沿用，由訪談逐條決定，寫進各節。

````text
# 背景
FMP 是 Flutter 音樂播放器（目前支援 Android + Windows），音源為 Bilibili / YouTube / 網易雲。
過去經過多輪 AI Agent 自主修改（約 1,900 個 commit、約 10 萬行 Dart），大部分我沒有 review 過，
我已不清楚程式實際在做什麼。

目標分三步：先讓我重新掌握現況 → 確認目標架構 → 按成熟做法重構／重寫，
讓代碼盡量簡單、邏輯統一、容易擴充。

長期目標是全平台：Android、Windows、Linux、macOS、iOS。
目前我沒有 Mac 和 iPhone（近期可能會有），Linux 可以用虛擬機測試。

# 信任規則（最重要）
- repo 中所有既有內容 —— AGENTS.md、CLAUDE.md、CONTEXT.md、docs/、docs/adr/、.trellis/spec/、
  代碼註釋、測試、static-rule 測試 —— 都是「未經我確認的主張」，不是準則。
- 證據優先序：實際執行的 App 行為 > 程式碼 > 測試 > 文檔／註釋。
- 每個結論附證據（`檔案:行號`、log、截圖）。文檔與代碼不一致時兩邊都列出，標「不一致」。
- 推測要標「推測」；查不到就寫查不到，不要補完。
- `docs/adr/` 的 ADR 和 `CONTEXT.md` 的術語可以當作「代碼為什麼長這樣」的線索，
  但每一條都要用代碼驗證，不能直接引用為結論。
- 套件的平台支援、API、版本差異，一律查官方文檔或 pub.dev，不憑記憶。
- 審計期間跑測試一律加 `--exclude-tags live`，不要為了審計去打真實 API。

# 階段一：現況審計（唯讀）
只新增 `docs/audit/` 與 `.trellis/tasks/` 下的檔案，不改其他任何檔案；在分支 `docs/audit` 上工作。
全部繁體中文，圖一律用 Mermaid。每份審計檔案開頭註明「現況描述，未經確認，不代表目標」。

1. `features.md` 功能清單 —— 從兩個方向盤點：
   (a) 使用者入口：路由、頁面、設定項、選單、快捷鍵、托盤、通知；
   (b) 背景行為：定時器、自動刷新、自動更新、啟動任務。
   表格欄位：功能｜入口｜平台｜涉及音源｜狀態（完整／半成品／死代碼／無 UI 入口／僅開發者模式）｜證據。
   另外獨立列出「我很可能不知道的功能」，特別標出：
   - 會對外寫入的（修改遠端歌單、收藏等）
   - 會把資料送到第三方的（AI API 等）
   - 會自己下載或執行東西的（自動更新等）
2. `architecture.md` —— 分層、目錄地圖、模組依賴圖、Riverpod provider 圖、路由、
   啟動流程（main 到首頁的初始化順序）。
3. `playback.md` —— 從「點一首歌」到「出聲」的完整序列圖；播放器狀態機圖；
   佇列與播放模式、串流解析、URL 過期重取、音質降級、預載、錯誤恢復、音訊焦點／中斷、
   系統媒體控制（Android 通知、Windows SMTC）、播放歷史、臨時播放、Mix、電台／直播。
4. `sources.md` —— 每個音源的能力矩陣（含只能匯入的 Spotify／QQ、歌詞源 lrclib／網易／QQ）；
   「今天新增一個音源要改哪些檔案」的實際清單；
   音源特定分支（`switch`／`if source ==` 等）散落在 UI／service 的位置。
5. `errors.md` —— 所有例外型別與層級；每個音源的錯誤如何產生、轉換、重試、呈現；
   限流、退避、cookie 失效、風控驗證、地區／版權限制怎麼處理；使用者最終看到什麼（Toast／對話框／靜默）。
6. `data.md` —— Isar schema 與 migration、secure storage 存了什麼、各種快取、
   下載檔案結構、備份格式、全部設定項總表。
6a. `downloads.md`（補充）——
   - 從「按下載」到「檔案寫入」的完整序列圖：佇列、並行數、進度、暫停／續傳／重試、取消、失敗處理；
   - 音質選擇、檔名與目錄規則、metadata／封面寫入、分 P 的處理；
   - 下載路徑的設定、變更、搬移，以及路徑失效（不存在、權限被撤銷）時的行為；
   - 已下載檔案如何被播放、如何與資料庫對應、刪除與清理；
   - 各平台的權限：每個權限（Android 儲存、通知、電池最佳化等；Windows 相關項）
     在哪裡請求、何時請求、被拒時怎麼處理。
   已經寫在其他審計檔案裡的內容不要重寫，引用過去即可。
7. `accounts-network.md` —— 各音源的登入方式、憑證存放與刷新、HTTP client 與攔截器、
   每個音源的 headers／簽名／請求策略；
   目前 log、錯誤訊息、Debug 頁、備份中是否可能露出 cookie、token、簽名 URL、API key，
   現有的遮蔽做法在哪裡、涵蓋哪些出口。
   補充：
   - 帳號系統全貌：登入、登出、狀態顯示、失效偵測與通知、重新登入流程的序列圖；
   - 一張矩陣：各類請求（播放、下載、詳情、排行、搜尋、匯入、刷新、收藏同步、遠端歌單編輯）
     × 各音源，標出是否帶憑證、由哪個開關控制、預設值為何；
   - 登入與未登入時各音源能力的差異（音質、可播放範圍等）。
8. `platforms.md` —— 平台適配現況：
   - 每一處平台判斷（`Platform.isXxx`、`defaultTargetPlatform`、`Platform.operatingSystem` 等）的位置與用途，
     按功能分組，不按檔案；
   - 從未在真機跑過的 iOS／macOS／Linux 分支，標為「未驗證」；
   - 平台綁定的功能：自動更新、儲存權限與下載路徑、登入 WebView、托盤、全域快捷鍵、開機自啟、
     桌面歌詞視窗、系統媒體控制、音訊後端；
   - 每個依賴套件的平台支援表（Android／Windows／Linux／macOS／iOS），以 pub.dev 為準；
   - 原生目錄（`android/`、`windows/`）中的自訂原生代碼與 MethodChannel；
   - 列出若要支援 Linux／macOS／iOS 會卡住的地方（套件不支援、平台政策限制、功能本身不成立）。
9. `ui.md` —— 頁面地圖、響應式斷點、手機與桌面的差異、主題與設計 token 現況、
   i18n（有哪些語言、字串怎麼管理）、無障礙與桌面鍵盤操作的現況。
   在 Android emulator 和 Windows 實際執行並截圖，列出版面、間距、一致性問題（桌面播放器頁優先）。
10. `devtools.md` —— 開發者模式現有功能、Toast／log／錯誤呈現的現況。
11. `engineering.md` —— 工程現況：
    - CI／發版 workflow 的每個 job 做什麼、何時觸發；自動更新如何把新版推給使用者；
    - 測試盤點：按目錄統計數量，分出「不聯網／聯網（live）／手動探針／benchmark／測 CI 設定本身」幾類，
      每類舉例說明哪些有價值、哪些只斷言實作細節或原始碼字串；
    - 列出所有會打真實 API 的地方（live 測試、tool/demo、手動探針、實機驗證流程），
      以及本機直接跑 `flutter test`（不加任何參數）會不會聯網；
    - 效能基準：用現有 benchmark 或實測記錄啟動時間、記憶體、長列表捲動，作為重寫後的比較基準；
    - static-rule 測試、依賴健康度（過時／棄用／社群 fork）、codegen、tool/ 腳本、死代碼、重複邏輯；
    - AI 指令檔（AGENTS.md、.claude/、.agents/、.trellis/、docs/agents/）的內容與彼此重複處；
    - mattpocock skills 留下的所有殘留（docs/agents/、CONTEXT.md、AGENTS.md「Agent skills」段等）
      以及引用它們的位置；
    - 逐份比對 `docs/adr/` 每份 ADR 與現在的代碼是否一致，逐條比對 `CONTEXT.md` 的術語是否仍對應到代碼。
12. `questions.md` —— 給我勾選的決策清單，每項選「保留／刪除／修改／不確定」，按影響大小排序。
    其中必須包含：
    - `docs/adr/` 每一份 ADR：列出它決定了什麼、代碼現況、選項「確認／推翻／不再適用」；
    - `CONTEXT.md` 每一個術語：選項「保留／併入 spec 或 docs 術語表／刪除」；
    - 每個平台綁定功能在其他平台上的去留：「全平台提供／僅部分平台／刪除」；
    - 每一類測試的去留；
    - 資料層是否更換（Isar 社群 fork vs 其他方案），及它對資料相容、全平台、重寫順序的影響；
    - i18n 保留哪些語言；
    - 發佈管道（GitHub Release／商店／sideload）各平台打算怎麼走。
    - （補充）下載、權限、帳號、「用登入狀態播放」相關的去留與行為決策。

階段一結束後停下，給我一頁摘要 + 最需要我先決定的 10 件事，等我回覆再繼續。

# 階段二：目標設計（我確認階段一後才開始）
先研究再設計，每個決定說明採用了誰的慣例：
- 架構：Flutter 官方 App Architecture 指南、Riverpod 官方建議
- 其他播放器：Spotube（音源插件、全平台）、MusicFree（插件系統）、LX Music（自訂源）、
  Listen1（多音源）、Harmony Music、Namida、Finamp
- 文檔：人類文檔按 Diátaxis 分類；AI 文檔按 AGENTS.md 慣例，只寫「打開程式碼查不到的東西」

每項給出方案、取捨、需要我決定的點：
1. 音源插件化 —— 單一註冊點宣告能力：搜尋、串流解析、歌單匯入、登入、收藏同步、遠端歌單編輯、
   排行／探索、電台直播、推薦／Mix、歌詞、下載。
   新增音源 = 新增一個目錄 + 註冊一行；UI 依能力自動出現入口，不支援就不顯示；
   UI 與 service 不得出現針對特定音源的分支。
   區分「可播放音源」「僅元資料／匯入音源（需匹配到可播放音源）」「歌詞源」，並統一匹配流程。
2. 統一錯誤模型 —— 一個 sealed 分類：網路、限流、需登入／憑證過期、風控驗證、地區／版權限制、
   找不到、解析失敗、不支援。
   回答：音源特有錯誤是否在音源自己的檔案中轉成統一型別？
   重試／退避／限流由誰負責（例如音源宣告策略、網路層統一執行）？
   哪些自動恢復、哪些提示使用者、哪些只記錄？
3. 統一 Toast —— 單一入口。開發者模式下錯誤 Toast 旁有「詳細」按鈕，
   可看錯誤類型、音源、請求摘要、stack trace，並可複製；所有錯誤同時進入可檢索的錯誤歷史。
   所有會展示或匯出請求內容的地方（Toast 詳細、Debug 頁、診斷包、log）
   經過同一個遮蔽函式，cookie、token、簽名 URL、API key 一律遮蔽。
4. Debug 頁 —— 做成正式工具而不是半成品：log 檢視與篩選、網路請求檢視、播放器／佇列即時狀態、
   資料庫檢視、音源健康檢查、快取管理、診斷包匯出。UI 使用與 App 其他部分相同的設計系統。
5. UI/UX —— 設計系統（間距、字級、色彩 token）、手機／平板／桌面的響應式規則、
   i18n 字串管理、無障礙與桌面鍵盤操作；桌面播放器頁給 2–3 個版面方案讓我選。
6. 資料相容 —— 現有資料庫、登入憑證、下載檔、備份檔要不要保留，以及 migration 策略；
   資料層是否更換，依我在 `questions.md` 的決定展開。
7. 重寫策略 —— 全新重寫 vs 逐步替換，給建議與理由；
   拆成可獨立驗證的里程碑，每個里程碑結束時 App 都能正常運作。
   說明分支與發版策略：重寫期間舊版的修正在哪裡做、使用者跳版升級時資料與憑證如何遷移。
8. 測試與閘門 —— 現有測試與 static-rule 哪些保留、哪些刪除；新架構需要哪些閘門。
   聯網策略分三層，給具體方案：
   - 預設測試零聯網，音源用錄製的真實回應（fixture）；本機直接 `flutter test` 也不得聯網；
   - 聯網冒煙測試每個音源每種能力最多一條，預設排除、需明確指定才跑，不擋 PR；
     評估是否用 CI 排程跑（注意機房 IP 可能被上游封鎖），失敗時如何通知；
   - 一個錄製 fixture 的工具，自動遮蔽 cookie、token、簽名 URL；
   - 音源插件化的共用契約測試：每個音源自動套用同一套測試，只需提供自己的 fixture；
   - 開發時減少真實請求的方法（例如開發者模式的假音源或回應快取），
     以及與 Debug 頁「音源健康檢查」共用檢查代碼的可能性。
9. 文檔結構 —— 給人看的（README、docs/）與給 AI 看的（AGENTS.md、Trellis spec）各放什麼，互不重複。
   保留 ADR 機制，三者分工如下：
   - `.trellis/spec/` 寫「這一層的程式碼怎麼寫」，不寫歷史；
   - Trellis task 的 `design.md` 寫「這次任務怎麼做」，隨任務歸檔；
   - `docs/adr/` 寫「跨模組決定的理由與被否決的方案」，長期保留。
   新架構的每個重大決定（音源插件、錯誤模型、平台策略、測試策略、資料層、重寫策略、資料相容等）
   各寫一份新 ADR。
10. 平台策略 —— 目標是全平台，但不要替還無法驗證的平台寫空實作：
    - 平台差異收進單一平台層，由平台宣告能力（托盤、全域快捷鍵、自動更新方式、桌面歌詞視窗、
      系統媒體控制實作、下載儲存方式、登入方式等），UI 與 service 依能力運作，
      平台層以外不得出現 `Platform.isXxx`；做法與音源插件化一致；
    - 選套件時，同等條件下優先選支援全平台的；列出目前依賴中需要替換的套件與替代方案；
    - 平台政策差異要明寫：例如 iOS 不能自行安裝更新、各平台的背景播放與儲存沙盒限制；
      以及各平台的發佈管道（非官方 API 與下載功能大概無法上架商店）；
    - 建議平台上線順序與驗證方式：Linux 可用虛擬機，建議儘早加入作為第三個平台驗證抽象；
      macOS／iOS 在沒有 Mac 時，用 GitHub Actions 的 macOS runner 做編譯檢查（不簽名）
      與 iOS 模擬器測試，取得 Mac／iPhone 後再做真機驗證與簽名；
    - 每個平台一個 child task，註明它需要的硬體或環境。
11. 下載與權限（補充）—— 下載作為音源能力之一如何納入插件化；佇列與續傳；
    下載路徑與儲存抽象如何配合平台層（各平台沙盒與權限差異）；
    權限管理統一入口：由平台宣告需要哪些權限，請求、被拒、引導使用者到系統設定的流程一致。
12. 帳號與認證（補充）—— 帳號作為音源能力之一；憑證存放、刷新、失效的統一流程；
    「哪些請求帶憑證」由一處宣告，不散落在各 service；登入狀態對能力的影響如何反映在 UI；
    登出與重設資料時的憑證清理，以及 migration 不得擅自改變使用者自己設定的值。
13. 播放核心（補充）—— 佇列、播放模式、播放狀態機、兩個音訊後端的抽象、串流解析與 URL 過期、
    錯誤恢復、系統媒體控制；電台／直播目前繞過 AudioController 的例外是否保留。
14. 音樂庫與同步（補充）—— 本地歌單與遠端歌單的關係與同步方向（誰覆蓋誰、衝突怎麼辦）；
    遠端歌單編輯寫回第三方平台前的確認機制；自動刷新規則；
    僅元資料音源（Spotify、QQ）匯入時的匹配流程與匹配失敗的處理。
15. 歌詞（補充）—— 歌詞源作為插件類別、自動匹配、AI 匹配（送往第三方的資料與開關）、
    桌面歌詞視窗在各平台的去留。
16. 背景任務（補充）—— 自動刷新、更新檢查、電台刷新、清理任務等統一由誰排程、如何取消、
    App 在背景或離線時的行為。
17. 快取與離線（補充）—— 圖片、串流 URL、歌詞、排行等快取的統一策略；沒有網路時 App 能做什麼。
18. 設定與日誌基礎設施（補充）—— 設定項的分組與存放；log 的分級、輸出位置、檔案輪替與保留，
    與 Debug 頁、診斷包、遮蔽函式的關係。

階段二的進行方式（補充）：階段二開始時先給出所有設計項目的依賴關係與建議順序（例如資料層 → 網路與帳號 →
音源插件與錯誤模型 → 播放核心 → 音樂庫與下載 → UI），我確認後再逐項用 trellis-brainstorm 展開，
不要一次展開所有項目。

# 階段三：Trellis 流程
- 檢查 `.trellis/`、`.claude/agents/`、`.claude/commands/`、`.claude/skills/`、`.agents/skills/`、hooks、`orca.yaml`
  與 AGENTS.md、docs/ 是否重疊或衝突，列出需要修改的地方。
- 移除 mattpocock skills 的殘留：刪除 `docs/agents/`，並刪除或改寫 AGENTS.md「Agent skills」段、
  `docs/README.md` 中對它們的引用；若「issue 用繁體中文撰寫」等慣例仍需要，搬一句到 AGENTS.md。
- 依我在 `questions.md` 的勾選處理 ADR 與術語：
  - 「推翻／不再適用」的 ADR 刪除；「確認」的保留，必要時按新架構重寫；
  - `CONTEXT.md` 的術語按勾選併入對應 spec 或 docs 術語表，全部處理完後刪除 `CONTEXT.md`；
  - 同步修改所有引用：`.trellis/spec/`（data、services、guides）、`.github/workflows/release.yml` 註解、
    AGENTS.md、docs/README.md；`.trellis/tasks/archive/` 是歷史紀錄，不改。
  - 修改後用 `git grep` 確認沒有指向已刪檔案或已刪 ADR 編號的引用。
- verify-on-device skill 與 AGENTS.md 的驗證表目前只涵蓋 Android emulator 與 Windows，
  規劃新平台加入時要如何擴充（Linux 虛擬機、macOS runner、iOS 模擬器），
  以及實機驗證時如何減少打真實 API（對應階段二第 8 項）。

# 重構過程的約束
- 可 review 性優先：每個 child task 產出一個 PR，大小控制在我能 review 的範圍，太大就拆；
  每個 PR 附 review 指南（改了什麼、為什麼、我該看哪幾個檔案、怎麼實際驗證）；
  沒有經我確認的 ADR 的設計，不進代碼。
- 功能凍結：重寫期間不加新功能，想到的記進 parent task 的待辦，不實作。
- 完成定義：`features.md` 中我勾「保留」的功能全部在新架構上跑通，
  且效能不低於階段一記錄的基準。
- 重寫期間不發布正式版本；舊版的緊急修正怎麼處理，在階段二的重寫策略中提出方案。
- 參考其他開源專案時只參考設計；要複製代碼，先確認授權相容並告訴我。

# Trellis 任務管理
- 建立 parent task `fmp-rewrite`，把這整份 prompt 原文存成它的 `prd.md`。
- 階段一建成它的第一個 child task `audit`（只寫 PRD，屬於輕量任務），然後開始執行。
- 之後每個里程碑、每個新平台各是 `fmp-rewrite` 下的一個 child task，
  規劃時用 `trellis-brainstorm` 與我逐項確認，各自有 prd／design／implement。

# 輸出要求
- 全程繁體中文，圖優先（架構圖、依賴圖、序列圖、狀態機圖）。
- 大量閱讀可以分派子代理並行處理，但結論由你彙整，並逐條附上證據。
````


### 1.1 第二輪（2026-11-06）

上一輪在 5.5 週後放棄。擁有者的評價：仍缺不少舊版有的功能（下載、歌詞、托盤、更新都沒做，VIP 標識被刻意丟掉），UI 也不及舊版。第二輪的方向：

- 所有目標平台一起開發：每個功能在同一個里程碑、同一張票裡，在全部目標平台做完並驗收。
- 第一版範圍要小。
- App 是載體，主要功能由音源插件完成，要支援 VIP 標識、操作遠端歌單等舊版已有的功能。
- UI 以舊版為底再優化，每個頁面先給設計稿確認。

## 2. 產品定位

### 2.1 本產品負責【決定】

多音源的搜尋與播放、本地歌單與匯入歌單、遠端寫入、帳號與會員狀態、歌詞、系統媒體控制與背景播放。

### 2.2 本產品不負責【決定】

上架 App Store 或 Google Play、影片播放、跨裝置雲端同步、多使用者、第三方插件來源（第一版）。

### 2.3 參考的成熟產品與採用的慣例

- 插件能力宣告：Spotube v6（功能與權限分開、遠端歌單寫入）、MusicFree（方法全部可選）。反例：LX Music 的自訂源只能解析網址，能力太窄。見 `docs/research/plugin-architectures.md`。
- 佇列與播放模式：Apple Music、Spotify；臨時播放沿用舊版。
- App 外殼與材質：Apple Music（iOS 26、macOS 26）的 Liquid Glass 用法：玻璃只用在浮在內容上的控制層，內容維持實心。
- 架構：Flutter 官方 App Architecture 指南；Riverpod 官方文件。
- 版面寬度分級：Material 3 的 compact、medium、expanded。
- 發版：Berth（tag 才跑完整閘門）；檢查指令：QIM 的 `xtask` 加 `.githooks`。

### 2.4 名稱【決定】

沿用 FMP。

## 3. 使用者與情境【決定】

擁有者本人為主，加上從 GitHub 下載的少數外部使用者。主要情境：手機通勤時聽、桌面工作時背景播放。

## 4. 平台範圍【決定】

- 第一版：iOS、macOS、Android、Windows。Linux 不在第一版。
- 每個功能在同一個里程碑、同一張票裡，在四個平台做完並驗收，不設「某某平台」里程碑。主力開發機是 Mac。
- 驗收方式：

| 平台 | 方式 |
| --- | --- |
| macOS | 本機實跑，`orca computer` 讀回畫面 |
| iOS | 模擬器，`orca emulator` |
| Android | 模擬器，`orca emulator-android` |
| Windows | SSH 到 `winpc`，以排程工作在桌面工作階段建置、測試、截圖傳回 |

- 里程碑驗收時由擁有者在各平台親手試用一次。不做實機驗收。

## 5. 音源與功能範圍【決定】

### 5.1 第一版的功能

1. 三音源搜尋與播放（含 B 站分 P）
2. 佇列、播放模式、臨時播放
3. 背景播放、系統媒體控制
4. 本地歌單（建立、排序、多選）
5. 匯入歌單與定時刷新
6. 登入（QR 與 WebView）、會員狀態
7. 曲目的存取等級標識（三音源）
8. 遠端寫入（建立歌單、加入曲目、移除曲目）
9. 歌詞：顯示、自動匹配、手動搜尋
10. 插件更新：插件頁手動檢查，列出新版本並經使用者確認才安裝，逐個確認，沒有「全部更新」；安裝前比對 SHA-256；新版要求的插件能力或網域變多時再確認一次。不做背景自動更新。
11. 匯入舊版 JSON 備份
12. 首頁：App 打開在首頁；近期熱門（三個音源的排行榜，不需登入）、繼續聽（正在播放與接下來）、最近更新的匯入歌單（擁有者 2026-11-11）

### 5.2 之後的里程碑（未排序）

下載與已下載頁、播放歷史（做了之後首頁加最近播放）、探索（排行榜已提前到第一版首頁）、B 站直播電台、YouTube Mix、Spotify 與 QQ 歌單匯入匹配、AI 歌詞匹配、桌面歌詞、托盤與全域快捷鍵與開機自啟、備份還原、應用內更新、Debug 頁、倍速與輸出裝置、取代舊版。

### 5.3 插件

- 音源與歌詞源都是插件，見 ADR 0038。第一版的插件：bilibili、youtube、netease、lrclib。
- 插件宣告插件能力，介面依插件能力出現入口；Dart 端不得有針對特定音源的分支。
- 插件只能連 manifest 宣告的網域，沒有檔案系統與 socket，只能用宿主給的 API。
- 錯誤以固定代碼回報，由宿主轉成錯誤分類（§13）。

### 5.4 存取等級與會員狀態

- 每首曲目有存取等級：免費、需會員、需付費、只有試聽；插件判斷不了就不顯示。搜尋結果、歌單、佇列、播放頁都顯示徽章。
- 帳號有會員狀態（等級、到期日），顯示在帳號頁；到期前 14 天起提示，已過期也提示；App 啟動時靜默檢查一次帳號。
- 插件列出可用音質，並標明哪些需要會員；播放時依偏好與會員狀態選最高可用。
- 只有試聽時照樣播放片段，播放列與播放頁明確標示「試聽」並提示一次；完全不能播時提示原因並跳下一首。

## 6. 播放【決定】

- 臨時播放照舊版：在搜尋結果、歌單詳情等處點一首歌，就在佇列之外播放它；播完或按上一首、下一首時，回到佇列原本那首，並依設定倒退若干秒（預設 10 秒）。連續臨時播放時，保留最早那個佇列位置。歌單的「播放全部」取代佇列。舊版行為見 `lib/services/audio/audio_provider.dart:609-640,1012-1060`。手機點一下、桌面雙擊或 ↩ 才臨時播放（桌面單擊是選取）。B 站多 P 點父列時，整組當成一首臨時播放，播完整組才回佇列。重啟後不保留臨時播放，回到佇列原本那首。
- 播放模式是兩個獨立的控制：隨機（開、關，真打亂）與循環（不循環、列表循環、單曲循環）。兩者可以同時開；慣例取自 Spotify、Apple Music 與舊版。
- 佇列畫面永遠是播放順序。開隨機時，正在播的那首移到最上方，其餘的歌打亂排在後面；摺線在正在播的那首下方，以上是播過的，以下是接下來的。
- 開關隨機不會改動原本的順序：關閉隨機時，佇列恢復原順序，從正在播的那首在原順序裡的位置繼續往下播。
- 隨機加列表循環時，整串播完後重新打亂再播一輪；只開隨機時，播完就停。
- 隨機時，「下一首播放」加入的歌一定是下一首；拖動排序直接改播放順序。
- 隨機時拖動過、或用「下一首播放」插進來的曲目，關掉隨機後排在正在播的那首後面，不回原位。用 × 移除正在播的那首時，直接接著播下一首。清空佇列要確認，清空後停止播放。
- 開啟佇列頁時自動捲到正在播的那首；點標頭的「佇列」標題隨時捲回去。
- 佇列與進度跨重啟保存，重啟後不自動播放；設定不提供開關。
- 依插件給的有效期，在串流過期前重新解析；預先解析下一首。
- 播放失敗時先降一級音質重試，再跳下一首；連續 3 首失敗就停止並提示。
- 音訊後端：宿主自己的後端介面，Android、iOS、macOS 用 just_audio，Windows 用 media_kit（理由見事實 K1）。系統媒體控制：Android 與 iOS 用 audio_service，Windows 用 `smtc_windows`，macOS 由 M0 實驗決定。Apple 平台的 YouTube 一律選 m4a/AAC（事實 M5）。
- 第一版不做：倍速、輸出裝置選擇、gapless 保證。

## 7. 音樂庫與同步【決定】

- 本地歌單可以任意編輯。匯入歌單是遠端歌單的唯讀鏡像，依刷新間隔刷新、以遠端為準，可以「複製成本地歌單」。
- 遠端寫入只對自己帳號底下的遠端歌單；成功後刷新對應的匯入歌單。
- 寫入前的確認由宿主統一處理，插件無法繞過：移除曲目每次都確認，列出歌單名稱、曲目與封面；建立與加入以加入歌單對話框作為確認。對話框列出本地歌單，也列出選取曲目所屬音源、自己帳號底下的遠端歌單（各音源預設收起，點開才載入）；取消勾選遠端歌單只先標「將移出」，按主按鈕時一次確認所有遠端移出。失敗時本機不改動，並提示原因。
- 從本地歌單移除不確認，改用提示的「復原」。刪除匯入歌單只刪 App 裡的鏡像，不動遠端歌單。

## 8. 帳號與登入【決定】

- Bilibili、網易雲：QR 與 WebView 兩種登入，四個平台都有。
- YouTube：WebView 登入；某平台行不通時改成貼上 cookie。
- WebView 用 `flutter_inappwebview` 6.1.5（穩定版，事實 R1）。
- 憑證存在 `flutter_secure_storage` 11.2.0：Android `resetOnError: false`；iOS `accessibility: first_unlock`；macOS `usesDataProtectionKeychain: false`。macOS 的 ad-hoc 版每次更新後會跳一次鑰匙圈授權（事實 M2），第一版接受。

## 9. 下載與離線【決定】

- 第一版不做下載。
- 離線時，音樂庫、佇列、設定照常可用；播放、搜尋、刷新顯示網路錯誤；已解析且未過期的串流照常播放。

## 10. 歌詞【決定】

- 歌詞來源：netease 插件與 lrclib 插件。
- 功能：逐行 LRC 同步、有翻譯時顯示在原文下一行（顯示模式三選一：原文＋翻譯、只顯示原文、優先顯示翻譯）、手動調整偏移、依標題與歌手與時長自動匹配、手動搜尋。
- 之後再做：逐字歌詞、羅馬音、AI 匹配、桌面歌詞、QQ 歌詞。

## 11. 介面【決定】

- 以舊版 UI 為底再優化：頁面地圖、資訊架構、各頁的功能入口照舊版；設計系統（色彩、字級、間距、圓角、材質）重新訂定。M1 開工前，第一版每個頁面都有經擁有者確認的設計稿。
- 材質（擁有者 2026-11-11，慣例見 §2.3）：玻璃只用在浮在內容上的控制層：導覽、迷你播放器、桌面側欄與播放膠囊、頂列按鈕、多選動作列、選單、sheet、對話框、提示。曲目列、歌單卡、設定列表、表格、桌面詳情面板、播放頁桌面右欄是實心內容。玻璃分三級，各平台做到哪一級由 M0 實驗定（§17）。
- 色彩：預設不用強調色，設定的「外觀」可選堇紫、靛藍、青綠。封面色只用在播放頁背景；音源色由插件宣告。
- 外殼：手機底部是迷你播放器，下面是導覽膠囊加上獨立的搜尋圓鈕，捲動時不收合；進搜尋時導覽收成左邊圓鈕，搜尋圓鈕展開成欄位。桌面是左側浮動玻璃側欄（搜尋欄、導覽、歌單清單、設定）、右側實心詳情面板（可收起）、底部播放膠囊。迷你播放器與播放膠囊用書脊式進度：膠囊本身就是進度條。
- 操作形式：手機上一首歌的「更多」用底部 sheet、確認用置中對話框；平板的「更多」用從按鈕長出的選單；桌面用右鍵選單與置中對話框。播放頁手機是「佇列 ← 封面 → 歌詞」三個畫面左右滑，打開在封面，有頁面點點，封面不能滑動切歌；桌面在頂列右端切換歌詞與佇列；頂列中間寫播放來源。
- 設計細節以 `docs/design/DESIGN.md` 為準（含〈9〉做稿時定的 1–36 條）；和本檔衝突時以本檔為準。
- 設計稿是靜態 HTML，每頁做手機、中寬度（平板、窄桌面視窗）與桌面三種寬度、深淺色，放在 `docs/design/`；有爭議的地方給 A／B 方案。實作照定稿切版。
- 寬度分級（擁有者 2026-11-11）：窄（小於 600，手機，固定直向）、中（600–1199，平板與縮小的桌面視窗，左側玻璃細欄）、寬（1200 以上，桌面，側欄＋常駐詳情面板）。桌面視窗最小 720×560。密度跟裝置走：iOS、Android 用觸控密度，macOS、Windows 用滑鼠密度。細節在 `docs/design/DESIGN.md` §5.3。
- 第一版的頁面：App 外殼（導覽、迷你播放器）、首頁、搜尋與結果、音樂庫、歌單詳情（本地、匯入）、佇列、全螢幕播放頁（含歌詞）、加入歌單對話框、帳號與登入、插件管理、設定、匯入舊版備份。導覽是首頁、音樂庫、佇列、設定四項，加上獨立的搜尋鈕（擁有者 2026-11-11）。
- 語言：zh-TW 為主，加上 zh-CN、en，用 slang 管理。

## 12. 舊版的資料與升級【決定】

- 正式身分沿用 `com.personal.fmp`（含 Android 的簽名金鑰）；開發與試用一律用 `com.personal.fmp.dev`，可以和舊版並存。
- 資料搬遷靠匯入舊版 JSON 備份（包含歌單與匯入來源、刷新間隔、曲目、播放與搜尋歷史、電台、設定、歌詞配對；不含憑證與下載檔，見 `lib/services/backup/backup_data.dart`）。登入要重新做一次。不讀舊版的 Isar。
- 版號從 `2.0.0` 起算，tag 用 `app-v*`。取代舊版之前，新版的 release 一律是 prerelease：舊版 v1.11.0 的自動更新讀 `releases/latest`（`lib/services/update/update_service.dart:397`），這支 API 不回傳 prerelease。
- 取代舊版的方式見〈待決〉。

## 13. 錯誤、log 與診斷【決定】

- 錯誤分類（sealed）：網路、限流、需登入、憑證失效、需驗證、不可用（原因：地區、版權、需會員、只有試聽）、找不到、解析失敗、不支援。重試只在網路層做一層。UI 依類別決定顯示提示、要求登入或只記錄。
- 單一 Toast 入口：錯誤依類別給文字與動作（例如「登入」「重試」），也用於成功提示與「復原」。需驗證時暫停播放並提示，「去驗證」打開音源給的驗證頁，驗證完自動重試那一首。
- 單一 log 門面，寫檔並輪替（2MB × 3），release 版保留 info 級。
- 單一遮蔽函式，log 與匯出都經過它。設定頁有「匯出診斷」。
- 之後再做：Debug 頁、開發者模式的錯誤詳細。

## 14. 隱私與安全【決定】

- 會送到第三方的資料只有一項：曲名、歌手、時長送到 lrclib。第一版沒有 AI 功能。
- 憑證只存在 secure storage，不進 log、診斷包與備份。
- 插件只能連宣告的網域（§5.3）。
- 公開 repo 與擁有者帳號的規則見 `AGENTS.md`。

## 15. 效能與品質指標【決定】

- profile build，跑 5 次取中位數，只在里程碑驗收時量。
- Android 與 Windows 不比舊版差（`docs/audit/perf-baseline.md`）：
  - 冷啟動到第一幀：Android 1239 ms、Windows 1731 ms。
  - 首頁穩定後的記憶體：Android PSS 179 MB、Windows Working Set 300 MB。
  - 1000 首以上的長列表捲動不掉幀（舊版 Windows 佇列 1195 首，0 幀超過 16.7 ms）。
- macOS 與 iOS 以第一次量到的數字為基準。
- 匯入大歌單時要顯示進度。

## 16. 發佈與更新【決定】

| 平台 | 安裝檔 | 簽章 |
| --- | --- | --- |
| Android | 依 ABI 分開的 APK | 沿用舊版的簽名金鑰 |
| Windows | Inno Setup 安裝檔加免安裝 zip | 不簽 |
| macOS | `.app` 的 zip | ad-hoc；擁有者自己的機器用本機的 Apple Development 憑證建置 |
| iOS | 未簽章的 IPA | 用 SideStore 或 AltStore 以免費 Apple ID 自簽 |

- 沒有付費的 Apple Developer 帳號。
- 由 `app-v*` tag 觸發 `app-release.yml`，在 GitHub runner 上跑完整閘門，綠了才發佈。
- 第一版沒有應用內更新；插件更新見 §5.1。

## 17. 待決

- **取代舊版的方式**：舊版使用者怎麼升上來（舊版的自動更新、資料搬遷、要不要讀 Isar）。卡在新版功能還沒齊全；到「取代舊版」的里程碑由擁有者決定。
- **macOS 的 Now Playing 接法**：事實 R4 顯示 audio_service 在 macOS 不完整。由 M0 實驗決定。
- **Windows 經 SSH 截圖傳回**：M0 票 01 已實測，做法見 plan §2〈Windows（`winpc`）〉。
- **玻璃的 Flutter 實作**：見事實 K10。由 M0 實驗（票 05b）決定：重驗 K10，在四平台實測已發佈的官方或社群套件，以及用 `BackdropFilter` 自己做，各平台做到哪一級。不論用哪種做法，都包在同一個玻璃元件後面，日後替換只改一處。

## 18. 查證過的事實

外部事實（音源 API 行為、套件與平台框架的能力、授權），每條附來源。可信度：「舊版程式碼」是舊版程式碼本身體現了這個做法（多數註解自稱實測）；「上一版文件」是只有上一輪的 ADR、research 或 references，標【待重驗】，用到它的票要重驗，驗過拿掉標記，對不上就改寫。`legacy:` 指根目錄舊版，`archive:` 指 tag `archive/trellis-rewrite-20261106`。驗證工具本身的怪癖不放這裡，在 plan〈平台〉。

### 18.1 Bilibili

- **F1** 匿名請求 `/x/web-interface/view` 回 HTTP 412；`/x/web-interface/wbi/view` 與 `/x/player/pagelist` 回 200（2026-09-15）。出處：`legacy:lib/data/sources/bilibili_source.dart:77-83`。可信度：舊版程式碼。
- **F2** 風控碼 `-352`、`-412`、`-509`、`-799` 與 HTTP 412、429 要當限流退避，換 buvid 指紋救不回來。節流針對匿名身分：2026-09-22 同時間窗匿名 23/40 被擋、帶登入 0/40；`curl`、`okhttp` 這類 UA 必被擋。出處：`legacy:lib/data/sources/bilibili_source.dart:923-940`、`legacy:lib/data/sources/bilibili_exception.dart:15-24`。可信度：舊版程式碼。
- **F3** 認證失敗是 HTTP 200 加 JSON `code: -101/-111`，不是 401；cookie 刷新用 RSA-OAEP，刷新後仍 `-101` 才是憑證真的失效；QR 輪詢回 `86038` 表示過期。出處：`legacy:lib/services/account/bilibili_auth_interceptor.dart:10-14,78`。可信度：舊版程式碼。
- **F4** 媒體與圖片 CDN 只需要 Referer（不帶結尾斜線）；API 要 Referer（帶斜線）加 Origin；媒體請求不帶憑證。出處：`legacy:lib/data/sources/source_http_policy.dart:45,73-84,100-104`。可信度：舊版程式碼。
- **F5** 串流網址的有效期寫在 `deadline` 參數（unix 秒），實測約 7178 秒；要讀參數，不要寫死。出處：`legacy:lib/data/sources/bilibili_source.dart:429-445`。可信度：舊版程式碼。
- **F6** `/x/player/playurl` 的 `fnval=16` 回 DASH 音訊軌（m4a/AAC），`fnval=0` 回 FLV；點播沒有 HLS。Apple 平台的 AVPlayer 不播 FLV。出處：`legacy:lib/data/sources/bilibili_source.dart:297-426`。可信度：舊版程式碼。
- **F7** 直播：mpv 開流後約 50 秒內位置與時長都是 0；Apple 平台要改用 h5 的 HLS（aac）。出處：`legacy:lib/services/audio/media_kit_audio_service.dart:555-565`（Windows，舊版程式碼）；`archive:docs/adr/0036` §決定 7（Apple，上一版文件【待重驗】）。

### 18.2 YouTube

- **F8**【待重驗】2026-08-26 起，ANDROID_VR client 不帶 PO token 的 googlevideo 網址只給約前 60 秒，之後 Range 一律 403；2026-09-30 實測 VISIONOS、IOS client 給完整長度的明文網址，不需要 PO token。client 每隔幾個月會變，解析串流要準備候選 client 序列。出處：archive 的 `youtubejs-probe.md`〈哪個 client 能用〉。可信度：上一版文件。
- **F9** 帶登入的 InnerTube `/player` 要用 WEB client，並帶 Origin 與 Referer 才通過 SAPISIDHASH 驗證；必要的 cookie 是 `SAPISID`、`__Secure-1PSID`、`__Secure-3PSID`。出處：`legacy:lib/data/sources/youtube_source.dart:60-70,407-410`。可信度：舊版程式碼。
- **F10** 每種串流類型先匿名試，失敗再帶登入重試同一類型；先把所有類型都匿名試完，會拿到含影像、位元率 3–5 倍的串流。出處：`legacy:lib/data/sources/youtube_source.dart:338-352`。可信度：舊版程式碼。
- **F11** googlevideo 網址約 1 小時過期；libmpv 分段請求之間連線閒置會被 CDN 切斷（WSAECONNRESET）。出處：`legacy:lib/data/sources/youtube_source.dart:52-54`、`legacy:lib/services/audio/media_kit_audio_service.dart:195-232`。可信度：舊版程式碼。
- **F12**【待重驗】Google 擋嵌入式 WebView 登入：Android 要從 UA 拿掉 `; wv`，iOS 的 WKWebView 要補成 Safari 形狀的 UA；Windows WebView2 的預設 UA 可以登入。登入完成看 cookie，不看網址；登出要清掉 WebView 的全部 cookie（Google 會寫地區網域與 CHIPS 分區 cookie）。出處：archive 的 `r1-youtube-login.md`、`archive:docs/adr/0029` §決定 9、11、`archive:docs/adr/0037` §決定 11。可信度：上一版文件。
- **F13**【待重驗】Windows 的 WebView 登入偶爾卡在 `accounts.youtube.com/accounts/SetSID` 或程序消失，原因不明，重開 App 再登入就好。出處：archive 的 `r1-youtube-login.md`〈Windows 跳轉時的偶發失敗〉。可信度：上一版文件。

### 18.3 網易雲音樂

- **F14** 播放串流走 eapi `/eapi/song/enhance/player/url/v1`，有效期看回應的 `expi`，實測約 1200 秒。出處：`legacy:lib/data/sources/netease_source.dart:40,69-70`。可信度：舊版程式碼。
- **F15** VIP 看 `fee`（1 或 4）；`flag & 4` 不是 VIP 標記（歌曲 139774 是 `flag=6`，匿名就拿到 320 kbps）。`cloudsearch` 的 `privilege.fee` 對 VIP 歌可能回 0，以 `song.fee` 為準。出處：`legacy:lib/data/sources/netease_source.dart:697-698,849-940`。可信度：舊版程式碼。
- **F16** 未登入時的失敗長相是 `code=404` 或 `301`、`fee=0`、`url=null`，要提示登入而不是引導付費（#87）。出處：`legacy:lib/data/sources/netease_source.dart:849-940`。可信度：舊版程式碼。
- **F17** 試聽片段（`freeTrialInfo != null`）會被當成完整歌曲回傳；API 在什麼情況下回試聽網址還沒實測過。出處：`legacy:lib/data/sources/netease_source.dart:139-150`。可信度：舊版程式碼（觸發條件未驗）。
- **F18** eapi 回的串流網址是 `http://`：Android 要 `usesCleartextTraffic`，Apple 要 `NSAllowsArbitraryLoadsForMedia`。出處：`legacy:android/app/src/main/AndroidManifest.xml:33-40`。可信度：舊版程式碼。
- **F19**【待重驗】QR 登入走 weapi（兩層 AES-128-CBC 加不帶 padding 的 RSA），帶固定的匿名 cookie 偽裝 Windows 客戶端；eapi、weapi 兩套加密並存；搜尋用明文 `/api/*`。出處：`docs/audit/accounts-network.md`。可信度：上一版文件。

### 18.4 Android

- **A1** App 自動備份會還原 shared preferences，但 Keystore 金鑰不會跟著還原，secure storage 解不開還原的憑證；設 `allowBackup="false"`。出處：`legacy:android/app/src/main/AndroidManifest.xml:26-31`（issue #35）。可信度：舊版程式碼。
- **A2** `MANAGE_EXTERNAL_STORAGE` 加裸路徑不能上 Google Play；`permission_handler_windows` 一註冊就訂閱位置事件，Windows 會顯示 App 正在使用位置。出處：`legacy:lib/services/platform/storage_permission_service.dart:18-24`。可信度：舊版程式碼。
- **A3** AGP 9 下，`package_info_plus` 9.0.1 需要 `android.builtInKotlin=false`；`file_picker` 11.0.3 要手動套 KGP。出處：`legacy:android/gradle.properties:3-6`、`legacy:android/build.gradle.kts:18-26`。可信度：舊版程式碼。
- **A4** AGP 9 移除了 `proguard-android.txt`，`flutter_inappwebview` 6.1.5 帶進來的 `flutter_inappwebview_android` 1.1.3 在 `build.gradle` 還在用：AGP 9.1.0 下 debug 與 release 都在 Gradle 設定階段失敗（`getDefaultProguardFile('proguard-android.txt')` is no longer supported）。App 的 `gradle.properties` 加暫時旗標 `android.r8.proguardAndroidTxt.disallowed=false` 後，debug、release（R8）都建得過、開得了網頁。上游 #2852 仍開著（2026-11-11）。出處：M0 票 04（`scripts/experiments/inappwebview/`）；`legacy:android/gradle.properties:9-12`。可信度：2026-11-11 實測。
- **A5**【待重驗】targetSdk 36 在 Android 16 預設開 predictive back：從通知等入口開啟的 task 按返回鍵會被 finish；要覆寫 `setFrameworkHandlesBack(true)` 與 `popSystemNavigator`。出處：commit `b2421e88`。可信度：上一版文件。
- **A6**【待重驗】`audio_service` 0.18.19 把真正的媒體鍵 PLAY、PAUSE 當成切換，暫停時按暫停鍵反而開始播放。出處：commit `fb75a020`。可信度：上一版文件。
- **A7**【待重驗】來電中斷後要在背景續播，會撞上 Android 12+ 的前景服務限制，中斷期間要回報 `playing` 加 `buffering`；`AUDIOFOCUS_LOSS` 不會送結束事件。出處：commits `a737e41c`、`2bfce093`。可信度：上一版文件。

### 18.5 Windows

- **W1** Material `Slider` 與 hover 時的 `Tooltip` 會弄壞 Windows 的無障礙樹，之後 Narrator 讀不到內容（flutter/flutter#182444，未修）；`Slider` 要包 `Overlay.wrap`。出處：`legacy:lib/ui/widgets/controls/scoped_slider.dart`、`docs/troubleshooting.md`。可信度：舊版程式碼。
- **W2** `runApp()` 之前的例外會變成「雙擊後什麼都沒發生」，要 try/catch 並顯示錯誤畫面。出處：`legacy:lib/main.dart:46-62`（issue #37）。可信度：舊版程式碼。
- **W3** `media_kit_libs_windows_audio` 1.0.9 帶的是 2023-09-24 的 libmpv（mpv 0.36、FFmpeg 6.0），pub 上沒有更新版（2026-11-06 查）；同一條串流 Android 能播、Windows 不能時先懷疑它。出處：`docs/troubleshooting.md`、`docs/research/audio-webview-2026-11.md`。可信度：舊版文件加 2026-11-06 研究。
- **W4** media_kit 的 `errorController` 不轉發 `ao` 開頭的錯誤（音訊裝置失敗），要另聽 log；長度為零的串流不報錯、一直 buffering，要有看門狗。出處：`legacy:lib/services/audio/media_kit_audio_service.dart:384-392`、`legacy:lib/services/audio/buffer_starvation_watchdog.dart:11-14`。可信度：舊版程式碼。
- **W5** media_kit 在 Windows 上同時 dispose 多個 player 會原生 crash（media-kit #1472）。出處：`docs/research/audio-webview-2026-11.md`。可信度：2026-11-06 研究。
- **W6**【待重驗】`smtc_windows` 的限制：收不到 seek 請求；時間軸不會自己前進，要每約 5 秒重推位置；讀不到 `file:///` 的封面，要給 https；`updateMetadata` 只設定非 null 的欄位，換歌時要先清空。出處：`legacy:lib/services/audio/now_playing_publisher.dart:283-284`、`archive:app/AGENTS.md`〈Windows（SMTC…）〉。可信度：上一版文件。
- **W7**【待重驗】`smtc_windows` 每次建置都從原始碼編 Rust，Windows 要裝 rustup；`flutter_rust_bridge` 要釘在和它 Rust 端相同的版本（=2.11.1）。出處：`docs/building.md:21,170`、commit `b7ab8de0`。可信度：上一版文件。
- **W8** `flutter_inappwebview_windows` 0.6.0（6.1.5 帶進來的）在 VS 2026（MSVC 14.51.36231）不加設定時，插件編譯報 `error C2338`（STL1011：`<experimental/coroutine>` 已棄用），要在 App 的 `windows/CMakeLists.txt` 對 `flutter_inappwebview_windows_plugin` 加 `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`。`/FS`（防多個編譯行程同時寫同一個 PDB 的 C1041）沒重現出需要：只加 define 的乾淨建置 3 次成功、沒出現 C1041，插件的 CMake 也沒開 `/MP`；留著當保險，VS 2022 也無害。繁中 Windows（cp950）下插件只報 C4819 警告：插件用自己的標準設定、刻意不開 `/WX`，所以不需要 `/utf-8`（舊版 `windows/` 也沒加）。上游 PR #2869 仍開著（2026-11-11）。出處：M0 票 04（`scripts/experiments/inappwebview/` 的 README〈W8〉，11 次建置的結果）；`flutter_inappwebview_windows-0.6.0/windows/CMakeLists.txt`；`legacy:windows/CMakeLists.txt:60-73`。可信度：2026-11-11 在 `winpc` 實測。
- **W9**【待重驗】`flutter_secure_storage_windows` 把所有鍵值用 DPAPI 存成單一 `flutter_secure_storage.dat`，解不開或 JSON 壞掉就整個刪掉；鍵名只能用小寫英數、`.`、`-`。出處：`archive:docs/adr/0029` §決定 5 更正。可信度：上一版文件。
- **W10**【待重驗】`desktop_multi_window` 的子視窗 engine 不能註冊 `tray_manager`、`hotkey_manager`、`window_manager`（它們用全域 static channel）。出處：`docs/audit/platforms.md` §3.7。可信度：上一版文件。

### 18.6 macOS

- **M1**【待重驗】ad-hoc 簽章下，`flutter_secure_storage` 的預設設定回 `-34018`；加了 `keychain-access-groups` 卻沒有 provisioning profile，App 一啟動就被 AMFI 殺掉。`usesDataProtectionKeychain: false` 可用，但 `readAll` 回 `-50`。出處：`archive:docs/adr/0036` §決定 3。可信度：上一版文件。
- **M2**【待重驗】登入 keychain 的授權依簽章分區：ad-hoc 與自簽憑證每次重建或更新都會跳授權視窗，只有 Apple 發的憑證（依 Team ID 分區）不會。出處：`archive:docs/adr/0036` §決定 3 更正、commits `bb2419d8`、`ae40e004`。可信度：上一版文件。
- **M3**【待重驗】開了 App Sandbox：子行程寫不了 `/Applications`；用 `open` 重啟會丟掉命令列參數；WKWebView 與 AVPlayer 缺 `network.client` 時靜默失敗。出處：`archive:docs/adr/0036` §決定 2。可信度：上一版文件。
- **M4**【待重驗】media_kit 的 Apple 版原生庫停在 2023-09，而且在 Apple 平台不接 Now Playing。出處：`archive:docs/adr/0018`〈考慮過的選項〉。可信度：上一版文件。
- **M5**【待重驗】AVPlayer（iOS 也一樣）：不播 WebM/Opus（iOS 回 `-11828`）與 FLV；`http://` 網域被 ATS 擋，要 `NSAllowsArbitraryLoadsForMedia`；`.m4s` 回 `application/octet-stream` 會打不開，`audio/mp4` 才行；自訂 header 要靠未公開的 `AVURLAssetHTTPHeaderFieldsKey`。真實 B 站、YouTube CDN 回的 Content-Type 沒驗過。出處：`archive:docs/adr/0036` §決定 7、`archive:docs/adr/0037` §決定 4、7。可信度：上一版文件。
- **M6**【待重驗】`window_manager` 已停止維護：macOS Tahoe 上點不到視窗頂端的按鈕（#565，closed NOT_PLANNED）；`hide()` 兩次後從 Dock 叫不回（#501）；隱藏標題列後量到的標題區高度是 0。出處：`archive:docs/adr/0036` §決定 6。可信度：上一版文件。
- **M7**【待重驗】單一實例要靠 Info.plist 的 `LSMultipleInstancesProhibited`；點 Dock 叫回視窗要自己實作 `applicationShouldHandleReopen`，`FlutterAppDelegate` 沒實作它。出處：`archive:docs/adr/0036` §決定 4。可信度：上一版文件。
- **M8** 穩定版 6.1.5 帶進來的 `flutter_inappwebview_macos` 1.1.2 在 Xcode 27.2 不加任何設定就建得過；沙盒 App 有 `com.apple.security.network.client`（事實 M3，`flutter create` 的範本沒有）就開得了網頁。Xcode 27.1 沒試（本機已更新）。上一輪用的是 1.2.0-beta.3，它在 Xcode 26.6 建不過的紀錄只適用 beta。出處：M0 票 04（`scripts/experiments/inappwebview/`）；`archive:docs/adr/0036` §決定 9。可信度：2026-11-11 實測。

### 18.7 iOS

- **I1**【待重驗】Info.plist 沒有 `UIBackgroundModes: [audio]` 的話，App 一進背景，Dart 與 JS 就一起被凍結；這個 key 免費帳號也能用。出處：`archive:docs/adr/0037` §決定 4。可信度：上一版文件。
- **I2**【待重驗】`audio_session` 在 iOS 把每次中斷開始都報成 `unknown`；要等結束事件帶 `shouldResume` 才續播；別的 App 開始播放時只發開始、不發結束。just_audio 0.10.6 的 `handleInterruptions` 在 duck 結束時把音量乘 2，所以中斷要自己處理。出處：commit `f6b07480`、`archive:docs/adr/0037` §決定 8。可信度：上一版文件。
- **I3**【待重驗】secure storage 在 iOS 預設 `unlocked`，鎖屏時讀不到（`-25308`）；解除安裝後 keychain 項目還在；換一個 Team 重簽後讀不到。出處：`archive:docs/adr/0037` §決定 6。可信度：上一版文件。
- **I4**【待重驗】AVPlayer 預載失敗時會吞掉錯誤，交接後才把壞項目報成 ready、時長 0，所以時長 0 要當成沒載入；一個卡住的項目會凍結之後所有的開檔；跳到已預載的下一首要用 seek，不要重開。出處：commits `49eb674a`、`ed1bc889`、`6c5d681b`。可信度：上一版文件。
- **I5**【待重驗】`audio_service` 0.18.19 在 iOS 不設 `MPNowPlayingInfoCenter.playbackState`（上游 #1139）。出處：`archive:docs/adr/0037` §決定 9。可信度：上一版文件。
- **I6**【待重驗】iOS 上 Dart 讀不到環境變數與 `main()` 參數，`--dart-entrypoint-args` 只支援桌面，開發用的切換只能靠 `--dart-define`。出處：`archive:docs/adr/0037` §決定 12。可信度：上一版文件。
- **I7**【待重驗】免費 Apple ID：描述檔 7 天到期；最多 10 個 App ID、3 台裝置；`DEVELOPMENT_TEAM` 不能寫進 pbxproj；`flutter build ipa --no-codesign` 只產出 `.xcarchive`，IPA 要自己把 `Payload/Runner.app` 壓成 zip。出處：`archive:docs/adr/0037` §決定 1、2。可信度：上一版文件。
- **I8**【待重驗】iPad 的分享表要給 `sharePositionOrigin` 錨點；只有桌面版的套件在 iOS 呼叫會拋 `MissingPluginException`。出處：`archive:docs/adr/0037` §決定 12、14。可信度：上一版文件。

### 18.8 套件

- **K1** just_audio 0.10.6 只支援 Android、iOS、macOS、web；`audio_session` 在 Windows 的 `setActive` 什麼都不做；`just_audio_windows` 不支援 request header；`just_audio_media_kit` 的代理對純音訊串流有相容問題（舊版因此拆回兩個後端）。出處：`docs/adr/0003`（commits `7fdec08e`、`2e73d1b8`、`6d39d15c`）。可信度：舊版程式碼。
- **K2** just_audio 要用 `setAudioSources` 才能在播放中追加下一首做 gapless；換回 `setAudioSource` 不報錯，只是不再 gapless。出處：`legacy:lib/services/audio/just_audio_service.dart:655-667`。可信度：舊版程式碼。
- **K3** ExoPlayer 把幾乎所有網路問題都壓成 `code=0, Source error`；Android 背景播放會漏掉 completed 事件，要用位置檢查補上。出處：`legacy:lib/services/audio/playback_end_reason_rules.dart:77,102`。可信度：舊版程式碼。
- **K4** media_kit 在 Windows：用 `Media.httpHeaders` 加 `on_load` hook 帶 header；`vid=no` 可省 200–400 MB；`prefetch-playlist=yes` 才會預載；先判斷 `buffering` 再判斷 `playing`。出處：`legacy:lib/services/audio/media_kit_audio_service.dart:190-250`。可信度：舊版程式碼。
- **K5** Riverpod 3 預設自動重試失敗的 provider（10 次、約 38 秒），連 `UnmountedRefException` 也會重試，要全域關掉。出處：`legacy:lib/main.dart:263-267`。可信度：舊版程式碼。
- **K6**【待重驗】`flutter_secure_storage` 跨大版本升級會讀不出舊憑證；Android 預設 `resetOnError: true` 要關掉。出處：`legacy:pubspec.yaml:68-72`、`archive:docs/adr/0029` §決定 5。可信度：上一版文件。
- **K7** `flutter_js` 0.8.7：`getJavascriptRuntime()` 在 iOS、macOS 回 JavaScriptCore，Android、Windows 回 QuickJS 2021-03-27；Apple 版的 podspec 只連 JavaScriptCore，要用 QuickJS 得自己把 android-js-runtimes 0.3.6 的原始碼編進 App。`QuickJsRuntime2` 的 `timeout` 中斷不了同步迴圈（橋接 `quickjs_runtime.cpp` 的 interrupt handler 比較的 `op->start` 從沒被設值），放進背景 isolate 再 `Isolate.kill` 也停不了原生執行緒（行程 CPU 持續滿載）；Android、Windows 附的二進位沒有 `jsSetMemoryLimit`，設 `memoryLimit` 會拋符號找不到；Android 在 AGP 9 下要 `kotlin.jvm.target.validation.mode=warning` 才建得過（上游 #191）。出處：M0 票 03（`scripts/experiments/js-engine/`）。可信度：2026-11-11 四平台實測。
- **K8** `flutter_inappwebview` 6.1.5（2024-10-08）仍是最後一個穩定版，之後只有 6.2.0-beta.1–3（2026-11-11 查）。從 beta 退回 stable 時，把 pubspec 改回 6.1.5 再 `pub get` 只會退主套件：`_android`、`_ios`、`_macos`、`_web` 留在 1.2.0-beta.3，`_platform_interface` 留在 1.4.0-beta.3，建置在 Dart 編譯失敗（`InAppBrowser` is missing implementations…）。`flutter pub upgrade flutter_inappwebview` 清不掉，要 `flutter pub upgrade --unlock-transitive flutter_inappwebview`。出處：M0 票 04（`scripts/experiments/inappwebview/lockfile-repro.sh`）；https://pub.dev/packages/flutter_inappwebview/versions 。可信度：2026-11-11 實測。
- **K9**【待重驗】桌面套件的維護狀態：`window_manager` 在 2026-09 批次關閉 issue；`hotkey_manager` 0.2.3 最後發佈在 2024-05；`qr_flutter` 4.1.0 停在 2023。出處：`docs/audit/platforms.md` §4.1。可信度：上一版文件。
- **K10** Flutter 官方的 Liquid Glass 還沒發佈。flutter/packages 把社群的 `liquid_glass_widgets`、`liquid_glass_renderer` 改編進 `cupertino_ui`（PR #13162、#13163、#13344、#13453、#13454，2026-10-20 至 11-06 合併），但合進的是 `liquid_glass` 功能分支，不在 main；pub 上 `cupertino_ui` 的 changelog 到 1.1.5（2026-11-03）都沒有 glass；追蹤 issue flutter/flutter#170310 仍開著。分支裡的 `doc/liquid_glass/PLATFORM_SUPPORT.md`：品質分三級，premium 是折射 shader，需要 Impeller，不適合捲動列表；standard 是輕量 shader，全平台可用；minimal 只用 `BackdropFilter`。平台分級：iOS、Android（Impeller）是主力，macOS 是 Supported，Windows 是 Partial（文件寫走 Skia，最高只到 standard）。出處：上述 PR；flutter/packages `liquid_glass` 分支的 `packages/cupertino_ui/doc/liquid_glass/PLATFORM_SUPPORT.md`；https://pub.dev/packages/cupertino_ui/changelog。可信度：2026-11-08 查證。
- **K11** `fjs` 3.3.2（2026-09-30）：四平台都是 rquickjs 包的 QuickJS-NG；所有引擎共用一個只有 2 條執行緒的 tokio runtime（寫死），2 個引擎卡在同步迴圈時其他引擎都無法執行，`close()` 後恢復。Android、Windows 由 Cargokit 從 Rust 原始碼編（Rust ≥ 1.95；Windows 的 rustup default host 是 gnu 時缺 `dlltool.exe` 而失敗，要 msvc）；iOS、macOS 走 SwiftPM，用套件附的預編譯 xcframework。中斷只有 `engine.close()`：進行中的 eval 以 `CANCELLED_ERROR` 結束，await 之後與 timer 回呼裡的迴圈也會停（timer 那種 `close()` 會拋出被中斷的背景錯誤），原生迴圈實測停止，引擎不能再用。記憶體上限是 `JsEngineRuntimeOptions(memoryLimit:)`，超過時 JS 拿到可捕捉的 out of memory。`eval` 會等 Promise；宿主函式只有單一 bridge（JS 端 `fjs.bridge_call(value)` 回 Promise）。JS 跑在 Rust 執行緒，Dart 端是 async，不卡主 isolate。內建 llrt 的 fs、net、child_process、fetch 等模組，建立引擎時指名才開；README 寫明記憶體與堆疊上限不是防惡意程式碼的沙箱。出處：M0 票 03（`scripts/experiments/js-engine/`）；https://pub.dev/packages/fjs ；fjs README〈Security Boundary〉。可信度：2026-11-11 四平台實測。
- **K12** `logger` 2.8.0 的 `AdvancedFileOutput`：`maxFileSizeKB > 0` 時 `path` 是目錄，正在寫的檔叫 `latestFileName`；大小在開啟時與之後每 `fileUpdateDuration`（預設 1 分鐘）檢查一次，超過就關檔、改名成 `fileNameFormatter` 給的檔名再開新檔，所以檔案會略超過上限。`maxRotatedFilesCount` 不算正在寫的檔；超過時刪掉目錄裡**所有其他檔案**中最舊的（依 `fileSorter`，預設最後修改時間），所以目錄只能放 log。預設只有 warning 以上馬上寫出，其他在記憶體裡最多等 `maxDelay`（2 秒），`writeImmediately` 可改。出處：`logger-2.8.0/lib/src/outputs/advanced_file_output.dart`；M0 票 06 的 `test/core/log_test.dart`。可信度：2026-11-11 讀原始碼與測試。
- **K13** `path_provider` 2.1.6 的 `getApplicationSupportDirectory()` 在 dev 身分下：macOS（沙盒）是 `~/Library/Containers/com.personal.fmp.dev/Data/Library/Application Support/com.personal.fmp.dev`；iOS 是 App 資料容器的 `Library/Application Support`；Android 是 `/data/data/com.personal.fmp.dev/files`；Windows 是 `%APPDATA%\<CompanyName>\<ProductName>`，取自 `windows/runner/Runner.rc`（目前是 `com.personal.fmp\FMP Dev`）。出處：M0 票 06 四平台實跑（log 檔寫在這些目錄底下的 `logs/`）。可信度：2026-11-11 四平台實測。
- **K14** drift 2.35.4、drift_dev 2.35.3、sqlite3 3.9.1：sqlite3 3.x 以 build hook 把 SQLite 打包進 App，`sqlite3_flutter_libs` 已停止維護（pub 上最後是 0.6.0+eol）。預設的 hook 在建置時從 sqlite3.dart 的 GitHub release 下載預編譯的 SQLite，以套件內的 SHA-256 比對，所以每台建置機器第一次建置要能連網；`flutter test` 也會在本機跑這個 hook。`drift_dev make-migrations` 讀 `build.yaml` 的 `databases`：只有一個版本時只寫 `drift_schemas/<資料庫>/drift_schema_v<N>.json`，不產生 steps 檔與測試；同版本的快照已存在而內容不同時報錯退出，版本加一時才新增快照；`test_dir` 下的 `migration_test.dart` 已存在就不覆寫，`generated/` 每次重寫。`drift_dev schema dump` 的輸出與 `make-migrations` 寫的快照逐字相同。出處：drift_dev 2.35.3 原始碼 `lib/src/cli/commands/make_migrations.dart`；sqlite3 3.9.1 原始碼 `hook/build.dart`、`lib/src/hook/asset_hashes.dart`；https://pub.dev/packages/sqlite3_flutter_libs ；https://drift.simonbinder.eu/migrations/ 。可信度：2026-11-11 讀原始碼並在本機實跑（M0 票 07）。
- **K15** Android SDK platform-tools 37.0.1 的 adb server 在 macOS 上會自己當掉：預設的 mDNS 後端 `libadbmdns`（Rust）解析區網的 mDNS 封包時 panic（`adbmdns_bridge` → `simple_dns` 的 `Name::try_from`），unwind 失敗後 `abort()`。下一個 adb 指令（含 `flutter devices`）會再啟動 server，所以看起來像被別人重啟；server 不在的那段時間 `flutter devices` 看不到 Android 模擬器。`adb server-status` 的 `mdns_enabled` 顯示 mDNS 是否開著；環境變數 `ADB_MDNS=0` 啟動的 server 不開 mDNS（mDNS 只用在無線偵錯的自動發現，模擬器不靠它）。出處：開發機 `~/Library/Logs/DiagnosticReports/adb-*.ips`（2026-11-08 至 11-11 共 25 份，父行程都是 launchd、堆疊相同）與 adb server log（11-10 18:53 起 server 啟動 53 次，50 次留下 `libunwind: stepWithCompactEncoding - invalid compact unwind encoding`）；https://developer.android.com/tools/adb 〈adb mDNS backends〉與 `server-status`；Google Issue Tracker 573133666（adb 37.0.1 server 因 mDNS 封包當掉，`ADB_MDNS=0` 可避開；只讀到搜尋摘要，頁面要登入）。實測（2026-11-11，M0 票 02b）：`adb kill-server` 後以 `ADB_MDNS=0 adb start-server` 啟動，`adb server-status` 回 `mdns_enabled: false`、`mdns_backend: MDNS_DISABLED`，Android 模擬器 1 秒內回到 `device`。可信度：2026-11-11 讀 crash report 與官方文件，並在開發機實測 `ADB_MDNS=0`。
- **K16** Dart 的 `RandomAccessFile.lock()` 在 macOS 是 POSIX fcntl 記錄鎖：屬於整個行程，持有的行程結束（含 `kill -9`）時 OS 自動放掉；同一個行程裡另外打開同一個檔再關掉，鎖就被放掉，同一個行程再鎖一次也不會被擋。`FileLock.exclusive` 拿不到時丟 `FileSystemException`（errno 35），`FileLock.blockingExclusive` 會一直等。出處：M0 票 02b 的實驗與 `app/test/tool/device_lock_test.dart`。可信度：2026-11-11 本機實測（Flutter 3.47.5 附的 Dart）。
- **K17** `flutter_inappwebview` 6.1.5 的 Apple 端（`_ios` 1.1.2、`_macos` 1.1.2）只有 podspec，沒有 `Package.swift`：Flutter 3.47.5 對它們退回 CocoaPods，建置時警告「The following plugins do not support Swift Package Manager … This will become an error in a future version of Flutter」。`app/` 目前沒有 Podfile（只用 SwiftPM），加了它之後 iOS、macOS 都會多出 Podfile、`Podfile.lock` 與 `Pods/`，建置機器要裝 CocoaPods（本機 1.17.0 可用）。出處：M0 票 04（`scripts/experiments/inappwebview/`）的建置輸出；pub cache 裡兩個套件的目錄。可信度：2026-11-11 實測。

### 18.9 工具鏈

- **T1** 版本基線：2026-11-06 實查 Mac 與 `winpc` 都是 Flutter 3.47.5，本機 Xcode 27.1（2026-11-11 M0 票 04 時已更新到 27.2）、iOS 27.1 模擬器、Android 模擬器 API 37。Flutter 3.47.5 的 `flutter create` 產生的 Android 專案是 AGP 9.1.0、KGP 2.4.0、Gradle 9.3.1、JDK 17。Material 已拆成獨立套件 `material_ui`（flutter/packages，pub 1.11.0，要求 Flutter 3.47.0 以上），但 Flutter 3.47.5 仍內建 `package:flutter/material.dart`，`flutter create` 也還用它；遷移用 `dart fix --apply --code=migrate_design_widgets`。出處：本機指令輸出、`app/android/`；https://pub.dev/packages/material_ui 與其 README〈Migrating existing code to this package〉。可信度：2026-11-11 實查。
- **T2**【待重驗】Apple 平台的 flavor：scheme 名稱要等於小寫的 flavor 名；每個 target 都要有六個 build configuration，並在 Podfile 對應；Podfile、`Podfile.lock`、xcconfig、pbxproj 都要提交。出處：`archive:docs/adr/0036` §決定 10、`0037` §決定 5。可信度：上一版文件。
- **T3**【待重驗】Apple 本機簽章設定檔放進 gitignore（Team ID 不進公開 repo）；`codesign -dvv` 看到 `TeamIdentifier=` 才算簽到。出處：archive 的 `.claude/skills/verify-on-device/references/macos.md`。可信度：上一版文件。
- **T4**【待重驗】Windows 安裝檔：`inno_bundle` 不認 flavor，要手寫 `.iss`；安裝檔的 `AppId` 發佈後不能改；專案路徑超過 260 字元會報 `FTK1011`。出處：`archive:app/AGENTS.md`〈發版〉。可信度：上一版文件。

### 18.10 2026-11-06 研究

出處：`docs/research/audio-webview-2026-11.md`（R1–R5、R8）、`docs/research/plugin-architectures.md`（R6、R7），內附 URL。

- **R1** `flutter_inappwebview` 穩定版 6.1.5 包含 Windows（WebView2）與 macOS；6.2.0 只有 beta（最新 beta.3，2026-02-04；2026-11-11 再查仍是）。Windows 透過 CDP 的 `Network.getCookies` 讀 cookie，含 httpOnly；iOS 與 macOS 走 `WKHTTPCookieStore`。
- **R2** `webview_flutter` 沒有 Windows 實作；它在 Android 上 `getCookies` 時，值含 `=` 的 cookie 會被截斷。
- **R3** media_kit 最後一次發佈是 1.2.6（2025-12-13）；main 分支已換新版 libmpv，但沒發到 pub。
- **R4** `audio_service` 與 `audio_session` 都不支援 Windows；`audio_service` 在 macOS 不完整。
- **R5** `flutter_secure_storage` 最新是 11.2.0（2026-09-16）；macOS 預設的 Data Protection Keychain 需要 `keychain-access-groups` 與 provisioning profile。
- **R6** App Store Guideline 2.5.2 禁止下載會改變功能的程式碼；4.7 允許 JS 插件，但要同時滿足 4.7.1–4.7.5（過濾與檢舉、不暴露原生 API、逐次同意、軟體索引、年齡限制）。
- **R7** Spotube v6 的插件介面定義了遠端歌單寫入（`createPlaylist`、`addTracksToPlaylist` 等），並把功能（abilities）與權限（capabilities）分開；MusicFree 沒有 VIP 欄位，也沒有遠端寫入；LX Music 的自訂源只有 `musicUrl`、`lyric`、`pic`。
- **R8** Google 對嵌入式 WebView 的 OAuth 會回 `disallowed_useragent`（Google Developers Blog）；直接載入登入網頁時改 UA 是否有效，沒有可靠來源，要實測。
