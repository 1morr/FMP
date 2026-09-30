/* ==FMP Plugin==
{
  "id": "fmp-test-http",
  "name": "FMP HTTP Test Plugin",
  "version": "1.0.0",
  "author": "FMP",
  "apiVersion": 1,
  "capabilities": ["search", "resolveStream"],
  "allowedHosts": ["api.fmp.test", "media.fmp.test"],
  "redaction": { "keyNames": ["demo_session"] }
}
==/FMP Plugin== */

// 契約執行器的第二個測試插件：會發 HTTP 請求，網域是 RFC 2606 保留的 .test，
// 回應由 fixtures/ 重播，不會真的連網。讓重播比對、網域與遮蔽的檢查真的被
// 執行到。

const API = 'https://api.fmp.test';
const REFERER = 'https://www.fmp.test/';
// 假的憑證：請求帶著它；fixture、log 與網路紀錄裡只能看到 ***。
const ACCESS_KEY = 'FAKE_ACCESS_KEY_0001';

export async function search({ keyword, page }) {
  // query 的順序刻意與 fixture 不同：重播比對不看順序。
  const url =
    `${API}/search?page=${page}&keyword=${encodeURIComponent(keyword)}` +
    `&access_key=${ACCESS_KEY}`;
  fmp.log.debug(`search ${url}`);
  const response = await fmp.http.request({ url, headers: { Referer: REFERER } });
  if (response.status === 429) throw { fmpError: 'RateLimited' };
  if (response.status !== 200) {
    throw { fmpError: 'ParseError', message: `HTTP ${response.status}` };
  }
  const json = JSON.parse(response.body);
  fmp.log.info('search results', {
    count: json.list.length,
    demo_session: json.demo_session,
  });
  return {
    items: json.list.map((item) => ({
      sourceId: item.id,
      title: item.name,
      uploader: item.owner,
      durationMs: item.ms,
    })),
    hasMore: json.more,
  };
}

export async function resolveStream({ sourceId }) {
  const response = await fmp.http.request({
    url: `${API}/stream?id=${encodeURIComponent(sourceId)}`,
  });
  if (response.status === 404) throw { fmpError: 'NotFound' };
  if (response.status !== 200) {
    throw { fmpError: 'ParseError', message: `HTTP ${response.status}` };
  }
  const json = JSON.parse(response.body);
  if (json.code === 403) throw { fmpError: 'Unavailable', reason: 'copyright' };
  if (json.code !== 0) throw { fmpError: 'NotFound', message: `code ${json.code}` };
  return {
    candidates: [
      {
        url: json.url,
        headers: { Referer: REFERER },
        container: 'mp4',
        codec: 'aac',
      },
    ],
  };
}
