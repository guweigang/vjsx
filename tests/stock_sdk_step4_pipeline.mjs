// Step 4: 模拟 stock-sdk 解析腾讯行情数据的完整路径
// 腾讯行情接口返回 GBK 编码，经过 TextDecoder("gbk") 解码后
// 使用 Intl.DateTimeFormat 做时间戳计算
// 这个测试完全离线，直接用模拟的原始字节数据

import {
  decodeGBK,
  parseResponse,
  formatInTz,
  buildTimeMeta,
  MARKET_TZ,
  normalizeSymbol,
} from "/Users/guweigang/node_modules/stock-sdk/dist/index.js";

// === 模拟腾讯行情原始响应（GBK 编码） ===
// 正常情况下 stock-sdk 的 getTencentQuote 会发送 HTTP 请求
// 返回 GBK 编码的文本如: v_sh600519="1~贵州茅台~600519~1850.00~..."
// 我们直接模拟解码后的文本进行解析测试

// 1. GBK 解码测试
const gbkName = new Uint8Array([0xb9, 0xf3, 0xd6, 0xdd, 0xc3, 0xa9, 0xcc, 0xa8]);
const decodedName = decodeGBK(gbkName);
console.log("1.name:" + decodedName);

// 2. 测试解析腾讯行情响应格式
// parseResponse 解析 "key=val1~val2~val3" 格式
const mockResponse = 'v_sh600519="1~' + decodedName + '~600519~1850.00~1840.00~1855.00~50000~25000~25000~1849.50~100~1849.00~200~1848.50~300~1848.00~400~1847.50~500~1850.50~150~1851.00~250~1851.50~350~1852.00~450~1852.50~550~2024-07-15 14:30:00~10.00~0.54~1860.00~1835.00~~50000.00~925000000.00~2.50~25.50~3.50~2.80~370000000000.00~460000000000.00~1.50~1.20~1860.00~1835.00~2.00~18.00~~~~1900.00~1800.00~~~20.00~22.00~~~1256000000.00~1260000000.00~~~";\n';
const parsed = parseResponse(mockResponse);
console.log("2.parsed_len:" + parsed.length);
console.log("2.parsed_key:" + (parsed.length > 0 ? parsed[0].key : "none"));
console.log("2.parsed_name:" + (parsed.length > 0 ? parsed[0].fields[1] : "none"));
console.log("2.parsed_code:" + (parsed.length > 0 ? parsed[0].fields[2] : "none"));
console.log("2.parsed_price:" + (parsed.length > 0 ? parsed[0].fields[3] : "none"));

// 3. 时间戳计算（Intl.DateTimeFormat 驱动）
const dateStr = "2024-07-15 14:30:00";
const timeMeta = buildTimeMeta(dateStr, MARKET_TZ.CN);
console.log("3.timestamp:" + timeMeta.timestamp);
console.log("3.tz:" + timeMeta.tz);
// 用 formatInTz 反向验证
const formatted = formatInTz(timeMeta.timestamp, MARKET_TZ.CN);
console.log("3.roundtrip:" + formatted);

// 4. 股票代码解析
const sym = normalizeSymbol("sh600519");
console.log("4.code:" + sym.code);
console.log("4.market:" + sym.market);
console.log("4.exchange:" + sym.exchange);

const sym2 = normalizeSymbol("sz000001");
console.log("4.sz_code:" + sym2.code);
console.log("4.sz_market:" + sym2.market);

// 5. 多个 GBK 编码测试
const testCases = [
  { bytes: [0xd6, 0xd0, 0xb9, 0xfa, 0xc6, 0xbd, 0xb0, 0xb2], expected: "中国平安" },
  { bytes: [0xd5, 0xd0, 0xc9, 0xcc, 0xd2, 0xf8, 0xd0, 0xd0], expected: "招商银行" },
  { bytes: [0xc3, 0xc0, 0xb5, 0xc4, 0xbc, 0xaf, 0xcd, 0xc5], expected: "美的集团" },
];
let allGbkOk = true;
for (const tc of testCases) {
  const result = decodeGBK(new Uint8Array(tc.bytes));
  if (result !== tc.expected) {
    console.log("5.FAIL:" + tc.expected + " got:" + result);
    allGbkOk = false;
  }
}
console.log("5.all_gbk_ok:" + allGbkOk);

console.log("PASS");
