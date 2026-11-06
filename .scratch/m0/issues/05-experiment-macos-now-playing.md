# 05: 實驗：macOS 的 Now Playing 接法

**What to build:** 決定 macOS 上的系統媒體控制怎麼接（brief §6、§17），讓 M1 能直接實作。候選至少包括 `audio_service` 在 macOS 的現況與自己用 platform channel 接 `MPNowPlayingInfoCenter`、`MPRemoteCommandCenter`。結論給擁有者確認後寫回 brief。

讀：brief §6、§17、事實 R4、M4、I5；plan §1.4、§2（macOS 的驗證怪癖）、§6 P2；spec〈共同規則〉的實驗規則

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] 實驗程式在 `scripts/experiments/` 底下，可重跑，附怎麼跑的說明。
- [ ] 每個候選實測：顯示標題、封面、播放狀態與進度；接收播放、暫停、上一首、下一首、seek。macOS 27 不讓第三方讀 Now Playing，驗證方式（目測、系統 log）寫明。
- [ ] 重驗事實 R4、M4；查到的新事實附來源寫進 brief §18。
- [ ] 結論草稿（用哪個接法、它的限制）先給擁有者確認；確認後寫進 brief §6、brief §17 移除該條、plan §1.4、§6 P2 更新。
