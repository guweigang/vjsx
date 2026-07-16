// Debug live fetch and response decoding
import { StockSDK } from "/Users/guweigang/node_modules/stock-sdk/dist/index.js";

const originalFetch = globalThis.fetch;

// Intercept fetch to inspect request and response
globalThis.fetch = async function(url, opts) {
  console.log("FETCH URL:", url);
  console.log("FETCH OPTS:", JSON.stringify(opts));
  const res = await originalFetch(url, opts);
  console.log("FETCH RES STATUS:", res.status);
  console.log("FETCH RES HEADERS:", JSON.stringify([...res.headers.entries()]));

  // Clone response so we can read body
  const clone = res.clone();
  const buffer = await clone.arrayBuffer();
  console.log("FETCH RES BODY BYTES LEN:", buffer.byteLength);
  const bytes = new Uint8Array(buffer);
  console.log("FETCH RES BODY FIRST 64 BYTES:", [...bytes.slice(0, 64)].map(x => x.toString(16).padStart(2, "0")).join(" "));

  // Try decoding as GBK manually
  try {
    const decoded = new TextDecoder("gbk").decode(bytes);
    console.log("MANUAL GBK DECODE FIRST 200 CHARS:", decoded.slice(0, 200));
  } catch (e) {
    console.log("MANUAL GBK DECODE ERROR:", e.message);
  }

  return res;
};

async function main() {
  const sdk = new StockSDK({ timeout: 10000 });
  const quotes = await sdk.quotes.cn(["600519"]);
  console.log("QUOTE OBJECT KEYS:", Object.keys(quotes[0]).join(", "));
  console.log("QUOTE OBJECT:", JSON.stringify(quotes[0], null, 2));
}

main().catch(console.error);
