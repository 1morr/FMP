# 0021 — 歌詞：插件提供歌詞與 AI、正規化的逐字歌詞文件、單一同步來源、可鎖定的桌面與行動歌詞

- 狀態：已採納
- 日期：2026-09-28
- 影響範圍：插件能力 `lyrics` 與新增的 `aiAssist`、歌詞文件 DTO、歌詞匹配流程、`lyrics_matches` 表、歌詞快取、歌詞顯示與同步、
  桌面歌詞視窗、Android 懸浮歌詞、iOS Live Activity、平台能力宣告、`PermissionGateway`、歌詞與 AI 設定、舊資料匯入

## 背景

舊專案（`.trellis/tasks/archive/2026-09/09-28-design-lyrics/research/current-state.md`、`docs/audit/features.md` §6，已以程式碼核對）：

- 三個歌詞源是三個獨立 Dart 類別、字串分派 5 處；各自的評分用 Levenshtein、±20 秒、門檻 0.6。
- 只有 LRC 與純文字，沒有逐字。
- AI 有兩種模式（標題解析、候選挑選），預設關；端點不驗 https，payload 與回應原文在 debug 級別寫進 log（B5）。
- 桌面歌詞視窗只開在 Windows、按鈕沒有平台守衛；沒有點擊穿透與鎖定。
- 同步掛在 `TrackDetailPanel` 的 `ref.listen` 上；字串以 map 推送，靠 `lyrics_window_strings` static-rule 守。

擁有者決定（2026-09-28）：
- E9–E11 保留，AI 兩種模式都保留；
- 逐字歌詞、桌面歌詞的點擊穿透與鎖定、Android／iOS 的懸浮歌詞解除功能凍結、納入本項；
- AI 服務做成插件；
- Android 狀態列歌詞列入待辦。

## 考慮過的選項

- **歌詞源寫死在 Dart（舊版）**：否決，ADR 0014 已決定所有來源都是插件。
- **宿主內建 QRC／KRC／YRC 解析器**：否決。解密與格式隨來源變動，放在插件裡改了只需更新插件；宿主只留 LRC 這個共同下限。
- **只保留 AI 標題解析**：否決（擁有者選擇保留候選挑選）。
- **App 內建 OpenAI 相容與 System One 兩個客戶端**：否決。擁有者指出做成插件只需更新插件；介面描述的是 FMP 的需求（給標題回曲名歌手、給候選回選擇與確定度），不是廠商格式，所以穩定。
- **只承諾 Windows 的桌面歌詞**：否決，目標是所有桌面平台一致（ADR 0009）。
- **沒有鎖定、只靠 hover 顯示工具列**（Namida、Spotube）：否決，擁有者要求穿透與鎖定。
- **同步掛在 UI 元件、以字串 map 推子視窗、逐 tick 推送位置**：否決。版面切換就可能停；漏推欄位只能靠 static-rule 擋；計時器與 IPC 過多。
- **Flutter 官方多視窗 API**：暫不採用，仍只在 `main` channel、標示實驗性；進 stable 後再評估。
- **Android 狀態列歌詞**：列入待辦。AOSP 自 API 21 不顯示 `tickerText`，不需 root 的只有魅族與需寄信申請的小米 HyperOS。
- **iOS 系統級懸浮歌詞**：不可行，系統只開放影片的子母畫面，誤用會被審核拒絕。

## 決定

1. **`lyrics` 能力**（ADR 0014）：
   - `searchLyrics({title, artist, album?, durationMs})` 回候選（id、標題、歌手陣列、專輯、時長、有無同步／逐字／翻譯／羅馬音）；
   - `getLyrics({id})` 回歌詞文件；
   - `lyricsForOrigin({platform, platformId})`：插件宣告認得的原始平台；曲目來自該平台，或 `track_origins`（ADR 0019）有該平台 id 時，直接取、不搜尋。
   
   第三方歌詞源不帶登入（ADR 0012）。
2. **歌詞文件**（隨 `apiVersion` 版本化）：
   - `kind`（`synced`／`plain`／`instrumental`）；
   - `lines[{startMs, endMs?, text, words?[{startMs, endMs, text}]}]`，一律絕對毫秒；
   - 行級的 `translation[]`、`romanization[]`；
   - 可選的 `lrc` 原文。
   
   YRC、QRC（非標準 DES）、KRC（XOR＋zlib、字時間相對行首）由插件轉成 `lines`。宿主只有一個 LRC 解析器（含 enhanced LRC 字時間），沿用舊版邏輯與測試。
   翻譯與羅馬音以行開始時間對齊、容差 100ms。沒有逐字時逐行顯示（行起＝首字起、行訖＝末字訖），不做逐行→逐字。
3. **`aiAssist` 能力**（新增）：
   - `parseTitle({title, uploader})` → 曲名、歌手、歌手確定度。
   - `pickCandidate({query, candidates})` → `chosen`（採用）、`noneMatch`（這次不自動匹配）或 `unsure`（改用評分核心的結果），附確定度。
   
   確定度門檻由插件解讀並可在插件設定調整（各家定義不同）。官方兩個：
   - `openai-compatible`：兩者都做；
   - `system-one`：`/v1/systemone`，接 TypeSafe、OpenRouter、自架 Laya；標題解析以宿主正則列出的拆法當選項。
4. **AI 隱私（B5）**：
   - AI 預設關；模式為「關／標題解析／標題解析＋候選挑選」。
   - 宿主決定送出欄位並在設定頁逐項列出：
     - 標題解析：影片標題、上傳者；
     - 候選挑選：影片標題、上傳者、時長、解析結果，以及每個候選的曲名、歌手、專輯、時長、有無同步、前 8 行（至多 500 字）預覽；
     - 影片描述不送。
   - manifest `userEndpoint`：端點由使用者填，宿主檢查 https，顯示網域、使用者確認後才加入該插件的允許網域。
   - key 存插件憑證區，不進 log、不進備份。宿主不記錄 AI payload 與回應原文。
5. **匹配**（E9、E10）：
   - 觸發：開播時在背景跑，「自動匹配歌詞」沿用、預設關；播放路徑不等它，同一曲目防併發。
   - 順序：
     1. 已有匹配就用；
     2. 依使用者排序以 `lyricsForOrigin` 直取；
     3. 標題解析（宿主正則，AI 模式開啟時用 `parseTitle`、失敗退回正則）；
     4. 並行搜尋所有啟用的歌詞插件；
     5. 共用評分核心加同步歌詞加分（ADR 0014 決定 9、ADR 0019 決定 6）；「允許自動匹配純文字歌詞」沿用、預設關；
     6. 開啟候選挑選時送前 8 名給 `pickCandidate`。
   - 手動改選列出評分，寫入後標 `manual`，自動流程永不覆寫。
   - 歌詞插件被移除時匹配保留、標「歌詞源未安裝」、不自動重配。
6. **資料**：
   - `lyrics_matches`（主資料庫）：曲目鍵 FK 連帶刪除、插件 id、歌詞 id、`offsetMs`、`origin`（`direct`／`scorer`／`ai`／`manual`）、分數、AI 確定度、時間。
   - 歌詞內容在 `cache.db`，鍵為插件 id＋歌詞 id（ADR 0016）；AI 標題解析結果也在 `cache.db`。
   - 偏移：`adjusted = position + offsetMs`，正值＝歌詞提前；播放頁 ±100／500／1000ms；點行跳轉；桌面視窗右鍵某行校正。
7. **同步與顯示**：
   - 歌詞模組的 `LyricsSession` 是唯一來源，持有目前曲目的歌詞文件、偏移、顯示模式與播放狀態，與 UI 生命週期無關。
   - 播放狀態、位置、速度、時間戳只在播放、暫停、seek、換歌、換速時推送，各顯示端以 frame callback 外推，不開週期計時器。
   - 子 engine 與主 engine 以一個共用 Dart 檔定義的型別化訊息溝通（JSON 序列化）；子視窗與懸浮窗不顯示提示，錯誤轉給主視窗（ADR 0023）。
   - 播放頁、桌面視窗、Android 懸浮共用一套歌詞 widget；逐字漸變用 `CustomPainter`＋分段 shader＋`saveLayer(dstIn)` 遮罩。
   - 顯示模式沿用（原文／優先翻譯／優先羅馬音），另加「逐字高亮」（預設開）。播放頁上歌詞的位置（右欄分頁或超寬時的中欄）見 ADR 0024。
8. **桌面歌詞視窗**（E11）：
   - 平台能力 `desktopLyrics`，細分 `clickThrough`、`alwaysOnTop`（ADR 0009）；入口只在宣告時出現。
   - 以 `desktop_multi_window`（每視窗一個 engine）實作；透明、置頂、單行、11 項樣式、hover 工具列、點行跳轉、右鍵校正沿用；關閉是隱藏不銷毀。
   - **鎖定**＝不能拖動＋點擊穿透。解鎖入口：托盤選單、全域快捷鍵、主視窗播放列的歌詞按鈕，以及 hover 浮出的解鎖鈕（預設開，可關）。
   - 平台實作：
     - Windows：`window_manager.setIgnoreMouseEvents`；
     - macOS：`window_manager`；
     - Linux X11：自寫 GTK 空 input region＋`gdk_window_set_pass_through`；
     - Wayland：實機驗證，不支援的能力不宣告，鎖定只剩不能拖動並在設定頁註明。
   - hover 解鎖鈕在 Windows 與 Linux 以每 100ms 查游標實作，計時器只在「鎖定＋視窗可見＋解鎖鈕開啟」時存在。
9. **Android 懸浮歌詞**：
   - 平台能力 `overlayLyrics`。
   - 可拖動；鎖定＝`FLAG_NOT_TOUCHABLE`＋不透明度 0.8（Android 12 起的規定）；解鎖在播放通知的自訂按鈕與 App 內開關。
   - 以 `flutter_overlay_window`（第二個 engine、共用歌詞 widget 與型別化訊息）為候選，控制經訊息回主 engine 的 `PlaybackController`；不可行就改原生 View，訊息不變。
   - 權限經 `PermissionGateway`（ADR 0020）新增「顯示在其他應用上層」；小米、ColorOS 的額外懸浮權限只能在說明中提示。
10. **iOS 鎖屏／動態島**：平台能力 `liveActivityLyrics`，以 ActivityKit 顯示目前一行（＋翻譯）、資料 ≤ 4KB、換行時本機更新；iOS 平台任務實測後才宣告。
11. **設定**（ADR 0011 的「歌詞」組）：
    - 歌詞插件的啟用與順序；
    - 自動匹配、純文字自動匹配、顯示模式、逐字高亮；
    - AI 模式與使用的 AI 插件，端點、模型、門檻、key 在該插件的設定頁；
    - 桌面歌詞的樣式、置頂、單行、鎖定、hover 解鎖鈕、快捷鍵；
    - Android 懸浮的開關、位置、字級、顏色、不透明度。
12. **舊資料匯入**（ADR 0010）：
    - `LyricsMatch` → `lyrics_matches`：來源對到官方插件 id，`externalId`、`offsetMs` 照搬；`origin` 記 `manual`（舊版不分自動與手動，視為使用者認可）。
    - 桌面歌詞樣式與顯示模式照搬。
    - AI 端點、模型、逾時搬進 `openai-compatible` 插件設定；舊 key 在該插件安裝後搬進其憑證區，並刪除舊項目。
    - 標題解析快取與舊歌詞檔案快取不搬。

採用的慣例：
- MusicFree 的「搜尋與取用分開、跨插件候選清單」；
- AMLL、Lyricify、BetterLyrics 的「行＋字、整數毫秒」正規化與逐字→逐行降級；
- LX 的翻譯行 100ms 容差對齊，以及 LX、BetterLyrics 的「鎖定＝不能拖＋穿透、托盤與快捷鍵解鎖、輪詢游標做 hover」；
- LX Mobile 的 Android 鎖定（`FLAG_NOT_TOUCHABLE`＋0.8）；
- `desktop_lyrics` 的 GTK 穿透；
- TypeSafe `/v1/systemone` 的 Choice 題與 pre-parsed value extraction。

## 後果

- 好的：
  - 來源與 AI 服務改了只需更新插件；
  - 逐字、翻譯、羅馬音一套結構、一套 widget；
  - 同步不再隨版面停止；
  - 漏推欄位變成編譯錯誤；
  - B5 的三個問題都有對應；
  - 桌面與 Android 都能鎖定穿透。
- 壞的：
  - 插件多一種能力與歌詞文件格式要長期相容；
  - Linux 要自寫 GTK 原生碼；
  - 桌面鎖定時多一個查游標的計時器；
  - Android 懸浮多開一個 engine；
  - `window_manager` 0.5.x 已停止維護（0.6.0 改建在 `nativeapi`），換套件的成本落在平台層。
- 之後要注意：
  - Android 狀態列歌詞、本機歌詞檔匯入在功能凍結待辦；
  - Flutter 官方多視窗 API 進 stable 後再評估；
  - 逐字渲染直接用 `flutter_lyric`（避開已撤回的 3.0.5）或自寫，在第一個加入逐字的里程碑決定。

## 如何確認

- 單元測試：
  - LRC 解析（含 enhanced LRC 字時間）、翻譯 100ms 對齊、逐字→逐行降級；
  - 匹配流程各分支：已有匹配、直取、正則與 AI 標題解析、`chosen`／`noneMatch`／`unsure`、手動改選不被覆寫、插件移除後保留；
  - 偏移換算與校正；顯示端外推位置。
- 插件契約（ADR 0015）：
  - `lyrics` 的搜尋、取用、直取回傳合法的歌詞文件（字時間為絕對、遞增）；
  - `aiAssist` 的兩個方法；官方 AI 插件的測試斷言 log 不含 payload 內容。
- 宿主測試：
  - AI 請求只含設定頁列出的欄位；非 https 端點被拒；
  - 使用者端點網域確認前不在允許清單。
- 型別化訊息的序列化往返測試；取代舊 `lyrics_window_strings` static-rule。
- lint：
  - `fmp_periodic_timer_owner`（ADR 0017）的允許擁有者加入平台層的桌面歌詞模組（查游標）；
  - `fmp_layer_imports`（ADR 0015）：`desktop_multi_window`、`window_manager`、`flutter_overlay_window` 只在平台層實作檔。
- 平台實測（延後）：
  - 桌面歌詞在 macOS、Linux X11、Wayland 的穿透、置頂、定位；
  - `window_manager` 在子 engine 設穿透時作用在歌詞視窗；
  - `flutter_overlay_window` 的記憶體與 Android 15 前景服務限制；
  - iOS Live Activity 本機逐行更新。
