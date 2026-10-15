# M4 PR 12 帶憑證錄製與 `mutates`

> M4 的 PR 12（`../10-15-m4-library-sync/implement.md` § 12）。設計在 `../10-15-m4-library-sync/design.md` §4.7、§12；契約在 ADR 0032 §決定 7（已採納）、ADR 0015 §決定 4 的 M4 補充、§決定 7 的更正。

## 做什麼

- **`mutates`**：`PluginCheck.mutates`（`checkShapes` 收 `mutates`，`parseChecks` 只接受 `true`）。會改動遠端的案例：
  - `HealthCheck`：結果「略過：會改動遠端」，不呼叫插件；
  - `record_test.dart`（命令列錄製與冒煙）：略過並印出理由；
  - `DevCaseRuns`：真實與錄製模式略過並顯示同一句；重播照跑；
  - 契約測試（`contract_test.dart`）照常重播。
  - 本 PR 還沒有任何案例用到 `mutates`（第一個是 PR 14 的 `libraryWrite`）；`FmpChecks` 的 `libraryRead`／`libraryWrite` 鍵在各自的 PR 加。
- **隔離環境帶憑證**：`runIsolatedCase` 在真實與錄製模式、案例標 `requiresLogin` 時，把該插件 `CredentialStore` 已存的憑證放進隔離環境的記憶體憑證存放（注入照 ADR 0012 的規則走，網路紀錄記 `credentials: true`）；重播模式不放（fixture 本來就是遮過的）；沒登入照舊「略過」。`login` 案例的現有行為（已存憑證當 `loginVerify` 的輸入）不變。
- **換值擴大**：所有 `requiresLogin` 的案例，錄製寫檔前以該插件 `accounts` 列的 `userId`、`displayName`、頭像換掉錄到的流量（`scrubAccount`），再以 `accountLeaks` 檢查，換完仍看得到就不寫；`login` 案例的帳號仍來自結果。
- **健康檢查**同樣：`requiresLogin` 的非 `login` 案例在已登入時帶憑證跑。
- `app/AGENTS.md` § 插件（插件開發工具的「已知限制」那一句改寫）；`.trellis/spec/app/plugins/index.md` 的錄製段。

## 驗收

- 測試（測試檔內雙向變異）：
  - `mutates` 在健康檢查、命令列錄製、`DevCaseRuns` 的真實與錄製模式都不呼叫插件（以記錄呼叫次數的假插件）、在重播照跑；`parseChecks` 拒收 `mutates: false` 以外的非 `true` 值（照現有 `requiresLogin` 的寫法）。
  - 隔離環境：真實與錄製模式、`requiresLogin` 案例帶憑證（網路紀錄 `credentials: true`）；重播模式不帶；沒登入略過。
  - 換值：含自己顯示名稱的回應換值後才寫；換值後仍有殘留就不寫；改一個無關欄位（例如歌單標題）不擋。
- `dart format`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全過。
- 沒有使用者看得到的改動（「略過」字樣在 PR 14 有 `mutates` 案例時一起看）：不做實機驗證。
