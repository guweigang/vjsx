console.log(typeof window);
console.log(typeof self);
console.log(typeof EventTarget);
console.log(typeof URL);
console.log(typeof setTimeout);
console.log(typeof Intl);
console.log(typeof Intl.DateTimeFormat);
console.log(new TextDecoder("gbk").decode(new Uint8Array([0x56, 0xb4, 0xf3, 0xb7, 0xa8, 0xba, 0xc3])));
const gbkDecoder = new TextDecoder("gbk");
console.log(gbkDecoder.decode(new Uint8Array([0xb4]), { stream: true }) + gbkDecoder.decode(new Uint8Array([0xf3])));
console.log(new Intl.DateTimeFormat("en-US", {
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  hour12: false,
  timeZone: "UTC",
}).format(new Date(Date.UTC(2024, 6, 15, 14, 30, 45))));
console.log(new Intl.DateTimeFormat("zh-CN", {
  weekday: "long",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  timeZone: "UTC",
}).formatToParts(new Date(Date.UTC(2024, 6, 15))).map((part) => `${part.type}:${part.value}`).join("|"));
console.log(typeof process);
console.log(typeof Buffer);
