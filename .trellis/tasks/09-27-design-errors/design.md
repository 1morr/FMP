# 設計：統一錯誤模型

採用的慣例：Dart sealed class 做窮舉分類；NewPipe `ErrorInfo` 的欄位（可重試、是否可回報、給使用者的訊息）與
「同一錯誤依情境升級呈現」；AWS〈Exponential Backoff And Jitter〉的全抖動退避；Riverpod 3 以 `AsyncValue` 承接錯誤。

## 1. 分類

一個 sealed 型別 `AppError`，擁有者指定的 8 類，加上 1 類給「預期外」：

| 類別 | 什麼時候 | 例子 |
|---|---|---|
| `NetworkError` | 連線、逾時、DNS、TLS、離線 | dio 的連線錯誤 |
| `RateLimited` | 音源明確表示請求太頻繁 | HTTP 429、網易 -460（依音源判定表） |
| `AuthRequired` | 需要登入的請求但未登入 | `AuthRequirement.required`（ADR 0012） |
| `CredentialInvalid` | 帶了憑證但音源判定無效 | B 站 -101（依音源判定表） |
| `VerificationRequired` | 風控，需要人工驗證或換身分 | B 站 -352／-412、YouTube「確認你不是機器人」 |
| `Unavailable` | 內容存在但不能播，附原因：地區、版權、會員、年齡、只有試聽 | 網易 VIP 歌、YouTube 地區限制 |
| `NotFound` | 內容不存在或已刪除、私人 | 影片下架 |
| `ParseError` | 回應格式不符合預期（多半是音源改版） | JSON 欄位消失 |
| `Unsupported` | 音源或平台沒有這個能力 | 理論上 UI 會先依能力隱藏；出現即是 bug |
| `UnexpectedError` | 以上都不是（包住未知例外） | — |

YouTube 的機器人驗證歸在 `VerificationRequired`，不歸 `CredentialInvalid`：它不代表帳號壞了，常見解法是登入或貼上 cookie、換網路（NewPipeExtractor 也把它獨立成專屬例外）。

**共同欄位**：音源 id（可空）、`retryable`、`retryAfter`（可空）、給使用者的 i18n 訊息 key 與參數、`expected`（預期內的錯誤不算 bug，不附「回報」）、原始 error 與 stackTrace（只進 log，經 ADR 0011 遮蔽）、對應的網路紀錄 id。

## 2. 在哪裡轉換

- **網路層**（ADR 0012 的錯誤對應攔截器）：把 dio 的傳輸層錯誤轉成 `NetworkError`。
- **每個音源在自己的目錄裡**有一份對應表：該音源的 HTTP 狀態與錯誤碼 → `AppError`，包含 ADR 0012 要求的「憑證無效」判定。
- **音源邊界以上**（service、Riverpod、UI）看不到 `DioException` 與音源私有的錯誤碼，只看 `AppError`。
- 未知例外在音源邊界包成 `UnexpectedError`，保留原始 error 與 stack。
- 測試：每個音源用錄下來的錯誤回應 fixture，逐一斷言對應到的類別（契約測試，第 8 項）。

## 3. 錯誤怎麼傳

- 音源與 service 丟出 `AppError`；Riverpod provider 以 `AsyncValue.error` 承接，UI 用 exhaustive `switch` 呈現。
  （Flutter 官方指南用 `Result` 型別，但那是為 `ChangeNotifier` 架構設計；本專案用 Riverpod，`AsyncValue` 已扮演同樣角色，不再包一層。）
- 使用者動作（播放、加入歌單、登入…）由呼叫端捕捉 `AppError` 交給呈現層（第 3 項 Toast）。
- 禁止空的 `catch` 與吞掉錯誤只回預設值；需要忽略時必須記 log 並註明原因（lint，第 8 項）。
- 所有錯誤被處理時經 log 門面寫入（ADR 0011），成為錯誤歷史。

## 4. 重試、退避、限流：只有一層

- **Riverpod 3 的自動重試全域關閉**（`ProviderScope(retry: (_, _) => null)`），避免與網路層重試相乘。
- **重試只在網路層做**，策略由音源宣告、網路層統一執行：
  - 只重試冪等請求（GET）；POST 等寫入不自動重試。
  - 只重試 `NetworkError`、`RateLimited`，以及音源標為可重試的其他錯誤。
  - 指數退避＋全抖動；尊重 `Retry-After`；次數上限由音源宣告（預設 2 次）。
  - 每個音源一個併發上限與最小請求間隔（`pool` 套件做併發；最小間隔自寫），用來預防限流，而不只是事後重試。
- **憑證刷新後重送**：ADR 0012 的單飛刷新，與上面的重試分開計算。
- **播放層的恢復**（連續失敗幾首就停、何時換音質、何時跳過）在第 13 項定。
- 使用者手動重試：UI 的「重試」按鈕 invalidate 對應 provider。

## 5. 使用者看到什麼

| 類別 | 自動處理 | 使用者看到 | log 層級 |
|---|---|---|---|
| `NetworkError` | 網路層重試 | 動作失敗時 toast「網路連線失敗」；持續離線時顯示離線狀態（第 16、17 項） | warning |
| `RateLimited` | 網路層退避重試 | 仍失敗才 toast「{音源} 請求太頻繁，請稍後再試」 | warning |
| `AuthRequired` | 不重試 | 提示並附「登入」按鈕 | info |
| `CredentialInvalid` | 刷新一次（ADR 0012） | 刷新失敗：提示一次需要重新登入 | warning |
| `VerificationRequired` | 不重試 | toast 附建議：登入（B 站、YouTube）、或貼上 cookie、或稍後再試 | warning |
| `Unavailable` | 不重試 | 在曲目上標示原因（地區／會員／年齡／只有試聽）；播放時跳過並提示 | info |
| `NotFound` | 不重試 | 在曲目上標示「已失效」；播放時跳過並提示 | info |
| `ParseError` | 不重試 | toast「{音源} 的回應格式改變，可能需要更新 App」 | error（可回報） |
| `Unsupported` | — | 不應出現；出現時 toast 通用訊息 | error（bug） |
| `UnexpectedError` | 不重試 | toast 通用訊息 | error（可回報） |

- **訊息一律來自 i18n key**，永遠不把 `e.toString()` 或伺服器原文顯示給使用者（修正 G4）；原文只進 log。
- **部分成功**：多音源搜尋、批次匯入等，成功的照常顯示，失敗的音源或項目單獨標示，不再被成功的結果蓋掉（修正 G4）。
- **背景工作**（自動刷新、排行抓取）不跳 toast，只記錄並在對應畫面顯示狀態（第 16 項）。
- **同一錯誤去重**：同一類別＋同一音源在短時間內只提示一次（Finamp 的做法）。
- 開發者模式下每個錯誤 toast 有「詳細」（第 3 項）。

## 6. 不做（功能凍結，記入第 20 項待辦）

- B 站 -352 的 geetest 驗證碼互動（PiliPlus 有做）：新功能；現階段以「登入」作為主要建議（舊版實測帶登入時 -352 為 0/40，`lib/data/models/settings.dart:70-75`）。
