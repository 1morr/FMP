# 11: 失敗處理、串流過期重新解析與看門狗

Status: ready-for-agent
Blocked by: 06、07
讀: brief §6、§13；architecture〈快取〉；事實 F5、I4、K4、K25、K26、W3、W4；M0 票 06、11 的 Comments；spec〈共同規則〉

## What to build

播放失敗時照 roadmap 定的順序處理：重新解析一次（含 CDN 回 403）→ 跳下一首 → 連續 3 首失敗就停止並用 Toast 提示（先降一級音質在 M2）。串流照 ARCHITECTURE〈快取〉在過期前重新解析：要用網址前（載入、暫停後繼續、seek）離過期不到 2 分鐘就先重新解析。看門狗：一直緩衝超過門檻就當成失敗走同一條路（M0 只記錄警告）。

M0 留下的一起做：
- media_kit 的 mpv 設定：`vid=no`、`prefetch-playlist=yes` 等（事實 K4）；`classifyMpvLog` 只把致命的 `cplayer` 錯誤當失敗。
- just_audio 接 `audio_session`。
- 未捕捉的錯誤（`FlutterError.onError`、`PlatformDispatcher.onError`）寫進 log。

## 驗收

- [ ] 失敗處理有測試：重新解析一次、403 重新解析、跳下一首、連續 3 首停止並提示、成功一首後計數歸零。
- [ ] 過期前重新解析有測試（假的時鐘）：離過期不到 2 分鐘時先解析；沒給有效期時不預先解析。
- [ ] 看門狗有測試：緩衝超過門檻走失敗處理。
- [ ] `classifyMpvLog` 只把致命錯誤當失敗，有測試；mpv 設定與 `audio_session` 已接上。
- [ ] 未捕捉的錯誤寫進 log，有測試。
- [ ] 四平台實跑：用壞掉的串流（假 CDN 回 403）觸發一次重新解析，讀回 log 與畫面。
- [ ] 補驗票 10 在 Windows 的缺口（2026-11-18 協調者加，擁有者定票 10 照現有結果收）：在這張票的最終 commit 上跑 `integration_test/real_run/persist_run.dart` 與 `restore_run.dart` 的 Windows 實跑（重開後停在原位、按播放從同一位置接著播），看截圖；完整閘門的 Windows `app_test`、`stream_duration_test` 綠。票 10 最後一輪這兩步在藍屏後連續紅在 MSB8066（Rust 編譯），先清 winpc 上 fjs 的 Rust 建置快取再判斷是不是程式的問題。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
