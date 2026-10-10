/* ==FMP Plugin==
{
  "id": "fmp-test",
  "name": "FMP Test Plugin",
  "version": "1.0.0",
  "author": "FMP",
  "apiVersion": 1,
  "capabilities": ["search", "resolveStream", "login"],
  "allowedHosts": [],
  "login": { "methods": ["qr"] }
}
==/FMP Plugin== */

// FMP 的測試插件（ADR 0015 §決定 6）：合成資料、不發任何網路請求。串流指向
// App 內附的音檔（dev flavor 的 asset），給執行環境的測試、實機驗證與量測用。

const TONES = [220, 440, 880];
const PAGE_SIZE = 2;
const TONE_ASSET = 'asset:///test/fixtures/plugins/test_plugin/tone.wav';
const MISSING_ASSET = 'asset:///test/fixtures/plugins/test_plugin/missing.wav';

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

// 假的 QR 登入（ADR 0029），不連網：每次產生的 QR 碼內容固定，第二次輪詢就完成，
// 交出一個一看就是假的憑證；`loginVerify` 只認它。
const FAKE_QR_TEXT = 'fmp-test://login';
const FAKE_SESSION_COOKIE = 'fmp_test_session';
const FAKE_SESSION = 'fake-session-0000';

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
    default:
      return `tone-${hz}`;
  }
}

// 標題的前綴可以用 storage 改（`titlePrefix`），順便走一次非同步的宿主函式。
export async function search(query) {
  if (query.keyword === FAIL_KEYWORD) {
    throw { fmpError: 'RateLimited', message: 'forced failure for on-device checks' };
  }
  const prefix = (await fmp.storage.get('titlePrefix')) ?? 'Test tone';
  const start = (query.page - 1) * PAGE_SIZE;
  const items = TONES.slice(start, start + PAGE_SIZE).map((hz, index) => ({
    sourceId: sourceIdFor(query.keyword, start + index, hz),
    title: `${prefix} ${hz} Hz (${query.keyword})`,
    uploader: 'FMP',
    durationMs: 2000,
    artwork: [],
  }));
  return { items, hasMore: start + PAGE_SIZE < TONES.length };
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
  } else if (!/^(tone|preview)-\d+$/.test(request.sourceId)) {
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

export function loginVerify(credentials) {
  if (credentials.cookies[FAKE_SESSION_COOKIE] !== FAKE_SESSION) {
    throw { fmpError: 'CredentialInvalid', message: 'not the fake session of the test plugin' };
  }
  return { userId: 'fmp-test-user', displayName: 'FMP Test User' };
}
