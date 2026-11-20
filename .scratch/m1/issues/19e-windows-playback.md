# 19e: Windows 播放核心回歸（時間不前進、預載卡住、預載時崩潰）

Status: ready-for-agent
Blocked by: None
讀: `docs/development.md`〈Windows（`winpc`）〉〈實跑驅動〉〈其他已知怪癖〉（winpc 的 Dart 偶發當掉）；ARCHITECTURE〈測試策略〉；票 11、12、13、15 的 Comments（各自的「Windows 跳過」那一行）；事實 W5、W13、K26；spec〈共同規則〉

2026-11-20 票 20（M1 驗收）插票：winpc 恢復後第一次在 Windows 跑票 11 起的程式碼（`e13a1b5c` 加票 20 的幾個 commit），閘門的 Windows integration_test 有 5 個紅，Windows 實跑一開始播放、預載下一首就崩潰。票 11 起 Windows 全部跳過（2026-11-18 擁有者定），票 10 之後就沒在 Windows 跑過播放；票 10 的閘門在 `07e78ae0` 之前的程式碼全綠。

修復票的驗收包含回頭補勾被它卡住的票：票 20 的「Windows 補驗」。

## 現象（票 20 在 winpc 跑到的，2026-11-20）

- `search_and_play_test`：播放後畫面上的時間一直沒到 `0:01` 以後（第 128 行等不到 `0:0[1-9]`）。
- `stream_refresh_test`：同樣等不到時間前進（第 130 行）。
- `preload_test`：三條都紅。「預載後接著播、不再解析」等不到（第 162 行）；「預載的串流被 CDN 拒絕」那條，換到預載那條後 8 秒內沒開始（`Playback stalled: starting for over 8000 ms`），重新解析一次後同樣卡住；HLS 那條 did not complete。
- `parts_test`：整組分 P 播完回到佇列那首等不到（第 171 行）。
- `stream_duration_test`：兩條紅，第三條 did not complete。
- `app_test`、`queue_test` 綠。
- 實跑 `persist_run`（真的 B 站）：搜尋、播第 1 首，log 有 `mpv options set: {vid: no, prefetch-playlist: yes}` 與 `Preloaded the next track`，同一秒 `fmp.exe` 崩潰：事件記錄 1000，錯誤模組 `ucrtbase.dll`、例外 `0xc0000005`、位移 `0x74a92`。
- 同一天 20:52 winpc 又藍屏一次（0x3B，`c000001d`），硬體仍不穩（〈其他已知怪癖〉）；但上面幾個紅每次都在同一處，不像隨機的 VM 當掉，要分清。

## What to build

先寫出失效條件，不要先改：

- 最小的 repro：`search_and_play_test` 在 Windows 單跑（`run_task.sh fmptest C:/fmp-wt/test.ps1 -File integration_test/search_and_play_test.dart -ScratchData fmp-integration-test`），不聯網；印出 App 的 log 與 mpv 的 log。
- 找出是哪個改動弄壞的：票 10 之後動過 `lib/playback/backends/` 的 commit（`0b121de5` 失敗處理與 mpv 設定、`70baa144` 起的預載、`bfd495be`、`e976a336`、`c0efc808`、`42e6a463`）。可以在 winpc 上二分；每次建置約 1–6 分鐘。
- 查根因並修；崩潰與「時間不前進」若是兩件事，各自寫出 repro。查到的 mpv／media_kit 行為寫成事實（`docs/research/facts-*.md`，附來源）。
- 改 Windows 音訊後端時照 spec〈共同規則〉，macOS、iOS、Android 的閘門也要綠。
- 票 20 的 Windows 補驗清單（SMTC、各票的 Windows 實跑）照舊由票 20 做；這張只負責讓播放在 Windows 正常。

## 驗收

- [ ] 修之前的 repro 與根因寫在 Comments。
- [ ] 完整閘門不帶 `--skip-windows` 綠燈（Windows 八個 integration_test 都過）；winpc 偶發當掉照〈其他已知怪癖〉重跑能過不算程式問題。
- [ ] Windows 實跑（真的 B 站，照 spec〈共同規則〉的聯網規則）：搜尋並播放一首、按下一首換到預載那條，讀回畫面與 log，沒有崩潰。

## Comments
