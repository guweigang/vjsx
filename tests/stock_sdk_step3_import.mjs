// Step 3: 验证 stock-sdk 核心模块 import 和 Intl/TextDecoder 集成
// 测试 import stock-sdk 主入口，验证 decodeGBK + normalizeSymbol + Intl 时区函数

import {
  StockSDK,
  normalizeSymbol,
  decodeGBK,
  formatInTz,
  parseMarketTime,
  MARKET_TZ,
  SdkError,
  MemoryCache,
  safeNumber,
  safeNumberOrNull,
} from "/Users/guweigang/node_modules/stock-sdk/dist/index.js";

// --- 1. normalizeSymbol ---
const sym1 = normalizeSymbol("600519");
console.log("sym_code:" + sym1.code);
console.log("sym_market:" + sym1.market);
console.log("sym_exchange:" + sym1.exchange);

const sym2 = normalizeSymbol("AAPL");
console.log("us_code:" + sym2.code);
console.log("us_market:" + sym2.market);

const sym3 = normalizeSymbol("00700");
console.log("hk_code:" + sym3.code);

// --- 2. decodeGBK (依赖 TextDecoder) ---
const gbkBytes = new Uint8Array([0xb9, 0xf3, 0xd6, 0xdd, 0xc3, 0xa9, 0xcc, 0xa8]);
const gbkResult = decodeGBK(gbkBytes);
console.log("decode_gbk:" + gbkResult);

// 新浪行情常见 GBK 序列
const sinaGbk = new Uint8Array([
  0xc6, 0xbd, 0xb0, 0xb2, 0xd2, 0xf8, 0xd0, 0xd0  // "平安银行" GBK
]);
console.log("decode_sina:" + decodeGBK(sinaGbk));

// --- 3. MARKET_TZ ---
console.log("tz_cn:" + MARKET_TZ.CN);
console.log("tz_hk:" + MARKET_TZ.HK);
console.log("tz_us:" + MARKET_TZ.US);

// --- 4. formatInTz (依赖 Intl.DateTimeFormat) ---
// 2024-07-15 14:30:00 UTC = 2024-07-15 22:30:00 Asia/Shanghai
const ts = Date.UTC(2024, 6, 15, 14, 30, 0);
const formatted = formatInTz(ts, MARKET_TZ.CN);
console.log("format_tz:" + formatted);

// --- 5. parseMarketTime (依赖 Intl.DateTimeFormat) ---
const mt = parseMarketTime("2024-07-15 14:30:00", MARKET_TZ.CN);
console.log("parse_mt_type:" + typeof mt);
console.log("parse_mt_is_num:" + (typeof mt === "number"));

// --- 6. safeNumber / safeNumberOrNull ---
console.log("safe_num:" + safeNumber("123.45"));
console.log("safe_null:" + safeNumberOrNull("--"));
console.log("safe_null2:" + safeNumberOrNull(""));

// --- 7. MemoryCache ---
const cache = new MemoryCache({ maxSize: 10 });
console.log("cache_type:" + typeof cache);

// --- 8. SdkError ---
try {
  throw new SdkError({ code: "TEST", message: "test error" });
} catch (e) {
  console.log("error_code:" + e.code);
  console.log("error_msg:" + e.message);
}

// --- 9. StockSDK 实例化 ---
const sdk = new StockSDK({ timeout: 5000 });
console.log("sdk_type:" + typeof sdk);
console.log("sdk_quotes:" + typeof sdk.quotes);

console.log("PASS");
