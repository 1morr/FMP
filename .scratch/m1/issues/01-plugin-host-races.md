# 01: 插件宿主的兩個競態

Status: ready-for-agent
Blocked by: None
讀: architecture〈執行形態〉；M0 票 08 的 Comments；spec〈共同規則〉

## What to build

插件宿主在兩種情況下不再出錯：呼叫逾時、宿主關掉並重建引擎的同時又有新的呼叫進來；建引擎失敗一次後，下一次呼叫會重新建，不會一直拿到快取住的失敗 future。照 `AGENTS.md`，先寫出會紅的測試再修；寫不出就在 Comments 記下試過什麼、為什麼重現不了，不改程式。

## 驗收

- [ ] 逾時關引擎的競態：有一條改之前紅、改之後綠的測試（真的 fjs 引擎，`loadFjsForTests()`），或在 Comments 記下重現不了的理由。
- [ ] 建引擎失敗後重試：有一條改之前紅、改之後綠的測試，或在 Comments 記下重現不了的理由。
- [ ] 四平台實跑搜尋一次，結果照常。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
