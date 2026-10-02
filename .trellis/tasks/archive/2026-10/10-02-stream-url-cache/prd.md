# 串流網址快取（M2 PR 7）

> 父任務：`.trellis/tasks/10-01-m2-full-playback`。技術設計在父任務 `design.md` §7.4 的前兩段（網址快取、期限邊界）；音質與格式偏好是 PR 8。本檔只列做什麼與驗收。

## 目標

同一首歌在網址到期前不再重複解析：預取（前瞻）解析過的，到播放時直接用；正在解析的，第二個呼叫共用同一個請求（ADR 0016 §決定 5）。

## 做什麼

1. `StreamResolver`（`lib/playback/stream_resolver.dart`）內的記憶體網址快取：
   - 鍵＝曲目鍵（已含分 P）＋音質＋格式偏好；PR 8 之前偏好固定，鍵先放固定值，形狀照 design 留給 PR 8 接；
   - LRU 64 筆；
   - 有效到 `expiresAt − 5 分鐘`；`expiresAt` 為空時解析後 5 分鐘內有效；時間經 `clock`；
   - 播放失敗（開不起來、中斷、HTTP 拒絕）作廢那一筆，由控制器或 session 在對應的失敗路徑呼叫；
   - 同一個鍵正在解析時，第二個呼叫拿同一個 `Future`；解析失敗不留在快取裡。
2. 期限邊界統一：`ResolvedStream.expiryMargin` 的 30 秒改成同一個 5 分鐘常數；控制器的前瞻刷新與交接檢查跟著改（design §7.4 第三段的理由）。
3. 文件：`app/AGENTS.md` § 播放加網址快取的契約（鍵、有效期、作廢時機、共用進行中請求），每條寫閘門；需要時更新 `.trellis/spec/app/playback/`。

## 不做

- 音質與格式偏好的設定、`StreamRequest.quality`（PR 8）。
- 下載不走快取（M6）。
- 前瞻開不起來的後端契約案例（PR 11）。

## 驗收

- [ ] 測試（ADR 0016 §如何確認，假插件、不連網）：
  - 安全邊界（剛好在 `expiresAt − 5 分鐘` 前後）、`expiresAt` 為空、作廢、上限 64 的淘汰（LRU 順序）；
  - **預取後播放只解析一次**；
  - 前瞻解析慢於目前這首結束時只解析一次（M1 follow-up 4 的後半）；
  - 解析失敗不進快取，下次重新解析；
  - 既有的 `expiry` 群組改成 5 分鐘。
- [ ] 驗證清單全綠（父任務 implement.md「每個 PR 的固定流程」第 5 步）；動到播放核心，照 `app/AGENTS.md` 在 Windows 跑 `integration_test/install_search_play_test.dart`。
- [ ] 實機（主對話做；重播）：Windows 與 Android 從搜尋頁連播兩首，log 的 `resolveStream` 次數＝曲目數。
