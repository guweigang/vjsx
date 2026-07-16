// Step 1: 验证 stock-sdk 的 Intl 和 TextDecoder 相关功能
// 纯离线测试，不需要网络

// --- 1. TextDecoder GBK 解码 ---
// 直接使用 decodeGBK 等价逻辑
const gbkBytes = new Uint8Array([0xb9, 0xf3, 0xd6, 0xdd, 0xc3, 0xa9, 0xcc, 0xa8]); // "贵州茅台" GBK
const decoded = new TextDecoder("gbk").decode(gbkBytes);
console.log("gbk_decode:" + decoded);

// --- 2. TextEncoder 往返测试 ---
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8");
const roundTrip = decoder.decode(encoder.encode("Hello, 世界! 🚀"));
console.log("roundtrip:" + roundTrip);

// --- 3. Intl.DateTimeFormat 基本格式化 ---
// stock-sdk 使用类似调用方式
const fmt1 = new Intl.DateTimeFormat("en-US", {
  hour12: false,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  timeZone: "UTC",
});
const ts1 = Date.UTC(2024, 6, 15, 14, 30, 45);
console.log("fmt1:" + fmt1.format(new Date(ts1)));

// --- 4. Intl.DateTimeFormat.formatToParts ---
// stock-sdk 的 De() 函数使用 formatToParts 提取字段
const parts = fmt1.formatToParts(new Date(ts1));
const partsMap = {};
for (const part of parts) {
  if (part.type !== "literal") partsMap[part.type] = part.value;
}
console.log("parts_year:" + partsMap.year);
console.log("parts_month:" + partsMap.month);
console.log("parts_day:" + partsMap.day);
console.log("parts_hour:" + partsMap.hour);
console.log("parts_minute:" + partsMap.minute);
console.log("parts_second:" + partsMap.second);

// --- 5. Intl.DateTimeFormat with weekday (stock-sdk os() 函数) ---
const fmt2 = new Intl.DateTimeFormat("en-US", {
  timeZone: "UTC",
  hour12: false,
  weekday: "short",
  hour: "2-digit",
  minute: "2-digit",
});
const parts2 = fmt2.formatToParts(new Date(ts1));
const partsMap2 = {};
for (const part of parts2) {
  if (part.type !== "literal") partsMap2[part.type] = part.value;
}
console.log("weekday:" + partsMap2.weekday);
console.log("hour:" + partsMap2.hour);
console.log("minute:" + partsMap2.minute);

// --- 6. zh-CN locale 日期格式化 ---
const fmt3 = new Intl.DateTimeFormat("zh-CN", {
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  timeZone: "UTC",
});
console.log("zh_date:" + fmt3.format(new Date(ts1)));

// --- 7. GBK 流式解码 ---
const streamDecoder = new TextDecoder("gbk");
const part1 = streamDecoder.decode(new Uint8Array([0xb9, 0xf3]), { stream: true });
const part2 = streamDecoder.decode(new Uint8Array([0xd6, 0xdd]));
console.log("stream_gbk:" + part1 + part2);

console.log("PASS");
