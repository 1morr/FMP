---
version: 1
slug: "shell-a-html"
primary_target: "shell-a.html"
related_targets: ["shell-b.html","system.html"]
---

# Surface brief：App 外殼與設計系統（D 設計稿第一步）

範圍：設計系統（色彩、字級、間距、寬度分級、玻璃與實心材質）＋ App 外殼 A／B，各做手機與桌面、深淺色。Visitor mode：Operate。
受眾與工作：擁有者與少數外部使用者；手機通勤時換歌、看佇列、加入歌單，桌面背景播放時整理歌單。
限制：brief §11（以舊版為底、玻璃只在控制層、外殼 A／B）、PRODUCT.md 的 Brand Commitments；示意曲目與數字是假資料。
未決：外殼選 A 或 B（擁有者看稿後定）；B 的導覽項目以稿中提案為準。

## Direction contract

THESIS: FMP 的介面是一張摺起來的卡帶 J-card：曲目密排、時長對齊成一欄、一條摺線把已播和接下來分開。拒絕類別預設的大封面、低密度、一屏五首的 Apple Music 列表。

OWN-WORLD: 中性底（深 #121214／淺 #F5F5F3），墨色文字，髮絲線分列；時長與曲數用等寬數字欄；音源是線框文字標籤，VIP 是唯一的實心金色標籤；強調色是單一 token（預設 FMP 紫，可自選），只標互動與目前狀態；玻璃是無色的中性層，只用在浮動控制層。

STORY: 使用者一眼看到正在播什麼、播到哪裡、接下來是什麼；列表上直接看出每首歌的音源與能不能播；不必學新的頁面地圖。

FIRST VIEWPORT: 手機歌單詳情：頂部返回與小封面標題列，下面是 60pt 固定高的曲目列（序號、44pt 封面、曲名與歌手、右側音源與存取標籤疊在等寬時長上）；底部浮著兩層玻璃：書脊式迷你播放器（已播段落陰影＋摺線標進度）和分頁列。招牌：書脊與摺線，佇列頁以摺線分 A 面／B 面。

FORM: 卡帶 J-card，自己排序清單的第 5 名（抽籤指定）。seed:ee00081b4b10368c

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

採納的加強：層級只靠疊放（玻璃在實心之上，內容不加陰影）；封面不染色、髮絲線分列不用卡片；固定列高、4pt 網格；主次只用字級與字重。
