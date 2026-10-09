# 失效與刷新（M3 PR 10，FMP 端）

> 父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`。技術設計在父任務 `design.md` §6.5（失效與刷新）、§4.2（`credentialsAttached`）、§6.7（帳號頁的最後刷新時間與結果）；ADR 0012 §決定 5、ADR 0013 §決定 5（呈現表）、ADR 0016（離線不發背景請求）。執行清單在父任務 `implement.md`「10.」。疊在 PR 9（#229）之上。插件端（B 站 `loginRefresh` 與三個插件的「憑證無效」判定表）另開 fmp-plugins 的 PR。本檔只列做什麼與驗收。

## 目標

帶憑證的請求被判定憑證無效時，宣告 `refresh` 的插件自動刷新並重跑一次；不能刷新就標「已失效」並只提示一次附「登入」；宣告 `refresh: 'onStartup'` 的插件在啟動後第一次上線時刷新一次。

## 做什麼

1. `lib/plugins/accounts/` 的 `AccountGuard` 包住對插件的每次呼叫：`CredentialInvalid` 時同一插件單飛刷新（共用 `Future`）；有 `refresh` → `loginRefresh(目前憑證)`，拿到新憑證就寫入（`last_refresh_result = refreshed`、`last_refresh_at`）並重跑原呼叫一次；回 `null` 或拋錯 → 標 `invalidated`；沒宣告 `refresh` → 直接標 `invalidated`。
2. 標 `invalidated`：保留憑證、之後不帶（PR 7 已有）、提示一次「{音源}的登入已失效」附「登入」動作（開帳號頁該列）；重新登入回到 `active` 後下一次失效再提示；原呼叫的錯誤照常往上。網路錯誤、限流、風控不標失效。
3. 啟動刷新：宣告 `refresh: 'onStartup'` 且有憑證的插件，第一幀之後、網路狀態第一次是 `Online` 時呼叫一次 `loginRefresh`；由 `AccountService` 自己聽網路狀態，跑過就不再跑；不進排程器、不進啟動維護清單。結果寫 `last_refresh_at`／`last_refresh_result`（`refreshed`／`unchanged`／`failed`）。
4. 帳號區塊：顯示最後刷新時間與結果（宣告 `refresh` 時）。
5. `fmp-test`：關鍵字 `expired` 的搜尋在帶憑證時回 `CredentialInvalid`，刷新後成功；另有一個關鍵字讓刷新失敗（`expired-hard` 之類）以看到失效提示；`fmp-test` 宣告 `refresh: 'onStartup'`；README。
6. 三語言；`app/AGENTS.md`（§ 帳號）與 spec。

## 不做

- 插件端的判定表與 B 站刷新實作（fmp-plugins）；全面驗證（啟動時對每個帳號打帳號資訊 API）；搜尋 chip 的標記。
- 判定表的守法：照 PR 1 的先例以插件 repo 的 Node 測試守（輸入回應與 `credentialsAttached`），不修訂 ADR 0015 §決定 4（每能力一條契約案例）；design §6.5 閘門那句「契約 fixture」在這個 PR 加一行更正。

## 驗收

- [ ] design §6.5 的閘門：刷新後重跑的那次請求帶新憑證；三個並行呼叫失效只刷新一次；不支援刷新時標失效；只提示一次、重新登入後再提示；限流與網路錯誤不標失效；啟動刷新在 `noInterface` 時不發、變 `Online` 後發一次、只發一次。
- [ ] 帳號區塊顯示最後刷新時間與結果的 widget 測試（guideline 400／1000）。
- [ ] 驗證清單全綠。
- [ ] 實機（重播）：兩平台以 `fmp-test` 的 `expired` 看刷新後成功、`expired-hard` 看失效提示附「登入」；重啟後啟動刷新跑一次（帳號頁最後刷新時間更新）。真實（B 站）在插件端合併、擁有者登入後做。
