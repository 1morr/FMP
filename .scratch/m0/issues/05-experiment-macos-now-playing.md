# 05: 實驗：macOS 的 Now Playing 接法

**What to build:** 決定 macOS 上的系統媒體控制怎麼接（brief §6、§17），讓 M1 能直接實作。候選至少包括 `audio_service` 在 macOS 的現況與自己用 platform channel 接 `MPNowPlayingInfoCenter`、`MPRemoteCommandCenter`。結論給擁有者確認後寫回 brief。

讀：brief §6、§17、事實 R4、M4、I5；plan §1.4、§2（macOS 的驗證怪癖）、§6 P2；spec〈共同規則〉的實驗規則

**Blocked by:** None (can start immediately)

**Status:** done

- [x] 實驗程式在 `scripts/experiments/` 底下，可重跑，附怎麼跑的說明。
- [x] 每個候選實測：顯示標題、封面、播放狀態與進度；接收播放、暫停、上一首、下一首、seek。macOS 27 不讓第三方讀 Now Playing，驗證方式（目測、系統 log）寫明。
- [x] 重驗事實 R4、M4；查到的新事實附來源寫進 brief §18。
- [x] 結論草稿（用哪個接法、它的限制）先給擁有者確認；確認後寫進 brief §6、brief §17 移除該條、plan §1.4、§6 P2 更新。

## Comments

- 結論（擁有者 2026-11-11 經 AskUserQuestion 確認）：macOS 也用 audio_service；自己的 platform channel 留作退路（plan §7）。macOS 27.0.1 上兩個候選表現相同：選單列「正在播放」顯示標題、歌手、封面、播放狀態與進度；面板的播放、暫停、上一首、下一首、seek 與鍵盤媒體鍵都收到；App 結束後清空。結果表與觀察在 `scripts/experiments/macos-now-playing/README.md`，每一步的原始結果在 `results/*.json`。
- 驗證方式：不讀 MediaRemote（macOS 15.4 起第三方讀不到），改用三份證據：輔助使用 API 讀選單列的「正在播放」面板（`np-panel.sh`）、App 自己記下收到的指令、`mediaremoted` 的系統 log（brief 事實 M9）。媒體鍵用 `mediakey.swift` 模擬，和實體鍵同一條路（系統 log 的來源是 `com.apple.rcd`）。AirPods 沒有硬體可測；它的播放／暫停走同一個 `togglePlayPauseCommand`，推測相同。
- 平台限制（兩個候選一樣）：App 沒出過聲就不是 Now Playing App（事實 M10）。brief §6 已寫：重啟後要先在 App 裡按播放，系統媒體控制才接到 FMP。
- 事實：重驗 M4（成立，附 pub 與原始碼出處）、R4（macOS 的部分改寫）；順手以原始碼證實 I5（iOS 不設 `playbackState`，#1139 的修正合併後沒發佈），拿掉【待重驗】但註明 iOS 上沒實測。新增 M9、M10、K18（原本寫 K17，合併 main 時和票 04 的 K17 撞號，改成 K18，引用一起改）。
- 共用裝置鎖：實驗的 `run.py`、`np-panel.sh`、`mediakey.sh` 自己拿共用裝置鎖（`lock_guard.sh`，照 `app/tool/winpc/lock_guard.sh`；`run.py` 開頭檢查、沒持有就經 `device_lock.dart` 重新執行自己），同一個 worktree 可重入。原因：它們送的 Escape 會打到最前面的 App，面板的按鈕與媒體鍵控制最近出過聲的 App，別的 worktree 的閘門可能正開著 dev App（票 11 之後 dev App 也會出聲）。本票最初照協調者當時的規則（實驗 App 用不同 bundle id、不碰共用裝置就不拿鎖）沒拿，協調者 2026-11-12 查證後改成要拿；實驗結果是改之前跑的，沒有重跑。驗證：讓另一個 worktree 的身分持鎖 8 秒，同時跑 `mediakey.sh`（不帶參數，拿到鎖後只印用法、不送按鍵），它印出持有者、等到鎖放掉才執行；在自己 worktree 的鎖裡跑則直接執行；`np-panel.sh close` 與 `run.py` 也都經鎖執行。完整閘門自己拿鎖。
- 意外：第一版 coldstart 情境只等 3 秒就對沒出過聲的 App 按媒體鍵，系統把指令轉給「音樂」App，把它叫起來，停在首次啟動的通知詢問對話框。背景點擊對那個對話框無效，所以直接結束行程（沒回答對話框，下次開啟時照舊出現）。之後 coldstart 改成等 25 秒、確定面板是這個 App 才按，不是就跳過（結果檔記成 `skipped`）。
- 讀面板偶爾剛點開時讀到空的：一次 channel basic 在 seek 後讀到空面板，驅動程式當掉，留下還在播的 App，污染了下一個情境。已改成讀到空的就重讀一次、情境中途出錯也關掉 App，結果檔全部用最終版的驅動程式重跑。
- 沒測：`flutter_media_session` 3.1.0（2026-11 才發佈，macOS 端沒設 `playbackState`）；channel 版的遠端封面（要自己下載，M1 若改用 channel 時再做）；暫停多久會被系統換掉；release 建置。
- code-review（c3dfd856 起）已處理：M10 的出處對不上提交的結果檔 → `run.py` 的系統 log 多收 `CanBeNowPlaying changed`、重跑 coldstart，「叫起音樂」改註明是手動觀察；coldstart 跳過的那步從 `ok: false` 改成 `null`；兩處註解寫 `run.sh` → `run.py`；「關掉 App」的判斷遇到讀面板失敗會假 OK → 排除錯誤並要求有標題；K18 的 `network.client` 改註明沒做拿掉的對照；remote-art 沒留 HTTP 證據 → 結果檔記下本機 server 收到的請求；`np-panel.sh` 讀錯視窗與全域 Escape 的限制寫進 README；`received()` 改名 `take_received()`、`step()` 的 tuple 參數改成 `moved_by`、toggle 的預期值收成一張表、`mediakey.swift` 的旗標只算一次。
- 第一個 commit 的 subject 原本 74 字元，超過 72：協調者要求後先建備份分支 `backup/t05-before-subject-20261112`，以 `git filter-branch --msg-filter` 改成 `feat(experiments): compare macos now playing via audio_service`（63 字元），保留中間的 merge commit，`git diff` 備份分支與 HEAD 為空。
- code-review 未處理（不做，理由）：#1139 的狀態在 I5、K18、plan §7 各寫一次（各自的上下文需要，plan §7 只是引用）。
