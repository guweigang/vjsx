// Live integration test for stock-sdk fetching real quotes from Tencent/Eastmoney
// Requires internet connection

import { StockSDK } from "/Users/guweigang/node_modules/stock-sdk/dist/index.js";

async function main() {
  console.log("Initializing StockSDK...");
  const sdk = new StockSDK({ timeout: 10000 });

  console.log("Fetching live quotes for 600519 (贵州茅台)...");
  try {
    const quotes = await sdk.quotes.cn(["600519"]);
    console.log("Successfully fetched quote!");
    console.log("Quote data count: " + quotes.length);
    if (quotes.length > 0) {
      const q = quotes[0];
      console.log("Code: " + q.code);
      console.log("Market: " + q.market);
      console.log("Name: " + q.name);
      console.log("Price: " + q.price);
      console.log("Open: " + q.open);
      console.log("High: " + q.high);
      console.log("Low: " + q.low);
      console.log("Volume: " + q.volume);
      console.log("Time: " + q.time);
    } else {
      console.log("Warning: empty quote array returned");
    }
  } catch (e) {
    console.log("Error fetching quote: " + e.message);
    if (e.stack) {
      console.log(e.stack);
    }
  }
}

main().catch(console.error);
