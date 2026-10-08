# CredentialStore、帳號表、每音源設定、注入與 Cookie 合併（M3 PR 7）

> 父任務：`.trellis/tasks/10-08-m3-sources-accounts-devtools`。技術設計在父任務 `design.md` §3.1（`accounts`、`source_settings`）、§3.2（schema 版本與測試）、§4.2（`authHeaders`、`credentialsAttached`）、§4.3（`FmpLoginCredentials` 的形狀）、§6.1（`CredentialStore` 與平台層 secure storage）、§6.2（帳號表與啟動對齊）、§6.3（注入、Cookie 合併、遮蔽）、§6.6（登出、移除插件）、§7.4（移除順序）、§14（`flutter_secure_storage`）；ADR 0012、0029。執行清單在父任務 `implement.md`「7.」。本檔只列做什麼與驗收。

## 目標

宿主有唯一的憑證來源與帳號資料：憑證存在平台的 secure storage，請求依 `auth` 注入並與插件、cookie jar 的 cookie 合併，憑證的 cookie 不經 jar 送出；登出與移除插件清掉憑證。登入流程與帳號頁在 PR 8。

## 做什麼

1. 平台層 `lib/platform/secure_storage/`（`flutter_secure_storage` 11.x；`resetOnError: false`；鍵前綴與 `storageNamespace` 依 flavor），宣告 `PlatformCapabilities.secureStorage`。
2. schema v8：`accounts`、`source_settings`；repository 與 migration。
3. `lib/plugins/accounts/credential_store.dart`：讀取失敗的「暫時無法讀取」與 30 秒重讀、啟動對齊、遮蔽登記與取消；實作 `CredentialSource` 的 `credentialMaterial`、`credentialCookieNames`、`browseAsLoggedIn`（取代 `credentialHeaders`）；`fmp.credentials.get()` 回 `FmpLoginCredentials | null`。
4. 認證攔截器：Cookie 三方合併（憑證 > 插件 header > jar）、`authHeaders` 只在 attach；`HttpRequest.authHeaders`、`HttpResponse.credentialsAttached` 進 `d.ts` 與 shapes；cookie 管理併 jar 時跳過 header 已有的名稱與 `credentialCookieNames`。
5. 登出的資料面（`AccountService.logout`：憑證、帳號列、遮蔽、記憶體 jar；WebView 那一步在 PR 9）；移除插件加上憑證、`accounts`、`source_settings` 的步驟（design §7.4 的順序）。
6. 文件：`app/AGENTS.md` § 網路的認證段改寫、加 § 帳號；data／network／plugins／platform spec 的對應段落；每條寫閘門。

## 不做

- `login` manifest 與匯出、QR 登入、帳號頁、登入期間 jar 不存 `Set-Cookie`（PR 8）；WebView 登入與清 WebView cookie（PR 9）；失效與刷新（PR 10）；重設資料（PR 14）。

## 驗收

- [ ] `auth_test.dart`：三種 `AuthRequirement` × 未登入／已登入開關開／已登入開關關，以假的 `CredentialStore`（取代 `NoCredentials`）。
- [ ] 合併規則：三方同名、只有 jar、只有插件 header；`authHeaders` 只在 attach（omit、refuse 不出現）；已失效不帶。
- [ ] jar 送出時不含憑證名稱的 cookie（jar 先放同名 cookie，attach、omit、已失效都不從 jar 送出）；`auth: 'never'` 的請求在登入後不帶憑證 cookie。
- [ ] `HttpResponse.credentialsAttached` 只在 attach 時為真（`source_http_client_test.dart`）。
- [ ] `credential_store_test.dart`：讀取失敗不刪、30 秒後重讀、啟動對齊兩種、遮蔽登記（log 與網路紀錄不出現假值；短於 `Redactor.minimumSecretLength` 的值略過、不讓寫入失敗）。
- [ ] 登出後 `CredentialStore` 為空、之後的請求不帶憑證；移除插件後憑證、`accounts`、`source_settings` 都不在（`plugin_installer_test.dart` 的 removing 群組）。
- [ ] migration 三種；`platform_test.dart` 的 `secureStorage`；`type_definitions_test.dart`（d.ts 與 shapes 同步）。
- [ ] 驗證清單全綠（`app/AGENTS.md` § 驗證）。
- 實機：沒有使用者看得到的改動。`integration_test/secure_storage_test.dart`（寫假值、讀回、刪除、`deleteAll` 只刪自己的前綴）兩平台各跑一次；Windows 另確認 `.secure` 檔在 dev 的 application support 目錄、不在 prod 的。
