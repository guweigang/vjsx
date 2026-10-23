const path = require('node:path');
const esbuild = require(process.env.ESBUILD_PATH || 'esbuild');
const root = process.env.SATORI_MODULES || path.join(__dirname, 'node_modules');
esbuild.buildSync({
 entryPoints: [path.join(__dirname, process.env.SATORI_PROBE || 'probe.mjs')], bundle: true, platform: 'browser', format: 'esm',
 nodePaths: [root], external: ['crypto'],
 banner: { js: `import * as __vjsxCrypto from 'crypto'; const require = id => { if (id === 'crypto') return __vjsxCrypto; throw Error('Unsupported require: '+id); };` }, outfile: path.join(__dirname, (process.env.SATORI_PROBE || 'probe.mjs').replace('.mjs', '.bundle.mjs')),
 // One ESM identity for Cordis/Satori services and the real reggol browser
 // constructor avoids duplicate service symbols and CJS default wrapping.
 alias: Object.fromEntries([['reggol', path.join(root, 'reggol/lib/browser.mjs')], ...['cordis', '@cordisjs/core', '@cordisjs/logger', '@cordisjs/schema', '@cordisjs/timer', '@satorijs/core'].map(name => [name, path.join(root, name, 'lib/index.mjs')])]),
});
