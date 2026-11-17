# 06b: iOS 播 B 站時時長錯成 33:10、切歌時短暫顯示上一首的時長

Status: ready-for-agent
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

- [ ] 兩個問題各有 repro，修之前紅、修之後綠；根因寫在 Comments，查不到的寫明為什麼。
- [ ] 四平台實跑同一首：迷你播放器與播放膠囊的時長和曲目時長一致（差 1 秒內）；連續切兩首時沒有顯示上一首的時長；iOS 拖到 33 分之後能繼續播。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
根因（2026-11-18）：B 站 CDN 偶爾把長的音訊下載連線中途關掉（curl 一次斷在 25 MB、另一次 225 MB 傳完）；AVPlayer（macOS 27、iOS 27 模擬器）把斷線前接得上的那段當整個檔，`duration` 與可 seek 範圍變短（看過 33:10、20:53、6:00），播到那裡發 `DidPlayToEnd`、seek 超過也直接結束，重開同網址也一樣。檔案本身完整（mvhd、mehd、sidx 都對，`scripts/experiments/bilibili-m4s-duration/`）。ExoPlayer、mpv 會續傳。
切歌閃舊時長：後端層測不到（macOS 換串流期間沒發舊長度，`stream_duration_test` 第一條修前就綠）；實跑看到的是載入中後端報 0（AVPlayer 的 NaN）讓畫面顯示 `0:00` 長達 38 秒。播放層顯示規則還沒改（見下面的待做）。
決定：Apple 平台用 byte-range HLS 包裝修，不改用 mpv、不只修顯示（使用者同意）
決定：ADR 0040 與 ADR 0039 的 segmentBase 補充照草稿寫入（使用者同意）；草稿在 session 暫存目錄，下一個 session 照 ADR 決定段重寫入 `docs/adr/0040-apple-plays-fmp4-through-hls.md`
決定：App 還沒有拖進度的 UI，驗收改由實跑情境經播放層 seek（Agent 定）
決定：後端介面加最小的 `seek`（兩個實作與 fake），不做進度條（Agent 定）
進度（WIP commit）：已做 domain `SegmentBase`／`ByteRange`、宿主解析、bilibili 插件填 segmentBase、契約期望與重錄 fixture、`playback/backends/hls/`（sidx 解析、清單、本機伺服器）、just_audio 後端接 HLS、`createAudioBackend(log)`、`seek`、測試支援（`FragmentedMp4`、`LocalAudioServer` 斷線）。`integration_test/stream_duration_test.dart` 斷線那條：macOS、iOS 沒 HLS 紅（長度 0:35、3:50），接上 HLS 綠。
待做：(1) 播放層顯示規則（後端長度只在這次載入完成後、>0、且與曲目時長差在 max(3 s, 1%) 內才用，否則用曲目時長；搜尋頁面板改用 effectiveDuration）＋單元測試（33:10、載入中報 0、遲到的舊長度三條，修前紅）並記成決定；(2) Android 模擬器、winpc 跑 stream_duration_test（這次 Android 模擬器沒開）；(3) `duration_run.dart` 加經 audioBackendProvider seek 到 33:20 並讀回位置前進，四平台實跑（含 01-launch）；(4) 寫 ADR 0040、0039 小節、事實 M14、M15、F24、M5（`application/octet-stream` 實測打不開）、macOS Release entitlements 加 network.server；(5) code-review、完整閘門、Session 紀錄與變更行。
