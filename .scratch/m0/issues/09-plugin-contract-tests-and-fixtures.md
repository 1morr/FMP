# 09: 插件契約測試與 fixture 錄製

**What to build:** 每個插件都套同一套契約測試，用錄好的 fixture 重播音源的回應，不連網就能證明插件的每個插件能力照宿主 API 的約定回傳。附錄製工具：手動執行時打真實音源，寫檔前經過遮蔽函式。這張票讓 bilibili 的搜尋能力納入契約測試，並加一條手動執行的 `live` 冒煙測試。

讀：plan §3；ADR 0038〈如何確認〉；brief §5.3、§14；`AGENTS.md`〈公開 repo〉；票 08 的 Comments；spec〈共同規則〉

**Blocked by:** 08

**Status:** ready-for-agent

- [ ] 契約測試依插件宣告的插件能力自動套用：插件宣告了搜尋，就跑搜尋的契約；新增插件不用改契約測試本身。
- [ ] fixture 重播時零聯網；fixture 對不上請求時測試直接失敗並說明哪個請求沒有 fixture。
- [ ] 錄製工具寫檔前經過票 06 的遮蔽函式；檢查提交的 fixture 不含 cookie、token、簽名網址的值，造一份含敏感值的 fixture 證明會紅。
- [ ] bilibili 搜尋的 fixture 已錄製並提交，契約測試通過。
- [ ] `live` 冒煙測試：bilibili 搜尋一條，預設跳過；手動執行一次並貼輸出。錄製與冒煙測試的指令寫進 `AGENTS.md` 或 plan §3。
- [ ] `dart run tool/check.dart` 完整版綠燈。
