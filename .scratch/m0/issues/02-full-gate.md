# 02: 完整閘門

**What to build:** 一條指令 `dart run tool/check.dart` 跑完新版合併前要過的全部檢查：quick 之外，在 macOS、iOS 模擬器、Android 模擬器、Windows（`winpc`）建置並跑 `integration_test`。這張票先放一條「App 啟動後看得到佔位畫面」的 `integration_test`，之後的票往裡面加。

讀：plan §2、§3、§4；brief §4；票 01 的 Comments；spec〈共同規則〉

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] 完整版依序做：quick、四平台建置、四平台 `integration_test`；任一平台失敗就非零退出，並指出是哪個平台、哪一步。
- [ ] Windows 照票 01 的做法經 SSH 同步工作樹（不 push）、在桌面工作階段跑建置與 `integration_test`，結果與輸出取回 Mac。
- [ ] 避開 plan §2 列的 `integration_test` 怪癖：一次一個檔；Android 不刪模擬器上同 applicationId 的資料。
- [ ] 有一條 `integration_test`：App 啟動後看得到佔位畫面，四平台都通過。
- [ ] 留好「插件打包產物是否最新」這一步的位置，由票 08 填入；這張票不做假的檢查。
- [ ] plan §2 每個平台一節：框架與套件、建置指令、實跑驗證的方式。
- [ ] 貼一次完整版綠燈的輸出。
