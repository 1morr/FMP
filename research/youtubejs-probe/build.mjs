// Bundles src/plugin.js into one FMP install file: manifest header + ES module.
import { build } from 'esbuild';
import { readFileSync, writeFileSync, mkdirSync, statSync } from 'node:fs';

const manifest = {
  id: 'youtubejs-probe',
  name: 'YouTube.js probe',
  version: '0.0.1',
  author: 'FMP probe',
  apiVersion: 1,
  capabilities: ['search', 'resolveStream'],
  allowedHosts: ['youtube.com', 'googlevideo.com', 'ytimg.com', 'googleapis.com'],
  redaction: {
    mediaCdns: [{ host: 'googlevideo.com', signedQueryParameters: ['sig', 'lsig', 'n', 'ip', 'pot'] }],
  },
};

const minify = process.env.MINIFY !== '0';
mkdirSync('dist', { recursive: true });
const result = await build({
  entryPoints: ['src/plugin.js'],
  bundle: true,
  format: 'esm',
  platform: 'neutral',
  mainFields: ['module', 'main'],
  conditions: ['import', 'default'],
  target: 'es2020',
  minify,
  legalComments: 'none',
  write: false,
  metafile: true,
  logLevel: 'warning',
});
const code = result.outputFiles[0].text;
const header = `/* ==FMP Plugin==\n${JSON.stringify(manifest, null, 2)}\n==/FMP Plugin== */\n`;
writeFileSync('dist/youtubejs_probe.js', header + code);
writeFileSync('dist/meta.json', JSON.stringify(result.metafile));
const size = statSync('dist/youtubejs_probe.js').size;
console.log(`dist/youtubejs_probe.js ${size} bytes (minify=${minify})`);
const inputs = {};
for (const [file, info] of Object.entries(result.metafile.outputs[Object.keys(result.metafile.outputs)[0]].inputs)) {
  const pkg = (/node_modules\/((?:@[^/]+\/)?[^/]+)/.exec(file) || [null, 'src'])[1];
  inputs[pkg] = (inputs[pkg] || 0) + info.bytesInOutput;
}
console.log(Object.entries(inputs).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k}: ${v}`).join('\n'));
void readFileSync;
