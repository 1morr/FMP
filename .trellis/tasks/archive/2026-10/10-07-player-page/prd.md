# M2 PR 18a：播放頁 B

M2 `design.md` §9.3、§9.6、§9.5（Ctrl+L／Q、Esc）、§3.1–§3.5（`layout_state`）、§7.6（速度）、§8.2（`NowPlaying.speed`）；ADR 0024 §決定 1、3、4、8；ADR 0023 §決定 2。依賴 PR 4、PR 17。佇列分頁的編輯與手機的佇列底部面板在 PR 18b，右側「正在播放」面板在 PR 19。

## 目標

點播放列空白處，開啟全螢幕播放頁：
- 依視窗寬度有三種版面，大封面加完整控制；
- 速度選單在這頁；
- 右欄有歌詞、佇列、詳細三個分頁，上次停在哪一分頁依裝置記住；
- 鍵盤可以 Esc 關閉、Ctrl+L／Q 切分頁、F6 在頁內換區。

## 要做的

### 開啟與關閉

- **開啟**：點播放列的空白處（曲名、封面那一塊，與按鈕的點擊區分開）開播放頁；Ctrl+L／Ctrl+Q 在播放頁沒開而且佇列不空時也會開（design §9.5）。
- **路由**：推在根 Navigator 的全螢幕 route，提示仍在它上面。外殼以 route observer 得知播放頁在最上層時，`toastBottomInsetProvider` 改成只有底部安全區（ADR 0023 §決定 2）。
- **關閉**：
  - 左上角的收合鈕（向下箭頭）：tooltip「關閉播放頁（Esc）」，三語言（主對話定：桌面沒有返回鍵，照 Spotify、YouTube Music 的慣例）；
  - Esc：頁面的 `Shortcuts` 以 `Navigator.maybePop` 關閉；對話框、選單照 Flutter 內建先關；
  - Android 返回鍵：route 先 pop，只關播放頁（補 PR 16a 的那一項）。
- 關閉後焦點回到開啟它的元件（design §9.6）。
- 佇列變空或沒有目前這首時，播放頁自己關閉。

### 版面（依整個視窗的 `WindowClass`，design §9.3）

| 寬度 | 版面 |
|---|---|
| compact、medium | 封面與歌詞切換（點封面切換）；控制在下方。佇列的底部面板在 18b，這個 PR 不放佇列入口 |
| expanded、large | 左右各半。左：封面（上限 420dp）、曲名、上傳者、進度、五個控制（隨機、上一首、播放、下一首、循環）、「⋯」；右：分頁「歌詞｜佇列｜詳細」 |
| extraLarge | 三欄約 1：1.15：0.9：封面與控制｜歌詞｜分頁「佇列｜詳細」 |

- **控制**：
  - 五個控制各版面都有，所以手機直向也有隨機、循環（PR 10 留下的）；
  - 狀態文字照播放列：重試中、等待網路連線、試聽（PR 12 留下的「播放頁的試聽標示」）；
  - 進度條可拖；
  - 啟動恢復後還沒播時，照 PR 17 的規則顯示恢復的位置。
- **「⋯」選單**：播放速度 0.5、0.75、1.0、1.25、1.5、1.75、2.0，目前的打勾（design §7.6，不持久化，重啟回到 1.0）。「切換右側面板」與面板一起在 PR 19 加。
- **歌詞**：M2 一律顯示「沒有歌詞」的空狀態（design §9.3）。
- **佇列分頁**（這個 PR 的最小版本）：
  - 唯讀清單，標出目前這首，點一下 `jumpTo`；
  - 拖曳、移除、下一首播放、清空、隨機說明都在 18b；
  - 一萬首時以 `ListView.builder` 不一次建出。
- **詳細分頁**：`TrackDetails` widget（之後與右側面板共用）：封面、曲名、上傳者、時長、音源名稱（以 `pluginId` 查插件名稱）。
- **背景與毛玻璃**：
  - 背景是模糊的封面加遮罩；
  - 右欄與控制區是約 66% 的 `surface` 色加 `BackdropFilter` 一般模糊；
  - `MediaQuery.highContrastOf` 為真時改成不透明；
  - 數值放 `AppLayout`／`AppTokens`；
  - 沒有封面時用佔位的背景。

### 分頁記憶與 `layout_state`（schema 升一版，design §3.4）

- 新表 `layout_state`（單列）：`player_tab` text?、`panel_expanded` bool?、`panel_width` real?。
  - 面板的兩欄這次就建好，PR 19 不必再升 schema；
  - 寬度在資料庫只擋明顯的壞值（> 1600）。
- 不屬於任何設定組，M4 的備份不收它。
- `player_tab` 存使用者上次選的分頁（`lyrics`／`queue`／`details`，寫死的字串）。
  - extraLarge 沒有「歌詞」分頁：記住的是歌詞時顯示佇列，但不覆寫記憶，回到兩欄時仍是歌詞。
- 照 `.trellis/spec/app/data/index.md` § 改 schema 的完整流程：快照、`stepByStep`、三種 migration 測試（含升級後既有表的使用者值不變）。

### 焦點與快捷鍵（design §9.5、§9.6）

- 播放頁包一層共用的 `PlaybackShortcuts`：播放頁是另一個 route，外殼那層管不到它。
- 頁內焦點區：控制區｜右欄分頁（extraLarge 另有歌詞欄）。F6 在頁內循環，Tab 只在區內。外殼的三區在播放頁之下不動。
- Ctrl+L：右欄切到歌詞。extraLarge 時焦點移到歌詞欄；compact、medium 時切到歌詞那一面。
- Ctrl+Q：右欄切到佇列。compact、medium 時不做事（佇列的底部面板在 18b，18b 再接）。
- 輸入框規則照 PR 17。

### 速度

- 控制器提供目前速度（getter 加 stream，或同等的可觀察狀態），給播放頁的「⋯」與 `NowPlayingPublisher` 用。
- publisher 推出的 `NowPlaying.speed` 跟著實際速度（PR 16a 留下的：否則系統推算的進度會偏）。

### 文件

- `app/AGENTS.md` § 介面：播放頁、開關、版面、分頁記憶、焦點與快捷鍵，每條寫出閘門。
- § 資料層：`layout_state`。
- `.trellis/spec/app/{ui,data}/` 需要時更新。
- ADR 0024 §決定 1 加一行更正：Flutter 3.47.5 的 `AccessibilityFeatures` 沒有「減少透明度」，目前只照 `highContrast` 改成不透明（design §11）。

## 驗收

- **開關**：
  - 點播放列空白處會開，點按鈕不會開；
  - 收合鈕、Esc、返回都關；
  - 有對話框時 Esc 先關對話框；
  - 關閉後焦點回到原處；
  - 佇列清空時自動關閉。
- **版面**：compact、medium、expanded、large、extraLarge 各有測試，涵蓋控制項、分頁、封面上限。
- **golden**：1000、1400、1800 寬，只守結構；`--update-goldens` 後由主對話看圖。
- **guideline**：淺色、深色 × 最淺、最深的測試封面，加進 `test/ui/guidelines_test.dart`。
- **分頁記憶**：選了會寫入；重開還在；extraLarge 記住歌詞時顯示佇列、不覆寫。
- **快捷鍵**：在播放頁上，Esc、F6、Ctrl+L／Q、空白鍵與其他播放鍵都有效；播放頁沒開時 Ctrl+L／Q 會開；佇列空時不開。
- **速度**：選單的七個值、目前的打勾；選了會呼叫控制器；publisher 推出新速度。
- **毛玻璃**：高對比時不透明，有測試。
- **提示貼底**：播放頁在最上層時，提示的底部只留安全區。`integration_test/toast_layering_test.dart` 加播放頁的案例。
- **migration**：v5 → v6 與從 v1–v4 升上來的案例；全新的資料庫。
- **本機**：`dart format`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全綠；Windows 上跑 `install_search_play_test.dart`、`toast_layering_test.dart`。
- **實機**（重播／測試插件）：
  - Windows：
    - 從播放列開播放頁；
    - 三種寬度；
    - Esc 關閉；
    - 速度選單；
    - 在播放頁上觸發一個提示：佇列加入測試插件 `preview` 關鍵字的曲目，開著播放頁按播放，「跳過試聽片段」開著時會跳過並提示。確認提示可見且貼底。
  - Android：
    - 手機版點封面切換歌詞；
    - 返回鍵只關播放頁；
    - 兩平台都跑 `toast_layering_test.dart`。

## 範圍外

- 佇列的編輯、手機的佇列底部面板、自動捲到目前歌曲（PR 18b）。
- 右側「正在播放」面板與它的開關（PR 19）。
- 歌詞內容（M7）。
