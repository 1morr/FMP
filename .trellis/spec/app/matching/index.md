# 匹配（`app/lib/core/matching/`）

改評分核心、詞表或繁簡字表時適用。契約、權重的理由與閘門見 `app/AGENTS.md` § 匹配；
為什麼有這個模組，見 ADR 0019 §決定 5、6 與 M4 design §8.1、§8.2。這裡只寫怎麼改。

## 結構

```
lib/core/matching/
  matching.dart          # 公開介面：MatchQuery、MatchCandidate、MatchScore、Ranked、score、rank、firstArtist；權重與門檻
  normalize.dart         # 折疊（NFKC → 小寫 → 繁簡）、拆括號、裝飾與版本詞表、拆歌手
  ts_characters.g.dart   # 產生檔：繁→簡字表與 OpenCC 授權全文
tool/opencc/             # 釘 commit 的 TSCharacters.txt、LICENSE、產生器
test/core/matching/
  match_corpus.dart      # 校準語料（資料）
  match_corpus_test.dart # 語料全綠
```

呼叫端只 import `matching.dart`；`normalize.dart` 的函式是給它與測試用的。第一個呼叫端是外部匯入
（`lib/library/external_import.dart`）：`TrackSummary` 的標題、`uploader`（歌手原字串）、時長轉成 `MatchQuery`，
搜尋結果轉成 `MatchCandidate`，同分的先後由它把各目標音源的結果依目標順序串起來決定。

- `firstArtist` 給搜尋關鍵字用：回原文（不折疊），分隔符跟 `splitArtists` 同一組但不分大小寫、另認全形 `，；`。改
  `_artistSeparator` 時 `_rawArtistSeparator` 一起改。

## 改權重、門檻或詞表

1. 先把讓你想改的情形寫進 `match_corpus.dart`：真實的公開歌名、常見的上傳標題寫法、
   約略的時長，手寫、不連網。該選的、不該選的、排序的各放對的清單；`note` 寫它代表的情形。
2. 跑 `flutter test test/core/matching`，看紅的是哪幾條、各分項是多少（失敗訊息印出
   `MatchScore`）。
3. 只改能讓整份語料全綠的最小改動：詞表加一個詞優先於改權重。改權重或門檻時在
   `app/AGENTS.md` § 匹配寫下是哪個案例逼的。
4. 分不出來的（兩個案例的分數一定一樣）放 `corpusKnownFalseMatches` 並寫原因，不要
   為它犧牲該選的案例。

- 詞表是繁簡統一之後的寫法：寫簡體（`高音质`，不是 `高音質`）。拉丁字的詞會比字的邊界，
  CJK 的詞直接比子字串，所以 CJK 的詞要夠長、不會是歌名的一部分。
- 裝飾詞兩邊都去掉，不算版本；版本詞兩邊不同時打折。一個詞放錯邊，會讓 Live 版與原版同分，
  或讓 `【MV】` 被當成另一個版本。

## 換 OpenCC 的版本

1. 用 `git ls-remote https://github.com/BYVoid/OpenCC.git refs/heads/master` 取 commit，
   以那個 commit 的 raw 網址下載 `data/dictionary/TSCharacters.txt` 與根目錄的 `LICENSE`
   （有 `NOTICE` 一併）到一個空目錄，看過格式（每行「繁體字 TAB 候選…」）再複製。
2. `TSCharacters.txt` 開頭保留四行 `# FMP:`，改掉網址、commit 與日期；其餘照抄。
3. `dart run tool/opencc/generate_ts_characters.dart`；產生器拒絕多字的鍵或值、重複的鍵、
   循環的串接。看 `ts_characters.g.dart` 的 diff，再跑語料。

## Quality Check

- `flutter test test/core/matching test/app/licenses_test.dart` 全綠。
- 改了 `tool/opencc/` 就重新產生並提交 `ts_characters.g.dart`。
- `lib/core/matching/` 沒有 import 上層（`fmp_layer_imports`）。
