# 05b: Windows 自繪標題列

Status: done
Blocked by: 05
讀: `docs/design/DESIGN.md` §5.2（Windows 那一點）；`docs/design/shell.html`、`docs/design/system.html`；票 05 的 Comments；architecture〈依賴規則〉〈主要依賴〉；spec〈共同規則〉

2026-11-15 協調者插票：票 05 做外殼時發現 Windows 用的是系統原生標題列，和 `DESIGN.md` §5.2 不符；擁有者定 05 先留原生標題列，自繪另開這張、排在 06 之前（M1 驗收要外殼截圖對得上設計稿）。

## What to build

Windows 照 `DESIGN.md` §5.2 改成沒有原生標題列的視窗：最小化、最大化（還原）、關閉三顆鈕（各 46×32，圖示 16）畫在視窗右上，內容頂列右端讓出 138px。視窗仍要像一般 Windows 視窗：可以拖曳頂列移動、雙擊頂列最大化與還原、滑鼠停在最大化鈕上出 Snap Layouts、邊緣可以拉大小、高 DPI 下按鈕與拖曳區位置正確，最小 720×560 照舊。

- 視窗相關的 Windows 差異收在 `platform/`，畫面只拿「要不要畫視窗鈕、讓出多少寬度」（依賴規則：`platform/` 以外不判斷平台）。
- 要加依賴（例如 `window_manager` 或 `bitsdojo_window`）時照〈事實與查證〉查當前 stable 與 Snap Layouts 的支援，版本寫進 ARCHITECTURE〈主要依賴〉；用到的平台行為補成事實。
- macOS、iOS、Android 不受影響。

## 驗收

- [x] Windows 沒有原生標題列，三顆視窗鈕的位置與大小照 `DESIGN.md` §5.2，內容頂列右端讓出 138px；截圖和設計稿對得上（深淺色）。
- [x] 拖曳頂列移動、雙擊最大化與還原、停在最大化鈕出 Snap Layouts、邊緣拉大小、最小 720×560，在 `winpc` 實跑讀回。
- [x] 讓出寬度與是否畫視窗鈕由 `platform/` 提供，有測試。
- [x] 新依賴的版本在 ARCHITECTURE〈主要依賴〉。（沒有新依賴：不用套件，見下面的決定與事實 K29）
- [x] 其他三平台實跑外殼照常。
- [x] 桌面寬版的頁面標題離側欄 24（側欄外框右緣 256 + 24 = 280），Windows 與 macOS 寬版、詳情面板開與收、深淺色截圖和 shell.html 對過。（2026-11-17 擁有者試用後加）
- [x] Windows 上詳情面板打開時，標頭與收起鈕整列在視窗鈕那一列（32）下方、收起鈕在標頭右端原位；中寬度浮動面板從視窗鈕下方 8 開始。（同上）
- [x] 詳情面板標頭不和右上視窗鈕重疊；收起時頂列的叫出面板鈕讓出 138。（同上）
- [x] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments

做法：`app/windows/runner/window_frame.cpp` 在 `WM_NCCALCSIZE` 拿掉標題列與頂框、保留左右下的拉邊緣；Flutter 畫面子視窗的 window procedure 換掉，最大化鈕與頂端拉邊緣那條回 `HTTRANSPARENT`，主視窗回 `HTMAXBUTTON`／`HTTOPLEFT`／`HTTOP`／`HTTOPRIGHT`；最大化鈕的 hover、按下、點擊由原生端處理並經 `fmp/window` 告訴 Dart。Dart 端 `platform/window_chrome.dart` 給「要不要畫、讓出多少、鈕多大」，`platform/window_controls.dart` 是頻道的 Riverpod notifier，`ui/shell/caption_buttons.dart` 畫鈕。事實 W12、K29；升級 Flutter 或 Windows 後的檢查清單在 docs/development.md〈Windows〉。
實跑（`winpc`，Windows 11、150% 縮放，以 SendInput 的真實滑鼠，腳本在 scratchpad）：拖曳頂列視窗移動 (224,131)、拖完點側欄照常換頁；雙擊頂列最大化、再雙擊還原；停在最大化鈕約 2 秒出 Snap Layouts（全螢幕截圖）；點最大化鈕最大化、圖示換成還原，再點還原；頂端往上拉高 +60、右邊緣拉寬 +80、頂左角斜拉 (−60,−40)；右下角往小拉時客戶區停在 720×560；最小化、還原、關閉後行程結束。最大化時內容貼齊螢幕不被切。
截圖（release 版）：第一版（詳情面板標頭右端讓 138）1280×720 深淺色、最小化鈕 hover 淡色底、關閉鈕 hover 紅底白圖示；960×720 浮動詳情面板打開時視窗鈕疊在面板右上、收起鈕讓到左邊（深淺色）；720×560 細欄版面。和 `system.html`〈Windows 視窗按鈕〉比對：三顆 46×32、圖示 16、label-2、貼右上，對得上。淺色那輪暫時把 `winpc` 的 `AppsUseLightTheme` 設成 1，跑完還原成原值 0（讀回確認）。
其他三平台：macOS（視窗 800×600，細欄、紅綠燈在細欄頂端、沒有視窗鈕）、iOS 模擬器 iPhone 18 Pro、Android 模擬器首頁，外殼照常。
擁有者試用（2026-11-17，經協調者）：寬版頁面標題離側欄太近、詳情面板的收起鈕和視窗鈕擠在同一列、面板標頭和視窗鈕重疊。查證：寬版標題 x=264 是照稿量的（shell.html、home.html、queue.html、search.html 寬版內容左內距都是 8），問擁有者後改 24；標頭的位置稿沒畫，問擁有者後整列下移 32。DESIGN.md §5.2 補了這兩句。
修正後的截圖：Windows（release、客戶區 1280×800）與 macOS（1280×800）寬版，詳情面板開與收、深淺色各一，和 shell.html〈桌面：側欄、詳情面板、播放膠囊〉四張並排：側欄、標頭高度、叫出面板鈕位置對得上；標題 x=280（稿 264，照新決定）；Windows 的「正在播放」與收起鈕在視窗鈕下方、收起鈕在右端（x=1254 中心）。macOS 與淺色那輪暫時切系統外觀，跑完還原（macOS 深色、winpc `AppsUseLightTheme`=0，讀回確認）。
閘門：`dart run tool/check.dart` 完整版在 95e61b41 第 6 次全綠（exit=0；Windows build 與兩個 integration_test 都過）。前 5 次 Mac 端與三平台都綠、只有 Windows 紅，原因都是 docs/development.md〈其他已知怪癖〉的 `winpc` 不穩：codegen 的 Dart `===== CRASH =====`（`exit codegen=78`、`-1073740791`，3 次）、只報 `MSB8066`（1 次）、閘門中途 `winpc` 非預期重開（System 事件 41、6008，03:29）。
code-review 未處理的發現：
- `window_chrome_test` 的 138 被說是重抄實作：保留，138 出自設計稿，票要求 `platform/` 這兩個值有測試。
- 懸停測試斷言 `CaptionButton` 的 `hovered`／`pressed` 欄位而不是畫面：保留，顏色以 `winpc` 截圖驗。
- `fmp/window` 頻道在 `window_drag.dart` 與 `window_controls.dart` 各宣告一次：拖動區 macOS 也用，不讀 `windowControlsProvider`（它會問 `isMaximized`，macOS 沒實作）。
- `WindowState` 這個名字偏泛、頻道方法沿用 macOS 的 `zoom`；`reportMaximizeButton` 只有一個呼叫點傳常數（留著讓按鈕位置只在 Dart 定義）；`_closeRed` 與白色是 `app/theme/` 外的字面值。
- 頂框線在 Windows 10 的樣子沒驗（`winpc` 是 Windows 11，四邊 1px 外框都在）。
- 第一輪實跑時 FMP 沒搶到前景，那輪的拖曳、雙擊與一次點擊可能落到 `winpc` 桌面上別的視窗（當時前景是 Orca）；之後腳本把 App 設成最上層，每個動作前確認前景是 FMP。
- 深色的 hover 截圖有一次游標停錯位置（收起面板鈕出 tooltip、關閉鈕沒紅），重拍正常，沒能重現。
Session 紀錄：2026-11-17 Windows 改成自繪標題列：runner 自己寫無標題列視窗與 Snap Layouts，Dart 畫三顆鈕、外殼讓出 138；winpc 真實滑鼠實跑全過，四平台外殼照常
Session 紀錄：2026-11-17 擁有者試用後併修三處：寬版頁面左內距 24、Windows 詳情面板標頭下移到視窗鈕下方，兩平台寬版深淺色和 shell.html 對過，完整閘門綠
決定：不用套件、自己在 Windows runner 寫 C++：window_manager 新版要 Flutter 3.50、舊版停止維護，兩版都不支援 Snap Layouts（事實 K29）（Agent 定）
決定：Snap Layouts 靠換掉 Flutter 子視窗的 window procedure；升級 Flutter 可能悄悄失效、沒有單元測試，只靠 winpc 實跑，清單在 development.md（Agent 定）
決定：拖曳與雙擊沿用 macOS 的做法，Dart 手勢經 `fmp/window` 叫原生端拖動與最大化，不由原生端對頂列回 `HTCAPTION`（Agent 定）
決定：「內容頂列右端讓出 138」解讀為頂列 `.wtop` 的右端退到 138（叫出面板鈕在 right 154）；詳情面板標頭改成下移，見下面擁有者的決定（Agent 定）
決定：頂端拉邊緣那條（約 8 邏輯像素）蓋住三顆鈕的上緣，兩角可斜拉，照 Windows Terminal（Agent 定）
決定：hover 照 Windows 11：最小化、最大化用 fill、按下 fill2，關閉紅底 #C42B1C 白圖示，160ms 過場；稿沒指定（Agent 定）
決定：最大化時的還原圖示用 Windows 慣例的兩個疊方框，和最大化同大；稿沒畫（Agent 定）
決定：視窗鈕不加 tooltip、只給螢幕閱讀器名稱（最小化、最大化／還原、關閉，三語），最大化鈕上 Windows 出 Snap Layouts（Agent 定）
決定：鈕的大小 46×32 只定義在 `WindowChrome.captionButtonSize`；最大化鈕位置由 Dart 以離右上角的距離告訴原生端（Agent 定）
決定：測試接縫照票面：`platform/` 的兩個值、外殼 widget 測試經 `fmp/window` 頻道；原生碼以 winpc 真實滑鼠實跑驗證（Agent 定）
決定：桌面寬版的頁面左內距從稿的 8 改成 24，和播放膠囊離側欄的距離相同；DESIGN.md §5.2 補一句，各頁 html 待設計同步（使用者定）
決定：Windows 上詳情面板頂端先讓出視窗鈕那一列 32，標頭與收起鈕在下面照常排；中寬度浮動面板從視窗鈕下方 8 開始（使用者定）
變更：Changed｜外殼｜桌面寬版的頁面內容離左側側欄多留一點空間（24）
變更：Changed｜外殼｜Windows 不再有系統標題列：最小化、最大化（還原）、關閉畫在視窗右上，拖曳頂列移動、雙擊最大化、停在最大化鈕出 Snap Layouts、邊緣與頂角拉大小照常
