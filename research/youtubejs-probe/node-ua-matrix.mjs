// Which request shapes does googlevideo accept for an ANDROID_VR audio URL?
// One player request, then a few small GETs (first 1 KiB only). Prints status only.
import { Innertube, Log } from 'youtubei.js';
import https from 'node:https';

Log.setLevel(Log.Level.NONE);
const yt = await Innertube.create({ retrieve_player: false });
const info = await yt.getBasicInfo(process.env.VID || 'dQw4w9WgXcQ', { client: 'ANDROID_VR' });
const f = info.streaming_data.adaptive_formats.find((x) => x.itag === 140);
const url = await f.decipher(undefined);

function get(headers) {
  return new Promise((resolve) => {
    const q = headers.__q || ''; delete headers.__q;
    const req = https.get(url + q, { headers }, (res) => { res.destroy(); resolve(res.statusCode); });
    req.on('error', (e) => resolve(e.code));
  });
}
const vrUa = 'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip';
const len = Number(f.content_length);
console.log('clen', len, 'dur', f.approx_duration_ms);
const offsets = [1200000, 1400000, 1600000, 1800000, 2000000];
async function scan(label) {
  const r = [];
  for (const o of offsets) r.push(`${o}:${await get({ Range: `bytes=${o}-${o + 65535}` })}`);
  console.log(label, new Date().toISOString(), r.join(' '));
}
await scan('t0');
await new Promise((r) => setTimeout(r, Number(process.env.WAIT || 60000)));
await scan('t+wait');
