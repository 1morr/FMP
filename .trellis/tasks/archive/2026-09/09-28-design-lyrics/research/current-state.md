# 舊專案的歌詞（current state）

- 查證日期：2026-09-28
- 查證方式：讀 `docs/audit/`（`features.md` §6/§15、`sources.md`、`data.md`、`platforms.md` §1.3/§3.7、`questions.md` B5/E9–E11）、`docs/adr/`（0009–0020）、`lib/services/lyrics/`、`lib/providers/lyrics/`、`lib/ui/windows/`、`lib/ui/widgets/lyrics/`、`lib/services/audio/` 與 `test/services/static_rules/lyrics_window_strings_static_rule_test.dart` 逐檔核對。未執行 App、未跑測試、未打 API。
- 舊專案狀態：`docs/audit/questions.md:247-249` 記 E9（多源搜尋／自動匹配／手動選擇）、E10（AI 歌詞匹配／標題解析）、E11（桌面歌詞視窗）三項擁有者都勾「保留」；B5（`questions.md:119`）勾「不確定」，方向見 `phase2-plan.md` §6。本檔描述的是被重寫的那份實作。

## 1. 歌詞源與取得流程

三個歌詞源是**三個各自獨立的 Dart 類別，沒有共同介面**，靠字串 `'netease' / 'qqmusic' / 'lrclib'` 分派（`docs/audit/sources.md:71`；`lib/services/lyrics/lyrics_auto_match_service.dart:278-300,444-461`）。分派點共 5 處（`sources.md:287`）。

| 源 | 端點 | 取得方式 | 證據 |
|---|---|---|---|
| 網易雲 | `https://music.163.com/api/search/get`（搜尋，POST 表單）、`/api/song/lyric`（歌詞，GET `lv=1&tv=1&rv=1`） | 搜尋 → 逐首抓歌詞，兩步 | `lib/services/lyrics/netease_source.dart:13-14,131,166-174,214-222` |
| QQ 音樂 | `https://u.y.qq.com/cgi-bin/musicu.fcg`（搜尋 `DoSearchForQQMusicDesktop`、歌詞 `GetPlayLyricInfo`，皆 POST JSON） | 搜尋 → 逐首抓歌詞；歌詞欄位 base64 解碼＋HTML entity 解碼 | `lib/services/lyrics/qqmusic_source.dart:10-19,130-152,178-206,295-335` |
| lrclib | `https://lrclib.net/api`（`/search`、`/get/<id>`、`/get` 精確匹配），**無 API key** | 一次搜尋直接回結果（含歌詞內容） | `lib/services/lyrics/lrclib_source.dart:20-24,46-127` |

- **原始平台 id 直取**：舊專案已有這條路，但欄位名不是 `track_origins`。`Track` 上有 `originalSongId` + `originalSource`（`docs/audit/data.md:36`；`lib/data/models/track.dart:264,267`），匯入歌單時寫入（`lib/data/repositories/playlist_mutation_repository.dart:749-760`）。自動匹配時若兩者非 null 且該源已啟用，直接 `getLyricsResult(id)` 跳過搜尋（`lyrics_auto_match_service.dart:130-151`、`_tryDirectFetch` `:643-672`）；失敗才退回搜尋。另有更早的一條特例：`sourceType == 'netease'` 的曲目直接用 `track.sourceId` 抓（`:104-127`）。`_tryDirectFetch` 明確標「Spotify 無歌詞 API」故不支援（`:642,658-659`；`sources.md:43`）。
- **兩條直取路的差別**：`:104-127` 認 `sourceType`（曲目所屬平台），`:130-151` 認 `originalSource`（匯入時記下的原始平台）。前者是網易曲目、後者是外部匯入曲目。
- lrclib 預設**停用**（`disabledLyricsSources` 預設 `'lrclib'`，`data.md:345`）；預設優先序 `netease,qqmusic,lrclib`（`data.md:344`；同一字串寫在 4 檔 6 處，`sources.md:291`）。lrclib 的 User-Agent 是佔位網址 `FMP/1.0.0 (https://github.com/user/fmp)`（`lrclib_source.dart:24`；`features.md:445` 列為不一致）。
- 網易與 QQ 都標註「非官方 API，可能隨時變更，僅供學習研究」（`netease_source.dart:16-17`、`qqmusic_source.dart:18-19`）。

## 2. 自動匹配：觸發時機、評分、門檻

**觸發**：每次開始播一首新歌，由 `LyricsAutoMatchCoordinator.onTrackStarted` 在背景 fire-and-forget 跑，播放路徑不等它（`lib/services/audio/lyrics_auto_match_coordinator.dart:8-10,37-39,48-86`）。設定開關 `autoMatchLyrics` **預設關**（`data.md:341`；`lyrics_auto_match_coordinator.dart:57`）。coordinator 由 `AudioController` 接線（`lib/services/audio/audio_provider.dart:191,1404`）。

**前置條件**：已有匹配就跳過（`lyrics_auto_match_service.dart:90-94`）；同一首歌用 `_matchingKeys` 防併發（`:65,82-86`）；無啟用源就跳過（`:98-101`）。

**流程分支**（`lyrics_auto_match_service.dart:72-196`）：
1. 網易曲目 sourceId 直取（`:104-127`）→ 2. `originalSongId` 直取（`:130-151`）→ 3. 看 AI 模式：
   - `off`（預設）→ 正則標題解析後搜尋（`:192-196`）
   - `alwaysAi` → AI 標題解析後搜尋，AI 失敗退回正則（`:156-171`）
   - `advancedAiSelect` → AI 標題解析後，**把所有候選送 LLM 挑**，失敗退回正則（`:173-190`）

**評分（`_calculateScore`，`:851-895`）**：標題相似度 40% + 歌手相似度 30% + 時長分 20% + 有無同步歌詞 10%。時長分為階梯：≤3s → 1.0、≤10s → 0.8、≤容差 → 0.5、否則 0；容差是 `AppConstants.lyricsDurationToleranceSec`（**±20 秒**，`:692-696,777-781`）。相似度是 Levenshtein 正規化（`:900-944`），無 NFKC、無繁簡統一、無多歌手拆分 —— 這些是重寫後共用評分核心才加的（ADR 0019 決定 6）。

**門檻**：多個候選才評分，最高分須 ≥ `AppConstants.lyricsMatchScoreThreshold`（**0.6**）才採用（`:841-847`）；只有一個候選就直接用（`:701-703`）。網易／QQ 源結果 `duration == 0` 時**跳過時長過濾當作合格**（`:693,736`）。

**允許純文字歌詞**：`allowPlainLyricsAutoMatch` 預設 false（`data.md:347`）；未開時只接受有同步歌詞的結果（`_isAllowedLyricsResult`，`:223-229`）。

**結果寫入**：`_saveMatch` 同時寫歌詞內容快取（key 為 `track.uniqueKey`）與主資料庫 `LyricsMatch`（`lyricsSource`、`externalId`、`offsetMs=0`、`matchedAt`）（`:624-638`）。

## 3. 手動搜尋與選擇

- 入口：曲目選單「匹配歌詞」、播放頁「更多」（`features.md:166`）。UI 是 `showModalBottomSheet` 開的 `LyricsSearchSheet`（`lib/ui/pages/lyrics/lyrics_search_sheet.dart:21-30`）。
- 篩選：頂部 `FilterChip` 列「全部 + 各源」（`lyrics_search_sheet.dart:77-150`），來源順序取自 `lyricsSourceOrderProvider`（`lib/providers/audio/audio_settings_provider.dart:348`）；被停用的源仍顯示但標為 disabled（`lyrics_search_sheet.dart:78,138`）。每源的圖示／名稱是**寫死的 switch**（`:87-110`，`sources.md:333-335` 列為音源分支）。
- 搜尋：「全部」時按使用者優先序**並行**搜所有啟用源，再按優先序串接結果；單源時只搜該源；單源被停用則回空（`lib/providers/lyrics/lyrics_provider.dart:347-493`）。有 request id 防取代（`:383,483,487`）。
- 選定：點結果 `saveMatch` → 寫 `LyricsMatch`（`offsetMs=0`）並**先刪舊快取再寫新內容**，避免重新匹配後讀到舊歌詞（`lyrics_provider.dart:496-513`）。
- 移除匹配：`removeMatch` 只刪資料庫那筆（`:513-516`）。

## 4. 偏移（offset）調整與保存

- 保存位置：`LyricsMatch.offsetMs`（Isar 欄位，`docs/audit/data.md:46,359`）。語意為 `adjustedMs = position + offsetMs`，正值＝歌詞提前（`lib/services/lyrics/lrc_parser.dart:166,177`）。
- 主視窗：播放頁「更多」有偏移入口（`features.md:167`）；`lyrics_offset_bar.dart` 提供 ±100／500／1000ms 與重設（`lib/ui/widgets/lyrics/lyrics_offset_bar.dart:11,23`）；點歌詞行可 seek 到 `timestamp - offsetMs`（`lib/ui/widgets/lyrics/lyrics_display.dart:416-426`）。
- 桌面歌詞視窗：有偏移列（±）、點行跳轉、**右鍵某行校正偏移**（`features.md:170`）。校正公式 `line.timestamp - positionMs`，抽在 `LyricsOffsetMath.calibrationOffsetForLine`（`lib/ui/widgets/lyrics/lyrics_offset_math.dart:13,18`；子視窗 `_calibrateOffsetToLine` `lib/ui/windows/lyrics_window.dart:435`）。
- 子視窗改 offset 是**經 IPC 回主視窗**由 `LyricsSearchNotifier.updateOffset` 寫入資料庫（`lyrics_window.dart:448` → `lyrics_window_service.dart:479-485` → `lyrics_provider.dart:519-521`）。
- 顯示端只在 `externalId` 變時重抓內容，offset 變不重抓（`lyrics_provider.dart:134-146`）。

## 5. 歌詞格式、解析器、逐字／翻譯／羅馬音

- **只有 LRC 與純文字**。解析器是 `lib/services/lyrics/lrc_parser.dart`：時間戳正則 `\[(\d{1,2}):(\d{2})\.(\d{2,3})\]`（`:49`），一行多時間戳展開成多行（`:83-111`），2 位毫秒 ×10（`:99-102`），解析後排序（`:115`）。無時間戳則整首當純文字（`:120-131`）。二分搜尋找當前行（`:169-195`）。
- **逐字歌詞沒有實作**。全 `lib/`（不含 `*.g.dart`）grep `yrc` / `qrc` / `krc` / `逐字`（歌詞義）／`karaoke` / `verbatim` 皆無命中。網易只要求 `lv/tv/rv`，**沒有 `yv`（逐字）**（`netease_source.dart:214-222`）；QQ 的 `GetPlayLyricInfo` 只取 `lyric` 與 `trans`，**沒有 qrc/roma**（`qqmusic_source.dart:203-207`）。`LyricsResult` 也只有 `plainLyrics` / `syncedLyrics` / `translatedLyrics` / `romajiLyrics` 四欄，**沒有逐字欄位**（`lyrics_result.dart:2-20`）。
- **翻譯與羅馬音**：`LyricsResult` 有 `translatedLyrics` 與 `romajiLyrics` 兩欄（`:16-20`）。網易同時取翻譯（`tlyric`）與羅馬音（`romalrc`）（`netease_source.dart:89-92,215-221`）；**QQ 只有翻譯、沒有羅馬音**（`qqmusic_source.dart:71,206,268`）；lrclib 兩者皆無（`lrclib_source.dart` 只填 `plainLyrics`/`syncedLyrics`）。
- **合併方式**：以毫秒時間戳對齊，把附加歌詞塞進對應行的 `subText`（`lrc_parser.dart:137-160`，`LyricsLine.subText` `:12-18`）；顯示模式 `original` / `preferTranslated` / `preferRomaji`（enum `lib/ui/windows/lyrics_display_mode.dart:9-32`），選附加文本的優先序在 `lyrics_provider.dart:227-240`。已解析結果會被 provider 快取，避免每次 position tick 重解析（`lyrics_provider.dart:245`）。
- 純音樂判定：網易歌詞含「纯音乐，请欣赏」即視為 instrumental（`netease_source.dart:100-101`）。
- 標題解析器（把 B 站／YouTube 影片標題拆成曲名／歌手）是 `lib/services/lyrics/title_parser.dart`：`RegexTitleParser` 一組中日文標籤詞（`:46-52`）與 3 種擷取模式 —— 模式 A `Artist - Title`（`:109`）、模式 B `Artist「Title」`（`:112`）、模式 C `Title / Artist`（`:115`），加上括號／後綴清理，全失敗則整串當歌名（`parse` `:127`）。介面 `TitleParser` 設計上可換 AI 實作（`:34,39`）。

## 6. AI 功能（E10 / B5）

兩種模式，由 `LyricsAiTitleParsingMode` 控制：`off` / `alwaysAi`（只做標題解析）/ `advancedAiSelect`（標題解析＋候選挑選）（`docs/audit/features.md:169`；`lyrics_auto_match_service.dart:156,174`）。UI 在歌詞來源設定頁（`features.md:233`）。**預設 off**（`data.md:346`）。

**送出的欄位**：

| 用途 | 送出內容 | 證據 |
|---|---|---|
| 標題解析 | `title`、非空的 `uploader` | `ai_title_parser.dart:46-50` |
| 候選挑選 | `title`、`uploader`、`videoDescription`（截 500 字，目前傳 null）、`durationSeconds`、`sourcePriority`、`allowPlainLyricsAutoMatch`、`candidates[]`（id、source、優先序、曲名、歌手、專輯、時長、時長差、四種歌詞有無、**歌詞預覽**） | `ai_lyrics_selector.dart:106-116`；候選欄位 `:8-57`；預覽最多 8 行／500 字，跳過時間戳與 metadata 行（`lyrics_auto_match_service.dart:492-550`） |

- **傳送去向**：使用者自填的 OpenAI 相容端點，`Authorization: Bearer <key>`，`temperature 0.1`，system prompt 要求回嚴格 JSON（`lib/services/lyrics/openai_chat_client.dart:41-68`）。回應解析容忍 ```json 圍欄（`:82`）。
- **API key 存放**：secure storage，鍵 `lyrics_ai_api_key`（`lyrics_ai_config_service.dart:32,70-82`；`data.md:202,351`）。**不在** Settings、**不在**備份（`features.md:273`）。讀不到金鑰時丟 `SecureStorageUnavailable` 不吞成空字串（`:66-72`）。
- **endpoint / model / timeout 存 Settings**（`lyricsAiEndpoint` / `lyricsAiModel` / `lyricsAiTimeoutSeconds`，預設 timeout 20s），**AI endpoint 與 model 會進備份**（`data.md:348-350`；`features.md:298`）。
- **B5 的三個問題（現況即缺點）**：
  1. **端點不強制 https**：`normalizeOpenAiChatCompletionsEndpoint` 只 trim 尾斜線並補 `/chat/completions`，不檢查 scheme（`openai_chat_endpoint.dart:1-6`）；設定頁也**沒有** https 驗證（`lib/ui/pages/settings/lyrics_source_settings_page.dart` grep `https`／`validator`／`errorText` 皆無命中）。
  2. **debug 級別整份 payload 寫進 log**：`ai_lyrics_selector.dart:116`（含候選與歌詞預覽）、`ai_title_parser.dart:57`；另有回應原文 `ai_lyrics_selector.dart:145`、`ai_title_parser.dart:73`。ADR 0011 開頭把這件事列為舊專案的隱私缺陷（`docs/adr/0011-settings-and-logging.md:9-10`）。
  3. **影片描述欄位存在但未使用**：`videoDescription: null` 寫死（`lyrics_auto_match_service.dart:394`），`ai_lyrics_selector.dart:94-98` 支援截 500 字。
- **`LyricsTitleParseCache`**：AI 標題解析結果的持久化快取（`trackUniqueKey` unique、`parsedTrackName`、`parsedArtistName`、`confidence`、`provider`、`model`、時間戳；`data.md:47`）。先查快取再呼叫 LLM（`_titleParseCacheRepo.getReusable` `lyrics_auto_match_service.dart:556-561`、寫入 `:588`；資料庫不可用時直接回 null `:558`）。每次啟動都會跑 `_relinkLyricsMatchesToCidKeys` 修補鍵（`data.md:166`，見 §8 鍵的變動）。
- **artist 信心門檻**：AI 回 `artistName` 需 `artistConfidence >= 0.8` 才採用，否則丟棄（`ai_title_parser.dart:23,118-125`）；快取讀回時套同一個門檻（`lyrics_auto_match_service.dart:608`）。
- AI 標題解析結果是 `advancedAiSelect` 的輸入；`alwaysAi` 只用解析結果當搜尋關鍵字（``:254-266`）。AI 挑選回傳 `selectedCandidateId` 為 null 表「全部不像」就不匹配（`:413-420`）。

## 7. 顯示（播放頁 / 側欄）

- 顯示模式（原文／優先翻譯／優先羅馬拼音）在播放頁與桌面側欄面板（`features.md:165`），寫入 `lyricsDisplayModeIndex`（`data.md:343`）。
- 歌詞面板元件 `lib/ui/widgets/lyrics/lyrics_display.dart`：用 `scrollable_positioned_list`，自動捲到當前行（`:248,255`），使用者手動捲動時暫停自動捲、計時後恢復（`:279-290`）。**點歌詞行 seek**（`:321,421-426`）、**右鍵行**有次要動作（`:322`）。
- 當前行索引由 `currentLyricsLineIndexProvider` 提供（`lyrics_provider.dart:299`）；它每個 position tick 可能重算，但只在整數行號變化時通知；行號計算 `calculateCurrentLyricsLineIndex` 跳過非同步歌詞（`:283`，呼叫點 `:306`）。
- 歌詞欄有沒有內容決定寬版右欄要不要開（`lyricsPaneHasContentProvider`，`:261-281`）。
- 舊專案有兩個獨立的歌詞顯示實作：播放頁的 `lyrics_display.dart` 與桌面子視窗的 `lyrics_window.dart`（後者自帶 `_LyricsLine`、單行模式、樣式）。

## 8. 桌面歌詞視窗（E11）

**只有 Windows**。`LyricsWindowService.open()` 非 Windows 直接 return（`lib/services/lyrics/lyrics_window_service.dart:161-162`；`docs/audit/platforms.md:61-65`）。macOS / Linux 按鈕點了沒反應，而按鈕本身**沒有平台守衛**（`lib/ui/widgets/panels/track_detail_panel.dart:533-579`），`platforms.md:65` 推測 Android 寬版面也會看到沒作用的按鈕。

**機制**（`docs/audit/platforms.md:185-208`）：
- `desktop_multi_window` 0.3.1，開獨立 Flutter engine（`:271`）。子視窗靠命令列參數 `multi_window` 進入獨立入口 `lyricsWindowMain`（`lib/main.dart:95-98`）；該參數由套件原生端寫死（`platforms.md:204`）。
- 通訊：`WindowMethodChannel('lyrics_sync', mode: bidirectional)`（`lyrics_window_service.dart:119-122`；子視窗 `lyrics_window.dart:231-234`）。主→子：`updateLyrics`（`:307`）/ `updatePosition`（`:335`）/ `updateTheme`（`:394`）/ `updatePlaybackState`（`:415`）/ `updateLyricsDisplayMode`（`:430`）/ `close`（`:271`）。子→主：`seekTo`（`lyrics_window.dart:422`）/ `adjustOffset`（`:448`）/ `resetOffset` / `playPause`（`:392`）/ `next`（`:398`）/ `previous`（`:404`）/ `changeLyricsDisplayMode` / `changeLyricsWindowStyle` / `resetLyricsWindowStyle`（`:506`）/ `requestHide`（`:410`）（子視窗發送 `:392-506`；主視窗 handler `lyrics_window_service.dart:472-515`）。
- 子視窗只註冊 6 個插件（`platforms.md:205`）；原因是 tray/hotkey/window_manager 用全域 static channel，註冊到子 engine 會蓋掉主視窗（`platforms.md:205`，註解主張、**未在執行中驗證**）。
- 關閉用**隱藏不銷毀**，避免 window_manager channel 被清空（`lyrics_window_service.dart:252-266`，`close()` 只呼叫 `_controller.hide()` `:255`；`destroy()` 另在 `:267`；`platforms.md:206`）。等待 channel 就緒用輪詢 `ping`，最多 3 秒（`:235-249`）。
- 檢測子視窗被系統關掉：監聽 `onWindowsChanged` 再比對 `WindowController.getAll()`（`:440-465`）。

**視窗行為**（`lib/ui/windows/lyrics_window.dart`）：
- 初始化：`setSize(400,500)`、`setMinimumSize(400,300)`、**`setAlwaysOnTop(true)`**、隱藏標題列、置中、show/focus（`:253-267`；尺寸常數 `lyrics_window_style.dart:7-25`）。
- 置頂可切換：`_alwaysOnTop` 預設 true，切換呼叫 `windowManager.setAlwaysOnTop`（`:205,739`）。
- 透明模式：`setAsFrameless()` + `setHasShadow(false)` + `setBackgroundColor(transparent)`；離開透明模式還原標題列樣式、陰影、表面色（`:524-542`）。透明模式下 hover 才顯示半透明底與工具列（`:631-667,846-850`）。
- **沒有滑鼠穿透**：全 `lib/` grep `setIgnoreMouseEvents` / `IgnoreMouse` / `clickThrough` / `點擊穿透` 皆無命中。舊專案只有「透明」與「置頂」，`features.md:170` 的功能清單也只列到透明與置頂。
- **沒有鎖定（lock）**：全檔 grep `lock`（UI 義）無命中。透明模式下靠「hover 才顯示工具列」降低誤觸，但沒有鎖定模式。
- 單行模式：`_singleLineMode` 切「單行」與「整頁」，UI 在 `lyrics_single_line_view.dart`（`lyrics_window.dart:209,623,726-727`）。
- 樣式：文字色、次要色、非當前行透明度、外框（色／寬）、陰影（色／模糊／位移），11 個欄位存 Settings（`lyrics_window_style.dart:66-106`；`data.md:352`）。樣式改動經 250ms debounce 才送主視窗（`lyrics_window_style.dart:27-63`）。樣式對話框是 `lib/ui/widgets/lyrics/lyrics_style_dialog.dart`。
- 主視窗推資料的**呼叫點全在 `TrackDetailPanel` 這個 UI widget 的 `ref.listen`**（`features.md:173`）—— 面板只在 expanded 以上寬版面且有曲目時掛載（`lib/ui/layouts/responsive_scaffold.dart:124-141,363-365,514`），收起仍掛載（`OverflowBox` 藏起 `:498-520`）。`features.md:173` 推測縮到 compact/medium 或全螢幕播放頁蓋住 shell 時可能停止更新（**未實測**）。這是一個架構缺陷：同步邏輯綁在 UI 生命週期上。

**移殖到其他平台需要的**（`platforms.md:208,351,369,410`）：Windows 端已在 `main.cpp` 加 `multi_window` 判斷跳過單一實例 mutex（`:331`）並選擇性註冊子視窗插件（`:334`）；macOS 要在 `MainFlutterWindow.swift`、Linux 要在 `my_application.cc` 加子視窗插件註冊（套件 README），並放寬 `isWindows` 守衛。

## 9. 舊 static-rule `lyrics_window_strings` 守什麼

- 檔案：`test/services/static_rules/lyrics_window_strings_static_rule_test.dart`（`docs/audit/engineering.md:279`；`.trellis/spec/ui/widgets.md:101`）。
- 守的性質：**子視窗讀的每一個翻譯字串 key，都必須有人從主視窗推過去**（`lyrics_window_strings_static_rule_test.dart:21-51`）。
- 為什麼需要：子視窗是獨立 runApp 進入點，拿不到主 isolate 的 slang 實例，所以自帶一份簡體 fallback；漏推一個 key 不會壞，只是顯示未翻譯的簡體（`:22-24`）。
- 怎麼做：從 `lyrics_window.dart` 的 `updateFrom` 本體掃 `map['key']` 取出「被讀的 key 集合」（`consumedStringKeys`，`:91-115`，只掃 `updateFrom` 本體、去註解），與 `syncTheme` 實際推的 `strings` map 比對，要求**兩集合相等**（`:35-48`）——「讀了沒推」會 fallback、「推了沒讀」是死鍵，兩邊都抓。
- 這條規則依賴「字串用 map 推、不是型別化訊息」。`docs/audit/engineering.md:279` 標它對「寫法變化、註解」敏感（無閘門守「推送機制本身」）。重寫若改成型別化 IPC 訊息，這條規則自然消失（見 `.trellis/tasks/archive/2026-09/09-27-design-testing/design.md:153` 的判斷）。

## 10. 快取與持久化

- **歌詞內容快取**：檔案式，`{cacheDir}/lyrics/*.json`，鍵為 base64url(`track.uniqueKey`)（`lib/services/lyrics/lyrics_cache_service.dart:63-64,268-272`）。上限：檔數 `Settings.maxLyricsCacheFiles`（預設 50，可調，UI 範圍 10–200）＋總量硬性 5 MB，按存取時間 LRU 淘汰（`:18-19,203-244`；`data.md:224,342`）。存取時間寫 `_metadata.json`，2 秒 debounce（`:39,311-320`）。**無 TTL**（`data.md:224`）。設定頁「清除歌詞快取」→ `clear()`（`:141-158`）。
- **匹配結果**：Isar `LyricsMatch`，只存 `externalId` 不存歌詞內容（`data.md:46,225`）。淘汰快取後可用存下的 id 重抓、不重新匹配（ADR 0016 決定 4，`docs/adr/0016-cache-and-offline.md:41`）。
- 重寫定案：歌詞內容快取改放**統一快取庫**（鍵為歌詞插件＋歌詞 id，只靠 LRU）；匹配結果存主資料庫 —— 淘汰後以存下的 id 重抓、不重新匹配（ADR 0016 決定 1、4；`0016-cache-and-offline.md:31,41`）。
- **鍵的坑**：`trackUniqueKey` 是 `sourceType:sourceId[:cid]`；B 站回填 cid 後鍵從兩段變三段，舊的兩段式鍵匹配會失聯（ADR 0005；`docs/audit/data.md:54,166`）。重寫後改用關聯表＋外鍵（ADR 0010/0019）。

## 11. 與重寫定案的落差（給設計的輸入）

| 舊專案 | 重寫定案 | 證據 |
|---|---|---|
| 三源各自 Dart 類別、字串分派 5 處 | 全部改為 JS 腳本插件，帶 `lyrics` 能力宣告，同一能力多提供者全列 | ADR 0014 決定 2、4（`docs/adr/0014-script-source-plugins.md:35,38`） |
| 每源自寫評分（Levenshtein、±20s、0.6） | 宿主**一份共用評分核心**：NFKC→小寫→繁簡統一(opencc)→去標點→括號分開比；`string_similarity`(Dice)；時長「10 秒或 5% 取寬」；多歌手拆開取最佳；歌詞另加同步歌詞加分；同分依使用者排序；結果持久化、改選後不重算 | ADR 0014 決定 9；ADR 0019 決定 6（`0019-library-and-sync.md:61-66`） |
| `Track.originalSongId/originalSource` 一組 | `track_origins`（原始平台 id）可供歌詞直取，涵蓋 Spotify／QQ 匯入 | ADR 0019 決定 5（`0019:58-59`） |
| 歌詞內容在自製檔案快取、匹配在 Isar | 統一快取庫＋主資料庫關聯表 | ADR 0016 決定 1、4 |
| 只有 LRC／純文字，無逐字 | 未定案（本任務要研究） | 本檔 §5 |
| 同步邏輯綁在 `TrackDetailPanel` 的 `ref.listen` | 未定案；重寫的 provider 邊界另有規定 | `features.md:173`；AGENTS.md § Providers |
| AI 端點不強制 https、payload 進 debug log | B5 方向：AI 歌詞保留、**預設關**、**強制 https**、**payload 不寫進 log**、送出欄位最小化並在設定頁列出 | 任務背景 + `questions.md:119` |
| 桌面歌詞視窗只開 Windows，按鈕無平台守衛 | ADR 0009：托盤、快捷鍵、**歌詞視窗**等都在平台層以能力宣告處理，目標全桌面平台一致 | ADR 0009（`0009-platform-layer-with-declared-capabilities.md:40`）；`platforms.md:14,410` |

## 12. 查不到 / 待確認

- **點擊穿透（click-through）與鎖定**：舊專案查無實作（§8 已 grep 全 `lib/`）。任務描述把「穿透點擊、鎖定」列為要研究的項目，但舊專案的歌詞視窗**兩者都沒有**；若重寫要做，屬新增功能，非搬運。
- **逐字歌詞**：舊專案完全沒有，沒有可搬的實作。
- **`advancedAiSelect` 的實際效果**：候選挑選的品質、成功率、成本查不到（未打 API、無量測資料）。
- **macOS / Linux 上歌詞視窗的實際行為**：程式碼只到「按了沒反應」，沒有實機驗證紀錄（`platforms.md:65,182` 為事實／推測標註）。
- **`desktop_multi_window` 0.3.1 在 macOS/Linux 的可用度**：audit 引套件 README 說支援，但舊專案從未在那些平台註冊子視窗插件，**未實測**。
