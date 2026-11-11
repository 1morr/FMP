// 把每個插件（含 manifest.json 的子目錄）的 src/index.ts 打包成
// dist/plugin.js（ADR 0038）。產物提交進 repo；`tool/check.dart` 完整版以
// `npm run build -- --outdir <暫存目錄>`（先 tsc 型別檢查再跑這支）重建一次，
// 和提交的產物逐位元組比對。
//
//   node build.mjs                  寫進各插件的 dist/
//   node build.mjs --outdir <dir>   寫進 <dir>/<插件>/dist/
import { build } from 'esbuild';
import { existsSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const flag = process.argv.indexOf('--outdir');
const outRoot = flag >= 0 ? process.argv[flag + 1] : root;
if (!outRoot) throw new Error('--outdir needs a directory');

const plugins = readdirSync(root, { withFileTypes: true })
  .filter((e) => e.isDirectory() && existsSync(join(root, e.name, 'manifest.json')))
  .map((e) => e.name)
  .sort();

for (const plugin of plugins) {
  await build({
    entryPoints: [join(root, plugin, 'src', 'index.ts')],
    outfile: join(outRoot, plugin, 'dist', 'plugin.js'),
    // 產物裡的路徑註解相對於這裡，不隨執行時的目錄變。
    absWorkingDir: root,
    bundle: true,
    // fjs 以 ES module 載入插件，宿主呼叫它匯出的插件能力函式。
    format: 'esm',
    platform: 'neutral',
    target: 'es2023',
    // 不壓縮：產物進 repo，diff 讀得懂，也方便在引擎裡看錯誤的行號。
    minify: false,
    legalComments: 'inline',
    charset: 'utf8',
    logLevel: 'warning',
  });
  console.log(`built ${plugin}`);
}
