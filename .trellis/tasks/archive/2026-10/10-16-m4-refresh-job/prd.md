# M4 PR 10 `playlist-refresh` 工作與每張歌單的間隔

> M4 的 PR 10（`../10-15-m4-library-sync/implement.md` § 10）。設計在 `../10-15-m4-library-sync/design.md` §6.1、§5.2（取消）、§10.5；決定在 ADR 0017（排程器）與 M4 補充、ADR 0033 §決定 4。PR 8a 留下的（implement.md「留下的後續」）：排程傳 `RefreshTrigger(isCurrent: () => context.isCurrent)`、到期選擇不挑 `sourceGone`／`authRequired`、間隔改成不啟用時的取消。

## 做什麼

- `lib/library/playlist_refresh_job.dart`，`FmpApp` 常駐（照 `RadioStatusJobs`）：登記一次 `SchedulerJob(id: 'playlist-refresh', pluginId: null, interval: 30 分, run:)`。
- 每次執行：讀到期的歌單（`status = active`、`refresh_interval_hours` 不為空、插件在清單上且啟用、`last_refreshed_at` 為空或已過間隔），依 `last_refreshed_at` 由舊到新逐張 `PlaylistRefresher.refresh(trigger: RefreshTrigger(isCurrent: () => context.isCurrent))`。單張失敗只寫那張的狀態、繼續下一張；到期的全部失敗才丟錯讓排程器退避；沒有到期的是成功。失敗的那張不寫 `last_refreshed_at`。
- **取消**：間隔改成不啟用、插件停用或移除時，進行中的那張由刷新器取消（照 design §5.2 的過期檢查；最小的介面）。
- **編輯對話框**（匯入歌單）：自動刷新間隔（1／6／12／24／48／72／168 小時或不啟用），寫 `playlist_remote.refresh_interval_hours`。
- `app/AGENTS.md` § 排程器的工作清單加它；§ 音樂庫。

## 驗收

- 測試（排程器的假時鐘）：到期條件各項、由舊到新、單張失敗繼續、全部失敗退避、沒有到期算成功、失敗的那張不寫 `last_refreshed_at`、`sourceGone`／`authRequired` 不選、取消（間隔改不啟用、插件停用）；編輯對話框寫入間隔；guideline 加有間隔欄位的對話框。
- `dart format`、`dart run slang`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全過。
- 實機（主對話做，重播，Android 與 Windows 各一次）：匯入 `fmp-test` 的 `pl-grow` → 把 `last_refreshed_at` 改成 25 小時前 → 重啟 → log 有 `Playlist refresh finished`；切到背景（Android）或最小化（Windows）時沒有工作執行。
