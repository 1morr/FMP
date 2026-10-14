# 宿主 `live` 能力（M3b PR 18a）

父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`（implement.md §18、design §4.4、§4.8、§5.3）。依據 ADR 0028、ADR 0014 §決定 4、ADR 0012 §決定 2。

**拆分**（主對話決定）：implement.md 的 PR 18 拆成四塊。
- **18a（這個）**：宿主的 `live` 能力與 `fmp-test` 的假實作。
- **18a-plugins**：`fmp-plugins` 的 B 站 `live`，在 `fmp-plugins` repo 另開 PR，fixture 由主對話以匿名真實連線錄。
- **18b**：`radio_stations`、電台服務、狀態工作、播放的 `live` 模式。
- **18c**：導覽、電台頁、搜尋頁的直播間模式、播放頁與播放列的直播版、設定列；兩平台實機。

這個 PR 沒有使用者看得到的改動：還沒有任何介面呼叫 `live`。

## 要做的

1. **`SourcePlugin` 加四個方法**（design §4.4 的表；沒宣告 `live` 時呼叫一律拋 `Unsupported`，與現有方法相同）
   - `liveSearch({keyword, page, status})`：`status` 可以是 `live`、`offline` 或 `null`。回傳 `{items: LiveRoom[], hasMore}`。
   - `liveRoomFromUrl({url})`：回傳 `{roomId}`；不是這個插件的網址時回 `null`。
   - `liveStatus({roomId})`：回傳 `LiveRoom`。**查詢失敗一律拋錯**，不能回 `offline`（D10）。
   - `resolveLive({roomId, formats})`：回傳 `StreamResult`，`expiresAt` 可以是空的。
   - `LiveRoom = {roomId, title, hostName?, artwork?: Artwork[], status: 'live'|'offline', online?: number}`。Dart 端的 DTO 放 `source_dto.dart`，比照現有 DTO 的寫法（形狀驗證、`Artwork` 沿用）。
2. **腳本插件的實作**
   - `script_source_plugin.dart`、worker 協定、`fmp-plugin.d.ts` 都要對應。
   - 回傳形狀不符時，與現有方法一樣轉成 `AppError`。
   - `live` 的四個呼叫都以 `userPreference` 發請求（ADR 0012 §決定 2 的「電台」）：跟著使用者的「以登入身分瀏覽」設定。更正（實作時）：`userPreference` 是插件在每個請求上標的 `auth`（預設 `never`），宿主不知道一次呼叫是不是直播；宿主決定的只是標了 `userPreference` 的請求帶不帶憑證（登入狀態與開關），插件分不出來。
   - manifest 宣告 `live` 時，載入檢查要求四個匯出都在，比照現有能力的檢查。
3. **`checks.json` 的 `live` 案例**（design §4.8）
   - 鍵是 `live`，案例呼叫 `liveStatus`，格式與 `search` 相同（`input` 加 `expect`）。
   - 要同步的地方：
     - `lib/plugins/health/checks.dart` 的解析、期望與形狀；
     - `FmpChecks` 型別與 `checks_test.dart`；
     - 契約執行器（`test/plugins/contract/`）；
     - 健康檢查；
     - App 內插件開發工具的案例執行（`lib/plugins/dev/case_runner.dart`）。
   - 「只收 `SourcePlugin` 已有方法的能力」照舊。
4. **`fmp-test` 的假實作**（`test/fixtures/plugins/test_plugin/`，不連網）
   - manifest 加 `live`；四個匯出。房間固定五個：

     | roomId | `liveStatus` | `resolveLive` | 用途 |
     |---|---|---|---|
     | `live-ok` | 開播中，人數固定 | 新的 60 秒音檔 `live.wav`（8 kHz 單聲道，越小越好） | 一般收聽 |
     | `live-offline` | 未開播 | 拋 `NotFound`（更正：插件丟的 `Unavailable` 必須有原因，現有原因都會誤導，例如「所在地區不提供」） | 未開播 |
     | `live-drop` | 一律開播中 | `tone.wav`（2 秒） | 提前結束後重連：每次重連又在 2 秒後結束 |
     | `live-ended` | 這個 isolate 第一次查是開播中，之後都是未開播 | `tone.wav` | 提前結束後問狀態，得到「直播已結束」 |
     | `live-broken` | 拋 `NetworkError` | 拋 `NetworkError` | 查詢失敗 |

   - `liveSearch`：
     - 任何關鍵字都回五個房間，依 `status` 篩選；`live-broken` 在搜尋結果裡標開播中。
     - `hasMore` 為假。
     - 關鍵字剛好是 `fail` 時，比照 `search` 以 `RateLimited` 失敗。
   - `liveRoomFromUrl`：
     - `https://fmp.test/live/<roomId>` 且是上面五個之一時，回 `roomId`；
     - 其他網址回 `null`。
   - `checks.json` 加一條 `live` 案例（`liveStatus` `live-ok`）。
   - README 寫上房間、網址格式與用途，供 18c 的實機驗證使用。
   - `pubspec.yaml` 的 dev asset 加上 `live.wav`。
5. **文件**：`app/AGENTS.md` § 插件，只補從程式碼查不到的契約（例如 D10「查詢失敗一律拋錯」）；`.trellis/spec/app/plugins/index.md` 視需要更新；父 implement.md §18 對應的項目打勾，拆分寫進「順序與相依」。

## 驗收（測試）

- `script_source_plugin` 的測試（以 `fmp-test` 或內嵌的測試腳本）：
  - 四個方法的正常回傳與形狀；
  - 形狀不符轉成 `AppError`；
  - 沒宣告 `live` 時拋 `Unsupported`；
  - 宣告 `live` 但少了匯出時拒絕載入；
  - `liveStatus` 拋錯時保持拋錯，不會變成 `offline`。
- `live` 的請求以 `userPreference` 發：比照現有測試 `search` 帶憑證與否的寫法。
- `checks.json`：
  - 解析 `live` 案例；
  - 契約測試以 `fmp-test` 重播 `live` 案例通過；
  - 健康檢查與插件開發工具的案例執行都能跑 `live` 案例。
- `type_definitions_test.dart`（或對應的形狀比對）涵蓋 `LiveRoom`。
- 每個新閘門都做雙向變異驗證並回報。
- 驗證清單：
  - `dart format --output=none --set-exit-if-changed lib test tool integration_test packages`
  - `dart analyze --fatal-infos`、`flutter analyze`
  - `flutter test`
  - 動到 lint 時，跑 `packages/fmp_lints` 的 `dart test` 與 `dart run tool/lint_sentinel.dart`

## 實機

- 沒有使用者看得到的改動，也沒動平台層與播放後端：不做實機。18c 的實測涵蓋。

## 不做

- B 站 `live`（18a-plugins）；電台、排程工作、播放的 `live` 模式（18b）；任何介面（18c）。
