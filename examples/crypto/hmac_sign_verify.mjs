const text = new TextEncoder().encode("hello");
const key = await crypto.subtle.importKey(
  "raw",
  new Uint8Array([1, 2, 3, 4]),
  { name: "HMAC", hash: "SHA-256" },
  false,
  ["sign", "verify"],
);

const signature = await crypto.subtle.sign("HMAC", key, text);
const verified = await crypto.subtle.verify("HMAC", key, signature, text);

console.log(signature.byteLength);
console.log(verified);
