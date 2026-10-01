# M2 PR 2：網路狀態與離線呈現

`../10-01-m2-full-playback/implement.md` §2；design §5。ADR 0016 §決定 6、7，ADR 0009 §決定 6。

## 做什麼

1. 平台層 `lib/platform/connectivity/`：介面 `NetworkInterfaces`（有沒有網路介面與它的變化），Android、Windows 以 `connectivity_plus` 實作；宣告 `PlatformCapabilities.networkInterfaces`，`platform_test.dart` 每平台一個斷言。其他平台照 ADR 0009 宣告為沒有。
2. 網路層 `lib/core/network/network_status.dart`：`NetworkStatus`（`online`、`noInterface`、`unreachable`）與狀態機（design §5.2 的轉換表；時間以 `clock` 取，不開計時器、不輪詢）。輸入：介面變化、`SourceHttpClient` 每次請求的結果（拿到 HTTP 回應不論狀態碼＝成功；`NetworkError`＝失敗）。PR 3 的媒體 client 接同一個入口。以 provider 對外。
3. `lib/app/` 的 `appLifecycleProvider`（`AppLifecycleState`）；回到 `resumed` 時重查一次介面（`connectivity_plus` README：Android 8 起背景收不到變化）。
4. 介面（design §5.4）：
   - 外殼內容區頂端的全域離線提示，`noInterface`／`unreachable` 兩種文字，不用 toast；
   - 共用的離線空狀態元件；
   - 搜尋頁：`noInterface`、`unreachable` 都照常送出使用者的搜尋（擁有者決定 9、ADR 0016 §決定 7 的更正），失敗時顯示離線空狀態與「重試」，已有的結果照常顯示；
   - 設定頁完整可用。
   - 字串三語言（slang）。
5. 依賴：`connectivity_plus` 用 pub.dev 當前 stable（`platformPackages` 已允許在 `lib/platform/`）。新原生插件的 registrant 是真的新增，不可還原。
6. 文件：`app/AGENTS.md` 的網路層、平台層、介面段（只寫查不到的契約與閘門）；需要時 `.trellis/spec/app/network`、`platform`、`ui`。

## 驗收

- [ ] 狀態轉換表逐列的單元測試；在 `fakeAsync` 裡跑完所有轉換後斷言沒有待執行的計時器。
- [ ] widget 測試：搜尋頁在 `noInterface` 與 `unreachable` 各一個（都送出，失敗時才顯示離線空狀態）；`noInterface` 收到回應回到 `online`；全域提示在離線時出現、回到 `online` 時消失；guideline 測試加離線狀態。
- [ ] 通用驗證：format、build_runner 後沒有實質變動、`dart run slang` 無變動、`dart analyze --fatal-infos`、`flutter analyze`、`flutter test`、哨兵。
- [ ] 實機（主對話照 `verify-on-device`，模式：重播）：Android 模擬器切飛航模式 → 全域提示與搜尋頁離線狀態 → 關掉恢復；Windows 停用網路介面再啟用（或以同等方式讓介面消失）。
