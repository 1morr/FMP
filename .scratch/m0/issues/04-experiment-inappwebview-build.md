# 04: 實驗：flutter_inappwebview 6.1.5 四平台建置

**What to build:** 確認登入 WebView 要用的 `flutter_inappwebview` 6.1.5 在目前的工具鏈（Flutter 3.47.5、Xcode 27.1、AGP 9、VS 2026）上四平台都建得起來並能開一個網頁，讓 M2 的登入票不用再踩建置問題。只驗建置與開頁，不做登入。

讀：plan §1.4、§2、§7；brief 事實 A4、W8、M8、K8、R1、T1；spec〈共同規則〉的實驗規則

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] 實驗專案在 `scripts/experiments/` 底下，可重跑，附怎麼跑的說明。
- [ ] 四平台各自建置成功並開出一個公開網頁，讀回畫面為證。
- [ ] 重驗事實 A4、W8、M8、K8：要加的旗標、編譯選項與 lock 檔的坑，逐條寫明是否仍需要；更新 brief §18 的寫法與【待重驗】標記。
- [ ] 某平台建不起來時，記下錯誤與試過的做法，結論寫進 brief，不改用 beta 版（要用 beta 先問擁有者）。
