import { Context } from '@satorijs/core';
import { LarkBrowserBot, LarkBrowserHTTP } from './compat.mjs';
const ctx = new Context();
ctx.plugin(LarkBrowserHTTP);
ctx.plugin(LarkBrowserBot, { appId: 'fixture-app', appSecret: 'fixture-secret', protocol: 'ws',
 endpoint: 'http://127.0.0.1:18881/open-apis', baseURL: 'http://127.0.0.1:18881',
 retryTimes: 0, retryInterval: 100 });
const bot = ctx.bots[0];
console.log('SATORI_CONSTRUCT', bot.platform, typeof ctx.http.ws);
ctx.on('interaction/command', session => console.log('SATORI_EVENT', session.content));
await ctx.start();
setTimeout(async () => { await ctx.stop(); console.log('SATORI_STOP'); }, 2000);
