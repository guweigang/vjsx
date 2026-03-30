const text = new TextEncoder().encode("hello");
const iv = new Uint8Array([15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]);
const key = await crypto.subtle.importKey(
  "raw",
  new Uint8Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]),
  "AES-CBC",
  true,
  ["encrypt", "decrypt"],
);

const encrypted = await crypto.subtle.encrypt({ name: "AES-CBC", iv }, key, text);
const decrypted = await crypto.subtle.decrypt({ name: "AES-CBC", iv }, key, encrypted);

console.log(encrypted.byteLength);
console.log(new TextDecoder().decode(decrypted));
