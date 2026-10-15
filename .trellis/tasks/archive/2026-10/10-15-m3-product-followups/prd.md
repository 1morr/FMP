# M3 留下的產品決定：搜尋重搜、Mix 循環、未開播人數（#260、#261、#262）

擁有者 2026-10-15 的決定，都照建議。

## #260 搜尋頁重搜統一用輸入框現在的文字

現況（`lib/ui/search/search_state.dart`）：
- `selectSource`、`selectMode`、`selectRoomFilter` 以 `state.keyword`（上次**送出**的關鍵字）重搜，
  所以按輸入框的「清除」（`search_page.dart` 只 `_text.clear()`）後換音源 chip，仍會送出舊關鍵字。
- 音源清單改變、直播音源被停用而退回「曲目」時（`build` 裡的 `ref.listen(searchSourcesProvider)`），完全不重搜。

要求：
1. `SearchState` 記住輸入框目前的文字（例如 `input`），輸入框改變時更新（頁面的 `TextField.onChanged` 與「清除」都要通知）。
   換到別的頁面再回來時輸入框顯示它（取代現在用 `keyword` 初始化）。
2. 換音源、換「曲目｜直播間」、換直播間篩選、自動退回曲目，四種情況一律：
   輸入框文字（trim 後）非空 → 以它搜尋第一頁；是空的 → 清掉結果回到初始畫面、不發請求。
3. 送出搜尋（Enter、重試）行為不變；`keyword` 仍是「上次送出的」，用於「找不到 X」之類的文字。

## #261 Mix 中停用循環「全部」

1. Mix 中循環只能「關」或「單曲」：`QueueModel.cycleLoopMode` 在 Mix 中依 off → one → off 輪轉。
2. `startMix` 時循環是「全部」就改成「關」；`restore` 恢復成 Mix 而循環是「全部」時也改成「關」（舊資料）。
   退出 Mix 後循環維持當時的值，不自動回到「全部」。
3. 介面：Mix 中循環鈕的 tooltip 與播放列「⋯」選單裡的循環項目說明 Mix 中沒有「全部」
   （照隨機鈕的 `shuffleInMixTooltip` 寫法，三種語言都加：zh-Hant、zh-Hans、en）。Ctrl+R 走同一個 `cycleLoopMode`。
4. ADR 0031 §決定 9 加一行「補充（2026-10-15，擁有者決定，#261）」。

## #262 未開播的直播間不顯示人數

搜尋頁直播間列（`search_page.dart` 約 610、688 行）只在 `room.status == LiveRoomStatus.live` 時顯示人數；
宿主統一處理，不改插件。電台頁沒有顯示人數，不用改。收聽中的直播版（`live_widgets.dart`）資料來自當下的 `liveStatus`，不改。

## 驗收

- 每項都有 widget 或單元測試，拿掉修正時會紅（變異寫在 PR 描述）。
  - #260：清除後換 chip 不發請求、結果清空；輸入新文字未送出就換 chip，以新文字搜尋；直播音源停用退回曲目時以輸入框文字重搜、空的就不發。
  - #261：Mix 中 cycle 只有 off/one；startMix、restore 把 all 改成 off；退出 Mix 後不回到 all。
  - #262：未開播、狀態未知的列沒有人數；開播中的有。
- `dart format`、`dart run slang`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全過。
- Android 模擬器（dev debug，重播 `fmp-test`）：三項各操作一次。

## 不做

- SMTC 的隨機、循環（#263，另一個 PR，Windows 要驗）。
- 不改插件。

## 結果

- 審查（opus）：
  - **中**：`search()` 把送出的文字寫回輸入框狀態，「清除 → 重試 → 換 chip」會把舊關鍵字送出，已改成 `search()` 不碰輸入框，並補測試。
  - 輸入框文字改放獨立的 `searchInputProvider`（沒有人 watch），打字不再讓整個搜尋頁連同結果重建；這和上面「`SearchState` 記住」的字面不同，屬實作細節。
  - 補了播放頁循環 tooltip、medium 寬度「⋯」選單的 Mix 循環測試；`app/AGENTS.md` 對齊。
- `flutter test` 3389 通過；變異：每項修正拿掉都會紅。
- Android 模擬器（dev debug）：
  - **真實（B 站匿名）**：App 重啟後預設選的是 Bilibili，沒先確認就搜了一次直播間 `test`：`search/type` 一次、`get_status_info_by_uids` 一次，共 2 個請求。順帶看到未開播的房間都沒有人數（#262）。
  - **重播（`fmp-test`）**：清除後換音源 → 回到初始畫面、沒有搜尋；打 `abc` 不送出就換到「曲目」→ 以 `abc` 搜尋（#260）。
    循環設「全部」後開始 Mix → 變成「關」，tooltip 寫「Mix 中沒有『全部』」，按兩下依序是「單曲」「關」（#261）。
- 留下的：自動退回曲目重搜失敗時，「搜尋失敗」的提示可能出現在設定頁（審查記下，擁有者沒定；搜尋頁在 `IndexedStack` 裡一直掛著）。
