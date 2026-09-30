# 外殼、搜尋、設定與播放列（M1 PR 12b）

父任務：`../09-28-m1-skeleton-tracer`（implement「12.」的後半；擁有者決定 2）。在 12a（UI 基礎）合併之後開始。

依據：
- ADR 0024：§決定 3、5、6、8；
- ADR 0023：§決定 2 的位置與底部位移；
- ADR 0018：`PlaybackController` 是唯一播放入口；
- ADR 0027：實機驗證。

## 做什麼

1. **外殼**：「搜尋」「設定」兩個導覽項，依 `WindowClass` 切換樣式。
   - compact 用底部導覽列；medium、expanded 用 NavigationRail；large 以上用常駐導覽抽屜。
   - 右側「正在播放」面板、播放頁都是 M2，不做。
   - 外殼發佈「底部被佔用的高度」給 `ToastHost`。
2. **搜尋頁**：
   - 輸入框，加上已安裝且有 `search` 能力的插件 chip 列。chip 列可橫向捲動，兩端有漸層提示。
   - 結果列表：封面、曲名、上傳者、時長；支援分頁或「載入更多」。
   - 點一首就把這份結果列表交給 `PlaybackController`，從那一首開始依序播。
   - 錯誤經 `Toaster.error`；沒有插件、沒有結果、載入中都要有狀態畫面。
   - 數字用 `NumberFormat.compact`；M1 只有時長的話就不用。
3. **設定頁**：只有外觀組，包含主題模式、語言，都可選「跟隨系統」。
   - expanded 以上用 list-detail，左分組、右內容；M1 只有一組也照這個版面。
4. **播放列**：封面、曲名、上傳者、上一首、播放暫停、下一首、進度條（可拖動 seek）。
   - 三段寬度的控制項集合照 ADR 0024 §決定 5，只放 M1 有的功能。< 600 只有播放與下一首。
   - 曲名寬度不小於 160dp。
   - 狀態來自 `PlaybackController`：`Loading`、`Buffering` 顯示載入中；`Failed` 經 `Toaster`。
   - 點空白處開播放頁是 M2，M1 不接。
5. **快捷鍵**：只在 FMP 在前景、焦點不在輸入框時有效。
   - 空白鍵：播放暫停；
   - Ctrl+←／→：上一首、下一首；
   - Shift+←／→：倒轉、快轉 5 秒；
   - Ctrl+F：搜尋；
   - Ctrl+,：設定；
   - F6：在導覽、內容、播放列三區之間移動焦點。
   - 三區用 `FocusTraversalGroup`，Tab 只在區內移動。只有圖示的按鈕都要有 tooltip 與語意標籤，tooltip 附上按鍵。
6. **收尾**：
   - 身分頁移除，flavor 與資料目錄改記在 log 的啟動紀錄。
   - `--fmp-dev-playback` 入口刪除（PR 10 說好的），`--fmp-dev-plugin` 保留。
   - `verify-on-device` skill 與 `.trellis/spec/app/playback/index.md` 裡跟身分頁、dev 播放有關的步驟同步改掉，spec 改成指向 skill。
7. **golden**：用 `alchemist`，色塊字型，只做播放列三段寬度，守版面結構。

## 驗收

- [ ] `app/` 驗證清單全過。
- [ ] widget 測試：
  - 外殼在五個寬度的導覽樣式；
  - 淺色與深色主題下，搜尋、設定、播放列通過點擊區與對比度 guideline；
  - 快捷鍵：輸入框內空白鍵只輸入空格、F6 在三區移動、Ctrl+F 與 Ctrl+, 會導覽；
  - 播放列三段寬度的控制項集合，曲名 ≥ 160dp；
  - 點搜尋結果時，`PlaybackController` 收到整份清單與起點。
- [ ] 實機，照 `verify-on-device`：
  - Android 與 Windows 各一次，**搜尋 B 站並從一首開始連續播完兩首**，屬真實連線、最少操作。這是 M1 端到端的驗收。
  - 用測試插件驗 UI 與提示：提示在對話框之上也看得到。
  - Windows Narrator 開著時送出提示，無障礙樹不凍結（`msaa_tree.ps1` 的節點數）。
