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

補查（`research/extra-features.md`、`research/ai-decision-models.md`，關鍵項已抽查）：

- **逐字格式**：YRC、QRC 的字時間是絕對時間，KRC 相對行首；QRC 需非標準 DES、KRC 是 XOR＋zlib，各有多份公開實作互證。
  成熟產品一律把各格式正規化成「行＋字、整數毫秒」的內部結構；降級只有逐字→逐行（行起訖＝首字起、末字訖），沒有逐行→逐字。
  逐字翻譯只有 Apple TTML 原生支援，其他來源的翻譯與羅馬音都是行級，以時間戳相等（LX 容差 100ms）合併。
- **逐字渲染**：`flutter_lyric` 3.0.8 以 `CustomPainter`＋分段 shader＋`saveLayer(dstIn)` 遮罩做漸變高亮。
- **桌面穿透**：`window_manager` 的 `setIgnoreMouseEvents` 在 Windows 只切 `WS_EX_TRANSPARENT`、`forward` 參數被忽略（已核對原始碼），macOS 可用，Linux 未實作；
  `window_manager` 0.5.x 已停止維護，0.6.0 改建在 `nativeapi` 上。Linux 可用 GTK3 空 input region 穿透（`desktop_lyrics` 的做法），GTK3 的 Wayland 後端也實作了 input region，但 Wayland 下實際效果未驗證、置頂與定位不保證。
  成熟產品的「鎖定」＝不能拖＋點擊穿透（＋淡化）；穿透後靠托盤選單、全域快捷鍵、主視窗開關解鎖，Windows 上 hover 顯示解鎖鈕要輪詢游標（LX 500ms、BetterLyrics 50ms）。
- **Android 懸浮**：`flutter_overlay_window` 0.5.0（2025-04-20）開第二個 engine、不註冊其他插件，只能以它自帶的訊息通道與主 isolate 溝通；
  LX Mobile、MusicFree 用原生 View。鎖定＝`FLAG_NOT_TOUCHABLE`，Android 12 起穿透觸控要求視窗不透明度 ≤ 0.8。小米、ColorOS 另有「後台彈出介面」「懸浮窗」權限，都沒有可程式判斷的 API。
- **Android 狀態列歌詞**：AOSP 自 API 21 不顯示 `tickerText`、`MediaMetadata` 沒有歌詞欄位；不需 root 的只有魅族 Flyme（文件化的反射 flag）與小米 HyperOS 焦點通知（需寄信申請）；其餘要 root＋LSPosed 模組。
- **iOS**：系統級懸浮不可能。Live Activity 可在鎖屏／動態島顯示一行歌詞：最長 8 小時、資料 ≤ 4KB、不能連網；官方只對「推播更新」記載每小時預算，App 在前景或背景以本機 `Activity.update` 更新是否受限未記載，需實測。媒體報導 iOS 26 的 Apple Music 就在 Live Activity 逐行顯示歌詞。
- **決策模型**：`POST /v1/systemone` 已有三個實作者——TypeSafe（官方）、OpenRouter（改 base URL 即可，用 OpenRouter 的 key 計費）、開源 Laya（Apache-2.0，可自架，宣稱 100+ 語言）；
  沒有跨廠商標準，這個形狀就是事實標準。各實作的 confidence 定義不同（Laya 文件明說不能沿用 Jev 的門檻）。另有多個 9 月才出現的開源復刻，都未經驗證。
  OpenAI 相容端點可用 `logprobs` 取選項機率，但 `top_logprobs` 最多 5。音樂或歌詞領域沒有產品級先例。
- **Jev 本身**（docs.typesafe.ai、NanoJev README）：
  - TypeSafe 於 2026-09-15 公告，early access；`POST https://api.typesafe.ai/v1/systemone`，Bearer key。
  - 不生成文字：輸入 state 與具型別的問題（Choice 從最多 255 個選項挑一個、Score 依等級評分、Noul 是非題），回傳每個選項的機率與 confidence。
  - 價格 $0.042／百萬輸入 token、輸出免費；官方宣稱 70–500ms。
  - 已知弱點（官方 jaggedness 頁）：英文最佳，CJK「可處理但不一樣好」；不擅長數字與日期比較（應在程式碼算）；會照字面理解；可被內容中的誘導文字影響。
  - 企業才有零資料保留；Jev 不以客戶資料訓練。
  - NanoJev（MIT，2026-09-17 建立）是研究用復刻：Qwen3-0.6B 加決策頭，只訓練在 4 個遊戲任務，需 CUDA 伺服器，不是通用模型。

## 已確定的方向

- E9–E11 保留；歌詞源全部是插件的 `lyrics` 能力（ADR 0014），匹配用共用評分核心、結果持久化、改選後不再重算（ADR 0014 決定 9、ADR 0019 決定 6）。
- 歌詞內容在統一快取（鍵為歌詞插件＋歌詞 id），匹配結果在主資料庫，淘汰後以存下的 id 重抓（ADR 0016）。
- B5：AI 保留、預設關；強制 https；payload 不寫進 log；送出的欄位最小化並在設定頁列出（`phase2-plan.md` §6）。
- 桌面歌詞視窗以平台能力宣告，目標是所有桌面平台一致（ADR 0009、`phase2-plan.md` §8）。

## 已決定

1. **AI 兩種模式都保留（2026-09-28）**：標題解析與候選挑選。
2. **歌詞的新功能解除凍結（2026-09-28）**：擁有者把逐字歌詞、桌面歌詞的點擊穿透與鎖定、Android／iOS 的懸浮歌詞納入本項，
   依成熟做法設計；各平台做不到的以能力宣告降級。可行性補查見 `research/extra-features.md`。

3. **AI 服務做成插件（2026-09-28）**：新增插件能力（標題解析、候選挑選），OpenAI 相容與 System One（`/v1/systemone`：TypeSafe、OpenRouter、Laya）各為一個官方插件；
   廠商格式、prompt、確定度門檻的解讀都在插件內，改了只更新插件。擁有者指出「插件只要更新插件就行」，推翻了「App 內建兩個客戶端」的建議——
   介面描述的是 FMP 的需求（給標題與上傳者回曲名歌手；給候選回選擇與確定度），不是廠商格式，所以穩定。
   宿主仍負責：送出欄位的白名單並在設定頁列出、https 檢查、key 存插件憑證區且不進 log 與備份、使用者自填的端點網域在設定頁顯示後才加入該插件的允許網域。

4. **行動裝置系統級歌詞（2026-09-28，按建議）**：
   - Android 懸浮歌詞做：可拖動，鎖定＝點擊穿透＋不透明度 ≤ 0.8，解鎖在播放通知按鈕與 App 內開關；需使用者授予「顯示在其他應用上層」，廠商額外權限只能在說明中提示。
   - iOS 鎖屏／動態島一行歌詞（Live Activity）列入設計，iOS 平台任務實測本機逐行更新可行才開放。
   - Android 狀態列歌詞列入待辦（AOSP 不支援；無 root 只有魅族與需申請的小米 HyperOS）。

5. **桌面歌詞鎖定（2026-09-28，按建議）**：鎖定＝不能拖動＋點擊穿透；解鎖入口為托盤選單、全域快捷鍵、主視窗播放列的歌詞按鈕、
   滑鼠停在歌詞上浮出的解鎖鈕（可在設定關閉；Windows 與 Linux 在鎖定期間約每 0.1 秒查游標，解鎖或關閉歌詞即停）。
   Windows、macOS 完整；Linux X11 以自寫 GTK 原生碼穿透；Wayland 實機驗證，不支援時鎖定只剩不能拖動並在設定頁註明。

6. **技術選擇（`design.md`）**：插件新增 `aiAssist` 能力、`lyrics` 能力分搜尋／取用／依原始平台直取；歌詞文件以「行＋字、絕對毫秒」正規化，各家逐字格式由插件轉換，宿主只有 LRC 解析器；
   `lyrics_matches` 表（手動改選永不被覆寫）；`LyricsSession` 為唯一同步來源、以型別化訊息推給子 engine、各顯示端自行外推位置；
   桌面視窗沿用 `desktop_multi_window`；Android 懸浮以 `flutter_overlay_window` 為候選、不行改原生 View；iOS 以 Live Activity 顯示一行。

## 不在範圍

- Android 狀態列歌詞、本機歌詞檔匯入：列入第 20 項待辦。
- 歌詞頁與視窗的版面（第 5 項）。

## 驗收條件

- [ ] ADR 0021 記錄：歌詞與 AI 插件介面、歌詞文件格式、自動匹配與手動改選、偏移、同步與顯示、桌面歌詞視窗（鎖定與平台差異）、Android 懸浮、iOS Live Activity、AI 隱私、資料與快取、舊資料匯入。
- [ ] E9（多源搜尋、自動匹配、手動選擇）、E10（AI 兩種模式）、E11（桌面歌詞視窗到全桌面平台）、B5（預設關、https、payload 不進 log、欄位清單）各自對到決定。
- [ ] ADR 0009、0014、0015／0017、0016、0020 加上指向 ADR 0021 的一句話；`phase2-plan.md` §3 第 15 項標 ✅、第 20 項待辦補上，§7／§8 加入實測項目。
