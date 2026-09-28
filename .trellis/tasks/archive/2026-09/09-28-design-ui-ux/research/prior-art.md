# prior-art.md — 外部先例（Material 3 版面、桌面播放器版面、token 慣例、快捷鍵、使用者指南）

- **查證日**：2026-09-28
- **查證方式**：三個 sonnet 子代理分頭查證，工具為 context7 / tavily-search（basic）／tavily-extract／WebFetch，GitHub 內容以 `gh api` 取固定 commit SHA 的 permalink。**未下載任何圖片**，只記官方截圖的路徑與 URL。**未執行 FMP App**、**未打任何音樂平台 API**。
- **標記慣例**：`逐字` = 官方頁原文引號；`推測` = 我的推論；`查不到` = 本輪找不到可靠出處。
- **已知工具限制**：`m3.material.io` 為 JS render，`tavily-extract` 與 WebFetch 都只取到導覽骨架，取不到內文表格；因此 M3 的數值多數引自 `developer.android.com` 的同義頁面。此限制影響本檔多條目，個別條目會再標註。

---

## 1. Material 3 版面官方規則

### 1.1 Window size class 的命名與斷點數值

- 官方頁面已由 `foundations/layout/applying-layout` 改稱 **breakpoints**：<https://m3.material.io/foundations/layout/breakpoints>。索引摘要逐字列出五個 class：compact, medium, expanded, large, extra-large，並說版面「typically transition from a single pane to two or three panes as window size increases」。
- **寬度**（逐字，出處為 `developer.android.com` 而非 m3 站）<https://developer.android.com/develop/adaptive-apps/guides/use-window-size-classes>：
  - Compact width `width < 600dp`
  - Medium width `600dp ≤ width < 840dp`
  - Expanded width `840dp ≤ width < 1200dp`
  - Extra-large width `width ≥ 1600dp`
  - **Large width = `1200dp ≤ width < 1600dp`**：該列在抓取時被截斷，由 Extra-large 下界反推 → **推測**。
- 官方說明 Large／Extra-large 的來源（逐字）：這兩個 class 是在 Material 的 compact/medium/expanded 之外「**additionally … added** to better target desktop and connected displays」→ 同上。
- **高度**（逐字，同頁）：`Compact height = height < 480dp`、`Medium height = 480dp ≤ height < 900dp`、`Expanded height = height ≥ 900dp`。**高度只有三個 class，寬度有五個**。
- 官方對「該看寬還是看高」的立場（逐字）：「Available width and height are classified separately, so at any point in time, your app has two window size classes—one for width, one for height. **Available width is usually more important than available height due to the ubiquity of vertical scrolling**, so the width window size class is likely more relevant to your app's UI.」→ 同上。

**與 FMP 現況的對照**（事實，不代表建議）：FMP `lib/core/constants/breakpoints.dart` 的 `WindowClass` 斷點為 compact 0 / medium 600 / expanded 840 / large 1200 / extraLarge 1600 —— 與上表五個寬度 class 完全同值同序。

### 1.2 Canonical layouts（list-detail / supporting pane / feed）

官方三個 canonical layout 各自有專頁：

- supporting pane — <https://m3.material.io/foundations/layout/canonical-examples/supporting-pane>
- list-detail — <https://m3.material.io/foundations/layout/canonical-examples/list-detail>
- feed — <https://m3.material.io/foundations/layout/canonical-examples/feed>

- **supporting pane 的斷點行為**（逐字，supporting-pane 頁）：
  - Compact：「The supporting pane should appear **below** the focus pane. **A bottom sheet can be useful** for keeping focus on the primary pane while providing access to supporting information.」
  - Medium：「The supporting pane should appear **below** the focus pane.」
  - Expanded：「The supporting pane should appear on the **leading or trailing side** of the focus pane.」
- **list-detail 的斷點行為**（逐字，M3 lists 指南 <https://m3.material.io/components/lists/guidelines>）：
  - Compact：「Lists should extend **edge-to-edge** in compact windows. Selecting a list item should open a page with the details.」
  - Medium & expanded：「can display primary and secondary content in the same view. For example, **a list and the detailed information can appear side-by-side**.」
- **兩者的判準**（逐字，`developer.android.com/develop/ui/views/layout/canonical-layouts`）：「A supporting pane layout differs from a list-detail layout in the relationship of the primary and secondary content. **Secondary pane content is meaningful only in relation to the primary content**; … **The supplementary content in the detail pane of a list-detail layout, however, is meaningful even without the primary content**, for example, the description of a product from a product listing.」
- **supporting pane 的適用情境**（逐字，同頁）：「Supporting pane layouts work well on **expanded-width** displays … **Medium- or compact-width** displays support showing both the primary and secondary display areas if the content is adaptable to narrower display spaces, or if the additional content can be **initially hidden in a bottom or side sheet** accessible by means of a control such as a menu or button.」
- feed 的**官方正文未取得**（頁面只取到骨架）。第三方（SAP Fiori for Android，非官方原文 <https://www.sap.com/design-system/fiori-design-android/v24-12/foundations/adaptive-layout/canonical-layouts>）轉述：三種 canonical layout 由 panes（flexible 或 fixed-width 容器）組成，隨 window size class 重新排列；feed「unique for using a grid composition」→ 標記**第三方轉述**。

### 1.3 導覽元件切換規則

**Navigation bar** <https://m3.material.io/components/navigation-bar/guidelines>（逐字）：

- 「**Only use navigation bars for compact and medium**」
- Compact：「For narrow windows, use a navigation bar or modal navigation rail.」
- Medium：「Use a navigation bar or navigation rail. Decide based on whether horizontal or vertical space is more important.」
- 「**Expanded and extra-large: Use a navigation rail instead.**」
- item 方向：「Use **vertical** items in compact windows (widths smaller than 600dp)… Use **horizontal** items in medium windows (widths from 600dp to 839dp)」

**Navigation rail** <https://m3.material.io/components/navigation-rail/guidelines>（逐字）：

- 「**Only use navigation rails for medium breakpoints and larger. Don't use a navigation bar.**」
- Compact：「**Don't** use a standard navigation rail for compact layouts due to space constraints. **Use a navigation bar instead.**」
- 「If there are more than **five** destinations, consider using a **modal expanded nav rail** instead.」
- 題目所稱的「navigation rail + extended」，M3 正式名稱是 **expanded navigation rail**：「The **expanded navigation rail** can be standard or modal, and should always open from a menu icon. … The **standard** configuration is placed beside body content… The **modal** configuration overlaps the body content.」
- 適用範圍：「It can be used in **medium** (600dp to 839dp) … to **extra large** (1600dp and larger) … such as tablets and desktop. In medium windows with few destinations, consider using a navigation bar instead.」

**Navigation drawer** <https://m3.material.io/components/navigation-drawer/guidelines>（逐字）：

- 「**Modal** navigation drawers can be used at **any breakpoint** but are most common in **compact** … and **medium**.」
- 「**Standard** navigation drawers are best for **expanded** (840dp to 1199dp), **large** (1200dp to 1599dp), and **extra-large** (1600dp and larger) breakpoints.」
- 「Use a modal navigation drawer alone or **with a navigation rail** on medium and expanded breakpoints.」
- 「A standard navigation drawer can be used in single pane layouts in expanded breakpoints.」
- 「切換時要做轉場動畫」這一條 → **官方逐字查不到**。

**第三方轉述**（非官方原文）：9to5Google 報導 M3 Expressive 的導覽變化，稱 navigation rail 適用「medium, expanded, large, or extra-large window sizes」，且 Google 希望以 expanded navigation **取代** navigation drawer → <https://9to5google.com/2025/05/14/material-3-expressive-navigation/>。

### 1.4 M3 Expressive 現況

- 官方定性（逐字）：「Material 3 Expressive is an **evolution of the Material 3 design system**. It's a set of new features, updated components, and design tactics for creating emotionally impactful UX.」→ <https://m3.material.io/blog/building-with-m3-expressive>（頁面日期 2025-05-13）
- 官方部落格發布（2025-05-13，作者 Mindy Brooks, VP of Product Management and User Experiences, Android Platform）→ <https://blog.google/products-and-platforms/platforms/android/material-3-expressive-android-wearos-launch>
- 官方首頁寫法（逐字）：「**M3 Expressive adds** vibrant colors, intuitive motion, adaptive components, flexible typography」→ <https://m3.material.io>。即官方定位為 **M3 的加值層**，沒有任何官方文字說它取代 M3 → **推測**：是延伸而非 replacement。
- 範圍（逐字）：「**Fourteen** new or updated components now feature more configuration capabilities, shape options, emphasized text, and other expressive updates.」清單含 app bars、button groups、common buttons、extended FAB、FAB menu、FABs、icon buttons、loading indicator、navigation bar 等 → 同 blog 頁。
- 「新增 35 個 shape 與 shape morphing」為第三方轉述（supercharge.design）→ <https://supercharge.design/blog/material-3-expressive>，**非官方原文**。
- 出貨時程（「隨 Android 16 QPR1 / 2025 九月 Pixel Drop」）本輪**未取得官方逐字** → **推測，需複查**。

**Flutter 端現況**（`gh api` 查證）：

- `flutter/flutter#168813`「☂️ Bring Material 3 Expressive to Flutter」，state = **open**，建立 2025-05-14，最後更新 2026-08-17 → <https://github.com/flutter/flutter/issues/168813>
- `flutter/packages#12093`「[material_ui] Add Material 3 Expressive IconButton」，state = **closed**、`merged: false`（closed_at 2026-09-10）→ <https://github.com/flutter/packages/pull/12093>
- 本地 Flutter SDK 3.47.1 的 `packages/flutter/lib/src/material/page_transitions_theme.dart:468` 有一行註解：「Android is using Material 3 Expressive springs that are not currently …」→ 即 framework 自身承認尚未支援 M3E 的動態曲線。

---

## 2. 桌面音樂播放器「播放頁」版面

> 逐家列出：封面／歌詞／佇列／控制列位置、背景處理、窄視窗行為、官方截圖或文件 URL。**未下載圖片**。

### 2.1 Spotify 桌面（官方支援文件為主）

- **Now Playing view 是右側面板**（逐字）：「Click [Video vertical] to display the Now Playing view. There you can find: About the Artist / On Tour / Merch / Podcast transcripts / **Next in queue**」；「Tip: To switch between the Friend Feed and the Now Playing view, click [Group active] / [Video vertical]」→ <https://support.spotify.com/us/article/now-playing>
- **佇列位置**（逐字）：「To open the queue, click **Play Queue next to the play bar at the bottom**.」→ <https://support.spotify.com/us/article/play-queue>
- **歌詞位置**（逐字）：「1. Play a song. 2. **Click Lyrics at the bottom.**」→ <https://support.spotify.com/us/article/lyrics>
- **右側面板開關快捷鍵**：Alt + Shift + R（Toggle Now Playing View Sidebar）→ <https://support.spotify.com/us/article/keyboard-shortcuts>
- **全螢幕**：官方支援文章查不到。官方社群版主回覆（2025-02-16）稱 full screen mode 已整合進 Now Playing view —— 先展開 Now Playing view，再按方形圖示，且可切 Album view / Artist banner view → <https://community.spotify.com/t5/Desktop-Windows/fullscreen-button-not-showing/td-p/6719164>（**版主回覆，非支援文件**）
- **Miniplayer 位置**（官方社群公告）：圖示在「bottom right corner between the volume and the full screen buttons」→ <https://community.spotify.com/t5/Community-Blog/Introducing-the-Spotify-Miniplayer-to-Spotify-Desktop/ba-p/5956132>
- **封面位置與大小、控制列精確位置、背景處理（純色／模糊封面／取色漸層）、窄視窗行為** → **查不到官方說明**。

### 2.2 Apple Music（macOS）

- **歌詞在右側**（逐字，含官方截圖說明）：「**The Full Screen Player** with a song playing and **lyrics on the right**, which appear onscreen in time with the music.」；開關方式「Lyrics button」；全螢幕播放器「Choose Window > Full Screen Player」→ <https://support.apple.com/guide/music/view-and-enter-lyrics-musf438ffc97/mac>
- **網站版同樣歌詞在右側**（逐字）：「A song is playing in the Full Screen Player in Apple Music. **Lyrics appear on the right**, in time with the music.」→ <https://support.apple.com/guide/music-web/welcome/web>
- **佇列位置**（逐字）：MiniPlayer 的「**Playing Next button in the bottom-right corner**」可檢視與編輯 upcoming songs；Full Screen Player 由 MiniPlayer 左上綠色鈕進入 → <https://support.apple.com/guide/music/use-music-miniplayer-mus71d7dcfce/mac>
- **窄視窗行為**（逐字，但出處是 Apple Music **Classical** 的 web 說明）：「Switch from the Full Screen Player to the MiniPlayer: **Reduce the width of the window—drag the right or left edge inward—until the Close button appears.**」→ <https://support.apple.com/guide/apple-music-classical/use-the-music-player-controls-dev418ee3f2d/web>。macOS Music 是否同規則 → **查不到官方逐字**。
- 全螢幕進入／離開（逐字）：左上 Full-Screen 鈕進入、按 **Esc** 離開 → <https://support.apple.com/guide/music/customize-the-music-window-mus0cec331d6/mac>
- **封面位置與大小、背景處理** → **查不到官方文字說明**（官方只有截圖）。

### 2.3 YouTube Music（桌面 web）

- **官方版面文件查不到**。
- 第三方描述（9to5Google, 2019-10-28，逐字）：「**Media controls are docked at the bottom** with play/pause, backwards, and forwards always in the **bottom-left**, while **album art and track details are centered**. Volume, repeat, and shuffle round out this strip. Tapping slides up **full-screen controls, larger cover art, and a now-playing queue**.」→ <https://9to5google.com/2019/10/28/youtube-music-desktop-pwa/>（**第三方，2019 年描述，可能已過時**）
- 同來源的窄視窗行為（逐字，指頂部導覽列）：「Depending on the window size, **the text switches to just icons**.」→ 同上
- 手機版 2025 Now Playing 改版（控制列移到曲名／演出者下方、Up Next 雙欄、歌詞改 sheet）為第三方報導，與桌面 web 無直接關係 → <https://nokiamob.net/2025/09/12/youtube-musics-now-playing-gets-a-major-ui-cleanup-and-queue-upgrade/>（**第三方**）

### 2.4 Tidal（桌面 app）

- **佇列／Now Playing**（搜尋索引摘要逐字，正文抽取只取到導覽骨架）：「The Play Queue menu allows you to manage your Play Queue as well as **Now Playing, Next Up, and recently played content. Desktop.**」→ <https://support.tidal.com/hc/en-us/articles/360004182777-Play-Queue>
- Now Playing 畫面存在（逐字，Tidal Connect 文章）：「In the Tidal app, open the **Now Playing screen** while playing a track. From the Now Playing screen, select the **device output icon**.」→ <https://support.tidal.com/hc/en-us/articles/360004565898-Tidal-Connect>
- 歌詞官方文章只說支援 41 種語言，**未描述位置** → <https://support.tidal.com/hc/en-us/articles/4404289436433-View-lyrics>
- **封面位置與大小、控制列位置、背景處理、窄視窗行為** → **查不到官方說明**。

### 2.5 網易雲音樂 PC 版

- **官方版面說明查不到**。
- 官方站（web 播放器）可見文字只有播放控制「上一首／播放暫停／下一首」與「打開客戶端播放，享受高清音質／去客戶端播放」→ <https://music.163.com>
- 唯一沾到版面的官方站內文字是**使用者專欄文章**（非官方文件）：「PC端：**点击歌词**，输入你要搜索的内容就可以。」→ <https://music.163.com/topic?id=18382055>
- 封面／歌詞／佇列／控制列位置、背景處理、窄視窗行為 → **查不到**。

### 2.6 QQ 音樂 PC 版

- **官方版面說明查不到**。官方下載頁只有版本號（Windows PC 22.6.1、Mac 11.9.1、Linux 1.1.8）→ <https://y.qq.com/download/download.html>
- 第三方（onlinedown）描述歌詞可切「竖屏」→ <https://m.onlinedown.net/article/10001131.htm>（**第三方**）
- 第三方（百度经验）描述桌面歌詞開關在「主界面右上角…点击『词』」→ <https://jingyan.baidu.com/article/1876c852df25a7c80b1376c2.html>（**第三方**）
- 其餘欄位 → **查不到**。

### 2.7 Namida（Flutter，開源）

固定 SHA `acb1e1622600440cc793f389f497e6771c732c5e`

- **寬螢幕播放頁版面**（`lib/ui/pages/wide_screen_player_page.dart`）：根為 `BackgroundWrapper` → `SafeArea` → `Stack`（左上 back 鈕 top:4,left:4）→ `Padding(horizontal: 16.0, vertical: 6.0)` → `Row[ Expanded(flex: 5, _LeftPane), SizedBox(width: 26.0), Expanded(flex: 5, _RightPane) ]` —— **左右各半（50/50）**。<https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/ui/pages/wide_screen_player_page.dart>
- **左側**：`Center → ConstrainedBox(maxWidth: maxHeight) → Column[ 曲名(displayLarge, maxLines 2) + 演出者(displaySmall, maxLines 1), gap = (maxHeight*0.02).clamp(6,16), Expanded(_Artwork), PlayerTransportControls(waveform seekbar) ]`；封面尺寸由可用框與圖片長寬比換算（`resolvePlayableImageAspectRatio`）。
- **右側**：`Column[ _PlayerActionsRow, 兩顆 _PaneChip(lang.lyrics / lang.queue), Expanded(IndexedStack) ]`；IndexedStack 內容為 `LyricsLRCParsedView`（字級 = `(maxWidth*0.03).clamp(15,26)`）與 `CurrentQueueList` —— **歌詞與佇列是同一個面板位置的互斥分頁**（非並排）。
- **面板選擇會持久化**：`settings.extra.widePlayerPageIndex`。
- **背景**：`BackgroundWrapper`（動態取色）。README 逐字：「Material3-like Theme. **Dynamic Theming, Player Colors are picked from the current album artwork.**」→ <https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/README.md>
- **官方截圖目錄**（未下載）：<https://github.com/namidaco/namida/tree/acb1e1622600440cc793f389f497e6771c732c5e/screens>（`collection_dark_1.jpg`、`collection_light_1.jpg`、`yt_miniplayer.png` 等）
- **窄視窗**：wide player 是獨立 route（`RouteType.PAGE_widePlayer`），窄視窗走一般 mobile now playing；**切換門檻本輪未查證**。

### 2.8 Harmonoid（Flutter，開源）

固定 SHA `2b021f7b0b5dbcbe027aec010580977a2939a28d`

- **桌面播放頁結構**（`lib/features/now_playing/desktop/desktop_now_playing_screen.dart`）：`Scaffold → Stack[ Positioned.fill(桌布/carousel), Positioned.fill(黑 20% 遮罩), Positioned.fill(上下漸層：黑 0.2 → 透明 → 透明 → 黑 0.2), Positioned.fill(Column[ Expanded(歌詞區，可切換), Controls ]) ]`。<https://github.com/harmonoid/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/features/now_playing/desktop/desktop_now_playing_screen.dart>
- **歌詞位置**：佔滿控制列以上的整個 `Expanded` 區，受 `notifier.desktopNowPlayingLyrics` 切換，無歌詞時為 `SizedBox`。
- **控制列**：`Row[ 封面(width/height = MediaQuery.height*0.28，clamp 0–256), SizedBox(32), Expanded(Column: 標題/演出者/專輯), SizedBox(32), 播放清單鈕, SizedBox(32) ]`，下方另一列為進度條與控制圖示。
- **背景處理**：`NowPlayingBackground` 用 `AnimatedMeshGradient`，顏色取自 `NowPlayingColorPaletteNotifier` 的 palette（只取 `computeLuminance() < 0.5` 的色；palette 為空時四色皆黑）→ <https://github.com/harmonoid/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/lib/features/now_playing/now_playing_background.dart>
- **桌布可換成自訂圖**：`DesktopNowPlayingScreenCarousel` 依 `Configuration.instance.desktopNowPlayingCarousel` 切換，index 0 為 `NowPlayingBackground`，其餘為 `Image.asset` / `Image.file` 滿版。
- **佇列位置**：`DesktopNowPlayingPlaylist` 是**獨立畫面**，寬度 `kDesktopCenteredLayoutWidth`。
- **窄視窗**：另有 mobile 版檔案（`mobile/m2_mobile_now_playing_bar.dart`、`m3_mobile_now_playing_bar.dart`、`mobile_now_playing_lyrics_screen.dart`）；**切換門檻本輪未查證**。
- README 逐字：「Material Design 3 & 2」、lyrics（LRC, tags & online）、lyrics translations → <https://github.com/harmonoid/harmonoid/blob/2b021f7b0b5dbcbe027aec010580977a2939a28d/README.md>
- **官方截圖在另一個分支 `screenshots`**（SHA `ebc5dd7321edf2006ee5526fd9a03b5fd5f9af0c`，與 master 不同 SHA，內容可能不一致）→ <https://github.com/harmonoid/harmonoid/blob/ebc5dd7321edf2006ee5526fd9a03b5fd5f9af0c/macos/light-2/0.webp>

### 2.9 Spotube（Flutter，開源）

固定 SHA `69a310c78f5ceaf4eab7dfee98f187d38211c9ba`（分支 `master`）

- **播放頁是自底部升起的面板**（`lib/modules/player/player_overlay.dart`）：`SlidingUpPanel(maxHeight: screen height, minHeight: 63, parallaxEnabled: true, renderPanelSheet: false, header: SizedBox(height: 63, PlayerOverlayCollapsedSection), panelBuilder: PlayerView)` → <https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/modules/player/player_overlay.dart>
- **面板內版面**（`lib/modules/player/player.dart`）：`Column[ 封面 Container, SizedBox(60), 曲名/演出者區, 控制列(showQueue: false), Row[ Expanded(→ PlayerQueueRoute), SizedBox(10), Expanded(→ PlayerLyricsRoute) ] ]` —— **歌詞與佇列都是推出去的全頁 route，不是同頁面板**。
- **窄／寬切換（關鍵）**：`PlayerView` 內 `useEffect` 判斷 `mediaQuery.lgAndUp` 為真時，post-frame 直接 `panelController.close()` —— **大螢幕自動關閉播放面板**。
- **斷點值**（`lib/extensions/constrains.dart`）：`xs: 480.0, sm: 640.0, md: 820.0, lg: 1024.0, xl: 1280.0`；`lgAndUp` = width > 820 → <https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/extensions/constrains.dart>
- 歌詞頁獨立目錄：`lib/pages/lyrics/`（lyrics / mini_lyrics / plain_lyrics / synced_lyrics）；`lib/pages/player/`（lyrics / queue / sources）→ <https://github.com/team-spotube/spotube/tree/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/pages/lyrics>
- README 逐字：「**Time synced lyrics** regardless of the plugin support」→ <https://github.com/team-spotube/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/README.md>
- **官方截圖**（未下載）：桌面 `assets/branding/spotube-screenshot.png`、行動 `assets/branding/mobile-screenshots/combined.jpg` → <https://github.com/team-spotube/spotube/tree/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/assets/branding>
- **背景處理**：在 `player.dart` 未見取色或模糊封面邏輯 → **查不到**。

### 2.10 Finamp（Flutter，開源）

固定 SHA `0aae9d5ed530ffdf3d62ab12dab4f475a67687dc`（**預設分支為 `redesign`，非 `main`**）

- **封面大小**：`imageSize = min(MediaQuery.widthOf(context), MediaQuery.heightOf(context)) / 2`
- **橫豎向切換**：`MediaQuery.orientationOf(context)` 決定版面
- **歌詞／佇列位置**：兩者都是獨立 route —— 左滑開啟 `LyricsScreen`；`QueueList` 亦為獨立 route（`QueueButton`）
- **背景處理**：`if (ref.watch(finampSettingsProvider.useCoverAsBackground)) const BlurredPlayerScreenBackground()` —— **可切換的模糊封面背景**
- **相關設定項**：`playerScreenCoverMinimumPadding`、`prioritizeCoverFactor`（widthPercent = factor*2+49；minPercent = factor*2+34）、`hidePlayerBottomActions`、`suppressPlayerPadding`
- 全部出處：<https://github.com/finamp-app/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/screens/player_screen.dart>
- **官方截圖目錄**：`images/screenshots/` 下只有 `linux/` → <https://github.com/finamp-app/finamp/tree/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/images/screenshots>
- **窄視窗變化**：**未查證**（此為行動優先 UI）。

### 2.11 Feishin（開源，非 Flutter；Electron + React）

固定 SHA `b34ffda29e0fdafe771f9c3ef470df3be88a3d42`（分支 `development`）

- **左右分割**（`full-screen-player.module.css`）：`.image-column { width: 50%; height: 100% }`；`@media (orientation: portrait)` 時 `width: 100%; height: 50%`。無 active module 時加 `.image-column-full` → `width: 100%`（TSX 逐字：`[styles.imageColumnFull]: !hasActiveModule`）→ <https://github.com/jeffvli/feishin/blob/b34ffda29e0fdafe771f9c3ef470df3be88a3d42/src/renderer/features/player/components/full-screen-player.module.css>
- **右側模組（歌詞／佇列／related／visualizer）**：`activeTab ∈ {queue, related, lyrics, visualizer}`；`.grid-container { position: absolute; top: 0; right: 0; width: 50%; height: 100% }`；portrait 時 `bottom: 0; left: 0; width: 100%; height: 50%`；收合態 `.grid-container-collapsed { transform: translateX(100%) }`（portrait 為 `translateY(100%)`），`transition: transform 0.5s ease-out` → <https://github.com/jeffvli/feishin/blob/b34ffda29e0fdafe771f9c3ef470df3be88a3d42/src/renderer/features/player/components/full-screen-player-queue.module.css>
- **控制列位置**：`FullScreenPlayerControls` 在容器底部；設定鈕在左上（`.full-screen-player-controls-container`，預設 `opacity: 0.2`，容器 hover 時 `opacity: 1`）→ <https://github.com/jeffvli/feishin/blob/b34ffda29e0fdafe771f9c3ef470df3be88a3d42/src/renderer/features/player/components/full-screen-player.tsx>
- **背景處理（兩種並存）**：`dynamicBackground` 開啟時，`BackgroundImage` 以**專輯封面鋪滿**（`background-size: cover`）＋疊一層 `backdrop-filter: blur(var(--image-blur))` 的遮罩；底色用 `useFastAverageColor({ algorithm: 'dominant' })` **取主色**；再有可調透明度的黑色遮罩（`alpha = opacity/120`）。關閉時底色為 `var(--theme-colors-background)` **純色**。
- **容器尺寸**：`.container { position: absolute; inset: 0; z-index: 200; display: flex; justify-content: center }`、`.responsive-container { max-width: 2560px }`
- **手機版另有獨立檔案**：`mobile-fullscreen-player.tsx`、`mobile-fullscreen-player-album-art.tsx` 等 → <https://github.com/jeffvli/feishin/tree/b34ffda29e0fdafe771f9c3ef470df3be88a3d42/src/renderer/features/player/components>
- **官方截圖**（未下載）：`media/preview_full_screen_player.png` → <https://github.com/jeffvli/feishin/blob/b34ffda29e0fdafe771f9c3ef470df3be88a3d42/media/preview_full_screen_player.png>
- README 逐字提及：「Synchronized and unsynchronized lyrics support」、MPV 與 web player 後端 → <https://github.com/jeffvli/feishin/blob/b34ffda29e0fdafe771f9c3ef470df3be88a3d42/README.md>

### 2.12 Cider（閉源）

- `ciderapp/Cider` GitHub repo 已**封存**，描述為「🎵 Source code for Cider 1」，最後 push 2024-12-10 → <https://github.com/ciderapp/Cider>（**v2+ 無公開原始碼**）
- **官方 changelog**：4.0.27（2026-09-22，最新）、4.0.25（2026-09-10）、4.0.0（2026-06-16）、3.1.0（2025-09-26）→ <https://cider.sh/changelogs>
- **官方 devlog 逐字**（Cider Collective 的 itch.io devlog）：
  - 佈局名單：「**Calico** - Based on Mojave, features a split view styled layout. **Montara** - Based on Mavericks, features a split view styled. **Compact** – a new slim experience… **Compact Inline** – an alternate version… Navigation is now inlined with content.」
  - 窄視窗：「**Sidebar can now be shrunken into a "Compact" form, similar to AM. Sidebar is now space aware and will enter a popout mode if Window…**」
  - 背景：「The current tracks color scheme as the background supplied by the **Apple Music API**.」
  - 歌詞：「**Immersive** layout… Modeled after the original Immersive layout from the Cider 2.0」；「Lyrics can now be viewed from **miniplayer**」
  - 快捷鍵：「**Spacebar will now toggle music playback**」、「**Alt + Enter** will now enter Fullscreen for Windows & Linux」、「Various Keybinds added around the app, can be adjusted in **General -> Keybinds**」
  - 佇列：「Added "Play" button to items in the queue. Added "Remove" button to items in the queue.」
  → <https://cidercollective.itch.io/cider/devlog/674855/cider-v230>
- **2.3.2 devlog 逐字**：「**New Queue List** + Replaces the current queue with a new, more powerful queue list. Featuring multi-selection and a new UI.」；「New Experiment: **Mini Player single-line lyrics**」→ <https://cidercollective.itch.io/cider/devlog/697900/cider-v232-queue-library-updates>
- **「Sugar layout」一詞**：本輪在官方頁面**查不到**；前段對話提到的此名 → **撤回**。
- 遠端 App Store 頁面提到的「Immersive Lyrics」、橫向版面、垂直佇列，本輪**未重查** → 需複查。

---

## 3. 設計 token 的慣例

### 3.1 M3 的 token 分層與名稱

- **三層**：system token（前綴 `sys`）→ reference token（前綴 `ref`）→ component token。system token 指向 ref token，ref token 才指向靜態值。component token 官方標註「in development」，規範上必須指向 sys/ref token，**不可含 hex 等硬編碼值** → <https://m3.material.io/foundations/design-tokens>

**Spacing（M3 現在官方有 spacing scale）**

- 官方有專門的 spacing 頁（Styles > Spacing），三頁：overview / applying-spacing / tokens → <https://m3.material.io/styles/spacing>
- 逐字：「Spacing units follow an **8dp scale**. Rather than defining every value, Material only defines the most recommended spacing unit values on the scale.」
- 基準單位：**space100 = 8dp**，其餘是它的倍數（逐字：「multiplier from the baseline unit of 8dp, which is space100」）
- 官方列出的 spacing system token 名稱：**Space 75、Space 100、Space 125、Space 150、Space 175、Space 200、Space 250、Space 300、Space 400、Space 450、Space 500、Space 600、Space 700、Space 800、Space 900** → <https://m3.material.io/styles/spacing/tokens>
- 同頁逐字：「The range covers **0x to 9x**」、「The main spacing units are multiples of 8dp」，另有 nested units（0.25x / 0.5x / 0.75x / 1.25x），官方只定義常用的 nested 值（2dp、4dp、6dp、10dp）。對應值：space25=2、space50=4、space75=6、space100=8、space500=40、space600=48、space700=56、space800=64、space900=72。spacing overview 頁的圖說逐字寫「2, 4, 6, 8 at the bottom range and 48, 56, 64, 72 at the top」，與上述倍數一致。
- **兩頁說法不一致**：applying-spacing 頁逐字寫「A list of spacing system tokens from **100 to 400**」，但 tokens 頁列到 900 → <https://m3.material.io/styles/spacing/applying-spacing>。官方未解釋此差異 → **存疑**；space125/150/175 等的實際 dp 值是由 8dp 倍數推得 → **推測**。
- 官方明示用途（逐字，applying-spacing 頁）：「Apply these to your product's custom components and layouts, **replacing any hardcoded values**. If the right system token doesn't exist, customize the system and add your own.」
- component 屬性命名策略（逐字，tokens 頁）：未來一律用 `padding` / `margin` / `gap` + 方位詞（horizontal / vertical / leading / trailing / top / bottom）；舊稱用 `space`（leading-space、between-space 等）。

**Shape scale（corner radius）**

- 官方頁：<https://m3.material.io/styles/shape/corner-radius-scale>；M3 Expressive 另加 corner-radii 選項（Large increased 20dp、Extra large increased 32dp、Extra extra large 48dp）→ <https://m3.material.io/styles/shape/overview-principles>
- **可直接查證的官方值**：androidx Material3 `ShapeTokens.kt`（`// VERSION: 14_1_0`，GENERATED CODE）→ <https://github.com/androidx/androidx/blob/a4c33ed762b60043605a87d0f44367c8ee78b58b/compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/tokens/ShapeTokens.kt>

  | Token | 值 |
  |---|---|
  | CornerExtraSmall | `RoundedCornerShape(4.0.dp)` |
  | CornerSmall | `RoundedCornerShape(8.0.dp)` |
  | CornerMedium | `RoundedCornerShape(12.0.dp)` |
  | CornerLarge | `RoundedCornerShape(16.0.dp)` |
  | CornerLargeIncreased | `RoundedCornerShape(20.0.dp)` |
  | CornerExtraLarge | `RoundedCornerShape(28.0.dp)` |
  | CornerExtraLargeIncreased | `RoundedCornerShape(32.0.dp)` |
  | CornerExtraExtraLarge | `RoundedCornerShape(48.0.dp)` |
  | CornerFull | `CircleShape` |

  另有單邊變體 `CornerExtraSmallTop` / `CornerExtraLargeTop` / `CornerLargeStart` / `CornerLargeEnd`。Flutter 端對應的可覆寫介面是 `ThemeData.shapes`（`extraSmall` / `small` / `medium` / `large` / `extraLarge`；Expressive 再加 `largeIncreased` / `extraLargeIncreased` / `extraExtraLarge`）→ <https://github.com/androidx/androidx/blob/a4c33ed762b60043605a87d0f44367c8ee78b58b/compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/Shapes.kt>

**Type scale**

- 五個角色：**display、headline、title、body、label**，各三級共 15 個 style（M3 Expressive 另有 emphasized 變體）→ <https://m3.material.io/styles/typography/type-scale-tokens>、<https://m3.material.io/styles/typography/applying-type>
- M3 用 Major Second（1.125）音階，key base size = 14。
- 官方字級值（取自 Flutter `Typography.material2021` 的 `_M3Typography.englishLike`，該檔註解逐字寫「match the 2021 Material Design 3 specification」）→ <https://github.com/flutter/flutter/blob/a89783e103e4d68d3171b56fc6a04e92020d251f/packages/flutter/lib/src/material/typography.dart>

  | Token | fontSize | height | weight | letterSpacing |
  |---|---|---|---|---|
  | displayLarge | 57 | 1.12 | w400 | -0.25 |
  | displayMedium | 45 | 1.16 | w400 | 0.0 |
  | displaySmall | 36 | 1.22 | w400 | 0.0 |
  | headlineLarge | 32 | 1.25 | w400 | 0.0 |
  | headlineMedium | 28 | 1.29 | w400 | 0.0 |
  | headlineSmall | 24 | 1.33 | w400 | 0.0 |
  | titleLarge | 22 | 1.27 | w400 | 0.0 |
  | titleMedium | 16 | 1.50 | w500 | 0.15 |
  | titleSmall | 14 | 1.43 | w500 | 0.1 |
  | bodyLarge | 16 | 1.50 | w400 | 0.5 |
  | bodyMedium | 14 | 1.43 | w400 | 0.25 |
  | bodySmall | 12 | 1.33 | w400 | 0.4 |
  | labelLarge | 14 | 1.43 | w500 | 0.1 |
  | labelMedium | 12 | 1.33 | w500 | 0.5 |
  | labelSmall | 11 | 1.45 | w500 | 0.5 |

### 3.2 用 `ThemeExtension` 放間距／圓角的開源實例

**（A）Very Good Ventures `very_good_app_ui` brick —— 間距 token 進 ThemeExtension（最貼近本專案需求）**

- `very_good_app_ui/__brick__/lib/src/theme/app_spacing.dart`：`class AppSpacing extends ThemeExtension<AppSpacing>`，欄位 `double xxs/xs/sm/md/lg/xlg/xxlg`，預設 `xxs=4, xs=8, sm=12, md=16, lg=24, xlg=32, xxlg=48`，實作 `copyWith` 與 `lerp`（用 `lerpDouble`）。
- `app_theme.dart`：`ThemeData(... extensions: const [appColors, AppSpacing(), AppTextStyles()])`
- 取用：`lib/src/extensions/build_context_extensions.dart` 提供 `extension AppThemeBuildContext on BuildContext { AppSpacing get appSpacing => Theme.of(this).extension<AppSpacing>()!; }`
- Permalinks（SHA `038a0df18ec65fc4a6d9969715f7da008f795ca5`）：
  - <https://github.com/VeryGoodOpenSource/very_good_templates/blob/038a0df18ec65fc4a6d9969715f7da008f795ca5/very_good_app_ui/__brick__/lib/src/theme/app_spacing.dart>
  - <https://github.com/VeryGoodOpenSource/very_good_templates/blob/038a0df18ec65fc4a6d9969715f7da008f795ca5/very_good_app_ui/__brick__/lib/src/theme/app_theme.dart>
  - <https://github.com/VeryGoodOpenSource/very_good_templates/blob/038a0df18ec65fc4a6d9969715f7da008f795ca5/very_good_app_ui/__brick__/lib/src/extensions/build_context_extensions.dart>

**（B）YumNumm/EQMonitor —— 間距 token 進 ThemeExtension + codegen**

- `app/lib/core/designsystem/extensions/spacing_theme_extension.dart`：`@tailorMixinComponent class SpacingThemeExtension(...) extends ThemeExtension<SpacingThemeExtension> with _$SpacingThemeExtensionTailorMixin`，欄位 `xs=4, sm=8, md=12, lg=16, xl=20, xxl=24, xxxl=28, xxxxl=32`（用 `theme_tailor_annotation` 生成 `copyWith` / `lerp`）
- Permalink（SHA `c89d43b631221b6e1ed8a6e8ef7bf344d7ed68f7`）：<https://github.com/YumNumm/EQMonitor/blob/c89d43b631221b6e1ed8a6e8ef7bf344d7ed68f7/app/lib/core/designsystem/extensions/spacing_theme_extension.dart>

**（C）Floating-Dartists/flutter_dsfr —— 圓角 token 進 ThemeExtension（法國政府設計系統 DSFR 的 Flutter 移植）**

- `lib/src/theme/radius.dart`：`class DSFRRadius extends ThemeExtension<DSFRRadius>`（`const DSFRRadius.regular() : this._(small: const Radius.circular(4))`），另有 `class DSFRBorderRadius extends ThemeExtension<DSFRBorderRadius>` 包住 radius 並提供 `BorderRadius get small`；皆實作 `copyWith` / `lerp` / `==` / `hashCode`
- Permalink（SHA `a93fb4dfb861fa7620b35c965bc7079eeecfc2f7`）：<https://github.com/Floating-Dartists/flutter_dsfr/blob/a93fb4dfb861fa7620b35c965bc7079eeecfc2f7/lib/src/theme/radius.dart>

**反例**：`tommyxchow/frosty`（桌面 Flutter app）的 `FrostyColors extends ThemeExtension<FrostyColors>` 只放顏色；**它的間距與圓角是行內字面值**（`EdgeInsets.symmetric(horizontal: 12)`、`BorderRadius.all(Radius.circular(12))` 直接寫在 `ThemeData` 各 component theme 裡）→ <https://github.com/tommyxchow/frosty/blob/bb150ce42ad3904ad3222c3c3516511c593a870c/lib/theme.dart>。**即社群實際做法並不一致。**

### 3.3 以 lint／靜態規則禁止字面數字間距的先例

找到 3 個可查的例子，皆為 `custom_lint` 系 analyzer 規則（非 `dart_code_metrics`）：

**（A）pattobrien/lints —— `design_system_lints`（最完整，規則族）**

- `avoid_edge_insets_literal`（`AvoidEdgeInsetsLiteral extends LintRule`），訊息「Avoid hardcoded EdgeInsets values」，correction「Use values in design system spec instead」。實作：`visitInstanceCreationExpression`，判斷型別是否為 `EdgeInsets`，逐個 argument 檢查是否為 `Literal` 或非 design-system expression 就 `reportLint`。
- README 列出同套還有：`avoid_sized_box_height_width_literals`、`avoid_border_radius_literal`、`avoid_color_literal`、`avoid_icon_literal`、`avoid_text_style_literal`、`avoid_box_shadow_literal`。用 `sidecar` 套件建構。
- Permalinks（SHA `8b7d2ed0054ef4f31bc6d858600511126bac7208`）：
  - <https://github.com/pattobrien/lints/blob/8b7d2ed0054ef4f31bc6d858600511126bac7208/packages/design_system_lints/lib/src/avoid_edge_insets_literal.dart>
  - <https://github.com/pattobrien/lints/blob/8b7d2ed0054ef4f31bc6d858600511126bac7208/packages/design_system_lints/README.md>

**（B）bcblr1993/iot_devkit_flutter —— `avoid_raw_edge_insets`**

- `AvoidRawEdgeInsets extends DartLintRule`，`LintCode(name: 'avoid_raw_edge_insets', problemMessage: 'EdgeInsets uses a literal number. Prefer LabTokens.of(context).sXxx ...', errorSeverity: ErrorSeverity.WARNING)`。實作：`_edgeTypes = {'EdgeInsets','EdgeInsetsDirectional'}`，只當**至少一個參數是 `IntegerLiteral` 或 `DoubleLiteral`** 才告警；並有豁免清單 `_isExempt`（`/lib/ui/lab/`、`/test/`、`/tooling/`、`/integration_test/`）。
- Permalink（SHA `5e8bffe857cd500b78688b9156681c2dd37727c4`）：<https://github.com/bcblr1993/iot_devkit_flutter/blob/5e8bffe857cd500b78688b9156681c2dd37727c4/tooling/lab_lints/lib/rules/avoid_raw_edge_insets.dart>

**（C）weiping/kite —— `kite_no_hardcoded_spacing`**

- `packages/design/custom_lint/lib/no_hardcoded_style.dart`，`LintRule`，訊息「禁止硬編碼間距，請使用 AppSpacing 的令牌（packages/design）」。**該檔自述「狀態：骨架」**，visit 邏輯只以註解示意，未完成。
- Permalink（SHA `6832ac46da12fd2319dba0184cf11918d43425b9`）：<https://github.com/weiping/kite/blob/6832ac46da12fd2319dba0184cf11918d43425b9/packages/design/custom_lint/lib/no_hardcoded_style.dart>

- `dart_code_metrics` 本身：官方規則清單頁**查不到**（該套件已轉為商業產品 DCM）→ 查不到它有專門擋 `EdgeInsets` / `SizedBox` 字面值的規則名稱與出處。
- **注意**：三個例子都是小型／範例專案。**查不到大型 App 在 CI 擋字面間距的實例**。
- 與 FMP 現況的關係（事實）：FMP 走的是**測試**而非 lint —— `test/ui/static_rules/*_static_rule_test.dart` 以讀 `lib/` 原始碼的方式擋規則（見 `current-state.md` §7）。

---

## 4. 音樂播放器鍵盤快捷鍵（官方表）

### 4.1 Spotify 桌面（有官方表）→ <https://support.spotify.com/us/article/keyboard-shortcuts>

| 功能 | 鍵 |
|---|---|
| Play/Pause | Space |
| Filter（篩選） | Cmd + F 或 Ctrl + F |
| Go to Previous | Up Arrow |
| Go to Next | Down Arrow |
| Add to Library | Left Arrow |
| Add to Queue | Right Arrow |
| Mute/Unmute | M |
| Toggle Now Playing View Sidebar | Alt + Shift + R |
| Toggle Your Library Sidebar | Alt + Shift + L |
| Go to Queue | Alt + Shift + Q |
| Go to Now Playing | Alt + Shift + J |
| Open Search | Cmd + K 或 Ctrl + K |
| Go to Search | Ctrl/Cmd + Shift + L (Mac)、Ctrl/Cmd + L (Windows) |
| Open Context Menu | Alt + J |
| Select All | Cmd + A 或 Ctrl + A |
| Shuffle | Alt + S (Mac)、Ctrl/Cmd + S (Windows) |
| Repeat | Alt + R (Mac)、Ctrl/Cmd + R (Windows) |
| Go to Library／Playlists／Podcasts／Artists／Albums | Alt + Shift + 0／1／2／3／4 |

以上逐字出自同一頁。**Esc（返回）**：官方表**未列** → 查不到。

### 4.2 Apple Music（macOS，有官方表）→ <https://support.apple.com/guide/music/keyboard-shortcuts-mus1019/mac>

| 動作 | 快捷鍵 |
|---|---|
| Start playing or pause the selected song | **Space bar** |
| Play the currently selected song from the beginning | Return |
| Move forward or backward within a song（seek） | **Option-Command-Right Arrow / Left Arrow** |
| Stop playing the selected song | Command-Period |
| 播放中下一首 | **Right Arrow** |
| 播放中上一首 | **Left Arrow** |
| Show the currently playing song in the list | Command-L |
| Show the queue | **Option-Command-U** |
| 上／下一張專輯 | Option-Right Arrow / Option-Left Arrow |
| 音量 | Command-Up Arrow / Command-Down Arrow |
| 開等化器 | Option-Command-E |
| 章節前後 | Shift-Command-Right Arrow / Shift-Command-Left Arrow |
| 從 URL 串流 | Command-U |

- **Cmd+F 搜尋**：官方 Mac 表**未列**（Lifehacker 有列，屬第三方）→ 官方表查不到；**Esc**：官方表未列 → 查不到。
- Apple Music **Windows** 另有官方表（鍵位不同）→ <https://support.apple.com/guide/music-windows/keyboard-shortcuts-mus1019/windows>（本輪**未逐字重查內容**；第三方 Lifehacker 列出 Windows 為 Ctrl-Spacebar 播放/暫停、Ctrl-Alt-Left/Right seek → <https://lifehacker.com/tech/best-apple-music-keyboard-shortcuts-for-mac-pc-desktop>）

### 4.3 foobar2000（**查不到官方預設表**）

- 官方 FAQ 只解釋 global keyboard shortcut 的 context 綁定（逐字）：「For **global** keyboard shortcuts there is no way to chose a list of tracks automatically when they are used, so you have to chose a context when you bind the command.」——全頁沒有預設鍵表 → <https://www.foobar2000.org/FAQ>
- 第三方 defkey.com 聲稱官方預設 9 個：Ctrl+F（Search）、Ctrl+N（New playlist）、Ctrl+O（Open）、Ctrl+P（Preferences）、Ctrl+S（Save playlist）、Ctrl+U（Add location）、Ctrl+W（Remove playlist）、Ctrl+Enter（Properties）、Alt+A（Stay always on top）；並稱「All predefined shortcuts are **non-global**」→ <https://defkey.com/foobar2000-shortcuts>（**第三方**；注意其預設**沒有** Space 播放/暫停，也**沒有**方向鍵 seek）

### 4.4 YouTube Music（**查不到官方表**）

- YouTube Music **沒有**官方快捷鍵頁面（搜尋只找到第三方擴充與論壇討論）→ <https://github.com/lidel/google-music-hotkeys>（**第三方**）
- 鄰近產品 **YouTube** 有官方表（對照用，**不是** YouTube Music）→ <https://support.google.com/youtube/answer/7631406>：Spacebar（seek bar 被選取時）Play/Pause；`k` Pause/Play；`m` Mute/Unmute；**Left/Right arrow on the seek bar = Seek backward/forward 5 seconds**；`j` Seek backward 10 seconds；`Shift+N` next video；`Shift+P` previous video（僅播放清單）；`i` 開 Miniplayer；`SHIFT+?` 開清單。**Esc**：該表未列 → 查不到。
- 第三方（9to5Google）：YouTube Music 桌面 PWA「supports your device's **media keyboard shortcuts** to play, pause, and skip」→ <https://9to5google.com/2019/10/28/youtube-music-desktop-pwa/>

### 4.5 桌面焦點順序（focus traversal）的官方 API 與社群實例

**官方 API 文件**

- `FocusTraversalGroup` <https://api.flutter.dev/flutter/widgets/FocusTraversalGroup-class.html>（逐字）：「A widget that describes the inherited focus policy for focus traversal for its descendants, **grouping them into a separate traversal group**.」；「A traversal group is treated as one entity when sorted by the traversal algorithm.」；「Within the group, it will use the given policy to order the elements」；「The group itself will be ordered using the parent group's policy.」預設「traverses in reading order using `ReadingOrderTraversalPolicy`」。參數 `policy`、`descendantsAreFocusable`、`descendantsAreTraversable`。
- `FocusTraversalOrder` <https://api.flutter.dev/flutter/widgets/FocusTraversalOrder-class.html>：搭配 `OrderedTraversalPolicy`；`NumericFocusOrder` / `LexicalFocusOrder` 兩種 `FocusOrder`。官方 focus 指南有 `FocusTraversalGroup(policy: OrderedTraversalPolicy(), child: Row(children: [ ... FocusTraversalOrder(order: const NumericFocusOrder(2), ...) ]))` 的完整範例 → <https://docs.flutter.dev/ui/interactivity/focus>
- `TraversalEdgeBehavior` <https://api.flutter.dev/flutter/widgets/TraversalEdgeBehavior.html>：「Controls the focus transfer at the edges of a `FocusScopeNode`」：`closedLoop`（停在 scope 內、繞回另一端）、`leaveFlutterView`、`parentScope`（無 parent 時 fallback 回 `closedLoop`）、`stop`。`showDialog` 預設 `closedLoop`；`Navigator` 有 `routeTraversalEdgeBehavior` / `routeDirectionalTraversalEdgeBehavior` → <https://api.flutter.dev/flutter/widgets/showDialog.html>、<https://api.flutter.dev/flutter/widgets/Navigator-class.html>
- `FocusScope` vs `FocusTraversalGroup` 的差別（逐字，<https://api.flutter.dev/flutter/widgets/FocusScope-class.html>）：「If you just want to group widgets together in a group so that they are traversed in a particular order, **but the focus can still leave the group**, use a `FocusTraversalGroup`.」——`FocusScope` 會限制焦點不能離開；只要分組排序就用 `FocusTraversalGroup`。

**社群實例（用 `FocusTraversalGroup` 分組）**

- **DonutWare/Fladder（Flutter Jellyfin 桌面／TV client）**：`lib/widgets/navigation_scaffold/components/side_navigation_bar.dart:145` 為 `FocusTraversalGroup(policy: _RailTraversalPolicy(), child: ...)`，`class _RailTraversalPolicy extends ReadingOrderTraversalPolicy`（第 241–242 行）→ **導航 rail 自成一組**；`lib/widgets/navigation_scaffold/components/navigation_body.dart:73` 為 `FocusTraversalGroup(policy: GlobalFallbackTraversalPolicy(fallbackNode: navBarNode), child: ...)` → **內容區自成一組，且提供 fallback 節點接到導航列**。另有 `lib/widgets/shared/grid_focus_traveler.dart:36` 與自製 `FocusRow`。Permalinks（SHA `91992fcd48cd83baaac1a979345e386e43beddc0`）：
  - <https://github.com/DonutWare/Fladder/blob/91992fcd48cd83baaac1a979345e386e43beddc0/lib/widgets/navigation_scaffold/components/side_navigation_bar.dart>
  - <https://github.com/DonutWare/Fladder/blob/91992fcd48cd83baaac1a979345e386e43beddc0/lib/widgets/navigation_scaffold/components/navigation_body.dart>
- **gskinnerTeam/flutter-adaptive-demo**：`lib/main_app_scaffold.dart:107` 為 `return FocusTraversalGroup(child: page ?? Container());` → 把「每個 page 內容」包成獨立 traversal group（預設 ReadingOrderTraversalPolicy）。Permalink（SHA `e8f05b33c0d37744a453f67bd73912e7e5fcfc4f`）：<https://github.com/gskinnerTeam/flutter-adaptive-demo/blob/e8f05b33c0d37744a453f67bd73912e7e5fcfc4f/lib/main_app_scaffold.dart>
- **MahanRahmati/Arna**：`lib/src/base/side_scaffold.dart:164,263`、`lib/src/base/tab_view.dart:264,309` 皆出現 `FocusTraversalGroup(`（其餘檔為搜尋命中，未逐一開檔）。Permalink（SHA `c50ffcf0f0aa2c213923013c85201df429607b72`）：<https://github.com/MahanRahmati/Arna/blob/c50ffcf0f0aa2c213923013c85201df429607b72/lib/src/base/side_scaffold.dart>
- **查不到**任何「官方建議把導航區／內容區／播放控制列分成三個 tab group」的 Flutter 官方文件或設計指引。官方只描述 API 語意 → **官方指引層級：查不到**；分組實作只有上述社群實例。

---

## 5. 使用者指南：內建說明頁 vs 連到網站文件

| App | 結論 | 證據（固定 SHA permalink） |
|---|---|---|
| **Spotube** | **兩者都有，但 app 內只有 About 頁**（無 FAQ／說明頁）；About 連到官網與 GitHub/Discord。官網 `website/` 內有完整 docs（`website/src/content/docs/*.mdx`）。另有 onboarding：`lib/pages/getting_started/`（greeting / playback / region / support）。 | `lib/pages/settings/sections/about.dart` 內 `launchUrlString("https://spotube.krtirtho.dev")`、`https://github.com/KRTirtho/spotube`、`https://discord.gg/uJ94vxB6vg`、LICENSE、opencollective。<br><https://github.com/KRTirtho/spotube/blob/69a310c78f5ceaf4eab7dfee98f187d38211c9ba/lib/pages/settings/sections/about.dart> |
| **Namida** | **內建 About 頁**，連到 GitHub / Telegram / Discord，並從 GitHub raw 抓 `CHANGELOG.md` 在 app 內顯示；**查不到**官方文件網站。另有 `lib/ui/pages/onboarding.dart`。 | `lib/ui/pages/about_page.dart`：`link: 'https://github.com/MSOB7YY'`、`https://t.me/namida_official`、`https://discord.gg/WeY7DTVChT`、`Rhttp.get('https://raw.githubusercontent.com/namidaco/namida/main/CHANGELOG.md')`。<br><https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/ui/pages/about_page.dart> |
| **Finamp** | **內建 About dialog**（用 Flutter 內建 `showAboutDialog`），連到 GitHub repo / releases / Weblate；**查不到** app 內連到文件網站，也查不到專案有獨立文件站（repo 有 GitHub wiki，`has_wiki = true`）。 | `lib/screens/settings_screen.dart`：`repoLink = "https://github.com/finamp-app/finamp"`、`releaseNotesLink = ".../releases"`、`translationsLink = "https://hosted.weblate.org/projects/finamp"` + `showAboutDialog(...)`。<br><https://github.com/jmshrv/finamp/blob/0aae9d5ed530ffdf3d62ab12dab4f475a67687dc/lib/screens/settings_screen.dart> |
| **Feishin** | **連到外部網站／GitHub**：Electron 原生選單有 `Help`（`role: 'help'`），項目全部 `shell.openExternal` 到 GitHub（**無內建說明頁**）。 | `src/main/menu.ts` 的 `subMenuHelp`：`'Learn More'` → github repo；`'Documentation'` → `https://github.com/jeffvli/feishin?tab=readme-ov-file#getting-started`（**用 README 當文件**）；`'Community Discussions'` → `/discussions`；`'Search Issues'` → `/issues`；末項顯示版本。<br><https://github.com/jeffvli/feishin/blob/b34ffda29e0fdafe771f9c3ef470df3be88a3d42/src/main/menu.ts> |
| **LocalSend** | **兩者都有**：內建 About 頁 + 內建「說明」dialog。 | `app/lib/pages/about/about_page.dart`：`launchUrl('https://localsend.org')`（Homepage）、GitHub、Codeberg、Apache License、`LicensePage()`、`DebugPage()`。另有 app 內說明 dialog：`app/lib/widget/dialogs/send_mode_help_dialog.dart`。<br><https://github.com/localsend/localsend/blob/6f6cd3ee496903e2206c51ffa3a13a5d10bc340b/app/lib/pages/about/about_page.dart> |
| **NewPipe** | **兩者都有**：內建「About & FAQ」畫面，FAQ 條目連到官網 FAQ。 | `shared/src/commonMain/kotlin/net/newpipe/app/screen/about/AboutPage.kt` 內有 `url = Constants.URL_FAQ`、`Res.string.view_on_github`、donation、website。常數在 `shared/src/androidMain/kotlin/net/newpipe/Constants.kt`：`URL_GITHUB`、`URL_DONATION`、`URL_WEBSITE`、`URL_PRIVACY`、`URL_FAQ`。strings：`tab_about = "About & FAQ"`、`faq = "View on website"`。<br><https://github.com/TeamNewPipe/NewPipe/blob/7e5df38aad4b2c035332b3f71aee3064d4fdaae4/shared/src/commonMain/kotlin/net/newpipe/app/screen/about/AboutPage.kt> |

**商業桌面版的 Help 選單**

- **Spotify（Windows/macOS 桌面）**：桌面版左上「三點選單」有一個 **Help** 子選單，內含 **Troubleshooting** 等項目（社群貼文描述操作路徑「three dots menu at the top left corner > Help > Troubleshooting」）→ <https://community.spotify.com/t5/Desktop-Windows/I-keep-getting-the-quot-something-went-wrong-quot-error-in/td-p/6588569>。是否直接開瀏覽器到 `support.spotify.com` → **查不到官方明文，推測**。
- **Apple Music（macOS）**：**查不到**可靠來源證實其 Help 選單內容或是否連到網站。（推測：macOS app 的 Help 選單通常開 Apple 說明書／支援頁，但無可直接引用的出處。）
- **YouTube Music（桌面）**：桌面版是網頁／PWA（`music.youtube.com`），**查不到**有原生 Help 選單的內建說明；**查不到**任何原生桌面 app 內建說明的證據。

---

## 本檔最不確定的 5 件事

1. **M3 寬度 class 的 Large（1200–1599dp）與 m3.material.io 的表格正文**：該站是 JS render，取不到正文；數值是 `developer.android.com` 的逐字表格與搜尋索引摘要拼合而成，Large 的上界是由 Extra-large（≥1600dp）反推。
2. **M3 spacing token 的完整值表**：overview 頁暗示 2/4/6/8…48/56/64/72，applying-spacing 頁寫「tokens from 100 to 400」，tokens 頁列到 900 —— 三者不一致，未找到官方調和說法；space125/150/175 的實際 dp 值是推得。
3. **Apple Music macOS 的「窄視窗 → MiniPlayer」行為**：官方只寫在 Apple Music **Classical 的 web** 說明頁，macOS Music 是否同規則無官方逐字來源。
4. **Spotify 的全螢幕模式、封面尺寸與背景處理**：只有官方社群版主回覆與社群公告，無支援文件；「全螢幕整合進 Now Playing view、可切 Album view / Artist banner view」是版主回覆而非正式文件。
5. **YouTube Music 與 foobar2000 的快捷鍵**：兩者都無官方預設表；foobar2000 的 9 個預設完全依賴第三方 defkey.com，且「預設沒有 Space 播放/暫停」需自行確認。另：Namida / Harmonoid / Finamp 的窄視窗切換門檻**未經真機或官方截圖驗證**，只讀到程式碼片段。
