# 19d: 動態補齊：對稿修正、減少動態效果、補上會突然跳出來的動畫

Status: ready-for-agent
Blocked by: 19c
讀: `docs/design/DESIGN.md` §3.4（含〈狀態變化對照〉，2026-11-20 新增）、§10；`docs/agents/ui.md` 的「動態」那條；`docs/design/assets/fmp.css`（`.spinner`、`.tab`、按下縮放）、`docs/design/player.html`（頁面點點）、`docs/design/system.html`（減少動態效果）；`app/lib/ui/` 的 motion token（`motion.dart`）；spec〈共同規則〉

2026-11-20 協調者插票（使用者定）：擁有者發現詳情面板沒有動畫（票 19c）後要求盤點全 App。盤點找到三類，擁有者選了要修的範圍（下面列的都要做）；`DESIGN.md` §3.4 的〈狀態變化對照〉與 `ui.md` 的動態規則同時寫入，這張照它們實作。位置是盤點當時（main 2d261601）的，以程式碼現況為準。

修復票的驗收包含回頭補勾被它卡住的票：沒有。

## What to build

**A. 稿上有寫、沒照做**
- 圖示鈕按下縮到 0.92（`iconPressScale` 定義了沒人用；`ShellButton`、`PlainIconButton` 與播放控制）；按鈕 0.96 也一併確認。
- 手機曲目 ⋮ sheet、曲目資訊 sheet 升起改 morph 520（現在 280 out）。
- 載入中的轉圈照 `.spinner`：900ms 等速旋轉，減少動態效果時 3 秒一圈；取代 Material 的 `CircularProgressIndicator`（分 P 載入、曲目資訊載入等）。
- 手機播放頁點點點換頁時，點點寬度用 spring（滑動時仍跟著位置走）。
- 手機導覽列選取項目的字色用 out 280 過渡。

**C. 減少動態效果沒跟著改**
- 讀「減少動態效果」收成一個共用入口（例如 motion token 旁的 helper），現有各處（盤點時 9 處各自呼叫 `MediaQuery.disableAnimationsOf`）改用它。
- 手機導覽選取膠囊：不彈跳、不放大，只淡入淡出。
- 進出搜尋時導覽變形：只淡入淡出。
- 曲目 ⋮ sheet 升起：只淡入淡出（曲目資訊 sheet 已處理，確認一致）。
- 迷你播放器、提示（toast）：拿掉位移，只留淡入。

**B. 稿沒寫、會突然跳出來的（照〈狀態變化對照〉）**
- 圖片與內容替換：封面載入淡入（out 160）；骨架換成內容交叉淡出（首頁榜同一個音源從載入變好也要淡、搜尋結果）；換歌時封面交叉淡出（迷你播放器、播放膠囊、播放頁、詳情面板）。
- 出現與消失：搜尋多選時動作列從底部滑入、導覽反向離開（手機與桌面）；桌面／中寬度播放膠囊第一次出現時比照手機迷你播放器淡入。
- 清單增減：搜尋頁分 P 展開改用首頁的展開元件（兩邊一致）；佇列移除一首時那列收起高度並淡出，清空後空狀態淡入。
- 不做：sheet 跟著手指拖（擁有者定，先不做）。

## 驗收

- [ ] A 每項一條 widget 測試（按下縮放、sheet 時長與曲線、spinner 轉速與減少動態效果時放慢、點點 spring、字色過渡）。
- [ ] C：共用入口有測試，各處改用它（搜不到直接呼叫 `disableAnimationsOf` 的地方，入口本身除外）；導覽膠囊、搜尋變形、⋮ sheet、迷你播放器、提示在減少動態效果時各一條測試。
- [ ] B 每組一條在動畫中途檢查的 widget 測試（透明度或高度在中間值），減少動態效果時照表退化。
- [ ] macOS 加一個手機平台實跑：換歌、搜尋多選、展開分 P、佇列移除各截一張動畫中途的圖；系統開減少動態效果再截導覽換頁與 sheet。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版；winpc 恢復前 `--skip-windows`）。

## Comments
決定：盤點出的「稿上有寫沒照做」與「減少動態效果沒跟著改」全修，讀這個設定收成一個共用入口（使用者定）
決定：新增的動畫只做圖片與內容替換、出現與消失、清單增減三組；sheet 跟手指拖先不做（使用者定）
等使用者：無（session 因額度中斷，下一個 session 接著做，見下一行）
進度（2026-11-20，未完成）：已做 A 全部（按下縮放、sheet morph 520、Spinner、點點 spring、導覽字色）、C 全部（共用入口、膠囊、搜尋變形、sheet、迷你播放器、提示；播放頁路由與換畫面也改成保留時長）、B 的封面載入淡入、換歌封面交叉淡出、首頁與搜尋的骨架交叉淡出、分 P 改用 `ExpandingRows`、多選動作列與 dock 進出、播放膠囊淡入；共用元件在 `app/lib/ui/common/motion.dart`（全用 `AnimationBehavior.preserve`），測試用 `test/support/motion.dart` 的 `reduceMotion`（改 platformDispatcher，5% 縮短真的生效）。還沒做：佇列移除一首收起高度＋淡出、清空後空狀態淡入、佇列頂列小標題在減少動態效果時直接消失（19c 留下）、事實 K35（AnimationBehavior：normal 在 disableAnimations 時縮成 5%，來源 api.flutter.dev/flutter/animation/AnimationBehavior.html）寫進 `docs/research/facts-packages.md`、設定頁 `FmpMotion.selection` 的隱式動畫在減少動態效果時仍會被縮成 5%（要不要改待查）、macOS＋iOS 模擬器實跑截圖（含系統開減少動態效果截淡入中途、跑完關回）、完整閘門 `--skip-windows`、code-review、Status 與紀錄行。
決定：減少動態效果時仍要動的動畫一律用 `AnimationBehavior.preserve`（官方文件寫的 API），不改 binding（協調者轉達）（Agent 定）
決定：按下縮 0.92 的圖示鈕是 `GlassIconButton`、`PlainIconButton`、播放／上一首／下一首、隨機循環圖示鈕與播放頁控制鈕；dock 的大圓鈕不縮（Agent 定）
決定：sheet 收起也用 morph 520（曲線反過來）；桌面曲目資訊對話框照舊淡入 160，改成保留時長（Agent 定）
決定：播放頁路由與減少動態效果時的換畫面同樣改保留時長（同一個 5% 問題，票面沒列）（Agent 定）
