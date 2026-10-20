# M4 PR 15：從帳號匯入電台（`libraryLiveRooms`）

上層：`.trellis/tasks/10-15-m4-library-sync`（implement.md § 15、design §4.4、§7.4、ADR 0032 §決定 3、ADR 0031、§17 第 13 條）。

## 目標

已登入的使用者可以把自己在平台上追蹤的直播間（B 站粉絲勳章牆）一次加進電台清單。

## 需求

- **契約**：PR 13 已加 `libraryLiveRooms` 的匯出規則（選填，需同時宣告 `libraryRead` 與 `live`）與 d.ts。本 PR 加 `SourcePlugin.libraryLiveRooms() → {rooms: LiveRoom[]}`、回傳值驗證（`LiveRoom` 照 live 能力既有的驗證；同一次回傳的房間以既有的鍵去重或拒收，照 `LiveRoom` 的現有規則）、ScriptSourcePlugin 接線。`checks.json` 不加（每能力一條，`libraryRead` 的那條已是 `libraryPlaylists`）。
- **入口**：帳號頁那張卡的「⋯」選單（沒有就加一個，與卡片其他動作一致）的「從帳號匯入電台」，條件是插件匯出 `libraryLiveRooms`、宣告 `live`、`CredentialState.active`；條件不成立不出現（ADR 0033）。
- **流程**：`libraryLiveRooms` → 逐一以 `RadioRepository.add` 寫入（重複回 `false`）→ 提示「新增 n 個，m 個已在電台清單」。不呼叫 `liveStatus`（`LiveRoom` 已有顯示資料）。失敗照 ADR 0013 提示（離線字樣）。進行中有進度指示、按鈕停用。
- **`fmp-test`**：匯出 `libraryLiveRooms`，登入後回五個直播間（未登入 `AuthRequired`）；README。
- **log**：tag `radio` 或既有的電台 tag，欄位插件 id 與計數，不放房間名稱。

## 驗收

- [x] 測試：只在匯出且宣告 `live`、已登入時出現；重複的計數；寫入 `radio_stations`；失敗提示。
- [x] 實機重播（Android）：`fmp-test` 匯入五個直播間，再匯入一次全部「已在清單」。
- [x] 實機真實（Windows，沿用登入）：B 站匯入一次；首頁電台區塊看得到。

## 不做

- YouTube、網易的直播間匯入（插件不匯出）。
