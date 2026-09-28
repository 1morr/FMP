# 設計：歌詞（階段二第 15 項）

## 目標

為 `app/` 定下歌詞源（插件能力）、自動匹配與手動改選、偏移、格式與解析、顯示、桌面歌詞視窗、AI 功能的形狀。產出 ADR 0021。技術設計見 `design.md`，執行步驟見 `implement.md`。

依據：parent `prd.md` 階段二第 15 項；`docs/audit/questions.md` E9–E11（皆保留）、B5；`phase2-plan.md` §6 的 B5 方向與 §8 平台功能；
ADR 0009（桌面歌詞視窗是平台能力）、0011（log 遮蔽、設定分組）、0012（第三方歌詞源不帶登入）、0014（`lyrics` 能力、共用匹配）、
0016（歌詞內容進統一快取、匹配結果在主資料庫）、0019（共用評分核心、`track_origins`）。

## 現況（`research/current-state.md`，已以程式碼核對，另見 `docs/audit/features.md` §6）

- 三個歌詞源（網易、QQ、lrclib）是三個獨立 Dart 類別，沒有共同介面，字串分派 5 處；lrclib 預設停用。
  曲目有原始平台 id 時直接抓、跳過搜尋（`lyrics_auto_match_service.dart:104-151`）。
- 自動匹配預設關，開播時在背景跑；評分為標題 40%／歌手 30%／時長 20%／有同步 10%，Levenshtein，門檻 0.6，±20 秒；只有一個候選就直接用（`:701-703,841-895`）。
- 手動搜尋：底部面板，「全部」並行搜所有啟用源，依使用者排序串接；選定後寫 `LyricsMatch`（`offsetMs=0`）並換掉快取內容。
- 偏移存在匹配紀錄上，正值＝歌詞提前；播放頁 ±100／500／1000ms；桌面視窗可右鍵某行校正。
- 只有 LRC 與純文字，**沒有逐字**；網易有翻譯＋羅馬音、QQ 只有翻譯、lrclib 都沒有；以時間戳相等合併，顯示模式原文／優先翻譯／優先羅馬音。
- 標題解析器（正則，3 種模式）把影片標題拆成曲名與歌手。
- AI 兩種模式（預設關）：「標題解析」只送標題與上傳者；「候選挑選」再送時長、所有候選（含每首最多 8 行／500 字的歌詞預覽）。
  使用者自填 OpenAI 相容端點，key 在 secure storage；**端點不驗 https**（`openai_chat_endpoint.dart:1-6`），**payload 與回應原文在 debug 級別寫進 log**（`ai_lyrics_selector.dart:116,145`、`ai_title_parser.dart:57,73`）。
- 桌面歌詞視窗（`desktop_multi_window` 0.3.1、獨立 engine）**只開在 Windows**，按鈕沒有平台守衛；有置頂、透明、hover 才顯示工具列、單行模式、11 項樣式；
  **沒有點擊穿透、沒有鎖定**。主視窗推資料的程式碼掛在 `TrackDetailPanel` 的 `ref.listen`，同步綁在 UI 生命週期上。
  字串以 map 推送，舊 static-rule `lyrics_window_strings` 守「讀的 key＝推的 key」。

## 研究結論（`research/prior-art.md`、`research/packages-and-platform.md`）

- 歌詞源插件化：MusicFree、LX、BetterLyrics。純歌詞插件的介面很窄：搜尋吃（標題、歌手、專輯、時長），取用吃 id；搜尋與取用分開才做得出候選清單。
- 候選清單＋手動改選：Namida、MusicFree、BetterLyrics 有，改選結果都持久化；LX、Spotube、Harmonoid 沒有。
- 逐字格式現實只有 QQ QRC、酷狗 KRC、網易 YRC；LRC 是唯一共同下限（lrclib 只給逐行）。`flutter_lyric` 3.0.8（2026-09-16）解析 LRC／QRC／YRC 並含渲染元件，沒有 KRC 的 Dart 套件；`lyrics_parser` 與 Dart 3 不相容。
- 桌面歌詞真正做到三平台的只有 LX（Electron `setIgnoreMouseEvents`，Linux 還要輪詢游標）；沒有穿透的產品（Namida、Spotube）改用 hover 顯示控制列。
- Flutter 官方多視窗 API（2026-08-24 公告）只在 `main` channel、標示實驗性；穩定路線仍是 `desktop_multi_window` 0.3.1（2026-08-26，Windows／macOS／Linux）。
- `window_manager` 0.5.2 的 Linux 後端沒有 `setIgnoreMouseEvents`（已核對原始碼）；Linux 透明靠 GTK CSS，#179（Arch 上透明變黑）2026-09-21 以 not planned 關閉。
  Wayland 的 XDG shell 刻意不給全域定位與置頂；GTK3＋Wayland 下置頂是否生效取決於 compositor，要實機驗證。
- Android 懸浮窗是使用者手動授予的特殊權限，12、15 持續收緊；iOS 沒有可顯示歌詞的系統級浮窗（PiP 只接受影片）。
- 七個成熟產品沒有一個用 LLM 做歌詞匹配；BetterLyrics 的 `SongSearchMap` 記「用什麼查詢、查哪個來源」而非結果。
- OpenAI「不要把 key 放在客戶端」指的是開發者把自己的 key 內嵌進 App；FMP 是使用者自帶 key（存在自己裝置的 secure storage），不是這種情形。

研究更正：研究初稿說 B5 勾「修改」，實際 `questions.md:119` 勾的是「不確定」，已在 `current-state.md` 更正；方向以 `phase2-plan.md` §6 為準。

## 已確定的方向

- E9–E11 保留；歌詞源全部是插件的 `lyrics` 能力（ADR 0014），匹配用共用評分核心、結果持久化、改選後不再重算（ADR 0014 決定 9、ADR 0019 決定 6）。
- 歌詞內容在統一快取（鍵為歌詞插件＋歌詞 id），匹配結果在主資料庫，淘汰後以存下的 id 重抓（ADR 0016）。
- B5：AI 保留、預設關；強制 https；payload 不寫進 log；送出的欄位最小化並在設定頁列出（`phase2-plan.md` §6）。
- 桌面歌詞視窗以平台能力宣告，目標是所有桌面平台一致（ADR 0009、`phase2-plan.md` §8）。

## 已決定

1. **AI 兩種模式都保留（2026-09-28）**：標題解析與候選挑選。
2. **歌詞的新功能解除凍結（2026-09-28）**：擁有者把逐字歌詞、桌面歌詞的點擊穿透與鎖定、Android／iOS 的懸浮歌詞納入本項，
   依成熟做法設計；各平台做不到的以能力宣告降級。可行性補查見 `research/extra-features.md`。

## 待決定

1. 是否接入 TypeSafe Jev 這類「結構化決策」模型做候選挑選，以及以什麼形式接入（補查見 `research/ai-decision-models.md`）。
2. 各新功能的平台範圍與降級方式（等補查結果）。

### Jev 已核對的事實（2026-09-28，docs.typesafe.ai 與 NanoJev README）

- TypeSafe 於 2026-09-15 公告，early access；`POST https://api.typesafe.ai/v1/systemone`，Bearer key。
- 不生成文字：輸入 state 與具型別的問題（Choice 從最多 255 個選項挑一個、Score 依等級評分、Noul 是非題），回傳每個選項的機率與 confidence。
- 價格 $0.042／百萬輸入 token、輸出免費；官方宣稱 70–500ms。
- 已知弱點（官方 jaggedness 頁）：英文最佳，CJK「可處理但不一樣好」；不擅長數字與日期比較（應在程式碼算）；會照字面理解；可被內容中的誘導文字影響。
- 企業才有零資料保留；Jev 不以客戶資料訓練。
- NanoJev（MIT，2026-09-17 建立）是研究用復刻：Qwen3-0.6B 加決策頭，只訓練在 4 個遊戲任務，需 CUDA 伺服器，不是通用模型。

## 不在範圍

- 本機歌詞檔匯入（舊專案沒有，擁有者未納入）。
- 歌詞頁與視窗的版面（第 5 項）。

## 驗收條件

- [ ] ADR 0021 記錄：歌詞插件介面、自動匹配與手動改選、偏移、格式與解析、顯示與同步來源、桌面歌詞視窗與平台差異、AI 功能與隱私、快取與持久化。
- [ ] E9–E11、B5 各自對到決定。
- [ ] `phase2-plan.md` §3 第 15 項標 ✅ 與 ADR 編號。
