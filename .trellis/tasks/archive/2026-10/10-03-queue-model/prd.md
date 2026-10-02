# 完整 `QueueModel`（M2 PR 9）

> 父任務：`.trellis/tasks/10-01-m2-full-playback`。技術設計在父任務 `design.md` §7.2（`QueueModel` 規則表、臨時播放、`detached` 與 `mix`／`live` 不做）、§3.1 末段（`TrackInfo` 與 `TrackSummary` 的轉換）；本檔只列做什麼與驗收。

## 目標

佇列規則一次寫完整、可單獨測：兩種模式、三種循環、位置式隨機、上一首 3 秒、10,000 上限、臨時播放的快照與回到佇列（ADR 0018 §決定 4、5）。控制器的新操作與 UI 入口在 PR 10。

## 做什麼

1. `lib/domain/track_info.dart`：`TrackInfo`（曲目鍵三段、曲名、上傳者、時長、`List<TrackArtwork>`）。`lib/plugins/` 加 `TrackSummary` → `TrackInfo` 的轉換（`domain/` 不 import `plugins/`）。
2. `lib/playback/queue_model.dart` 改寫成完整的純 Dart 模型（不碰資料庫與後端），`QueueState` 的項目是 `QueueEntry(TrackInfo)`；規則照 design §7.2 的表：
   - 模式 `queue`、`temporary`；
   - 循環 `off`／`all`／`one`，依序輪轉；
   - 位置式隨機：開（目前位置排第一）、關（從目前位置依序往下）、拖曳只移歌不動排列（拖進本輪已播的位置本輪不再播）、下一首播放（排在目前之後，連續加入依加入順序）、附加（隨機時插在剩下未播的隨機一處）、跳到某首、一輪結束（`all` 時重排、`off` 時停）；
   - 上一首：播放超過 3 秒回到開頭，否則往前一個（依排列）；播放位置由呼叫端傳入；
   - 上限 10,000：任何加入會超過就整批不加並回報（控制器在 PR 10 轉成 `QueueFull` 事件）；
   - 移除（移除目前這首時往下一首）、清空；
   - 臨時播放：進入時記快照（佇列位置、播放位置、是否在播），已在臨時播放時只換曲目、快照不變；回到佇列的觸發與計算（倒退秒數、「記住播放位置」）由模型提供純函數，設定值由呼叫端傳入；單曲循環時模式維持 `temporary`；在佇列點選某首結束臨時播放並丟掉快照；「下一首播放」插在快照位置之後。
   - 隨機用可注入的 `Random`（測試以固定種子）。
3. **讓 repo 保持可運作**：控制器與搜尋頁照 M1 的行為繼續用（點一首＝整份清單從那首開始、依序播放、`queueTracksProvider` 照舊），只做讓它們接上新模型所需的最小改動；新的控制器 API、臨時播放入口、刪 `queueTracksProvider` 在 PR 10。
4. 文件：`app/AGENTS.md` § 播放的佇列段改寫（拿掉「其他模式、隨機、上限在 M2」），每條寫閘門；需要時更新 `.trellis/spec/app/playback/`。

## 不做

- `mix`、`live`、Mix 修剪（M3）；`detached`（不做，design §7.2）。
- 控制器的新操作、UI 入口、`QueueFull` 提示（PR 10）。
- 持久化（PR 14）。

## 驗收

- [ ] 測試（ADR 0018 §如何確認的 `QueueModel` 部分，Mix 修剪除外）：
  - 隨機位置語意；拖進已播位置本輪不再播；連續「下一首播放」依加入順序；附加與跳到某首時其他未播的相對順序不變；
  - 一輪結束在 `all`／`off` 的行為；
  - 上一首 3 秒的兩側；
  - 臨時播放保留最早快照；臨時播放中單曲循環仍回到快照；點選佇列結束臨時播放；「下一首播放」在臨時播放中插在快照之後；
  - 上限：剛好 10,000 可、10,001 整批拒絕（含附加、下一首播放、取代）；
  - 以固定種子的隨機操作序列比對不變式：每個位置在一輪內恰好播一次。
- [ ] 既有 `playback_controller_test.dart`、`search_page_test.dart`、`install_search_play_test.dart` 不改期望仍通過（行為不變）。
- [ ] 驗證清單全綠（父任務 implement.md「每個 PR 的固定流程」第 5 步）。
- [ ] 實機：沒有使用者看得到的改動，不做。
