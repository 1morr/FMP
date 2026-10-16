# Mix 歌單

## 目標

M4 PR 11（上層 `implement.md` § 11、design §5.4、ADR 0033 §決定 1、ADR 0031 §決定 8、9）：匯入對話框貼上 Mix 網址（插件回 `mixSeed`）時建一張 `kind = mix` 的歌單；歌單卡與詳情可「Mix 播放」、改名、刪除。上層計畫已核准；本 PR 不需要新的擁有者決定。

## 需求

- **建立**：匯入對話框拿到 `ImportMixSeed` 時，呼叫該插件的 `mix(seed)` 一次（驗證種子並取 `MixBatch.title`），建一列 `playlists`：`kind = mix`、名稱＝回傳的標題、`mix_plugin_id`、`mix_seed_source_id`、`mix_seed_cid`（CHECK 已在 PR 1 建好）。不存曲目，不建 `playlist_remote`。成功後照匯入歌單的流程在音樂庫內開詳情；失敗與離線的提示照匯入的錯誤處理（第一次 `mix` 失敗就不建列）。`ImportMetadataOnly` 仍顯示「尚未支援」（PR 19）。
  - 同一個插件、同一個種子再貼一次：建新的一張（舊版行為，Mix 沒有遠端身分可對應）。
  - 插件呼叫放在 `lib/library/`（`PlaylistService` 或 importer，照現有分層：UI 不直接碰插件），repository 加建 Mix 列的方法。log：`Mix playlist created`（`pluginId`、`playlistId`）。
- **Mix 播放**：以歌單存的種子開始 Mix，取代佇列並進 `mix` 模式（ADR 0031 §決定 9）。控制器目前只有 `startMix(TrackInfo)`；改成 `MixSession.start` 以 `(pluginId, MixSeedQuery)` 開始，`PlaybackController` 加以種子開始的方法，`startMix(TrackInfo)` 委派給它（同一條路徑，不另寫一份）。UI 端照 `startMixFrom` 的錯誤提示寫一個以歌單開始的函式。
- **停用**：插件不在清單上（停用、移除、還沒載入）或沒宣告 `mix` 時，「Mix 播放」停用並顯示原因（照 `canStartMixProvider`）。
- **歌單卡**（音樂庫清單與格狀）：Mix 歌單的選單是「Mix 播放」、「編輯」、「刪除」（沒有加入佇列、隨機、刷新）。首頁卡片沒有選單（PR 4 的決定），點了開詳情。
- **詳情**：不列曲目。標頭顯示名稱、種類副標題（已有）、音源插件名；主要動作「Mix 播放」；顯示種子曲目：以曲目鍵（`mix_plugin_id`、`mix_seed_source_id`、`mix_seed_cid`）查 `tracks`，查到就顯示標題與作者（`TrackRow` 的樣式，點了不播放也行，照現有元件最簡單的方式），查不到只顯示 id。選單：編輯、刪除。
- **編輯**：Mix 只有名稱（沒有描述、封面、自動刷新）。刪除照本機歌單的確認。
- 字串三語言（en、zh-CN、zh-TW），跑 `dart run slang`。

## 驗收

- 測試：
  - 建立：`ImportMixSeed` → `mix` 被呼叫一次 → 一列 `kind = mix`、三欄正確、名稱是回傳標題；`mix` 丟錯時不建列、對話框顯示錯誤；離線提示。插件沒宣告 `mix` 時拿不到 `mixSeed` 由 PR 6 的測試守，不重複。
  - Mix 播放：從歌單開始取代佇列、`mix` 不為空、種子傳對；`startMix(TrackInfo)` 行為不變（既有測試照過）。
  - 詳情不列曲目；種子曲目查得到與查不到兩種顯示；停用（插件停用、沒宣告 `mix`）時按鈕停用並有原因。
  - 歌單卡選單的項目依種類不同；編輯對話框 Mix 只有名稱。
  - guideline：Mix 詳情頁（400、1000 寬，淺色深色）、Mix 的編輯對話框。
  - 雙向變異：至少「建立時不寫 `mix_seed_cid`」、「停用條件拿掉」各要讓測試紅；無關改名不紅。
- `dart format --output=none --set-exit-if-changed lib test integration_test`、`dart run slang`（無差異）、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全過（Windows 上兩個 `trackDetail` CRLF 失敗是既有的）。
- 文件：`app/AGENTS.md` § 介面的音樂庫／歌單詳情條目補 Mix；`.trellis/spec/app/ui/index.md` 若有需要。
- 實機（主對話做）：重播（Android）：`https://fmp.test/mix/<id>` 建一張 → Mix 播放 → 補歌一次。真實（YouTube 匿名，Android）：`mix:<videoId>` 建一張 → Mix 播放一首。

## 不做

- 曲目選單的「存成 Mix 歌單」（舊版也沒有）；曲目選單的「開始 Mix」不變。
- Mix 歌單的自動刷新或存曲目。
