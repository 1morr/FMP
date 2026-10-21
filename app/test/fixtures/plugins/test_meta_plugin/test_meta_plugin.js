/* ==FMP Plugin==
{
  "id": "fmp-test-meta",
  "name": "FMP Test Metadata Plugin",
  "version": "1.0.0",
  "author": "FMP",
  "apiVersion": 1,
  "capabilities": ["importPlaylist"],
  "allowedHosts": []
}
==/FMP Plugin== */

// FMP 的測試插件（僅元資料來源，M4 design §4.9）：只有 `playlistFromUrl` 與 `importPlaylist`，
// 沒有 `search`、`resolveStream`，不發任何網路請求。外部匯入（匯入預覽頁）的實機重播用：
// 歌曲的標題、歌手、時長照 `fmp-test` 的搜尋結果寫，所以裝了 `fmp-test` 時匹配得到。
//
// `playlistFromUrl` 認 `https://fmp.test/meta/<id>`（任何 id；不存在的在 `importPlaylist` 才
// NotFound）。歌單（每頁 2 首）：
// - meta-basic：6 首、3 頁。4 首照 `fmp-test` 的曲目（Test tone 220／440／880 Hz、歌手 FMP、
//   2 秒；220 出現兩次），2 首匹配不到（時長 999 秒與 300 秒，超出評分的時長門檻）。
// - meta-truncated：3 首、2 頁，最後一頁 `truncated: true`（來源只提供了部分曲目）。
// - meta-broken：第 1 頁 2 首，第 2 頁 NetworkError（讀取失敗，不進匹配）。

const PLAYLIST_URL = /^https:\/\/fmp\.test\/meta\/([a-z0-9-]+)$/;
const PAGE_SIZE = 2;

function song(sourceId, title, uploader, durationMs) {
  return { track: { sourceId, title, uploader, durationMs, artwork: [] } };
}

const TONE = (hz, n) => song(`meta-tone-${hz}-${n}`, `Test tone ${hz} Hz`, 'FMP', 2000);

const PLAYLISTS = {
  'meta-basic': {
    title: 'Metadata playlist',
    items: [
      TONE(220, 1),
      song('meta-long', 'A song nobody uploaded', 'Nobody', 999000),
      TONE(440, 1),
      TONE(880, 1),
      song('meta-other', 'Another missing song', 'Nobody / Someone', 300000),
      // 同一首在歌單裡出現兩次（外部 id 相同）。
      TONE(220, 1),
    ],
  },
  'meta-truncated': {
    title: 'Truncated playlist',
    items: [TONE(220, 2), TONE(440, 2), TONE(880, 2)],
    truncated: true,
  },
  'meta-broken': {
    title: 'Broken playlist',
    items: [TONE(220, 3), TONE(440, 3), TONE(880, 3)],
    brokenFrom: PAGE_SIZE,
  },
};

export function playlistFromUrl(query) {
  const match = PLAYLIST_URL.exec(query.url);
  return match === null ? null : { playlistId: match[1] };
}

export async function importPlaylist(query) {
  const playlist = PLAYLISTS[query.playlistId];
  if (playlist === undefined) {
    throw { fmpError: 'NotFound', message: `no such playlist: ${query.playlistId}` };
  }
  const start = query.cursor === undefined || query.cursor === null ? 0 : Number(query.cursor);
  if (playlist.brokenFrom !== undefined && start >= playlist.brokenFrom) {
    throw { fmpError: 'NetworkError', message: 'forced failure for on-device checks' };
  }
  const end = start + PAGE_SIZE;
  const last = end >= playlist.items.length;
  return {
    playlist: { title: playlist.title, ownerName: 'FMP' },
    items: playlist.items.slice(start, end),
    cursor: last ? null : String(end),
    ...(last && playlist.truncated ? { truncated: true } : {}),
  };
}
