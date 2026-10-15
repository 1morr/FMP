# 以帳號本身的值遮蔽帳號識別（#264、#254 的準備）

## 目標

- #264：自己的帳號 id（B 站 mid、網易雲 uid、YouTube id）不出現在網路紀錄、錯誤報告、診斷包。
- #254 的準備：App 內以登入狀態錄 login 案例時，帳號 id、名稱、頭像不寫進 fixture，
  而且不用改插件 manifest、不用重錄現有 fixture。

## 擁有者決定（2026-10-15）

- 只遮**自己的** id；瀏覽的 UP 主、主播的 id 照留（除錯用得到）。
- YouTube 的 `userId` 退回 handle 或名稱時也登記，接受同名一般文字被遮（寧可多遮）。
- 不照 issue 原文加鍵名（`mid`、`uid`、`vmid`、`uname`、`face`）：會遮到別人的 id、
  頭像，弄壞 fixture 與契約（design §4、§5.5）。

## 要求

- **A**：`CredentialStore` 登記憑證時連同帳號的 `userId` 登記為已知值（短於 4 字元略過），
  登出、換帳號時取消（design §5.2）。
- **B**：全數字的已知值只在數字邊界比對（`(?<![0-9])值(?![0-9])`）；其他已知值照舊子字串比對（design §5.3）。
- **C**：`recordCase` 在結果是 `LoginAccount` 時，寫檔前以帳號的 `userId`、`displayName`、
  頭像換掉錄到的流量（頭像換成 `<scheme>://<host>/***`）；`accountLeaks` 留作最後一道，
  頭像改用主機＋路徑比對，補上網易雲頭像被改寫成 https 加 `?param=` 時比對不到的漏洞（design §5.4）。
- ADR 0029 §決定 5、ADR 0011 §決定 3 各加一行更正；`app/AGENTS.md` 與
  `.trellis/spec/app/plugins/index.md` 同步（design §6、§8）。

## 驗收

- design §7 的測試全部到位，每條新規則都有兩個方向的變異（違規會紅、無關改動維持綠）。
- `dart format`、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test` 全過。
- 三個官方插件的契約重播（`FMP_PLUGIN_DIR`）全綠，不用重錄。
- Android 模擬器（dev debug，重播 `fmp-test` 假帳號）：登入 `fmp-test` 後觸發一次帶自己 id 的請求，
  或以單元測試涵蓋時註明實機看不到的原因。

## 不做

- 不遮別人的 id；不加網路紀錄專用的 query 名單。
- 不登記 `displayName`、頭像為全域已知值。
- 不改 fmp-plugins；16c 的實際錄製留在 #254，擁有者在場時做，錄完人工檢查 login fixture 的其他帳號欄位（design §9 第 2 點）。
- M4 的「需要登入、非 login 案例」的換值（design §10）。
