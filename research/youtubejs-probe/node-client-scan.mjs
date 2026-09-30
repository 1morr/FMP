// For each client: playability, formats (audio-only + muxed), and whether a small
// Range GET deep into the file (past the ~60 s cap) is served. Minimal requests.
// Usage: node node-client-scan.mjs [VIDEO_ID] ; CLIENTS=VISIONOS,ANDROID_VR
import { Innertube, Log } from 'youtubei.js';
import https from 'node:https';

Log.setLevel(Log.Level.NONE);
const vid = process.argv[2] || 'dQw4w9WgXcQ';
const clients = (process.env.CLIENTS || 'VISIONOS,ANDROID_VR').split(',');
const yt = await Innertube.create({ retrieve_player: false });

function get(url, headers) {
  return new Promise((resolve) => {
    const req = https.get(url, { headers }, (res) => { res.destroy(); resolve(res.statusCode); });
    req.on('error', (e) => resolve(e.code));
  });
}

for (const client of clients) {
  try {
    const info = await yt.getBasicInfo(vid, { client });
    const sd = info.streaming_data || {};
    const ps = info.playability_status || {};
    const fmt = (f) => `${f.itag}:${(f.mime_type || '').split(';')[0]}${f.has_video ? '' : '(audio)'}${f.url ? '' : '[ciphered]'}`;
    console.log(client, ps.status, ps.reason || '', 'formats', (sd.formats || []).map(fmt).join(' '), '| adaptive', (sd.adaptive_formats || []).filter((f) => !f.has_video).map(fmt).join(' '), sd.hls_manifest_url ? '| hls' : '', sd.server_abr_streaming_url ? '| sabr' : '');
    const pick = [...(sd.adaptive_formats || []).filter((f) => f.has_audio && !f.has_video && f.url), ...(sd.formats || []).filter((f) => f.url)];
    for (const f of pick.slice(0, 3)) {
      const len = Number(f.content_length || 0);
      if (process.env.UA_MATRIX === '1') {
        for (const u of ['libmpv', 'ExoPlayerLib/2.19.1', 'Dart/3.13 (dart:io)', null]) {
          const hh = u ? { 'User-Agent': u } : {};
          console.log('   itag', f.itag, 'UA', u, 'open-ended', await get(f.url, { ...hh, Range: 'bytes=0-' }), 'no-range', await get(f.url, hh), '@80%', await get(f.url, { ...hh, Range: `bytes=${Math.floor(len * 0.8)}-` }));
        }
        break;
      }
      const ua = client === 'VISIONOS' ? 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15' : undefined;
      const h = ua ? { 'User-Agent': ua } : {};
      const deep = Math.floor(len * 0.8);
      console.log('   itag', f.itag, 'clen', len,
        'open-ended', await get(f.url, { ...h, Range: 'bytes=0-' }),
        '@80%', await get(f.url, { ...h, Range: `bytes=${deep}-${deep + 65535}` }));
    }
  } catch (e) {
    console.log(client, 'ERR', e.message);
  }
}
