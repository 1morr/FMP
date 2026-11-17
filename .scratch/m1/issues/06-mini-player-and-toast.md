# 06: 迷你播放器、播放膠囊與 Toast

Status: done
Blocked by: 05
讀: brief §11、§13；`docs/design/DESIGN.md` §5.1、§5.2、§6.4；`docs/design/shell.html`；architecture〈依賴規則〉；spec〈共同規則〉

## What to build

外殼有照稿的播放控制與提示：手機底部的書脊式迷你播放器、桌面底部的播放膠囊（膠囊本身就是進度條），顯示目前曲目（封面、標題、作者、音源標識）、播放與暫停，沒有目前曲目時照稿的空狀態；點迷你播放器打開播放頁由 16 接上，這張票不做空的播放頁。

單一的 Toast 入口（brief §13）：錯誤依錯誤分類給文字與動作，也用於成功提示；這張票接上播放失敗與沒有網路兩種。上一首、下一首等佇列有了再接（07）。

## 驗收

- [x] 迷你播放器與播放膠囊的截圖和 `shell.html` 對得上（有曲目、無曲目、播放中、暫停）。
- [x] 書脊式進度跟著播放位置走，有 widget 測試。
- [x] Toast 入口有測試：錯誤分類對到文字與動作；沒有網路時播放顯示網路錯誤的 Toast。
- [x] 音源標識讀 manifest 宣告的簡稱、顏色、符號（ADR 0039），Dart 端沒有音源專屬的分支；manifest 多的欄位寫回 ADR 0039〈各插件能力的介面〉。
- [x] 四平台實跑：搜尋、播放一首，迷你播放器讀回曲名並能暫停、繼續。
- [x] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。（Windows 的兩個 integration_test 在 winpc 重開後補跑，見 Comments 的閘門）

## Comments
閘門：`dart run tool/check.dart` 完整版（51b3c78a，之後只改了票）除了 Windows 的兩個 integration_test 都綠，Windows build 也綠；跑 `integration_test/app_test.dart` 時 `winpc` 斷線（`ssh_dispatch_run_fatal … Operation timed out`，接著 `Host is down`），之後 30 多分鐘 ping 不通、SSH 連不上。擁有者開機後查到：13:24:41 Kernel-Power 41、13:24:54 藍屏 BugCheck `0x3B`（`0xc0000005`，minidump 在 `C:\WINDOWS\Minidump\`），6008 記上次非預期關機在 10:10:00。照 docs/development.md〈Windows〉的閘門指令持鎖補跑（`app/` 和 51b3c78a 相同）：第 1 輪 pub get、slang、codegen 都是 0，`integration_test/app_test.dart`（+2）與 `integration_test/search_and_play_test.dart`（+1）都 `All tests passed`、`exit test=0`、有 `=== done`；那輪的建置步驟是 rustc 編 `hashbrown` 失敗（MSB8066，沒有編譯錯誤訊息；同時段 powershell 在 clr.dll 存取違規）。第 2–4 輪建置都卡在 codegen 的 Dart `===== CRASH =====`（`exit codegen=78`／`-1073740791`，位址每次不同），是〈其他已知怪癖〉記的 winpc 不穩。Windows 建置在上面那輪完整閘門已是 `ok`，所以每一步都在這份程式碼綠過
Session 紀錄：2026-11-17 迷你播放器、播放膠囊（書脊式進度）、單一 Toast 入口與播放失敗提示；manifest 的音源標識、曲目封面與磁碟快取；四平台實跑搜尋、播放、暫停、繼續
決定：音源標識是 manifest 選填的 `mark`（簡稱、顏色、照 VectorDrawable 欄位名的路徑清單），用 path_parsing 畫、不加 SVG 渲染；寫回 ADR 0039（使用者同意）
決定：曲目加選填的封面網址，B 站搜尋回傳封面，用 cached_network_image 4.0.7 顯示；這張票補上，不留給別張（使用者同意）
決定：圖片快取改成上限 1000 個檔、30 天沒用就刪（套件不能限位元組），ARCHITECTURE〈快取〉照實改（使用者同意）
決定：B 站插件把封面交成 160 方形 webp 縮圖（約 2 KB，原圖平均約 450 KB，事實 F23），大圖之後另取（Agent 定）
決定：Toast 同時只有一則、新的取代舊的；沒動作 4 秒、有動作 8 秒收起（Agent 定）
決定：桌面與中寬度的 Toast 在播放膠囊上方 12、膠囊左右範圍內置中、最寬 480；沒有曲目時離底 24（Agent 定）
決定：桌面與中寬度沒有目前曲目時也不顯示播放膠囊，同手機（Agent 定）
決定：「重試」只給網路、限流、解析失敗與原因不明；需登入、需驗證的動作等那些功能做出來才加（Agent 定）
決定：播放鈕遇到播完或失敗的那首從頭再播；解析與載入中顯示暫停（Agent 定）
決定：搜尋頁的 M0 播放面板拿掉暫停、繼續鈕，改用外殼的播放控制；狀態與串流資訊留到票 14 換搜尋頁（Agent 定）
決定：cached_network_image、flutter_cache_manager 只在 `platform/` 用，依賴規則分類成平台套件（Agent 定）
決定：契約測試的 search 加 `covers` 期望，B 站的搜尋 fixture 重錄並要求每首有封面（Agent 定）
決定：音源標識的螢幕閱讀器名稱用 manifest 的 `name`；迷你播放器與播放膠囊各自是一個語意節點（Agent 定）
決定：`shot.ps1` 加 `-TypeAt`，Tab 到不了的欄位先點它再打字（Agent 定）
截圖比對（和 `shell.html` 同狀態並排看過，截圖留在本機暫存目錄，不進 repo）：
- macOS：1280×800 播放中、暫停、收起詳情面板（right 24），960×720（left 104）、720×560（收掉時間），深淺色；沒有曲目時沒有膠囊；沒有網路的提示（真實的一次 TLS 失敗）按「重試」後播放。
- iOS：iPhone 18 Pro 深淺色，首頁與搜尋模式的迷你播放器（362×56、top 24），暫停、繼續。
- Android：Medium Phone 深淺色，迷你播放器播放、暫停、繼續，螢幕閱讀器讀回曲名、音源、作者、時間。
- Windows：1280×800 淺色，搜尋、播放、暫停、繼續。
已知差異：播放膠囊中間只有播放鈕、右邊只有時間，迷你播放器沒有下一首鈕（上一首、下一首等之後的票，還沒有的功能不出現入口）；點迷你播放器、播放膠囊沒有動作（票 16）；Windows 只看了淺色；平板觸控密度的膠囊只有 widget 測試（iPad 換裝置會關掉 iPhone 模擬器）
發現：macOS 的 AVPlayer 對 `upos-hz-mirrorakam.akamaized.net` 回過一次 TLS 錯誤 -1200（分到網路錯誤），按重試重新解析就播了；票 11 做失敗處理時可參考 backupUrl
發現：寬版側欄的搜尋欄點第一下只聚焦，第二下才進搜尋頁，進頁後要再點一下才打得進字（macOS、Windows 都一樣），留給票 14
code-review 未處理：書脊已播放段的密度沒有依底下亮度調整（玻璃元件沒有自適應色調，DESIGN.md〈手機〉）
code-review 未處理：解析與載入中播放鈕顯示暫停但按了沒作用；進度 0 時折線不畫（CSS 會露出 1px）
code-review 未處理：manifest 的 `short`、`color` 解析了但 M1 的畫面還沒用到（手機搜尋結果與 chip 才用，票 14、17）
code-review 未處理：一個測試同時驗顯示、暫停與書脊；Toast 的 8 秒與「新的取代舊的」、封面顯示沒有測試
code-review 未處理：判斷題的 smell 沒改：`MiniPlayer`／`TransportBar` 外層結構重複、`ToastLayer` 同時畫提示與監聽播放、`manifest.dart` 的 `_NoPath` 與圖示的 `_PathProxy` 同形、`now_playing.dart` 檔名、`PlaybackStatus` 在三處各 switch 一次
變更：Added｜播放控制｜手機底部的迷你播放器顯示正在播的曲目（封面、標題、音源標識、作者、時間）與播放、暫停，膠囊本身隨播放填滿成進度條
變更：Added｜播放控制｜桌面與平板底部的播放膠囊顯示正在播的曲目與播放、暫停，膠囊本身就是進度條；視窗窄時收掉時間
變更：Added｜提示｜播放失敗時跳出提示說明原因，沒有網路這類可重試的情況有「重試」
變更：Changed｜搜尋｜搜尋頁的播放面板不再有暫停、繼續鈕，改用迷你播放器或播放膠囊
等使用者：`winpc`（跑 Windows 建置與測試的那台電腦）在完整閘門跑到 Windows 的 integration_test 時斷線，之後一直連不上（ping 不通、SSH 逾時）。選項：開機並登入桌面，讓接手的 session 在 51b3c78a 照 docs/development.md〈Windows〉的閘門指令補跑那兩個 integration_test（先查有沒有 Kernel-Power 重開事件）；或者這張票先不管 Windows。建議開機補跑。不處理的話，這張票不能改 done，也不能合併。
決定：開機補跑 Windows 的 integration_test（使用者定）
Session 紀錄：2026-11-17 winpc 重開後補跑 Windows 的兩個 integration_test（綠），票改 done
