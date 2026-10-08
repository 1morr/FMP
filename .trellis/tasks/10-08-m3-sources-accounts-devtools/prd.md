# M3 三音源、帳號與開發工具

> 擁有者核准 prd／design／implement 之前不開工（ADR 0026 §決定 1）。技術決定在 `design.md`，PR 順序在 `implement.md`。
> 新 ADR 0028–0031 是草稿（提議中），隨本規劃一起核准；0029 的 App 內網頁登入部分等 R1 的結果定案。

## 目標

三個音源（B 站、YouTube、網易雲）都能搜尋、播放、登入（`milestones.md` § M3）。M3 拆成兩半（決定 1）：

- **M3a「三音源與帳號」**：YouTube、網易雲插件；插件庫、插件頁、首次啟動引導；帳號、`CredentialStore`、三種登入方式。做完就是「三個音源都能搜尋、播放、登入」。
- **M3b「開發工具、排程器、電台、Mix、分 P」**：Debug 頁與開發者模式、錯誤詳細頁與回報、插件開發工具、背景排程器、電台直播、Mix、B 站分 P、曲目詳細（`trackDetail`）。M4 依賴 M3b。

## 背景

- 範圍與驗收的來源：`../09-26-fmp-rewrite/milestones.md` § M3；行為以 ADR 0009–0027 為準，M3 新增的決定在 ADR 0028–0031（草稿）。
- M2 已完成（#196–#219），留給 M3 的待辦整理在 `research/m3-scope-digest.md` §2。
- 研究：
  - `research/m3-scope-digest.md`：各 ADR 的 M3 範圍、14 條矛盾、33 條未定之處；
  - `research/m3-decisions.md`：矛盾的處理、未定之處的甲乙丙分類與建議、PR 順序草案、擁有者對丙類五題的決定；
  - `research/r1-youtube-login.md`：R1 的結果（R1 做完才有）。
- 未定之處逐條的決定見 `design.md` §0。

## 擁有者的決定

2026-10-08 規劃 M3 時（丙類五題都照建議，`research/m3-decisions.md` 最後一節）：

1. **拆成 M3a 與 M3b**：M3a「三音源與帳號」是 PR 1–10，M3b「開發工具、排程器、電台、Mix、分 P」是 PR 11–21；兩半各自驗收，M4 依賴 M3b。
2. **真實帳號與真實連線**：
   - 擁有者另開一個 Google 測試帳號，給 R1 與 YouTube 網頁登入的 PR 用；B 站、網易用擁有者指定的帳號。
   - 登入時由擁有者自己輸入密碼或掃 QR；代理不輸入、不讀取密碼。
   - 平常的插件 PR 只用匿名的真實連線，操作最少。
   - 登入相關的實測 Android 與 Windows 兩平台都做。R1 失敗時 YouTube 只提供貼上 cookie（`phase2-plan.md:238` 已定的退路）。
3. **電台對齊舊版主體**：導覽加「電台」、電台清單、以網址新增、排序、刪除、搜尋頁「加為電台」、直播狀態輪詢、播放頁的直播版。粉絲勳章匯入與首頁的電台區塊在 M4。
4. **Mix 從 YouTube 曲目選單開始**：曲目選單的「開始 Mix」，規則照舊版（禁止隨機、禁止加入、插入與打亂，清空佇列就退出 Mix，重啟後恢復）。歌單形態的 Mix 在 M4。
5. **`trackDetail` 在 M3b 最後一個 PR（PR 21）**。

先前已定、在 M3 沿用的：

6. **背景排程器、`mix` 與 `live` 模式從 M2 移到 M3**（2026-10-01，M2 決定 2、M2 `design.md` §12 第 3 條）。排程器與 `fmp_periodic_timer_owner` 跟第一個真工作（電台狀態）一起做。
7. **YouTube 走插件，不改用 Dart**（2026-09-30，M1 探針；ADR 0014 §決定 10 的補充）。
8. **YouTube App 內網頁登入要先實測**：第一個加入 YouTube 登入的里程碑先測，不可用就只提供貼上 cookie（`phase2-plan.md:238`、ADR 0012 §後果）。M3 以 R1 做這項實測。
9. **Linux、macOS、iOS 的實作等 Mac 到貨**（2026-10-01，ADR 0026 §決定 4 的修訂）；M3 的實機驗證是 Android 模擬器與 Windows。

## 範圍

明細與每項落在哪一節見 `design.md` §1；PR 見 `implement.md`。

### M3a 三音源與帳號（PR 1–10）

- YouTube 插件（`search`、`resolveStream`，之後的 PR 加 `login`、`mix`、`trackDetail`）、網易雲插件（`search`、`resolveStream`、`previewOnly`，之後加 `login`、`trackDetail`）；官方 id `youtube`、`netease`。
- 宿主 API v1 的擴充：`HttpRequest.idempotent`、`authHeaders`、`login` 契約（ADR 0028、0029）。
- `1morr/fmp-plugins`：CI、`index.json`、B 站插件的修正（HTML 實體、多尺寸封面、版本號）（ADR 0030）。
- 插件生命週期：啟用與停用、安裝前確認、從 index 安裝與更新（SHA-256）、移除；插件頁；首次啟動引導（ADR 0030）。
- 帳號：`CredentialStore`、帳號表、每音源設定表（「以登入身分瀏覽與播放」）、憑證注入與 Cookie 合併、登出；B 站與網易 QR 登入、YouTube App 內網頁登入（依 R1）與貼上 cookie；失效與刷新（ADR 0012、0029）。
- 設定頁加「帳號」「插件」兩個區塊。

### M3b 開發工具、排程器、電台、Mix、分 P（PR 11–21）

- 開發者模式、設定頁「關於」的版本列、Debug 頁八個區塊、診斷包（ADR 0025）。
- `ErrorReport`、錯誤詳細頁、「在 GitHub 回報」、`.github/ISSUE_TEMPLATE/bug_report.yml`（ADR 0023 §決定 4）。
- 音源健康檢查、App 內插件開發工具（ADR 0015 §決定 7、ADR 0025 §決定 6–7）。
- `BackgroundScheduler` 與 lint `fmp_periodic_timer_owner`（ADR 0017）。
- 電台：`live` 能力、`playLive`、`QueueMode.live`、電台清單與頁面、搜尋頁直播間與「加為電台」、狀態輪詢（ADR 0018 §決定 9、ADR 0031）。
- Mix：`mix` 能力、`QueueMode.mix`、Mix 的持久化與恢復（ADR 0018 §決定 4、10，ADR 0031）。
- B 站分 P：`multiPart` 能力、搜尋結果展開分 P（ADR 0028）。
- 曲目詳細：`trackDetail` 能力、播放頁「詳細」分頁與右側面板補上詳細資料（ADR 0028）。

## 不在 M3

- 歌單、匯入與刷新、排行、遠端歌單編輯、Mix 的歌單形態、粉絲勳章匯入電台、首頁（M4）；帳號頁的「帳號歌單匯入」（M4）。
- 新格式的備份與還原（E16，M4）。M3 的「重設資料」與「從備份還原」用資料庫檔副本（design §12.2）。
- 排行與匯入歌單的刷新間隔設定（跟 M4 的工作一起加，design §16 第 5 條）。
- 舊資料匯入，含舊憑證與 M3 新表的對照（M5）。
- 下載與 Debug 頁「檔案遺失的下載數」（M6）；歌詞、網易歌詞源、AI 插件（M7）；托盤、全域快捷鍵（M8）。
- 「關於」頁的完整內容、使用者指南（M9）。
- Android 的插件開發工具（需要 SAF 讀目錄，另立 ADR）；Linux、macOS、iOS 的實作。
- B 站 geetest 驗證互動（ADR 0013 的待辦）。

## 驗收

### M3a

- [ ] Android 模擬器與 Windows 各做一次端到端操作，步驟照 `implement.md` § M3a 驗收（從首次啟動引導安裝官方插件；三個音源各搜尋、播放；B 站 QR、網易 QR、YouTube 網頁登入或貼上 cookie 各登入一次；「以登入身分瀏覽與播放」開關；登出；停用、更新、移除插件），證據寫進 `research/m3a-acceptance.md`。
- [ ] ADR 0012、0013（三個音源的錯誤對應）、0014、0015 §決定 6、0016（插件頁與登入的離線狀態）、0028（`idempotent`、`login` 的檢查案例）、0029、0030 的測試，逐項對到 `implement.md` § M3a 驗收的表，證據寫進 `research/m3-adr-tests.md`。
- [ ] §8：YouTube App 內網頁登入（ADR 0012）。R1 通過時以 App 內網頁登入驗；R1 不通過時記錄「只提供貼上 cookie」並以貼上 cookie 驗。
- [ ] `milestones.md` 的 M3a 狀態與勾選已更新。

### M3b

- [ ] Android 模擬器與 Windows 各做一次端到端操作，步驟照 `implement.md` § M3b 驗收，證據寫進 `research/m3b-acceptance.md`。
- [ ] ADR 0017 排程器的測試與 lint `fmp_periodic_timer_owner` 的雙向變異測試。
- [ ] ADR 0015 §決定 7、0016（電台頁的離線狀態）、0018（Mix 修剪、開直播後音樂結果不播出也不再解析、直播重連）、0023 §決定 4、0025、0028、0031 的測試，逐項對到 `implement.md` § M3b 驗收的表，證據寫進 `research/m3-adr-tests.md`。
- [ ] §8：加入 Debug 頁的里程碑實測（ADR 0025）：Windows release 版開啟開發者模式、重啟後仍開啟、從總開關關掉；Debug 頁看到一次搜尋的網路摘要；匯出的診斷包以解壓工具打開。
- [ ] `milestones.md` 的 M3b 狀態與勾選已更新；本任務 `finish`、`archive`。

## 未決

只剩一件，其餘都在 design 定案：

1. **R1 的結果**（`implement.md` § R1）：決定 ADR 0029 的 App 內網頁登入部分、manifest `login.webView` 的欄位（固定 UA 字串或宿主的「桌面 UA」）、PR 9 的範圍。
（`design.md` §16 的確認清單：2026-10-08 擁有者確認 14 條全部照建議。）
