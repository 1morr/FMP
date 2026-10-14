/* ==FMP Plugin==
{
  "id": "fmp-test",
  "name": "FMP Test Plugin",
  "version": "1.0.0",
  "author": "FMP",
  "apiVersion": 1,
  "capabilities": ["search", "resolveStream", "live", "mix", "multiPart", "login"],
  "allowedHosts": [],
  "login": { "methods": ["qr", "cookie"], "refresh": "onStartup" }
}
==/FMP Plugin== */

// FMP 的測試插件（ADR 0015 §決定 6）：合成資料、不發任何網路請求。串流指向
// App 內附的音檔（dev flavor 的 asset），給執行環境的測試、實機驗證與量測用。

const TONES = [220, 440, 880];
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
  { roomId: 'live-ok', title: 'Test live room', hostName: 'FMP', status: 'live', online: 42 },
  { roomId: 'live-offline', title: 'Test offline room', hostName: 'FMP', status: 'offline' },
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
  } else if (!/^(tone|preview|parts)-\d+$/.test(request.sourceId) && !/^mix-.+-\d+$/.test(request.sourceId)) {
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
