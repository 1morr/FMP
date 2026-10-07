# M2 驗收紀錄（2026-10-08）

逐項對照本任務 `implement.md`「里程碑驗收」。證據類型：**實測**＝實機、執行時；**測試**＝單元／widget 測試。
兩平台都用 dev flavor 的 debug 建置（`main` 在 #218 之後）。

截圖只留在 session 暫存目錄，沒有放進來：B 站的封面與標題是第三方內容，有幾張是真人照片。

## 兩平台端到端

- **Windows 11**：縮放 150%，視窗 1920×1080 px，約 1265dp，是 large。
- **Android 模擬器**：`Medium_Phone`，直向 411dp，橫向 914dp。
- **模式**：
  - 第 1–11、14 步：**真實**，B 站插件 `bilibili 0.1.0`，來自 `1morr/fmp-plugins` 的 `33caa3a`；
  - 第 12、13 步：**重播**，測試插件 `fmp-test`。
- 開始前都清掉 dev 資料：Windows 刪 `userdata-dev/`，Android `pm clear com.personal.fmp.dev`。插件以 `--fmp-dev-plugin` 安裝。

### 真實請求（整段的網路紀錄，tag `network`）

| 平台 | 搜尋 | `nav` | `wbi/view` | `playurl` | 封面（`*.hdslb.com`） | 其他 |
|---|---|---|---|---|---|---|
| Windows | 1 | 1 | 8 | 8 | 21（含清除快取後重新下載的 4） | 無 |
| Android | 1 | 1 | 9 | 9 | 18（含清除快取後重新下載的 1） | 離線時的搜尋：1 次加 2 次重試，都沒有連到伺服器（`status` 為空） |

- 搜尋關鍵字兩平台都是 `piano`。
- 音訊串流由播放引擎直接連 CDN，不經 App 的 HTTP client，所以不在網路紀錄裡。
- 兩平台的 log 都沒有 `error` 級別的紀錄。

### 逐步

| 步驟 | Windows | Android |
|---|---|---|
| 1. 清資料、裝插件、啟動 | `Installed a plugin from the development entry {pluginId: bilibili}`；啟動時沒有請求 | 同左 |
| 2. 搜尋、臨時播放、加入四首（一首下一首播放） | 臨時播放第一次出聲 1145 ms；選單加入 3 首，「下一首播放」排在快照那首之後（第 1 位） | 臨時播放出聲 4080 ms（模擬器網路較慢）；「下一首播放」排在第 1 位 |
| 3. 播放列 | 下一首結束臨時播放（佇列原本是空的，停在 `Idle`）；上一首：播 7 秒後按回到 0:01（同一首），3 秒內按回到前一首（`Stream URL reused from cache`）；拖進度到 1:11:12；隨機、循環「全部」、音量 0.33、靜音與取消都寫進 `player_state` | 橫向（播放列 600–839 段）做：上一首兩種情況同左；拖進度到 1:13；隨機、循環從「⋯」；音量彈出滑桿 0.90、靜音與取消 |
| 4. 播放頁 | 三種寬度：medium 1100 px 單欄、large 1920 px 兩半、extraLarge 2600 px 三欄；佇列分頁拖最後一首到最上面（目前這首仍是目前這首，位置 2→3）；「⋯」移除一首（不提示）；詳細分頁（曲名、上傳者、時長、音源）；速度 1.5 換歌後仍勾 1.5；Esc 關閉 | 橫向 expanded：分頁、拖曳、移除、詳細；速度 1.5 換歌後仍勾 1.5，`dumpsys media_session` 的 `speed=1.5`；直向 compact：右上角「Queue」開面板，返回鍵第一次只關面板，第二次關播放頁 |
| 5. 右側面板 | 拖寬 412→479，收起與展開各寫一次 `panel_expanded`（另見 PR 19 的實機） | PR 19 已驗橫向 |
| 6. 系統媒體控制 | 經 `smtc_command.ps1` 只對 FMP 的工作階段送 pause／play／next／previous，狀態跟著變；`smtc_probe -AppFilter fmp`：曲名、上傳者、`THUMBNAIL=present`、Playing。**鍵盤的實體媒體鍵沒有按**：會送到別的 App（PR 16b 的決定） | 通知的媒體卡片：play、next、previous（播 4 秒後按，回到開頭）、pause 都有作用；拖卡片進度條到 168 秒。**鎖定畫面沒驗**：模擬器沒設螢幕鎖 |
| 7. 返回鍵與音訊中斷 | — | 「歷史」按返回回到「搜尋」，再按 App 退到背景、音樂繼續（`PLAYING`）；`adb emu gsm call` 時 `Audio interrupted; pausing`，掛斷後 `Audio interruption ended; resuming`。**另見發現 2、3** |
| 8. 輸出裝置 | 選單列出系統預設與三個裝置；選一個裝置 `Output device selected`、播放照常；再選回系統預設，偏好清空 | — |
| 9. 單曲循環、歷史、從歷史臨時播放 | 兩圈各一次 `Look-ahead handover {repeat: true}`（間隔 98–203 ms），歷史 +2，沒有請求；歷史頁「今天」10 筆對得上；從歷史點一首臨時播放，循環切回「全部」後播完：`snapshotPositionMs 74445 → resumeAtMs 64445, play: true` | 兩圈、歷史 +2、沒有請求；從歷史臨時播放結束：`48305 → 38305, play: true` |
| 10. 重開 | `Playback restored {queueLength 3, queueIndex 2, positionMs 94250, loop all, shuffle true}`、`shuffle_rank` 與音量不變；啟動時**沒有任何請求**，封面從快取讀 | `Playback restored {3, 2, 63049, all, true}`；啟動時沒有請求 |
| 11. 設定 | 「播放」組 8 列各改一次，`playback_settings` 每次都寫入（輸出裝置見第 8 步）；音質「低」：同一首 `bitrate` 96949 → 48322，重新解析一次；「網路」組用量 14.6 MB，清除後 0 B 並提示，換歌後封面重新下載 | 7 列各改一次（Android 沒有輸出裝置）；同一首 129662 → 67193；用量 2.2 MB → 0 B，換歌後封面重新下載 |
| 12. 離線 | **沒有實機斷網**：要停用網路卡或加防火牆規則，會影響擁有者的其他程式（擁有者決定略過）；以 widget 測試為證（`app_shell_test.dart` 的 `the offline banner`、`search_page_test.dart` 的 `offline`、`playback_controller_test.dart` 的 `recovery: offline (design §5.3)`） | 飛航模式：`Network status changed online → noInterface`，頂端「No network connection」；B 站搜尋以 `NetworkError` 失敗（重試 2 次，沒有送到伺服器）；`flaky` 播放：`action: waitForNetwork`，播放列「Waiting for the network」，沒有提示；關掉飛航模式：`Network is back; retrying`、出聲 |
| 13. 錯誤 | `fail`：搜尋頁「搜尋失敗」加重試，提示「FMP Test Plugin 請求太頻繁，請稍後再試」；佇列只有同一首 `unavailable` 兩次：第一次 `skip`、第二次 `stop`，只提示一則「連續 2 首無法播放，已停止播放」；`preview`：開著時跳過並提示原因，關著時照播、播放列標「試聽」、提示「只有試聽片段」 | 同左（英文介面） |
| 14. log 保留 | 輪替檔改成 8 天前與 6 天前，重開：`Deleted expired log files {count: 1}`，6 天前的留著 | 同左 |

## 發現

1. **暫停中回到佇列時進度條是臨時那首的**（Android 實測）：
   - 重現：佇列的歌暫停中，臨時播放另一首，按下一首結束。
   - 現象：log 是 `play: false`、位置 219049，`dumpsys` 的位置也對，但進度條顯示臨時那首的 0:29／1:06，按播放後才更正。
   - 處理：見本任務「里程碑驗收」的修正。
2. **Android 在「搜尋」按返回會結束 Activity**：
   - 現象：`wm_finish_activity … app-request`、`wm_destroy_activity`，不是 `app/AGENTS.md` 寫的 `moveTaskToBack`。
   - 播放中有服務留著引擎，所以看不出來。暫停時從桌面圖示再開，`main()` 會重跑，搜尋字與分頁都不見。重現兩次。
   - 處理：同上。
3. **背景續播時前景服務被拒**：來電結束、App 在背景續播時，`am_wtf … Background started FGS: Disallowed [callingPackage: com.personal.fmp.dev …]`。處理：同上。
4. **B 站插件的標題沒有解 HTML 實體**：標題原樣顯示 `&#x27;`。問題在 `1morr/fmp-plugins`，不在 `app/`，記為插件的後續。
5. **手機橫向開鍵盤時 `NavigationRail` 與搜尋頁溢出**：PR 19 已記，不是這次造成。這次的 log 沒有出現，因為步驟沒在橫向打字。

## ADR 的測試

逐項對照在 `research/m2-adr-tests.md`：41 個子項目都有自動測試，沒有「只有實機」或「找不到」的。該檔「需要主對話決定」一節的處理：

- **跨類別淘汰**：M2 只有 `image` 一個類別。淘汰查詢本來就不分類別（`app/AGENTS.md` § 快取庫已註明），接受；M6 加下載類別時補兩個類別的測試。
- **「連續下一首播放」**：指連續多次「下一首播放」（ADR 0018 §決定 5 的用語）。
- **「各頁離線狀態」**：指要網路的頁面。M2 只有搜尋頁要網路；設定頁與歷史頁是本機資料，不算。
- **M1 就有的 `RecoveryPolicy` 測試**：接受為證據，它們仍在、仍綠。
