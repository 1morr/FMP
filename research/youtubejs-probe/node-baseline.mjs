// Node baseline: which Innertube client gives playable audio today, logged out,
// without PO token. Minimal requests. Usage: node node-baseline.mjs [CLIENT ...]
import { Innertube, Platform, Log } from 'youtubei.js';

Log.setLevel(Log.Level.WARNING);
Platform.shim.eval = async (data, env) => {
  const props = [];
  if (env.n) props.push(`n: exportedVars.nFunction(${JSON.stringify(env.n)})`);
  if (env.sig) props.push(`sig: exportedVars.sigFunction(${JSON.stringify(env.sig)})`);
  return new Function(`${data.output}\nreturn { ${props.join(', ')} }`)();
};

const clients = process.argv.slice(2);
const retrievePlayer = process.env.PLAYER === '1';
let t = Date.now();
const yt = await Innertube.create({ retrieve_player: retrievePlayer, generate_session_locally: process.env.LOCAL === '1' });
console.log('create ms', Date.now() - t);
t = Date.now();
const search = await yt.search('lofi hip hop', { type: 'video' });
const videos = search.videos.filter((v) => v.type === 'Video');
console.log('search ms', Date.now() - t, 'videos', videos.length, videos.slice(0, 3).map((v) => [v.video_id, v.title?.toString(), v.duration?.seconds]));
const id = process.env.VID || videos.find((v) => (v.duration?.seconds ?? 0) > 60)?.video_id;
for (const client of clients) {
  try {
    t = Date.now();
    const info = await yt.getBasicInfo(id, { client });
    const ps = info.playability_status;
    const audio = (info.streaming_data?.adaptive_formats ?? []).filter((f) => f.has_audio && !f.has_video);
    console.log(client, 'info ms', Date.now() - t, 'status', ps?.status, ps?.reason, 'audio', audio.map((f) => [f.itag, f.mime_type, f.bitrate, !!f.url, !!f.signature_cipher]));
    const f = audio.find((x) => x.mime_type.startsWith('audio/mp4')) ?? audio[0];
    if (!f) continue;
    const url = await f.decipher(yt.session.player);
    const res = await fetch(url, { headers: { Range: 'bytes=0-65535' } });
    console.log(client, 'range GET', res.status, res.headers.get('content-type'), (await res.arrayBuffer()).byteLength, 'host', new URL(url).host, 'n?', new URL(url).searchParams.has('n'));
  } catch (e) {
    console.log(client, 'ERR', e?.message);
  }
}
