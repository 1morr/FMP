// 評分核心的校準語料（M4 design §8.1）：手寫，不連網。
//
// 原曲是 Spotify／QQ 音樂會給的樣子（乾淨的歌名、歌手、時長；Spotify 的歌手常是
// 英文名，`(feat. …)` 與 ` - Remastered` 寫在歌名裡）；候選是 B 站、YouTube、網易雲
// 搜尋結果常見的上傳標題與上傳者。歌名與歌手都是真實的公開作品；時長是約略值，
// 上傳版本與原曲的差距照常見的情形寫（MV 有前奏或片尾所以比較長、搬運的音檔相同）。
//
// `lib/core/matching/matching.dart` 的權重、門檻與 `normalize.dart` 的詞表改了，
// 這份要全綠（`match_corpus_test.dart`）。
import 'package:fmp/core/matching/matching.dart';

Duration _d(int minutes, int seconds) =>
    Duration(minutes: minutes, seconds: seconds);

/// 一對原曲與候選，以及第一名是它時應不應該自動選。
final class CorpusPair {
  const CorpusPair(
    this.note,
    this.query,
    this.candidate, {
    required this.matches,
  });

  final String note;
  final MatchQuery query;
  final MatchCandidate candidate;
  final bool matches;
}

/// 同一首歌的幾個候選，[expectedFirst] 要排第一。
final class CorpusRanking {
  const CorpusRanking(
    this.note,
    this.query,
    this.candidates, {
    required this.expectedFirst,
  });

  final String note;
  final MatchQuery query;
  final List<MatchCandidate> candidates;
  final int expectedFirst;
}

const _sunny = MatchQuery(
  title: '晴天',
  artist: '周杰倫',
  duration: Duration(seconds: 269),
);

final corpusPairs = <CorpusPair>[
  // ── 應該選 ──
  CorpusPair(
    '官方 MV：歌名在括號裡、中英並列，上傳者是中英並列的頻道名',
    _sunny,
    MatchCandidate(
      title: '周杰倫 Jay Chou【晴天 Sunny Day】Official MV',
      uploader: '周杰倫 Jay Chou',
      duration: _d(4, 36),
    ),
    matches: true,
  ),
  CorpusPair(
    'B 站搬運：歌手在【】裡，標題帶音質字樣，上傳者不是歌手',
    _sunny,
    MatchCandidate(
      title: '【周杰伦】晴天 无损音质 高音质',
      uploader: '无损音乐搬运',
      duration: _d(4, 29),
    ),
    matches: true,
  ),
  CorpusPair(
    'Spotify 給英文歌手名、網易給中文：歌手對不上，靠歌名與時長',
    MatchQuery(title: '稻香', artist: 'Jay Chou', duration: _d(3, 43)),
    MatchCandidate(title: '稻香', uploader: '周杰伦', duration: _d(3, 43)),
    matches: true,
  ),
  CorpusPair(
    '繁簡：QQ 的繁體對網易的簡體',
    MatchQuery(title: '告白氣球', artist: '周杰倫', duration: _d(3, 35)),
    MatchCandidate(title: '告白气球', uploader: '周杰伦', duration: _d(3, 35)),
    matches: true,
  ),
  CorpusPair(
    '繁簡：`後來`／`后来`，`歌手 - 歌名 (高音质)`',
    MatchQuery(title: '後來', artist: '劉若英', duration: _d(5, 41)),
    MatchCandidate(
      title: '刘若英 - 后来 (高音质)',
      uploader: '经典老歌频道',
      duration: _d(5, 42),
    ),
    matches: true,
  ),
  CorpusPair(
    '《》裡是歌名，括號裡是電影資訊',
    MatchQuery(title: '小幸運', artist: '田馥甄', duration: _d(4, 25)),
    MatchCandidate(
      title: '田馥甄 Hebe Tien《小幸運》Official MV (電影「我的少女時代」主題曲)',
      uploader: '華研國際',
      duration: _d(4, 31),
    ),
    matches: true,
  ),
  CorpusPair(
    '歌手名寫法不同（`G.E.M.`／`GEM`），歌名中英並列在【】裡',
    MatchQuery(title: '光年之外', artist: 'G.E.M.鄧紫棋', duration: _d(3, 55)),
    MatchCandidate(
      title: 'G.E.M.鄧紫棋【光年之外 LIGHT YEARS AWAY】MV (電影《太空潛航者 Passengers》中文主題曲)',
      uploader: 'GEM鄧紫棋',
      duration: _d(4, 1),
    ),
    matches: true,
  ),
  CorpusPair(
    '《》與「完整版」',
    MatchQuery(title: '演员', artist: '薛之谦', duration: _d(4, 21)),
    MatchCandidate(title: '薛之谦《演员》完整版', uploader: '音乐小站', duration: _d(4, 22)),
    matches: true,
  ),
  CorpusPair(
    '歌詞頻道：`Artist - Title (Lyrics)`，大小寫不同',
    MatchQuery(
      title: 'Shape of You',
      artist: 'Ed Sheeran',
      duration: _d(3, 53),
    ),
    MatchCandidate(
      title: 'Ed Sheeran - Shape Of You (Lyrics)',
      uploader: '7clouds',
      duration: _d(3, 54),
    ),
    matches: true,
  ),
  CorpusPair(
    'VEVO 頻道、Official Audio',
    MatchQuery(
      title: 'Blinding Lights',
      artist: 'The Weeknd',
      duration: _d(3, 20),
    ),
    MatchCandidate(
      title: 'The Weeknd - Blinding Lights (Official Audio)',
      uploader: 'TheWeekndVEVO',
      duration: _d(3, 22),
    ),
    matches: true,
  ),
  CorpusPair(
    'YouTube 自動產生的 Topic 頻道',
    MatchQuery(title: 'Lemon', artist: 'Kenshi Yonezu', duration: _d(4, 15)),
    MatchCandidate(
      title: 'Lemon',
      uploader: 'Kenshi Yonezu - Topic',
      duration: _d(4, 15),
    ),
    matches: true,
  ),
  CorpusPair(
    '日文：「」裡是歌名，上傳者是兩個名字',
    MatchQuery(title: '夜に駆ける', artist: 'YOASOBI', duration: _d(4, 21)),
    MatchCandidate(
      title: 'YOASOBI「夜に駆ける」 Official Music Video',
      uploader: 'Ayase / YOASOBI',
      duration: _d(4, 23),
    ),
    matches: true,
  ),
  CorpusPair(
    '日文：歌名夾在兩個【】中間',
    MatchQuery(title: '千本桜', artist: '黒うさP', duration: _d(4, 5)),
    MatchCandidate(
      title: '【初音ミク】千本桜【オリジナル曲PV】',
      uploader: '黒うさP',
      duration: _d(4, 5),
    ),
    matches: true,
  ),
  CorpusPair(
    '多歌手（`&`），VEVO 頻道名少了冠詞',
    MatchQuery(
      title: 'Something Just Like This',
      artist: 'The Chainsmokers & Coldplay',
      duration: _d(4, 7),
    ),
    MatchCandidate(
      title: 'The Chainsmokers & Coldplay - Something Just Like This (Lyric)',
      uploader: 'ChainsmokersVEVO',
      duration: _d(4, 8),
    ),
    matches: true,
  ),
  CorpusPair(
    'Spotify 把 feat. 寫在歌名裡；候選的 ft. 在標題中間、後面還有電影名',
    MatchQuery(
      title: 'See You Again (feat. Charlie Puth)',
      artist: 'Wiz Khalifa, Charlie Puth',
      duration: _d(3, 49),
    ),
    MatchCandidate(
      title: 'Wiz Khalifa - See You Again ft. Charlie Puth [Official Video] Furious 7 Soundtrack',
      uploader: 'Wiz Khalifa',
      duration: _d(3, 57),
    ),
    matches: true,
  ),
  CorpusPair(
    '全形英數',
    MatchQuery(
      title: 'Love Story',
      artist: 'Taylor Swift',
      duration: _d(3, 55),
    ),
    MatchCandidate(
      title: '【Ｔａｙｌｏｒ Ｓｗｉｆｔ】Ｌｏｖｅ Ｓｔｏｒｙ【中英字幕】',
      uploader: '欧美音乐精选',
      duration: _d(3, 56),
    ),
    matches: true,
  ),
  CorpusPair(
    'Spotify 的 ` - Remastered 2011` 後綴',
    MatchQuery(
      title: 'Bohemian Rhapsody - Remastered 2011',
      artist: 'Queen',
      duration: _d(5, 54),
    ),
    MatchCandidate(
      title: 'Queen – Bohemian Rhapsody (Official Video Remastered)',
      uploader: 'Queen Official',
      duration: _d(5, 59),
    ),
    matches: true,
  ),
  CorpusPair(
    '網易：歌名與歌手都乾淨，繁簡不同',
    MatchQuery(title: '七里香', artist: '周杰倫', duration: _d(4, 59)),
    MatchCandidate(title: '七里香', uploader: '周杰伦', duration: _d(5, 0)),
    matches: true,
  ),
  CorpusPair(
    'B 站：【4K修复】、MV、中字都是裝飾',
    MatchQuery(title: '夜曲', artist: '周杰倫', duration: _d(3, 46)),
    MatchCandidate(
      title: '【4K修复】周杰伦 - 夜曲 MV 中字',
      uploader: '高清MV收藏',
      duration: _d(3, 53),
    ),
    matches: true,
  ),
  CorpusPair(
    '`歌名 - 歌手【动态歌词】`',
    MatchQuery(title: '起风了', artist: '买辣椒也用券', duration: _d(5, 25)),
    MatchCandidate(
      title: '起风了 - 买辣椒也用券【动态歌词】',
      uploader: '动态歌词排版',
      duration: _d(5, 25),
    ),
    matches: true,
  ),
  CorpusPair(
    '《》、官方MV、高清',
    MatchQuery(title: '青花瓷', artist: '周杰倫', duration: _d(3, 59)),
    MatchCandidate(
      title: '周杰伦《青花瓷》官方MV 高清',
      uploader: '音乐搬运',
      duration: _d(4, 0),
    ),
    matches: true,
  ),
  CorpusPair(
    '繁簡在歌名，上傳者是「歌手＋樂隊」',
    MatchQuery(title: '海闊天空', artist: 'Beyond', duration: _d(5, 26)),
    MatchCandidate(
      title: 'Beyond - 海阔天空 (官方MV)',
      uploader: 'Beyond乐队',
      duration: _d(5, 30),
    ),
    matches: true,
  ),
  CorpusPair(
    '`歌手 - 歌名 [高音质]`',
    MatchQuery(title: '月亮代表我的心', artist: '鄧麗君', duration: _d(3, 29)),
    MatchCandidate(
      title: '邓丽君 - 月亮代表我的心 [高音质]',
      uploader: '怀旧金曲',
      duration: _d(3, 30),
    ),
    matches: true,
  ),
  CorpusPair(
    'ft. 在括號之後',
    MatchQuery(
      title: 'Uptown Funk (feat. Bruno Mars)',
      artist: 'Mark Ronson, Bruno Mars',
      duration: _d(4, 30),
    ),
    MatchCandidate(
      title: 'Mark Ronson - Uptown Funk (Official Video) ft. Bruno Mars',
      uploader: 'Mark Ronson',
      duration: _d(4, 31),
    ),
    matches: true,
  ),
  CorpusPair(
    'Topic 頻道是英文名、原曲是中文名：歌手對不上',
    MatchQuery(title: '不能說的秘密', artist: '周杰倫', duration: _d(4, 56)),
    MatchCandidate(
      title: '不能说的秘密',
      uploader: 'Jay Chou - Topic',
      duration: _d(4, 56),
    ),
    matches: true,
  ),
  CorpusPair(
    '小寫歌名、Topic 頻道',
    MatchQuery(title: 'bad guy', artist: 'Billie Eilish', duration: _d(3, 14)),
    MatchCandidate(
      title: 'bad guy',
      uploader: 'Billie Eilish - Topic',
      duration: _d(3, 14),
    ),
    matches: true,
  ),
  CorpusPair(
    '`×` 連兩位歌手，『』裡是歌名',
    MatchQuery(title: '打上花火', artist: 'DAOKO × 米津玄師', duration: _d(4, 49)),
    MatchCandidate(
      title: 'DAOKO × 米津玄師『打上花火』MUSIC VIDEO',
      uploader: 'DAOKO',
      duration: _d(4, 56),
    ),
    matches: true,
  ),
  CorpusPair(
    '`-MUSiC CLiP-`',
    MatchQuery(title: '紅蓮華', artist: 'LiSA', duration: _d(3, 59)),
    MatchCandidate(
      title: 'LiSA 『紅蓮華』 -MUSiC CLiP-',
      uploader: 'LiSA Official YouTube',
      duration: _d(4, 1),
    ),
    matches: true,
  ),
  CorpusPair(
    '一個字的歌名',
    MatchQuery(title: '恋', artist: '星野源', duration: _d(4, 12)),
    MatchCandidate(title: '星野源 - 恋 【MV】', uploader: '星野源', duration: _d(4, 20)),
    matches: true,
  ),
  CorpusPair(
    '韓文歌名，英文譯名在括號裡（Spotify 給英文名）',
    MatchQuery(title: 'Spring Day', artist: 'BTS', duration: _d(4, 34)),
    MatchCandidate(
      title: '봄날 (Spring Day)',
      uploader: 'BTS',
      duration: _d(4, 34),
    ),
    matches: true,
  ),
  CorpusPair(
    'Official Video、VEVO',
    MatchQuery(
      title: 'You Raise Me Up',
      artist: 'Westlife',
      duration: _d(4, 1),
    ),
    MatchCandidate(
      title: 'Westlife - You Raise Me Up (Official Video)',
      uploader: 'WestlifeVEVO',
      duration: _d(4, 4),
    ),
    matches: true,
  ),
  CorpusPair(
    '原曲歌名帶 (with …)，候選把它放在另一個括號',
    MatchQuery(title: '說好不哭 (with 五月天阿信)', artist: '周杰倫', duration: _d(3, 42)),
    MatchCandidate(
      title: "周杰倫 Jay Chou【說好不哭 Won't Cry】(with 五月天阿信) Official MV",
      uploader: '周杰倫 Jay Chou',
      duration: _d(3, 48),
    ),
    matches: true,
  ),
  CorpusPair(
    '歌手名以 Official 開頭（不能當裝飾刪掉），全形［］，Spotify 給羅馬字團名',
    MatchQuery(
      title: 'Pretender',
      artist: 'Official HIGE DANDism',
      duration: _d(5, 27),
    ),
    MatchCandidate(
      title: 'Official髭男dism - Pretender［Official Video］',
      uploader: 'Official髭男dism',
      duration: _d(5, 32),
    ),
    matches: true,
  ),
  CorpusPair(
    '繁體上傳標題、官方完整版MV',
    MatchQuery(title: '江南', artist: '林俊傑', duration: _d(4, 28)),
    MatchCandidate(
      title: '林俊杰 JJ Lin - 江南 (官方完整版MV)',
      uploader: '林俊杰JJ Lin',
      duration: _d(4, 34),
    ),
    matches: true,
  ),
  CorpusPair(
    '原曲沒有時長（歌詞匹配時可能發生）',
    MatchQuery(title: '晴天', artist: '周杰倫'),
    MatchCandidate(title: '晴天', uploader: '周杰伦', duration: _d(4, 29)),
    matches: true,
  ),
  CorpusPair(
    '候選沒有上傳者',
    MatchQuery(title: 'Perfect', artist: 'Ed Sheeran', duration: _d(4, 23)),
    MatchCandidate(title: 'Ed Sheeran - Perfect', duration: _d(4, 23)),
    matches: true,
  ),
  CorpusPair(
    '原曲是 Live，候選也是（括號寫法不同）',
    MatchQuery(title: '晴天 (Live)', artist: '周杰倫', duration: _d(5, 2)),
    MatchCandidate(
      title: '周杰伦 晴天 现场版 2004无与伦比演唱会',
      uploader: '演唱会合集',
      duration: _d(5, 3),
    ),
    matches: true,
  ),
  CorpusPair(
    'B 站：歌手與一個字的歌名只隔空白',
    MatchQuery(title: '恋', artist: '星野源', duration: _d(4, 12)),
    MatchCandidate(title: '星野源 恋 中日字幕', uploader: '日语歌搬运', duration: _d(4, 12)),
    matches: true,
  ),
  CorpusPair(
    'Spotify 的 ` - From "…"/Soundtrack Version` 後綴',
    MatchQuery(
      title: 'Let It Go - From "Frozen"/Soundtrack Version',
      artist: 'Idina Menzel',
      duration: _d(3, 44),
    ),
    MatchCandidate(
      title: 'Let It Go',
      uploader: 'Idina Menzel - Topic',
      duration: _d(3, 44),
    ),
    matches: true,
  ),
  CorpusPair(
    '歌名整個是詞表的詞（`Karaoke`）',
    MatchQuery(title: 'Karaoke', artist: 'Drake', duration: _d(3, 48)),
    MatchCandidate(
      title: 'Karaoke',
      uploader: 'Drake - Topic',
      duration: _d(3, 48),
    ),
    matches: true,
  ),
  CorpusPair(
    '歌名與歌手同名',
    MatchQuery(
      title: 'Black Sabbath',
      artist: 'Black Sabbath',
      duration: _d(6, 20),
    ),
    MatchCandidate(
      title: 'Black Sabbath - Black Sabbath (Official Audio)',
      uploader: 'Black Sabbath',
      duration: _d(6, 21),
    ),
    matches: true,
  ),
  CorpusPair(
    '原歌手唱的 Live：版本不同但有歌手，不整首否決',
    MatchQuery(title: '七里香', artist: '周杰倫', duration: _d(4, 59)),
    MatchCandidate(title: '七里香 (Live)', uploader: '周杰伦', duration: _d(5, 5)),
    matches: true,
  ),
  CorpusPair(
    '原歌手自己上傳的伴奏：版本不同，歌手由上傳者對上',
    MatchQuery(title: 'Faded', artist: 'Alan Walker', duration: _d(3, 32)),
    MatchCandidate(
      title: 'Alan Walker - Faded (Instrumental)',
      uploader: 'Alan Walker',
      duration: _d(3, 32),
    ),
    matches: true,
  ),

  // ── 不該選 ──
  CorpusPair(
    'Live 版比原曲長很多',
    _sunny,
    MatchCandidate(
      title: '周杰伦 - 晴天 (Live)',
      uploader: '演唱会合集',
      duration: _d(5, 12),
    ),
    matches: false,
  ),
  CorpusPair(
    '鋼琴版：時長差很多',
    _sunny,
    MatchCandidate(title: '晴天 钢琴版 纯音乐', uploader: '钢琴小王子', duration: _d(3, 0)),
    matches: false,
  ),
  CorpusPair(
    '同名不同曲：時長不同',
    MatchQuery(title: 'Hello', artist: 'Adele', duration: _d(4, 55)),
    MatchCandidate(
      title: 'Lionel Richie - Hello',
      uploader: 'LionelRichieVEVO',
      duration: _d(4, 9),
    ),
    matches: false,
  ),
  CorpusPair(
    '同名不同曲：歌手、時長都不同',
    MatchQuery(
      title: 'Stay',
      artist: 'The Kid LAROI, Justin Bieber',
      duration: _d(2, 21),
    ),
    MatchCandidate(
      title: 'Rihanna - Stay ft. Mikky Ekko',
      uploader: 'RihannaVEVO',
      duration: _d(4, 0),
    ),
    matches: false,
  ),
  CorpusPair(
    '官方 MV 比音檔長很多',
    MatchQuery(
      title: 'Despacito',
      artist: 'Luis Fonsi, Daddy Yankee',
      duration: _d(3, 49),
    ),
    MatchCandidate(
      title: 'Luis Fonsi - Despacito ft. Daddy Yankee',
      uploader: 'LuisFonsiVEVO',
      duration: _d(4, 42),
    ),
    matches: false,
  ),
  CorpusPair(
    '官方 MV 比音檔長 30 秒',
    MatchQuery(
      title: 'Shape of You',
      artist: 'Ed Sheeran',
      duration: _d(3, 53),
    ),
    MatchCandidate(
      title: 'Ed Sheeran - Shape of You (Official Music Video)',
      uploader: 'Ed Sheeran',
      duration: _d(4, 23),
    ),
    matches: false,
  ),
  CorpusPair(
    '合集：標題裡有歌名',
    _sunny,
    MatchCandidate(
      title: '周杰伦 最好听的20首歌 合集 晴天 稻香 七里香',
      uploader: '音乐合集',
      duration: _d(80, 0),
    ),
    matches: false,
  ),
  CorpusPair(
    '同歌手、歌名開頭相同的另一首（候選沒有時長）',
    MatchQuery(title: '說好的幸福呢', artist: '周杰倫', duration: _d(4, 15)),
    MatchCandidate(title: '说好不哭', uploader: '周杰伦'),
    matches: false,
  ),
  CorpusPair(
    '同歌手的另一首（候選沒有時長）',
    MatchQuery(title: 'Faded', artist: 'Alan Walker', duration: _d(3, 32)),
    MatchCandidate(title: 'Alan Walker - Alone', uploader: 'Alan Walker'),
    matches: false,
  ),
  CorpusPair(
    '同曲不同詞：旋律與時長都一樣，歌名不同',
    MatchQuery(title: '愛情轉移', artist: '陳奕迅', duration: _d(4, 20)),
    MatchCandidate(title: '富士山下', uploader: '陈奕迅', duration: _d(4, 19)),
    matches: false,
  ),
  CorpusPair(
    '歌名是候選的開頭（`晴天`／`晴天娃娃`）',
    _sunny,
    MatchCandidate(title: '晴天娃娃', uploader: '儿歌精选'),
    matches: false,
  ),
  CorpusPair(
    '歌名是候選的開頭（`Lemon`／`Lemon Tree`）',
    MatchQuery(title: 'Lemon', artist: 'Kenshi Yonezu', duration: _d(4, 15)),
    MatchCandidate(title: 'Lemon Tree', uploader: 'Fools Garden'),
    matches: false,
  ),
  CorpusPair(
    '歌名是候選的一部分（節目名）',
    MatchQuery(title: '演员', artist: '薛之谦', duration: _d(4, 21)),
    MatchCandidate(title: '演员的诞生 第一期', uploader: '综艺频道'),
    matches: false,
  ),
  CorpusPair(
    '同歌手的另一首（時長不同）',
    MatchQuery(title: '七里香', artist: '周杰倫', duration: _d(4, 59)),
    MatchCandidate(title: '周杰伦 - 稻香', uploader: '音乐搬运', duration: _d(3, 43)),
    matches: false,
  ),
  CorpusPair(
    '別人的鋼琴版，時長在門檻內：版本不同又沒有歌手',
    MatchQuery(title: '小幸運', artist: '田馥甄', duration: _d(4, 25)),
    MatchCandidate(title: '小幸运 (钢琴版)', uploader: '钢琴曲', duration: _d(4, 20)),
    matches: false,
  ),
  CorpusPair(
    '別人的伴奏，時長相同：版本不同又沒有歌手',
    MatchQuery(title: '稻香', artist: 'Jay Chou', duration: _d(3, 43)),
    MatchCandidate(title: '稻香 伴奏 高品质', uploader: '伴奏库', duration: _d(3, 43)),
    matches: false,
  ),
  CorpusPair(
    '別人的翻唱，時長相近：版本不同又沒有歌手',
    _sunny,
    MatchCandidate(title: '【翻唱】晴天', uploader: '翻唱小站', duration: _d(4, 27)),
    matches: false,
  ),
  CorpusPair(
    '別人的翻唱，標題提到原歌手：版本標記下的歌手名是原唱，不算歌手分',
    _sunny,
    MatchCandidate(title: '【翻唱】周杰伦《晴天》', uploader: '翻唱小站', duration: _d(4, 29)),
    matches: false,
  ),
];

final corpusRankings = <CorpusRanking>[
  CorpusRanking('原版排在 Live、伴奏、翻唱前面（後三個都提到原歌手）', _sunny, [
    MatchCandidate(
      title: '周杰伦 - 晴天 (Live)',
      uploader: '演唱会现场',
      duration: _d(4, 35),
    ),
    MatchCandidate(
      title: '【伴奏】晴天 - 周杰伦 高品质伴奏',
      uploader: '伴奏库',
      duration: _d(4, 29),
    ),
    MatchCandidate(
      title: '晴天 (Cover 周杰伦) 女声版',
      uploader: '某翻唱歌手',
      duration: _d(4, 27),
    ),
    MatchCandidate(
      title: '【周杰伦】晴天 无损音质',
      uploader: '无损音乐搬运',
      duration: _d(4, 29),
    ),
  ], expectedFirst: 3),
  CorpusRanking('標題提到原歌手的翻唱、伴奏與歌手對不上的原版（Topic 頻道是英文名）：原版排前面', _sunny, [
    MatchCandidate(title: '【翻唱】周杰伦《晴天》', uploader: '翻唱小站', duration: _d(4, 29)),
    MatchCandidate(
      title: '【伴奏】晴天 - 周杰伦 高品质伴奏',
      uploader: '伴奏库',
      duration: _d(4, 29),
    ),
    MatchCandidate(
      title: '晴天',
      uploader: 'Jay Chou - Topic',
      duration: _d(4, 30),
    ),
  ], expectedFirst: 2),
  CorpusRanking(
    '同名不同曲：有歌手的排前面',
    MatchQuery(title: 'Hero', artist: 'Mariah Carey', duration: _d(4, 19)),
    [
      MatchCandidate(
        title: 'Enrique Iglesias - Hero (Official Music Video)',
        uploader: 'EnriqueIglesiasVEVO',
        duration: _d(4, 24),
      ),
      MatchCandidate(
        title: 'Mariah Carey - Hero (Official HD Video)',
        uploader: 'MariahCareyVEVO',
        duration: _d(4, 20),
      ),
    ],
    expectedFirst: 1,
  ),
  CorpusRanking(
    '原歌手的 Live 與原版：原版排前面',
    MatchQuery(title: '七里香', artist: '周杰倫', duration: _d(4, 59)),
    [
      MatchCandidate(title: '七里香 (Live)', uploader: '周杰伦', duration: _d(5, 5)),
      MatchCandidate(title: '七里香', uploader: '周杰伦', duration: _d(4, 59)),
    ],
    expectedFirst: 1,
  ),
  CorpusRanking(
    '原歌手的伴奏與原版：原版排前面',
    MatchQuery(title: 'Faded', artist: 'Alan Walker', duration: _d(3, 32)),
    [
      MatchCandidate(
        title: 'Alan Walker - Faded (Instrumental)',
        uploader: 'Alan Walker',
        duration: _d(3, 32),
      ),
      MatchCandidate(
        title: 'Alan Walker - Faded',
        uploader: 'Alan Walker',
        duration: _d(3, 33),
      ),
    ],
    expectedFirst: 1,
  ),
  CorpusRanking(
    'DJ 版與原版（歌手對不上時也一樣）',
    MatchQuery(title: '稻香', artist: 'Jay Chou', duration: _d(3, 43)),
    [
      MatchCandidate(title: '稻香 (DJ版)', uploader: 'DJ小鱼', duration: _d(3, 40)),
      MatchCandidate(title: '稻香', uploader: '周杰伦', duration: _d(3, 43)),
    ],
    expectedFirst: 1,
  ),
];

/// 已知分不出來的：同名、時長相近、上傳者不是歌手的另一首歌。它和「Spotify
/// 給英文歌手名」（上面的 `稻香`、`不能說的秘密`）在評分上一模一樣，要選後者
/// 就得接受前者。搜尋關鍵字帶第一位歌手（design §8.4），對的那首通常也在
/// 候選裡，由排序選到它（`corpusRankings` 的 `Hero`）。
final corpusKnownFalseMatches = <CorpusPair>[
  CorpusPair(
    '同名不同曲、時長在門檻內，只有它一個候選',
    MatchQuery(title: 'Hero', artist: 'Mariah Carey', duration: _d(4, 19)),
    MatchCandidate(
      title: 'Enrique Iglesias - Hero (Official Music Video)',
      uploader: 'EnriqueIglesiasVEVO',
      duration: _d(4, 24),
    ),
    matches: false,
  ),
];
