import fs from 'node:fs';
if(typeof fs.readFileSync!=='function')throw Error('missing host module');
// A future timer must not run between already-ready promise continuations.
await new Promise(resolve=>setTimeout(resolve,1));
let timerFired=false;
const timer=setInterval(()=>{timerFired=true;},1000);
let chain=Promise.resolve();
let count=0;
for(let i=0;i<128;i++) chain=chain.then(async()=>{await Promise.resolve();count++;});
await chain;
clearInterval(timer);
if(timerFired || count!==128)throw Error('ready microtasks were blocked by OS polling');
console.log('PASS top-level await drains ready jobs before polling');
