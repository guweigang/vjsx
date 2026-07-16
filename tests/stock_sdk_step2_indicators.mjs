// Step 2: 验证 stock-sdk 技术指标计算模块
// 纯离线计算，不需要网络，不需要 Intl/TextDecoder

import {
  calcMA,
  calcEMA,
  calcSMA,
  calcMACD,
  calcBOLL,
  calcKDJ,
  calcRSI,
} from "/Users/guweigang/node_modules/stock-sdk/dist/indicators.js";

// 模拟 30 天收盘价数据
const closes = [
  10.5, 10.8, 11.2, 10.9, 11.5, 11.8, 12.0, 11.7, 12.3, 12.5,
  12.1, 12.8, 13.0, 12.6, 13.2, 13.5, 13.1, 13.8, 14.0, 13.6,
  14.2, 14.5, 14.1, 14.8, 15.0, 14.6, 15.2, 15.5, 15.1, 15.8,
];

// --- 1. MA (移动平均线) ---
// 返回 [{ ma5, ma10, ma20, ma30, ma60, ma120, ma250 }]
const ma = calcMA(closes, 5);
console.log("ma_len:" + ma.length);
// 前 4 个 ma5 应是 null，第 5 个开始有值
console.log("ma_first_null:" + (ma[0].ma5 === null));
console.log("ma5_at4:" + (typeof ma[4].ma5 === "number"));
console.log("ma5_val:" + ma[4].ma5);

// --- 2. EMA (指数移动平均线) ---
const ema = calcEMA(closes, 5);
console.log("ema_len:" + ema.length);
// 前 4 个是 null
const emaValid = ema.filter(v => v !== null);
console.log("ema_valid:" + emaValid.length);
console.log("ema_last:" + ema[ema.length - 1]);

// --- 3. MACD ---
// 返回 [{ dif, dea, macd }]
const macd = calcMACD(closes);
console.log("macd_len:" + macd.length);
console.log("macd_keys:" + Object.keys(macd[0]).sort().join(","));
// 最后几个应该有值
const lastMacd = macd[macd.length - 1];
console.log("macd_last_dif:" + lastMacd.dif);
console.log("macd_last_dea:" + lastMacd.dea);

// --- 4. BOLL (布林带) ---
// 返回 [{ mid, upper, lower, bandwidth }]
const boll = calcBOLL(closes);
console.log("boll_len:" + boll.length);
console.log("boll_keys:" + Object.keys(boll[0]).sort().join(","));
const lastBoll = boll[boll.length - 1];
console.log("boll_last_mid:" + lastBoll.mid);
console.log("boll_has_upper:" + (lastBoll.upper !== null));

// --- 5. RSI ---
// 返回 [{ rsi6, rsi12, rsi24 }]
const rsi = calcRSI(closes);
console.log("rsi_len:" + rsi.length);
const lastRsi = rsi[rsi.length - 1];
console.log("rsi_keys:" + Object.keys(lastRsi).sort().join(","));
console.log("rsi6_last:" + lastRsi.rsi6);

// --- 6. KDJ ---
// 返回 [{ k, d, j }]
const highs = closes.map(c => c + 0.5);
const lows = closes.map(c => c - 0.3);
const kdj = calcKDJ(highs, lows, closes);
console.log("kdj_len:" + kdj.length);
const lastKdj = kdj[kdj.length - 1];
console.log("kdj_keys:" + Object.keys(lastKdj).sort().join(","));
console.log("kdj_k:" + lastKdj.k);

console.log("PASS");
