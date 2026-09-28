# 額外功能的事實查證：逐字歌詞、逐字渲染、桌面穿透／鎖定、Android 懸浮與狀態列、iOS

- 查證日：**2026-09-28**（本檔所有條目均為此日查證）
- **本檔只寫事實與出處，不含設計建議。** 查不到寫「查不到」；由間接證據推論者標「**推測**」。
- 方法限制：**未呼叫任何音樂平台的真實 API**；**未對任何裝置下 adb / 模擬器指令**（需要實測才能定論的條目一律標「需實測」）。歌詞文本一律以佔位符表示（「字」「word」），不貼真實歌詞內容。
- GitHub 連結一律為**固定 commit SHA 的 permalink**。

## 與同目錄其他研究的關係（避免重複）

| 檔案 | 內容 | 本檔如何處理 |
|---|---|---|
| `prior-art.md` | 產品面：各家歌詞功能、插件化、匹配與改選、桌面歌詞有無 | 已查過的產品層結論**不重複**，只補「實作層」細節 |
| `packages-and-platform.md` | 套件與平台：多視窗、`window_manager` 各平台能力、Android SAW 權限、iOS 預算、Dart LRC 套件 | 標註「見 §」處僅補新事實 |
| `current-state.md` | 舊 FMP 的歌詞實作 | 不涉及 |
| `ai-decision-models.md` | 決策模型／reranker | 不涉及 |

## 標記約定

| 標記 | 意義 |
|---|---|
| 逐字 | 直接引用來源文字 |
| 一手 | 官方文件、原始碼、官方 API |
| 二手 | 部落格、論壇、教學站 |
| 推測 | 非來源明言，由間接證據推得 |
| 查不到 | 本次查證未找到來源 |

## 引用來源 SHA 一覽

| 專案 | repo | commit SHA |
|---|---|---|
| LX Music Desktop | `lyswhut/lx-music-desktop` | `ad95d5091c9ed689fa72b5e5c849df65f5a679ce` |
| LX Music Mobile | `lyswhut/lx-music-mobile` | `fb8480728d875fa5e0da25eebd3a26bb71723aae` |
| Lyricify-Lyrics-Helper | `WXRIW/Lyricify-Lyrics-Helper` | `cabe0b71d443a9b882a35c60c4f7f21addcbe751` |
| AMLL | `amll-dev/applemusic-like-lyrics` | `86200dead453bb067e554e989110cbadca8d4756` |
| Namida | `namidaco/namida` | `acb1e1622600440cc793f389f497e6771c732c5e` |
| BetterLyrics | `jayfunc/BetterLyrics` | `97629ddf085877cdc90de8cb56006a023320fe00` |
| go-musicfox | `anhoder/go-musicfox` | `12169a71098f8b8607bcf655eaddabf57ca14daf` |
| ESLyric-LyricsSource | `Robotxm/ESLyric-LyricsSource` | `ebaf516f01292895a02c62383717c7500acf95f1` |
| MediaIsland | `bywhite0/MediaIsland` | `c5afb2cff4f331dec70c0c99c96a6e9b738cb81d` |
| kotonoha | `locez/kotonoha` | `175cfcc04ffb67fbbba26c76437275083090233a` |
| goqdes | `lxsrcs/goqdes` | `b1886b062367ff15466d9d2d1c6ff4b1050639f9` |
| LyricTools | `blockshy/LyricTools` | `76042ecd492dd07444fab9171e6f67fa70f81416` |
| flutter_lyric | `ozyl/flutter_lyric` | `b5151e6344e39f35dbc69d2e6d531464d27f9207` |
| flutter_overlay_window | `X-SLAYER/flutter_overlay_window` | `111b21041ac3250a965a8ce1705e210c414a7a62` |
| audio_service | `ryanheise/audio_service` | `da405ddd07840d5861a09ab252cce6f40cc95a0b` |
| window_manager | `leanflutter/window_manager` | `4080b59c0b1084c6085f1613c660382cd164ad76` |
| desktop_lyrics | `587626/desktop_lyrics` | `e92aa0e2c0831285570974883f1dd99b36354958` |
| MusicFree | `maotoumao/MusicFree` | `d118b18b3d0c904400f7eea7bf99c0ceec6c1aee` |
| StatusBarLyric | `Block-Network/StatusBarLyric` | `bd2ec998c4a4d667d5e0602923bdd9cfec330a54` |
| lyricon | `tomakino/lyricon` | `c93da0eef8b7aee015d2670b48e9e262fcf72cd1` |
| SuperLyric | `HChenX/SuperLyric` | `bfca70931651f9c5acc69e088140cc1210780405` |
| SuperLyricApi | `HChenX/SuperLyricApi` | `b7ad6e48360cb5e054b523e9f9dc5727d99755af` |
| Lyric-Getter | `xiaowine/Lyric-Getter` | `9e6d3f72694b08f56dce0b1a4524e18dc56f5c09` |
| HiMoriafly | `Moriafly/HiMoriafly` | `98e04b2cf53aa65fa998a424cf328330fe345044` |

> 註：`Binaryify/NeteaseCloudMusicApi` 在查證日**已被清空**（root 只剩 `README.MD`，`module/` 不存在），無法作為出處；網易雲一節改用 go-musicfox 與 LX 兩個獨立實作交叉比對。

---

# §1 逐字（word-level）歌詞的取得與正規化

## 1.1 網易雲 YRC

**取得**（LX desktop）：`POST https://interface3.music.163.com/eapi/song/lyric/v1`，參數 `{ id, cp:false, tv:0, lv:0, rv:0, kv:0, yv:0, ytv:0, yrv:0 }`；go-musicfox 走 `https://interface.music.163.com/eapi/song/lyric/v1`，同參數但值以**字串**送出，註解稱其為 “Netease 'lyric/new' API”。兩份實作**都送 `yv`**，且全 0 仍拿得到 yrc。
→ [LX `src/renderer/utils/musicSdk/wy/lyric.js`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/renderer/utils/musicSdk/wy/lyric.js)、[go-musicfox `utils/netease/lyric.go`](https://github.com/anhoder/go-musicfox/blob/12169a71098f8b8607bcf655eaddabf57ca14daf/utils/netease/lyric.go)

**回應欄位**（兩份實作一致，皆為 `.lyric` 字串）：

| 欄位 | 內容 |
|---|---|
| `lrc.lyric` | 行級原文 |
| `tlyric.lyric` | 行級翻譯 |
| `romalrc.lyric` | 行級羅馬音 |
| `yrc.lyric` | **逐字原文** |
| `ytlrc.lyric` | **逐字翻譯**（同 YRC 格式） |
| `yromalrc.lyric` | **逐字羅馬音**（同 YRC 格式） |

`kv`（karaoke）對應的回應欄位名：**查不到**（兩份實作都沒讀）。各旗標字母的逐字語意**查不到**（無規範）；`l/t/r/y/k` 的推測對應見來源註解 → **推測**。
→ [go-musicfox `internal/structs/lyric.go`](https://github.com/anhoder/go-musicfox/blob/12169a71098f8b8607bcf655eaddabf57ca14daf/internal/structs/lyric.go)

**YRC 行格式**（LX 正則 `lineTime: /^\[(\d+),\d+\]/`、`wordTime: /\(\d+,\d+,\d+\)/`）：

```
[行開始ms, 行長度ms](詞1開始ms, 詞1長度ms, 0)字(詞2開始ms, 詞2長度ms, 0)word…
```

- **時間單位 = 整數毫秒**；**詞時間是絕對時間**（不是相對行首）。證據：LX 轉 lxlrc 時做的是「詞絕對 ms − 行絕對 ms」；Lyricify 產生音節時直接 `new SyllableInfo(text, wordTimespan, wordTimespan + wordDuration)`，**沒有再加行首**。
- **詞標籤第三欄固定為 `0`**（兩份實作都忽略；AMLL 正則直接寫死 `,0)`）。
→ [AMLL `formats/yrc.ts`](https://github.com/amll-dev/applemusic-like-lyrics/blob/86200dead453bb067e554e989110cbadca8d4756/packages/lyric/src/formats/yrc.ts)、[Lyricify `Parsers/YrcParser.cs`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/cabe0b71d443a9b882a35c60c4f7f21addcbe751/Lyricify.Lyrics.Helper/Parsers/YrcParser.cs)

**metadata / credits 行**：除歌詞行外，每行一個 JSON 物件（行首 `{`）。LX 判定 `info: /^{"/`，取 `info.t`（ms）與 `info.c.map(t => t.tx).join('')`；Lyricify 解析成 `CreditsInfo`，並在首個 credit 以「作詞」開頭時抽出 `Writers`。其他欄位語意**查不到**。

**降級**：LX **不留逐字翻譯**——`info.tlyric = this.fixTimeTag(result.lyric, lines.join('\n'))` 傳入的是**行級** `result.lyric`。逐字翻譯的詞時間是否與主 YRC 逐詞對應：**查不到**。

## 1.2 QQ 音樂 QRC

**取得**：`POST https://u.y.qq.com/cgi-bin/musicu.fcg`，body 內 `req.param` 帶 `{ format:'json', crypt:1, qrc:1, roma:1, trans:1, songID, … }`；回應位置 `body.req.data.lyric` / `.trans` / `.roma`，三者皆為**加密字串**。Lyricify 的回應 model `QqLyricsResponse { Lyrics, Trans }` —— **只有兩個欄位，沒有 roma**。
→ [LX `tx/lyric.js`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/renderer/utils/musicSdk/tx/lyric.js)、[Lyricify `Decrypter/Qrc/Model.cs`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/cabe0b71d443a9b882a35c60c4f7f21addcbe751/Lyricify.Lyrics.Helper/Decrypter/Qrc/Model.cs)

**金鑰（固定，24 bytes ASCII）**：`!@#)(*$%123ZXC!@!@#)(NHL` —— **四份獨立來源一致**（LX byte array、Lyricify 字面字串、AMLL 拆三段各 8 bytes、ESLyric `createUtf8Bytes`）。
→ [LX `tx/qrcDecode.js`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/renderer/utils/musicSdk/tx/qrcDecode.js)、[AMLL `formats/eqrc/constants.ts`](https://github.com/amll-dev/applemusic-like-lyrics/blob/86200dead453bb067e554e989110cbadca8d4756/packages/lyric/src/formats/eqrc/constants.ts)、[ESLyric `current/qrc/lib/qrc-decryptor/qrc-decryptor.js`](https://github.com/Robotxm/ESLyric-LyricsSource/blob/ebaf516f01292895a02c62383717c7500acf95f1/current/qrc/lib/qrc-decryptor/qrc-decryptor.js)

**演算法**：3DES（DES-EDE3）、ECB、8-byte 分塊、零填充，之後 **zlib inflate**。AMLL 解密序 `D(K3) → E(K2) → D(K1)`；輸入是**十六進位字串**。步驟：hex→bytes（長度需為 8 倍數）→ 每 8 bytes 3DES 解密 → zlib inflate → 去 UTF-8 BOM → UTF-8 解碼。
→ [AMLL `formats/eqrc/index.ts`](https://github.com/amll-dev/applemusic-like-lyrics/blob/86200dead453bb067e554e989110cbadca8d4756/packages/lyric/src/formats/eqrc/index.ts)

**非標準 DES S-box（陷阱）**：QRC 用的是 DES 變體，**`S2[23]=15`、`S4[53]=10`**（標準為 14、1）。LX 原始碼註解明寫此事，AMLL 與 ESLyric 的陣列人眼核對一致（**三份一致**）。→ **不能直接用現成 DES 函式庫解 QRC**。

**解密後格式**：外層是 XML（`<QrcInfos><QrcHeadInfo/><LyricInfo><Lyric_1 LyricType="1" LyricContent="…"/>`），`LyricContent` 是**屬性**；剝殼後為：

```
[行開始ms, 行長度ms](詞1開始ms, 詞1長度ms)字(詞2開始ms, 詞2長度ms)word…
```

- 詞標籤**只有兩個欄位**（沒有 YRC 的第三個 `0`）。時間單位 = 整數毫秒；**詞時間絕對**（Namida `span.start = int.parse(time[0])`、Lyricify `endTime = startTime + duration` 皆未加行首）。
→ [AMLL `formats/qrc.ts`](https://github.com/amll-dev/applemusic-like-lyrics/blob/86200dead453bb067e554e989110cbadca8d4756/packages/lyric/src/formats/qrc.ts)、[Namida `parser_qrc.dart`](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/packages/lyrics_parser/parser_qrc.dart)

**翻譯 / 羅馬音**：來源是同一份 XML 內的另一個 `Lyric_1` 節點（以 `LyricType` 區分）或回應的 `.trans` / `.roma`。LX 剝殼後直接餵 `lrc-file-parser`，**沒有做詞級對齊**。`LyricType` 其他值的語意、`trans`/`roma` 是行級還是逐字：**皆查不到**（未取樣本）。

## 1.3 Kugou KRC

**magic**：4-byte ASCII `krc1`（kotonoha `KRC_MAGIC = b"krc1"`；MediaIsland 註解同）。LX 只寫 `subarray(4)` 丟掉前 4 bytes，未命名該 magic。
→ [kotonoha `krc_parser.py`](https://github.com/locez/kotonoha/blob/175cfcc04ffb67fbbba26c76437275083090233a/src/kotonoha/lyrics/krc_parser.py)、[MediaIsland `KrcDecrypter.cs`](https://github.com/bywhite0/MediaIsland/blob/c5afb2cff4f331dec70c0c99c96a6e9b738cb81d/MediaIsland/Services/Lyrics/Crypto/KrcDecrypter.cs)

**金鑰（16 bytes，三份一致）**：

```
0x40,0x47,0x61,0x77,0x5e,0x32,0x74,0x47,0x51,0x36,0x31,0x2d,0xce,0xd2,0x6e,0x69
```

（kotonoha 註解：「it is part of the file format, not a secret」。）

**完整解密步驟**：① base64 解碼 → ② **丟掉前 4 bytes** → ③ 逐 byte XOR `b[i] ^= key[i % 16]`（索引自 body 起點重新起算）→ ④ **zlib inflate** → ⑤ UTF-8 解碼。
- Lyricify 另有一步**解壓後再去掉第 1 個字元**（`res[1..]`）——這與 LX 的 `subarray(4)` 是**不同階段**，勿混淆。
- 取檔 URL（Lyricify）：`https://lyrics.kugou.com/download?ver=1&client=pc&id={id}&accesskey={accesskey}&fmt=krc&charset=utf8`
→ [LX `src/common/utils/lyricUtils/kg.js`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/common/utils/lyricUtils/kg.js)、[Lyricify `Decrypter/Krc/Decrypter.cs`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/cabe0b71d443a9b882a35c60c4f7f21addcbe751/Lyricify.Lyrics.Helper/Decrypter/Krc/Decrypter.cs)

**解密後格式**：可能先有一行 `[id:$xxxx]` 標頭（LX `headExp = /^.*\[id:\$\w+\]\n/`）。

```
[行開始ms, 行長度ms]<詞1開始ms, 詞1長度ms, 0>字<…>word…
```

- 時間單位 = 整數毫秒；**詞時間相對行首**（與 YRC/QRC 相反）。證據：Lyricify `StartTime = lineStart + start`、`EndTime = lineStart + start + duration` —— **有加行首**。
- 拆詞（Lyricify）：`line[(line.IndexOf(']')+1)..].Split(",0>")`，第一個詞去掉開頭的 `<`。純行級＝刪掉所有 `<d,d>`。
→ [Lyricify `Parsers/KrcParser.cs`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/cabe0b71d443a9b882a35c60c4f7f21addcbe751/Lyricify.Lyrics.Helper/Parsers/KrcParser.cs)

**`[language:<base64>]` metadata**：base64 解出 JSON，`json.content[]` 每項有 `type` 與 `lyricContent`：**`type:0` = 羅馬音、`type:1` = 翻譯**。`lyricContent` 是「每行一個字串陣列」的陣列。**KRC 的翻譯/羅馬音是行級，不是逐字**——證據：LX 用**同一個行序號 `i`** 把主歌詞的行時間標籤前置到 `rlyric[i]` / `tlyric[i]`。

## 1.4 Apple Music TTML

**命名空間**：`tt`=`http://www.w3.org/ns/ttml`、`ttm`=`…#metadata`、`itunes`=`http://music.apple.com/lyric-ttml-internal`、`xml`=`http://www.w3.org/XML/1998/namespace`。結構：`<tt>` → `<head>`（metadata / translations / agents / iTunesMetadata）＋ `<body>` → `<div>` → `<p>`（行）→ `<span>`（詞）。
→ [Lyricify `Parsers/TtmlParser.cs`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/cabe0b71d443a9b882a35c60c4f7f21addcbe751/Lyricify.Lyrics.Helper/Parsers/TtmlParser.cs)、[AMLL `packages/ttml/src/constants.ts`](https://github.com/amll-dev/applemusic-like-lyrics/blob/86200dead453bb067e554e989110cbadca8d4756/packages/ttml/src/constants.ts)

**逐字表達**：`<span begin end>字</span>` 嵌在 `<p begin end>` 內。
- **`itunes:timing`** 值 `"Word"` / `"Line"`：AMLL 讀它並在**屬性不存在時靠推斷**（任一行有 >1 個 word 即判 `"Word"`）；**Lyricify 不看 `itunes:timing`**，只靠 `<span>` 是否存在判斷。
- Ruby（注音）：`tts:ruby`（`container`/`base`/`textContainer`/`text`）。
- 背景人聲：`ttm:role="x-bg"`。對唱：`ttm:agent`；AMLL 的 `Agent.id` 有 `v1`（非對唱）/`v2`（對唱），Apple 的檔案另有 `v3`/`v4`…（各演唱者）與 `v1000`（合唱）。
→ [AMLL `packages/ttml/src/parser.ts`、`types/index.ts`](https://github.com/amll-dev/applemusic-like-lyrics/blob/86200dead453bb067e554e989110cbadca8d4756/packages/ttml/src/parser.ts)

**時間單位 = 秒（可含小數）**：結尾帶 `s` → 直接當秒；`hh:mm:ss` / `mm:ss` → 各段相加；最後乘 1000 轉 ms（Lyricify 用 `MidpointRounding.AwayFromZero`；AMLL 用 `Math.round`）。（對照：ASS 卡拉 OK 以**厘秒**計，AMLL 由 ms 導出 ASS 四捨五入，**誤差至多 10 ms**。）

**翻譯 / 音譯**：行級放在 `<head>`（`<itunes:translation type="replacement"|"subtitle" xml:lang="…">`，以 `for` 屬性對應主 `<p itunes:key>`）；**逐字翻譯/音譯在同一檔內以 span 的 `ttm:role` 標記**：`x-translation`（翻譯）、`x-roman`（羅馬音）、`x-bg`（背景人聲），時間與主 span 一樣用 `begin`/`end`（秒）。AMLL 產生器有 `useSidecar` 選項，但**逐字翻譯/音譯一律強制放 `<head>`**，只有逐行可選內嵌。BetterLyrics 對內嵌逐字翻譯**只取 span 整體文字並沿用父行時間** → **逐字翻譯被壓成行級**。
→ [AMLL `packages/ttml/src/types/index.ts`](https://github.com/amll-dev/applemusic-like-lyrics/blob/86200dead453bb067e554e989110cbadca8d4756/packages/ttml/src/types/index.ts)、[BetterLyrics `LyricsContentParser.Ttml.cs`](https://github.com/jayfunc/BetterLyrics/blob/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.Core/Helpers/Lyrics/ContentParser/LyricsContentParser.Ttml.cs)

## 1.5 Spotify richsync / Musixmatch richsync

- **Spotify**：`SpotifyLyrics.syncType` ∈ `UNSYNCED` / `LINE_SYNCED` / `SYLLABLE_SYNCED`；行 `SpotifyLyricsLine { startTimeMs, endTimeMs（ms 的**字串**）, words（整行文字）, syllables }`；詞 `SyllableItem { startTimeMs, endTimeMs, numChars }` —— **詞的文字不是獨立欄位**，用累計 `numChars` 從 `line.words` 切出。時間單位 ms、**詞時間絕對**。
- **Musixmatch**：`calls["track.richsync.get"].body.richsync.richsync_body` 是**一個 JSON 字串**，解出 `RichSyncedLine { "ts"→TimeStart(float 秒), "te"→TimeEnd(float 秒), "l"→Words[], "x"→Text }`；`Word { "c"→Chars, "o"→Position(double 秒) }`。**時間單位秒（浮點）；詞的 `Position` 相對行首**（`StartTime = start + (int)(words[i].Position*1000)`；最後一詞 `EndTime = (int)(line.TimeEnd*1000)`）。
→ [Lyricify `Parsers/Models/Spotify.cs`、`Musixmatch.cs`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/tree/cabe0b71d443a9b882a35c60c4f7f21addcbe751/Lyricify.Lyrics.Helper/Parsers)

## 1.6 ESLrc / LRC A2 / SPL（Enhanced Synced LRC 系）

- AMLL 把三者統一成一個 `LrcParser`，`mode` ∈ `"plain"`（不保留逐字）/ `"enhanced"`（逐字）/ `"spl"`（Salt Player Lyrics，前兩者超集，**解析預設值**）。
- **逐字語法：行內時間戳 `<mm:ss.ms>` 或 `[mm:ss.ms]`**，置於該字之前。正則 `/(?:\[|<)(?<min>\d{1,3}):(?<sec>\d{1,2})(?:[:.](?<ms>\d{1,6}))?(?:\]|>)/g`。
- 時間欄位規則：分 1–3 位、秒 1–2 位、毫秒 1–6 位；**毫秒不足三位視為後位補 0**（`.1`=100 ms、`.02`=20 ms），超過三位**截斷**；秒與毫秒間也接受冒號。
- **內部時間單位一律 ms**。
→ [AMLL `packages/lyric/src/formats/lrc/types.ts`、`parser.ts`、`utils.ts`](https://github.com/amll-dev/applemusic-like-lyrics/tree/86200dead453bb067e554e989110cbadca8d4756/packages/lyric/src/formats/lrc)

**ESLrc 的正式規格文件：查不到**（找不到 Salt Player / ESLyric 的正式格式文件；以上全由實作反推）。

## 1.7 正規化成單一內部結構（各產品的欄位名）

### AMLL（`@applemusic-like-lyrics/lyric`，AGPL-3.0-only）

```ts
export interface LyricWord { startTime: number; endTime: number; word: string; romanWord?: string; }
export interface LyricLine { words: LyricWord[]; translatedLyric: string; romanLyric: string;
                             isBG: boolean; isDuet: boolean; startTime: number; endTime: number; }
export interface TTMLLyric { lines: LyricLine[]; metadata: [string, string[]][]; }
export type LyricParseResult = TTMLLyric;
```

- **時間單位 = ms（number）**；`LyricLine.startTime` **不保證等於 `words[0].startTime`**（官方註記）。
- 翻譯與羅馬音在此結構中是**行級字串**；`LyricWord` 另有**詞級** `romanWord?`；**逐字翻譯在核心結構裡沒有欄位**。
- TTML 專用層（`packages/ttml`）欄位更豐富：`Syllable { text, startTime, endTime, endsWithSpace?, ruby?, obscene?, emptyBeat? }`；`LyricLine { …, words?: Syllable[], translations?: SubLyricContent[], romanizations?: SubLyricContent[], backgroundVocal?, agentId?, … }`；`SubLyricContent { language?, text, words?: Syllable[] }` → **TTML 這一層支援逐字翻譯/音譯**。
- 支援的格式函式（`parseX`/`stringifyX`）：`ass`、`lqe`、`eslrc`、`lrc`、`lrcA2`、`lrcLike`、`spl`、`lyl`、`lys`、`qrc`、`ttml`、`yrc`，以及 `decryptQrcHex`/`encryptQrcHex`。**沒有 krc**。
→ [AMLL `packages/lyric/src/types.ts`、`index.ts`、`packages/ttml/src/types/index.ts`](https://github.com/amll-dev/applemusic-like-lyrics/blob/86200dead453bb067e554e989110cbadca8d4756/packages/lyric/src/types.ts)

### Lyricify（C#）

| 型別 | 欄位 |
|---|---|
| `ISyllableInfo` | `string Text`、`int StartTime`、`int EndTime`、`int Duration => EndTime - StartTime` |
| `ILineInfo` | `Text`、`int? StartTime/EndTime/Duration`、`StartTimeWithSubLine`…、`LyricsAlignment`、`ILineInfo? SubLine`、`FullText` |
| `SyllableLineInfo : ISyllableInfo[]` | `List<ISyllableInfo> Syllables`、`Text`（串接）、`StartTime => First().StartTime`、`EndTime => Last().EndTime`、`bool IsSyllable` |
| `FullLineInfo : LineInfo` | `Dictionary<string,string> Translations`、`string? Pronunciation` |
| `LyricsData` | `FileInfo?`、`List<ILineInfo>? Lines`、`List<string>? Writers`、`ITrackMetadata?` |
| `enum SyncTypes` | `Unknown=0, SyllableSynced=1, LineSynced=2, MixedSynced=3, Unsynced=4` |
| `enum LyricsTypes` | `…, LyricifySyllable=1, LyricifyLines=2, Lrc=3, Qrc=4, Krc=5, Yrc=6, Ttml=7, Spotify=8, Musixmatch=9` |

- **時間單位 = `int` 毫秒**。**逐字翻譯不存在**：`Translations` 是 `Dictionary<string,string>`，**只有行級**。另有 `SyllableWordMerger` 把相鄰非 CJK 音節併成 `FullSyllableInfo`。
→ [Lyricify `Models/`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/tree/cabe0b71d443a9b882a35c60c4f7f21addcbe751/Lyricify.Lyrics.Helper/Models)

### Lyricify Syllable（`.lys`）/ Lyricify Lines（`.lyl`）

- `.lys`：`[prop]字(startMs,durMs)word(startMs,durMs)…`。`prop`（0–8）：`isDuet = prop % 3 === 2`、`isBG = prop >= 6`；主行 Left→4/Right→5/Unspecified→3，子行 Left→7/Right→8/Unspecified→6。詞時間**絕對 ms**；行頭＝第一詞 start、行尾＝最後一詞 end。
- `.lyl`：`[type:LyricifyLines]` + `[startMs,endMs]字…`（純行級，無逐字）。
→ [AMLL `formats/lys.ts`、`lyl.ts`](https://github.com/amll-dev/applemusic-like-lyrics/tree/86200dead453bb067e554e989110cbadca8d4756/packages/lyric/src/formats)

### BetterLyrics（WinUI3，C#）

- 底層**直接用 Lyricify 的 parser**（QRC/KRC 走 `QrcParser` / `KrcParser`）；LRC/ESLrc 與 TTML 才是自寫。
- 自家模型 `BaseLyrics { int StartMs, int? EndMs, int DurationMs, string Text, int Length, int StartIndex, int EndIndex }`；`LyricsLine : BaseLyrics` 有 `PrimarySyllables` / `Secondary` / `Tertiary`、`PrimaryChars`、`IsPrimaryHasRealSyllableInfo`、`AgentId`。**三軌結構**：Primary＝原文、Secondary＝翻譯、Tertiary＝注音。
- 逐字補償：對每個音節以 `avgCharDuration = syllable.DurationMs / syllable.Length` 把時間**平均攤到每個字元**（`PrimaryChars`）。
→ [BetterLyrics `Models/Lyrics/`](https://github.com/jayfunc/BetterLyrics/tree/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.Core/Models/Lyrics)

### Namida（Flutter）

| 型別 | 欄位 |
|---|---|
| `LyricsLineModel` | `String? mainText`、`extText`、`int? startTime`、`endTime`、`List<LyricSpanInfo>? spanList`；`Duration? get timeStamp => Duration(milliseconds: startTime!)` |
| `LyricSpanInfo` | `int index`（行文字中的起始**字元**索引）、`int length`、`duration`、`start`、`String raw`、`drawWidth`、`drawHeight`；`end => start + duration`、`endIndex => index + length` |

- 時間單位 = ms（int），QRC 詞時間**絕對**；詞與文字用**字元 index/length** 表示。
→ [Namida `lib/packages/lyrics_parser/models.dart`](https://github.com/namidaco/namida/blob/acb1e1622600440cc793f389f497e6771c732c5e/lib/packages/lyrics_parser/models.dart)

### LX（`lxlrc`，四條平行字串，不轉物件）

| 欄位 | 內容 | 格式 |
|---|---|---|
| `lrc` | 行級原文 | `[mm:ss.xxx]字…` |
| `tlrc` | 行級翻譯 | `[mm:ss.xxx]字…` |
| `rlrc` | 行級羅馬音 | `[mm:ss.xxx]字…` |
| `lxlrc` | **逐字原文** | `[mm:ss.xxx]<詞相對ms,詞長度ms>字<…>word…` |

- `lxlrc` 詞時間**相對行首**、單位 ms；**不含行結束時間**（行尾由最後一個詞推得）→ **推測**。IPC 合約 `set_info` 帶這四個欄位。
→ [LX `src/common/types/desktop_lyric.d.ts`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/common/types/desktop_lyric.d.ts)

### 共同語意彙整

| 格式 / 產品 | 詞時間單位 | 相對 / 絕對 | 逐字翻譯欄位 | 逐字音譯欄位 |
|---|---|---|---|---|
| 網易雲 YRC | ms (int) | **絕對** | `ytlrc`（同格式） | `yromalrc`（同格式） |
| QQ QRC | ms (int) | **絕對** | `trans`（格式未證實） | `roma`（格式未證實） |
| Kugou KRC | ms (int) | **相對行首** | `[language:]` JSON `type:1`（**行級**） | `type:0`（**行級**） |
| Apple TTML | 秒（小數）→ ms | 絕對 | `ttm:role="x-translation"` span（**詞級**） | `x-roman` span（**詞級**） |
| ESLrc / LRC A2 / SPL | 文字 `mm:ss.ms` | 絕對 | 無原生 | 無原生 |
| Spotify richsync | ms（字串） | 絕對 | 無 | 無 |
| Musixmatch richsync | 秒（float）→ ms | 相對行首 | 無 | 無 |
| LX `lxlrc` | ms (int) | **相對行首** | 無（另存 `tlrc` 行級） | 無（另存 `rlrc` 行級） |
| Lyricify `ISyllableInfo` | ms (int) | 依來源 | **無**（行級 dictionary） | **無**（行級 `Pronunciation`） |
| BetterLyrics `BaseLyrics` | ms (int) | 依來源 | 三軌 `SecondarySyllables` | 三軌 `TertiarySyllables` |
| Namida `LyricSpanInfo` | ms (int) | 依來源 | 無 | 無 |
| AMLL `LyricWord` | ms (number) | 依來源 | 行級 `translatedLyric`；TTML 層有 `SubLyricContent.words` | 行級 `romanLyric`；`LyricWord.romanWord` |
| ASS | 厘秒 (cs) | — | 無 | 無 |

## 1.8 word → line 降級

- **Lyricify `SyncDowngrade.DowngradeToLineSynced`**：遞迴處理 `SubLine`；`SyllableLineInfo` → `Text = 詞文字合併回整行`、`StartTime = Syllables.First().StartTime`、`EndTime = Syllables.Last().EndTime`；`Translations` / `Pronunciation` 原樣帶進 `FullLineInfo`（不丟）。即 **行開始＝第一詞開始、行結束＝最後一詞結束；文字按原順序直接串接，不另加空白**。
  → [Lyricify `Helpers/Optimization/SyncDowngrade.cs`](https://github.com/WXRIW/Lyricify-Lyrics-Helper/blob/cabe0b71d443a9b882a35c60c4f7f21addcbe751/Lyricify.Lyrics.Helper/Helpers/Optimization/SyncDowngrade.cs)
- **AMLL**：**沒有名為 downgrade 的函式**（`packages/lyric/src/` 搜不到 `downgrade`/`toLine`/`flatten`）；降級發生在 generator 輸出階段。README 明文規範：
  1. 目標為純行級（`.lrc`、`.lyl`）時逐詞時間戳被剝離、整行合併；
  2. 導出至 LRC 系時翻譯/音譯作為**額外主時間戳行**插入；導出至 YRC/QRC/LYS/LYL 時**翻譯和音譯被丟棄**；
  3. 背景人聲降級為文字兩端包圓括號 `(...)`；
  4. 對唱資訊只有 `LYS`/`LQE`/`TTML` 具備，其他格式導出時**丟失**；
  5. 元數據只有 TTML 與 SPL 支援；
  6. ASS 厘秒折損，誤差至多 10 ms。
  → [AMLL `packages/lyric/README-CN.md`](https://github.com/amll-dev/applemusic-like-lyrics/blob/86200dead453bb067e554e989110cbadca8d4756/packages/lyric/README-CN.md)
- **LX**：**無獨立降級步驟**，解析當下同時產生行級與逐字兩份；KRC 的降級是**刪標籤**（`lxlrc.replace(/<\d+,\d+>/g, '')`）。
- **line → word（自動斷詞配時）**：**Lyricify / LX / AMLL 都沒有**；BetterLyrics 只有**同一音節內重切**（`SplitIntoTokens` 把一個音節切成多 token 後均分或按比例分時，再用 `SyllableWordMerger.Merge` 併回），**不是**整行→逐字。

## 1.9 逐字翻譯 / 羅馬音的對齊依據

| 產品 | 對齊依據 | 粒度 |
|---|---|---|
| LX（桌面） | **時間標籤最近匹配，容差 < 100 ms**（`fixTimeTag`） | 行級 |
| MusicFree | **時間戳完全相等**（雙指標，見 prior-art） | 行級 |
| BetterLyrics（LRC 系） | **`StartMs` 完全相等**（`GroupBy(l => l.StartMs)`，**無容差**） | 行級 |
| Lyricify | **沒有翻譯對齊機制**（直接掛在行上） | 行級 |
| Namida | 解析器直接寫在同一行物件 | 行級 |
| AMLL（核心） | 無對齊；翻譯是行上的獨立字串 | 行級 |
| AMLL / Apple TTML | `itunes:key` / `for` 屬性接線；詞級靠 `ttm:role` span 自帶 `begin`/`end` | 行級與**詞級** |
| Kugou KRC | **行序號 `i`**（用主歌詞第 i 行的時間標籤） | 行級 |
| 網易雲 `ytlrc` | 無公開規範；LX 走 `fixTimeTag` | 行級 |

**LX `fixTimeTag`**：對 `targetlrc` 每行取其時間標籤 `t1`，依序吃掉主歌詞行取 `t2`，若 `|t1−t2| < 100` 則把 target 行的時間標籤改寫成主行原始標籤並收進結果，否則推回；**沒配到的行直接丟棄**。它只比對「行標籤」（正則 `^\[([\d:.]+)\]`），**是行級近似匹配，不是逐字對齊**。

> **LX 的已知疑點**：LX 把 YRC 的 `ytlrc` 丟進 `fixTimeTag` 時，來源行仍是 `[start,dur](…)` 形式，而 `fixTimeTag` 的正則需要「僅數字、冒號、句點」的標籤，**逗號會使匹配失敗 → 該行被丟棄**。→ LX 是否真能取得逐字翻譯，**需實測**（本檔標推測）。
→ [LX `wy/lyric.js`（`fixTimeTag` / `filterExtendedLyricLabel`）](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/renderer/utils/musicSdk/wy/lyric.js)

## 1.10 本節查不到

1. 網易雲 YRC 的**官方格式規範**（全部知識來自 LX 與 go-musicfox 實作）。
2. 網易雲 `lv`/`tv`/`rv`/`kv` 各自對應的回應欄位名、`kv` 的回應欄位。
3. 非 eapi 的 `/api/song/lyric` 是否接受 `yv`。
4. QRC 的 `trans` / `roma` 是行級還是逐字；QRC `LyricType` 其他值的語意。
5. 網易雲 `ytlrc` 的詞時間是否與主 YRC 逐詞對應。
6. ESLrc（Enhanced Synced LRC）的**正式規格文件**。
7. `lxlrc` 是否需要行結束時間、行尾如何決定（本檔的推論已標**推測**）。
8. line → word（自動斷詞配時）在任何一個產品中的完整實作。

---

# §2 Flutter 的逐字（逐詞）渲染

## 2.1 `flutter_lyric` 3.x

| 項目 | 值 |
|---|---|
| 最新版 | `3.0.8`，發佈 `2026-09-16`；`isDiscontinued` 無值 |
| Likes / 分數 | Likes 109；`grantedPoints 160/160` |
| 授權 | MIT（`license:mit`、`fsf-libre`、`osi-approved`） |
| 平台 | `android, ios, windows, linux, macos, web`；`is:wasm-ready`、`is:dart3-compatible` |
| 釘選 commit | `b5151e6344e39f35dbc69d2e6d531464d27f9207` |

→ `https://pub.dev/api/packages/flutter_lyric`、`/score`、`https://github.com/ozyl/flutter_lyric`

**入口類名 `LyricView`**（`StatefulWidget`），構造參數只有四個：`controller`、`width`、`height`、`style`。`build` 回傳 `CustomPaint(painter: LyricPainter(layout:…, playIndex:…, activeHighlightWidth:…, isSelecting:…, scrollY:…, switchState:…, size:…))`。
→ [flutter_lyric `lib/widgets/lyric_view.dart`](https://github.com/ozyl/flutter_lyric/blob/b5151e6344e39f35dbc69d2e6d531464d27f9207/lib/widgets/lyric_view.dart)

> **重要更正：`highlightLevel` 參數不存在。** 對 3.0.8 的 `lib/core/lyric_style.dart`、`lib/render/lyric_painter.dart`、`lib/widgets/lyric_view.dart` 三檔 grep `highlightLevel` 皆 **0 筆**。簡報假設的 `highlightLevel` 應為 1.x 版 API。

**`LyricStyle` 高亮與對齊參數**（`lib/core/lyric_style.dart`）：高亮 `activeHighlightColor` / `activeHighlightGradient` / `activeHighlightExtraFadeWidth`；文字 `textStyle` / `activeStyle` / `translationStyle` / `selectedColor` / `translationActiveColor` / `selectedTranslationColor`；對齊 `lineTextAlign` / `contentAlignment` / `selectionAlignment` / `activeAlignment` / `selectionAnchorPosition` / `activeAnchorPosition`（0–1 相對值，>1 視為像素）；行距 `lineGap` / `translationLineGap` / `contentPadding`；漸隱遮罩 `fadeRange`；捲動 `scrollDuration(s)` / `scrollCurve` / `scrollAnimationBuilder` / `selectionAutoResumeDuration` / `activeAutoResumeDuration` / `SelectionAutoResumeMode{selecting, afterSelecting, neverResume}`；行切換 `enableSwitchAnimation` / `switchEnterDuration` / `switchExitDuration`（預設 200 ms）/ `switchEnterCurve` / `switchExitCurve`；其他 `activeLineOnly` / `disableTouchEvent`。斷言：`selectionAutoResumeDuration < activeAutoResumeDuration`。預設樣式 `LyricStyles.default1`。

README 逐字：
> 🔥 漸變/顏色高亮：根據播放進度實時推進高亮寬度，可疊加漸變與尾部淡出
> 📦 內置解析：默認支持 `.lrc`、`.qrc` 與 `.yrc`，可注入自定義解析器

**控制器**（`lib/core/lyric_controller.dart`）：`ValueNotifier<LyricModel?> lyricNotifier`、`activeIndexNotifiter`（原文拼字如此）、`progressNotifier`、`selectedIndexNotifier`、`isSelectingNotifier`、`selectedLineHeightNotifier`、`anchorPositionNotifier`、`lyricOffset`（毫秒）。`setProgress(Duration)` → `getIndexByProgress`（二分搜尋）；`loadLyric(String, {String? translationLyric})`。

**逐詞時間如何到達渲染層**：`LyricLine.words: List<LyricWord>` → `LineMetrics.words: List<WordMetrics>`。

| 型別 | 欄位 |
|---|---|
| `LyricModel` | `idTags`、`lines`；getter `title/artist/album/by/offset` |
| `LyricLine` | `start: Duration`、`end: Duration?`、`text`、`translation`、`words: List<LyricWord>?` |
| `LyricWord` | `text`、`start: Duration`、`end: Duration?` |
| `LineMetrics` | `textPainter`、`activeTextPainter`、`textMaskPainter`、`activeMaskPainter`、`translationTextPainter`、`words: List<WordMetrics>` |
| `WordMetrics` | `word`、`width`、`height`、`highlightWidth`、`highlightHeight` |

→ [flutter_lyric `lib/core/lyric_model.dart`](https://github.com/ozyl/flutter_lyric/blob/b5151e6344e39f35dbc69d2e6d531464d27f9207/lib/core/lyric_model.dart)

**逐詞高亮的寬度是 `WordMetrics.highlightWidth` 累加**（`lib/widgets/mixins/lyric_line_highlight.dart`）：`const Duration _kHighlightTransitionDuration = Duration(milliseconds: 200);`；`updateHighlightWidth()` 以 `currentProgress = controller.progressNotifier.value + Duration(milliseconds: controller.lyricOffset)` 為準，對每個 word 累加 `highlightWidth`，對當前 word 做部分扣除 `newWidth -= wordMetric.highlightWidth * (1 - elapsed / wordDuration);`，補上 `style.activeHighlightExtraFadeWidth`，再用一個 `AnimationController` 以 `Curves.linear` 補間。逐詞 vs 整行由「有無提供逐詞時間」決定（有則 `highlightTotalWidth == activeHighlightWidth`，否則 `double.infinity`）。

**內建 LRC → QRC 近似逐詞工具**：`LrcToQrcUtil.convert(String lrc, {Duration? totalDuration, Duration? lastDuration})`，`assert(totalDuration != null || lastDuration != null)`，把每行時長分配給該行各字 → **純 LRC 可被轉成 QRC 形式取得近似逐字，是套件內建能力**。
→ [flutter_lyric `lib/utils/lyric_lrc_to_qrc.dart`](https://github.com/ozyl/flutter_lyric/blob/b5151e6344e39f35dbc69d2e6d531464d27f9207/lib/utils/lyric_lrc_to_qrc.dart)

## 2.2 漸變高亮的實作技術（逐字片段）

**技術是 `CustomPainter` + 分段 `ui.Shader` 矩形 + `saveLayer` 遮罩，不是 `ShaderMask`。**

```dart
void _drawMaskedHighlightSegments(Canvas canvas, TextPainter maskPainter, Rect bounds, List<_HighlightSegment> segments) {
  canvas.save();
  canvas.clipRect(bounds);
  canvas.saveLayer(bounds, Paint());
  final paint = Paint();
  for (final segment in segments) { paint.shader = segment.shader; canvas.drawRect(segment.rect, paint); }
  canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
  maskPainter.paint(canvas, Offset.zero);
  canvas.restore(); canvas.restore(); canvas.restore();
}
```

- 高亮顏色：`activeHighlightGradient ?? LinearGradient(colors: [activeHighlightColor!, activeHighlightColor])`，以 `c.withValues(alpha: …)` 套用 `animationOpacity`。
- `shouldRepaint` 比較 `layout` / `playIndex` / `scrollY` / `activeHighlightWidth` / `switchState`。
- **`ShaderMask` 只用於上下漸隱邊界**（`lyric_mask_mixin.dart`，`style.fadeRange != null` 時 `LinearGradient(transparent→black→black→transparent, stops [0, top, 1-bottom, 1])` + `BlendMode.dstIn`），**不用於逐詞高亮**。
- **`ClipRect` 未被用於高亮**，而是 `canvas.clipRect(bounds)`（畫布層 clip）。「`ClipRect` + 兩個 `Text` 圖層」這手法在本套件**查不到**。
→ [flutter_lyric `lib/render/lyric_painter.dart`、`lib/widgets/mixins/lyric_mask_mixin.dart`](https://github.com/ozyl/flutter_lyric/tree/b5151e6344e39f35dbc69d2e6d531464d27f9207/lib)

## 2.3 效能相關

- **套件原始碼中沒有任何 `RepaintBoundary`**（對 `lib/` 全樹 grep，僅 `lyric_painter.dart` 命中 `shouldRepaint`）。
- `lib/widgets/highlight_listenable_builder.dart` 的 `SelectListenableBuilder` 為**四層巢狀 `ValueListenableBuilder`**。
- CHANGELOG 效能相關條目（逐字）：`3.0.4` 「Decouple active highlight rendering from active text opacity: dedicated mask painters avoid per-frame text relayout…」；`3.0.3` 「Optimize `LyricPainter` — cache style lookups, reduce redundant object creation, only rebuild TextSpan when color changes」。另 `3.0.4` 有一條非破壞性行為變更：「Active highlight vs. text opacity: Gradients/highlights on the playing line are no longer tied to `activeStyle` text opacity.」
- `3.0.5` 曾引入動畫生命週期 regression（#39），`3.0.6` 修回。
- **官方文件/issue 中關於「應關閉哪些效果以換效能」的明文建議：查不到。**

## 2.4 Flutter 官方漸變技術與成本（官方逐字）

- **`ShaderMask`**：「A widget that applies a mask generated by a Shader to its child.」→ `https://api.flutter.dev/flutter/widgets/ShaderMask-class.html`
- **`TextStyle.foreground`**（單一圖層漸層文字，不額外開圖層）逐字：「The paint drawn as a foreground for the text. … **The value should ideally be cached and reused each time** if multiple text styles are created with the same paint settings. Otherwise, each time it will appear like the style changed, which will result in unnecessary updates all the way through the framework.」→ `https://api.flutter.dev/flutter/painting/TextStyle/foreground.html`
- **`TextPainter.getBoxesForSelection`**（取字元矩形，逐字含「only returns `TextBox`es of glyphs that are entirely enclosed by the given selection」）→ `https://api.flutter.dev/flutter/painting/TextPainter/getBoxesForSelection.html`。這是「算出每個字/詞覆蓋矩形」的官方 API（`flutter_lyric` 未用它，改走 `WordMetrics.highlightWidth` 累加）。
- **每幀重建成本**：`State.build` 逐字「This method can potentially be called in every frame…」；`docs.flutter.dev/perf/best-practices` 逐字「Avoid repetitive and costly work in build() methods…」。
- **`RepaintBoundary`** 逐字：「A widget that creates a separate display list for its child. … Containing `RenderObject.paint` to parts of the render subtree that are actually visually changing using `RepaintBoundary` … is therefore critical to minimizing redundant work…」。
- **`saveLayer()` 成本**（`docs.flutter.dev/perf/best-practices` 逐字）：「Some Flutter code uses `saveLayer()`, **an expensive operation**, to implement various visual effects… excessive calls to `saveLayer()` can cause jank.」「Calling `saveLayer()` allocates an offscreen buffer and drawing content into the offscreen buffer might trigger a render target switch… On mobile GPUs this is particularly disruptive to rendering throughput.」→ 對照：`flutter_lyric` 的逐詞高亮每個高亮段都走 `canvas.saveLayer`。
- 「`ClipRect` + 兩個 `Text` 圖層」手法的官方來源：**查不到**（較接近的官方替代是 `TextStyle.foreground`）。

## 2.5 其他 Flutter 歌詞／逐字套件（pub.dev 普查）

| 套件 | 版本 | 發佈日 | Likes | 授權 | 平台 | 說明 |
|---|---|---|---|---|---|---|
| `flutter_lyric` | 3.0.8 | 2026-09-16 | 109 | MIT | 全平台 | **本次唯一查到、解析器明文支援 `.qrc` 的渲染套件** |
| `lyrics_parser` | 1.0.0-nullsafety.0 | 2021-02-03 | 12 | MIT | android, ios, windows, linux, macos | 解析庫，**無 `platform:web` 標籤** |
| `desktop_lyrics` | 0.0.8 | 2026-07-09 | 0 | MIT | **僅 windows/linux/macos** | 桌面歌詞視窗（非 Android） |
| `lyric_xx` | 0.7.6 | 2025-03-26 | 1 | MIT | 全平台 | 描述逐字「A Flutter package to encode and decode lrc.」→ **純編解碼** |
| `my_lyric` | 0.3.2 | 2024-11-24 | 2 | MIT | 全平台 | 描述逐字同 `lyric_xx` → **純編解碼** |
| `amlv` | 1.0.2 | 2023-11-01 | 15 | MIT | 全平台 | 「Inspired by Apple Music's Lyrics Viewer…displays lyrics(srt, lrc, json)…」→ **無逐詞字樣** |
| `lrc` | — | — | 18 | BSD-3-Clause | 全平台 | LRC 解析 |
| `lyrics` | — | — | 9 | BSD-3-Clause | — | **`is:dart3-incompatible`**、`grantedPoints 20/160` |

- **QRC 格式的原生 Flutter 渲染套件：除 `flutter_lyric` 外查不到**（`pub.dev` 搜 `qrc` 全為 QR code 類）。
- **`lyrics_parser` 與 Dart 3 不相容的說法在 pub.dev 標籤上查不到**（反而標 `is:dart3-compatible`）；明確標 `is:dart3-incompatible` 的是 `lyrics`。→ **推測**：原始情報可能把兩套件混淆。
- `lyric_xx` 與 `my_lyric` 為同一作者、描述相同的兩個 repo，**是否同一程式碼庫：查不到**（未逐行比對）。

---

# §3 桌面歌詞的穿透與鎖定

> `window_manager` 各平台能力表與 GTK4 遷移、GNOME Discourse 的 Wayland 說明已見 `packages-and-platform.md` §A3；本節只補**原始碼層**事實與新查到的官方逐字。

## 3.1 `window_manager` 的 `setIgnoreMouseEvents(ignore, forward)`

`window_manager` pub.dev 最新版 `0.5.2`（2026-07-04）。讀取 SHA `4080b59c…`。

Dart 端簽名與 doc（逐字）：
```dart
/// Makes the window ignore all mouse events.
///
/// All mouse events happened in this window will be passed to the window below this window, but if this window has focus, it will still receive keyboard events.
Future<void> setIgnoreMouseEvents(bool ignore, {bool forward = false}) async { … }
```
→ [window_manager `lib/src/window_manager.dart#L701-L709`](https://github.com/leanflutter/window_manager/blob/4080b59c0b1084c6085f1613c660382cd164ad76/packages/window_manager/lib/src/window_manager.dart#L701-L709)

**Windows：`forward` 完全沒有被讀取。** `SetIgnoreMouseEvents` 只讀 `ignore`，以 `WS_EX_TRANSPARENT | WS_EX_LAYERED` 同設/同清；無 `SetLayeredWindowAttributes`。
→ [window_manager `windows/window_manager.cpp#L1058`](https://github.com/leanflutter/window_manager/blob/4080b59c0b1084c6085f1613c660382cd164ad76/packages/window_manager/windows/window_manager.cpp#L1058)

**macOS：`forward` 有被實作**，對應 `NSWindow.acceptsMouseMovedEvents`（語意是「仍收到 mouse-moved 事件」，**不是**把點擊轉送給下層視窗）：
```swift
mainWindow.ignoresMouseEvents = ignore
if (!ignore) { mainWindow.acceptsMouseMovedEvents = false }
else { mainWindow.acceptsMouseMovedEvents = forward }
```
→ [window_manager `macos/…/WindowManager.swift#L501-L510`](https://github.com/leanflutter/window_manager/blob/4080b59c0b1084c6085f1613c660382cd164ad76/packages/window_manager/macos/window_manager/Sources/window_manager/WindowManager.swift#L501-L510)

**Linux：未實作**（`linux/window_manager_plugin.cc` 搜 `setIgnoreMouseEvents` **零命中**）。
→ [window_manager `linux/window_manager_plugin.cc`](https://github.com/leanflutter/window_manager/blob/4080b59c0b1084c6085f1613c660382cd164ad76/packages/window_manager/linux/window_manager_plugin.cc)

**CHANGELOG 與 issue**：0.2.0 逐字「[macos & windows] Implement setIgnoreMouseEvents metnod #89」（原文拼字錯誤）；#94 `[linux] Implement setIgnoreMouseEvents method` **內文空白、從未實作**；#96 原作者 `lijy91` 2022-03-19 逐字「The forward parameter is already supported on the macos platform… But I haven't found out how to implement it on windows platform」。`lijy91` **2026-09-21** 留言逐字：「window_manager 0.5.x is no longer maintained: from 0.6.0 window_manager is rebuilt on [nativeapi] … nativeapi doesn't handle this yet either, so it's now tracked in libnativeapi/nativeapi#67.」
→ [#89](https://github.com/leanflutter/window_manager/issues/89)、[#94](https://github.com/leanflutter/window_manager/issues/94)、[#96](https://github.com/leanflutter/window_manager/issues/96)
- **查不到**：`libnativeapi/nativeapi` issue `#67` 的內容（`gh api` 回 **404**；org 與 repo 皆存在、最後 push 為 2026-09-27）。

`flutter_acrylic`（1.1.4，2024-06-11）與 `bitsdojo_window`（0.1.6，2023-12-23）：**查不到**任何 Linux 點擊穿透實作或說明。

**小結（此層級）**：`forward` 在 **Windows 完全無效**、在 **macOS 只是 `acceptsMouseMovedEvents`**、在 **Linux 未實作**。Linux 若要有穿透，必須走 GTK 的 input shape。

## 3.2 Linux：GTK3 / GTK4 / Wayland 的 input region

**GTK3 官方文件（逐字）**：
- `gtk_widget_input_shape_combine_region`（自 3.0）：「Sets an input shape for this widget's GDK window. This allows for windows which react to mouse click in a nonrectangular region…」。`region` 參數「Shape to be added, or `NULL` to remove an existing shape.」。**`GtkWindow` 上沒有同名方法**（該 URL 回 404），此函式只在 `GtkWidget` 上。
- `gdk_window_input_shape_combine_region`（自 2.10）逐字：「…Mouse events which happen while the pointer position corresponds to an unset bit in the mask will be **passed on the window below** `window`. … On the X11 platform, this requires version 1.1 of the shape extension. **On the Win32 platform, this functionality is not present and the function does nothing.**」
- `gdk_window_set_pass_through`（**自 3.18**）逐字：「Sets whether input to the window is passed through to the window below. … If `pass_through` is `TRUE` then such pointer events happen as if the window wasn't there at all…」
→ `https://docs.gtk.org/gtk3/method.Widget.input_shape_combine_region.html`、`https://docs.gtk.org/gdk3/method.Window.input_shape_combine_region.html`、`https://docs.gtk.org/gdk3/method.Window.set_pass_through.html`

> **空 region 的語意**：mask 中未設位元的位置，事件往下方視窗傳遞 → **空 region ⇒ 整個視窗不接收輸入**。
> **`set_pass_through` 的關鍵限制（社群澄清，非官方文件）**：**只在同一 process 的 window hierarchy 內生效**，無法穿透到**其他 process** 的視窗。GNOME Discourse 回答者逐字：「I believe it's only for a window hierarchy... Windows of other processes do not count. For that you need `gdk_window_input_shape_combine_region`」。同串提問者逐字：「…it does work for X backend desktop environment, but it has no effect on xWayland…」。
> → **此點應標為「社群來源、非官方保證」**。`GtkOverlay` 的 `"pass-through"` 子屬性（自 3.18）逐字亦註明「implemented by calling `gdk_window_set_pass_through()`」→ 仍是同一 process 內。
→ `https://discourse.gnome.org/t/gtk3-set-pass-through-seems-not-work/20170`

**GTK4**：遷移指南逐字「`gdk_surface_input_shape_combine_region()` has been renamed to `gdk_surface_set_input_region()`」。替代 API `gdk_surface_set_input_region(surface, region)` 逐字「Apply the region to the surface for the purpose of event handling. Mouse events … will be passed on the surface below `surface`. … Use `gdk_display_supports_input_shapes()` to find out if a particular backend supports input regions.」；`region` 參數「…or `NULL` to make the entire surface reactive.」。`gdk_display_supports_input_shapes` 逐字：「…On modern displays, this value is always `TRUE`.」
→ `https://docs.gtk.org/gtk4/migrating-3to4.html`、`https://docs.gtk.org/gdk4/method.Surface.set_input_region.html`
- **查不到**：`gtk_widget_set_can_target` 是否被官方定位為 input shape 的替代。

**GTK3 的 Wayland backend 其實有實作 input shape**（`GNOME/gtk` 分支 `backport-5702-3-24`，`gdk/wayland/gdkwindow-wayland.c`）：`gdk_wayland_window_sync_input_region()` → `wl_surface_set_input_region(...)`；`gdk_wayland_set_input_region_if_empty()` 對**空 region** 特判 `wl_surface_set_input_region(wl_surface, empty)`；`impl_class->input_shape_combine_region` **已註冊**。
→ [GNOME/gtk `gdk/wayland/gdkwindow-wayland.c`](https://github.com/GNOME/gtk/blob/backport-5702-3-24/gdk/wayland/gdkwindow-wayland.c)
→ 因此 `desktop_lyrics` README 的「Wayland 不支援穿透」**不能單純歸因於「GTK3 Wayland backend 沒有此 API」**；實際失效原因**查不到**直接出處（**推測**與 XWayland、compositor 對 input region 的處理、或該 overlay 其他 X11-only 行為如 `gtk_window_move` 有關）。

**Wayland 官方 protocol `wl_surface.set_input_region`（逐字）**：「This request sets the region of the surface that can receive pointer and touch events. Input events happening outside of this region will try **the next surface in the server surface stack**. … The initial value for an input region is infinite. … A NULL wl_region causes the input region to be set to infinite.」
- 協定本身**沒有**提供「把事件轉送給其他 process 的特定視窗」的機制；穿透效果來自「區域外的部分對該 surface 而言不存在，compositor 改測堆疊中的下一個 surface」。
- **空 region ⇒ 該 surface 永不接收 pointer/touch**：協定未明文定義「空 region」，此為**推測**（GTK 的 `gdk_wayland_set_input_region_if_empty` 實作佐證）。
→ `https://wayland.freedesktop.org/docs/html/apa.html`、`https://wayland.app/protocols/wayland#wl_surface:request:set_input_region`
- 全域定位／置頂在 xdg-shell 不提供（見 `packages-and-platform.md` §A3）；**本輪未取得 xdg-shell 官方 protocol 的逐字引文**。
- 以 `gh search code` 搜 `set_input_region` / `gdk_window_input_shape_combine_region`，命中者為 GTK 本體、鏡像 repo、protocol headers，**未找到任何 Flutter 專案**以此實作穿透 → **Flutter 生態內無先例**。

## 3.3 `desktop_lyrics` 的 Linux 實作（穿透怎麼做的）

`linux/desktop_lyrics_overlay_render.cc` 的 `ApplyWindowBehavior()` 逐字：
```cpp
gtk_widget_set_opacity(window_, 1.0);
gtk_window_set_keep_above(GTK_WINDOW(window_), TRUE);
gtk_window_set_accept_focus(GTK_WINDOW(window_), FALSE);
GdkWindow* gdk_window = gtk_widget_get_window(window_);
if (gdk_window != nullptr) { gdk_window_set_pass_through(gdk_window, click_through_); }
if (click_through_) {
  cairo_region_t* empty_region = cairo_region_create();
  gtk_widget_input_shape_combine_region(window_, empty_region);
  if (drawing_area_ != nullptr) { gtk_widget_input_shape_combine_region(drawing_area_, empty_region); }
  cairo_region_destroy(empty_region);
} else {
  gtk_widget_input_shape_combine_region(window_, nullptr);
  if (drawing_area_ != nullptr) { gtk_widget_input_shape_combine_region(drawing_area_, nullptr); }
}
```
→ [desktop_lyrics `linux/desktop_lyrics_overlay_render.cc`](https://github.com/587626/desktop_lyrics/blob/e92aa0e2c0831285570974883f1dd99b36354958/linux/desktop_lyrics_overlay_render.cc)

- 用 **`gdk_window_set_pass_through`**（GTK3 3.18+）＋**空的 `cairo_region`** 丟給 **`gtk_widget_input_shape_combine_region`**，同時對 `window_` 與 `drawing_area_` 兩個 widget 設；關閉穿透時傳 `nullptr` 還原。
- 定位用 **`gtk_window_move(...)`** —— 該 API **只在 X11/XWayland 有效**。
- `OnButtonPress`：`if (self->click_through_) return FALSE;`；`OnMotion`：`if (!self->dragging_ || self->click_through_) return FALSE;`；雙鍵按下降回預設位置，單鍵按下 `gtk_window_begin_move_drag`。同檔註解逐字：「Some Wayland compositors can transiently report a very small allocation for undecorated windows…」
- `README.md` 逐字：「Linux: supported / - Wayland: click-through is currently not supported due to technical limitations.」；`README_zh.md` 逐字「Linux：已支持 / - Wayland：由于技术原因，暂不支持点击穿透。」；另有「overlay size/position does not automatically follow system scaling or resolution changes（X11 與 Wayland 皆然）」。
→ [desktop_lyrics `README.md`](https://github.com/587626/desktop_lyrics/blob/e92aa0e2c0831285570974883f1dd99b36354958/README.md)

## 3.4 成熟產品的「鎖定 / 解鎖」定義與入口

| 產品 | 平台 | 「鎖定」＝不能拖？ | 「鎖定」＝點擊穿透？ | 解鎖入口 | 來源性質 |
|---|---|---|---|---|---|
| **LX Music Desktop** | Win/macOS/Linux(Electron) | 是（收不到滑鼠） | 是（`isLock` ⇒ `setIgnoreMouseEvents(true)`） | 全域快捷鍵 `desktop_lyric.toggle_lock`；托盤選單「解鎖歌詞視窗」 | 官方原始碼 |
| **LX Music Mobile** | Android | 是（`FLAG_NOT_TOUCHABLE`） | 是（同 flag；另 alpha 0.8、去背） | 設定頁 checkbox；**長按桌面歌詞按鈕** | 官方原始碼 |
| **BetterLyrics** | Windows（WinUI3） | 是 | 是（`WS_EX_LAYERED\|WS_EX_TRANSPARENT`） | 鎖定時顯示的 `LockToggleButtonContainer`；hover 浮現的 `UnlockButton`（可用 `IsAlwaysHideUnlockButton` 整個藏掉） | 官方原始碼 |
| **Lyricify 4 / Fusion** | Windows | **查不到**（原始碼未開源、文件站無鎖定頁） | **查不到** | **查不到** | — |
| **網易雲音樂 PC** | Windows | **查不到官方** | **查不到官方** | **查不到官方** | 僅第三方 |
| **QQ 音樂 PC** | Windows | 第三方稱「不可移動」 | **查不到** | 熱鍵 `Ctrl+Alt+E`；歌詞工具列「鎖定」；下拉「點擊解鎖桌面歌詞」（**第三方**） | 僅第三方 |

**LX Desktop 的細節**（[`winLyric/config.ts`](https://github.com/lyswhut/lx-music-desktop/blob/ad95d5091c9ed689fa72b5e5c849df65f5a679ce/src/main/modules/winLyric/config.ts)）：
- `isLock = true` ⇒ 立即 `setIgnoreMouseEvents(true)`。Linux 一律 `forward: false`（`!isLinux` 短路）——因為 Electron/Linux 沒有 `forward`。
- `mouseCheckTools`（500 ms 輪詢游標）在 `isLinux || !isLock || !isHoverHide || !isMouseInWindow` 時直接 return；**Windows 的 `forward` 無效，故用輪詢補足 hover 判斷**。
- 歌詞視窗自己的鎖定按鈕**只能鎖不能解**（`handleLock = () => updateSetting({ 'desktopLyric.isLock': true })`）。
- 預設值：`desktopLyric.enable: false`、`isLock: false`、`isHoverHide: false`、`isLockScreen: isWin`。
- 相關 issue：#725（已 closed，作者稱「v2.0.0中已移除窗口穿透的管理」）；#743（**仍 open**）作者 2022-04-11 逐字「…桌面歌词无法使用拖动来移动位置，并且置顶无效，**锁定歌词后无法鼠标穿透**」→ **Wayland 下失效的第一手陳述**。

**LX Mobile 的細節**：`LyricView.getLayoutParamsFlags()` 在 `isLock` 時加 `FLAG_NOT_TOUCHABLE`；`lockView()`/`unlockView()` 另在 `SDK_INT > R` 時設 `alpha = 0.8f / 1.0f`（原始碼註解逐字：`// 修复 Android 12 的穿透点击问题`）。

**BetterLyrics 的細節**：`OverlayInputHelper` 為 `DispatcherTimer`，間隔 **50 ms**，每次 tick 用 `User32.GetCursorPos` 比對已 `Register` 的 `FrameworkElement` 的螢幕座標矩形；命中 ⇒ `SetIsClickThrough(false)`，離開 ⇒ `SetIsClickThrough(true)`。檔頭註解逐字：「用于管理覆盖层窗口的鼠标交互区域检测」。→ 手法與 LX 的 `mouseCheckTools` 同型：**輪詢游標決定此刻要不要關掉穿透**，因為 Windows 的 `WS_EX_TRANSPARENT` 是全域開關。
→ [BetterLyrics `Helpers/OverlayInputHelper.cs`](https://github.com/jayfunc/BetterLyrics/blob/97629ddf085877cdc90de8cb56006a023320fe00/src/BetterLyrics.DotNet/BetterLyrics.WinUI3/BetterLyrics.WinUI3/Helpers/OverlayInputHelper.cs)

**Lyricify**（[`WXRIW/Lyricify-App` README](https://github.com/WXRIW/Lyricify-App)）：Lyricify 4 `4.3.52-release`（Windows）；Fusion `1.2.5-release`（Windows）；Mobile `1.5.1-release`（iOS/iPadOS/macOS/Android/Windows，官網另列 visionOS）；3 已 EOL。**App 原始碼未開源**（僅 `Lyricify-Lyrics-Helper`（Apache-2.0）與 `Lyricify-Backgrounds` 開源）→ 無法讀其穿透／鎖定實作。「靈動詞島」首創 2022-09-30（Lyricify 3.8.1 公開）、「妙控條」首創 2022-10-09（Lyricify 4.0.0 公開）。
- **妙控條不是 macOS 選單列歌詞**：它是 **Lyricify 4（Windows）** 的側邊長條快捷控件。**macOS 選單列歌詞：查不到** Lyricify 或其他產品有明示此功能。
- `docs.lyricify.app` 全站 sitemap **查不到**任何「桌面歌詞鎖定／解鎖」官方頁。

## 3.5 本節查不到

1. `libnativeapi/nativeapi` issue **#67** 內容（`gh api` 404）。
2. X11 SHAPE extension **官方規範**中 input shape / bounding shape 的逐字定義。
3. xdg-shell 官方 protocol 中「不提供全域定位／置頂」的**逐字**引文。
4. `flutter_acrylic` / `bitsdojo_window` 任何 Linux 點擊穿透實作。
5. Lyricify 任何「桌面歌詞鎖定／解鎖」官方說明。
6. 網易雲音樂 PC 桌面歌詞鎖定的官方說明與解鎖入口（僅第三方）。
7. QQ 音樂 PC 桌面歌詞鎖定的官方說明（僅第三方）。
8. `desktop_lyrics` README「Wayland 不支援穿透」的技術根因。
9. Flutter 生態內以 GTK/Wayland input region 實作穿透的先例。

---

# §4 Android 懸浮歌詞視窗

## 4.1 `flutter_overlay_window`

| 項目 | 值 |
|---|---|
| 最新版 | `0.5.0`，發佈 `2025-04-20`；`isDiscontinued` 無值 |
| Likes / 分數 | Likes 528；`grantedPoints 160/160` |
| 授權 / 平台 | MIT；`platform:android`、`is:plugin`、`is:built-in-kotlin` |
| 釘選 commit | `111b21041ac3250a965a8ce1705e210c414a7a62` |

→ `https://pub.dev/api/packages/flutter_overlay_window`、`https://github.com/X-SLAYER/flutter_overlay_window`

**是否獨立 FlutterEngine：是。** `OverlayService.onCreate()` 逐字：
```java
FlutterEngine flutterEngine = FlutterEngineCache.getInstance().get(OverlayConstants.CACHED_TAG);
if (flutterEngine == null) {
    FlutterEngineGroup engineGroup = new FlutterEngineGroup(this);
    DartExecutor.DartEntrypoint entryPoint = new DartExecutor.DartEntrypoint(
        FlutterInjector.instance().flutterLoader().findAppBundlePath(), "overlayMain");  // custom entry point
    flutterEngine = engineGroup.createAndRunEngine(this, entryPoint);
    FlutterEngineCache.getInstance().put(OverlayConstants.CACHED_TAG, flutterEngine);
}
```
常數：`CACHED_TAG = "myCachedEngine"`、`CHANNEL_TAG = "x-slayer/overlay_channel"`、`OVERLAY_TAG = "x-slayer/overlay"`、`MESSENGER_TAG = "x-slayer/overlay_messenger"`、`NOTIFICATION_ID = 4579`。

> **關鍵事實：overlay engine 上沒有跑 `GeneratedPluginRegistrant`。** 對 `OverlayService.java` 全文 grep `Registrant` 為 **0 筆**；該 engine 只被建立兩個 channel。→ **其他任何 Flutter 外掛（含 `audio_service`）都不會註冊在 overlay engine 上。**

**三條通道**：① `MethodChannel("x-slayer/overlay_channel")` 主 isolate → 原生（`checkPermission`/`requestPermission`/`showOverlay`/`isOverlayActive`/`moveOverlay`/`getOverlayPosition`/`closeOverlay`）；② `MethodChannel("x-slayer/overlay")` 原生 → overlay engine（`updateFlag`/`updateOverlayPosition`/`resizeOverlay`）；③ `BasicMessageChannel("x-slayer/overlay_messenger", JSONMessageCodec())` **雙向，是主 isolate 與 overlay isolate 唯一的資料通道**。Dart 端 `FlutterOverlayWindow.shareData(x)` → 原生 `onMessage` 轉發到主引擎 → 主 isolate 的 `overlayListener` 收到。

**內建點擊穿透：有**，即 `clickThrough` / `flagNotTouchable`（= `FLAG_NOT_TOUCHABLE`，另加 `FLAG_NOT_FOCUSABLE | FLAG_LAYOUT_NO_LIMITS | FLAG_LAYOUT_IN_SCREEN`）。**內建「鎖定/解鎖」切換：查不到**——`updateFlag` 只是重跑 `WindowSetup.setFlag(flag)` 並 `updateViewLayout`，**沒有鎖定狀態機**。Android 12 的 0.8 alpha 上限**有被硬編碼**：`MAXIMUM_OPACITY_ALLOWED_FOR_S_AND_HIGHER = 0.8f`，條件為 `SDK_INT >= S && WindowSetup.flag == clickableFlag`。
→ [flutter_overlay_window `WindowSetup.java`、`OverlayService.java`](https://github.com/X-SLAYER/flutter_overlay_window/tree/111b21041ac3250a965a8ce1705e210c414a7a62/android/src/main/java/flutter/overlay/window/flutter_overlay_window)

**Manifest 必要條目**（README 逐字）：權限 `SYSTEM_ALERT_WINDOW`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_SPECIAL_USE`；`<service android:name="…OverlayService" android:exported="false" android:foregroundServiceType="specialUse">`（內附 `<property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" …/>`）；overlay 入口點 `@pragma("vm:entry-point") void overlayMain()`。

## 4.2 與 `audio_service` 背景 isolate 的關係

`audio_service` `0.18.19`（2026-06-29）；釘選 SHA `da405ddd…`。

> **前提修正**：`audio_service` 的「另一個 isolate」是 **Dart 層 `Isolate`**，不是第二個 engine。Activity 與 foreground Service **共用同一個 cached `FlutterEngine`**（`AudioServicePlugin.getFlutterEngine`）。
> `IsolatedAudioHandler` 用 `IsolateNameServer.registerPortWithName(_receivePort.sendPort, portName)` 與 `lookupPortByName`，**走 `SendPort`/`ReceivePort`，不走 MethodChannel，也不開新 engine**。
→ [audio_service `lib/audio_service.dart`、`AudioServicePlugin.java`](https://github.com/ryanheise/audio_service/blob/da405ddd07840d5861a09ab252cce6f40cc95a0b/audio_service/lib/audio_service.dart)

**互通結論**：
- **官方支援的互通路徑：查不到。** 兩套件互不引用；overlay engine 沒有 `GeneratedPluginRegistrant`，`audio_service` 也沒有 API 指向 overlay channel。
- **overlay isolate 直接 `IsolatedAudioHandler.lookup(...)` 是否可行：查不到**（未在查到的 Flutter 官方頁面明言 `IsolateNameServer` 跨 engine/isolate group 的可見性）。**推測**：因 `flutter_overlay_window` 用 `FlutterEngineGroup.createAndRunEngine` 產生**另一個 engine**，若兩 engine 不共享同一 isolate group，lookup 會失敗。**需實測**。
- **唯一可用的通道（事實陳述）**：`flutter_overlay_window` 自帶的 `BasicMessageChannel("x-slayer/overlay_messenger")` 是它唯一對外資料通道。

**兄弟／替代套件**：`flutter_overlay_window_plus` 1.0.1（2025-07-15，`{"fork":false}`，非 fork）；`easy_overlay` 1.0.1（2024-08-10，**GPL-3.0**）；`floating` 6.0.0（2025-02-14）——**`floating` 是 PiP（子母畫面），不是系統 overlay**（pub.dev 描述逐字「Picture in Picture management for Flutter. Android only」，公開 API `PiPSwitcher`、`Floating()`，需 `android:supportsPictureInPicture="true"`），列為系統級懸浮窗替代品會誤導。`desktop_lyrics` **沒有 Android**。

## 4.3 原生 Kotlin/Java View 路線

**共同點**：都用 `TYPE_APPLICATION_OVERLAY`（API ≥ 26）/ `TYPE_SYSTEM_ALERT`（API < 26）、`FLAG_NOT_FOCUSABLE | FLAG_NOT_TOUCH_MODAL | FLAG_LAYOUT_IN_SCREEN | FLAG_LAYOUT_NO_LIMITS`、`PixelFormat.TRANSPARENT`、`windowManager.updateViewLayout` 更新。

- **LX Music Mobile**（[`LyricView.java`](https://github.com/lyswhut/lx-music-mobile/blob/fb8480728d875fa5e0da25eebd3a26bb71723aae/android/app/src/main/java/cn/toside/music/mobile/lyric/LyricView.java)）：`if (isLock) flag |= FLAG_NOT_TOUCHABLE;`；`lockView()`/`unlockView()` 切換該 flag，並在 `SDK_INT > R` 時設 `alpha = 0.8f / 1.0f`。**「鎖定」＝不能拖＋點擊穿透＋視覺淡化（0.8、去圓角背景）**。解鎖入口：設定頁 checkbox、**長按桌面歌詞按鈕**（`DesktopLyricBtn.tsx` 的 `onLongPress={updateLock}`）。預設 `desktopLyric.enable: false`、`isLock: false`。`LyricTextView.java` 的註解指出其來源是 `Block-Network/StatusBarLyric` 的 `LyricTextView.kt`；常數 `SPEED_LIMIT = 0.135F`、`startScrollDelay = 1500`、`invalidateDelay = 10`。
- **MusicFree**（[`LyricView.kt`](https://github.com/maotoumao/MusicFree/blob/d118b18b3d0c904400f7eea7bf99c0ceec6c1aee/android/app/src/main/java/fun/upup/musicfree/lyricUtil/LyricView.kt)）：`onTouch` 直接 `return false`，flags **恆含 `FLAG_NOT_TOUCHABLE`** → **無觸控能力**（與 LX 的可鎖可拖不同）。`gravity = Gravity.TOP or Gravity.START`；選項 `topPercent`/`leftPercent`/`align`/`color`/`backgroundColor`/`widthPercent`/`fontSize`。

## 4.4 Android 12 不受信任觸碰（官方逐字）

> **來源更正（重要）**：`https://developer.android.com/about/versions/12/behavior-changes-12` **不含此內容**（2026-09-28 對下載頁全文計數：`untrusted` 0 次、`obscur` 0 次）。**正確頁面是** `https://developer.android.com/about/versions/12/behavior-changes-all#untrusted-touch`。

逐字（節錄）：
> **Untrusted touch events are blocked** — To preserve system security and a good user experience, Android 12 prevents apps from consuming touch events where an overlay obscures the app in an unsafe way. …
> **Affected apps** — This change affects apps that choose to let touches pass through their windows, for example by using the `FLAG_NOT_TOUCHABLE` flag. … Overlays that require the `SYSTEM_ALERT_WINDOW` permission, such as windows that use `TYPE_APPLICATION_OVERLAY`, and use the `FLAG_NOT_TOUCHABLE` flag.
> **Exceptions** — … Trusted windows (Accessibility / IME / Assistant windows) — **Note:** Windows of type `TYPE_APPLICATION_OVERLAY` aren't trusted. … Invisible windows … Completely transparent windows (`alpha` 0.0) … **Sufficiently translucent system alert windows.** … **In Android 12, this maximum opacity is 0.8 by default.**
> **Detect when an untrusted touch is blocked** — Logcat: `Untrusted touch due to occlusion by PACKAGE_NAME`
> **Test the change** — `adb shell am compat disable BLOCK_UNTRUSTED_TOUCHES com.example.app`

**`WindowManager.LayoutParams` flag 逐字**（`https://developer.android.com/reference/android/view/WindowManager.LayoutParams`）：
> `FLAG_NOT_TOUCHABLE` — Window flag: this window can never receive touch events.
> `FLAG_NOT_FOCUSABLE` — Window flag: this window won't ever get key input focus…（並**隱含** `FLAG_NOT_TOUCH_MODAL`）

## 4.5 權限流程與廠商 ROM

- `Settings.canDrawOverlays(context)` 逐字「Returns true if the app can draw overlays on top of other apps.」；`Settings.ACTION_MANAGE_OVERLAY_PERMISSION` 逐字「Show screen for controlling which apps can draw on top of other apps. **In some cases, a matching Activity may not exist, so ensure you safeguard against this.** … Constant Value: `"android.settings.action.MANAGE_OVERLAY_PERMISSION"`」。
  → `https://developer.android.com/reference/android/provider/Settings#canDrawOverlays(android.content.Context)`
- **官方是否對「使用者拒絕後如何處理」給出建議：查不到**（該頁僅有上列 safeguard 提醒與 Android 11 起「一律路由到頂層設定頁」敘述）。
- `flutter_overlay_window` 的實作：`checkOverlayPermission()` → `Settings.canDrawOverlays(context)`；`requestPermission` → `Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)` + `intent.setData(Uri.parse("package:" + mActivity.getPackageName()))` + `startActivityForResult(...)`；`onActivityResult` 回報 `checkOverlayPermission()`。
- SAW 權限與 API 版本限制（manifest 宣告不足、API 23 起須 `ACTION_MANAGE_OVERLAY_PERMISSION`、API 26 起須 `TYPE_APPLICATION_OVERLAY`、Android 10 Go 無法取得、Android 11 一律頂層、Android 15 FGS 豁免收緊）**見 `packages-and-platform.md` §B1**，本檔不重複。

**廠商 ROM 額外權限**：
- **MIUI / HyperOS「後台彈出介面」：存在。** 官方頁 `https://dev.mi.com/console/doc/detail?pId=1735` 為 JS 渲染，`tavily-extract` 正文為空；新網域 `https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1735` 顯示「暂无数据」。**逐字正文取不到**；可取得的政策文字（搜尋索引摘要 + 第三方轉引，**二手**）：「该权限默认为拒绝的…针对特殊应用会提供白名单，例如音乐（歌词显示）、运动、VOIP（来电）等」。第三方（**二手**）稱其實作位於 `AppOpsManager` 擴充 op，`opCode = 10021`（小米機型）。**本次未找到小米官方對「如何以程式判斷此權限」的 API**；二手來源一致指出沒有公開 API，只能以「啟動是否成功」反推。
- **MIUI / HyperOS「顯示在其他應用上層」：存在**，即 AOSP `SYSTEM_ALERT_WINDOW` 在 MIUI 設定中的名稱（**二手**：騰訊雲開發者社群問答）。小米官方對該權限的逐字說明**查不到**。
- **ColorOS「懸浮窗」：存在**（設定項名稱即「懸浮窗」）。**OPPO/ColorOS 官方文件逐字說明：查不到**。`https://www.coloros.com/instruction?id=850` 是「自由浮窗」（應用內多工），**與跨應用 SAW 不同**。可取得的路徑描述（**二手**）：「ColorOS 13及以上：设置> 应用> 特殊应用权限> 悬浮窗…」。未授予時懸浮窗不顯示且系統不報錯（**二手**）。
- **共同事實**：本次查證到的四項廠商 ROM 額外權限（MIUI 後台彈出介面、MIUI 顯示在其他應用上層、ColorOS 懸浮窗、HyperOS 焦點通知權限）**都沒有可用於程式化判斷的公開 API**。

## 4.6 本節查不到

1. `flutter_overlay_window` 的 overlay isolate 能否直接使用 `IsolatedAudioHandler.lookup`（**查不到**，**推測**會因跨 engine 失敗，**未實測**）。
2. MIUI 後台彈出介面官方頁面的**逐字正文**（JS 渲染，新舊網域皆空）。
3. ColorOS 懸浮窗的**官方說明**（路徑描述全為二手）。

---

# §5 Android 狀態列歌詞

## 5.1 魅族 Flyme ticker（一手）

官方頁：`https://open.flyme.cn/docs?id=239`（標題「【系统媒体控件 & 状态栏歌词】适配说明」；Nuxt SPA，`WebFetch` 只回導覽，正文經官方 JSON API `https://apiopen.flyme.cn/api/web/v1/doc-wiki/detail?id=239` 取得）。

逐字：
> （1）Flyme 状态栏歌词显示功能，是在 android 通知框架的基础上，**利用 Notification 的 tickerText 显示功能**，做的一个定制功能。
> 如果不存在如下两个 flag 则该机型不支持此功能。
> `mNotification.flags |= Notification.FLAG_NO_CLEAR;` // Notice. 必须添加，使该条通知常驻
> `mNotification.extras.putBoolean("ticker_icon_switch", false);` / `mNotification.extras.putInt("ticker_icon", R.drawable.notification_icon);`
> `mNotification.flags |= mflag_show_ticker;` / `mNotification.flags |= mflag_update_ticker;`

- 兩個 flag 以反射 `Class.forName("android.app.Notification")` 取得：`FLAG_ALWAYS_SHOW_TICKER` / `FLAG_ONLY_UPDATE_TICKER`。**沒有獨立 SDK**——「公開 API」＝官方文件化的**反射 flag 名稱**，不是 `Notification.Builder` 的公開參數。
- 其他官方要求：smallIcon 60×60（xxhdpi）；RemoteView 同一條通知只設一次；取消時 `builder.setTicker(null)` 並清除兩個 flag。
- **數值由兩個獨立開源實作相互印證**（官方頁只寫 flag 名稱）：`xiaowine/Lyric-Getter` 的 `MeiZuNotification` 與 `Moriafly/HiMoriafly` 的文件皆為 `0x01000000` / `0x02000000` → **三方一致**。
→ [Lyric-Getter `MeiZuNotification.kt`](https://github.com/xiaowine/Lyric-Getter/blob/9e6d3f72694b08f56dce0b1a4524e18dc56f5c09/app/src/main/kotlin/cn/lyric/getter/tool/MeiZuNotification.kt)、[HiMoriafly `flyme-lyrics-noti.md`](https://github.com/Moriafly/HiMoriafly/blob/98e04b2cf53aa65fa998a424cf328330fe345044/docs/android-dev/flyme-lyrics-noti.md)

## 5.2 HyperOS / 澎湃 OS 焦點通知 / 超級島

官方文件：`https://dev.mi.com/xiaomihyperos/documentation/detail?pId=2146`（Q&A，標示更新於 2025-10-23）、`?pId=2131`（開發指南）。

- **App 可以主動提供歌詞，但需先取得權限**：焦點通知 access 需**向 `mipush-permission@xiaomi.com` 發郵件申請**（非 SDK 自助開通）。
- 權限探測：`ContentResolver.call(Uri.parse("content://miui.statusbar.notification.public"), "canShowFocus", null, extras)` → `bundle.getBoolean("canShowFocus")`。
- OS 版本探測：`Settings.System.getInt(cr, "notification_focus_protocol", 0)`（`1`=OS1、`2`=OS2、`3`=OS3）。
- extra 載荷：`miui.focus.param` / `miui.focus.param_v2`，內含 `ticker`（文件稱「OS2 焦点通知状态栏显示文案」）、`tickerPic`、`aodTitle`、`islandProperty`、`islandTimeout`、`bigIslandArea`、`smallIslandArea`、`shareData`。`miui.focus.param` 大小上限 **≤ 3072 bytes**。
- media 通知會自動上島，但文件指向另一份《Xiaomi HyperOS 媒体通知适配说明》。
- **沒有可從 pub.dev / Maven 直接依賴的公開 SDK**；「公開」的部分是郵件申請後的協定文件 + 既有的 `content://` Provider。`islandProperty` 的具體 schema、`ticker` 的官方逐字定義**本次未逐欄取得**（頁面為 JS 渲染）。

## 5.3 LSPosed 模組（需 root）

- **`StatusBarLyric`**（`bd2ec998…`，GPL-3.0）：README 逐字「这是一个Xposed模块，**仅支持LSPosed框架** / 用于在状态栏显示歌词 / 理论支持 __所有__ 官方以及部分修改系统」。**需要 root/LSPosed：是。** 掛鉤作用域（`arrays.xml` 逐字）**只有 `com.android.systemui`**。**歌詞不是直接讀 `MediaSession`，而是走 `SuperLyric` 的 Binder 協定**：`SystemUILyric.kt` 從 `com.hchen.superlyricapi` 匯入 `ISuperLyric`/`SuperLyricData`，以 `registerSuperLyric(context)` 註冊 `ISuperLyric.Stub`（`onStop`/`onSuperLyric` 回呼）。另有小米焦點通知掛鉤 `xiaomi/FocusNotifyController.kt`（掛 `FocusedNotifPromptController`）。**支援應用清單：README 未列。**
  → [StatusBarLyric `SystemUILyric.kt`](https://github.com/Block-Network/StatusBarLyric/blob/bd2ec998c4a4d667d5e0602923bdd9cfec330a54/app/src/main/kotlin/statusbar/lyric/hook/module/SystemUILyric.kt)
- **`Lyricon`**（正確 repo 是 `tomakino/lyricon`（`c93da0ee…`）；簡報若寫 `lz233/Lyricon` 該 repo 回 **404**）：Xposed 模組，需 **Root + LSPosed**、Android 9.0（API 28）+、必須以 **System UI 作用域**運行。**歌詞來自外掛（LyricProvider），不是來自 `MediaSession`**：Provider 應用在 `<application>` 宣告 `<meta-data android:name="lyricon_module" android:value="true" />`（另有 `lyricon_module_author`、`lyricon_module_description`、可選 `lyricon_module_tags` 值 `$syllable`/`$translation`）。主要掛鉤 `SystemUIHooker.kt` 呼叫 `subscriber.subscribeActivePlayer(LyricDataHub)`。**支援面由外掛生態決定，README 無逐應用清單。**
  → [lyricon `SystemUIHooker.kt`](https://github.com/tomakino/lyricon/blob/c93da0eef8b7aee015d2670b48e9e262fcf72cd1/xposed/src/main/kotlin/cn/tomakino/lyricon/xposed/systemui/SystemUIHooker.kt)
- **相關：`SuperLyric` / `SuperLyricApi`**（`HChenX/SuperLyric` `bfca7093…`、`HChenX/SuperLyricApi` `b7ad6e48…`）：**基於 Binder 的歌詞取得器/發布器**，有 Hook / 網路雙路徑，**按應用分發輸出目標**（魅族狀態欄歌詞 / 狀態欄歌詞 / 藍牙歌詞 / 桌面歌詞）。README 列出 LX Music 與 MusicFree → 桌面歌詞，Flamingo／光錐音樂 → API 原生支援，**YouTube Music 不受支援**。JitPack 依賴 `com.github.HChenX:SuperLyricApi:3.5`。

## 5.4 無 root 的通用方法（官方逐字）

- **`Notification.tickerText`**（`https://developer.android.com/reference/android/app/Notification#tickerText`）逐字：「Text that summarizes this notification for accessibility services. **As of the L release, this text is no longer shown on screen**, but it is still useful to accessibility services…」；`tickerView` 逐字「Formerly, a view showing the `tickerText`. **No longer displayed in the status bar as of API 21.**」
  → **`tickerText` 未被標 deprecated，但自 Android L（API 21）起系統不再在螢幕上顯示。** 這與魅族不衝突：魅族是「利用 `tickerText` 顯示功能做的一個定製功能」，屬 ROM 端復活該行為。
- **`MediaMetadata`**（`https://developer.android.com/reference/android/media/MediaMetadata`）：有 `METADATA_KEY_TITLE` / `ARTIST` / `ALBUM` / `DISPLAY_TITLE` 等，**`METADATA_KEY_LYRICS` 在該頁出現 0 次** → **官方 `MediaMetadata` 沒有歌詞欄位**。「把當前行塞進 `METADATA_KEY_TITLE`」屬**挪用**，不是官方設計用途。
- **哪些 ROM 會讀這些欄位顯示在狀態列**：魅族 Flyme 是（見 5.1）；小米 HyperOS 是但走焦點通知（見 5.2）；**其他 ROM：查不到**。**AOSP 原生不顯示**（see 上方 tickerText/tickerView 逐字）。

## 5.5 本節查不到

1. 第三方應用在**未 root** 情況下，被 AOSP 或任一廠商官方文件明示「讀取 `MediaMetadata` 特定欄位並顯示在狀態列」的做法（魅族與小米以外）。
2. `islandProperty` 的官方 schema、`ticker` 欄位的官方逐字定義。
3. `StatusBarLyric` / `Lyricon` 的逐應用支援清單。

---

# §6 iOS

## 6.1 系統級懸浮歌詞：不可能（交叉引用）

App 無法在其他 App 之上繪製系統級懸浮視窗；唯一的系統浮動窗是 Picture in Picture，且 `AVPictureInPictureController.ContentSource` 只接受影片來源（誤用會被 App Review 以 "Misusing PiP" 拒絕）；`MPNowPlayingInfoCenter.nowPlayingInfo` 接受的欄位子集**不含歌詞**，且 Apple 文件逐字「You don't have direct control over what information the system displays, or its formatting.」
→ **完整逐字與出處見 `packages-and-platform.md` §B2**，本檔不重複。

## 6.2 Live Activity：本地更新 vs 推播預算

Apple 文件為 JS 渲染，`WebFetch`/`tavily-extract` 只回導覽；**可行替代**是文件 JSON 端點 `https://developer.apple.com/tutorials/data/documentation/<path>.json`。以下皆為該 JSON 逐字。

**生命週期與大小限制**（`displaying-live-data-with-live-activities`）：
> 「A Live Activity can be active for up to **eight hours** unless its app or a person ends it… After the eight-hour limit, the system automatically ends the Live Activity… a Live Activity remains on the Lock Screen for a maximum of **12 hours**.」
> 「Each Live Activity runs in its own sandbox, and — unlike a widget — **it can't access the network** or receive location updates.」
> 「Static and dynamic data … including data for ActivityKit updates and ActivityKit push notifications, **can't exceed a combined size of 4 KB**.」
> 「the Music app displays an extended presentation in the Dynamic Island when a person starts playing audio in the app」

**推播更新的預算**（`starting-and-updating-live-activities-with-activitykit-push-notifications`，章節「Determine the update frequency」）：
> 「The system allows for a certain **budget of ActivityKit push notifications per hour**. As with other push notifications you send with APNs, you can set the HTTP header field `apns-priority`… If you don't specify the `apns-priority` value, APNs delivers the ActivityKit push notification immediately with the **default priority of `10`** and **counts it toward the notification budget** that the system imposes. If you exceed the budget, the system may **throttle** your ActivityKit push notifications.」
（另提及 `NSSupportsLiveActivitiesFrequentUpdates` Info.plist 開關。）

**本地 `Activity.update(_:)`** 逐字：
> 「Updates the dynamic content of the Live Activity. ## Discussion: Use this function to update the Live Activity while your app is in the foreground or while it's in the background… The system ignores attempts to update a Live Activity that ended.」

> **關鍵否定發現**：對抓下來的 Apple 文件 JSON grep `budget` / `throttl`，**只命中推播那篇**（`apple_push.json`），**未命中** `displaying-live-data…`、`Activity` class、`Activity.update(_:)`、ActivityKit 索引。
> → **Apple 官方只對「ActivityKit *push* notifications」記載「每小時預算／可能被 throttle」；對本地 `Activity.update(_:)` 並未記載任何預算或節流。** 「本地更新不受推播預算限制」是**由官方文件的有無推得**，Apple **未明文**寫出 → **推測**（**需實測**）。

## 6.3 成熟 iOS 音樂 App 的做法

- **Apple Music**（官方，Apple Newsroom 2025-06-09）：iOS 26 新增 `Lyrics Translation`（歌詞翻譯）與 `Lyrics Pronunciation`（歌詞發音），逐字「In Apple Music, Lyrics Translation helps users understand the words to their favorite songs, while Lyrics Pronunciation allows everyone to sing along, regardless of language.」。
- **Apple Music Live Activity 的動態歌詞**：MacStories 對 iOS 26 的敘述含「That's followed by a single line for lyrics that update live in time with the music, including when your iPhone is in Always-On mode.」→ **媒體，非官方**。**Apple 官方文件明示此事的敘述：查不到。**
- **Lyricify Mobile 1.5.1** 支援 iOS/iPadOS/macOS/Android/Windows（官網另列 visionOS）；iOS 版未上 App Store，需自簽 `.ipa`。
- **第三方歌詞 App**（**非**網易雲／QQ 音樂本體）：`Dynamic Lyrics` 商店敘述逐字「Dynamic Lyrics is an app that displays real-time lyrics and translations on your **lock screen, Dynamic Island, widgets, floating windows**, and more. It supports Apple Music and Spotify.」→ **App Store 商店頁，非官方技術文件**。
- **網易雲音樂 iOS / QQ 音樂 iOS 是否用 Live Activity / Dynamic Island / 鎖屏歌詞**：**查不到**官方或可靠來源。

## 6.4 CarPlay 與 macOS 選單列

**CarPlay**：
- `CPNowPlayingTemplate` 逐字：「A shared system template that displays Now Playing information… The Now Playing template displays information from `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`. … The template displays a series of playback control buttons, as well as information about the current album and artist… `CPNowPlayingTemplate` is only available in apps with the audio entitlement.」→ **不放歌詞**。
- `MPNowPlayingInfoCenter` 逐字：「The system displays Now Playing information on the device's Lock Screen and in the media controls in Control Center. …」→ **只涵蓋正在播放的中繼資料，沒有歌詞欄位**。
- **iOS 26 CarPlay 支援 widgets 與 Live Activities**（Apple Newsroom 逐字）：「…with **widgets and Live Activities**, users can stay in the loop without losing focus on the road. These updates also come to CarPlay Ultra…」；圖說逐字「Widgets are shown in CarPlay. / Live Activities are shown in CarPlay.」→ 官方確認這**兩個表面**存在；官方**未**說 Apple Music 在 CarPlay 上顯示逐行動態歌詞。
- **第三方（非官方）**：CarPlay 的 widget 需在 iPhone `設定 → 一般 → CarPlay → <車> → 小工具` 手動加入堆疊；第三方歌詞 widget（如 `Dynamic Lyrics`）可把當前歌詞行放進 CarPlay widget，每秒更新。
→ `https://developer.apple.com/documentation/carplay/cpnowplayingtemplate`、`https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter`、`https://www.apple.com/newsroom/2025/06/apple-elevates-the-iphone-experience-with-ios-26`

**macOS 選單列歌詞**：**查不到** Lyricify 或其他產品有明示此功能（Lyricify Mobile 支援 macOS，但其文件未提選單列歌詞；「妙控條」經查是 Lyricify 4 Windows 功能，見 §3.4）。

## 6.5 LX 是否有 iOS 版

**沒有。** LX Music Mobile README 逐字：「已支持的平台：- Android 5 及以上 / ***注：目前没有计划支持 iOS 和 HarmonyOS NEXT**。」
→ [lx-music-mobile `README.md`](https://github.com/lyswhut/lx-music-mobile/blob/fb8480728d875fa5e0da25eebd3a26bb71723aae/README.md)

## 6.6 本節查不到

1. Apple 官方文件明示 Apple Music 把歌詞放進 Live Activity / Dynamic Island / 鎖定畫面。
2. 網易雲音樂 iOS / QQ 音樂 iOS 是否使用 Live Activity / Dynamic Island / 鎖屏歌詞。
3. Lyricify 或其他產品做 macOS 選單列歌詞的明示證據。

---

# 附錄 A：本檔全部「推測」彙總

- 網易雲各旗標字母（`l/t/r/y/k`）的語意對應。
- `lxlrc` 不含行結束時間、行尾由最後一個詞推得。
- LX 把 YRC 的 `ytlrc` 丟進 `fixTimeTag` 時因正則不接受 `[start,dur]` 標籤而**可能整行被丟棄**（未實測）。
- `lyrics_parser` 與 Dart 3 不相容的說法可能與 `lyrics` 套件混淆。
- Wayland 協定層「空 region ⇒ 該 surface 不接收輸入」（協定未明文；GTK 實作佐證）。
- `desktop_lyrics` 的 Wayland 失效與 XWayland 路徑有關。
- 本地 `Activity.update(_:)` 不受推播預算限制（Apple 只對 push 記載預算）。
- `flutter_overlay_window` 的 overlay isolate 直接 `IsolatedAudioHandler.lookup` 會因跨 engine 失敗（**未實測**）。

# 附錄 B：本檔全部「查不到」彙總

見各節末尾的「本節查不到」小節（§1.10、§2.3/§2.4、§3.5、§4.6、§5.5、§6.6）。跨節重複出現者不再重列。
