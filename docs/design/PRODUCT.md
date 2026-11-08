# Product

<!-- impeccable:product-schema 1 -->

本檔是 `docs/design-brief.md` 的摘要，給設計工具讀。兩者衝突時以 brief 為準；改產品事實先改 brief，再同步這裡。

## Platform

adaptive

## Users

擁有者本人為主，加上從 GitHub 下載的少數外部使用者（brief §3）。主要情境：手機通勤時聽；桌面工作時背景播放，偶爾切過去換歌、看歌詞。

## Product Purpose

多音源（Bilibili、YouTube、網易雲音樂）的搜尋與播放，本地歌單與匯入歌單，遠端歌單寫入，帳號與會員狀態，歌詞，系統媒體控制與背景播放（brief §2.1）。App 是載體，音源能力由插件提供。

## Positioning

一個 App 裡同時搜、同時排佇列三個音源的曲目，並在每首歌上標出它來自哪個音源、要不要會員。

## Operating Context

- 手機：單手、通勤途中，常在背景播放，回到 App 多半是換歌、看佇列、加入歌單。
- 桌面：視窗開在旁邊，迷你播放器與右側詳情面板常駐，主區做搜尋與整理歌單。
- 長期使用者是舊版 FMP（Material 3，Android 與 Windows）的使用者，熟悉它的頁面地圖。

## Capabilities and Constraints

- 平台：iOS、macOS、Android、Windows，同一個里程碑一起做（brief §4）。四個平台用同一套視覺語言；版面依寬度級距（Material 3 的 compact、medium、expanded）變化；返回手勢、安全區、標題列、系統媒體控制等作業系統慣例照各平台。Platform 記為 `adaptive` 是為了讀進 iOS 與 Android 兩邊的平台慣例，不代表各平台換設計語言。
- 實作是 Flutter；設計稿是靜態 HTML，實作照定稿切版（brief §11）。
- 第一版頁面：App 外殼（導覽、迷你播放器）、搜尋與結果、音樂庫、歌單詳情（本地、匯入）、佇列、全螢幕播放頁（含歌詞）、加入歌單對話框、帳號與登入、插件管理、設定、匯入舊版備份。第一版沒有首頁、電台、下載。
- 曲目的存取等級標識（三音源的 VIP、試聽、需登入）是必備資訊（brief §5.1、§5.4）。
- 語言：zh-TW 為主，另有 zh-CN、en。標題常是長的中日韓混排字串。
- 深色與淺色同等設計，預設跟隨系統。
- 名詞一律用根目錄 `GLOSSARY.md` 的詞。

## Brand Commitments

- 名稱 FMP。
- 以舊版 UI 為底：頁面地圖、資訊架構、各頁功能入口照舊版；設計系統重新訂定（brief §11）。
- 玻璃材質只用在浮在內容上的控制層，內容實心；慣例取自 Apple Music（iOS 26、macOS 26）（brief §2.3、§11）。
- 強調色是單一 token，只用在互動與狀態；使用者可從預設色中自選（舊版有 9 色，篩掉對比不足的）；玻璃與底色不帶強調色。全螢幕播放頁背景跟著封面取色。
- 必須保留：音源與 VIP 標識、桌面右側詳情面板、舊版的列表資訊密度（一屏多首，播放量、時長等中繼資訊都在）。

## Evidence on Hand

- 舊版截圖：`docs/audit/screenshots/`（Android、Windows）、`screenshots/`。
- 舊版 UI 現況審計：`docs/audit/ui.md`（頁面地圖、斷點、token）。
- 擁有者提供的 Apple Music（iOS 26）截圖，只作為材質與外殼 B 的參照，未存進 repo。
- 沒有真實使用數據、使用者訪談或評價；設計稿裡的曲目與數字是示意，不得當成事實。

## Product Principles

1. 播放不中斷：任何頁面都能一眼看到並控制正在播放的歌。
2. 音源是一等資訊：來源與存取等級在列表上就看得到，不必點進去。
3. 熟悉優先：舊版使用者不需重新學頁面地圖。
4. 內容是主角，控制層退後：材質和顏色不搶封面與標題。

## Accessibility & Inclusion

- Windows Narrator 可讀（brief 事實 W1 的 Slider 問題要避開）。
- 桌面完整鍵盤操作與可見的焦點框。
- 尊重系統的減少動態效果與字級設定。
