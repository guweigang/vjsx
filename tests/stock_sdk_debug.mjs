// 验证 stock-sdk 时区计算的核心路径对 A 股、港股、美股的影响
import {
  formatInTz,
  MARKET_TZ,
  TradingCalendarService,
  StockSDK,
} from "/Users/guweigang/node_modules/stock-sdk/dist/index.js";

// === A 股 (Asia/Shanghai) ===
// 在 Asia/Shanghai 系统上，formatInTz + Asia/Shanghai = 正确
const ts_cn = Date.UTC(2024, 6, 15, 6, 30, 0); // 14:30 上海时间
console.log("CN:" + formatInTz(ts_cn, MARKET_TZ.CN));
// 期望: 07/15/2024, 14:30

// === 港股 (Asia/Hong_Kong) ===
// Hong_Kong 和 Shanghai 同为 UTC+8，结果碰巧正确
console.log("HK:" + formatInTz(ts_cn, MARKET_TZ.HK));
// 期望: 07/15/2024, 14:30（与 CN 相同因为同时区）

// === 美股 (America/New_York) ===
// 这里应该是 EDT (UTC-4)，所以应该是 02:30
const ts_us = Date.UTC(2024, 6, 15, 18, 30, 0); // 14:30 纽约时间(EDT)
console.log("US:" + formatInTz(ts_us, MARKET_TZ.US));
// 期望: 07/15/2024, 14:30
// 实际: 07/16/2024, 02:30 (因为用的是 Asia/Shanghai)

// 测试 SDK 是否能正常实例化且获取交易日历服务
const sdk = new StockSDK();
console.log("has_calendar:" + (typeof sdk.calendar));
console.log("has_quotes_cn:" + (typeof sdk.quotes.cn));
console.log("has_quotes_hk:" + (typeof sdk.quotes.hk));
console.log("has_quotes_us:" + (typeof sdk.quotes.us));
console.log("has_kline:" + (typeof sdk.kline));
console.log("has_options:" + (typeof sdk.options));

// 市场状态判断
const cal = new TradingCalendarService(sdk.quotes);
const marketStatus = cal.getMarketStatus("A");
console.log("cn_market_status:" + marketStatus);

console.log("DONE");
