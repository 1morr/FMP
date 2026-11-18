# 06b: iOS 播 B 站時時長錯成 33:10、切歌時短暫顯示上一首的時長

Status: done
Blocked by: None
讀: `app/lib/playback/playback.dart`（`effectiveDuration`、取後端時長那段）與 `app/lib/playback/backends/`；事實 M5、M11；票 06、08、08b 的 Comments（時長那幾行）；`docs/development.md`〈實跑驅動〉；spec〈共同規則〉

2026-11-18 協調者插票（擁有者同意）：發現兩次。
- 票 08b 實跑時，iOS 模擬器播 B 站搜「lofi」的第一首（【Lofi｜梦核｜蓝调治愈】…，包包不理狗子），迷你播放器與搜尋頁的播放面板都顯示 `0:00 / 33:10`。同一首在佇列頁與搜尋結果是 59:33，macOS、Android、Windows 播放時是 59:32。那次串流是 mp4a.40.2、174 kbps 的 `.m4s`。
- 票 08 實跑時，macOS 切到新曲目後，播放膠囊短暫顯示上一首的時長。

修復票的驗收包含回頭補勾被它卡住的票：沒有。

## What to build

先寫出失效條件，分清下面兩件事各是什麼情況，各做成修之前會紅的 repro：
- 只是顯示錯：後端回報的時長錯，或 `effectiveDuration` 取錯來源。
- iOS 真的只播到 33 分左右就停或跳下一首：拖到 33 分附近實測，或用本機假 CDN 造一樣的檔。

切歌時短暫顯示上一首時長，查清是後端還沒回報新時長時沿用了舊值，還是畫面沒跟著換曲目。

- 修根因。顯示的時長在後端回報可信的值之前用曲目自己的時長；「可信」怎麼判斷寫成一條決定。
- 查到的 AVPlayer（或 just_audio）行為補成事實，或者更新 M5、M11。
- 實跑用票 08b 的實跑驅動，不搶游標。

## 驗收

- [x] 兩個問題各有 repro，修之前紅、修之後綠；根因寫在 Comments，查不到的寫明為什麼。
- [x] 四平台實跑同一首：迷你播放器與播放膠囊的時長和曲目時長一致（差 1 秒內）；連續切兩首時沒有顯示上一首的時長；iOS 拖到 33 分之後能繼續播。
- [x] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
根因（2026-11-18）：B 站 CDN 偶爾把長的音訊下載連線中途關掉（curl 一次斷在 25 MB、另一次 225 MB 傳完，事實 F24）；AVPlayer（macOS 27、iOS 27 模擬器）把斷線前接得上的那段當整個檔，`duration` 與可 seek 範圍變短（看過 33:10、20:53、6:00），播到那裡發 `DidPlayToEnd`、seek 超過也直接結束，重開同網址也一樣（事實 M14）。所以「只是顯示錯」與「真的只播到 33 分」兩者都是：後端報的長度錯，而且真的會提早結束。檔案本身完整（mvhd、mehd、sidx 都對，`scripts/experiments/bilibili-m4s-duration/`）。ExoPlayer、mpv 會續傳，Android、Windows 不受影響。
切歌閃上一首時長：沒重現。後端層換串流期間不發舊長度（`stream_duration_test` 第一條修前就綠），四平台實跑三次切歌的狀態流水帳也沒有；票 08 那次的截圖沒留，兩個假設都排除不了。實跑看到的是載入中後端報 0（AVPlayer 的 NaN）讓畫面顯示 `0:00`，最長 38 秒。`playback_test` 的「遲到的舊長度」是照可能的機制寫的防禦性測試（修前紅），不是重現。
修法：Apple 平台把有 `segmentBase` 的串流包成 byte-range HLS（ADR 0040、事實 M15）；顯示的時長在後端長度可信前用曲目自己的時長。
Repro：`integration_test/stream_duration_test.dart` 的斷線那條，合成 1 小時檔、每個回應 256 KB 就斷：macOS、iOS 拿掉 HLS 時紅（長度 0:35、3:50），接上綠；Android 綠。顯示：`playback_test`〈the shown length〉三條（33:10、載入中報 0、遲到的舊長度）與 `search_playback_test` 的面板那條修前紅、修後綠。退回直接播：拿掉 warning callback 時紅。
實跑（2026-11-18，`integration_test/real_run/duration_run.dart`，每平台匿名搜一次「lofi」、播三首，截圖含啟動後不動視窗的 01-launch）：四平台都 `All tests passed`，讀回一致：第一首 `0:06 / 59:32`（曲目 59:33）、seek 到 33:20 後 `33:28 / 59:32` 播放中、第二首 `0:06 / 3:08:27`、第三首 `0:06 / 3:13:36`；情境比對迷你播放器或播放膠囊畫出的長度與曲目時長差 1 秒內，切歌全程沒出現上一首的長度；Apple 平台 log 沒有退回直接播的 warning。iOS、macOS 在加了畫面文字比對後再跑一次，也綠。
順帶觀察：走 HLS 後切到 3 小時長片約 8 秒開始播，直接播時開頭卡過 15–38 秒（看門狗警告）。沒量化，留給票 12（預載與切歌延遲）。
發現：第一輪 Windows 實跑的 6 張截圖全是白圖（`shot.ps1` 回報 `printwindow=True`），讀回的文字卻正常，情境照樣綠。查到 winpc 的主控台是「使用中」、沒有 LogonUI（沒鎖定），螢幕閒置一小時就關（AC 3600 秒），所以是螢幕睡著。協調者要求後改了兩處：`test.ps1 -RealRunDir` 跑情境期間呼叫 `SetThreadExecutionState(ES_CONTINUOUS|ES_SYSTEM_REQUIRED|ES_DISPLAY_REQUIRED)`、跑完還原；`real_run.dart` 遇到幾乎同一色的截圖就判失敗（`tool/src/blank_screenshot.dart`，舊的白圖判成「only 2 colours」）。重跑前擁有者先把螢幕叫醒，所以這次只驗到呼叫成功、沒驗到它能叫醒已睡著的螢幕。重跑 Windows 綠、6 張截圖都是正常畫面（01-launch 首頁、04-seek `33:28 / 59:32`）；這輪第三首換成 49:00 那首（搜尋結果的順序變了），讀回 `0:06 / 49:00`。
決定：Apple 平台用 byte-range HLS 包裝修，不改用 mpv、不只修顯示（使用者同意）
決定：ADR 0040 與 ADR 0039 的 segmentBase 小節照草稿寫入（使用者同意）
決定：ADR 0040 補兩點：測試斷線門檻 256 KB、抓索引不經宿主網路層（使用者同意）
決定：App 還沒有拖進度的 UI，驗收改由實跑情境經播放層 seek（Agent 定）
決定：後端介面加最小的 `seek`（兩個實作與 fake），不做進度條；票 09 的 seek 驗收已先滿足（Agent 定）
決定：顯示的時長：後端的長度在這一首載入完成後才收，大於 0 且與曲目時長差在 max(3 秒, 1%) 內才用它，否則用曲目時長（Agent 定）
決定：搜尋頁的播放面板改用同一個顯示時長，不再直接讀後端的長度（Agent 定）
決定：segmentBase 由插件從音源拿（不靠網址猜），其他平台不看；抓索引失敗照舊直接播並寫 warning（Agent 定）
決定：索引用 dart:io 的 HttpClient 帶串流的 header 直接抓，和原生播放器一樣不經宿主網路層（Agent 定）
決定：整合測試用 12 KB 範本在記憶體合成約 8 MB 的 fMP4，不提交大檔；範本由 `make_fragment_template.sh` 產生（Agent 定）
決定：實跑情境為了驗收的「連續切兩首」播三首，比 spec 的「播一首」多兩首（Agent 定）
M2 提醒：做試聽時，串流要能標明自己是片段（例如 resolveStream 回報片段長度或存取等級），那時顯示規則改成片段用播放器的時長；現在不預先設計（協調者轉述）。
code-review 未處理：顯示規則容許 max(3 秒, 1%)，比驗收的「差 1 秒內」寬，59:33 的曲目後端差 35 秒內仍會採用；這次靠 HLS 給的長度準才在 1 秒內，規則已由協調者同意，不改。
code-review 未處理：實跑的 seek 經音訊後端（`audioBackendProvider`），`Playback` 還沒有 seek，由票 09 接。
code-review 未處理：`createAudioBackend` 的 `fetchRange` 參數只給測試用；`FakeAudioBackend` 記下的 `seek` 呼叫目前沒有測試讀。留著，票 09 用得到。
code-review 未處理：測試註解用「票 06b」指向文件，沿用 repo 既有寫法。
閘門：`dart run tool/check.dart` 完整版在 602dcfc9 一次全綠（exit=0）：quick 八步、四平台建置、macOS 原生測試、四平台各四個 integration_test（含新的 `stream_duration_test`，Windows 那條證實 mpv 會續傳）、插件打包。之後的 a1d80ea0 只改 `tool/`、`test/tool/`、`test.ps1` 實跑那段與文件，pre-commit 的 quick 閘門綠，`test.ps1` 那段由 Windows 重跑驗過。
決定：Windows 實跑期間用 `SetThreadExecutionState` 讓螢幕與系統保持醒著，跑完還原，不送滑鼠鍵盤輸入（Agent 定）
決定：實跑截圖不到 32 種顏色或 99.5% 是同一色就判失敗；門檻依實測（正常畫面最少 754 種，白圖 2 種）（Agent 定）
Session 紀錄：2026-11-18 查出 B 站 CDN 中途斷線讓 AVPlayer 截短長度並提早結束；Apple 平台改包成 byte-range HLS，顯示的時長改用可信的值，實跑工具拒收白圖；四平台實跑與完整閘門綠
變更：Fixed｜播放控制｜macOS、iOS 播 B 站長片時，時長不再偶爾變短（例如 59:33 顯示成 33:10），也不會播到一半就結束、跳下一首
變更：Fixed｜播放控制｜切歌與載入中時，迷你播放器、播放膠囊與搜尋頁的播放面板顯示曲目自己的時長，不再顯示 0:00 或不可信的長度
