# `login` 契約、QR 登入、帳號區塊（M3 PR 8，FMP 端）

> 父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`。技術設計在父任務 `design.md` §4.3（`login` manifest 與匯出）、§4.8（`checks.json` 的 `login` 案例）、§6.3（登入期間 jar 不存 `Set-Cookie`）、§6.4（三種登入方式，這個 PR 只做 QR）、§6.6（登出）、§6.7（帳號頁）；ADR 0012、0029。執行清單在父任務 `implement.md`「8.」。疊在 PR 6（#227）之上。插件端（B 站、網易的 `login`）另開 fmp-plugins 的 PR；YouTube 的 `login` 隨 PR 9。本檔只列做什麼與驗收。

## 目標

使用者能在設定頁第一個區塊「帳號」以 QR 登入宣告 `qr` 的插件、看到帳號狀態、切換「以登入身分瀏覽與播放」、登出；宿主有完整的 `login` 契約供插件實作。

## 做什麼

1. 宿主：manifest 的 `login` 欄位（design §4.3 的形狀與驗證；M1 整個拒收的那段改掉）；`SourcePlugin` 的 `loginQrStart`、`loginQrPoll`、`loginVerify`、`loginRefresh`（能力與匯出一致才載入）；`FmpLoginCredentials` 等進 `d.ts` 與 shapes；`checks.json` 的 `login` 案例（`loginVerify`，標 `requiresLogin: true`）；`login*` 匯出執行期間該插件的 client 不把回應的 `Set-Cookie` 存進 jar；`loginVerify`／`loginRefresh` 呼叫前把傳入憑證的值登記到遮蔽。
2. `AccountService.login`：三種方式共用的「`loginVerify` 通過才寫入」（先憑證、後帳號列、再登記遮蔽；拋錯就什麼都不寫）；QR 流程（`qr_flutter` 4.1.0；2 秒輪詢以一次性 `Timer` 接力；`scanned`、`expired` 與「重新產生」；離開畫面停止）。
3. 帳號區塊（設定頁第一個區塊）：每個宣告 `login` 的已啟用插件一列；未登入時是「methods ∩ 平台能力」的登入按鈕（這個 PR 只有 QR 能用；`webView`、`cookie` 在 PR 9）；已登入時是頭像、名稱、狀態（正常／已失效／暫時無法讀取）、「以登入身分瀏覽與播放」開關（`automationRisk` 附說明）、登出（確認框）；已失效時多「重新登入」；離線照常可用。
4. `fmp-test`：假的 QR 登入（第二次輪詢 `done`）、`loginVerify`，寫進它的 README。
5. 三語言；`app/AGENTS.md`（§ 帳號、§ 插件的 `login`）與 spec；`toast_layering_test.dart` 加 QR 登入畫面（若是全螢幕路由）。

## 不做

- 網頁登入、貼上 cookie、清 WebView cookie（PR 9）；失效判定與刷新、最後刷新時間的顯示內容（PR 10，但列的欄位位置可先留）；B 站、網易、YouTube 插件的 `login` 實作（fmp-plugins 另開 PR）。

## 驗收

- [ ] manifest `login` 驗證（methods 含 `webView` 卻缺 `webView` 拒收等）；宣告 `login` 卻沒匯出 `loginVerify` 拒載。
- [ ] `account_service_test.dart`：`loginVerify` 拋錯時什麼都不寫；成功時先憑證後帳號列；QR 的 `expired`、`scanned`、離開畫面不再輪詢（`fakeAsync` 下沒有待執行的計時器）。
- [ ] jar 不存登入回應的 cookie：`login*` 執行期間回應的 `Set-Cookie` 不進 jar，結束後一般回應照常存。
- [ ] 登入後 `auth: 'never'` 與開關關閉的請求不帶憑證 cookie（以 `fmp-test` 的假 QR 走真的 `login*` 流程）。
- [ ] 帳號區塊的 widget 測試（methods ∩ 平台能力、已失效、暫時無法讀取、離線、登出確認、guideline 400／1000）。
- [ ] 驗證清單全綠。
- [ ] 實機（重播）：兩平台以 `fmp-test` 的假 QR 走完登入、開關、登出。真實（B 站、網易，擁有者自己掃 QR）在插件端 PR 合併後做。
