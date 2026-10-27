/* ==FMP Plugin==
{
  "id": "fmp-test",
  "name": "FMP Test Plugin",
  "version": "1.0.0",
  "author": "FMP",
  "apiVersion": 1,
  "capabilities": ["search", "resolveStream", "live", "mix", "multiPart", "trackDetail", "importPlaylist", "charts", "libraryRead", "libraryWrite", "login"],
  "allowedHosts": ["fmp.test"],
  "login": { "methods": ["qr", "cookie"], "refresh": "onStartup" }
}
==/FMP Plugin== */

// FMP 的測試插件（ADR 0015 §決定 6）：合成資料、不發任何網路請求。串流指向
// App 內附的音檔（dev flavor 的 asset），給執行環境的測試、實機驗證與量測用。

const TONES = [220, 440, 880];
// 播放數（ADR 0035 §決定 10）：搜尋結果與榜單的曲目帶 viewCount，看縮寫（1234、460萬／4.6M、12）。
const VIEW_COUNTS = { 220: 1234, 440: 4600000, 880: 12 };
const PAGE_SIZE = 2;
const TONE_ASSET = 'asset:///test/fixtures/plugins/test_plugin/tone.wav';
const MISSING_ASSET = 'asset:///test/fixtures/plugins/test_plugin/missing.wav';
const LIVE_ASSET = 'asset:///test/fixtures/plugins/test_plugin/live.wav';

// 關鍵字剛好是它時，搜尋以限流失敗：實機不連網也能看到錯誤提示（ADR 0027
// 「測試插件不足以涵蓋某類 UI 時先補測試插件」）。
const FAIL_KEYWORD = 'fail';

// 關鍵字剛好是它時，第一頁第二首的串流指向不存在的 asset：兩首加進佇列連播，
// 第二首的前瞻開不起來，第一首照常播完、第二首走恢復（實機不連網也看得到）。
const MISSING_NEXT_KEYWORD = 'missing';

// 播放恢復的實機驗證（ADR 0018 §決定 7），都不連網：
// - 關鍵字剛好是 `preview` 時，每一首都只回試聽片段（previewOnly）：「跳過試聽
//   片段」開著就跳過並提示，關著就照播並在播放列標「試聽」。
// - 關鍵字剛好是 `flaky` 時，每一首的解析輪流以 NetworkError 失敗與成功（第一次
//   失敗）：在線上是「重試中」一秒後播起來；網路狀態不是 online（模擬器開飛航
//   模式）時停在「等待網路連線」，網路回來後自動從原位置續播。
// - 關鍵字剛好是 `unavailable` 時，第一頁第一首以 Unavailable（版權）失敗：和
//   第二首一起加進佇列播放，第一首跳過並提示原因。
const PREVIEW_KEYWORD = 'preview';
// 遠端寫入的實機驗證：關鍵字剛好是 `write-fail` 時，第一頁第一首的 sourceId 是 `fail`，
// `addToPlaylist` 對它回 `failed`（見「遠端寫入」）。
const WRITE_FAIL_KEYWORD = 'write-fail';
const FLAKY_KEYWORD = 'flaky';
const UNAVAILABLE_KEYWORD = 'unavailable';

// `flaky-` 曲目各自解析過幾次（插件的 isolate 活著就一直留著）。
const flakyCalls = new Map();

// 假的登入（ADR 0029），不連網。QR：每次產生的 QR 碼內容固定，第二次輪詢就完成，
// 交出一個一看就是假的憑證。貼上 cookie：`loginVerify` 認任何帶 `fmp_test_session`
// （值不空）的 cookie，貼 `fmp_test_session=anything` 就能登入。
const FAKE_QR_TEXT = 'fmp-test://login';
const FAKE_SESSION_COOKIE = 'fmp_test_session';
const FAKE_SESSION = 'fake-session-0000';

// 失效與刷新（design §6.5），不連網。插件不發請求，看不到 `credentialsAttached`，
// 所以以 `fmp.credentials.get()` 是否有憑證當「這次帶了憑證」。狀態存在 storage 的
// `expiry`：
// - 關鍵字剛好是 `expired`、已登入：第一次丟 CredentialInvalid（expiry＝pending），宿主
//   呼叫 loginRefresh 換成新憑證（expiry＝renewed）後重跑，這次成功並清掉 expiry。
// - 關鍵字剛好是 `expired-hard`、已登入：丟 CredentialInvalid（expiry＝hard），
//   loginRefresh 也以 CredentialInvalid 失敗，帳號轉成已失效；重新登入清掉 expiry。
// - 其他時候 loginRefresh 回 null（啟動刷新：沒有變動）。
const EXPIRED_KEYWORD = 'expired';
const EXPIRED_HARD_KEYWORD = 'expired-hard';

// 直播（ADR 0028 §決定 3），不連網。固定五個直播間，行為見 README：
// - live-ok：一直開播中，串流是 60 秒的 live.wav。
// - live-offline：未開播，解析串流以 NotFound 失敗。
// - live-drop：一直開播中，但串流只有 2 秒：每次重連又在 2 秒後結束。
// - live-ended：這個 isolate 第一次查是開播中，之後都是未開播（提前結束後問狀態）。
// - live-broken：查狀態與解析串流都以 NetworkError 失敗（搜尋結果裡標開播中）。
const LIVE_ROOMS = [
  { roomId: 'live-ok', title: 'Test live room', hostName: 'FMP', status: 'live', online: 42, area: 'Test area' },
  { roomId: 'live-offline', title: 'Test offline room', hostName: 'FMP', status: 'offline', area: 'Chat' },
  { roomId: 'live-drop', title: 'Test dropping room', hostName: 'FMP', status: 'live', online: 7 },
  { roomId: 'live-ended', title: 'Test ending room', hostName: 'FMP', status: 'live', online: 3 },
  { roomId: 'live-broken', title: 'Test broken room', hostName: 'FMP', status: 'live', online: 1 },
];
const LIVE_URL = /^https:\/\/fmp\.test\/live\/([a-z-]+)$/;

// live-ended 已經查過幾次狀態。
let liveEndedChecks = 0;

// Mix（ADR 0028 §決定 4），不連網。任何 seed 都開一個新的 Mix（mixId 每次不同，重啟
// 後也不會撞上佇列裡還留著的舊曲目鍵），每批 5 首，曲目鍵是 `mix-<mixId>-<n>`：
// - 第一批 n＝1–5，cursor 是 `2`；
// - 第二批 n＝3、6–9，cursor 是 `3`：第 3 首刻意重複第一批的，驗證宿主去重；
// - 第三批 n＝10–14，沒有 cursor：Mix 到此為止，宿主改以佇列最後一首當 seed 開新的一批。
const MIX_BATCHES = {
  2: { numbers: [3, 6, 7, 8, 9], cursor: '3' },
  3: { numbers: [10, 11, 12, 13, 14], cursor: null },
};
let mixCount = 0;

// 分 P（ADR 0028 §決定 5），不連網。關鍵字剛好是 `parts` 時，三首各是一種分 P 狀況：
// - parts-220：搜尋結果帶 partCount 3；multiPart 回三個分 P（cid 22001–22003）。
// - parts-440：搜尋結果沒有 partCount（B 站的搜尋回應就沒有）；multiPart 回兩個分 P
//   （cid 44001、44002）：展開鈕照顯示，影片選單先取分 P 再套用到全部。
// - parts-880：沒有 partCount；multiPart 只回一個分 P：展開後鈕消失，選單照單曲處理。
// 其他關鍵字的曲目都帶 partCount 1（確定單 P，不顯示展開鈕）。
const PARTS_KEYWORD = 'parts';
const PART_TITLES = ['Part one', 'Part two', 'Part three'];
const PART_COUNTS = { 220: 3, 440: 2, 880: 1 };

// 曲目詳細（ADR 0028 §決定 6），不連網：
// - tone-440：完整的詳細資料（長簡介、發佈時間、專輯、七種統計；allowedHosts 是空的，
//   沒有可用的頭像網址，所以沒有 uploaderAvatar；有 webUrl）；
// - tone-880：以 NetworkError 失敗，看詳細區的失敗與重試；
// - 其他曲目：空的詳細資料。
const DETAIL_FULL_ID = 'tone-440';
const DETAIL_FAIL_ID = 'tone-880';

// 歌單匯入（ADR 0032 §決定 2），不連網；狀態存在這個 isolate 的記憶體，到 App 重啟為止。
// `playlistFromUrl` 認 `https://fmp.test/playlist/<id>`（任何 id；不存在的 id 在
// `importPlaylist` 才 NotFound）與 `https://fmp.test/mix/<sourceId>`（回 mixSeed）。歌單：
// - pl-basic：5 首、每頁 3 首（cursor `3`），第 1、4 首是同一首（曲目鍵與資料都相同）；
//   沒有 remoteItemId。
// - pl-grow：單頁，有 remoteItemId，每項是不同的曲目（`grow-<n>`，看得出順序）。每次取
//   第一頁（＝每刷新一次）輪流：新增一首、移除最前面一首、整張倒序。
// - pl-partial：第 1 頁 3 首，第 2 頁（cursor `3`）NetworkError。
// - pl-gone：NotFound。
// - pl-auth：沒有憑證 AuthRequired；有就回 3 首、writable: true（內容在記憶體，`libraryWrite`
//   會改它，見下面「遠端寫入」）。
// - pl-unavailable：3 首，第 2 首 unavailable。
// - pl-long：1200 首、每頁 50 首（cursor 是位移），每頁都給 total 1200；曲目 `long-<n>`，標題
//   `Long track <n>`（給匯入進度與取消的實機驗證）。
// - pl-long-nototal：同 pl-long，但不給 total（進度只顯示「已讀 n 首」）。
// - pl-long-slow：同 pl-long，但每頁先忙等 300ms（約 7 秒讀完），實機看得到進度、來得及按取消。
// - pl-parts：一支 3 P 的影片（parts-220）展開成 3 首，帶 partIndex、parentTitle；不給 total。
const PLAYLIST_URL = /^https:\/\/fmp\.test\/playlist\/([a-z0-9-]+)$/;
const MIX_URL = /^https:\/\/fmp\.test\/mix\/([a-z0-9-]+)$/;
const IMPORT_PAGE_SIZE = 3;
const LONG_TRACKS = 1200;
const LONG_PAGE_SIZE = 50;
const BASIC_TRACKS = [440, 220, 880, 440, 330];

// pl-grow 目前的內容（遠端項目 id 的清單，順序就是遠端順序）與已經取過幾次第一頁。
let growItems = [1, 2, 3, 4];
let growNext = 5;
let growFetches = 0;

function playlistTrack(sourceId, title, extra) {
  return { sourceId, title, uploader: 'FMP', durationMs: 2000, artwork: [], ...extra };
}

// 遠端寫入（ADR 0032 §決定 4），不連網；同樣存在這個 isolate 的記憶體。帳號自己的、可寫的歌單：
// `pl-auth`（從 3 首起，每項有 remoteItemId `auth-<n>`）與 `createPlaylist` 建的 `pl-new-<n>`（空）。
// - addToPlaylist：歌單裡沒有就加到尾端（`added`），已經有（同 sourceId 與 cid）是 `alreadyPresent`；
//   sourceId 剛好是 `fail` 的那一首 `failed`（帶結構化錯誤）。搜尋 `write-fail` 的第一首就是它。
// - removeFromPlaylist：有 remoteItemId 就以它找，否則以 sourceId 與 cid 找；找到移除（`removed`），
//   找不到 `notPresent`；sourceId 是 `fail` 的 `failed`（遠端不會有這一首，只有契約測試走到它）。
// - 寫入前沒有憑證 AuthRequired；歌單不是帳號自己的可寫歌單（例如 pl-basic）NotFound。
const WRITE_FAIL_SOURCE_ID = 'fail';
const accountPlaylists = new Map([
  [
    'pl-auth',
    {
      title: 'Private playlist',
      items: basicItems()
        .slice(0, 3)
        .map((item, index) => ({ ...item, remoteItemId: `auth-${index + 1}` })),
    },
  ],
]);
let accountItemCount = 3;
let createdCount = 0;

function accountTrack(ref) {
  const tone = /^tone-(\d+)$/.exec(ref.sourceId);
  const title = tone === null ? `Added ${ref.sourceId}` : `Playlist tone ${tone[1]} Hz`;
  return playlistTrack(ref.sourceId, title, ref.cid === undefined || ref.cid === null ? {} : { cid: ref.cid });
}

function sameItem(item, ref) {
  if (ref.remoteItemId !== undefined && ref.remoteItemId !== null) {
    return item.remoteItemId === ref.remoteItemId;
  }
  return item.track.sourceId === ref.sourceId && (item.track.cid ?? null) === (ref.cid ?? null);
}

async function writablePlaylist(playlistId) {
  if ((await fmp.credentials.get()) === null) {
    throw { fmpError: 'AuthRequired', message: 'log in to change your playlists' };
  }
  const playlist = accountPlaylists.get(playlistId);
  if (playlist === undefined) {
    throw { fmpError: 'NotFound', message: `not a writable playlist: ${playlistId}` };
  }
  return playlist;
}

const WRITE_FAILED = {
  status: 'failed',
  error: { fmpError: 'RateLimited', retryAfterSeconds: 30, message: 'forced failure for on-device checks' },
};

export async function createPlaylist(query) {
  if ((await fmp.credentials.get()) === null) {
    throw { fmpError: 'AuthRequired', message: 'log in to change your playlists' };
  }
  createdCount += 1;
  const playlistId = `pl-new-${createdCount}`;
  accountPlaylists.set(playlistId, { title: query.title, items: [] });
  return { playlistId };
}

export async function addToPlaylist(query) {
  const playlist = await writablePlaylist(query.playlistId);
  const results = query.tracks.map((ref) => {
    if (ref.sourceId === WRITE_FAIL_SOURCE_ID) return WRITE_FAILED;
    if (playlist.items.some((item) => sameItem(item, ref))) return { status: 'alreadyPresent' };
    accountItemCount += 1;
    playlist.items.push({ track: accountTrack(ref), remoteItemId: `auth-${accountItemCount}` });
    return { status: 'added' };
  });
  return { results };
}

export async function removeFromPlaylist(query) {
  const playlist = await writablePlaylist(query.playlistId);
  const results = query.items.map((ref) => {
    if (ref.sourceId === WRITE_FAIL_SOURCE_ID) return WRITE_FAILED;
    const index = playlist.items.findIndex((item) => sameItem(item, ref));
    if (index < 0) return { status: 'notPresent' };
    playlist.items.splice(index, 1);
    return { status: 'removed' };
  });
  return { results };
}

// 帳號自己的歌單的一頁：`pl-auth` 與 `pl-new-<n>`，內容就是記憶體裡現在的。
async function accountPage(playlistId, meta) {
  const playlist = await writablePlaylist(playlistId);
  return {
    playlist: { ...meta, title: playlist.title, writable: true },
    items: playlist.items,
    cursor: null,
    total: playlist.items.length,
  };
}

// 同一首曲目在每張歌單、每個位置的資料都一樣（真的音源也是），宿主依曲目鍵存一份。
function basicItems() {
  return BASIC_TRACKS.map((hz) => ({
    track: playlistTrack(`tone-${hz}`, `Playlist tone ${hz} Hz`),
  }));
}

function growStep() {
  growFetches += 1;
  switch (growFetches % 3) {
    case 1:
      growItems = [...growItems, growNext++];
      break;
    case 2:
      growItems = growItems.slice(1);
      break;
    default:
      growItems = [...growItems].reverse();
  }
}

function pagedItems(items, cursor) {
  const start = cursor === undefined || cursor === null ? 0 : Number(cursor);
  const end = start + IMPORT_PAGE_SIZE;
  return { items: items.slice(start, end), cursor: end < items.length ? String(end) : null };
}

function longPage(cursor, title, withTotal) {
  const start = cursor === undefined || cursor === null ? 0 : Number(cursor);
  const end = Math.min(start + LONG_PAGE_SIZE, LONG_TRACKS);
  const items = [];
  for (let n = start + 1; n <= end; n += 1) {
    items.push({ track: playlistTrack(`long-${n}`, `Long track ${n}`) });
  }
  return {
    playlist: { ownerName: 'FMP', title },
    items,
    cursor: end < LONG_TRACKS ? String(end) : null,
    ...(withTotal ? { total: LONG_TRACKS } : {}),
  };
}

export function playlistFromUrl(query) {
  const playlist = PLAYLIST_URL.exec(query.url);
  if (playlist !== null) return { playlistId: playlist[1] };
  const mix = MIX_URL.exec(query.url);
  if (mix !== null) return { mixSeed: { sourceId: mix[1] } };
  return null;
}

export async function importPlaylist(query) {
  const id = query.playlistId;
  const meta = { ownerName: 'FMP' };
  switch (id) {
    case 'pl-basic': {
      const page = pagedItems(basicItems(), query.cursor);
      return { playlist: { ...meta, title: 'Basic playlist' }, ...page, total: BASIC_TRACKS.length };
    }
    case 'pl-grow': {
      if (query.cursor === undefined || query.cursor === null) growStep();
      return {
        playlist: { ...meta, title: 'Growing playlist' },
        items: growItems.map((n) => ({
          track: playlistTrack(`grow-${n}`, `Grow track ${n}`),
          remoteItemId: `grow-${n}`,
        })),
        cursor: null,
        total: growItems.length,
      };
    }
    case 'pl-partial': {
      if (query.cursor !== undefined && query.cursor !== null) {
        throw { fmpError: 'NetworkError', message: 'forced failure for on-device checks' };
      }
      const page = pagedItems(basicItems(), query.cursor);
      return { playlist: { ...meta, title: 'Partial playlist' }, ...page, total: BASIC_TRACKS.length };
    }
    case 'pl-long':
      return longPage(query.cursor, 'Long playlist', true);
    case 'pl-long-nototal':
      return longPage(query.cursor, 'Long playlist (no total)', false);
    case 'pl-long-slow': {
      // 宿主沒有計時器；每次呼叫有 30 秒的看門狗，300ms 遠在其下。
      const until = Date.now() + 300;
      while (Date.now() < until) {
        // 忙等
      }
      return longPage(query.cursor, 'Long playlist (slow)', true);
    }
    case 'pl-gone':
      throw { fmpError: 'NotFound', message: 'the playlist is gone' };
    case 'pl-auth':
      return accountPage(id, meta);
    case 'pl-unavailable':
      return {
        playlist: { ...meta, title: 'Unavailable playlist' },
        items: basicItems()
          .slice(0, 3)
          .map((item, index) => (index === 1 ? { ...item, unavailable: true } : item)),
        cursor: null,
        total: 3,
      };
    case 'pl-parts':
      return {
        playlist: { ...meta, title: 'Multi-part playlist' },
        items: PART_TITLES.map((title, index) => ({
          track: playlistTrack('parts-220', title, {
            cid: 22001 + index,
            partIndex: index + 1,
            parentTitle: 'Test multi-part video',
          }),
        })),
        cursor: null,
      };
    default:
      if (accountPlaylists.has(id)) return accountPage(id, meta);
      throw { fmpError: 'NotFound', message: `no such playlist: ${id}` };
  }
}

// 帳號的歌單（ADR 0032 §決定 3），不連網：沒有憑證 AuthRequired；登入後一頁（不分頁），
// pl-auth（可寫）、pl-basic（不可寫），再接 `createPlaylist` 建的（可寫）；標題與首數同
// `importPlaylist` 回的。
export async function libraryPlaylists() {
  if ((await fmp.credentials.get()) === null) {
    throw { fmpError: 'AuthRequired', message: 'log in to read your playlists' };
  }
  const writable = [...accountPlaylists].map(([playlistId, playlist]) => ({
    playlistId,
    title: playlist.title,
    trackCount: playlist.items.length,
    writable: true,
  }));
  return {
    playlists: [
      writable[0],
      { playlistId: 'pl-basic', title: 'Basic playlist', trackCount: BASIC_TRACKS.length, writable: false },
      { playlistId: 'pl-long', title: 'Long playlist', trackCount: LONG_TRACKS, writable: false },
      ...writable.slice(1),
    ],
    cursor: null,
  };
}

// 帳號關注的直播間（ADR 0032 §決定 3），不連網：沒有憑證 AuthRequired；登入後就是上面五個
// 直播間（同 liveSearch 的資料，不分登入狀態、不隨操作改變）。
export async function libraryLiveRooms() {
  if ((await fmp.credentials.get()) === null) {
    throw { fmpError: 'AuthRequired', message: 'log in to read your live rooms' };
  }
  return { rooms: LIVE_ROOMS.map((room) => ({ ...room, artwork: [] })) };
}

// 每個 QR 碼（token）已經輪詢過幾次。
const qrPolls = new Map();
let qrCount = 0;

function sourceIdFor(keyword, index, hz) {
  switch (keyword) {
    case MISSING_NEXT_KEYWORD:
      return index === 1 ? `missing-${hz}` : `tone-${hz}`;
    case UNAVAILABLE_KEYWORD:
      return index === 0 ? `unavailable-${hz}` : `tone-${hz}`;
    case PREVIEW_KEYWORD:
      return `preview-${hz}`;
    case WRITE_FAIL_KEYWORD:
      return index === 0 ? WRITE_FAIL_SOURCE_ID : `tone-${hz}`;
    case FLAKY_KEYWORD:
      return `flaky-${hz}`;
    case PARTS_KEYWORD:
      return `parts-${hz}`;
    default:
      return `tone-${hz}`;
  }
}

// 標題的前綴可以用 storage 改（`titlePrefix`），順便走一次非同步的宿主函式。
export async function search(query) {
  if (query.keyword === FAIL_KEYWORD) {
    throw { fmpError: 'RateLimited', message: 'forced failure for on-device checks' };
  }
  if (query.keyword === EXPIRED_KEYWORD || query.keyword === EXPIRED_HARD_KEYWORD) {
    const credentials = await fmp.credentials.get();
    const hard = query.keyword === EXPIRED_HARD_KEYWORD;
    const expiry = await fmp.storage.get('expiry');
    if (credentials !== null && (hard || expiry !== 'renewed')) {
      await fmp.storage.set('expiry', hard ? 'hard' : 'pending');
      throw { fmpError: 'CredentialInvalid', message: 'forced failure for on-device checks' };
    }
    await fmp.storage.delete('expiry');
  }
  const prefix = (await fmp.storage.get('titlePrefix')) ?? 'Test tone';
  const start = (query.page - 1) * PAGE_SIZE;
  const items = TONES.slice(start, start + PAGE_SIZE).map((hz, index) => ({
    sourceId: sourceIdFor(query.keyword, start + index, hz),
    title: `${prefix} ${hz} Hz (${query.keyword})`,
    uploader: 'FMP',
    durationMs: 2000,
    artwork: [],
    viewCount: VIEW_COUNTS[hz],
    ...partCountFor(query.keyword, hz),
  }));
  return { items, hasMore: start + PAGE_SIZE < TONES.length };
}

function partCountFor(keyword, hz) {
  if (keyword !== PARTS_KEYWORD) return { partCount: 1 };
  return hz === 220 ? { partCount: 3 } : {};
}

export async function resolveStream(request) {
  if (/^missing-\d+$/.test(request.sourceId)) {
    return {
      candidates: [
        {
          url: MISSING_ASSET,
          container: 'wav',
          codec: 'pcm_s16le',
          bitrate: 256000,
          expiresAt: null,
        },
      ],
    };
  }
  if (/^unavailable-\d+$/.test(request.sourceId)) {
    throw {
      fmpError: 'Unavailable',
      reason: 'copyright',
      message: 'forced failure for on-device checks',
    };
  }
  if (/^flaky-\d+$/.test(request.sourceId)) {
    const calls = (flakyCalls.get(request.sourceId) ?? 0) + 1;
    flakyCalls.set(request.sourceId, calls);
    if (calls % 2 === 1) {
      throw { fmpError: 'NetworkError', message: 'forced failure for on-device checks' };
    }
  } else if (!/^(tone|preview|parts|grow|long)-\d+$/.test(request.sourceId) && !/^mix-.+-\d+$/.test(request.sourceId)) {
    throw { fmpError: 'NotFound', message: `no such tone: ${request.sourceId}` };
  }
  // 內附的音檔只有 440 Hz 一個；其他音高也回它。
  return {
    previewOnly: request.sourceId.startsWith('preview-'),
    candidates: [
      {
        url: TONE_ASSET,
        container: 'wav',
        codec: 'pcm_s16le',
        bitrate: 256000,
        expiresAt: null,
      },
    ],
  };
}

export function loginQrStart() {
  qrCount += 1;
  const token = `qr-${qrCount}`;
  qrPolls.set(token, 0);
  return { qrText: FAKE_QR_TEXT, token };
}

export function loginQrPoll(token) {
  if (!qrPolls.has(token)) return { status: 'expired' };
  const polls = qrPolls.get(token) + 1;
  if (polls < 2) {
    qrPolls.set(token, polls);
    return { status: 'waiting' };
  }
  qrPolls.delete(token);
  return { status: 'done', credentials: { cookies: { [FAKE_SESSION_COOKIE]: FAKE_SESSION } } };
}

export async function loginVerify(credentials) {
  if (!credentials.cookies[FAKE_SESSION_COOKIE]) {
    throw { fmpError: 'CredentialInvalid', message: 'no fake session cookie of the test plugin' };
  }
  await fmp.storage.delete('expiry');
  return { userId: 'fmp-test-user', displayName: 'FMP Test User' };
}

export async function loginRefresh(credentials) {
  const expiry = await fmp.storage.get('expiry');
  if (expiry === 'hard') {
    throw { fmpError: 'CredentialInvalid', message: 'forced failure for on-device checks' };
  }
  if (expiry !== 'pending') return null;
  const renewals = Number((await fmp.storage.get('renewals')) ?? '0') + 1;
  await fmp.storage.set('renewals', String(renewals));
  await fmp.storage.set('expiry', 'renewed');
  return {
    cookies: {
      ...credentials.cookies,
      [FAKE_SESSION_COOKIE]: `fake-session-${String(renewals).padStart(4, '0')}`,
    },
  };
}

export function liveSearch(query) {
  if (query.keyword === FAIL_KEYWORD) {
    throw { fmpError: 'RateLimited', message: 'forced failure for on-device checks' };
  }
  const items = LIVE_ROOMS.filter((room) => !query.status || room.status === query.status).map(
    (room) => ({ ...room, artwork: [] }),
  );
  return { items, hasMore: false };
}

export function liveRoomFromUrl(query) {
  const match = LIVE_URL.exec(query.url);
  if (match === null || !LIVE_ROOMS.some((room) => room.roomId === match[1])) return null;
  return { roomId: match[1] };
}

function liveRoom(roomId) {
  const room = LIVE_ROOMS.find((candidate) => candidate.roomId === roomId);
  if (room === undefined) throw { fmpError: 'NotFound', message: `no such live room: ${roomId}` };
  return room;
}

export function liveStatus(query) {
  const room = liveRoom(query.roomId);
  if (room.roomId === 'live-broken') {
    throw { fmpError: 'NetworkError', message: 'forced failure for on-device checks' };
  }
  if (room.roomId === 'live-ended') {
    liveEndedChecks += 1;
    return { ...room, artwork: [], status: liveEndedChecks === 1 ? 'live' : 'offline' };
  }
  return { ...room, artwork: [] };
}

export function resolveLive(request) {
  const room = liveRoom(request.roomId);
  if (room.roomId === 'live-offline') {
    // 沒有「未開播」的錯誤：NotFound（現在沒有串流）比 Unavailable 的任何原因都不誤導。
    throw { fmpError: 'NotFound', message: 'the live room is offline' };
  }
  if (room.roomId === 'live-broken') {
    throw { fmpError: 'NetworkError', message: 'forced failure for on-device checks' };
  }
  return {
    candidates: [
      {
        url: room.roomId === 'live-ok' ? LIVE_ASSET : TONE_ASSET,
        container: 'wav',
        codec: 'pcm_s16le',
        bitrate: room.roomId === 'live-ok' ? 128000 : 256000,
        expiresAt: null,
      },
    ],
  };
}

function mixTracks(mixId, numbers) {
  return numbers.map((number) => ({
    sourceId: `mix-${mixId}-${number}`,
    title: `Test mix track ${number}`,
    uploader: 'FMP',
    durationMs: 2000,
    artwork: [],
  }));
}

// 排行（ADR 0032 §決定 5），不連網。三個榜單：
// - hot：5 首；
// - new：3 首；
// - broken：以 NetworkError 失敗（單一榜單失敗不影響其他榜單）。
// 曲目沿用 tone-<hz>（可播）。
const CHARTS = [
  { chartId: 'hot', title: 'Hot', hz: [440, 220, 880, 330, 550] },
  { chartId: 'new', title: 'New', hz: [110, 660, 770] },
  { chartId: 'broken', title: 'Broken', hz: [] },
];

export function chartList() {
  return { charts: CHARTS.map(({ chartId, title }) => ({ chartId, title })) };
}

export function chart(query) {
  const found = CHARTS.find((entry) => entry.chartId === query.chartId);
  if (found === undefined) {
    throw { fmpError: 'NotFound', message: `no such chart: ${query.chartId}` };
  }
  if (found.chartId === 'broken') {
    throw { fmpError: 'NetworkError', message: 'forced failure for on-device checks' };
  }
  return {
    tracks: found.hz.map((hz) =>
      playlistTrack(`tone-${hz}`, `${found.title} tone ${hz} Hz`, { viewCount: VIEW_COUNTS[hz] }),
    ),
  };
}

export function mix(query) {
  if (query.seed) {
    mixCount += 1;
    const mixId = `m${mixCount}x${Date.now().toString(36)}`;
    return {
      mixId,
      title: `Test mix ${mixCount}`,
      tracks: mixTracks(mixId, [1, 2, 3, 4, 5]),
      cursor: '2',
    };
  }
  const batch = MIX_BATCHES[query.cursor];
  if (batch === undefined) {
    throw { fmpError: 'NotFound', message: `no such mix cursor: ${query.cursor}` };
  }
  return {
    mixId: query.mixId,
    title: 'Test mix',
    tracks: mixTracks(query.mixId, batch.numbers),
    cursor: batch.cursor,
  };
}

export function multiPart(query) {
  const match = /^parts-(\d+)$/.exec(query.sourceId);
  const count = match === null ? undefined : PART_COUNTS[Number(match[1])];
  if (count === undefined) {
    throw { fmpError: 'NotFound', message: `no such multi-part video: ${query.sourceId}` };
  }
  return {
    parts: PART_TITLES.slice(0, count).map((title, index) => ({
      cid: Number(match[1]) * 100 + index + 1,
      title,
      durationMs: 2000,
      index: index + 1,
    })),
  };
}

export function trackDetail(query) {
  if (query.sourceId === DETAIL_FAIL_ID) {
    throw { fmpError: 'NetworkError', message: 'test detail failure' };
  }
  if (query.sourceId !== DETAIL_FULL_ID) return {};
  return {
    description: [
      'A long description for the test track.',
      'It has several lines so the collapsed view cuts it off.',
      'Line three.',
      'Line four.',
      'Line five.',
      'Line six, only visible after expanding.',
    ].join('\n'),
    publishedAt: Date.UTC(2024, 4, 17, 8, 30),
    album: 'Test album',
    // 允許網域是 fmp.test（不連網，只給實機驗「點封面與標題開原網頁」）。
    webUrl: 'https://fmp.test/track/tone-440',
    stats: [
      { kind: 'view', count: 46000000 },
      { kind: 'like', count: 1234567 },
      { kind: 'favorite', count: 98765 },
      { kind: 'comment', count: 4321 },
      { kind: 'share', count: 321 },
      { kind: 'danmaku', count: 12 },
      { kind: 'coin', count: 0 },
    ],
  };
}
