import { Context } from '@satorijs/core';
import { LarkBrowserBot, LarkBrowserHTTP } from './compat.mjs';
const ctx = new Context();
ctx.plugin(LarkBrowserHTTP);
ctx.plugin(LarkBrowserBot, { appId: 'fixture-app', appSecret: 'fixture-secret', protocol: 'ws',
  endpoint: 'http://127.0.0.1:18882/open-apis', baseURL: 'http://127.0.0.1:18882', retryTimes: 0 });
const bot = ctx.bots[0];
let completed = 0;
const users = new Set();
const watchdog = setTimeout(() => { throw new Error('EMPLOYEE_TIMEOUT'); }, 6000);
ctx.on('message', async session => {
  if (!session.isDirect || !session.userId || !session.messageId) throw new Error('Missing employee identity');
  if (users.has(session.userId)) throw new Error('Duplicate employee event');
  users.add(session.userId);
  console.log('EMPLOYEE_IN', JSON.stringify({ user: session.userId, chat: session.channelId, message: session.messageId, text: session.content }));
  const reply = await bot.sendMessage(session.channelId, `ACK:${session.content}`);
  if (typeof reply[0] !== 'string' || !reply[0]) throw new Error('Missing reply receipt');
  console.log('EMPLOYEE_REPLY', session.userId, reply[0]);
  completed++;
  if (completed === 2) {
    const sent = await bot.sendMessage('ou_employee_1', 'TASK:follow-up-customer');
    if (typeof sent[0] !== 'string' || !sent[0]) throw new Error('Missing proactive receipt');
    console.log('EMPLOYEE_PROACTIVE', sent[0]);
    await new Promise(resolve => setTimeout(resolve, 100));
    clearTimeout(watchdog);
    await ctx.stop();
    console.log('EMPLOYEE_STOP', users.size);
  }
});
await ctx.start();
