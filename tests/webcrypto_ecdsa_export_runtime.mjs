import { writeFile } from "node:fs/promises";
import { subtle } from "node:crypto";

const [privatePath, publicPath, privateJwkPath, publicJwkPath] = process.argv.slice(-4);
const pair = await subtle.generateKey(
  { name: "ECDSA", namedCurve: "P-256" },
  true,
  ["sign", "verify"],
);
const pkcs8 = await subtle.exportKey("pkcs8", pair.privateKey);
const spki = await subtle.exportKey("spki", pair.publicKey);
const privateJwk = await subtle.exportKey("jwk", pair.privateKey);
const publicJwk = await subtle.exportKey("jwk", pair.publicKey);
await writeFile(privatePath, new Uint8Array(pkcs8));
await writeFile(publicPath, new Uint8Array(spki));
await writeFile(privateJwkPath, JSON.stringify(privateJwk));
await writeFile(publicJwkPath, JSON.stringify(publicJwk));
console.log(`${pkcs8.byteLength > 0}:${spki.byteLength > 0}:${typeof privateJwk.d}:${"d" in publicJwk}`);
