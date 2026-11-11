# 11: 播放出聲

**What to build:** 在佔位搜尋頁點一首 B 站曲目，四個平台都播放出聲，並能暫停、繼續。宿主有自己的音訊後端介面，Android、iOS、macOS 用 just_audio 實作，Windows 用 media_kit 實作；串流的 header 照插件回傳的帶上。主要流程（搜尋到播放）有一條 `integration_test`，四平台都在完整閘門裡跑。這張票做完就是 M0 的 tracer bullet。

讀：brief §6、事實 K1、K3、K4、M5、W3、W4、W5、I4；plan §1.2、§1.3、§1.4、§2、§3；票 10 的 Comments；spec〈共同規則〉、〈驗收〉

**Blocked by:** 10

**Status:** ready-for-agent

- [ ] 音訊後端介面用 `mattpocock-skills:codebase-design` 設計，只涵蓋 M0 要的載入、播放、暫停、狀態與錯誤；兩個實作在 `playback/backends/`（plan §1.3 的例外，擁有者 2026-11-11 決定），平台判斷只在 `platform/`。
- [ ] 帶 header 播放：Apple 平台照事實 M5 重驗 B 站 CDN 回的 Content-Type 與 header 做法；Windows 照事實 K4。重驗結果更新 brief §18。
- [ ] 播放錯誤轉成錯誤分類並寫 log；長度為零或一直 buffering 的情況至少有記錄（事實 W4），完整的看門狗留給 M1，記到票的 Comments。
- [ ] 單元測試用 fake 後端測播放流程；零聯網。
- [ ] `integration_test`：搜尋、點一首、進入播放狀態，用 fixture 重播與不連網的音訊來源，四平台在 `check.dart` 完整版通過。
- [ ] 四平台實跑：搜一次、播一首，確認出聲並能暫停、繼續（macOS、Windows 本機聽；模擬器以播放狀態與進度前進為證），讀回畫面。
- [ ] 依賴版本寫進 plan §1.4。
- [ ] Windows 上的原生崩潰要分清來源再處理：建置階段 `frontend_server` 當掉（MSB8066，plan §2 記的 `winpc` 不穩）可以重跑；App 執行中的崩潰（崩的是 App 自己的行程，例如事實 W5 的 media_kit 同時 dispose）一律當產品 bug 查，不能重跑放過。判斷依據（log、crash dump 的模組名）記在票的 Comments。
- [ ] `dart run tool/check.dart` 完整版綠燈。
