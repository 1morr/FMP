# 04 — UI / UX、佈局與設計語言審查

- **審查日期**：2026-09-02
- **HEAD**：`679f7829`（審查開始時 `git status --short` 空；本輪只新增 `docs/review/assets/04-ui-ux/` 下的 28 張截圖，未修改任何程式碼、文檔或 git 歷史）
- **範圍**：E（UI / UX 與佈局）＋ Detail Panel 規範性判定 ＋ 設計語言可切換性評估 ＋ issue #36
- **環境**：Flutter 3.47.1 stable（revision `6655482ec0`, 2026-08-19）/ Windows 11 主機 ＋ AVD `Medium_Phone`（411×914dp）與 `Medium_Tablet`（1280×800dp / 800×1280dp）。**Windows、Android 手機、Android 平板三種尺寸都實跑過**，截圖在 `docs/review/assets/04-ui-ux/`。
- **本輪只做審查與規劃**：未改碼、未刪文檔、未動 git 歷史、未關 issue。

> 標記約定：**【事實】**＝有 `file:line`、指令輸出、截圖或實跑觀察佐證；**【推論】**＝由事實推導；**【建議】**＝行動提案，附成本（S/M/L）、風險、可逆性；**【未驗證】**＝查不到或被阻塞。

---

## 目錄

1. [摘要](#摘要)
2. [現況 A：斷點與響應式骨架](#1-現況a斷點與響應式骨架)
3. [現況 B：Detail Panel](#2-現況bdetail-panel)
4. [現況 C：資訊架構與首頁](#3-現況c資訊架構與首頁)
5. [現況 D：空狀態 / 載入 / 錯誤](#4-現況d空狀態--載入--錯誤)
6. [現況 E：無障礙](#5-現況e無障礙)
7. [現況 F：設計語言與 token 層](#6-現況f設計語言與-token-層)
8. [現況 G：Windows 與 Android 差異](#7-現況gwindows-與-android-差異)
9. [問題清單 P0–P3](#8-問題清單-p0p3)
10. [成熟做法對照](#9-成熟做法對照)
11. [建議方案](#10-建議方案)
12. [重寫 vs 漸進重構](#11-重寫-vs-漸進重構)
13. [需要你決策的點](#12-需要你決策的點)
14. [Quick wins](#13-quick-wins)
15. [issue #36 的裁決](#14-issue-36-的裁決)
16. [驗證記錄](#15-驗證記錄)

---

## 摘要

**0.（最重要）在 Android 平板上，「播一首歌」就會讓首頁少掉一整個內容來源 —— Windows 與 Android 兩個平台都實測拍到了。**

`home_page.dart:67-69` 用 `Breakpoints.getLayoutType(maxWidth)` 決定首頁排行榜要顯示幾個音源（desktop → 3，其餘 → 2），但 `:234` 傳進去的 `maxWidth` 是 `LayoutBuilder` 量到的**內容區寬度**，不是視窗寬度。內容區 = 視窗 − 導覽軌(72) − 分隔線(1) − 面板(380+6)。於是：

| 視窗寬 | 面板狀態 | 內容區寬 | 首頁排行榜 | 截圖 |
|---|---|---|---|---|
| 1700dp | 收起（36dp） | ≈1591dp | **3 個**（嗶哩嗶哩／YouTube／網易雲音樂） | `win-07-1700-3sources.png` |
| 1700dp | 拖到上限（500dp） | ≈1121dp | **2 個**（網易雲音樂消失） | `win-08-1700-panelmax-drops-source.png` |

使用者只是把側邊面板拖寬，網易雲音樂排行榜就整欄不見了，沒有任何提示、沒有任何 affordance。這是把「視窗級斷點」餵給「內容區寬度」造成的，不是設計取捨。同一個 bug 讓 1250dp 視窗即使面板收起也永遠只看得到 2 個音源（`win-06-panel-collapsed.png`）。

**而在 Android 平板上，這個 bug 的門檻低到不需要任何拖動。** `ResponsiveScaffold` 只看寬度不看平台（`responsive_scaffold.dart:76-79`），所以 1280×800dp 的平板橫向就走桌面佈局：

| 平板 1280dp 橫向 | 內容區寬 | 首頁排行榜 | 截圖 |
|---|---|---|---|
| 尚未播放（無面板） | 1208dp | **3 個** | `and-04-tablet-1280-land.png` |
| **點一首歌播放**（面板預設 380dp 展開） | 822dp | **2 個**（網易雲音樂消失） | `and-05-tablet-1280-panel.png` |

Windows 上需要 1700dp 視窗加手動拖到上限才會觸發；平板上**只要開始聽歌就會觸發**，而且沒有任何不收起面板就能救回來的辦法。

**1. 你問的「Detail Panel 可拖動、上限 50%」—— 上限不是 50%，是寫死的 500dp 絕對值，而且拖完的寬度不會被記住。**

`responsive_scaffold.dart:204-206`：

```dart
double _detailPanelWidth = 380; // 默认宽度
static const double _minPanelWidth = 280.0;
static const double _maxPanelWidth = 500.0;
```

全庫沒有任何百分比上限（`rg` 在 `lib/ui/layouts` 與 `lib/ui/widgets/panels` 找不到 `width * 0.x` 形式的面板寬度）。這三個都是 `_DesktopLayoutState` 的普通 State 欄位，`Settings` Isar model 沒有對應欄位，`lib/ui` 全域零 `SharedPreferences` —— **面板寬度、面板展開狀態、導覽軌展開狀態三者每次啟動都重置**。

「可拖動」本身**是規範做法**：M3 明文把「音樂 App 側邊的播放器」列為 standard side sheet 的範例用途，並定義 spacer 內含 drag handle 用來調整 pane 寬度。FMP 偏離規範的是**數值與 affordance**，不是「可不可以拖」（見 §9.1）。

**2. 三層斷點少了 M3 的一整層，而那一層正好是「Windows 視窗貼半螢幕」的常態尺寸。**

`breakpoints.dart` 只有 600 / 1200 兩個切點。M3 現行斷點是 600 / 840 / 1200 / 1600 五段。FMP 把 M3 的 Medium(600–839) 與 Expanded(840–1199) 合併成同一個「tablet」，兩者都只給 72dp 導覽軌、**完全沒有 Detail Panel**。1920×1080 螢幕上把視窗貼左半邊 = 960dp，正好落在這個洞裡：M3 說這已經該是兩欄佈局，FMP 給的是單欄（`win-02-1199.png`）。

**3. 無障礙基本上是零。**

`lib/ui` 全部 121 檔裡 `Semantics(` 只出現 **2 次**（都在標題列），`semanticLabel:` **0 次**，`textScaler` / `textScaleFactor` 在整個 `lib/` **0 次**（沒有任何字級上限保護），`test/` 裡 `meetsGuideline` / `AccessibilityGuideline` **0 次**。96 個 `IconButton` 有 27 個沒有 tooltip。迷你播放器的進度條是手刻 `GestureDetector`（`mini_player.dart:145-183`），對讀屏軟體完全不存在。

**4. 底部導覽 6 個目的地，M3 規範上限是 5。**

M3 Navigation bar guidelines：「Navigation bars provide access to **three to five** destinations」「Can contain 3-5 destinations of equal importance」。FMP 是首頁／搜尋／佇列／音樂庫／電台／設定 = 6（`responsive_scaffold.dart:28-58`，`and-01-home.png`）。

**5.「Material 3 + dynamic_color」的現況描述不成立 —— `dynamic_color` 是死依賴。**

`pubspec.yaml:15` 宣告 `dynamic_color: ^1.7.0`，但 `rg "dynamic_color|DynamicColorBuilder|CorePalette"` 在 `lib/` 命中 **0 次**（round 01 已記過同一件事，`docs/review/01-docs-structure-tests.md:1106`）。實際配色是 `ColorScheme.fromSeed` + 9 個寫死的預設色（`theme_preset_colors.dart:19-29`），沒有系統取色。

**6.「可切換設計風格（Material ↔ 液態玻璃）」的答案是：現在不值得，而且卡在套件而不是卡在你的架構。**

`liquid_glass_renderer`（885 likes，社群事實標準）最新版是 **0.2.0-dev.4，9 個月沒發新版**，pub 宣告支援平台只有 **Android / iOS / macOS**，README 第一句是「EXPERIMENTAL - USE WITH CAUTION ... should not be blindly added to production apps」。FMP 的兩個目標平台之一是 Windows。詳細取捨見 §10.4。

**7. 播放頁在寬螢幕的做法，在六個成熟對照組裡是獨一份 —— 而且獨的方向不對。**

FMP 的播放頁用一個布林值（寬度 ≥1200）切兩套版面，寬版把 **58%（`flex: 7`）的畫面固定給歌詞欄**。查了 Finamp / Harmonoid / Spotube / Auxio / Symphony / Spotify 桌面之後：**沒有任何一個把播放頁的多數面積固定給歌詞**；Harmonoid 與 Spotube 甚至根本不給播放頁做桌面雙欄（Spotube 在 >1024dp 時主動 `panelController.close()` 把展開式播放頁關掉）。而真的做雙欄的兩個（Auxio、Symphony）切換依據是**高度**或**寬高比**，不是寬度 —— 這正好對上我拍到的失效畫面：800dp 直向平板上封面撐到 742dp、吃掉 60% 的**高度**，而 FMP 的條件完全不看高度，所以永遠不會切換。詳見 §3.6 / §9.3d，方案見 §10.3b。

**8. 一個一行的文案 bug，在播放器頁面上直接看得到。**

`player_page.dart:488` 寫 `track?.artist ?? t.player.selectTrackToPlay`。`??` 把「沒有歌曲」和「歌曲沒有藝術家」兩件事合併了，所以**正在播放一首沒有藝術家欄位的歌時，播放器標題底下寫著「Select a track to start playing」**（`and-02-player.png`）。本輪在 Windows 上又拍到中文版：標題「D8 youtube verify」、底下「選擇一首歌曲開始播放」，而同一畫面的進度條正走在 0:40 / 3:39（`win-14-player-wide-1280.png`）。同一個條件在 `home_page.dart:1088,1177` 用的是正確的 `t.general.unknownArtist`。

---

## 1. 現況A：斷點與響應式骨架

### 1.1 斷點定義只有三段【事實】

`lib/core/constants/breakpoints.dart:6,9`：

```dart
static const double mobile = 600;   // < 600  → mobile
static const double tablet = 1200;  // 600–1199 → tablet；>= 1200 → desktop
```

對照 Material 3 現行斷點（`m3.material.io`，2026-05 改版後把 window size class 更名為 breakpoints）與 `androidx.window` 的常數：

| M3 breakpoint | 範圍 | M3 建議 | FMP 對應 | FMP 實際給的 |
|---|---|---|---|---|
| Compact | `< 600dp` | 底部導覽列、單欄 | mobile | ✅ `NavigationBar` + 單欄 |
| Medium | `600–839dp` | 導覽軌、可開始兩欄 | tablet | 72dp 軌，**單欄** |
| Expanded | `840–1199dp` | **兩欄** | tablet | 72dp 軌，**單欄** |
| Large | `1200–1599dp` | 兩欄，fixed pane 412dp | desktop | 可收合軌 + 380dp 面板 |
| Extra-large | `>= 1600dp` | 兩欄 + side sheet 當第三欄 | desktop | 同上（無額外變化） |

`WindowSizeClass.WIDTH_DP_EXPANDED_LOWER_BOUND = 840`、`WIDTH_DP_EXTRA_LARGE_LOWER_BOUND = 1600`（`developer.android.com/reference/kotlin/androidx/window/core/layout/WindowSizeClass`）。

**【推論】** FMP 缺的是 840 這一刀。840–1199dp 這個區間在桌面上非常常見（1920 螢幕貼半邊 = 960dp、1440 螢幕貼半邊 = 720dp 落在 Medium），而 FMP 在整個區間都拒絕顯示 Detail Panel。實測：`win-02-1199.png`（1199dp）與 `win-03-1201.png` 版面完全相同 —— 都是 tablet 佈局。

### 1.2 斷點消費點只有 5 處，其餘用臨時數字【事實】

`Breakpoints.*` 在 `lib/ui` 的全部呼叫點：

| file:line | 用途 |
|---|---|
| `responsive_scaffold.dart:77` | 決定 mobile / tablet / desktop 三種骨架 |
| `home_page.dart:67` | 首頁排行榜的軸向與最大音源數（§3.1 的 bug 源頭） |
| `player_page.dart:82` | 播放器單欄 vs 封面＋歌詞雙欄 |
| `radio_player_page.dart:51` | 電台頁 `contentMaxWidth` 720 vs 420 |
| `mini_player_volume_control.dart:35` | 音量控制 popup vs inline |

繞過 `Breakpoints` 自己比大小的地方（都是一次性字面值，沒有共用常數）：

| file:line | 門檻 | 用途 |
|---|---|---|
| `account_management_page.dart:269` | **520** | 帳號卡片的操作按鈕是否換行堆疊 |
| `color_palette_button.dart:178,179` | **320 / 360** | 取色對話框內距 |
| `lyrics_style_dialog.dart:167,168` | **400 / 360** | 歌詞樣式對話框內距 |

**【事實】** 全 `lib/ui` **沒有任何一個 `FractionallySizedBox`**；比例式尺寸全部是手算（`(constraints.maxWidth / 4).clamp(100.0, 140.0)` 在 `home_page.dart:399,432,686` 重複三次）。`Expanded(flex:)` 只有 6 處，其中 `responsive_scaffold.dart:243` 的 `flex: 2` 是無效的（同一個 `Row` 裡只有它一個 `Expanded`，flex 值不影響結果）。

### 1.3 尺寸常數集中度：只有一半【事實】

`lib/core/constants/ui_constants.dart` 提供 `AppRadius`(7 階)、`AnimationDurations`(6 階)、`AppSizes`(7 個)、`ImageTargetSizes`(6 階)、`ToastDurations`、`DebounceDurations`、`AppShadows`(1 個)、灰階矩陣。

沒有提供、因此散落在各檔的：

- **間距 scale** —— `lib/ui` 有 **260 個** `EdgeInsets.*(...)` 字面值，沒有 `AppSpacing`。M3 2026 改版明確引入了 spacing system，並規定 large / extra-large 佈局的 margin 與 pane spacer 都是 24dp；FMP 的對應數字是 16（`home_page.dart:264`）與 6（面板分隔線）。
- **版面尺寸 token** —— 導覽軌 `72`/`256`、面板 `380`/`280`/`500`、對話框 `400`（7 個檔案各寫一次）、grid `maxCrossAxisExtent` `200`/`160`/`100` 全是 inline 字面值。
- **動效曲線** —— 有時長沒有曲線，`Curves.*` 在 `lib/ui` inline 出現 13 次。
- **字體階層別名** —— 直接用 `Theme.of(context).textTheme.*`，沒有語意層（`AppText.trackTitle` 之類）。

`AppSizes.thumbnailSmall/Medium/Large`（40/48/56）已經存在，但 40/48/56 仍以字面值出現在 20 多處（例如 `search_page.dart:1026,1445,1563-1584`、`radio_mini_player.dart:103-109`）——**常數存在但沒有被強制使用**。

---

## 2. 現況B：Detail Panel

### 2.1 它是什麼，怎麼定尺寸【事實】

`responsive_scaffold.dart:196-206`（`_DesktopLayoutState`）：

```dart
bool _isNavExpanded = false;        // 默认收起
bool _isDetailPanelExpanded = true; // 详情面板默认展开
double _detailPanelWidth = 380;     // 默认宽度
static const double _minPanelWidth = 280.0;
static const double _maxPanelWidth = 500.0;
```

- 只在 `LayoutType.desktop`（>= 1200dp）出現，且只在 `hasTrack`（有歌或有電台播放 UI）時才掛上（`:247-248`）。**沒有播放內容時整個面板連同分隔線一起消失，主內容區寬度突變。**
- 展開時總寬 = `_detailPanelWidth + 6`；收起時 36dp，hover 時 54dp（`:346-348`）。
- 拖動把手：`Container(width: 6, color: Colors.transparent)` 裡放一條 `width: 1` 的 `outlineVariant` 線（`:406-417`），`MouseRegion(cursor: resizeColumn)` + `GestureDetector(onHorizontalDragUpdate)`（`:393-405`）。
- 收起後變成一條 36dp 的長條，中間一個 `Icons.first_page`，整條可點回展開（`:361-366, 434-455`）。

實測（`win-04-1250-panel.png` → `win-05-panel-maxdrag.png`）：在 1250dp 視窗把分隔線往左拖到底，面板停在 500dp，主內容區被壓到 ≈744dp，排行榜標題全部截斷成「华强见宋老虎 ...」「JENNIE - FALLE...」。

### 2.2 「上限 50%」不存在【事實】

`_maxPanelWidth = 500.0` 是**絕對像素**，與視窗寬度無關。實際佔比：

| 視窗寬 | 面板 500dp 佔比 |
|---|---|
| 1200dp（desktop 下限） | 41.7% |
| 1920dp（1080p 全螢幕） | 26.0% |
| 3440dp（ultrawide） | **14.5%** |

也就是說：小視窗時 500dp 太寬（吃掉主內容區的 40%），大視窗時 500dp 太窄（在 34 吋帶魚屏上，這個面板細得像一條側欄）。**絕對上限的方向剛好和需求相反** —— 螢幕越大，使用者越可能想要更寬的資訊面板。

### 2.3 拖完的寬度不會被記住【事實】

`_detailPanelWidth` / `_isDetailPanelExpanded` / `_isNavExpanded` 都是 `State` 欄位：

- `lib/data/models/settings.dart` 沒有對應欄位（`rg "panelWidth|navExpanded|detailPanel" lib/data lib/providers` 無命中）。
- `lib/ui` 全域 **零** `SharedPreferences`。
- 因此每次冷啟動：導覽軌收起、面板展開、寬度 380。

同一份 `State` 還有另外幾個「應該記住但沒記」的欄位（`lyrics_window.dart:198,202,203` 的 `_alwaysOnTop` / `_transparentMode` / `_singleLineMode`；`player_page.dart:71` 與 `track_detail_panel.dart:97` 各自一份 `_showLyrics`）。

### 2.4 拖動把手的可用性【事實 ＋ 推論】

- 命中區只有 **6dp 寬**（`:406`），視覺上只有 **1dp** 的線。M3 規定 large / extra-large 佈局的 pane spacer 是 **24dp**，且「如果 pane 可以調整大小，spacer 內要放一個 drag handle」。FMP 的 6dp 沒有任何 drag handle 圖形。
- **只有 hover 游標會變**，沒有任何靜態視覺提示。**【推論】** 觸控／鍵盤使用者無從發現這條線可以拖；6dp 也遠低於任何觸控目標建議值。
- 拖動時 `AnimatedContainer` 的 duration 被切成 `Duration.zero`（`:370-372`），這個處理是對的。

---

## 3. 現況C：資訊架構與首頁

### 3.1 首頁六個區塊，順序寫死，其中三個講同一件事【事實】

`home_page.dart:108-133`：

```dart
HomeRankingsSection(),      // 排行榜
_RecentPlaylistsSection(),  // 我的歌單
_RadioSection(),            // 電台
_NowPlayingSection(),       // 正在播放
_QueuePreviewSection(),     // 佇列預覽
_RecentHistorySection(),    // 最近播放
SizedBox(height: 100),      // 为迷你播放器留出空间
```

順序是硬編碼的 `Column` children，使用者不能重排也不能隱藏（只有排行榜的**音源**可以在設定裡排序／開關，`enabledHomeRankingSourceOrderProvider`）。

**【推論】** 後三個區塊（正在播放／佇列預覽／最近播放）都是「播放狀態」的不同切片。在桌面版同一畫面上，同一首歌會同時出現在：① 首頁「正在播放」卡片 ② 底部迷你播放器 ③ 右側 Detail Panel —— **三份**（`win-01-home-1400.png` 可同時看到全部三處都是「D8 youtube verify」）。

`SizedBox(height: 100)` 是手算的底部留白，而迷你播放器實際高度是 64（`mini_player.dart:59`），Android 上還要再加 `NavigationBar`。這個數字沒有任何來源，也不會隨佈局變化。

### 3.2 排行榜音源數的 bug【事實，已實測】

見 §摘要 0。程式路徑：

```dart
// home_page.dart:232-238
return LayoutBuilder(builder: (context, constraints) {
  final plan = buildHomeRankingLayoutPlan(
    maxWidth: constraints.maxWidth,   // ← 內容區寬度
    ...
// home_page.dart:66-69
  final layoutType = Breakpoints.getLayoutType(maxWidth);
  final axis = layoutType == LayoutType.mobile ? Axis.vertical : Axis.horizontal;
  final maxSources = layoutType == LayoutType.desktop ? 3 : 2;
```

`Breakpoints` 的三段語意是**視窗級**的（決定 bottom nav / rail / 三欄），拿來判斷一個 pane 內部要放幾欄是語意錯置。`test/ui/pages/home/home_ranking_sources_test.dart` 有 5 條測試覆蓋 `buildHomeRankingLayoutPlan`，但它們直接餵 `maxWidth`，因此**測試永遠測不到「視窗夠寬但內容區不夠寬」這個真實情境**。

**【事實】** 實測序列：1250dp 視窗（面板展開 380）→ 2 源；1250dp（面板收起 36）→ 仍 2 源；1700dp（面板收起）→ 3 源；1700dp（面板拖到 500）→ 退回 2 源。

要在面板預設展開下看到第三個音源，視窗必須 ≥ `1200 + 72 + 1 + 386 = 1659dp`。

**【事實，Android 二次複現，2026-09-02】** 這個 bug 不是 Windows 專屬，也不需要拖動就會發生。`ResponsiveScaffold.build`（`responsive_scaffold.dart:76-79`）**只看寬度、不看平台**，所以 `Medium_Tablet` AVD（2560×1600 @ density 320 → **邏輯 1280×800dp**）橫向時直接走 `_DesktopLayout`：

| 狀態 | 截圖 | 內容區寬度 | 顯示音源數 |
|---|---|---|---|
| 尚未播放（無面板） | `and-04-tablet-1280-land.png` | 1280 − 72 = 1208dp | **3**（Bilibili / YouTube / 網易雲音樂） |
| 播放一首歌（面板預設 380dp） | `and-05-tablet-1280-panel.png` | 1280 − 72 − 386 = 822dp | **2**（網易雲音樂整欄消失） |
| 觸控拖到上限（500dp） | `and-06-tablet-drag-attempt.png` | 1280 − 72 − 506 = 702dp | 2，且標題大量截斷 |

面板左緣的實測位置佐證了算式：截圖中分隔線在 physical x=1792（=1280−384dp），拖動後移到 x=1549（=1280−506dp，已頂到 `_maxPanelWidth`）。

這比 Windows 那組證據更嚴重：Windows 需要 1700dp 視窗 **加上** 手動把面板拖到 500dp 才會掉音源；在 1280dp 的平板上，**使用者只要點一首歌，首頁就少一個音源**，而且沒有任何操作可以在不收起面板的前提下把它找回來。

### 3.3 底部導覽 6 個目的地【事實】

`responsive_scaffold.dart:28-58` 定義 6 個 `NavDestination`：首頁／搜尋／佇列／音樂庫／電台／設定。

M3 Navigation bar guidelines（`m3.material.io/components/navigation-bar/guidelines`）：

> Navigation bars provide access to **three to five** destinations.
> Navigation bars can have three to five destinations.
> Can contain 3-5 destinations of equal importance.

**【推論】** 「設定」是最不常用的一個，卻和「首頁」佔一樣的權重與寬度。實測 340dp 視窗仍未溢出（`win-12-narrow-340.png`，CJK 標籤較短），但這是靠語言僥倖；Android 上的英文標籤在 411dp 剛好塞下（`and-01-home.png`）。

### 3.4 版面留白與 Fitts 問題【事實，來自截圖】

- **「我的歌單」橫向卡片列**在 1400dp 桌面上只放了一張 200dp 卡片，右側 1000dp 全空（`win-01-home-1400.png`）。卡片寬度來自 `(constraints.maxWidth / 4).clamp(100.0, 140.0)`（`home_page.dart:399`），是 `HorizontalScrollSection` 的單列橫捲，不會換行成 grid。
- **「正在播放」卡片**在桌面上是整列寬（≈1100dp），左邊 56dp 縮圖＋標題，播放按鈕在最右端 —— 兩者相隔約 1000dp（`win-01`, `win-13`）。
- **帳號管理頁**同樣是整列寬卡片，操作按鈕貼右邊緣（`win-10-account.png`）。

### 3.5 搜尋頁的音源 chip 在手機寬度被切掉【事實，已實測】

`search_page.dart:160-183`：`SizedBox(height: 40)` → `Row` → `Expanded(SingleChildScrollView(horizontal, Row(ChoiceChip × 4)))` ＋ 右側固定的排序按鈕。

Android 411dp 實測（`and-03-search-empty.png`）：可見的是「All Sources」「Bilibili」「Yo」（硬切）—— **YouTube chip 被截斷、Netease chip 完全看不到**，而且沒有漸層遮罩或箭頭之類的捲動提示。根 `AGENTS.md` 寫「chips select All/Bilibili/YouTube/Netease」，但手機上使用者看不到後兩個存在。

`SizedBox(height: 40)` 是寫死的行高；配合 §5.3 的「全 App 不限制字級」，放大系統字體時 chip 會被垂直裁切。

### 3.6 播放頁的版面：一個 bool 切兩套，中間 600dp 沒有著落【事實，已實測】

播放頁只有兩套版面，由**單一布林值**決定（`player_page.dart:81-82,127`）：

```dart
final isWideLayout = Breakpoints.isDesktop(MediaQuery.sizeOf(context).width);  // ≥ 1200
...
final playerContent = isWideLayout ? _buildDesktopPlayerContent(...) : _buildNarrowPlayerContent(...);
```

| | 窄版 `_buildNarrowPlayerContent`（`:298-321`） | 寬版 `_buildDesktopPlayerContent`（`:324-360`） |
|---|---|---|
| 外距 | `EdgeInsets.all(24)` | `EdgeInsets.all(24)`（**與 M3 的 24dp 一致** ✅） |
| 結構 | `Column`：`Expanded(flex: 3)` 媒體區 → `SizedBox(height: 32)` → 控制區 | `Row`：`Expanded(flex: 5)` ＋ `SizedBox(width: 32)` ＋ `Expanded(flex: 7)` |
| 封面 | 無寬度上限，實測在 800dp 平板上撐到約 **742dp**、佔畫面高度約 60%（`and-08`） | `ConstrainedBox(maxWidth: 420)` |
| 右欄 | 無 | **只有歌詞**（`_buildLyricsPanel`），佔 7/12 ≈ **58%** 的寬度 |
| 佇列 | 不在此頁（獨立導覽目的地） | 同左，**寬版也沒有佇列欄** |

三個問題：

1. **600–1199dp 整段拿不到寬版。** `isWideLayout` 用的是 `Breakpoints.isDesktop`（≥1200）。實測 800dp 平板直向拿到的是窄版直接放大：封面 742dp 佔六成高度，標題／進度／控制全擠在下方約 25%（`and-08`）。M3 在 Medium/Expanded 就建議雙欄，而 Finamp 的分割門檻是 800×500（§9.3c）—— FMP 的門檻比兩個參考點都高。

2. **寬版把最大的一塊面積給了最常是空的內容。** 歌詞欄固定 `flex: 7`（58%），但歌詞是可能不存在的：實測 1280dp 橫向時右欄整片只顯示「No lyrics available」，而左欄的封面被 `maxWidth: 420` 壓在 41% 的欄位裡（`and-12`）。**版面比例不隨內容有無調整**，沒有歌詞時等於浪費掉近六成畫面。

3. **`_showLyrics` 是純 State，且入口是長按。** `:71` `bool _showLyrics = false`，`:420-431` 的 `AnimatedSwitcher` 用 `onLongPress` 在歌詞／封面之間切換。長按沒有任何視覺提示，也沒有 tooltip；`showLyricsActions = isWideLayout || _showLyrics`（`:83`）意味著窄版在切到歌詞前，歌詞相關動作全部隱藏 —— 使用者必須先發現長按，才會看到操作它的按鈕。

---

## 4. 現況D：空狀態 / 載入 / 錯誤

### 4.1 有共用元件，但只有一半的頁面用它【事實】

`lib/ui/widgets/feedback/error_display.dart` 提供 `ErrorDisplay`（`ErrorType` 含 `empty`，具名建構子 `.network/.server/.notFound/.permission/.empty`）與 `LoadingPlaceholder`。這就是事實上的 EmptyState / ErrorState / LoadingState。

| 指標 | 數字 |
|---|---|
| 走共用 `ErrorDisplay` 的呼叫點 | 16 |
| 手刻的空／錯誤區塊 | **17**（7 個 Icon+Text、10 個純 Text） |
| 完全不碰 `ErrorDisplay` 的檔案 | 8（`lyrics_search_sheet.dart`、`player_page.dart`、`cover_picker_dialog.dart`、`account_playlists_sheet.dart`、`account_radio_import_sheet.dart`、`import_playlist_dialog.dart`、`log_viewer_page.dart`、`home_page.dart` 的歌單卡片） |
| `CircularProgressIndicator` 出現次數 | 36 |
| 其中走 `LoadingPlaceholder` 的 | **10** |

`database_viewer_page.dart`、`download_manager_page.dart`、`downloaded_category_page.dart` 三個檔案**同時**用共用元件和手刻區塊，同一頁不同分支長得不一樣。

### 4.2 錯誤被吞掉的 9 個地方【事實】

`.when(error: ...)` 直接回傳空 widget、且多數連 log 都沒有：

| file:line | 吞掉的內容 |
|---|---|
| `home_page.dart:368` | 歌單預覽載入失敗 → `SizedBox.shrink()` |
| `home_page.dart:658` | 最近播放載入失敗 → `SizedBox.shrink()` |
| `home_page.dart:916` | 封面失敗 → placeholder，無 log |
| `library_page.dart:329,378` | 封面失敗 → placeholder，無 log |
| `playlist_detail_page.dart:647,694-695` | 封面失敗 → `null`／placeholder，無 log |
| `play_history_page.dart:263-266` | 統計列失敗 → `debugPrint` + `SizedBox.shrink()` |
| `create_playlist_dialog.dart:385-388` | 封面失敗 → placeholder（**唯一有 `debugPrint` 的**） |

另外三個同形狀但不是 `.when` 的：

- `download_manager_page.dart:343-350` —— `.maybeWhen(orElse: () => t.general.loading)` 把 loading 和 error 收斂成同一個字串，**永久失敗的查詢會永遠顯示「載入中…」**。
- `settings_storage.dart:82` —— `ref.read(downloadPathProvider).value` 直接取值，loading／error 都靜默變 `null`。
- `player_page.dart:742-759` —— `if (detail != null) … else if (isLoading) … else _BasicInfoContent(...)`，載入失敗會靜默掉進「基本資訊」分支，一個字的錯誤提示都沒有。

### 4.3 錯誤文案把原始例外丟給使用者【事實】

- **完全沒有 i18n 包裝、直接把 `e.toString()` 顯示出來**的有 9 個檔案：`lyrics_search_sheet.dart:387`、`bilibili_login_page.dart:182,263,289,296`、`youtube_login_page.dart:118`、`netease_login_page.dart:251`、`search_page.dart:742,789`、`import_playlist_dialog.dart:380`。
- `import_playlist_dialog.dart:380` 最糟：`_errorMessage = e.toString()`（`:536,591`），而上游拋的是 `Exception(state.errorMessage ?? ...)`（`:575-576`），所以畫面上可以真的出現 `"Exception: <伺服器原文>"`。
- 另有 13 處是 `t.x.loadFailed(error: e.toString())` —— **標題翻譯了，使用者真正要讀的細節仍是未翻譯的 Dart／平台例外訊息**。

### 4.4 錯誤被統一吞成同一個代碼【事實】

`account_playlists_sheet.dart:123-129`：

```dart
} catch (e) {
  _error = t.remote.error.unknown(code: 'LOAD');   // 例外型別完全丟棄
}
```

不論是 `BilibiliFavoritesException(-101)`（登入失效）、`YouTubePlaylistException('UNAUTHENTICATED')` 還是網路逾時，使用者一律看到「操作失敗 (LOAD)」。這是 issue #36 的直接證據之一（§14）。

---

## 5. 現況E：無障礙

### 5.1 語意樹幾乎不存在【事實】

`rg 'Semantics\(' lib/ui --type dart` 的**全部**命中：

```
lib/ui/windows/lyrics/lyrics_title_bar.dart:196
lib/ui/widgets/app_bars/custom_title_bar.dart:177
```

兩處都是視窗標題列。`semanticLabel:` 在 `lib/ui` 命中 **0 次**。`MergeSemantics` **0 次**。

實測（`orca emulator ax`，Android 411dp 首頁）印證了後果 —— 每一列排行榜曲目在無障礙樹裡是**單一個 `ImageView` 節點**，標籤是四段文字硬串起來：

```
ImageView txt='1\n华强见宋老虎 但是唱跳RAP 【多梦综合征】【AI音乐宇宙】\n多梦综合征\n3.1M'
```

排名、標題、上傳者、播放數沒有語意分界，節點角色是 `ImageView` 而不是按鈕。

### 5.2 主要控制項的語意缺口【事實】

| file:line | 控制項 | 問題 |
|---|---|---|
| `mini_player.dart:145-183` | 迷你播放器進度條（拖曳／點擊 seek） | 手刻 `GestureDetector`，**不是 `Slider`**，讀屏軟體看不到，也無法用鍵盤操作 |
| `mini_player.dart:52-53, 268-269` | 整個迷你播放器 → 進入播放器頁 | 裸 `GestureDetector`，無標籤 |
| `radio_mini_player.dart:40-41` | 電台迷你播放器 → 電台播放器頁 | 同上 |
| `player_page.dart:520-541` | 主進度條 | 是真的 `Slider`，但無 `label:` / `semanticFormatterCallback:` → 讀屏念出來是比例不是時間 |
| `compact_volume_control.dart:29-60` | 音量 | 同上 |
| `color_palette_button.dart:378-424` | 取色器（`CustomPaint` + `onPanUpdate`） | 完全沒有替代輸入路徑 |
| `lyrics_display.dart:511-512` 等 3 處 | 點歌詞行跳轉 | 裸 `GestureDetector` |

**【事實，已實測】** 兩個全螢幕播放頁的**主播放／暫停鍵完全沒有語意標籤**。`PlayerPlayPauseButton`（`player_play_pause_button.dart:19,78-80`）本身支援選用的 `tooltip` 參數並以 `Tooltip` 包裹，四個呼叫點中：

| file:line | 是否傳 `tooltip` |
|---|---|
| `mini_player.dart:366-370` | ✅ `isPlaying ? t.general.pause : t.general.play` |
| `radio_mini_player.dart:161-164` | ✅ 同上 |
| `player_page.dart:603-609` | ❌ **未傳** |
| `radio_player_page.dart:324-334` | ❌ **未傳** |

裝置上的 `ax` 樹直接證實了後果（`and-08` / `and-12` 當下）：同一排五個鍵，`Previous` / `Next` / `Shuffle off` / `Loop off` 都有標籤，唯獨最重要的那一顆是 `Button txt=''`。兩個 mini player 有傳、兩個全螢幕頁沒傳，這是遺漏而不是取捨。

96 個 `IconButton` 中 **27 個沒有 `tooltip:`**，包括返回箭頭（`playlist_detail_page.dart:753`、`downloaded_category_page.dart:207`）、搜尋清除（`search_page.dart:119`）、多選勾選框（`search_page.dart:1493`、`play_history_page.dart:961`、`ranking_track_tile.dart:197`）。

### 5.3 字級：完全沒有保護【事實】

`textScaler` / `textScaleFactor` / `TextScaler` / `MediaQuery.withNoTextScaling` 在整個 `lib/` 命中 **0 次**。`lib/app.dart:142` 的 `builder:` 是唯一該做全域鉗制的位置，它只包了 `_AppContentWrapper`（標題列／網路 banner／SafeArea），沒有動 `textScaler`。

因此系統字級放到最大時，這幾個「固定高度直接包 `Text`」的地方會垂直裁切：

- `radio_player_page.dart:242-253, 267-278` —— `SizedBox(height: 24)` 包 `bodySmall`（註解寫「固定高度，避免佈局跳動」）
- `import_playlist_dialog.dart:347-353` —— `SizedBox(height: 20)` 包 `bodySmall`
- `search_page.dart:167` —— `SizedBox(height: 40)` 包整排 `ChoiceChip`（§3.5）

### 5.4 對比度【事實 ＋ 推論】

前景文字／圖示套 alpha ≤ 0.6 的地方（已逐一確認是前景而非裝飾）共 18 處，最低的幾個：

| file:line | alpha | 內容 |
|---|---|---|
| `lyrics_display.dart:536` | **0.25** | 非當前歌詞的副行文字 |
| `comment_pager.dart:288` | 0.3 | 停用態的翻頁圖示 |
| `lyrics_offset_bar.dart:56` | 0.3 | 停用態標籤 |
| `lyrics_line_item.dart:55` | 0.3 | 非當前歌詞副行 |
| `lyrics_display.dart:503` | 0.4 | 非當前歌詞主行 |

**【推論】** `onSurfaceVariant` 在 M3 淺色配色下對 `surface` 的對比約 4.6:1；乘 0.4 之後遠低於 WCAG AA 的 4.5:1。歌詞的「非當前行」刻意壓暗是常見設計，但 0.25 已經接近不可讀。

三個音源的品牌色是硬編碼的（`account_management_page.dart:17-19`：`kBrandBilibili = 0xFFFF6699`、`kBrandYoutube = 0xFFFF0000`、`kBrandNetease = 0xFFE60026`），不走 `colorScheme`，也沒有執行期對比檢查 —— 深色主題下沒有任何保證。**【事實】** 對照組：`app_theme.dart:63-67` 的 `_foregroundColorFor` 和 `settings_appearance.dart:283-284` 都有做執行期對比計算，所以這個能力在專案裡是有的，只是沒用在品牌色上。

### 5.5 沒有任何無障礙測試【事實】

```
rg 'meetsGuideline|AccessibilityGuideline|textContrastGuideline|androidTapTargetGuideline|labeledTapTargetGuideline' test/
→ 0 命中
```

唯一沾到 `Semantics` 的測試是 `test/services/platform/windows_desktop_service_phase4_test.dart:75-105`，它 `File(...).readAsStringSync()` 之後 `expect(source, contains('Semantics('))` —— **是原始碼字串比對，不是執行期無障礙檢查**。

### 5.6 觸控目標【事實】

`VisualDensity.compact` 在 `lib/ui` 出現 23 次，其中 `mini_player.dart:353,361,377,393` 是**四個次要播放控制鍵全部**（隨機／上一首／下一首／循環）。

**【事實，已量測】** 這四個鍵在 `Medium_Tablet`（density 320，scale 2.0）上的實際語意框是 **80 physical px = 40dp**（`ax` 節點中心點 x 依序為 1232 / 1312 / 1392 / 1472 / 1552，間距固定 80px）。`VisualDensity.compact` 的定義是兩軸各 −2、每單位 4dp，48 − 2×4 = **40dp**，與量測完全吻合。Material 與 Flutter 的最小觸控目標都是 **48×48dp**，所以這不是「偏小」而是明確低於下限 8dp。
`materialTapTargetSize: shrinkWrap` 3 處。明確把 `IconButton` 壓到 48dp 以下的只有 `lyrics_title_bar.dart:190-194`（`minWidth: 28, minHeight: 28` + `compact` + `padding: zero`），那是桌面浮動歌詞視窗的標題列，情境上可接受。

### 5.7 狀態列圖示在部分畫面對比只有 1.05:1【事實，已量測】

`SystemUiOverlayStyle`、`statusBarIconBrightness`、`AnnotatedRegion`、`SystemChrome` 在整個 `lib/` 命中 **0 次** —— FMP 從未控制過 Android 狀態列圖示的明暗，完全交給 Flutter 的隱式推導。

在 12 張 Android 截圖上量測狀態列時鐘區（x 20–140、y 4–44）的前景／背景對比（WCAG 相對亮度）：

| 對比 | 畫面 |
|---|---|
| 5.64–19.92:1（深色圖示，可讀） | `and-01` 首頁、`and-02` 播放頁、`and-04`～`and-08` 平板首頁／面板／直向播放頁 |
| **1.05:1（白色圖示打在近白底上，實質不可見）** | `and-03` 搜尋、`and-09` 音樂庫、`and-10` 佇列、`and-11` 電台、`and-12` 寬版播放頁 |

背景在所有畫面都是同一個 `(253,247,255)`（`colorScheme.surface`）。失效畫面的前景是 `(255,255,255)`。`and-13-statusbar-contrast.png` 是四條狀態列的並排放大圖，肉眼即可確認不是「沒有內容」而是白字白底。

**觸發條件仍為未驗證。** 本輪用受控序列排除了四個候選假設，都無法複現：

| 假設 | 實驗 | 結果 |
|---|---|---|
| 有 `AppBar` 的頁面會翻成淺色 | 冷啟動 → 音樂庫（`library_page.dart:59` 有 `AppBar`） | 仍 5.64:1，**否定** |
| 播放頁是觸發點 | 冷啟動 → 播放頁 → 返回首頁 | 全程 5.64:1，**否定** |
| 播放頁之後再進有 `AppBar` 的頁 | 承上 → 音樂庫 → 首頁 | 全程 5.64:1，**否定** |
| 單純旋轉螢幕 | `and-07` / `and-08` 為旋轉後畫面 | 仍 5.64:1，**否定** |

**【推論】** 既然 FMP 一行都沒設過，這個值只可能來自 Flutter／engine 對 `AppBar` 與視窗旗標的隱式推導，而推導結果在同一組頁面上並不穩定。修法不需要先找出觸發條件：在 `app.dart:142` 的 `builder:` 用一個 `AnnotatedRegion<SystemUiOverlayStyle>` 依 `Theme.of(context).brightness` 明確指定，即可讓它不再由隱式行為決定。這比繼續追觸發條件划算得多。

---

## 6. 現況F：設計語言與 token 層

### 6.1 現況不是「Material 3 + dynamic_color」，是「Material 3 + 手刻 seed 色」【事實】

- `pubspec.yaml:15` 有 `dynamic_color: ^1.7.0`，`lib/` 內 `DynamicColorBuilder` / `CorePalette` / `dynamic_color` 命中 **0 次**。唯一的殘留是 `windows/runner/flutter_window.cpp:8` 的 plugin include（Flutter 自動產生的註冊碼）。
- 實際配色：`app_theme.dart:27-31` 的 `ColorScheme.fromSeed(seedColor, brightness)`，seed 來自 9 個預設色之一或使用者自訂色（`theme_preset_colors.dart:19-29`）。
- 使用者可調的外觀維度只有三個：主題模式（跟隨系統／淺／深）、主題色、字體（`win-09-settings.png`、`app_theme.dart:70-95`）。

### 6.2 主題實作是兩份幾乎相同的巨大字面值【事實】

`app_theme.dart` 共 296 行，`lightTheme()`（`:105-195`）與 `darkTheme()`（`:198-288`）**逐字重複約 85 行**：appBarTheme、cardTheme、listTileTheme、navigationBarTheme、navigationRailTheme、navigationDrawerTheme、inputDecorationTheme、sliderTheme 八個 sub-theme 在兩個函式裡一模一樣，唯一差別是 `brightness` 與 `_colorScheme` 的參數。

**【推論】** 這代表**沒有 component token 層**：元件外觀直接寫在兩個 `ThemeData` 字面值裡，任何一次視覺調整都要改兩個地方且無法保證同步。

### 6.3 token 層的實際覆蓋率【事實】

| Token 類別 | 有沒有 | 證據 |
|---|---|---|
| 圓角 | ✅ `AppRadius` 7 階，59 個檔案使用 | `ui_constants.dart:9-35` |
| 動畫時長 | ✅ `AnimationDurations` 6 階，19 個檔案使用 | `:39-60` |
| 圖片畫質檔位 | ✅ `ImageTargetSizes` 6 階（且有靜態規則測試把關） | `:104-136` |
| 縮圖尺寸 | ⚠️ `AppSizes.thumbnail*` 存在，但 40/48/56 仍以字面值散落 20+ 處 | `:79-92` |
| **間距** | ❌ 無。260 個 `EdgeInsets.*` 字面值 | — |
| **字體階層語意** | ❌ 無。直接用 `textTheme.*` | — |
| **版面尺寸**（pane 寬、內容 max-width、grid extent） | ❌ 無。全 inline | §1.3 |
| **動效曲線** | ❌ 無。`Curves.*` inline 13 次 | — |
| **高度／表面層級** | ❌ 無。直接用 `colorScheme.surfaceContainer*` | — |
| **元件 token** | ❌ 無。見 §6.2 | — |

### 6.4 命名撞車警告【事實】

`radio_station_card.dart:156` 已經有一個叫「**液態模式**」的東西：

```dart
// 液態模式：封面大小 = 卡片寬度 - 水平 padding（20 * 2）
final effectiveCoverSize = coverSize ?? constraints.maxWidth - 40;
```

它是**尺寸行為**（封面隨卡片寬度流動），和 Apple 的「液態玻璃 / Liquid Glass」視覺語言完全無關。討論設計風格切換時要避開這個詞，否則兩件事會在程式碼裡混在一起。

---

## 7. 現況G：Windows 與 Android 差異

### 7.1 有意的差異【事實】

| 面向 | Windows | Android | 來源 |
|---|---|---|---|
| 標題列 | `CustomTitleBar`（自繪，含拖動區） | 無 | `app.dart:158-164` |
| 網路 banner | 在標題列下方 | 在 `SafeArea` 內、狀態列著色配合 | `app.dart:150-198` |
| 音訊後端 | media_kit | just_audio | 根 `AGENTS.md` |
| 迷你播放器控制 | 隨機／前／播／後／循環／裝置／音量（7 個） | 隨機／前／播／後／循環（5 個） | `and-01`, `win-01` |
| 字體 fallback | Microsoft YaHei UI | Noto Sans SC | `app_theme.dart:99-107` |
| 桌面歌詞子視窗 | 有 | 無 | `lib/ui/windows/lyrics/` |

### 7.2 非有意的差異與缺口【事實 ＋ 推論】

**a. 完全沒有控制 Android 狀態列樣式。** `SystemUiOverlayStyle` / `SystemChrome` / `AnnotatedRegion` 在整個 `lib/` 命中 **0 次**。而 `app.dart:186` 的 `MediaQuery.removePadding(removeTop: true)` 把頂部 padding 拿掉了，首頁／搜尋頁／播放器頁又都沒有 `Scaffold.appBar`（`player_page.dart:282` 明寫 `appBar: null`；`search_page.dart:107` 只有多選模式才給 appBar）。**【推論】** 在沒有 AppBar 的頁面上，狀態列圖示的明暗完全交給引擎預設值，不隨主題走。**本輪已把它從印象升級成量測**：12 張 Android 截圖中 5 張的狀態列前景／背景對比只有 **1.05:1**（白字打在 `(253,247,255)` 上），另 7 張是 5.64–19.92:1。四個候選觸發假設已用受控序列一一否定。完整量測與實驗見 **§5.7**；`and-13-statusbar-contrast.png` 為並排放大圖。**【未驗證】** 觸發條件仍未隔離，但修法不依賴它。

**b. Windows 沒有最小視窗尺寸。** 實測可以縮到 340×700（`win-12-narrow-340.png`）並正常降級成手機佈局，**沒有 RenderFlex overflow**（我在 `flutter run -d windows` 的輸出裡過濾 `overflow`/`RenderFlex`，0 命中）。這點是好的。對照組：Harmonoid 在 `lib/main.dart` 把桌面最小視窗設成 1024×600。

**c. 桌面上仍然出現手機語彙。** 340–1199dp 的 Windows 視窗會顯示 `NavigationBar`（底部橫向 6 格）＋ 迷你播放器兩層堆疊，佔掉 ≈144dp 的垂直空間（`win-11-narrow-560.png`）。

**d. Detail Panel 不隨頁面上下文變化。** 使用者進到「設定 → 帳號管理」時，右側面板仍然是「正在播放」（`win-10-account.png`）。它是 shell 級的固定面板，不是 M3 意義上的 supporting pane。

### 7.3 桌面歌詞子視窗：實看結果【事實，已實測】

本輪補做了先前缺的實看（`win-15-desktop-lyrics-window.png`）。開啟路徑本身值得記錄：按鈕在 **Detail Panel 標頭**，而且 `track_detail_panel.dart:531-536` 用 `Opacity(opacity: 0)` ＋ `IgnorePointer` 把它藏起來，**只有面板切到歌詞模式時才可見**：

```dart
// 歌词弹出窗口按钮（仅在显示歌词时可见；电台模式下隐藏）
Opacity(
  opacity: (!isRadio && _showLyrics) ? 1.0 : 0.0,
  child: IgnorePointer(ignoring: isRadio || !_showLyrics, child: IconButton(...)),
)
```

所以要用桌面歌詞，使用者得先知道「Detail Panel 可以切成歌詞模式」，才會看到開窗按鈕。（`Opacity` 在 alpha 為 0 時預設不進語意樹，所以這裡**沒有**讀屏會念到隱形按鈕的問題。）

視窗本身約 390×470 physical px（DPR 1.5 → 約 260×313dp），標題列擠了 8 個控制：上一首／播放／下一首／字級／配色／行距／背景／置頂／關閉。這解釋了 §5.6 提到的 `lyrics_title_bar.dart:190-194` 為什麼要把 `IconButton` 壓到 28dp —— 是這個標題列的空間逼出來的。

**一個新發現的缺陷：子視窗只有「等待」一種空狀態，沒有「無歌詞」。**

`lyrics_empty_state.dart` 的 `LyricsEmptyState` 只接受單一 `waitingText` 參數，`lyrics_window.dart:739` 固定傳 `_strings.waitingLyrics`。結果是：**同一首歌、同一時刻**，App 內面板顯示 `noLyricsAvailable` =「暫無歌詞」，浮動視窗顯示 `windowWaitingLyrics` =「等待歌詞...」，而且會**永遠停在「等待」**（截圖 `win-15`，對照同時刻的 `5c5add3a` 面板狀態）。這與 P0-2 是同一類缺陷：把「失敗／沒有」渲染成「進行中」。

順帶澄清兩件本來以為是問題、查證後不是的事：

- **子視窗的 i18n 是完整的。** `lyrics_window.dart:34-65` 那份 31 條硬編碼簡體中文字串只是 fallback；`lyrics_window_service.dart:354,395` 會把 slang 的 `t.lyrics.window*` 推過去，而 `en` / `zh-TW` / `zh-CN` 三個語系各有齊全的 23 個 `window*` 鍵。只有在推送失敗時使用者才會看到簡體預設值。
- 子視窗是獨立的 `runApp` 進入點（`main.dart:45` → `lyricsWindowMain`），拿不到主 isolate 的 slang 實例，**所以「自己維護一份字串表」是 `desktop_multi_window` 的固有代價，不是偷懶**。

---

## 8. 問題清單 P0–P3

### P0 — 使用者會靜默失去內容或永遠卡住

| # | 問題 | 證據 | 影響 |
|---|---|---|---|
| **P0-1** | 首頁排行榜音源數用**視窗級**斷點判斷**內容區**寬度 | `home_page.dart:67-69` ＋ `:234`；Windows `win-07` vs `win-08`；**Android 平板 `and-04` vs `and-05`（獨立複現）** | 拖寬 Detail Panel 會讓網易雲音樂排行榜整欄消失；1200–1658dp 的視窗在面板展開時永遠只看得到 2 個音源。**在 1280dp 的 Android 平板上，光是開始播放就會觸發。**無任何提示 |
| **P0-2** | `download_manager_page.dart:343-350` 用 `.maybeWhen(orElse: () => t.general.loading)` 把 loading 與 error 收斂成同一個字串 | 同行 | 永久失敗的曲目查詢會**永遠顯示「載入中…」**，使用者不會知道它壞了 |
| **P0-3** | 9 處 `.when(error:)` 直接回傳空 widget，8 處連 log 都沒有 | §4.2 表 | 首頁歌單／最近播放載入失敗時整個區塊憑空消失，看起來像「沒有資料」 |
| **P0-4** | 桌面歌詞子視窗只有「等待」一種空狀態，沒有「無歌詞」 | `lyrics_empty_state.dart`（只接受 `waitingText`）＋ `lyrics_window.dart:739`；截圖 `win-15` | 沒有歌詞的曲目，浮動視窗**永遠顯示「等待歌詞...」**，而同一時刻 App 內面板已經正確顯示「暫無歌詞」。與 P0-2 同類 |

### P1 — 明顯影響可用性，但不是靜默失敗

| # | 問題 | 證據 | 影響 |
|---|---|---|---|
| **P1-1** | 無障礙近乎為零：`lib/ui` 只有 2 個 `Semantics(`、0 個 `semanticLabel:`；迷你播放器 seek bar 是裸 `GestureDetector` | §5.1–5.2 | 讀屏使用者無法操作播放進度，曲目列在語意樹上是一個沒有角色的 `ImageView` |
| **P1-2** | 全 App 不限制系統字級，且有 3 處固定高度直接包 `Text` | §5.3 | 放大字級時電台頁與匯入對話框的文字會被垂直裁切 |
| **P1-3** | Detail Panel 寬度／展開狀態／導覽軌展開狀態都不持久化 | `responsive_scaffold.dart:202-206` ＋ `Settings` model 無對應欄位 | 每次開 App 都要重調 |
| **P1-4** | Detail Panel 上限是絕對值 500dp | `responsive_scaffold.dart:206` | 1200dp 視窗吃掉 42% 主內容；3440dp 只剩 14.5%，方向與需求相反 |
| **P1-5** | 缺 840dp 斷點；840–1199dp 完全沒有兩欄佈局 | `breakpoints.dart:6,9`；`win-02-1199.png` | 1080p 螢幕貼半邊視窗（960dp）拿不到 Detail Panel |
| **P1-6** | 搜尋頁音源 chip 在手機寬度被硬切，且無捲動提示 | `search_page.dart:160-183`；`and-03-search-empty.png` | 手機使用者看不到「YouTube」「網易雲音樂」兩個篩選存在 |
| **P1-7** | 9 個檔案把未經 i18n 的 `e.toString()` 直接顯示給使用者，最糟會顯示 `"Exception: ..."` | §4.3 | 登入頁、搜尋、匯入對話框 |
| **P1-8** | 帳號狀態只有「已登錄／未登錄」兩態，憑證失效當下直接 `logout()` | `account_management_page.dart:217,257-258`；`account_provider.dart:190-193` | 使用者分不出「我沒登入」和「我剛被踢出去」。見 §14 |

### P2 — 一致性與規範偏離

| # | 問題 | 證據 |
|---|---|---|
| **P2-1** | 底部導覽 6 個目的地，M3 規範是 3–5，且明文「Avoid putting more than five navigation items」 | `responsive_scaffold.dart:28-58` |
| **P2-2** | 桌面首頁同時用三種方式顯示同一首歌（首頁「正在播放」卡片 ＋ 迷你播放器 ＋ Detail Panel） | `home_page.dart:108-133`；`win-01-home-1400.png` |
| **P2-3** | 17 處手刻空／錯誤區塊 vs 16 處共用 `ErrorDisplay`；36 個 `CircularProgressIndicator` 只有 10 個走 `LoadingPlaceholder` | §4.1 |
| **P2-4** | 隨機播放「關閉」態用 `Icons.arrow_forward`（→），與旁邊的「下一首」語意衝突；而循環鍵是正確做法（同一個 `Icons.repeat` 用顏色區分） | `mini_player.dart:346` / `player_page.dart:586` vs `mini_player.dart:384-387` |
| **P2-5** | 拖動把手命中區 6dp、視覺 1dp、無 drag handle 圖形；M3 規定 spacer 24dp 且內含 drag handle | `responsive_scaffold.dart:406-417` |
| **P2-6** | `app_theme.dart` 的 light/dark 逐字重複 ≈85 行八個 sub-theme | `app_theme.dart:105-195` vs `:198-288` |
| **P2-7** | 沒有間距 scale（260 個 `EdgeInsets` 字面值）、沒有版面尺寸 token、沒有動效曲線 token | §6.3 |
| **P2-8** | `AppSizes.thumbnailSmall/Medium/Large` 存在但 40/48/56 仍以字面值出現 20+ 處 | §1.3 |
| **P2-9** | 桌面首頁「我的歌單」單列橫捲，1400dp 下一張卡片右邊留 1000dp 空白 | `home_page.dart:399`；`win-01` |
| **P2-10** | 沒有任何無障礙測試；唯一相關測試是原始碼字串比對 | `windows_desktop_service_phase4_test.dart:75-105` |
| **P2-11** | 播放頁寬版把 58%（`flex: 7`）固定給歌詞欄，比例不隨「有無歌詞」調整 | `player_page.dart:353-355`；`and-12`、`win-14` |
| **P2-12** | 播放頁的雙欄切換只看寬度（≥1200），不看高度；六個對照組裡是唯一只看單一維度的 | `player_page.dart:82`；§9.3d |
| **P2-13** | `LayoutType { mobile, tablet, desktop }` 與 `isMobile/isTablet/isDesktop` 的命名違反 Flutter 官方 *Avoid checking for hardware types* | `breakpoints.dart`；§9.0 第 2 點 |
| **P2-14** | `MediaQuery.of(context).size` 與 `MediaQuery.sizeOf` 混用（5 : 8），官方指定後者 | §9.0 第 4 點 |

### P3 — 小瑕疵

| # | 問題 | 證據 |
|---|---|---|
| **P3-1** | `dynamic_color` 是死依賴（0 使用） | `pubspec.yaml:15` |
| **P3-2** | 設定頁「帳號管理」副標題漏掉網易雲音樂（三個語言檔都漏） | `settings.i18n.json:6`（en/zh-TW/zh-CN） |
| **P3-3** | 「未知藝術家」有三個不同字串：`general.unknownArtist`、`player.unknownAuthor`、`smtc/tray.unknownArtist` | `general.i18n.json:15`、`player.i18n.json:16` |
| **P3-4** | `home_page.dart:133` 的 `SizedBox(height: 100)` 是手算底部留白，與實際迷你播放器高度 64 無關 | 同行 |
| **P3-5** | 三個音源品牌色硬編碼且無執行期對比檢查，深色主題無保證 | `account_management_page.dart:17-19` |
| **P3-6** | `responsive_scaffold.dart:243` 的 `flex: 2` 無作用；`:245-246` 有重複註解「仅当有歌曲时显示右侧面板」 | 同檔 |
| **P3-7** | `radio_player_page.dart:219` 用 `station?.hostName ?? t.radio.live`，把「直播中」當作主播名稱的 fallback | 同行 |
| **P3-8** | 桌面歌詞視窗的開窗按鈕用 `Opacity(0)` ＋ `IgnorePointer` 藏在 Detail Panel 標頭，只有切到歌詞模式才可見 | `track_detail_panel.dart:531-536`；§7.3 |

---

## 9. 成熟做法對照

### 9.0 先講 Flutter 官方 adaptive design 指南說了什麼、以及沒說什麼

本輪指令要求對照 Flutter 官方 adaptive design 指南。逐頁查證後的結論是：**它支持本報告對「量測方式」的判斷，但對「側邊面板該多寬、要不要記住」完全沉默** —— 所以 §9.1 只能改由 M3 與成熟桌面 App 回答，這不是繞過官方文檔，是官方文檔沒有這一段。

**它說了什麼（皆為原文引用）：**

1. 斷點不自己定義，轉給 M3 ——「For choosing the maximum width value, consider using the values recommended by Material 3 in the *Applying layout* guide.」（`docs.flutter.dev/ui/adaptive-responsive/large-screens`）與「Then use adaptive breakpoints like the ones that Material recommends.」（`.../best-practices`）。這佐證 §9.2：FMP 的三段斷點與 M3 五段的落差，是與官方推薦來源的落差。

2. **不要用裝置類型做佈局判斷** ——「Avoid writing code that checks whether the device you're running on is a 'phone' or a 'tablet', or any other type of device when making layout decisions.」（`.../best-practices`，該節標題就叫 *Avoid checking for hardware types*）。FMP 的 `enum LayoutType { mobile, tablet, desktop }` 與 `Breakpoints.isMobile/isTablet/isDesktop`（`breakpoints.dart`）**在命名層直接違反這一條**。這是命名問題而非行為問題（實際判斷的是寬度），但它正是 §3.2 那個 bug 的心理成因：名字叫 `isDesktop`，於是被拿去判斷一個 pane 內部要放幾欄。

3. **`MediaQuery` 與 `LayoutBuilder` 的分工，官方講得很清楚** ——「`LayoutBuilder` provides the layout constraints from the parent `Widget`. This means that you get sizing information based on the specific spot in the widget tree where you added the `LayoutBuilder`.」以及「imagine a custom widget, where you want the sizing to be based on the space specifically given to that widget, and not the app window in general. In this scenario, use `LayoutBuilder`.」（`.../general`）

   **這一條修正了一個容易下錯的結論**：`home_page.dart:232-236` 用 `LayoutBuilder` 的 `constraints.maxWidth` 量自己拿到的空間，**是官方推薦的做法，不是 bug**。§3.2 的缺陷精確地說是「拿視窗級的門檻值（`Breakpoints.tablet = 1200`）去判斷容器級的量測值」，而不是「量錯了東西」。§10.2 的建議因此維持不變：分開兩套門檻，而不是改回 `MediaQuery`。

4. `MediaQuery.of` 應改用 `sizeOf` ——「The short answer is **for performance reasons.** `MediaQuery` contains a lot of data, but if you're only interested in the size property, it's more efficient to use the `sizeOf` method.」（`.../general`）FMP 兩種寫法各半：`MediaQuery.of(context).size` 5 處（`responsive_scaffold.dart:76`、`player_page.dart:638,674`、`track_detail_panel.dart:80`、`comment_pager.dart:81`、`capped_draggable_sheet.dart:78`），`MediaQuery.sizeOf` 8 處。其中 `responsive_scaffold.dart:76` 是全 app 每次 rebuild 都會經過的那一個。

   附帶澄清：該行上方的註解「使用 MediaQuery 而不是 LayoutBuilder 来避免与 go_router Navigator 的布局冲突」**選擇是對的** —— 這裡要的正是視窗尺寸而非容器尺寸。要改的只是 `of` → `sizeOf`，註解的理由應予保留。

5. 官方明確要求跨設定變更保存狀態 ——「Apps should retain or restore app state as the device rotates, changes window size, or folds and unfolds.」（`.../best-practices`，*Save app state* 節）。這是官方文檔裡**最接近**支持 §2.3（面板寬度不被記住）的一句，但它講的是執行期設定變更，不是跨 session 持久化。

**它沒說什麼（逐項確認為 absent）：** 側邊 pane 的最小／最大寬度、pane 可否調整大小、drag handle、以及**跨 session 記住使用者調整後的 pane 寬度**。`large-screens` 那頁關於側邊區域只有一句「switch between a `BottomNavigationBar` and a `NavigationRail` depending on available screen space」，其餘轉向一篇 2021 年的 Medium 文章。

**因此 §9.1 的對照對象是 M3 規範與 VS Code / Finamp 的實作，而不是 Flutter 官方指南 —— 因為後者在這個問題上沒有立場。**

### 9.1 側邊面板：可拖動是規範，FMP 偏離的是數值與持久化

**Material 3（`m3.material.io/foundations/layout/applying-layout/large-extra-large` 與 `.../understanding-layout/parts-of-layout`）**

M3 直接把 FMP 這個用途寫進了規範裡：

> **standard side sheet** — Standard side sheets display content without blocking access to the screen's primary content, **such as an audio player at the side of a music app**. They're often used in medium and expanded window sizes like tablet or desktop.

具體數字：

> When using a fixed-and-flexible layout, the fixed pane should have a width of **412dp** by default.
> Note: Fixed panes in this window size are recommended to be 412dp, but **side sheets have a default maximum width of 400dp**.
> Large and extra-large layouts have a leading and trailing margin of **24dp**. The spacer between panes is **24dp**.
> **A spacer is the space between two panes. If panes can be resized, the spacer contains a drag handle.**
> Drag handles can be used to resize panes in a layout. They can: **Adjust the width of flexible panes** / **Fully collapse and expand fixed panes** to quickly switch between a single and two-pane layout.

對照 FMP：

| 項目 | M3 | FMP | 判定 |
|---|---|---|---|
| 側邊播放器面板本身 | 明確支持（standard side sheet） | 有 | ✅ |
| 可拖動調整 | 明確支持（drag handle in spacer） | 有 | ✅ |
| 收起／展開切換 | drag handle 可完全收合 | 有（點收起條） | ✅ |
| 預設寬度 | 412dp（side sheet 上限 400dp） | 380dp | ⚠️ 偏窄但同量級 |
| pane 間距 | 24dp，內含 drag handle | **6dp，無 handle 圖形** | ❌ |
| 佈局左右外邊距 | 24dp | 16dp（`home_page.dart:264`） | ⚠️ |
| 上限 | 未規定（M3 只給預設值，暗示 flexible pane 用比例） | 絕對 500dp | ❌ 見 §9.1 結論 |

**「上限該用什麼」—— 成熟桌面 App 的實際做法：**

- **VS Code**（`microsoft/vscode`）：`SidebarPart`（`src/vs/workbench/browser/parts/sidebar/sidebarPart.ts`）宣告 `minimumWidth = 170`、`maximumWidth = Number.POSITIVE_INFINITY`，並且 `override get snap(): boolean { return true; }` —— **有像素下限，沒有上限**，拖到下限以下會整個收合而不是卡住。預設寬度是 `Math.min(300, mainContainerDimension.width / 4)`：**像素上限與比例取小值**。
- **Finamp**（`finamp-app/finamp`，**Flutter，同類產品，本輪最貼切的先例**）：`lib/components/PlayerScreen/player_split_screen_scaffold.dart` 的 `buildPlayerSplitScreenScaffold()` 掛在 `MaterialApp(builder:)` 上對全站生效，當 `constraints.maxWidth >= 800 && constraints.maxHeight >= 500` 時用 `split_view` 套件把播放頁固定顯示在畫面右側，**可拖曳，且寬度持久化**到 Hive 的 `FinampSettings.splitScreenPlayerWidth`（`@HiveField(61)`，另有 `allowSplitScreen` `@HiveField(62)` 作為開關）。這證明「側邊播放器面板 + 可拖動 + 記住寬度 + 使用者可關閉」在 Flutter 生態裡是已經有人做過、且用一般套件就能做到的組合，不需要自造。

- **Spotify 桌面版**：Now Playing View 可拖動（Spotify Star MattSuda 在官方社群確認），未公開 min/max【未驗證】。預設行為是「開始播放時自動打開」，可在 Settings → Display → 「Show the now-playing panel on click of play」關掉。
- **Apple Music (macOS)**：Playing Next / Lyrics 面板在標準視窗中**不可調整大小**，只能開關（Apple 支援文件只寫 "click Lyrics to show or hide"）。想放大歌詞只能切到 MiniPlayer 再調 MiniPlayer 視窗大小（Apple Community Specialist 於 `discussions.apple.com/thread/253283378` 給出的官方 workaround，該串有 39 個「Me too」）。

**Spotify 的反面教材直接對應 FMP 的 P1-3：** Spotify 桌面版「面板寬度／開關狀態重啟後不記得」是一條從 2023-04 延燒到 2025 的社群抱怨（`community.spotify.com/t5/Desktop-Windows/Desktop-New-quot-Now-Playing-View-quot-sidebar/td-p/5600889` 開了 8 頁以上；另有 `.../td-p/5832258`、`.../td-p/6550064`、`.../td-p/7159299` 三串專門講這件事）。**FMP 現在的行為和 Spotify 被罵了兩年的那個 bug 完全一樣。**

**結論：** 「可拖動 + 上限」是規範做法；**「絕對像素上限」不是**。VS Code 的答案（像素下限 + 無上限 + 預設取 `min(px, width/4)` + 持久化）是這一類 UI 的事實標準，而 M3 給的 412dp 是**預設值**不是上限。Finamp 則證明同一組行為在 Flutter 裡可以直接用既有套件落地，並把寬度存進設定 model —— §10.1 的建議因此不是設計提案，而是有兩個獨立實作可抄的既成做法。

### 9.2 斷點：M3 五段，FMP 三段

見 §1.1 表。補充兩個實作參考：

- **Harmonoid**（Flutter，GPL-3.0）不用裸 `MediaQuery`，而是把 `LayoutVariant { mobile, tablet, desktop }` 包成 `LayoutVariantThemeExtension`，透過 `Theme.of(context).extension<LayoutVariantThemeExtension>()` 取用（`lib/utils/rendering.dart`）。**好處：斷點成為 theme 的一部分，可以在 widget test 裡直接注入而不用假造 `MediaQuery`。**【未驗證】它實際的像素切點在 submodule `harmonoid/adaptive_layouts` 裡，該 repo 現在回 404，數值無法核對。
- Harmonoid 同時在 `lib/main.dart` 設定桌面最小視窗 **1024×600**，並把版面常數集中在 `lib/utils/dimensions.dart`（`kDesktopHeaderHeight = 52.0`、`kMobileHeaderHeight = 56.0`、`kDesktopMargin = 16.0`、`kMobileMargin = 8.0`）—— 就是 FMP 缺的那個「版面尺寸 token」層。

### 9.3 首頁與導覽：可設定的分頁是主流做法

- **Auxio**（`OxygenCobalt/Auxio`，Kotlin）把首頁分頁做成使用者可排序、可隱藏的設定：sealed class `Tab`（`app/src/main/java/org/oxycblt/auxio/home/tabs/Tab.kt`）有 `Tab.Visible` / `Tab.Invisible` 兩種，覆蓋 Songs / Albums / Artists / Genres / Playlists 五個 `MusicType`，**順序與可見性打包成一個位元序列持久化**（預設 `0b1000_1001_1010_1011_1100`，每個 tab 4 bits），設定入口在 `HomeSettings.kt`（`homeTabs: Array<Tab>`），重排 UI 在 `TabCustomizeDialog.kt` / `TabAdapter.kt` / `TabDragCallback.kt`。首頁本身是單一 `ViewPager2`（`HomeFragment.kt`）+ `TabLayoutMediator`，**不用 bottom nav 也不用 rail**。
- Auxio 的播放層是**自己寫的多層 bottom sheet**，不是 MDC 的 `BottomSheetBehavior`：`PlaybackBottomSheetBehavior.kt` 與 `QueueBottomSheetBehavior.kt` 都繼承自家的 `BaseBottomSheetBehavior`（`ui/BaseBottomSheetBehavior.kt`），註解直接寫理由是標準 sheet 的「inadequate edge-to-edge support, inconsistent corner radius handling, and inability to bypass the half-expanded state at full-screen dimensions」。**代價也很明確** —— 維護者在 issue #554 自陳「I also have to check for this **every drawn frame**」。這是一個「自己造輪子的真實成本」的可引用案例。
- **Harmonoid** 的 now-playing 是三份 widget tree 由 `LayoutVariant` 路由（`lib/features/now_playing/now_playing_bar.dart` → `DesktopNowPlayingBar` / tablet（`UnimplementedError()`）/ `MobileNowPlayingBar`），桌面走 **bar → 全螢幕**，**沒有側邊面板**。

### 9.3b Spotube 與 Symphony：兩個最貼近 FMP 的同類專案

**Spotube**（`KRTirtho/spotube`，Flutter，桌面＋行動，多音源）—— 架構上最像 FMP 的專案：

- **斷點**：不用套件，自己在 `lib/extensions/constrains.dart` 定義 `Breakpoints = (xs: 480.0, sm: 640.0, md: 820.0, lg: 1024.0, xl: 1280.0)`（**五段**，md 820 幾乎就是 M3 的 840），並把 `isXs/smAndUp/mdAndDown/...` 同時掛在 **`MediaQueryData`、`BoxConstraints`、`Size`、`SliverConstraints` 四個型別上**。也就是說同一組斷點值可以拿來量視窗，也可以拿來量容器，但**呼叫端必須明示自己在量哪一個**。另有 `lib/hooks/utils/use_breakpoint_value.dart` 的 `useBreakpointValue<T>({xs, sm, md, lg, xl, xxl, others})`。
- **shell**：`lib/modules/root/sidebar/sidebar.dart` 三段式 —— `mediaQuery.lgAndUp`（≥1024）給有標籤的 `NavigationSidebar`，640–1024 給 icon-only `NavigationRail`，`smAndDown` 交給底部導覽（`spotube_navigation_bar.dart`）。
- **導覽目的地**：桌面側欄上組 4 個（Browse / Search / Lyrics / Stats）＋ Library 組 4 個；**行動底部導覽只有 4 個**（`lib/collections/side_bar_tiles.dart`，Library 把 playlists/artists/albums 收成一個）。
- **佈局模式是使用者可選且持久化的**：`enum LayoutMode { compact, extended, adaptive }`，存在 **Drift/SQLite 的 `preferencesTable`**（`lib/models/database/tables/preferences.dart` 的 `textEnum<LayoutMode>()`，預設 `adaptive`），透過 `UserPreferencesNotifier.setLayoutMode()` 寫入。**這是「可切換佈局模式」的最小可行版本 —— 一個 enum，不是三套 shell。**
- **但 Spotube 沒有可拖動的面板**：repo 全域搜 `ResizableBox` 與 `onHorizontalDragUpdate` **0 命中**，側欄寬度是 `shadcn_flutter` 元件決定的，`SidebarFooter` 硬寫 `width: 180`。**FMP 在這一點上比 Spotube 走得更遠。**
- **首頁區塊順序也是硬編碼的**：`lib/pages/home/home.dart` 用 `switch (index)` 列出三個固定 section（還有兩個被註解掉），沒有使用者排序 UI。**FMP 的硬編碼首頁不是異類。**

**Symphony**（`zyrouge/symphony`，Kotlin/Compose，Android）—— 直接給出 FMP「6 個導覽目的地」的解法：

- `enum HomePage` 有 **10 個**候選分頁（`ui/view/Home.kt:96`：ForYou, Songs, Artists, Albums, AlbumArtists, Genres, Playlists, Browser, Folders, Tree），使用者自己選要哪幾個上底部導覽列。
- **但選擇數量被硬性限制在 2–5**：`ui/view/settings/HomePageSettingsView.kt` 的 `SettingsMultiOptionTile(..., satisfies = { it.size in 2..5 })` 讓「完成」按鈕在超出範圍時 disabled，提示文案就叫 `SelectAtleast2orAtmost5Tabs`（「Select at least 2 or at most 5 tabs」）。**一個成熟播放器把 M3 的 5 個上限做成了設定驗證。**
- 順序由上下箭頭調整（`ui/components/settings/MultiOptionTile.kt` 的 `Collections.swap(nValue, i - 1, i)`），持久化在 SharedPreferences 的 `home_tabs` 鍵（`services/Settings.kt` 的 `EnumSetEntry`，以逗號串接 enum 名稱）。
- **超出的分頁怎麼辦？** 不做 overflow menu，而是在底部導覽列上加一個「往上滑／點空白」手勢（`Home.kt` 的 `detectTapGestures` + `.swipeable(onSwipeUp = ...)`），打開一個 `ModalBottomSheet`，裡面列出**全部 10 個** `HomePage.entries` 讓你直接跳。**釘在列上的是 5 個，能到達的是 10 個。**
- now-playing 是 bar → 全螢幕路由（`NowPlayingBottomBar.kt` 的 onClick/onSwipeUp → `NowPlayingViewRoute`），沒有中間的 sheet 層。

**兩者都不持久化 pane 寬度** —— 因為兩者都沒有可調整寬度的 pane。這一項的參考對象只有 VS Code（§9.1）。

**Material 3 導覽列上限（`m3.material.io/components/navigation-bar/guidelines`）：**

> Navigation bars can have three to five destinations.
> Navigation bars should be used for: **Three to five main pages in the product**.
> **Don't**: Avoid putting more than five navigation items in a navigation bar.

Flutter 端的精確狀況：`NavigationBar`（M3 元件）的 doc **沒有**複述 3–5，只連到 M3 spec，程式碼上只有 `assert(destinations.length >= 2)`，**沒有上限**；「typically between three and five」這句話在舊的 `BottomNavigationBar` doc 裡（`packages/flutter/lib/src/material/bottom_navigation_bar.dart`）。所以 FMP 的 6 個目的地**不會被 framework 擋下來，但違反 M3 規範的明文**。

### 9.3c Finamp：首頁可設定、播放頁分層，兩者都持久化

Finamp 是本輪唯一同時滿足「Flutter + 音樂播放器 + 有側邊播放器 + 有可設定首頁」的對照組。注意版本狀態：`main` 分支停在 `0.6.27+52`（最後動 `pubspec.yaml` 是 2025-01-25），實際發布中的 `v1.0.1-beta` 與所有 redesign 成果都在 **`redesign` 分支**（領先 `main` 3920 commits）。以下引用皆取自 `redesign`。

**首頁：** `lib/screens/music_screen.dart` 是 tab bar + `TabBarView`，tab 集合來自 `ContentType` enum。redesign 新增了 `ContentType.home` 這個特殊 tab，內容由 `lib/components/HomeScreen/home_screen_content.dart` 的 `HomeScreenContent` 提供，是**可設定 section 的策展式資訊流**（`homeScreenConfiguration.sections`），而不是固定順序的 Column。程式碼保證它一定存在：若使用者關掉所有 tab，`music_screen.dart` 會強制把 Home tab 打開回來。

**tab 可重排、可隱藏**，UI 在 `lib/screens/tabs_settings_screen.dart`（`ReorderableListView.builder` + `HideTabToggle`），持久化於 `FinampSettings`（`lib/models/finamp_models.dart:324`，`@HiveType(typeId: 28)`）的 `tabOrder: List<ContentType>`（`@HiveField(22)`）與 `showTabs: Map<ContentType, bool>`。**這與 §10.7 建議 FMP 抄 Symphony 的解法是同一個模式，而且 Finamp 版本是 Flutter 實作。**

**寬螢幕：** `home_screen_content.dart` 用 `final double maxWidth = isDesktop ? 800.0 : 600.0;` 置中內容並依可用寬度換算卡片欄數。**注意 `isDesktop`（`lib/utils/platform_helper.dart`）是用 `Platform.isWindows/isLinux/isMacOS` 判斷、不是看寬度** —— 這正是 Flutter 官方 *Avoid checking for hardware types* 明文反對的寫法（§9.0）。**Finamp 在這一點上不值得抄。**

**播放頁分層（對 §10.3b 直接有用）：** mini bar 是 `NowPlayingBar`（掛在 `Scaffold.bottomNavigationBar`），全螢幕頁是 `PlayerScreen`（獨立 route `/nowplaying`）。垂直順序是 透明 AppBar → `PlayerScreenAlbumImage`（正方形、8px 圓角、陰影）→ `TrackNameContent`（標題 + `ArtistChips` + `AlbumChips`）→ `ControlArea`（`FeatureChips` + `ProgressSlider` + `PlayerButtons`）→ 底部動作列（輸出裝置 / `QueueButton` / Lyrics）。

三個值得注意的做法：

1. **`PlayerHideableController` + `PlayerHideable` enum**（`player_screen.dart`）依可用空間**逐項**決定哪些元素顯示、間距多少 —— 不是「窄就換一套佈局」的二元切換，而是一個可降級的元素優先序。FMP 目前是 `isWideLayout` 一個 bool 切兩套（§10.3b 方案 C 的對照）。
2. **歌詞是獨立 route**（`lib/screens/lyrics_screen.dart`），入口有二：底部動作列的 Lyrics 按鈕（無歌詞時 `inactive`）、以及**水平向左滑**（`SimpleGestureDetector.onHorizontalSwipe`，僅在 `isLyricsAvailable` 時生效）。
3. **佇列是 `DraggableScrollableSheet` + `showModalBottomSheet`**（`queue_list.dart:277-360`，`initialChildSize: 0.92`），覆蓋在播放頁之上而非分割畫面；入口是 `QueueButton` 或垂直上滑。

**設計語言：** `pubspec.yaml` 有 `dynamic_color: ^1.8.1` 與自建 fork 的 `palette_generator`。`lib/services/theme_provider.dart` 同時做兩件事：`PaletteGenerator.fromImage(...)`（:255-257，從專輯封面取色）與 `DynamicColorPlugin.getCorePalette()` / `getAccentColor()`（:507-510，讀 Android Material You），最後都餵進 `ColorScheme.fromSeed(...)`。**這是 §6.1 那個「本輪指令說 FMP 有 dynamic_color、實際上沒有」的正確參考實作。**

### 9.3d 播放頁在寬螢幕怎麼做：六個對照組，只有兩個真的做雙欄

這是本輪指令要求的「首頁**與播放頁**」對照。結論比預期反直覺：**把播放頁做成桌面雙欄，並不是主流做法；FMP 現在的做法在六個對照組裡是獨一份。**

| 專案 | 播放頁在寬螢幕的做法 | 切換依據（file:line） | 佇列 | 歌詞 |
|---|---|---|---|---|
| **FMP** | 雙欄：左封面＋控制 `flex:5`、右歌詞 `flex:7` | **寬度 ≥1200**（`player_page.dart:82`） | 不在播放頁（獨立導覽目的地） | 右欄固定佔 58% |
| **Finamp** | 不改播放頁內部，改為把**整個播放頁**放進右側可拖動側欄 | `maxWidth>=800 && maxHeight>=500`（`player_split_screen_scaffold.dart`），寬度持久化 | `DraggableScrollableSheet` 0.92 覆蓋 | 獨立 route ＋ 水平左滑 |
| **Harmonoid** | **不做。** 桌面靠常駐底部 now-playing bar；全螢幕頁桌面版只有一套版面 | 平台分支 `isDesktop/isTablet/isMobile`；**tablet 分支是 `throw UnimplementedError()`**（`now_playing_screen.dart:22`，由 `:32` 呼叫） | 置中 Modal Dialog（`ReorderableListView`） | 同頁 `AnimatedSwitcher` 就地覆蓋在背景上 |
| **Spotube** | **不做，而且方向相反**：視窗夠寬時直接關掉展開式播放頁 | `useEffect(... if (mediaQuery.lgAndUp) panelController.close() ...)`（`player.dart:50-56`，`lg=1024`） | 獨立 route | 獨立 route ＋ Synced/Plain 分頁 |
| **Auxio** | 兩欄，但**軸線是高度不是寬度**：可用高度不足時封面置左、資訊與控制置右 | Android 資源限定詞 `layout-h360dp` / `layout-h520dp`（**沒有** `layout-w600dp` 版本的播放面板） | 巢狀第二層 bottom sheet | 無歌詞功能 |
| **Symphony** | 兩欄：`Row`，左封面 `weight(1f)`、右內容 | `ScreenOrientation.fromDimension`：`width > height` 即 LANDSCAPE（`UserInterface.kt:25-28`） | 獨立 route | 兩種模式（就地取代封面 / 獨立頁），**由設定決定** |
| **Spotify 桌面** | 常駐右側 Now Playing 面板 ＋ 另一個獨立的全螢幕模式 | 未公開【未驗證】 | 面板內 "Next in queue" | 面板內 |

**抽驗**：Spotube 的 `panelController.close()` 與 Harmonoid 的 tablet `throw UnimplementedError()` 是兩條最反直覺的結論，我直接讀原始檔覆核，兩條都成立（行號以我實讀為準，與子代理回報略有出入，見 §15.4）。

從這張表可以讀出三件事：

**1. 「寬螢幕 = 播放頁變雙欄」不是共識。** 六個對照組裡，Harmonoid 與 Spotube 明確選擇不做 —— 它們把桌面的 now-playing 責任交給**常駐的橫向控制列**，全螢幕播放頁在桌面反而退居次要（Spotube 甚至主動關掉它）。Finamp 走第三條路：不改播放頁內部佈局，而是把整頁塞進側欄。

**2. 沒有任何一個對照組把播放頁的多數面積固定給歌詞。** FMP 的 `flex: 7`（58%）在這張表裡沒有同類。最接近的 Symphony 是「歌詞**取代**封面」而非「歌詞**旁邊**放封面」，而且是使用者可選的模式。

**3. 切換依據上，FMP 是唯一只看寬度的。** Symphony 看的是寬高比（橫向），Auxio 看的是高度，Finamp 兩個維度都看。**這正好對應 §3.6 拍到的失效畫面**：800dp 直向平板的問題是封面吃掉 60% 的**高度**，而 FMP 的 `isWideLayout` 完全不看高度，所以永遠不會因此切換。Auxio 用 `layout-h360dp` 處理的就是同一個問題。

### 9.4 「液態玻璃」在 Flutter 的現況（2026-09 查證）

**渲染器前提已經不是問題了。** `docs.flutter.dev/perf/impeller`（頁面標示 Flutter 3.44.7，最後更新 2026-08-21）：

> **Windows** — Impeller is available and enabled by default **as of Flutter 3.47**. In a future release, the ability to opt out of using Impeller will be removed.
> **Linux / macOS** — 同上，3.47 起預設開啟。
> **Android** — enabled by default on API 29+；更低版本或不支援 Vulkan 時退回 OpenGL。

FMP 目前正是 **Flutter 3.47.1 stable**（`flutter --version`），所以 Windows 與 Android 兩個目標平台**都已經在 Impeller 上**。網路上「Windows 沒有 Impeller，所以做不了液態玻璃」的說法（含 `flutter/flutter#183495` 那份設計文件）在 3.47 之後已經過期。

**但套件端還沒跟上。** `liquid_glass_renderer`（whynotmake.it，MIT，社群事實標準，885 likes / 24.3k downloads）：

| 項目 | 現況 |
|---|---|
| 最新版本 | **0.2.0-dev.4**，**9 個月前發佈**（仍是 `-dev`，從未發過 stable） |
| pub 宣告支援平台 | **Android / iOS / macOS** —— **沒有 Windows** |
| README 首句 | 「⚠️ **EXPERIMENTAL - USE WITH CAUTION** This package is still experimental and **should not be blindly added to production apps** for all devices.」 |
| 限制 1 | 「Only works on Impeller, so **Web, Windows, and Linux are entirely unsupported for now**」 |
| 限制 2 | 動畫形狀時有記憶體尖峰（Flutter texture 無法即時釋放的已知 bug） |
| 限制 3 | 一個 `LiquidGlassBlendGroup` 最多 16 個形狀，數量越多效能衰減越明顯 |
| 限制 4 | 混合形狀時 blur 會產生 artifact；`Glassify` 完全不支援 blur |

**【推論】** 套件寫的理由（「Windows 沒有 Impeller」）已經過期，但**它的 pub 平台宣告仍然沒有 Windows，也沒有針對 3.47 發過新版**。所以現在的狀態是：「在 Windows 上能不能跑」**【未驗證】**，而且沒有人在維護這個問題 —— 9 個月沒有新版本。

分支 `liquid_glass_widgets` 宣稱支援 Windows，但它自己的平台矩陣寫的是 Windows 走「**Lightweight 2D shader default**」，也就是**降級成普通 glassmorphism，不是真正的折射效果**。

**效能面的可引用事實：** Flutter 官方部落格記錄過 backdrop filter 的兩次大優化（2019 年 iOS 3x 提速；3.19 版「scenes utilizing multiple backdrop filters have seen performance gains ranging from 20% to 70%」），這說明**多層 backdrop filter 一直是 Flutter 的已知重負載路徑**。液態玻璃比 backdrop filter 更貴（要 SDF + 折射 shader + texture capture）。

**結論（回答「值不值得」而不是「可不可以」）：**

- 「可不可以」：Android 可以（有套件、Impeller 預設開）；Windows **不確定**，最好的情況也只是降級的 glassmorphism。
- 「值不值得」：**現在不值得。** 理由不是你的架構做不到，而是（a）唯一成熟的套件是 9 個月沒動的 `-dev` 版且不宣告支援你一半的目標平台，（b）你要付的架構代價（見 §10.4）大約是 1500–2500 行的 token/元件抽象重寫，而換來的是**只有一個平台能看到、且作者自己說別放進 production** 的視覺效果。
- **但**：§10.4 提出的 token 層重構**本身就值得做**（它同時解決 P2-6/P2-7/P2-8），而且做完之後「未來要不要加第二套視覺語言」變成一個可逆的小決定。**先做 token 層，把設計風格切換當成它的副產品而不是目標。**

---

## 10. 建議方案

每項標註 **成本**（S ≤ 半天 / M ≤ 2–3 天 / L > 1 週）、**風險**、**可逆性**。

### 10.1 Detail Panel：改成「像素下限 + 比例上限 + 持久化 + 真的 drag handle」

**建議 R1（推薦）** — 採 VS Code 的模型，數值取 M3 的預設值：

```dart
// 建議放進 lib/core/constants/ui_constants.dart 的新 AppLayout
static const double detailPanelMin = 320;        // 略高於現行 280，讓內容不擠
static const double detailPanelDefault = 412;    // M3 fixed pane 預設值
static const double detailPanelMaxFraction = 0.4; // 比例上限
static const double paneSpacer = 24;             // M3 spacer，內含 drag handle
```

- 上限改成 `min(視窗寬 * 0.4, 某個絕對天花板)`；下限維持像素。**這樣小視窗不會被面板吃掉、大視窗也不會卡在 500dp。**
- 預設寬度用 VS Code 的公式風格：`min(412, 視窗寬 / 4)`。
- spacer 從 6dp 拉到 24dp，中間放一個實際可見的 drag handle（M3 有這個元件）。
- 三個 State 欄位（寬度／面板展開／導覽軌展開）搬進 `Settings` Isar model 持久化。

**成本 M**（`responsive_scaffold.dart` 改寫約 120 行 ＋ `Settings` 加 3 個欄位 ＋ `build_runner` ＋ `database_catalog.dart` 同步 ＋ 遷移測試）。**風險 低**（純 UI 狀態，壞了最多是寬度不對）。**可逆 高**。

**替代方案 R1'** — 只做持久化，不動上限（成本 S）。**取捨**：解決 P1-3 但不解決 P1-4，ultrawide 使用者仍然只能拿到 14.5% 的面板。

**替代方案 R1''** — 學 Apple Music，把面板改成不可調整、只能開關（成本 S，等於刪掉拖動邏輯）。**取捨**：程式碼最簡單，但你已經有拖動了，拿掉是功能倒退；而且 Apple 這個決定在自家社群被抱怨了（39 個「Me too」）。**不推薦。**

**同時要做（否則 R1 會放大 P0-1）：** §10.2 的斷點語意分離必須跟 R1 一起上，不然把面板拖更寬只會讓首頁掉更多內容。

### 10.2 斷點：把「視窗級」和「容器級」分開，並補 840dp

**建議 R2** — `Breakpoints` 保留給**視窗骨架**決策，新增一組**容器級**的欄數決策：

```dart
// 視窗級（決定 bottom nav / rail / 三欄），補上 840
enum WindowClass { compact, medium, expanded, large, extraLarge }
// 600 / 840 / 1200 / 1600，對齊 M3 與 androidx.window

// 容器級（決定一個 pane 內部放幾欄）—— 與視窗寬無關
int columnsFor(double containerWidth, {double idealColumn = 420}) =>
    (containerWidth / idealColumn).floor().clamp(1, 3);
```

- `home_page.dart:67-69` 改用 `columnsFor(constraints.maxWidth)` → **P0-1 直接消失**，而且 840–1199dp 也能拿到 2 欄。
- `responsive_scaffold.dart:77` 改用 `WindowClass`，在 `expanded`（840–1199）就開始給 Detail Panel（可先給收起態，讓使用者自己展開）。
- `test/ui/pages/home/home_ranking_sources_test.dart` 的 5 條測試要改成餵容器寬度，並**新增一條「視窗 1700 + 面板 500 → 仍應是 2 欄還是 3 欄」的迴歸測試**（這正是現在測不到的情境）。

**成本 M**。**風險 中**（會改變所有既有斷點行為，需要在兩個平台各跑一輪實機）。**可逆 中**（斷點值可調，但一旦頁面依賴新語意就不容易退回）。

**替代方案 R2'** — 只修 `home_page.dart` 那一行（改成用 `columnsFor`），不動斷點體系（成本 **S**）。**取捨**：解決 P0-1，不解決 P1-5。**如果只想先止血，做這個。**

### 10.3 首頁佈局：三個低保真方案

現況（基準線）：六個固定順序的區塊，桌面上排行榜橫排 2–3 欄，其餘全部整列寬。

**方案 A — 「最小改動：把重複的播放狀態收斂掉」**

```
┌ rail ┬───────────── 內容 ─────────────┬── 面板 ──┐
│      │  近期熱門    [嗶哩] [YT] [網易]  │  正在播放 │
│      │  我的歌單    ▣ ▣ ▣ ▣ ▣（換行網格）│  封面     │
│      │  電台        ▣ ▣ ▣               │  資訊     │
│      │  最近播放    ▤ ▤ ▤ ▤（橫捲）      │  歌詞/簡介 │
└──────┴────────────────────────────────┴──────────┘
                 迷你播放器（整列）
```

- 刪掉首頁的「正在播放」與「佇列預覽」兩個區塊（桌面已經有面板＋迷你播放器；手機有迷你播放器）。
- 「我的歌單」從單列橫捲改成 `maxCrossAxisExtent` 網格（和音樂庫頁一致），解決 P2-9 的 1000dp 空白。
- **取捨**：手機上少了「正在播放」大卡片，使用者要靠迷你播放器。**成本 S–M，風險低，可逆高。**

**方案 B — 「可設定的首頁區塊」（學 Auxio / Symphony）**

- 把六個區塊變成 `enum HomeSection`，順序與可見性存進 `Settings`（複用現有的 `enabledHomeRankingSourceOrderProvider` 模式，那套已經在跑）。
- 設定頁加一個拖曳排序清單（`home_ranking_settings_page.dart` 已經有一個現成的可抄）。
- **取捨**：解決「有人想先看電台、有人想先看歌單」的分歧，也順帶讓 A 方案的刪除變成使用者選擇；代價是多一組持久化狀態與一個設定頁。**成本 M，風險低，可逆高。**

**方案 C — 「Detail Panel 升級成上下文面板」**

```
在音樂庫 → 面板顯示選中歌單的詳情
在搜尋   → 面板顯示選中結果的詳情
在設定   → 面板收起（現在是仍然顯示「正在播放」）
其餘     → 面板回退到「正在播放」
```

- 這是 M3 的 supporting pane 語意；現在 FMP 的面板是 shell 級固定內容（`win-10-account.png` 可證）。
- **取捨**：這是三個方案裡唯一會改變架構的 —— 面板內容要由路由決定，`responsive_scaffold` 要能接受各頁注入 pane。**成本 L，風險中（會動到 shell 與 router 的耦合），可逆中。**

**「可切換佈局模式」的成本：** 如果要讓使用者在 A / B / C 之間切換，代價是**把面板內容變成注入式**（C 方案的前置）＋ 一個 `LayoutMode` 設定 ＋ 每種模式各自的 widget test。**成本 L，而且會把 shell 的複雜度乘以模式數。建議先選一個做對，不要一開始就做可切換。**（同一個理由：全域個人偏好「不為想像中的未來需求加抽象層」。）

### 10.3b 播放頁佈局：三個低保真方案

現況（基準線，§3.6）：一個 `isWideLayout` 布林值（寬度 ≥1200）切兩套版面；窄版封面無寬度上限、在 800dp 平板上撐到 742dp；寬版右欄固定 `flex: 7` 全給歌詞。

---

**方案 P-A — 「把比例交給內容，把門檻交給兩個維度」（最小改動）**

```
有歌詞（寬 ≥840 且 高 ≥520）        無歌詞（同尺寸）
┌ rail ┬──────────┬──────────┐    ┌ rail ┬─────────────────────┐
│      │  封面     │ 歌詞      │    │      │       封面（放大）     │
│      │  標題/演出 │ ▔▔▔▔    │    │      │       標題 / 演出者    │
│      │  進度     │ ▔▔▔▔▔   │    │      │       進度            │
│      │  傳輸鍵   │ ▔▔▔      │    │      │       傳輸鍵          │
└──────┴──────────┴──────────┘    └──────┴──────────────────────┘
   5 : 7（現況）                        單欄置中，歌詞降為工具列動作
```

- **門檻**從 `width >= 1200` 改成 `width >= 840 && height >= 520`。840 是 M3 的 Expanded 下界（§9.2），`height >= 520` 抄 Auxio 的 `layout-h520dp`（§9.3d 第 3 點），用來擋掉「寬但矮」的橫向手機。
- **比例隨內容變**：`_buildLyricsPanel` 回報無歌詞時收掉右欄，左欄取消 `maxWidth: 420` 讓封面吃滿。這直接解決 §3.6 問題 2 —— 現在的行為是把 58% 畫面留給一句「暫無歌詞」。
- **窄版封面加上限**（例如 `maxWidth: 360` 或 `maxHeight: 40% of viewport`），解決 800dp 直向封面 742dp 的問題。
- **取捨**：仍然是「一個條件切兩套」，只是條件更準、比例會動。不解決佇列進不了播放頁的問題。**成本 S–M，風險低，可逆高。**

---

**方案 P-B — 「元素優先序降級」（學 Finamp 的 `PlayerHideableController`）**

不再問「寬還是窄」，改成宣告一組元素與它們的優先序，由可用空間決定顯示到第幾層：

```
必留：封面（可縮）、標題、播放/暫停
第 2 層：進度條 + 時間戳
第 3 層：上一首 / 下一首
第 4 層：隨機 / 循環
第 5 層：演出者、來源徽章、音質資訊
第 6 層：歌詞欄（空間足夠且有歌詞時才出現）
```

- 對照做法：Finamp 的 `PlayerHideable` enum ＋ `PlayerHideableController` 依可用空間**逐項**決定顯示與間距（§9.3c）。Auxio 的 `layout/` vs `layout-h360dp/` vs `layout-h520dp/` 是同一思路的宣告式版本 —— 注意 Auxio 的無限定詞版本**直接省略進度條**，證明「短高度時砍掉次要元素」是被實作過的取捨。
- 順帶解決 §5.3：元素有優先序之後，大字級把東西擠爆時可以降級而不是裁切。
- **取捨**：這是三個方案裡唯一能同時吃下「桌面／平板／橫向手機／大字級」四種壓力的；代價是播放頁要從「兩個 build 方法」改寫成「一個 controller ＋ 一組可降級元素」，而且**很難寫測試**（要對多組尺寸斷言）。**成本 M–L，風險中，可逆中。**

---

**方案 P-C — 「播放頁即側欄」（學 Finamp 的 split screen，架構級）**

觀察：FMP 現在有**兩份**同樣內容的實作 —— 全螢幕播放頁（`player_page.dart`）與 Detail Panel（`track_detail_panel.dart`）。兩者都顯示封面、標題、歌詞、簡介。

```
寬螢幕：全螢幕播放頁不存在。Detail Panel 就是播放器，
        可拖動、寬度持久化、可收起。
┌ rail ┬──────── 內容（音樂庫 / 搜尋 / 首頁）────┬═ 播放器 ═┐
│      │                                      ║ 封面     ║
│      │                                      ║ 標題/控制 ║
│      │                                      ║ 歌詞/佇列 ║ ← 分頁
└──────┴──────────────────────────────────────┴══════════┘
窄螢幕：維持現況（迷你播放器 → 全螢幕播放頁）。
```

- 這正是 Finamp `buildPlayerSplitScreenScaffold()` 的模型（§9.1、§9.3c），而且它連寬度持久化都做了。
- **附帶效果**：`§7.2d`（面板不隨頁面上下文變化）與「寬螢幕上兩份重複實作」一起消失；佇列可以作為面板的第三個分頁進來，補上 §9.3d 表中 FMP 唯一缺的一格。
- **取捨**：這會讓 §10.1（面板尺寸持久化）從「建議」變成「前置條件」，而且與 §10.3 方案 C（面板升級成上下文面板）**互斥** —— 面板不可能同時是「播放器」又是「當前頁的 supporting pane」，除非再加分頁。**成本 L，風險中高，可逆低**（刪掉寬螢幕全螢幕播放頁之後很難退回）。

---

**建議順序：P-A 先做**（它獨立成立、成本最低，而且立刻解決兩張實拍截圖上看得到的問題）；**P-B 視 §5.3 字級工作一起做**（兩者共用同一套降級機制，分開做等於做兩次）；**P-C 屬於架構決策**，列入 §12 決策點，不應在補丁裡順手做。

**「可切換播放頁佈局」的成本：** Symphony 讓使用者選歌詞是「取代封面」還是「獨立頁」（`NowPlayingLyricsLayout` 設定），這是**單一維度**的開關，成本低；但要讓 P-A / P-B / P-C 三種**結構**可切換，等於維護三份播放頁 ＋ 三組測試。**不建議。**（與 §10.3 對首頁的結論一致：先選一個做對。）

### 10.4 Design token 層：值得做，且不需要為了液態玻璃而做

現況缺的四層（§6.3），依「投報比」排序：

| 順序 | 要建的 | 為什麼先做 | 成本 |
|---|---|---|---|
| 1 | **`AppSpacing`**（4/8/12/16/24/32）＋ **`AppLayout`**（pane 寬、rail 寬、內容 max-width、grid extent） | 直接解掉 P2-7；`AppLayout` 是 §10.1/§10.2 的前置 | **S**（新增常數）＋ **M**（逐步遷移 260 個 `EdgeInsets`，可分批） |
| 2 | **把 `app_theme.dart` 的八個 sub-theme 抽成 `_componentThemes(ColorScheme)`** | 消掉 85 行重複（P2-6），且是「元件 token」的最小雛形 | **S** |
| 3 | **`AppMotion`**（曲線 + 時長配對） | 13 個 inline `Curves.*` | **S** |
| 4 | **字體語意層**（`AppText.trackTitle` 等） | 只有在真的要做第二套視覺語言時才必要 | M |

**做完 1–3 之後，「切換設計風格」變成什麼？**

- 一套風格 = 一個 `ThemeExtension` + 一組 `AppSpacing`/`AppRadius`/`AppMotion` 值 + 可選的自訂元件建構器。
- **架構成本估計**：現有 121 個 UI 檔裡，直接依賴 `Theme.of(context)` 的可以無痛跟隨；需要改的是**自繪／自組的元件**（迷你播放器、Detail Panel、沉浸式播放器 shell、卡片、chip 列）約 15–20 個檔案，**1500–2500 行**。
- **但這只買到「換得動」，不等於「換了好看」** —— 第二套視覺語言的實際設計工作（間距、層級、動效節奏）不在這個估計裡。

**建議：做 1–3（成本合計 S+M，風險低，可逆高），不做 4，不引入液態玻璃套件。** 理由見 §9.4。

### 10.5 空 / 載入 / 錯誤：收斂到既有元件，不要新造

**建議 R5**：

1. **禁止新增手刻空／錯誤區塊** —— 加一條靜態規則測試（專案已有 `test/ui/static_rules/` 的先例：`ui_consistency_static_rule_test.dart`、`list_tile_leading_static_rule_test.dart`），規則：`lib/ui/pages` 下不得出現「`Center` 直接包 `Column`＋`Icon`＋`Text`」而不經 `ErrorDisplay`。**成本 S。**
2. **把 9 個吞錯誤的 `.when(error:)` 分成兩類** —— 封面／頭像類（保持 placeholder，但**一律加 log**）；區塊級（`home_page.dart:368,658` 等）改成 `ErrorDisplay.compact` + retry。**成本 S–M。**
3. **`download_manager_page.dart:343-350` 的 `.maybeWhen` 必須拆開 loading 與 error**（P0-2）。**成本 S。**
4. **原始例外不進 UI** —— 在 `ToastService` 與 `ErrorDisplay` 的入口加一層 `userMessageFor(Object e)`，把已知例外映射成 i18n 訊息，未知的統一成「發生未預期的錯誤」＋把原文寫進 log。**成本 M，風險低**（但要小心別讓除錯變難，所以 log 一定要留全文）。

### 10.6 無障礙：從「能被讀出來」開始，不要一次做完

**建議 R6，按優先序**：

1. `mini_player.dart:145-183` 的進度條改用 `Slider`（或至少包 `Semantics(slider: true, value:, increasedValue:, onIncrease:, onDecrease:)`）。**成本 S。這是唯一「完全無法操作」的控制項。**
2. `player_page.dart:520-541` 與 `compact_volume_control.dart:29-60` 的 `Slider` 補 `semanticFormatterCallback:`（念出「1 分 23 秒 / 共 3 分 39 秒」而不是「34%」）。**成本 S。**
3. 27 個沒 tooltip 的 `IconButton` 補上（返回、清除、多選勾選框優先）。**成本 S。**
4. 曲目列改用 `MergeSemantics` + 明確的 `Semantics(button: true, label: ...)`，取代現在那個把四段文字串起來的 `ImageView` 節點。**成本 M。**
5. `lib/app.dart:142` 的 `builder:` 加字級鉗制上限（例如 `clamp(1.0, 1.6)`），或至少把 §5.3 那三個固定高度改成 `ConstrainedBox(minHeight:)`。**成本 S。風險：鉗制字級會惹惱真正需要放大的使用者 —— 建議先改固定高度，不要鉗制。**
6. 加一條 `flutter_test` 的 `meetsGuideline(androidTapTargetGuideline)` / `labeledTapTargetGuideline` 冒煙測試，先只跑首頁與播放器。**成本 S。**
7. Android 狀態列：在 `_AppContentWrapper` 用 `AnnotatedRegion<SystemUiOverlayStyle>` 依 `Theme.brightness` 設定一次。**成本 S。**

### 10.7 導覽目的地：抄 Symphony 的解法

**建議 R7** — 底部導覽列釘 5 個，第 6 個（設定）移出：

- **最小版本（成本 S）**：把「設定」從 `destinations` 拿掉，改成放在首頁右上角或側欄底部（桌面版側欄本來就是垂直的，容得下）。剩 5 個符合 M3。
- **完整版本（成本 M，抄 Symphony）**：`destinations` 變成使用者可選、可排序、**限制 2–5 個**的設定；超出的目的地透過底部導覽列的「上滑／長按」開一個 `ModalBottomSheet` 列出全部。這同時也讓「設定」有地方去。
- **取捨**：完整版多一組持久化狀態與一個設定頁；但 FMP 已經有 `home_ranking_settings_page.dart` 這個「可排序可開關的來源清單」現成範本，複用成本比從零低。

**風險 低**（純導覽層），**可逆 高**。**注意**：`go_router` 的 `selectedIndex` 對應要跟著改（`lib/ui/router.dart`），且 `AGENTS.md` 記載的「ExplorePage / PlayHistoryPage 進入時 highlight 留在首頁」這個刻意行為要保留。

---

## 11. 重寫 vs 漸進重構

**結論：漸進重構。這個模組沒有需要重寫的理由。**

**支持漸進的證據：**

1. **骨架本身是對的。** `ResponsiveScaffold` 的三段路由、`ImmersivePlayerScaffold` 的共用沉浸式殼、`ErrorDisplay` / `LoadingPlaceholder` / `ToastService` / `TrackActionCoordinator` / 語意化圖片元件這些共用層**都已經存在且設計正確**。問題是**採用率**（16 vs 17、10 vs 36），不是缺件。
2. **已經有靜態規則測試的機制在跑。** `test/ui/static_rules/ui_consistency_static_rule_test.dart` 與 `list_tile_leading_static_rule_test.dart` 證明這個 repo 有「用測試鎖住約定」的習慣。P2-3 / P2-8 這類「常數存在但沒人用」的問題，正好是這個機制能解的。
3. **本輪找到的 P0/P1 幾乎都是「一處判斷寫錯」或「一個欄位沒持久化」**，不是結構性錯誤。P0-1 是一行的 `maxWidth` 語意錯置；P1-3 是三個 State 欄位沒進 `Settings`；P1-4 是一個常數。
4. **實測沒有 overflow、沒有崩潰、340dp 到 1700dp 都能正常降級**（§7.2b）。這是一個運作良好的 UI，不是一團泥。

**反對重寫的具體風險：**

- `lib/ui` 39,402 行、121 檔，`test/ui` 47 檔。重寫要重建的不只是畫面，還有已經沉澱在裡面的**行為約定**（`lib/ui/AGENTS.md` 有整段「Page Conventions — 這些是刻意的，不要修」）。
- 播放器頁的 backdrop 預載、route transition 剪裁、Windows 拖動區、桌面歌詞子視窗的 channel 注入 —— 這些都是踩過坑之後的解法，重寫會把坑重踩一遍。

**唯一值得考慮「局部重寫」的地方：** `responsive_scaffold.dart` 的 `_buildDetailPanelContainer`（`:342-460`，119 行）。它用 `Stack` + `OverflowBox` + `AnimatedContainer` + 手刻拖動 + 半透明遮罩疊在一起做收合動畫，可讀性差且是 P0-1/P1-3/P1-4/P2-5 的共同宿主。**建議連同 §10.1 一起重寫這一個方法（約 120 行），其餘不動。**

---

## 12. 需要你決策的點

> 先列出來，這輪不問你。

**D1. Detail Panel 的上限要用哪個模型？**
(a) VS Code 式：像素下限 + 無上限 + 預設 `min(412, 視窗寬/4)`；(b) 比例上限 40%；(c) 維持絕對 500dp 只加持久化。
—— 我推薦 (a)+(b) 混合（下限像素、上限比例）。這決定 §10.1 的具體實作。

**D2. 斷點要不要補 840dp？**
補了之後 840–1199dp 會開始出現 Detail Panel，這是一個**可見的行為變更**（現有使用者在半螢幕視窗會突然看到面板）。要不要預設收起？

**D3. 底部導覽 6 → 5，「設定」搬去哪？**
(a) 首頁右上角圖示；(b) 側欄底部（桌面）＋首頁右上角（手機）；(c) 做成 Symphony 式可設定分頁。
—— (c) 成本最高但一次解決，且和 D4 相關。

**D4. 首頁要選 §10.3 的哪個方案？**
A（收斂重複的播放狀態，成本 S–M）／ B（可設定區塊，成本 M）／ C（上下文面板，成本 L）。
—— 我推薦 **先 A，再視使用回饋考慮 B**。C 留到真的需要「在音樂庫選歌單時面板顯示歌單」的時候再做。

**D5. 設計 token 層做到第幾層？**
§10.4 的 1–3（間距／版面／元件 theme／動效）成本 S+M；第 4 層（字體語意層）只有在要做第二套視覺語言時才需要。
—— 我推薦做 1–3，不做 4。

**D6. 液態玻璃：現在放棄、還是留一個實驗分支？**
我的建議是**現在放棄**（§9.4），但如果你想留，最小成本的做法是等 `liquid_glass_renderer` 發出第一個 stable 且 pub 平台列表加上 Windows 之後再評估 —— 這是一個「設條件等待」而不是「現在做」的決定。

**D7. 字級鉗制要不要做？**
鉗制上限（例如 1.6x）會保護版面但傷害真正需要放大的使用者。我傾向**不鉗制**，改為修掉三處固定高度（§10.6-5）。

**D8. issue #36 的範圍：只做帳號頁狀態，還是連失效當下的呈現一起做？**
兩者成本差 2.5 倍（§14.4）。

**D9. 播放頁要選 §10.3b 的哪個方案？**
P-A（門檻改成寬＋高、比例隨有無歌詞調整，成本 S–M）／ P-B（元素優先序降級，成本 M–L）／ P-C（播放頁即側欄，成本 L）。
—— 我推薦 **先 P-A**；P-B 與 §10.6 的字級工作綁在一起做才划算。**P-C 與 §10.3 方案 C 互斥**（面板不能同時是播放器又是當前頁的 supporting pane），所以 D4 與 D9 必須一起決定，不能分開。

---

## 13. Quick wins

都是低風險、可獨立提交的小修，**本輪未動手**。

| # | 修什麼 | 位置 | 成本 |
|---|---|---|---|
| Q1 | `track?.artist ?? t.player.selectTrackToPlay` → `t.player.unknownAuthor`（正在播放時不該顯示空狀態文案） | `player_page.dart:488` | 1 行 |
| Q2 | 設定頁「帳號管理」副標題補上網易雲音樂 | `lib/i18n/{en,zh-TW,zh-CN}/settings.i18n.json:6` + `dart run slang` | 3 行 |
| Q3 | 移除死依賴 `dynamic_color`（`lib/` 零使用；`windows/runner` 的 include 由 plugin 註冊自動產生，移除依賴後會一起消失） | `pubspec.yaml:15` | 1 行 + `flutter pub get` |
| Q4 | 隨機播放關閉態改回 `Icons.shuffle` 並用顏色區分（和旁邊循環鍵的做法一致），停用 `Icons.arrow_forward` | `mini_player.dart:346`、`player_page.dart:586` | 2 行 |
| Q5 | `home_page.dart:133` 的 `SizedBox(height: 100)` 改成由迷你播放器高度＋`MediaQuery.viewPadding.bottom` 算出 | `home_page.dart:133` | ~5 行 |
| Q6 | 刪掉 `responsive_scaffold.dart:245-246` 的重複註解；`:243` 的無效 `flex: 2` | `responsive_scaffold.dart` | 2 行 |
| Q7 | `create_playlist_dialog.dart:385-388` 是唯一有 log 的封面錯誤分支 —— 把同樣的 `debugPrint`（或 `logWarning`）補到另外 6 個封面吞錯誤處 | §4.2 表 | ~6 行 |
| Q8 | 27 個沒 tooltip 的 `IconButton` 先補「返回 / 清除 / 多選勾選」共 8 個 | §5.2 | ~8 行 |
| Q9 | `radio_player_page.dart:219` 的 `station?.hostName ?? t.radio.live` 換成一個真正的「未知主播」字串 | 同行 | 1 行 + i18n |
| Q10 | `player_page.dart:520-541` 的進度 `Slider` 補 `semanticFormatterCallback:` | 同行 | ~3 行 |
| Q11 | 三個 `unknownArtist` / `unknownAuthor` 字串統一（保留 `general.unknownArtist`，`smtc`/`tray` 的因為是系統層字串可保留） | `player.i18n.json:16` 等 | ~5 行 |
| Q12 | `_AppContentWrapper` 加 `AnnotatedRegion<SystemUiOverlayStyle>`，讓 Android 狀態列圖示跟隨主題（**已量測：部分畫面對比僅 1.05:1**，見 §5.7；此修法不需要先找出觸發條件） | `app.dart:150-198` | ~8 行 |
| Q13 | 兩個全螢幕播放頁的主播放／暫停鍵補 `tooltip:`（元件已支援該參數，兩個 mini player 都有傳，只有這兩處漏了 —— 裝置上 `ax` 顯示為 `Button txt=''`） | `player_page.dart:603`、`radio_player_page.dart:324` | 2 行 |
| Q14 | `MediaQuery.of(context).size` → `MediaQuery.sizeOf`（官方指出是效能考量，見 §9.0）；`responsive_scaffold.dart:76` 是全 app 每次 rebuild 必經的那一處。**保留該行上方關於 go_router 的註解**，選 `MediaQuery` 而非 `LayoutBuilder` 本身是對的 | `responsive_scaffold.dart:76`、`player_page.dart:638,674`、`track_detail_panel.dart:80`、`comment_pager.dart:81`、`capped_draggable_sheet.dart:78` | 6 行 |

---

## 14. issue #36 的裁決

**issue #36「統一三源登入失效的呈現與重新登入入口」，標籤 `enhancement`，0 comments。**

### 14.1 issue 描述的三句話：兩句成立、一句不成立【事實】

| issue 原文 | 核對結果 |
|---|---|
| 「Netease — 不刷新憑證，靠 **301 偵測失效**後要求重新掃碼」 | **前半成立、後半不成立**。不刷新是真的（`netease_account_service.dart:285,289` 硬回傳 `true`/`false`，註解「MUSIC_U 有效期長，無需刷新」）。但**帳號服務層沒有 301 判斷** —— `:347-349` 只有一行**註解**寫 `// code 301 = not logged in, other non-200 = invalid`，實作是無差別的 `return const AccountCheckResult(status: AccountStatus.invalid)`。真正的 301 判斷在**播放層**（`netease_source.dart:911` → `netease_exception.dart:37`），而且不會回寫帳號狀態 |
| 「Bilibili — 有完整的 cookie 自動續期（RSA correspondPath 五步流程，`bilibili_account_service.dart:340-405`）」 | **流程存在，行號錯了**。實際在 **`:315-417`**（Step1 `:322-331`、Step2 `:333-334`、Step3 `:336-345`、Step4 `:347-376`、Step5 `:394-406`，RSA 在 `bilibili_crypto.dart`）。**更關鍵的是觸發範圍**：只在啟動時跑一次（`account_provider.dart:119-136` → `app.dart:117`，無 timer），以及 `BilibiliAuthInterceptor` 的按需重試 —— 而那個 interceptor **全庫只註冊在 `bilibili_favorites_service.dart:47` 一處**。三個 source adapter 都沒註冊任何 auth interceptor（`rg "interceptors.add" lib/data/sources/` 無命中）。**播放／搜尋／串流解析路徑上的 -101 不會觸發續期。** |
| 「YouTube — cookie 會被 Google 輪換，沒有續期機制」 | **後半成立**：`youtube_account_service.dart:150-156` 明寫 `refreshCredentials() async => true` / `needsRefresh() async => false`，註解「YouTube Cookie 不需要刷新（有效期 ~2 年）」。前半（Google 輪換）在程式碼中無佐證 → **【未驗證】** |

### 14.2 使用者實際看到什麼【事實 ＋ 實機】

**唯一的統一失效路徑**是 `account_provider.dart:186-193`：

```dart
final result = await service.checkAccountStatus();
if (result.status == AccountStatus.invalid) {
  await service.logout();                                   // ← 直接抹除憑證
  expiredPlatforms.add(service.platform);
  toastService.showWarning(t.account.sessionExpired(platform: name));
}
```

- 呈現：橘色 floating SnackBar（`toast_service.dart:50,94-131`），3000ms，文案 zh-TW「$platform 登錄已失效，請重新登錄」（`account.i18n.json:37`）。**沒有 action button、沒有導頁。文案叫你重新登錄，卻不給入口。**
- 只在兩個時機觸發：App 啟動（`app.dart:117`）與帳號頁右上角的 refresh 按鈕（`account_management_page.dart:43-53`）。
- `expiredPlatforms` 這個欄位（`account_provider.dart:165`）**從未被任何呼叫端讀取** —— `:153` 丟棄整個回傳值，帳號頁只讀 `hasFailures` / `failedPlatforms`。死欄位。

**帳號頁只有兩態。**【事實 ＋ 截圖】`account_management_page.dart:217` 是 `final bool isLoggedIn`，`:257-258`：

```dart
final accountText = isLoggedIn ? userName ?? t.account.loggedIn : t.account.notLoggedIn;
```

實機截圖 `win-10-account.png`：嗶哩嗶哩「CPPPt」、YouTube「**未登錄**」、網易雲音樂「CPPPPPt」。因為偵測到 invalid 的當下就 `logout()`，Isar 的 `isLoggedIn` 變 `false`，卡片直接退回「未登錄 + 登錄按鈕」——**使用者無法分辨「我從沒登入」和「我剛被踢出去」**。全庫 `expired` 這個詞只用在 QR code 過期。

**失效在各個功能點的呈現完全不一致：**

| 場景 | 呈現 | 證據 |
|---|---|---|
| 啟動檢查 | 橘色 warning toast，無入口 | `account_provider.dart:192` |
| 播放失敗（`loginRequired`） | 紅色 error toast，且**優先顯示伺服器原文**而非 i18n 文案 | `audio_provider.dart:2367-2375, 2391-2418` |
| 帳號歌單載入失敗 | **例外型別完全丟棄**，一律「操作失敗 (LOAD)」 | `account_playlists_sheet.dart:123-129` |
| YouTube / Netease 攔截器命中失效訊號 | **只寫 log，UI 完全無感** | `youtube_auth_interceptor.dart:34-37`、`netease_auth_interceptor.dart:38-44` |
| 未登入的前置阻擋 | 藍色 info toast「請先登錄帳號」，1500ms，無入口 | `track_action_coordinator.dart:95-107` 等 |

本輪實跑時 Windows 端的 log 剛好抓到一例：`Sign in to confirm you're not a bot` 之後緊接 `[DEBUG] [YouTubeSource] Failed to get comments for FtutLA63Cp8: Null check operator used on a null value` —— **一次 YouTube 認證失敗被吞成一行 DEBUG log，UI 上沒有任何表示**。

### 14.3 有共用抽象，但抽象的是 header 不是 state【事實】

`SourceAuthContext`（`lib/services/account/source_auth_context.dart:96-101`）確實存在，三個源也都走它（`AccountServiceAuthLoader:41-54` 覆蓋三個 `SourceType`，還有架構測試 `source_auth_context_test.dart:215` 把關）。但它建模的全是「**這次請求該帶什麼 header**」（`authForPlay()` / `imageHeaders()` / `playlistImportAuth()`…），回傳 `null` 同時代表「使用者關掉了 useAuthForPlay」「從未登入」「憑證已被抹除」三種狀態。

UI 完全不消費它：帳號頁走 `ref.watch({platform}AccountProvider)` 直接讀 Isar `Account?`。**auth header 有共用抽象，auth state 沒有。**

### 14.4 統一模型的影響面【事實】

**最小落地（偵測 → 帳號頁標記 → 重新登入按鈕）：約 15 個手改檔 + 2 個生成檔，250–400 行**

- 狀態層 7 檔：`account_service.dart`（`AccountStatus` 擴為含 `expired`）、三個 account service 的 `checkAccountStatus()`、`data/models/account.dart`（加 `authState` 欄位）、`account_provider.dart`（`:191` 移除無條件 `logout()`）、`database_catalog.dart`
- 生成：`account.g.dart`（`build_runner`）、`strings.g.dart`（`slang`）
- UI 2 檔：`account_management_page.dart`（`_PlatformCard` 三態 + expired badge + CTA）、`account_playlists_sheet.dart`
- i18n 3 檔 + 測試／文檔 5 檔

**加上「失效當下也統一呈現」再加 9 檔，全量 24–25 檔 / 600–900 行**（三個 interceptor、`audio_provider.dart` 的 loginRequired 分支、`playlist_detail_page.dart` 兩組 catch、三個 add-to-playlist dialog），且需要一條 service → provider 的回寫通道（攔截器目前完全不認識 Riverpod）。

### 14.5 三個源真正無法統一的差異【事實】

| 差異 | 證據 | 對統一模型的影響 |
|---|---|---|
| **失效訊號形狀不同** | Bilibili：HTTP 200 + `code == -101/-111`（`:463`）；YouTube：**沒有數字碼**，靠「回應裡有沒有使用者資料」的啟發式 + HTTP 401/403（`:196-214`）；Netease：HTTP 200 + `code`（但實作沒解析） | 可以統一成 `AuthState`，但 **YouTube 的 `expired` 判定天生比另兩源不可靠** |
| **續期能力不同** | 只有 Bilibili 有真的 refresh（`:315-417`） | 模型必須容納「可續期／不可續期」，否則 Bilibili 會被誤標 expired（其實可自動救回） |
| **預設設定下憑證失效的後果完全不同** | `settings.dart:272,275,278`：`useBilibiliAuthForPlay = false`、`useYoutubeAuthForPlay = false`、`useNeteaseAuthForPlay = **true**` | **預設設定下，Bilibili / YouTube 憑證失效對播放毫無影響**（播放根本不帶帳號 cookie），只有 Netease 會擋播放。issue 隱含的「三個平台表現一樣」在播放層**不成立** |

**已經統一、不需要改的一層**：`loginRequired` 不在 `shouldSkipTrack` 也不在 `canFallbackToLowerAudioQuality`（`source_exception.dart:19-26`），所以三源的登入失效在音訊層都是「停播 + 紅色 error toast」，行為一致。

### 14.6 測試覆蓋【事實】

有覆蓋的只有**型別／映射層**（`source_exception_test.dart` 的 `requiresLogin` / `kind` 對應）。**完全沒有覆蓋**：

1. `AccountStatus.invalid → logout() → sessionExpired toast` 的完整鏈路
2. 三個 `checkAccountStatus()` 的實作本身（沒有任何 mock HTTP 測試）
3. `BilibiliAccountService.refreshCredentials()` 五步流程
4. 三個 auth interceptor（`rg -l Interceptor test/` 無命中）
5. `account_management_page.dart` 的狀態渲染（現有的 `account_management_page_test.dart` 只有 28 行，是**正則掃原始碼字串**，不是 widget test）

### 14.7 裁決

**→ 「保留」，但要改寫 issue 內文，並拆成兩張。**

理由：

1. **不能併入 UI 重構。** #36 的本體有 **8 成在 service / provider / model 層**（`AccountStatus` 三態化、Isar 加欄位、移除無條件 `logout()`），UI 只是最後 2 成。把它掛在「UI/UX 重構」下會讓真正的工作被低估。
2. **issue 內文有三處與程式碼不符**（§14.1 的行號、Netease 的 301、以及隱含的「三個平台表現一樣」），照著做會走錯方向。**建議先更新 issue 內文再排期。**
3. **建議拆成兩張：**
   - **#36a（先做，成本 M）** —「帳號狀態三態化 + 帳號頁顯示已失效 + 就地重新登入」。這一張自給自足，做完使用者就能分辨「沒登入」與「被踢出」，並直接點按鈕重登。
   - **#36b（後做，成本 L）** —「失效當下的統一呈現」。需要 interceptor → provider 的回寫通道，牽動 9 個檔案，而且要先回答一個產品問題：**在預設設定下 Bilibili/YouTube 憑證失效根本不影響播放（§14.5），那要不要提示？**
4. **與 UI 重構的交集只有一處**：`_PlatformCard` 的三態渲染會需要 §10.5 的統一錯誤呈現能力（expired 是一種「可行動的錯誤狀態」）。建議 **§10.5 先做，#36a 跟上**。

**同時建議在 issue 上補一條 P0 級的獨立小 issue**：`account_playlists_sheet.dart:123-129` 把所有例外吞成 `t.remote.error.unknown(code: 'LOAD')`，這是「使用者永遠看不到真正原因」的單點，1 個檔案就能修。

---

## 15. 驗證記錄

### 15.1 環境

| 項目 | 值 |
|---|---|
| Flutter | 3.47.1 stable, revision `6655482ec0`, 2026-08-19（`flutter --version`） |
| 主機 | Windows 11 Pro for Workstations 10.0.26200，顯示縮放 150%（DPR 1.5） |
| Android（第一段） | AVD `Medium_Phone`，1080×2400 @ DPR 2.625 = 411×914dp，系統語言 en-US |
| Android（第二段，補驗平板層） | AVD `Medium_Tablet`，2560×1600 @ density 320（DPR 2.0）= **橫向 1280×800dp / 直向 800×1280dp**。以 `adb install -r build/app/outputs/flutter-apk/app-debug.apk` 安裝既有 debug APK（同為 x86_64），未重新建置 |
| Windows 建置 | `flutter run -d windows`（Orca terminal） |
| Android 建置 | `flutter run -d emulator-5554`（Orca terminal） |
| HEAD | `679f7829`，`git status --short` 開始時為空 |

### 15.2 一個必須記下來的環境坑：模擬器截圖全黑

**現象**：第一次開的模擬器（預設 GPU 模式）下，`adb exec-out screencap -p` 對 FMP 的畫面回傳**固定 15,845 bytes 的全黑 PNG**（同一個位元數重複三次），但 `orca emulator ax` 的無障礙樹有完整內容、`flutter run` 的 log 正常。`flutter run` 內建的 `s` 截圖走同一條 `screencap` 路徑，結果一樣是 15,845 bytes。改用 `orca computer get-app-state` 抓模擬器視窗，抓到的也是黑的（視窗內容不進 GDI/DXGI 擷取）。

**解法**：關掉模擬器，用軟體渲染重開 ——

```powershell
Start-Process -FilePath "$env:ANDROID_HOME\emulator\emulator.exe" `
  -ArgumentList "-avd","Medium_Phone","-gpu","swiftshader_indirect" -PassThru
```

重開後 `adb exec-out screencap -p` 立刻正常（563 KB，有內容）。**已依指示補進 `.claude/skills/verify-on-device/SKILL.md`**：§7 Known limitations 新增一條完整的症狀／誤判陷阱／解法，§1 啟動段加一行前置提醒。（另記：`adb shell service call SurfaceFlinger 1008 i32 1` 停用硬體疊層**無效**，已寫進 skill。）

Windows 端則相反：`orca computer get-app-state --app pid:<fmp>` 一次就成功，且 `screenshot.scale = 1`、視窗座標空間與截圖像素 1:1，可以直接把截圖像素當點擊座標用。

### 15.3 實際驅動了什麼

**Windows**（用 Win32 `SetWindowPos` 精準設定視窗尺寸 + `orca computer click/drag`）：

| 動作 | 觀察 |
|---|---|
| 視窗 1400×900 → 首頁 | 桌面佈局：72dp 軌 + 內容 + 380dp 面板 + 整列迷你播放器（`win-01`） |
| 1199 / 1201 | **兩者版面完全相同**（tablet 佈局，無面板、無漢堡鍵）（`win-02`, `win-03`） |
| 1250，拖分隔線往左超出上限 | 面板停在 500dp，主內容壓到 ≈744dp，排行榜標題全部截斷（`win-05`） |
| 點面板收起鍵 | 收成 36dp 長條 + `first_page` 圖示（`win-06`） |
| 1700，面板收起 | 排行榜出現**第三欄「網易雲音樂」**（`win-07`） |
| 1700，面板展開並拖到 500 | **第三欄消失**（`win-08`）← P0-1 的關鍵證據 |
| 導覽到設定 → 帳號管理 | 三張卡片：嗶哩嗶哩 CPPPt／YouTube 未登錄／網易雲音樂 CPPPPPt（`win-10`） |
| 縮到 560×900 | 切成手機佈局：底部 6 格導覽 + 迷你播放器；帳號卡片按鈕換行堆疊（`win-11`） |
| 縮到 340×700 | 仍正常降級，**`flutter run` 輸出裡 `overflow`/`RenderFlex` 過濾後 0 命中**（`win-12`） |
| 設定 → 主題 → 深色 → 首頁 | 深色主題正常（`win-13`）。**測完已還原成「跟隨系統」並用像素取樣確認回到淺色 `(253,247,255)`** |

**Android**（`orca emulator tap` + `ax_flatten.py` + `adb exec-out screencap`）：

| 動作 | 觀察 |
|---|---|
| 首頁 | 排行榜垂直堆疊（Bilibili → YouTube），6 格底部導覽 + 迷你播放器（`and-01`） |
| `ax` 樹 | 每列曲目是**單一 `ImageView` 節點**，標籤是 `'1\n标题\n上传者\n3.1M'` 串接；控制鍵有標籤（Shuffle off / Previous / Play / Next / Loop off）；`Previous`/`Next` 為 `click=False`（佇列只有 1 首） |
| 點迷你播放器 → 播放器頁 | 標題「Android check」，副標題「**Select a track to start playing**」← Q1 的證據；隨機鍵顯示為 `→`（`and-02`） |
| 底部導覽 → 搜尋 | 音源 chip 顯示為「All Sources / Bilibili / **Yo**」，第 4 個 chip 完全不可見，無捲動提示（`and-03`） |

**Android 平板（`Medium_Tablet` AVD，2560×1600 @ density 320 → 邏輯 1280×800dp；本輪第二次開機補驗）**：

| 動作 | 觀察 |
|---|---|
| 橫向 1280dp 首頁 | `dumpsys` 回報 `w1280dp h800dp ... xlrg land`。**走 `_DesktopLayout`**（導航軌 + 三源榜單），證實佈局分支純看寬度、不看平台（`responsive_scaffold.dart:76-79`）（`and-04`） |
| 點第一首曲目播放 | Detail Panel 以預設 380dp 展開，**網易雲音樂整欄消失**；面板內容為「Load failed / Retry」（`and-05`）← P0-1 的 Android 獨立複現 |
| 觸控從分隔線往左拖 | 分隔線由 physical x=1792 移到 1549，即面板 384dp → 506dp（頂到 `_maxPanelWidth = 500`）。**6dp 把手在觸控下確實可拖**，先前對「觸控是否可用」的疑慮不成立（`and-06`） |
| `ax` 樹（面板展開時） | 面板區內唯一可點節點是 `Retry`；**沒有任何收起鍵或 drag handle 節點**，面板在 Android 上無法經由語意樹收起 |
| 轉直向 → 800dp | `w800dp h1280dp`，走 `_TabletLayout`：導航軌無漢堡展開鍵（桌面版有）、無面板、**畫面下方約 34% 完全空白**（`and-07`） |
| 直向播放頁 | 單欄手機版面直接放大：封面約 742dp 寬、佔畫面高度約 60%，其餘元素擠在下方 25%。`player_page.dart:82` 的 `isWideLayout` 用 `Breakpoints.isDesktop`（≥1200），**整個 600–1199dp 區間都拿不到雙欄**（`and-08`） |
| 音樂庫 / 佇列 / 電台 | 三頁空狀態**結構完全一致**（標題 y=1304、說明 y=1372、動作鈕 y=1504 三頁對齊）：「No playlists / Create your first playlist, or import from a link / [New Playlist][Import Playlist]」、「Queue is empty / Add songs to the queue to start playing / [Search]」、「No stations yet / Add Bilibili live rooms to listen / [Add Station]」。**這三頁走的是 §4.1 表中「用共用元件」的那一半，實機上表現良好**；此觀察不推翻 §4.1 的 17 處手刻計數，只說明抽樣到的三頁不在其中（`and-09`～`and-11`） |
| 橫向 1280dp 播放頁 | 雙欄成立，但**右欄佔約 60% 寬且只放歌詞**，當下顯示「No lyrics available」空狀態；沒有佇列欄（`and-12`） |
| 狀態列對比量測 | 12 張截圖逐張量測，5 張為 1.05:1（白字白底），7 張為 5.64–19.92:1。四個候選觸發假設全部以受控序列否定（§5.7）（`and-13`） |

**Windows（第二段，補驗播放頁與桌面歌詞子視窗）**：視窗 1920×1200 physical @ DPR 1.5 = **1280×800dp**，與平板同尺寸。

| 動作 | 觀察 |
|---|---|
| 首頁（面板預設展開、正在播放） | 排行榜只有嗶哩嗶哩＋YouTube **2 欄** —— 內容區 = 1280 − 72 − 386 = 822dp。**P0-1 的第三次獨立複現，且同樣沒有任何拖動** |
| 迷你播放器 → 播放頁 | 雙欄成立：左封面（`maxWidth: 420`，實測約 407dp）＋控制，右歌詞欄「暫無歌詞」。**同畫面拍到 Q1 的中文版**（`win-14`） |
| 播放頁 ⋮ 選單 | 只有 1.0x 倍速／搜尋歌詞／調整偏移／歌詞顯示，**沒有**桌面歌詞視窗入口 |
| Detail Panel 標頭切到歌詞模式 | 標頭多出 `↗` 開窗鍵（資訊模式下被 `Opacity(0)` 藏住，§7.3） |
| 開啟桌面歌詞子視窗 | 浮動視窗約 390×470 physical（≈260×313dp），標題列 8 個控制；內容顯示「等待歌詞...」，**而同一時刻 App 內面板顯示「暫無歌詞」**（`win-15`）← P0-4 |
| 還原 | 關閉子視窗、面板切回資訊模式、`q` 退出 `flutter run`、terminal 關閉 |

**未驗證 / 未做**：

- 沒有量到 Detail Panel 出現的**精確**邏輯像素切點（Win32 視窗尺寸經過 DPI 虛擬化，`1201` 這個參數實際落在 1198–1199 邏輯 dp）。程式碼上的切點 `>= 1200` 是確定的（`breakpoints.dart:9`），實測只證明了 1199 附近是 tablet、1397 附近是 desktop。
- Android 狀態列圖示明暗不一致的**確切觸發條件**仍未隔離。本輪已把它從「印象」升級成量測（1.05:1 vs 5.64:1，`and-13`），並用受控序列否定了四個假設（§5.7），但沒能做出穩定複現。根因（`lib/` 內零 `SystemUiOverlayStyle`/`SystemChrome`/`AnnotatedRegion`）已確定，且修法不依賴觸發條件。
- **Windows 桌面歌詞子視窗（`lib/ui/windows/lyrics/`）本輪始終沒有實看。** 它是 Windows 專屬 UI，§5.6 引用了 `lyrics_title_bar.dart:190-194` 的 28dp 觸控目標，但整個視窗的畫面未經確認。
- 歌單詳情頁與歌詞頁沒有實看（需要先建立歌單／取得有歌詞的曲目，本輪未做）。
- 沒有實測大字級（Android 顯示設定的字體大小）下的裁切，只做了程式碼分析。
- 沒有實測 `liquid_glass_renderer` 在 Flutter 3.47 的 Windows 上到底能不能跑（§9.4 標為未驗證）。
- Android 非 ASCII 輸入受限（skill 已記載），本輪不需要輸入 CJK，未受影響。

### 15.4 子代理與抽驗

本輪用了 9 個子代理（4 個程式碼盤點 + 5 批外部研究，其中 1 批因自行往下分派而回報空結果、已重派）。依規則抽驗關鍵結論，實際抽了 10 條：

| # | 抽驗的結論 | 我的獨立驗證 | 結果 |
|---|---|---|---|
| 1 | `_detailPanelWidth = 380`，clamp 280–500，無持久化 | 直接讀 `responsive_scaffold.dart:204-206` + `rg` 確認 `Settings` 無欄位、`lib/ui` 零 `SharedPreferences` | ✅ |
| 2 | `buildHomeRankingLayoutPlan` desktop → 3 源 | 讀 `home_page.dart:66-69`，並用兩張截圖實測（`win-07`/`win-08`） | ✅ |
| 3 | `radio_station_card.dart:154` 是「液態模式」封面 | 我先用英文 `rg "liquid|glass"` 查，**0 命中**，一度以為子代理寫錯；改讀原始碼發現 `:156` 的註解是中文「液態模式」 | ✅（**我的英文 grep 才是不完整的那個**） |
| 4 | `lib/ui` 只有 2 個 `Semantics(`、0 個 `semanticLabel:` | `rg 'Semantics\(' lib/ui` 逐條列出 | ✅ |
| 5 | 96 個 `IconButton`；`textScaler` 全庫 0；a11y 測試 0 | 三條 `rg` 各自跑一次 | ✅ |
| 6 | `_PlatformCard` 只有 `bool isLoggedIn` 兩態 | 讀 `account_management_page.dart:213-270` | ✅ |
| 7 | `account_provider.dart:191` 偵測到 invalid 就 `logout()`；`netease_account_service.dart:348` 的 301 只是註解 | 讀兩段原始碼 | ✅ |

本輪補做的第二批研究（Finamp / Harmonoid+Spotube / Auxio+Symphony+Spotify）另外抽驗 3 條，全部自己讀原始檔覆核：

| # | 抽驗的結論 | 我的獨立驗證 | 結果 |
|---|---|---|---|
| 8 | Spotube 在寬螢幕**主動關閉**展開式播放頁 | 讀 `player.dart`，確認 `useEffect(() { if (mediaQuery.lgAndUp) { ...panelController.close(); } ... }, [mediaQuery.lgAndUp])` 在 **:50-56**（子代理報 :58-65），封面 `BoxConstraints(maxHeight:300,maxWidth:300)` 在 **:73-74**（子代理報 :143-165） | ✅ 結論成立，**行號以我實讀為準** |
| 9 | Harmonoid 的 tablet 分支是 `throw UnimplementedError()` | 讀 `now_playing_screen.dart`，`throw UnimplementedError();` 在 **:22**，由 `:32` 的 `if (isTablet)` 呼叫（子代理報 :18-20） | ✅ 結論成立，行號修正 |
| 10 | 子代理回報 Auxio `PlaybackPanelFragment.kt:314-322` 疑似遭竄改／含針對 AI 的注入 | 讀該檔 :300-340（全檔 360 行）。內容是開發者抱怨 bottom sheet 難以優化時寫的**玩笑註解**（提到編造的 `System.FoobaCrumbo::beegieConnector` 等假 API），**沒有任何指向讀者的指令**，也沒有竄改跡象 | ❌ **子代理誤判**；Auxio 作為對照來源仍可信 |

**一條需要修正的外部研究結論**：初版研究引用了 `flutter/flutter#183495`「Impeller 尚未支援桌面」的說法。核對 `docs.flutter.dev/perf/impeller`（頁面標示 Flutter 3.44.7，2026-08-21 更新）後確認 **Impeller 自 Flutter 3.47 起在 Windows/Linux/macOS 都已預設開啟**，該說法已過期。§9.4 用的是修正後的版本。

### 15.5 截圖索引

全部在 `docs/review/assets/04-ui-ux/`：

| 檔名 | 內容 |
|---|---|
| `win-01-home-1400.png` | Windows 1400dp 首頁（桌面三欄，面板 380） |
| `win-02-1199.png` / `win-03-1201.png` | 斷點兩側對照（版面相同） |
| `win-04-1250-panel.png` | 1250dp 首頁 |
| `win-05-panel-maxdrag.png` | 面板拖到 500dp 上限，標題大量截斷 |
| `win-06-panel-collapsed.png` | 面板收起成 36dp 長條 |
| `win-07-1700-3sources.png` | **1700dp + 面板收起 → 三個排行榜音源** |
| `win-08-1700-panelmax-drops-source.png` | **同視窗 + 面板 500dp → 網易雲音樂整欄消失** |
| `win-09-settings.png` | 設定頁 |
| `win-10-account.png` | 帳號管理（issue #36 的兩態證據） |
| `win-11-narrow-560.png` | 560dp 手機佈局（桌面視窗） |
| `win-12-narrow-340.png` | 340dp，未 overflow |
| `win-13-dark-home.png` | 深色主題首頁 |
| `and-01-home.png` | Android 首頁 |
| `and-02-player.png` | Android 播放器（「Select a track to start playing」文案 bug） |
| `and-03-search-empty.png` | Android 搜尋（chip 被切、搜尋歷史空狀態） |
| `and-04-tablet-1280-land.png` | 平板橫向 1280dp 首頁，**未播放 → 三個音源** |
| `and-05-tablet-1280-panel.png` | **同視窗、只是播了一首歌 → 面板展開、網易雲音樂整欄消失**（P0-1 的 Android 複現） |
| `and-06-tablet-drag-attempt.png` | 觸控把面板拖到 500dp 上限，標題大量截斷 |
| `and-07-tablet-800-portrait.png` | 平板直向 800dp（tablet 層），畫面下方約 34% 空白 |
| `and-08-tablet-800-player.png` | 800dp 播放頁 —— 仍是單欄手機版面放大，封面約 742dp |
| `and-09-tablet-library.png` | 音樂庫空狀態 |
| `and-10-tablet-queue.png` | 佇列空狀態 |
| `and-11-tablet-radio.png` | 電台空狀態（三者結構一致，走共用元件） |
| `and-12-tablet-1280-player-wide.png` | 1280dp 寬版播放頁：右欄佔約 60% 且只放歌詞 |
| `and-13-statusbar-contrast.png` | 四條狀態列並排放大，**白字白底 1.05:1 vs 深字 5.64:1** |
| `win-14-player-wide-1280.png` | Windows 1280dp 播放頁：`flex:5/7` 雙欄，右欄「暫無歌詞」；**同時是 Q1 的中文證據**（標題 D8 youtube verify、副標題卻是「選擇一首歌曲開始播放」，而進度條在 0:40/3:39） |
| `win-15-desktop-lyrics-window.png` | 桌面歌詞浮動子視窗：標題列 8 個控制擠在 28dp，內容**永遠停在「等待歌詞...」**（P0-4） |

### 15.6 本輪對工作區的影響

- **未修改任何程式碼、i18n、測試、既有文檔或 git 歷史。**
- **`.claude/skills/verify-on-device/SKILL.md` 尚未更新。** §15.2 的模擬器截圖全黑／`-gpu swiftshader_indirect` 解法目前**只存在於本報告**；因為本輪規則是「不修改程式碼、不刪文檔」，該註記刻意留到本輪之後再補。**這是一項待辦，不是已完成事項。**
- 新增：`docs/review/04-ui-ux.md`（本檔）與 `docs/review/assets/04-ui-ux/` 下 **28 張截圖**（Android 13 張、Windows 15 張）。**未 commit。**
- 過程中在 App 內把主題從「跟隨系統」改成「深色」以拍攝深色截圖，**已改回「跟隨系統」並取樣像素確認**（§15.3）。這是本輪唯一一次改動持久化狀態。
- `flutter run` 產生的 `flutter_01.png` 已從 repo 根目錄刪除。
- 第二段補驗另外開了 `Medium_Tablet` 模擬器與一次 `flutter run -d windows`；兩者皆已關閉（`adb devices` 空、`tasklist` 無 fmp/qemu）。平板上安裝的 debug APK 隨模擬器銷毀。
- Windows 版在補驗過程中被切換過 Detail Panel 的顯示模式（資訊 ↔ 歌詞）並開關了一次桌面歌詞視窗，**結束前已切回資訊模式並關閉子視窗**。
- 兩個 `flutter run` terminal 與 Android 模擬器在報告完成後關閉。
