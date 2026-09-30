# YouTube.js 可行性探針（M1）

父任務：`../09-28-m1-skeleton-tracer`（擁有者決定 3；implement「探針：YouTube.js」）。依據 ADR 0014 §決定 10。

## 問題

YouTube.js（npm `youtubei.js`）能否在 FMP 的插件執行環境裡搜尋，並解出可以播放的串流？執行環境是 `flutter_js` 0.8.7 的 QuickJS，每個插件一個背景 isolate，只有宿主 API v1。

## 過關標準

Android 與 Windows 都要做到：
- 能載入；
- 搜尋有結果；
- 解出的音訊網址 FMP 播得出聲音；
- 不需要登入，也不需要另外生成 PO token。

效能只記錄，不影響過關。時限約 2–3 個 session，程式碼不合併。

## 結果

**通過**，前提是 `resolveStream` 改用 VISIONOS client，IOS 當備援。證據、墊片、client 現況、效能與宿主 API 缺口都在 `research/youtubejs-probe.md`。
- 探針程式碼保存在分支 `probe/youtubejs`：已 push，不合併。
- 但書：Android 模擬器是以 `-no-audio` 啟動的，Android 的「播得出聲音」只驗到音訊系統那一層。
- 結論：M3 的 YouTube 走插件，不改用 Dart 實作。ADR 0014 §決定 10 已補一句。
