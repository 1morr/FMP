# 成熟產品的歌詞功能（prior art）

- 查證日期：2026-09-28
- 查證方式：tavily-search / tavily-extract / GitHub permalink（各節註明）

## 閱讀說明

- 所有 GitHub 連結都是**固定 commit SHA 的 permalink**。SHA 由 `gh api repos/<owner>/<repo>/commits?per_page=1` 取得，檔案內容由 `gh api repos/<owner>/<repo>/contents/<path>?ref=<sha>` 讀取。
- 本報告只寫「讀到的程式碼／文檔說了什麼」。沒查到的主題一律寫「查不到」；由間接證據推論的寫「推測」。
- 各產品的 HEAD SHA（本報告寫作時）：

  | 產品 | repo | HEAD SHA |
  |---|---|---|
  | Namida | `namidaco/namida` | `e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5` |
  | Spotube | `KRTirtho/spotube` | `69a310c78f5ceaf4eab7dfee98f187d38211c9ba` |
  | LX Music Desktop | `lyswhut/lx-music-desktop` | `ad95d5091c9ed689fa72b5e5c849df65f5a679ce` |
  | LX Music Mobile | `lyswhut/lx-music-mobile` | `fb8480728d875fa5e0da25eebd3a26bb71723aae` |
  | MusicFree | `maotoumao/MusicFree` | `d118b18b3d0c904400f7eea7bf99c0ceec6c1aee` |
  | Harmonoid | `harmonoid/harmonoid` | `2b021f7b0b5dbcbe027aec010580977a2939a28d` |
  | BetterLyrics | `jayfunc/BetterLyrics` | `97629ddf085877cdc90de8cb56006a023320fe00` |
  | Lyricify-App | `WXRIW/Lyricify-App` | `2aad11e7404fc3770a90da4fa4c4403e3b7ad0f1` |
  | Lyricify-Lyrics-Helper | `WXRIW/Lyricify-Lyrics-Helper` | `cabe0b71d443a9b882a35c60c4f7f21addcbe751` |

---

## 1. Namida（Flutter，Android / Windows / Linux）

查證方式：tavily-search（定位 repo）＋ GitHub permalink（逐檔讀取，SHA 見上表）。

### 1.1 歌詞源插件化：沒有插件，硬編碼 + 本地檔案

歌詞**不是**插件機制。來源列舉寫死在 enum 裡：

- `LyricsSource { auto, local, internet }`（優先序設定，不是來源清單）
- `LyricsProvider { lrclib, kugou }`
  → [`lib/core/enums.dart#L750-L759`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/core/enums.dart#L750-L759)

實際的取得順序（`Lyrics._updateLyrics` → `_fetchLRCBasedLyrics`）是：

1. 音檔同目錄的 `.lrc`（`firstDeviceLRCFile()`）
2. 自家歌詞快取目錄的 `.lrc`
3. 音檔內嵌 tag 歌詞（`embeddedLyrics`）
4. 網路：LRCLIB 與 KuGou（`_LRCProvidersSearcher`，`allProviders` 時 KuGou 取 3 筆、否則 1 筆）
5. 以上都沒有 → `.txt` 快取 → 內嵌純文字 → 最後手段是**爬 Google 搜尋結果**（`_fetchLyricsGoogle` 打 `https://www.google.com/search?...`，再用 regex 去 HTML 標籤）

→ [`lib/controller/lyrics_controller.dart`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/lyrics_controller.dart)、
[`lib/controller/lyrics_search_utils/lrc_search_utils_base.dart`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/lyrics_search_utils/lrc_search_utils_base.dart)

搜尋字串由來源型別決定：本機曲目用「藝人 - 標題 + 專輯 + 時長」（`searchDetailsQueries()`），YouTube 曲目用「影片標題 lyrics」（`searchQueriesGoogle()`）。
→ [`lrc_search_utils_selectable.dart`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/lyrics_search_utils/lrc_search_utils_selectable.dart)、[`lrc_search_utils_youtubeid.dart`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/lyrics_search_utils/lrc_search_utils_youtubeid.dart)

### 1.2 匹配與手動改選：有候選清單，選完寫入快取

- 自動匹配就是上面那條固定優先序，最後用網路搜尋的**第一筆**（`lyrics.firstOrNull`）。
- 手動改選在 `showLRCSetDialog(item, colorScheme)`：把「內嵌 / 快取 txt / 快取 lrc / 裝置 lrc」放進 `availableLyrics`，把網路搜尋結果放進 `fetchedLyrics`（用 `onPartial` 串流進來、邊搜邊顯示），使用者可選、可**編輯**、可**刪除**。
  → [`lib/ui/dialogs/set_lrc_dialog.dart`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/ui/dialogs/set_lrc_dialog.dart)
- 改了會不會記住：會。選定後寫進 `cachedLRCFile` / `cachedTxtFile`（檔名是曲目的 cache key），下次同一首直接命中快取，不再打網路。
- 另有 `LrcFingerprint`：去掉 metadata 行、時間戳統一降到 centisecond，用來**去重**同一批候選，避免同一份歌詞出現兩次。
  → [`lib/class/lyrics.dart`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/class/lyrics.dart)

### 1.3 逐字歌詞與翻譯：逐字有，翻譯存疑

- 有 **卡拉 OK 逐字**。parser 有三個：`parser_lrc`、`parser_qrc`、`parser_smart`（自動判斷）。
  - `LRCParserQrc` 解 `[start,duration]` 進階標籤與 `(start,duration)` 逐字標籤，產出 `spanList: List<LyricSpanInfo>`（每個字 span 的 `start` / `duration` / `length`）。
  - 渲染端有 `_KaraokeLayout` / `_KaraokeTextPainter`，註釋寫 "Karaoke-style word-synced line"，並有 `karaokeShimmer` 效果。
  → [`lib/packages/lyrics_parser/parser_qrc.dart`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/packages/lyrics_parser/parser_qrc.dart)、[`lib/packages/lyrics_parser/models.dart`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/packages/lyrics_parser/models.dart)、[`lib/packages/lyrics_lrc_parsed_view.dart#L1258`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/packages/lyrics_lrc_parsed_view.dart#L1258)
- 資料格式：LRC（`[mm:ss.xx]`）與 QRC。**沒有** KRC / YRC / TTML 的 parser。
- 翻譯／羅馬音：`LyricsLineModel` 有 `extText` 欄位（延伸歌詞）與 parser 的 `isMain` 參數，`LRCParserLrc` 在 `isMain == false` 時把文字寫進 `extText`，形式上留了「主歌詞 + 延伸歌詞」的位置；但**本次查證的 controller 只抓單一 LRC，沒有看到抓翻譯源或翻譯開關的程式碼** → 翻譯支援程度**查不到**（推測：欄位預留、未實作完整）。

### 1.4 桌面歌詞：有，獨立迷你歌詞視窗（desktop）

- `MiniLyricsWindow`（[`lib/ui/widgets/mini_lyrics_window.dart`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/ui/widgets/mini_lyrics_window.dart)），在 `lib/main.dart` 依 `NamidaWindowManager.isMiniLyricsMode` 切換顯示。
- `enterMiniLyricsMode()` 的做法（[`window_manager_desktop.dart#L94-L121`](https://github.com/namidaco/namida/blob/e8363dbf1cc1efb9cb9be58b409b60b692fe1eb5/lib/controller/platform/window_manager/window_manager_desktop.dart#L94-L121)）：
  - `setAsFrameless()`、`setHasShadow(false)`、`setBackgroundColor(transparent)`、`setMinimumSize(kMiniLyricsMinSize)`
  - **置頂**：`setAlwaysOnTop(true)`
  - **不佔工作列**：`setSkipTaskbar(true)`，另有 `setVisibleOnAllWorkspaces(true)`
  - 記住 bounds（`settings.extra.miniLyricsWindowBounds`），退出時還原原本視窗狀態
  - 以邊緣 grip 自行實作 `windowManager.startResizing(edge)`
- **點擊穿透：沒有**。程式碼裡沒有 `setIgnoreMouseEvents` 之類用法；相反地視窗用 `_hovering` 狀態在 hover 時顯示控制列 —— 它是一個可互動、可拖曳的正常視窗。
- 平台：走 `window_manager` 桌面路徑，程式碼中有 `Platform.isWindows` 與 `Platform.isLinux` 分支（後者是標題列重新裝飾的處理）。macOS 沒有特別分支，**能不能跑未確認**。
- 觸發入口：托盤選單（`TrayMenuKey.miniLyricsWindow`）、桌面快捷鍵、`main_page_wrapper.dart` 的按鈕。

### 1.5 AI / LLM：查不到

沒有發現任何 LLM 相關程式碼或設定。

---

## 2. Spotube（Flutter，跨平台）

查證方式：`gh search code` 定位 ＋ GitHub permalink 逐檔讀取 ＋ README/CHANGELOG 對照。

### 2.1 歌詞源插件化：單一硬編碼來源 LRCLIB

- 歌詞**不是**插件。整個 `lib/provider/lyrics/` 只有一個檔案 `synced.dart`，只有一個 provider：`getLRCLibLyrics()`。
  → [`lib/provider/lyrics/synced.dart`](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/provider/lyrics/synced.dart)
- 打的是 `https://lrclib.net/api/get`，query 參數 `artist_name` / `track_name` / `album_name` / `duration`（秒），Header 帶標明版本與 repo 的 `User-Agent`。回傳取 `syncedLyrics`，沒有就用 `plainLyrics` 逐行拆成 `time == Duration.zero` 的假同步歌詞。
- README 的 features 寫 "Time synced lyrics regardless of the plugin support"，服務清單列 "LRCLib - A public synced lyric API"。
  → [`README.md`](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/README.md)
- CHANGELOG 顯示演進：早期有「use official spotify API for fetching lyrics」、「add LRCLIB lyrics provider as fallback」、後來「fallback to LRCLIB when lyrics line less than 6 lines」、「LRCLIB lyrics should be usable without logging in」。**HEAD 的程式碼只剩 LRCLIB 一條路**。
  → [`CHANGELOG.md`](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/CHANGELOG.md)

### 2.2 匹配與手動改選：精確查詢，無候選清單

- `/api/get` 是**精確查詢**（不是 search API），沒有候選清單、也沒有手動改選 UI。
- 快取：drift 表 `LyricsTable { id, trackId, data }`，用 track id 當 key（`InsertMode.replace`）。快取命中條件包含「歌詞行數 > 5」，太短會重抓。
  → [`lib/models/database/tables/lyrics.dart`](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/models/database/tables/lyrics.dart)
- 模型 `SubtitleSimple { uri, name, lyrics, rating, provider }`，`rating` 是 provider 自報的分數（LRCLIB 同步歌詞給 100、純文字給 0），並記錄 `provider: "LRCLib"`。
  → [`lib/models/lyrics.dart`](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/models/lyrics.dart)

### 2.3 逐字歌詞與翻譯：都沒有

- 模型只有 `LyricSlice { Duration time; String text }` → **逐行**，無逐字。
- 播放器歌詞頁是兩個 tab：Synced 與 Plain（`PlayerLyricsPage` 的 `TabItem`）。
  → [`lib/pages/player/lyrics.dart`](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/pages/player/lyrics.dart)
- 翻譯／羅馬音：在 repo 內 `gh search code "translation"` 沒有命中歌詞相關程式碼 → **查不到**。
- 格式：LRC，用 pub 套件 `lrc` 解析（README 的 Dependencies 有列）。
- 同步機制：`useSyncedLyrics` 把 `lyricsMap` 轉成 `{秒: 文字}`，用 `audioPlayer.positionStream` 比對，另有 `syncedLyricsDelayProvider` 讓使用者調延遲。
  → [`lib/modules/lyrics/use_synced_lyrics.dart`](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/modules/lyrics/use_synced_lyrics.dart)

### 2.4 桌面歌詞：有 mini lyrics 視窗，置頂／穿透查不到

- `MiniLyricsPage`（[`lib/pages/lyrics/mini_lyrics.dart`](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/pages/lyrics/mini_lyrics.dart)），route 是 `/mini-player`（[`lib/collections/routes.dart`](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/collections/routes.dart)）。
- 做法：半透明背景（`background.withValues(alpha: 0.4)`）、`MouseRegion` 做到 hover 才顯示控制列，桌面平台另用 `window_manager` 讀 `isMaximized()` 記住最大化狀態。
- 平台判定：`kIsDesktop = kIsLinux || kIsWindows || kIsMacOS`。
  → [`lib/utils/platform.dart`](https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/utils/platform.dart)
- **置頂（always-on-top）與點擊穿透：查不到** —— 沒有在這次讀到的檔案裡看到 `setAlwaysOnTop` / `setIgnoreMouseEvents` 的呼叫。
- CHANGELOG 有 "mini_player: show/hide lyrics"、"jump to specific time on lyric click"（點歌詞跳時間）等條目。

### 2.5 AI / LLM：查不到

沒有發現任何 LLM 相關程式碼。

---

## 3. LX Music（Desktop = Electron/Vue，Mobile = React Native）

查證方式：`gh search code` 定位 ＋ GitHub permalink 逐檔讀取；zh-cn / zh-tw / en-us 語系檔對照設定語意。

### 3.1 歌詞源插件化：內建音源各自 `getLyric` + 使用者自訂音源腳本

- 內建音源目錄 `src/renderer/utils/musicSdk/`：`wy`（網易雲）、`tx`（QQ）、`kg`（酷狗）、`kw`（酷我）、`mg`（咪咕）、`bd`（百度）、`xm`（蝦米），每個都有 `getLyric()`。
  → [`src/renderer/utils/musicSdk`](https://github.com/lyswhut/lx-music-desktop/tree/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/renderer/utils/musicSdk)
- **使用者自訂音源腳本**（`src/main/modules/userApi/`，事件 `import_user_api` / `remove_user_api`）會被掛上同一組介面，包含 `getLyric`：
  `apis[source].getLyric = (songInfo: LX.Music.MusicInfo) => {...}`
  → [`src/renderer/core/useApp/useInitUserApi.ts`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/renderer/core/useApp/useInitUserApi.ts)
  → 這就是 LX 的「歌詞插件化」：自訂音源可以自己帶歌詞來源。
- 歌詞資料結構 `LX.Music.LyricInfo` 四欄：`lyric`（主歌詞）、`tlyric`（翻譯）、`rlyric`（羅馬音）、`lxlyric` / `lxlrc`（LX 自有逐字格式）。
  → 桌面歌詞視窗的 IPC 合約 [`src/common/types/desktop_lyric.d.ts`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/common/types/desktop_lyric.d.ts) 裡 `set_info` 帶 `lrc / tlrc / rlrc / lxlrc`。

### 3.2 匹配與手動改選：自動換源，無候選清單

- `getLyricInfo({ musicInfo, isRefresh, allowToggleSource = true, onToggleSource })`
  → [`src/renderer/core/music/online.ts#L83-L103`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/renderer/core/music/online.ts#L83-L103)
  行為：先查快取（`getCachedLyricInfo`）；沒有就抓，抓不到時**自動換源**（拿同一首歌在別的平台抓歌詞），成功後 `saveLyric(targetMusicInfo, lyricInfo)` 存起來 —— 注意存的是**實際抓到的來源**那份（`targetMusicInfo.id != musicInfo.id` 時存 target）。
- 手動候選清單：**查不到**。整份 repo 裡只有酷狗內部用的 `searchLyric(name, hash, time, tryNum)`，沒有看到「列出多份歌詞讓使用者挑」的 UI 或入口。
- 可手動調的只有**歌詞偏移**（`setLyricOffset`）與換源。

### 3.3 逐字歌詞與翻譯：完整（含獨門格式）

- 設定項（語系檔 zh-tw）：
  - `player.isShowLyricTranslation`「顯示歌詞翻譯」
  - `player.isShowLyricRoma`「顯示歌詞羅馬音」
  - `player.isSwapLyricTranslationAndRoma`「交換翻譯與羅馬音順序」
  - `player.isPlayLxlrc`「使用卡拉 OK 式歌詞播放（如果可用）」，其 tooltip 明說「此功能比較耗性能，低配置電腦不建議開啟」
  → [`src/lang/zh-tw.json`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/lang/zh-tw.json)、[`src/renderer/views/Setting/components/SettingPlay.vue`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/renderer/views/Setting/components/SettingPlay.vue)
- 渲染端的擴充歌詞是**疊加**上去的：`extendedLyrics.push(lyrics.tlyric)` / `rlyric`，交給 `lrc-file-parser` 這類播放器一起算行。
  → [`src/renderer-lyric/core/lyric.ts`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/renderer-lyric/core/lyric.ts)
- 各來源逐字格式：`tx` 用 `decodeQrc`（QRC 解密）、`kg` 用 KRC（`src/common/utils/lyricUtils/kg.js`）、`wy` 產 YRC、加上 LX 自有的 `lxlrc`。
- **下載歌詞**時可輸出：`.lrc`、`tlrc:`（base64 編碼的翻譯行）、以及 AWLRC 格式；`buildAwlyric` 就是組這個。
  → [`src/renderer/worker/download/lrcTool.ts`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/renderer/worker/download/lrcTool.ts)
- 同檔還有 `filterExtendedLyricLabel()`：把翻譯/羅馬音的時間標籤**過濾成只留主歌詞也有的時間戳**（再用 `[t1][t2]文字` 合併）—— 這是翻譯行與主歌詞對齊的實作。

### 3.4 桌面歌詞：最完整的一套，真的跨平台

- 獨立的 Electron `BrowserWindow`「winLyric」模組：[`src/main/modules/winLyric/`](https://github.com/lyswhut/lx-music-desktop/tree/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/main/modules/winLyric)（`config.ts` / `main.ts` / `mouseCheckTools.ts` / `rendererEvent.ts`），前端是獨立 renderer `src/renderer-lyric/`（橫向 / 縱向兩種版面、可顯示頻譜 `AudioVisualizer.vue`）。
- 設定面（`desktopLyric.*`，見 [`src/common/types/desktop_lyric.d.ts#L3-L45`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/common/types/desktop_lyric.d.ts#L3-L45)）：
  `enable`、`isLock`、`isAlwaysOnTop`、`isAlwaysOnTopLoop`、`isShowTaskbar`、`isLockScreen`、`pauseHide`、`isHoverHide`、`isDelayScroll`、`scrollAlign`、`direction`、`audioVisualization`、`width/height/x/y`，以及一整套 `style.*`（align、font、fontSize、lineGap、lyricUnplayColor、lyricPlayedColor、lyricShadowColor、opacity、ellipsis、isFontWeightFont/Line/Extended、**isZoomActiveLrc**）。
- **置頂**：`setAlwaysOnTop(flag, level)`，並有 `alwaysOnTopTools.startLoop()` 週期性重設置頂（註釋說明 Linux 每次重開要重設）。`isAlwaysOnTopLoop` 是給這個循環用的開關。
  → [`src/main/modules/winLyric/config.ts`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/main/modules/winLyric/config.ts)
- **鎖定 / 點擊穿透**：`browserWindow.setIgnoreMouseEvents(true, { forward: !isLinux && isHoverHide })`
  → [`src/main/modules/winLyric/main.ts#L78`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/main/modules/winLyric/main.ts#L78)、[`main.ts#L187-L190`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/main/modules/winLyric/main.ts#L187-L190)
  因為穿透後收不到 mouseleave，另外用 `mouseCheckTools.runCheck(sendMouseLeave)` **輪詢游標位置**來實作 hover 隱藏（`isHoverHide`）。
- **平台差異**（程式碼明說）：
  - Linux：`setIgnoreMouseEvents` 的 `forward` 選項不支援（所以 `!isLinux` 才開）、每次重開視窗要重設置頂、**不能把視窗設到螢幕外**（所以只有 Windows 會強制把被移走的視窗拉回設定值）。
  - macOS：`main.ts` 註解直寫「MacOS未知」。
  - 平台：Windows / Linux / macOS 都支援（Electron），但細節處理以 Windows 最完整。
- **Mobile 版**：Android 用原生 overlay window 做桌面歌詞／狀態欄歌詞（`android/app/src/main/java/cn/toside/music/mobile/lyric/`：`LyricView.java`、`LyricPlayer.java`、`LyricTextView.java`），RN 端 [`src/core/desktopLyric.ts`](https://github.com/lyswhut/lx-music-mobile/blob/fb8480728d875fa5e0da25eebd3a26bb71723aae/src/core/desktopLyric.ts)，可調 `isSingleLine` / `maxLineNum` / `isLock` / `position` / `opacity` / `textSize` / `showToggleAnima`，權限走 `checkOverlayPermission`。另有**藍牙歌詞**（設定 `IsShowBluetoothLyric`）。
- LX Mobile 的字串處理獨立成 [`src/plugins/lyric.ts`](https://github.com/lyswhut/lx-music-mobile/blob/fb8480728d875fa5e0da25eebd3a26bb71723aae/src/plugins/lyric.ts)：`setLyric(lyric, translation?, romalrc?)` 把翻譯與羅馬音當 `extendedLyrics` 一起餵給 `lrc-file-parser`。

### 3.5 AI / LLM：查不到

沒有發現任何 LLM 相關程式碼。

---

## 4. MusicFree（React Native）

查證方式：`gh search code` 定位 ＋ GitHub permalink 逐檔讀取。這是本次查證中**插件化最徹底**的一個。

### 4.1 歌詞源插件化：完全靠插件

- 插件 API 直接定義了歌詞能力：
  ```ts
  /** 获取歌词 */
  getLyric?: (
      musicItem: IMusic.IMusicItemBase,
  ) => Promise<ILyric.ILyricSource | null>;
  ```
  → [`src/types/plugin.d.ts#L101-L103`](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/types/plugin.d.ts#L101-L103)
- 回傳型別：`ILyricSource { lrc? (deprecated, 歌詞 url)、rawLrc? (純文字歌詞)、translation? (純文字翻譯) }`；另有 `ILyricItem extends IMusic.IMusicItem { rawLrcTxt? }`。
  → [`src/types/lyric.d.ts`](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/types/lyric.d.ts)
- 插件宣告自己支援的搜尋類型，其中包含 `"lyric"`：
  `SupportMediaType = "music" | "album" | "artist" | "sheet" | "lyric"`
  → [`src/types/common.d.ts#L3-L8`](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/types/common.d.ts#L3-L8)
- 宿主用 `getSearchablePlugins("lyric")` 過濾出「能搜歌詞的已啟用插件」。
  → [`src/core/pluginManager/index.ts#L504-L515`](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/core/pluginManager/index.ts#L504-L515)
- → 網易 / QQ / lrclib 等全部是社群插件，不是內建清單。

### 4.2 匹配與手動改選：跨插件自動匹配 + 每插件一個 tab 的候選清單，且會記住

`src/core/lyricManager.ts` 的 `refreshLyric()`：

1. 先問**當前歌曲所屬插件**的 `getLyric`（`pluginManager.getByMedia(currentMusicItem)?.methods?.getLyric(...)`）。
2. 拿不到且設定 `lyric.autoSearchLyric` 開啟 → `searchSimilarLyric(musicItem)`：
   - 取 `getSearchablePlugins("lyric")`，**跳過當前歌曲自己那個平台**；
   - 用 `musicItem.alias || musicItem.title` 當關鍵字，每個插件搜尋、**只取前 2 筆**；
   - 先用 `item.title === keyword && item.artist === musicItem.artist` 直接判定距離 0，否則算 `minDistance(keyword, title) + minDistance(artist, artist)`（編輯距離）；
   - 取全域最小距離那筆，叫該插件 `getLyric` → **跨插件自動匹配**（全區域距離歸零就提前 break）。
3. 手動改選：`SearchLrc` panel —— 輸入框（預設 `alias ?? title`）＋ `TabView` 每個插件一個 tab 的候選清單，按下去執行 `lyricManager.associateLyric(currentMusic, item)`。
   → [`src/components/panels/types/searchLrc/index.tsx`](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/components/panels/types/searchLrc/index.tsx)、[`LyricList.tsx`](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/components/panels/types/searchLrc/LyricList.tsx)、[`useSearchLrc.ts`](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/components/panels/types/searchLrc/useSearchLrc.ts)
4. **記住**：`associateLyric()` 把 `patchMediaExtra(musicItem, { associatedLrc: linkToMusicItem })` 寫進該曲目的 mediaExtra；`unassociateLyric()` 清除。另有 offset `patchMediaExtra(musicItem, { lyricOffset: offset })`。
5. 也能**手動上傳本機歌詞**：`uploadLocalLyric()` 依 `localLrcPath/<md5(platform)>/<md5(id)>.lrc`（翻譯是 `.tran.lrc`）寫檔，`removeLocalLyric()` 刪除。

### 4.3 逐字歌詞與翻譯：翻譯有，逐字沒有

- 翻譯：`ILyricSource.translation`。解析在 [`src/utils/lrcParser.ts`](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/utils/lrcParser.ts)：用**雙指標**依「時間戳完全相等」把翻譯行併進 `IParsedLrcItem.translation`（不相等就填空字串），並設 `hasTranslation`。UI 開關是 `PersistStatus` 的 `lyric.showTranslation`（[`lyricOperations.tsx`](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/pages/musicDetail/components/content/lyric/lyricOperations.tsx)）。
- 逐字：**沒有**。`IParsedLrcItem { time, lrc, translation?, index }` 只有行級時間；渲染元件 `lyricItem.tsx` 就是一個 `<Text>`（只有 normal / highlight / light 三態）。
  → [`src/pages/musicDetail/components/content/lyric/lyricItem.tsx`](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/src/pages/musicDetail/components/content/lyric/lyricItem.tsx)
- 羅馬音：**查不到**。
- 格式：自寫 LRC parser（`[mm:ss.xx]`、`[key:value]` metadata、支援 `offset` meta 並與使用者 offset 疊加）。
- 歌詞面板可調：字級（`lyric.detailFontSize`）、偏移（`SetLyricOffset`）、搜尋改選。

### 4.4 桌面歌詞：Android 浮動歌詞窗 + 狀態欄歌詞（不是桌面 OS 的桌面歌詞）

- Android 原生 overlay：[`android/app/src/main/java/fun/upup/musicfree/lyricUtil/LyricView.kt`](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/android/app/src/main/java/fun/upup/musicfree/lyricUtil/LyricView.kt)
  - `WindowManager.LayoutParams.type = TYPE_APPLICATION_OVERLAY`（API < O 用 `TYPE_SYSTEM_ALERT`）
  - 可設定項：`topPercent` / `leftPercent` / `widthPercent` / `align` / `color` / `backgroundColor` / `fontSize`
  - 有 `OrientationEventListener`（轉向重算）與 `onTouch`（目前直接 `return false`）
- 「狀態欄歌詞」：`LyricUtil.setStatusBarLyricText(歌詞 + 可選翻譯)`，在換歌與換行時更新；設定 `lyric.showStatusBarLyric`、`lyric.topPercent/leftPercent/...`。
- Windows / macOS / Linux 桌面版歌詞窗：**查不到**（MusicFree 主體是 Android / iOS 的 RN 專案，未見桌面版實作）。

### 4.5 AI / LLM：查不到

沒有發現任何 LLM 相關程式碼。

---

## 5. Harmonoid（Flutter / Dart）

查證方式：GitHub permalink 逐檔讀取 ＋ repo 內 `gh search code` 比對。

### 5.1 歌詞源插件化：沒有插件，自架後端 API

- `LyricsGet` 打自家後端：`<apiBaseUrl>/functions/v1/lyrics-get?track=&artist=&duration=`，Header 帶 `X-API-Key`。
  → [`lib/state/lyrics/api/lyrics_get.dart`](https://github.com/harmonoid/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/state/lyrics/api/lyrics_get.dart)
- `apiBaseUrl` / `apiKey` 來自 `--dart-define=API_BASE_URL`（CI 用 GitHub secret 注入，[`.github/workflows/master.yml`](https://github.com/harmonoid/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/.github/workflows/master.yml)）或使用者在 configuration 覆寫。
  → [`lib/api/utils/constants.dart`](https://github.com/harmonoid/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/api/utils/constants.dart)
  → 值得注意：`apiKey` getter 寫成 `Configuration.instance.apiBaseUrl.nullIfBlank() ?? String.fromEnvironment('API_KEY')`，看起來是把 base URL 當 API key 回傳（**疑似筆誤/bug**，這裡只描述讀到的程式碼）。
- **後端本身沒有開源**（是 Supabase edge function）→ 後端實際查了哪些歌詞庫、怎麼匹配，**查不到**。
- 沒有插件／擴充機制。

### 5.2 匹配與手動改選：單次查詢，無候選清單

- 一次呼叫拿一整份 `Lyrics`，用 `track` / `artist` / `duration` 三個參數查。沒有候選清單、沒有手動改選 UI（**查不到**）。
- 有本機 DB 快取：`lib/state/lyrics/database/` 的 `lyrics_entries` 與 `lyrics_translation_entries` 兩張表，key 是 `LyricsKey { track, artist, duration }`（[`lib/state/lyrics/models/lyrics_key.dart`](https://github.com/harmonoid/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/state/lyrics/models/lyrics_key.dart)），翻譯用 `LyricsTranslationKey` 再多一個 `language`。
- 換歌時 `LyricsNotifier` 會先清索引、`_fetchLyrics()` 再 `_fetchLyricsTranslation()`，用 `SplayTreeMap.lastKeyBefore(position + 1)` 找當前行。

### 5.3 逐字歌詞與翻譯：翻譯有，逐字沒有

- 模型 `Lyric { required int timestamp, required String text }` → **逐行**，沒有逐字欄位。
  → [`lib/state/lyrics/models/lyric.dart`](https://github.com/harmonoid/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/state/lyrics/models/lyric.dart)
- 翻譯是**獨立的一次伺服器端呼叫**：`Supabase.instance.client.functions.invoke('lyrics-translation', body: { lyrics: [...], language, track, artist, duration })`
  → [`lib/state/lyrics/api/lyrics_translation_get.dart`](https://github.com/harmonoid/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/state/lyrics/api/lyrics_translation_get.dart)
  → 送的是**整份已解析歌詞 + 目標語言**，回傳翻譯。因為是後端黑盒，是否用 LLM **查不到**（**推測**：機器翻譯或 LLM，因為輸入是整份歌詞而非逐行）。
- README 能力清單：「Lyrics (LRC, tags & online)」、「Lyrics translations」、「Notification lyrics」。
  → [`README.md`](https://github.com/harmonoid/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/README.md)
- 格式：LRC（用 pub 套件 `lrc`），本地 tag 歌詞也算在內。
- 羅馬音：**查不到**。

### 5.4 桌面歌詞：查不到；有 Android 通知欄歌詞

- 桌面歌詞視窗：在 repo 內**查不到**（沒有對應的 desktop lyric 檔案）。
- 有 **Android 通知欄歌詞**：`lyrics_notifier.dart` 定義 `_kNotificationChannelName = 'Lyrics'`、channel id、category、以及 `hide` action，設定 `mobileNotificationLyricsHidden`；當當前行跳動超過 1 行或播放完成時會重發通知。
  → [`lib/state/lyrics/lyrics_notifier.dart`](https://github.com/harmonoid/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/state/lyrics/lyrics_notifier.dart)

### 5.5 AI / LLM：伺服器端翻譯，是否為 LLM 查不到

- 唯一的 AI 可能性就是後端 `lyrics-translation`，實作未開源 → **查不到**。
- 客戶端沒有任何 LLM 呼叫。

---

## 6. BetterLyrics（Windows，WinUI3 / Win2D）＋ Lyricify

查證方式：GitHub permalink 逐檔讀取（BetterLyrics 原始碼全開）＋ Lyricify 讀 README；`gh search code` 交叉比對。

### 6.1 歌詞源插件化：內建 12 種來源 + DLL 插件 SDK

- `LyricsProvider` enum（[`Enums/LyricsProvider.cs`](https://github.com/jayfunc/BetterLyrics/blob/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.Core/Enums/LyricsProvider.cs)）：
  `QQ`、`Kugou`、`Netease`、`LrcLib`、`AmllTtmlDb`、`LocalMusicFile`、`LocalLrcFile`、`LocalEslrcFile`、`LocalTtmlFile`、`AppleMusic`、`BetterLyrics`、`LibreTranslate`
- 每個來源是一筆 `LyricsSearchProviderInfo`，可個別 `IsEnabled`、可覆寫 `MatchingThreshold`（預設 60）、可 `IgnoreCacheWhenSearching`，並有 `IsPlugin` 判斷。
  → [`Models/Settings/LyricsSearchProviderInfo.cs`](https://github.com/jayfunc/BetterLyrics/blob/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.Core/Models/Settings/LyricsSearchProviderInfo.cs)
- **插件系統**：`PluginService`（`PluginLoadContext.cs`、`PluginConfigurator.cs`、`PluginContext.cs`），SDK 是 [`.NET` 專案 `BetterLyrics.Sdk`](https://github.com/jayfunc/BetterLyrics/tree/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.Sdk)。三個能力介面：
  - `ILyricsSource.GetLyricsAsync(title, artist, album, duration, token) → LyricsSearchResult`（可含 Raw、Translation、Transliteration、Reference URL）
  - `ILyricsTranslator.GetTranslationAsync(text, targetLangTag)`
  - `ILyricsTransliterator.GetTransliterationAsync(text, targetLangTag, token)`
  → [`BetterLyrics.Sdk/README.md`](https://github.com/jayfunc/BetterLyrics/blob/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.Sdk/README.md)、[`ILyricsSource.cs`](https://github.com/jayfunc/BetterLyrics/blob/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.Sdk/Interfaces/Plugins/ILyricsSource.cs)
  - 插件設定 UI 由 SDK **自動生成**（`SettingBuilder.Bool()/Text()/Password()/Number()/Choice()/Action()` → `GetSettingDefDict()` 回傳 `SettingDef`）。
- AMLL TTML DB 是內建來源之一：`raw.githubusercontent.com/amll-dev/amll-ttml-db` 的 `metadata/raw-lyrics-index.jsonl`。
  → [`Constants/AmllTTmlDB.cs`](https://github.com/jayfunc/BetterLyrics/blob/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.Core/Constants/AmllTTmlDB.cs)
- Apple Music 來源要 `Media User Token`，存在 `IPasswordVaultProvider`（OS 憑證庫）。
  → [`LyricsSearchService/Providers/AppleMusic.cs`](https://github.com/jayfunc/BetterLyrics/blob/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.Core/Implementations/Services/LyricsSearchService/Providers/AppleMusic.cs)

### 6.2 匹配與手動改選：候選清單 + 手動選 + 記住查詢映射

- 搜尋策略 `LyricsSearchType { Sequential, BestMatch }`（[`Enums/LyricsSearchType.cs`](https://github.com/jayfunc/BetterLyrics/blob/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.Core/Enums/LyricsSearchType.cs)），主流程是 [`LyricsSearchService.SearchSmartlyAsync`](https://github.com/jayfunc/BetterLyrics/blob/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.Core/Implementations/Services/LyricsSearchService/LyricsSearchService.cs)。
- **候選清單 + 手動改選**：
  `LyricsSearchControlViewModel` 有 `ObservableCollection<LyricsCacheItem> LyricsSearchResults` 與 `SelectedLyricsSearchResult`，UI 綁在 `LyricsSearchControl.xaml`（`ItemsSource` / `SelectedItem`）。
  → [`ViewModels/LyricsSearchControlViewModel.cs`](https://github.com/jayfunc/BetterLyrics/blob/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.Core/ViewModels/LyricsSearchControlViewModel.cs)、[`Controls/LyricsSearchControl.xaml`](https://github.com/jayfunc/BetterLyrics/blob/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.WinUI3/BetterLyrics.WinUI3/Controls/LyricsSearchControl.xaml)
- **記住**：`ISongSearchMapService.SaveMappingAsync / TryGetMappingAsync`，存 `MappedSongSearchQuery`（`MappedTitle` / `MappedArtist` / `MappedAlbum` / `LyricsSearchProvider` / `IsMarkedAsPureMusic`）。搜尋前先查映射，命中就用**使用者認可過的標題/藝人/專輯**與指定來源再查。
  → [`Interfaces/Services/ISongSearchMapService.cs`](https://github.com/jayfunc/BetterLyrics/blob/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.Core/Interfaces/Services/ISongSearchMapService.cs)
- 被標成純音樂（`IsMarkedAsPureMusic`）的直接回 `[00:00.000]🎶🎶🎶\n[99:00.000]`，不再搜尋。

### 6.3 逐字歌詞與翻譯：完整

- 逐字：`WordByWordEffectMode { Auto, Never, Always }`（[`Enums/WordByWordEffectMode.cs`](https://github.com/jayfunc/BetterLyrics/blob/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.Core/Enums/WordByWordEffectMode.cs)）。
- 格式 `LyricsFormat { Lrc, Eslrc, Ttml, Qrc, Krc, NotSpecified }`（[`Enums/LyricsFormat.cs`](https://github.com/jayfunc/BetterLyrics/blob/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.Core/Enums/LyricsFormat.cs)）。
- 解析**不是自己寫的**：用 Lyricify 的開源庫 —— `using Lyricify.Lyrics.Decrypter.Krc; ... .Parsers; ... .Searchers; ... .Searchers.Helpers;`（見 `LyricsSearchService.cs` 的 using 區塊）。
- 翻譯：預設走**自架的 LibreTranslate**，`TranslationService.TranslateTextAsync` 打 `<LibreTranslateServer>/translate`，送 `q`（原文）/ `source` / `target`，並先用 `LanguageHelper.DetectLanguageTag` 偵測語言、同語言直接回原文。同檔中保留了 `ILyricsTranslator` 插件路徑（被註解掉）。
  → [`Implementations/Services/TranslateService.cs`](https://github.com/jayfunc/BetterLyrics/blob/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.Core/Implementations/Services/TranslateService.cs)
- 另有 `TransliterationService`（羅馬音／拼音）。

### 6.4 桌面歌詞：產品本身就是桌面歌詞工具（Windows only）

- BetterLyrics 是 Windows 的「歌詞可視化 + 播放器」，`Enums/` 裡有 `LyricsWindowMode`、`DockPlacement`、`TaskbarPlacement`、`SystemTrayClickCallback`、`LyricsLayerType`、`LyricsLayoutOrientation`、`NowPlayingBarBackgroundStyle` 等一整套歌詞視窗/工作列/托盤設定。
- 媒體來源靠 **GSMTC**（Windows Global System Media Transport Controls）抓其他播放器的曲目：`GsmtcService.AlbumArtUpdater.cs` / `GsmtcService.LyricsUpdater.cs`。
  → 甚至內建 LX Music 的訂閱端點：`Constants/LXMusic.cs` 的 `/subscribe-player-status?filter=progress,duration,picUrl`。
  → [`Constants/LXMusic.cs`](https://github.com/jayfunc/BetterLyrics/blob/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.Core/Constants/LXMusic.cs)
- 平台：**Windows only**（WinUI3 / Win2D；repo description 明寫）。
- 置頂 / 點擊穿透的實作細節：本次未逐檔追（**查不到**）。

### 6.5 AI / LLM：有 AI 能力，但是給插件用的，不是用來匹配

- SDK 把 AI 當成**提供給插件的能力**：
  ```csharp
  public interface IAIService { Task<string> ChatAsync(string systemPrompt, string userPrompt); }
  ```
  宿主實作：`PluginContext.AIService => _pluginService.GetPlugin<IAIService>();`
  → [`Sdk/Interfaces/Plugins/IAIService.cs`](https://github.com/jayfunc/BetterLyrics/blob/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.Sdk/Interfaces/Plugins/IAIService.cs)、[`PluginService/PluginContext.cs`](https://github.com/jayfunc/BetterLyrics/blob/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.Core/Implementations/Services/PluginService/PluginContext.cs)、[`Sdk/README.md`](https://github.com/jayfunc/BetterLyrics/blob/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.Sdk/README.md)
- **核心的歌詞搜尋/匹配沒有用到 AI** —— 靠的是每來源的 `MatchingThreshold` + `BestMatch` 排序 + 使用者存下來的 `SongSearchMap`。
- 誰實作 `IAIService`、用哪家 LLM、API key 怎麼放：**查不到**（需要在 WinUI3 專案或外部插件裡再追）。

### 6.6 Lyricify（同類 Windows 歌詞工具，做為格式/來源的對照基準）

Lyricify-App repo 只有 README 與 docs（**沒有應用程式原始碼**），歌詞處理核心另開在 `WXRIW/Lyricify-Lyrics-Helper`（Apache-2.0）。

- 產品線：Lyricify 4（Spotify 使用者，Windows）、Lyricify Fusion（任何接 SMTC 的 app，Windows）、Lyricify Mobile（iOS/iPadOS/macOS/Android/Windows）、Lyricify 3（EOL）。Lyricify 4 / 3 可透過 Wine 跑 Linux、macOS（官方 README remark 3，並另開 `Lyricify/Lyricify-on-Wine`）。
- 首創功能（README「Lyricify 原創」）：靈動島 / Dynamic Lyrics Island、妙控條 / Magic Strip、動態專輯封面 / Live Album Cover。
- **歌詞格式能力**（`Lyricify-Lyrics-Helper` README 的表，解析／生成）：

  | 格式 | 解析 | 生成 | 說明 |
  |---|:-:|:-:|---|
  | Lyricify Syllable | ✓ | ✓ | Lyricify 逐字歌詞 |
  | Lyricify Lines | ✓ | ✓ | Lyricify 逐行歌詞 |
  | LRC | ✓ | ✓ | 標準逐行歌詞 |
  | QRC | ✓ | ✓ | QQ 音樂逐字歌詞 |
  | KRC | ✓ | ✓ | 酷狗逐字歌詞 |
  | YRC | ✓ | ✓ | 網易雲音樂逐字歌詞 |
  | TTML | ✓ | — | 逐行、逐字；支援 Apple Music 擴展 |
  | Spotify (JSON) | ✓ | — | 未同步、逐行或逐字歌詞 |
  | Musixmatch (JSON) | ✓ | — | 未同步、逐行或逐字歌詞 |

  另有 `ParseHelper` / `GenerateHelper` / `TypeHelper`（自動識別格式），並支援 QRC (XML)、網易完整 YRC (JSON)、Apple Music (JSON) 等原始封裝。
- **搜尋來源與憑證要求**（同一份 README）：

  | 來源 | 歌詞能力 | 憑證要求 |
  |---|---|---|
  | QQ 音樂 | 歌詞及翻譯 | 無需配置 |
  | 網易雲音樂 | LRC、YRC 等 | 無需配置 |
  | 酷狗音樂 | 搜尋歌詞並取 KRC | 無需配置 |
  | 汽水音樂 | 曲目詳情取歌詞 | 無需配置 |
  | Apple Music | TTML 歌詞 | 必須提供 Media User Token（Access Token 自動取得） |
  | Musixmatch | 逐字/逐行/未同步歌詞及翻譯 | User Token 自動取得，可手動設置 |
  | Spotify | 未同步/逐行/逐字歌詞 | 必須提供 `sp_dc` Cookie |
  | LRCLIB | 同步或純文字歌詞 | 無需配置 |

- 另有歌詞優化（Explicit 處理、標準化 YRC/Musixmatch、資訊行識別、Apple Music TTML 擴展的翻譯/簡中替換/背景人聲/演唱者對齊）與時間軸處理（加 offset、**把逐字降級成逐行**）。
  → [`Lyricify-Lyrics-Helper/README.md`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/cabe0b71d443a9b882a35c60c4f7f21addcbe751/README.md)
- Lyricify 應用層（候選清單手動改選、桌面歌詞置頂/穿透細節）：**查不到**（repo 不含 app 原始碼）。

---

## 7. 綜合觀察

### 7.1 候選清單 + 手動改選是常態嗎？不是，大約一半

| 產品 | 候選清單 | 手動改選 | 記住選擇的方式 |
|---|:-:|:-:|---|
| Namida | 有（含網路結果串流） | 有，還可編輯/刪除 | 寫 `.lrc` / `.txt` 快取檔 |
| MusicFree | 有（每插件一個 tab） | 有（associate） | mediaExtra `associatedLrc` |
| BetterLyrics | 有（`LyricsSearchResults`） | 有（`SelectedLyricsSearchResult`） | DB 存 `SongSearchMap`（含查詢字串與來源） |
| LX Music | **沒有** | 只有自動換源 + 調 offset | 存實際抓到的來源那份歌詞 |
| Spotube | **沒有** | 沒有 | DB 快取（trackId 為 key） |
| Harmonoid | **沒有** | 沒有 | DB 快取（track/artist/duration 為 key） |

- 有候選清單的三個，共同點是：**手動改選的結果會被持久化成「這首歌用這一份」**，只是存法不同（快取檔 / mediaExtra / DB mapping）。
- 「自動匹配」的兩條主流路線：
  1. **精確參數查詢**（Spotube、Harmonoid）：artist + title + album + duration 打單一 API，不做相似度排序。簡單，但離線庫／翻唱／直播版就找不到。
  2. **相似度挑選**（MusicFree 的 `minDistance` 編輯距離、BetterLyrics 的 `MatchingThreshold` 預設 60、LX 的自動換源）：先撈一批再排序。需要一個可調門檻。
- BetterLyrics 的 `SongSearchMap` 值得注意：它記的不是「結果」，而是**「這首歌該用什麼查詢字串、查哪個來源」**。這樣換一個新來源插件時仍有機會命中，比只存結果更有韌性。

### 7.2 逐字歌詞與翻譯：格式現實

- 真實世界的逐字格式就三種：**QQ QRC**、**酷狗 KRC**、**網易 YRC**。能在自家 App 內自成一格的只有 LX（`lxlrc`）與 Lyricify（Lyricify Syllable）。
- **LRC 是所有人都支援的唯一下限**。LRCLIB（Spotube 唯一來源、FMP 想接的來源之一）**只給逐行 LRC**，拿不到逐字。
- **翻譯欄位名一致的叫 `tlyric` / `translation`**，配對策略一致地用**時間戳相等**合併（MusicFree 用雙指標；LX 用 `filterExtendedLyricLabel` 先把沒有對應時間戳的翻譯行濾掉再合併）。逐字歌詞的翻譯通常由同一個來源一起回（QQ 的 `lrc` + `tlyric` + `rlyric`）。
- **羅馬音**：LX 有完整支援（`rlyric` + `player.isShowLyricRoma` + 交換順序設定）；BetterLyrics 有 `ILyricsTransliterator`；Namida / MusicFree / Spotube / Harmonoid **查不到**。
- 逐字能力一定要有**降級路徑**：Lyricify-Lyrics-Helper 明列「將逐字歌詞降級為逐行歌詞」（來源不支援逐字、或來源只給 LRC 時）。沒有這條，UI 會被迫為不同同步級別寫兩套。

### 7.3 桌面歌詞：跨平台誰真的做到了

| 產品 | 桌面歌詞 | 平台 | 置頂 | 點擊穿透 |
|---|---|:-:|:-:|:-:|
| LX Music Desktop | 獨立 BrowserWindow（橫向/縱向 + 頻譜） | **Windows / Linux / macOS** | ✓（`isAlwaysOnTop` + 循環重設） | ✓（`setIgnoreMouseEvents(true,{forward})`，Linux 不支援 forward → 改輪詢） |
| Namida | 迷你歌詞視窗（frameless + 透明） | Windows / Linux（macOS 未確認） | ✓ | **✗**（改成 hover 顯示控制列） |
| Spotube | mini lyrics（`/mini-player`） | Linux / Windows / macOS（`kIsDesktop`） | 查不到 | 查不到 |
| BetterLyrics | 就是桌面歌詞工具 | Windows only | 查不到（未逐檔追） | 查不到 |
| Lyricify | 桌面歌詞工具（靈動島/妙控條） | Windows（+ Wine 勉強跑 Linux/macOS） | 查不到 | 查不到 |
| MusicFree | Android overlay + 狀態欄歌詞 | Android | — | — |
| Harmonoid | 查不到 | — | — | — |

三個可帶走的結論：

1. **只有 LX 真的做完了三平台**，而且是用 Electron 的 `setIgnoreMouseEvents`。而且連它都要為 Linux 開後門：`forward` 選項在 Linux 不支援，只能自己輪詢游標位置來補 hover 偵測。
2. **不支援點擊穿透的產品，改用「hover 顯示/隱藏控制列」**（Namida、Spotube）。這是純 Flutter 沒有等價 API 時的低成本替代。
3. 桌面歌詞窗的**基本設定集**幾乎一致：always-on-top、skip taskbar、記住座標/尺寸、字級、played/unplayed 兩色、透明度、對齊、點擊穿透、hover 隱藏、暫停隱藏。

### 7.4 有多少產品真的用了 LLM？零

七個產品裡，**沒有一個把 LLM 用在歌詞匹配上**。所有找得到的 AI 痕跡：

- **BetterLyrics**：SDK 提供 `IAIService.ChatAsync(systemPrompt, userPrompt)`，但這是**給插件呼叫的能力**（`PluginContext.AIService`），核心的搜尋/匹配完全靠 `MatchingThreshold` + `BestMatch` + `SongSearchMap`。誰實作 IAIService、用哪家模型、key 放哪，查不到。
- **Harmonoid**：唯一的後端 `lyrics-translation` 送「整份歌詞 + 目標語言」拿翻譯，**推測**是機器翻譯或 LLM，但後端未開源，查不到。
- **BetterLyrics 的翻譯**：預設走自架 LibreTranslate（明確不是 LLM），LLM 路徑（`ILyricsTranslator` 插件）被註解掉。

→ 也就是說，**「用 LLM 做歌詞匹配」在成熟產品中沒有先例**。成熟產品的替代品是「編輯距離 / 相似度 + 可調門檻 + 記住使用者修正」。如果 FMP 要做「可選的 AI 歌詞匹配」，那會是差異化而非跟隨；值得參考的設計是 **BetterLyrics 的 `SongSearchMap`**（把 LLM 的產出當成「映射」存下來覆核一次，而不是每次播放都問一次 LLM）。

### 7.5 對 FMP 插件 API 的幾個直接啟示

- **歌詞插件的能力邊界**：成熟產品的歌詞接口都很窄 —— 輸入幾乎固定是 `(title, artist, album, duration)`，輸出是 `{ 主歌詞, 翻譯, 羅馬音, 來源 url }`。MusicFree 的 `getLyric(musicItem)` 是唯一帶「平台內 id」的（因為它同時是音樂來源插件）；純歌詞插件（BetterLyrics 的 `ILyricsSource`）則只吃四個純量參數。
- **憑證一定要能存**：需要 token/cookie 的來源（Spotify `sp_dc`、Apple Music Media User Token、Musixmatch token）在 Lyricify 是「自動取得 + 可手動覆寫」，在 BetterLyrics 是 OS 憑證庫（`IPasswordVaultProvider`）。FMP 的插件 manifest 需要一個 secret 欄位與一套儲存位置。
- **搜尋與取用要分開**：MusicFree 的插件既有 `search`（可用 `"lyric"` 類型）又有 `getLyric`，Lyricify 也分 `SearchHelper`（找曲目）與 `ProviderHelper`（已知 id 直接取）。只有搜尋分離出來，「候選清單」才做得出來。
- **來源能力要能被查詢**：MusicFree 用 `supportedSearchType.includes("lyric")` 做能力過濾、`getPluginsWithAbility(ability)` 做方法過濾；BetterLyrics 用 `[Flags]`/enum + per-provider 開關與門檻。FMP 若要「多源搜尋」，插件需要宣告「我能搜歌詞」。

### 7.6 本次查不到清單（彙總）

- Namida：翻譯／羅馬音的實際抓取與 UI 開關（只確認解析層有 `extText` 欄位）。macOS 是否支援迷你歌詞視窗。
- Spotube：mini lyrics 的置頂／點擊穿透；翻譯支援；LRCLIB 之前的 Spotify 官方歌詞路徑是否已完全移除（只知道 HEAD 沒有）。
- LX Music：手動歌詞候選清單（沒有）；桌面歌詞視窗在 macOS 的實際行為（原始碼註解寫「MacOS未知」）。
- MusicFree：羅馬音；桌面 OS（Windows/macOS/Linux）版歌詞窗。
- Harmonoid：後端 `lyrics-get` / `lyrics-translation` 的實作與資料庫來源；是否有候選清單；羅馬音。
- BetterLyrics：`IAIService` 的實作者與模型；桌面歌詞窗置頂/穿透的實作細節；`MatchingThreshold` 的比較演算法。
- Lyricify：應用層（非 library）的候選清單手動改選與桌面歌詞視窗細節（repo 不含 app 原始碼，其餘在 docs.lyricify.app，本次未逐頁讀）。
