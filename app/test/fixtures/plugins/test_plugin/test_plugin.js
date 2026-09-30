/* ==FMP Plugin==
{
  "id": "fmp-test",
  "name": "FMP Test Plugin",
  "version": "1.0.0",
  "author": "FMP",
  "apiVersion": 1,
  "capabilities": ["search", "resolveStream"],
  "allowedHosts": []
}
==/FMP Plugin== */

// FMP 的測試插件（ADR 0015 §決定 6）：合成資料、不發任何網路請求。串流指向
// App 內附的音檔（dev flavor 的 asset），給執行環境的測試、實機驗證與量測用。

const TONES = [220, 440, 880];
const PAGE_SIZE = 2;
const TONE_ASSET = 'asset:///test/fixtures/plugins/test_plugin/tone.wav';

// 關鍵字剛好是它時，搜尋以限流失敗：實機不連網也能看到錯誤提示（ADR 0027
// 「測試插件不足以涵蓋某類 UI 時先補測試插件」）。
const FAIL_KEYWORD = 'fail';

// 標題的前綴可以用 storage 改（`titlePrefix`），順便走一次非同步的宿主函式。
export async function search(query) {
  if (query.keyword === FAIL_KEYWORD) {
    throw { fmpError: 'RateLimited', message: 'forced failure for on-device checks' };
  }
  const prefix = (await fmp.storage.get('titlePrefix')) ?? 'Test tone';
  const start = (query.page - 1) * PAGE_SIZE;
  const items = TONES.slice(start, start + PAGE_SIZE).map((hz) => ({
    sourceId: `tone-${hz}`,
    title: `${prefix} ${hz} Hz (${query.keyword})`,
    uploader: 'FMP',
    durationMs: 2000,
    artwork: [],
  }));
  return { items, hasMore: start + PAGE_SIZE < TONES.length };
}

export async function resolveStream(request) {
  if (!/^tone-\d+$/.test(request.sourceId)) {
    throw { fmpError: 'NotFound', message: `no such tone: ${request.sourceId}` };
  }
  // 內附的音檔只有 440 Hz 一個；其他音高也回它。
  return {
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
