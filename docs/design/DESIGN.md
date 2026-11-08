---
name: FMP
description: 卡帶 J-card：曲目密排、時長對齊成一欄、一條摺線分開已播與接下來；中性底、單一強調色、玻璃只在浮動控制層。
colors:
  bg-dark: "#121214"
  bg2-dark: "#1A1A1D"
  fg-dark: "#F2F1EE"
  fg2-dark: "#B4B2AD"
  fg3-dark: "#8C8A85"
  line-dark: "rgba(255,255,255,.08)"
  line-strong-dark: "rgba(255,255,255,.22)"
  accent-dark: "#CFBCFF"
  on-accent-dark: "#21005D"
  accent-soft-dark: "rgba(207,188,255,.14)"
  vip-dark: "#E3B341"
  on-vip-dark: "#241A00"
  trial-dark: "#E3B341"
  error-dark: "#FFB4AB"
  glass-dark: "rgba(40,40,44,.56)"
  glass-edge-dark: "rgba(255,255,255,.12)"
  glass-hi-dark: "rgba(255,255,255,.14)"
  played-dark: "rgba(255,255,255,.07)"
  crease-hi-dark: "rgba(255,255,255,.45)"
  crease-lo-dark: "rgba(0,0,0,.45)"
  hover-dark: "rgba(255,255,255,.05)"
  pressed-dark: "rgba(255,255,255,.10)"
  bg-light: "#F5F5F3"
  bg2-light: "#EBEBE8"
  fg-light: "#17171A"
  fg2-light: "#55544F"
  fg3-light: "#6B6A65"
  line-light: "rgba(0,0,0,.08)"
  line-strong-light: "rgba(0,0,0,.24)"
  accent-light: "#6750A4"
  on-accent-light: "#FFFFFF"
  accent-soft-light: "rgba(103,80,164,.10)"
  vip-light: "#E3B341"
  on-vip-light: "#241A00"
  trial-light: "#8A6100"
  error-light: "#BA1A1A"
  glass-light: "rgba(252,252,250,.64)"
  glass-edge-light: "rgba(0,0,0,.08)"
  glass-hi-light: "rgba(255,255,255,.75)"
  played-light: "rgba(0,0,0,.05)"
  crease-hi-light: "rgba(255,255,255,.95)"
  crease-lo-light: "rgba(0,0,0,.22)"
  hover-light: "rgba(0,0,0,.04)"
  pressed-light: "rgba(0,0,0,.08)"
typography:
  h1:
    fontFamily: "-apple-system, BlinkMacSystemFont, PingFang TC, Microsoft JhengHei UI, Noto Sans TC, Roboto, sans-serif"
    fontSize: "32px"
    fontWeight: 700
  h2:
    fontFamily: "-apple-system, BlinkMacSystemFont, PingFang TC, Microsoft JhengHei UI, Noto Sans TC, Roboto, sans-serif"
    fontSize: "26px"
    fontWeight: 700
  h3:
    fontFamily: "-apple-system, BlinkMacSystemFont, PingFang TC, Microsoft JhengHei UI, Noto Sans TC, Roboto, sans-serif"
    fontSize: "20px"
    fontWeight: 700
  title:
    fontFamily: "-apple-system, BlinkMacSystemFont, PingFang TC, Microsoft JhengHei UI, Noto Sans TC, Roboto, sans-serif"
    fontSize: "17px"
    fontWeight: 600
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, PingFang TC, Microsoft JhengHei UI, Noto Sans TC, Roboto, sans-serif"
    fontSize: "15px"
    fontWeight: 500
    lineHeight: 1.3
    fontFeature: "tnum"
  small:
    fontFamily: "-apple-system, BlinkMacSystemFont, PingFang TC, Microsoft JhengHei UI, Noto Sans TC, Roboto, sans-serif"
    fontSize: "13px"
    fontWeight: 400
  meta:
    fontFamily: "-apple-system, BlinkMacSystemFont, PingFang TC, Microsoft JhengHei UI, Noto Sans TC, Roboto, sans-serif"
    fontSize: "12px"
    fontWeight: 400
  caption:
    fontFamily: "-apple-system, BlinkMacSystemFont, PingFang TC, Microsoft JhengHei UI, Noto Sans TC, Roboto, sans-serif"
    fontSize: "11px"
    fontWeight: 500
  duration:
    fontFamily: "ui-monospace, SF Mono, Cascadia Mono, Menlo, monospace"
    fontSize: "12px"
    lineHeight: 1
rounded:
  tag: "4px"
  cover: "6px"
  ctl: "12px"
  spine: "16px"
  sheet: "20px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  xxl: "24px"
  xxxl: "32px"
components:
  track-row-phone:
    height: "60px"
    padding: "0 20px 0 8px"
    typography: "{typography.body}"
  track-row-desktop:
    height: "52px"
    padding: "0 28px 0 16px"
  tag-source:
    textColor: "{colors.fg2-dark}"
    rounded: "{rounded.tag}"
    typography: "{typography.caption}"
    padding: "0 5px"
  tag-vip:
    backgroundColor: "{colors.vip-dark}"
    textColor: "{colors.on-vip-dark}"
    rounded: "{rounded.tag}"
    typography: "{typography.caption}"
  button-primary:
    backgroundColor: "{colors.accent-dark}"
    textColor: "{colors.on-accent-dark}"
    rounded: "{rounded.ctl}"
    height: "40px"
    padding: "0 18px"
  button-tonal:
    backgroundColor: "{colors.accent-soft-dark}"
    textColor: "{colors.fg-dark}"
    rounded: "{rounded.ctl}"
    height: "40px"
    padding: "0 18px"
  button-outline:
    textColor: "{colors.fg-dark}"
    rounded: "{rounded.ctl}"
    height: "40px"
    padding: "0 18px"
  spine-phone:
    backgroundColor: "{colors.glass-dark}"
    rounded: "{rounded.spine}"
    height: "58px"
    padding: "0 12px 0 9px"
---

# Design System: FMP

本檔記錄的是已完成的靜態設計稿（`assets/fmp.css` 與 `src/build.py` 的 PAGE_CSS）實際用到的規則，供 Flutter 實作對照。frontmatter 的 token 為準，深淺色各一組（`-dark`、`-light` 後綴，對應 CSS 的 `.t-dark`、`.t-light`）。設計稿頁面的外框（手機殼、`body.doc` 的 `#2A2A2D` 展示底）只是展示用，不屬於產品。

## Overview

**Creative North Star: "摺起來的卡帶 J-card"**

介面像一張摺起來的卡帶曲目卡：曲目密排、時長對齊成一欄，一條摺線把已播和接下來分開。底色中性，文字像墨，列與列只用髮絲線分隔，不用卡片。音源是線框文字標籤，VIP 是唯一的實心金色。層級只靠疊放：玻璃浮在實心內容之上，內容本身不加陰影。

密度承襲舊版：一屏多首，序號、封面、曲名、歌手、音源、時長都在列上。封面不染色。主次只用字級與字重區分。

**Key Characteristics:**
- 中性深／淺底，強調色為單一 token，只標互動與目前狀態。
- 固定列高，4pt 網格，等寬數字欄。
- 玻璃只給浮動控制層；書脊與摺線是招牌。
- 深淺色同等設計，預設跟隨系統。

## Colors

中性墨色加一個可自選的強調色；金色只屬於 VIP 與試聽。

### Primary
- **FMP 紫** (`accent`，深色 #CFBCFF／淺色 #6750A4)：互動與目前狀態（目前曲目的序號與曲名、焦點框、主按鈕、導覽選中、摺線）。`on-accent` 為其上的文字色。`accent-soft` 為選中背景。
- **強調色預設**（淺色值／深色值）：預設紫 #6750A4／#CFBCFF、靛藍 #3F51B5／#BAC3FF、藍 #0061A4／#9FCAFF、青綠 #006A6A／#4CDADA、綠 #006E1C／#78DC77、橙 #7C5800／#F5BF48、紅 #BA1A1A／#FFB4AB、粉 #984061／#FFB0C8。黃 #F9A825 在淺色底上對比不足（與白字、與底色都不足），已劃掉，不在可選清單。

### Secondary
- **VIP 金** (`vip` #E3B341，on-vip #241A00)：VIP 標籤的實心底，兩個主題同值。
- **試聽** (`trial`，深色 #E3B341／淺色 #8A6100)：試聽標籤的線框與字，淺色改深以保持對比。

### Neutral
- **bg／bg2**：底與第二層底（面板、導覽軌、桌面側欄）。
- **fg／fg2／fg3**：主要文字、次要文字、序號與已播／不能播。
- **line／line-strong**：列的髮絲線；標籤、分段、摺線的較強線。
- **hover／pressed**：中性半透明填色，列的滑鼠移入與按下。
- **played**：書脊已播段落的中性陰影（不帶強調色）。
- **crease-hi／crease-lo**：摺痕兩側一明一暗的 1px 線。
- **glass／glass-edge／glass-hi**：玻璃底、邊線、頂部內高光；皆為無色中性。
- **error**：錯誤文字色。

### Named Rules
**The One Accent Rule.** 強調色只有一個 token，使用者從預設清單選；玻璃與底色永遠不帶強調色。
**The Only Solid Tag Rule.** VIP 是唯一實心標籤；其他標籤（音源、試聽、需登入）一律線框。
**The Dim Login Rule.** 需登入的曲目，整列（封面 opacity .45、曲名、歌手、時長、序號改 fg3）在所有列表變淡，點了引導登入。

## Typography

**字型：** 單一系統字族 `-apple-system, BlinkMacSystemFont, "PingFang TC", "Microsoft JhengHei UI", "Noto Sans TC", Roboto, sans-serif`，不引入網路字型。
**等寬：** `ui-monospace, "SF Mono", "Cascadia Mono", Menlo, monospace`，只用於時長與計時。

**Character：** 無襯線、中性，靠字級與字重分主次；全域 `tabular-nums`，數字對齊成欄。字級跟系統字級設定縮放。

### Hierarchy
- **h1**（700、32px、行高 38–40px）：手機大標題、桌面歌單標題。
- **h2**（700、26px、行高 32px）：頁標題。
- **h3**（700、20px）：區段、詳情面板曲名。
- **title**（600、17px）：標題列。
- **body**（500、15px、行高 1.3）：曲名；書脊曲名 14px/600。
- **small**（400、13px）：說明。
- **meta**（400、12px）：歌手、序號、播放量；時長用等寬 12px。
- **caption**（500、11px）：標籤、導覽項、表頭、側欄分組標題（不轉大寫）。

### Named Rules
**The Mono Duration Rule.** 時長與計時一律等寬字型、右對齊成一欄。

## Layout

4pt 網格，常用間距 4、8、12、16、20、24、32。曲目列固定高度，不隨內容變：手機 60（封面 44）、桌面 52（封面 36）；桌面表頭 30。手機列 grid 為 序號 24／封面 44／文字／右側（音源標籤疊在時長上），列左右內距 8／20；桌面列欄位為 28、36、文字、84、56、72、52，內距 16／28。

寬度級距（Material 3）：
- **compact**（< 600）：底部分頁列；迷你播放器在上方（A）或浮動膠囊（B）。
- **medium**（600–839）：左側收合導覽軌，播放列在底部。
- **expanded**（≥ 840）：導覽軌（A）或浮動側欄（B）＋內容＋有目前曲目時的右側詳情面板（352px）。桌面稿欄寬：A 為 76／內容／352，B 為 256／內容／352。

### 外殼：採 A（擁有者 2026-11-08 選定）
- **A**：舊版結構換成玻璃。手機為底部分頁列（64px 膠囊）加其上的書脊，捲動不收合；桌面為 76px 導覽軌、右側詳情、底部浮動玻璃播放列（三邊內縮 12px、圓角 18）。
- **B**（未採用，稿留作參考）：Apple Music 式。手機為兩條浮動膠囊，搜尋獨立成右側 56px 圓鈕；往下捲時分頁列收成一顆顯示目前分頁的圓鈕，書脊移到中間；頂部沒有實心標題列，大標題跟著內容捲走，狀態列下方漸進淡出。桌面為內縮的實心側欄（256px）加浮動玻璃播放膠囊。
- 其餘頁面照 A 做；B 的規則不適用。

## Elevation & Depth

混合：以疊放分層。內容層全是實心、無陰影；浮動控制層用玻璃。玻璃配方：`background: var(--glass)`、`backdrop-filter: blur(22px) saturate(180%)`、1px `glass-edge` 邊線、`inset 0 1px 0 var(--glass-hi)` 頂部高光、外陰影 `glass-shadow`（深色 `0 10px 28px rgba(0,0,0,.38)`、淺色 `0 10px 28px rgba(0,0,0,.12)`）。B 頂部另有一條與底色同色的漸進淡出（`.edge`，96px 高，6px 模糊）取代標題列。

### Named Rules
**The Floating Glass Rule.** 玻璃只用在浮在捲動內容之上的控制層（書脊、分頁列、浮動膠囊、圓鈕）。底下沒有內容捲過的面，用實心。因此 B 的桌面側欄是實心（bg2＋髮絲邊線）：它下面沒有內容經過，玻璃在那裡只是裝飾。
**The No Content Shadow Rule.** 列、封面、面板不加陰影。

## Shapes

圓角：標籤 4、封面 6（桌面詳情大封面 10）、按鈕與控制 12、書脊 16、sheet 20。分頁列與搜尋圓鈕為全圓（膠囊）；桌面側欄 18、桌面播放列 18。列不用卡片，以 1px `line` 髮絲線分隔。封面為方形，不染色。

## Components

### 曲目列
固定高度，髮絲線分隔。目前曲目：序號與曲名用 `accent`。已播：曲名、歌手、時長用 fg3。不能播（需登入）：見 Dim Login Rule。右側為標籤（右對齊，間距 4）疊在等寬時長上。

### 標籤
11px/500、高 16px、內距 0 5px、圓角 4、1px `line-strong` 線框、字 fg2。音源（B站、YT、網易）為線框。**VIP** 為實心 `vip` 底、`on-vip` 字、700。**試聽** 線框與字用 `trial`。**需登入** 虛線框。

### 狀態
- **hover／pressed**：列背景用中性 `hover`／`pressed` 填色，不用強調色。
- **focus**：2px `accent` 外框；列為 offset -2px、圓角 8；按鈕與導覽項 offset 2px。
- **disabled**：按鈕 opacity .38。

### 按鈕
高 40、內距 0 18、圓角 12、14px/600。**主要**：`accent` 底、`on-accent` 字。**tonal**：`accent-soft` 底、fg 字。**outline**：1px `line-strong`、fg 字。

### 導覽
手機分頁項 78×54、圓角 27、11px/500；選中為 `accent` 字加 `accent-soft` 底。桌面導覽軌項 60 寬、圓角 14；側欄項高 34、圓角 10、14px。分段控制：圓角 10、1px `line-strong`，選中 `accent-soft` 底。

### 書脊（迷你播放器，招牌）
玻璃、高 58（B 的中央收合版 56）、圓角 16。已播段落以 `played` 中性陰影鋪在左側。**摺線**：一條 2px `accent` 左線，只在上下各 12px 露出（遮罩），不壓文字；兩側 1px 暗（`crease-lo`）、亮（`crease-hi`）做出摺痕。桌面播放列（高 72／68，圓角 18）用同一摺線。

### 摺線（佇列）
`foldrule`：不寫字，一條 1px `line-strong` 橫線，下方有 `glass-hi` 的 1px 高光，左端一截 2×12px 強調色刻度（呼應書脊的摺線）。放在正在播的那首下方：以上是播過的（變淡），以下是接下來的。
- 佇列畫面永遠是播放順序（隨機時重排成打亂後的順序，關閉隨機恢復原順序），所以摺線在每種模式下都成立。
- 開啟佇列頁時自動捲到正在播的那首；點標頭的「佇列」標題可隨時捲回去（同 iOS 點狀態列回頂端的習慣，沒有另外的按鈕）。
- 佇列標頭寫總首數與剩餘時間（`42 首 · 剩 1 小時 52 分`），右側是兩顆獨立的切換鈕：隨機（開／關）、循環（不循環 → 列表循環 → 單曲循環），可以同時開；開啟時 `accent-soft` 底、強調色字（`.tog.on`）。播放列上的同兩顆是圖示鈕，開啟時強調色加下方 4px 圓點（`.it.on`）。

## Do's and Don'ts

### Do:
- **Do** 用 `accent` 標互動與目前狀態，並讓使用者從預設清單改它。
- **Do** 時長用等寬、右對齊；全域 tabular-nums。
- **Do** 以固定列高與髮絲線分列；用字級與字重分主次。
- **Do** 玻璃只給浮動控制層，內容實心。
- **Do** hover／pressed 用中性填色，focus 用 2px 強調色外框；桌面完整鍵盤操作要看得到焦點。

### Don't:
- **Don't** 讓玻璃或底色帶強調色。
- **Don't** 增加第二種實心標籤；音源標籤不上色。
- **Don't** 給列、封面、面板加陰影，或用卡片分列。
- **Don't** 把黃 #F9A825 放進淺色強調色清單。
- **Don't** 做大封面、低密度、一屏五首的列表。

## 未決與未使用

- 桌面右側詳情面板目前是一般實心面板；「J-card 內頁」式的處理尚未設計。
- 側欄標籤的印刷字樣（卡帶側標的排字）尚未設計。
- 設計稿未見的 token：陰影以外的動態時長與 easing、字重之外的字距、錯誤狀態元件。

## 全螢幕播放頁

稿：`player.html`。結構照舊版：上方收合鈕、加入歌單、資訊、更多（桌面多音量）；中間封面，點封面切到歌詞；下方曲名與歌手（附音源標籤）、進度、播放控制；手機最下方一顆玻璃膠囊切「歌詞」「佇列」，桌面改在頂列右側（見下）。

- **背景跟著封面取色**：整個 App 只有這裡帶封面色。用封面的主色做兩團大範圍徑向漸層，深色主題壓一層 `rgba(10,12,16,.50→.78)`，淺色主題蓋一層 `rgba(248,247,244,.62→.82)`。文字改用 `.onart` 的前景色（深：`#F7F6F3` 與其 72%、50%；淺：`#141416` 與其 68%、48%）。
- **進度**：已播段用前景色實心，未播段 `line-strong`；播放頭是 2×20px 強調色摺線加摺痕（同書脊）。時間用等寬字，右側顯示剩餘時間。
- **播放鈕**：72px 前景色實心圓；隨機與循環是圖示鈕，開啟時強調色加小圓點（同 `.it.on`）。
- **歌詞**：目前行用前景色粗體，其他行 `fg3`；翻譯在原文下方小一級。上下以遮罩淡出。桌面寬度 ≥ 840 且高度 ≥ 520 時分兩欄：左欄封面與控制，頂列右側最前面兩顆圖示鈕「歌詞」「佇列」（與其他工具以細線隔開，選中的亮強調色加小圓點，同 `.it.on`）決定右欄顯示歌詞（右下角標歌詞來源與偏移）或佇列（同佇列頁的列與摺線）。
- 第一版不做倍速與輸出裝置選擇（brief §6），畫面上沒有這兩個控制。
