# 12: 預載下一首

Status: ready-for-agent
Blocked by: 11
讀: brief §6、§9；architecture〈快取〉；事實 I4、K4、W3；`app/lib/playback/audio_backend.dart`；spec〈共同規則〉

## What to build

快到下一首時先解析它的串流，再讓音訊後端先緩衝開頭，切歌時不必等連線（brief §6）。音訊後端介面現在一次只裝一首，要改成能先裝好下一首（`mattpocock-skills:codebase-design`，兩個實作都改；just_audio 跳到已預載的項目用 seek、不重開，事實 I4；media_kit 要 `prefetch-playlist=yes`，事實 K4）。

第一步（擁有者定）：在四個平台量「按下一首到出聲」，並查 macOS 點下到出聲約 15 秒（M0 票 12 的觀察）慢在哪裡，原因寫進事實、數字寫進 `docs/research/`；數字給擁有者定預載後的目標，記成一條決定。

## 驗收

- [ ] 預載前四平台的「按下一首到出聲」與 macOS 慢的原因已寫進 `docs/research/` 與事實；擁有者定了目標。
- [ ] 預載有測試：快到下一首時解析並緩衝；下一首改變（拖動、下一首播放、隨機）時換掉預載；預載的網址照〈快取〉檢查過期。
- [ ] 預載後再量一次，四平台達到擁有者定的目標，數字寫進 `docs/research/`。
- [ ] 四平台實跑讀回切歌。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
