# 02: 插件 id 與曲目 id 成對的型別

Status: ready-for-agent
Blocked by: None
讀: brief §5.3；`GLOSSARY.md`〈曲目〉；`app/lib/domain/track.dart`；spec〈共同規則〉

## What to build

曲目的身分改成一個型別，把提供它的插件 id 和曲目 id 綁在一起，取代現在的裸字串 `Track.source` 加 `Track.id`。佇列、臨時播放、持久化與系統媒體控制都拿這個型別當鍵，之後找插件、寫 log、存資料庫都從它來。純 Dart，放 `domain/`。名詞缺的話照〈擁有者確認〉補進 `GLOSSARY.md`。

## 驗收

- [ ] 新型別有相等與 hash，可以當 map 的鍵；有單元測試。
- [ ] `Track`、插件宿主找插件、`Playback`、log 的 `logId` 都改用它，沒有地方再單獨傳插件 id 字串。
- [ ] 依賴規則測試照過（Dart 端沒有音源識別碼的字面值）。
- [ ] 四平台實跑搜尋並播放一首。
- [ ] 全部檢查綠燈（`dart run tool/check.dart` 完整版）。

## Comments
