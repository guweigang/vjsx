const password = new TextEncoder().encode("password");
const salt = new TextEncoder().encode("salt");
const baseKey = await crypto.subtle.importKey(
  "raw",
  password,
  "PBKDF2",
  false,
  ["deriveBits", "deriveKey"],
);

const bits = await crypto.subtle.deriveBits(
  {
    name: "PBKDF2",
    salt,
    iterations: 2,
    hash: "SHA-256",
  },
  baseKey,
  128,
);

const aesKey = await crypto.subtle.deriveKey(
  {
    name: "PBKDF2",
    salt,
    iterations: 1000,
    hash: "SHA-256",
  },
  baseKey,
  { name: "AES-CBC", length: 128 },
  true,
  ["encrypt", "decrypt"],
);

const hex = Array.from(new Uint8Array(bits))
  .map((byte) => byte.toString(16).padStart(2, "0"))
  .join("");

console.log(hex);
console.log(`${aesKey.algorithm.name}:${aesKey.algorithm.length}`);
