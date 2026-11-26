import { readFile } from "node:fs/promises";
import { subtle } from "node:crypto";

const [privatePath, publicPath, privateJwkPath, publicJwkPath] = process.argv.slice(-4);
const algorithm = { name: "ECDSA", namedCurve: "P-256" };
const privateKey = await subtle.importKey(
  "pkcs8",
  await readFile(privatePath),
  algorithm,
  false,
  ["sign"],
);
const publicKey = await subtle.importKey(
  "spki",
  await readFile(publicPath),
  algorithm,
  true,
  ["verify"],
);
const data = new TextEncoder().encode("restored ACME account key");
const signature = await subtle.sign(
  { name: "ECDSA", hash: "SHA-256" },
  privateKey,
  data,
);
const verified = await subtle.verify(
  { name: "ECDSA", hash: "SHA-256" },
  publicKey,
  signature,
  data,
);
const privateJwk = JSON.parse(await readFile(privateJwkPath, "utf8"));
const publicJwk = JSON.parse(await readFile(publicJwkPath, "utf8"));
const jwkPrivateKey = await subtle.importKey("jwk", privateJwk, algorithm, false, ["sign"]);
const jwkPublicKey = await subtle.importKey("jwk", publicJwk, algorithm, true, ["verify"]);
const jwkSignature = await subtle.sign(
  { name: "ECDSA", hash: "SHA-256" },
  jwkPrivateKey,
  data,
);
const jwkVerified = await subtle.verify(
  { name: "ECDSA", hash: "SHA-256" },
  jwkPublicKey,
  jwkSignature,
  data,
);
console.log(`${signature.byteLength}:${verified}:${jwkSignature.byteLength}:${jwkVerified}`);
