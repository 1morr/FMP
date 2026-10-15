# 實作順序

1. B：`lib/core/redaction/redactor.dart` 已知值迴圈的數字邊界；`test/core/redaction/redactor_test.dart`（design §7.2 的四個變異）。
2. A：`lib/plugins/accounts/credential_store.dart` 的 `_set`、`_Entry`、`_forget` 與四個呼叫點；
   `test/plugins/accounts/credential_store_test.dart`（design §7.1，含網路紀錄端到端）。
3. C：`lib/plugins/dev/account_scrub.dart`（新）與 `case_runner.dart` 的 `recordCase`、`accountLeaks`；
   `test/plugins/dev/dev_case_runs_test.dart` 與新的 scrub／accountLeaks 單元測試（design §7.3）。
4. 文件：ADR 0029、0011 的更正；`app/AGENTS.md` 三處；`.trellis/spec/app/plugins/index.md`。
5. 驗證：format、analyze、flutter test；三個插件的契約重播（`FMP_PLUGIN_DIR=../fmp-plugins/<id>`，看 `app/AGENTS.md` 怎麼跑）。

# 檢查

- opus `trellis-check` 審查。
- 變異：每條新規則一個違規變異會紅、一個無關改動維持綠，寫在測試裡或 PR 描述。

# 結果

- 實作（sonnet）照計畫完成；審查（opus）把 `redact()` 每次呼叫都 new 的全數字 RegExp 改成登記時編好。
- `flutter test` 3389 通過；三個插件的契約重播全綠（bilibili 8、netease 6、youtube 7），不用重錄；
  審查另以暫時測試把三個插件的 login fixture 經 `scrubAccount` 換值後重播，都通過且確實換了值。
- 實機：沒驗。`fmp-test` 不連網，也沒有會帶自己 id 的請求；改由 `credential_store_test.dart` 的網路紀錄端到端案例涵蓋。
  使用者看不到的改動，依 `app/AGENTS.md` § 驗證不需要 Android 實機。

# 留下的

1. **讀不到憑證時不登記 `userId`**（審查，低）：`_read` 的 catch 直接寫 `_Entry.unreadable()`，舊登記留到重啟（多遮），
   啟動就讀不到時帳號列的 `userId` 從不登記。要漏出得插件在不帶憑證的請求裡放自己的 id；沒有 repro，不修。
2. **`scrubAccount` 會多換**（審查，低，design §5.4 刻意的規則）：4 字元以上的名稱或非數字 id 以子字串比對，
   也會換到網址主機、JSON 鍵（名叫 `music` 時 `music.163.com` → `***.163.com`），不漏但 fixture 重播不了，
   `recordCase` 寫完不重播。16c（#254）錄完時會看到；真的碰到再改成避開主機與鍵，或寫完自動重播一次。
3. **頭像比對認不得 `//host/path` 與純文字 body 裡跳脫過的 `http:\/\/`**（審查，低，舊的 `contains` 寫法也一樣）。
   JSON 回應先解碼成 `jsonBody`，不受跳脫影響。
4. **App 內建名單寫著各音源的 cookie 名稱**（擁有者問到時說明）：`redaction_lists.dart` 從舊版搬來，理想上由插件 manifest 宣告；
   目前是多一層保險，要不要搬走另外決定。
