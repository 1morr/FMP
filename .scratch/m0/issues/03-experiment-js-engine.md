# 03: 實驗：JS 引擎

**What to build:** 用實驗決定插件跑在哪個 JS 引擎：`fjs` 或 `flutter_js`（加自編 QuickJS）。標準照 brief §17：四平台同一引擎、能中斷無窮迴圈、能設記憶體上限、支援 async。也量出引擎與 isolate 的配置（plan §1.1）。結論給擁有者確認後寫回 brief 與 plan。

讀：brief §5.3、§17、事實 K7、R6、R7；plan §1.1、§1.4、§6 P2；ADR 0038；spec〈共同規則〉的實驗規則

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] 實驗程式在 `scripts/experiments/` 底下，可重跑，附怎麼跑的說明；換版本時能重量。
- [ ] 兩個候選在四平台各自實測四項標準，另測一次 async 宿主呼叫（JS 呼叫 Dart 提供的 async 函式並拿回結果）；結果做成表，含版本號與平台。
- [ ] 重驗事實 K7，更新它在 brief 的寫法與可信度。
- [ ] 結論草稿（選哪個、isolate 配置、已知限制）先給擁有者確認；確認後寫進 brief §18（事實）、brief §17 移除該條、plan §1.1、§1.4、§6 P2 更新。
- [ ] 如果兩個都不滿足四項標準：停下來回報，不自己放寬標準。
