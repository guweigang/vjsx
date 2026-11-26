const equalBytes = (left, right) => {
  if (left.byteLength !== right.byteLength) return false;
  const a = new Uint8Array(left);
  const b = new Uint8Array(right);
  for (let i = 0; i < a.length; i += 1) {
    if (a[i] !== b[i]) return false;
  }
  return true;
};

const toHex = (buffer) => Array.from(new Uint8Array(buffer))
  .map((byte) => byte.toString(16).padStart(2, "0"))
  .join("");

const keySource = Uint8Array.from([0, 9, 8, 7, 6, 5]).subarray(1);
const dataSource = Uint8Array.from([99, 1, 2, 3, 4]).subarray(1, 4);
const key = await crypto.subtle.importKey(
  "raw",
  keySource,
  { name: "HMAC", hash: "SHA-256" },
  false,
  ["sign", "verify"],
);
let exportRejected = false;
try {
  await crypto.subtle.exportKey("raw", key);
} catch {
  exportRejected = true;
}
const signature = await crypto.subtle.sign("HMAC", key, dataSource);
const verified = await crypto.subtle.verify({ name: "HMAC" }, key, signature, dataSource);
const rejected = await crypto.subtle.verify("HMAC", key, signature, Uint8Array.from([1, 2, 4]));
const digestFromView = await crypto.subtle.digest(
  "SHA-256",
  Uint8Array.from([1, 2, 3, 4]).subarray(1, 3),
);
const digestFromCopy = await crypto.subtle.digest("SHA-256", Uint8Array.from([2, 3]));
const generatedKey = await crypto.subtle.generateKey(
  { name: "HMAC", hash: "SHA-512" },
  true,
  ["sign", "verify"],
);
const exported = await crypto.subtle.exportKey("raw", generatedKey);
const generatedSignature = await crypto.subtle.sign("HMAC", generatedKey, dataSource);
const generatedVerified = await crypto.subtle.verify("HMAC", generatedKey, generatedSignature, dataSource);
const edPair = await crypto.subtle.generateKey("Ed25519", false, ["sign", "verify"]);
const edSignature = await crypto.subtle.sign("Ed25519", edPair.privateKey, dataSource);
const edVerified = await crypto.subtle.verify("Ed25519", edPair.publicKey, edSignature, dataSource);
const edRejected = await crypto.subtle.verify("Ed25519", edPair.publicKey, edSignature, Uint8Array.from([7, 8, 9]));
const exportedEdPublic = await crypto.subtle.exportKey("raw", edPair.publicKey);
const importedEdPublic = await crypto.subtle.importKey(
  "raw",
  exportedEdPublic,
  "Ed25519",
  true,
  ["verify"],
);
const importedEdVerified = await crypto.subtle.verify(
  "Ed25519",
  importedEdPublic,
  edSignature,
  dataSource,
);
const aesCbcKeyBytes = Uint8Array.from([
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
]);
const aesCbcIv = Uint8Array.from([
  15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0,
]);
const aesCbcKey = await crypto.subtle.importKey(
  "raw",
  aesCbcKeyBytes,
  "AES-CBC",
  true,
  ["encrypt", "decrypt"],
);
const aesPlaintext = Uint8Array.from([104, 101, 108, 108, 111]);
const aesCbcCiphertext = await crypto.subtle.encrypt(
  { name: "AES-CBC", iv: aesCbcIv },
  aesCbcKey,
  aesPlaintext,
);
const aesCbcDecrypted = await crypto.subtle.decrypt(
  { name: "AES-CBC", iv: aesCbcIv },
  aesCbcKey,
  aesCbcCiphertext,
);
const aesCbcExported = await crypto.subtle.exportKey("raw", aesCbcKey);
const aesCtrKey = await crypto.subtle.generateKey(
  { name: "AES-CTR", length: 128 },
  true,
  ["encrypt", "decrypt"],
);
const aesCtrCounter = Uint8Array.from([
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
]);
const aesCtrCiphertext = await crypto.subtle.encrypt(
  { name: "AES-CTR", counter: aesCtrCounter, length: 128 },
  aesCtrKey,
  aesPlaintext,
);
const aesCtrDecrypted = await crypto.subtle.decrypt(
  { name: "AES-CTR", counter: aesCtrCounter, length: 128 },
  aesCtrKey,
  aesCtrCiphertext,
);
const aesCtrExported = await crypto.subtle.exportKey("raw", aesCtrKey);
const pbkdf2BaseKey = await crypto.subtle.importKey(
  "raw",
  Uint8Array.from([112, 97, 115, 115, 119, 111, 114, 100]),
  "PBKDF2",
  false,
  ["deriveBits", "deriveKey"],
);
const pbkdf2Bits = await crypto.subtle.deriveBits(
  {
    name: "PBKDF2",
    salt: Uint8Array.from([115, 97, 108, 116]),
    iterations: 2,
    hash: "SHA-256",
  },
  pbkdf2BaseKey,
  128,
);
const pbkdf2AesKey = await crypto.subtle.deriveKey(
  {
    name: "PBKDF2",
    salt: Uint8Array.from([115, 97, 108, 116]),
    iterations: 2,
    hash: "SHA-256",
  },
  pbkdf2BaseKey,
  { name: "AES-CBC", length: 128 },
  true,
  ["encrypt", "decrypt"],
);
const pbkdf2HmacKey = await crypto.subtle.deriveKey(
  {
    name: "PBKDF2",
    salt: Uint8Array.from([115, 97, 108, 116]),
    iterations: 2,
    hash: "SHA-512",
  },
  pbkdf2BaseKey,
  { name: "HMAC", hash: "SHA-512", length: 256 },
  true,
  ["sign", "verify"],
);
const pbkdf2HmacSignature = await crypto.subtle.sign("HMAC", pbkdf2HmacKey, aesPlaintext);
const pbkdf2HmacVerified = await crypto.subtle.verify("HMAC", pbkdf2HmacKey, pbkdf2HmacSignature, aesPlaintext);
const pbkdf2AesExported = await crypto.subtle.exportKey("raw", pbkdf2AesKey);
const ecdsaPair = await crypto.subtle.generateKey(
  { name: "ECDSA", namedCurve: "P-256" },
  true,
  ["sign", "verify"],
);
const ecdsaSignature = await crypto.subtle.sign(
  { name: "ECDSA", hash: "SHA-256" },
  ecdsaPair.privateKey,
  aesPlaintext,
);
const ecdsaVerified = await crypto.subtle.verify(
  { name: "ECDSA", hash: "SHA-256" },
  ecdsaPair.publicKey,
  ecdsaSignature,
  aesPlaintext,
);
const ecdsaRejected = await crypto.subtle.verify(
  { name: "ECDSA", hash: "SHA-256" },
  ecdsaPair.publicKey,
  ecdsaSignature,
  Uint8Array.from([104, 101, 108, 112]),
);
const ecdsaMalformedRejected = await crypto.subtle.verify(
  { name: "ECDSA", hash: "SHA-256" },
  ecdsaPair.publicKey,
  new Uint8Array(ecdsaSignature).subarray(1),
  aesPlaintext,
);
const ecdsaExportedPublic = await crypto.subtle.exportKey("raw", ecdsaPair.publicKey);
const ecdsaImportedRawPublic = await crypto.subtle.importKey(
  "raw",
  ecdsaExportedPublic,
  { name: "ECDSA", namedCurve: "P-256" },
  true,
  ["verify"],
);
const ecdsaImportedRawVerified = await crypto.subtle.verify(
  { name: "ECDSA", hash: "SHA-256" },
  ecdsaImportedRawPublic,
  ecdsaSignature,
  aesPlaintext,
);
const ecdsaPkcs8 = await crypto.subtle.exportKey("pkcs8", ecdsaPair.privateKey);
const ecdsaSpki = await crypto.subtle.exportKey("spki", ecdsaPair.publicKey);
const ecdsaPrivateJwk = await crypto.subtle.exportKey("jwk", ecdsaPair.privateKey);
const ecdsaPublicJwk = await crypto.subtle.exportKey("jwk", ecdsaPair.publicKey);
const ecdsaImportedPkcs8 = await crypto.subtle.importKey(
  "pkcs8",
  ecdsaPkcs8,
  { name: "ECDSA", namedCurve: "P-256" },
  true,
  ["sign"],
);
const ecdsaImportedSpki = await crypto.subtle.importKey(
  "spki",
  ecdsaSpki,
  { name: "ECDSA", namedCurve: "P-256" },
  true,
  ["verify"],
);
const ecdsaRestoredSignature = await crypto.subtle.sign(
  { name: "ECDSA", hash: "SHA-256" },
  ecdsaImportedPkcs8,
  aesPlaintext,
);
const ecdsaRestoredVerified = await crypto.subtle.verify(
  { name: "ECDSA", hash: "SHA-256" },
  ecdsaImportedSpki,
  ecdsaRestoredSignature,
  aesPlaintext,
);
const ecdsaImportedPrivateJwk = await crypto.subtle.importKey(
  "jwk",
  ecdsaPrivateJwk,
  { name: "ECDSA", namedCurve: "P-256" },
  true,
  ["sign"],
);
const ecdsaImportedPublicJwk = await crypto.subtle.importKey(
  "jwk",
  ecdsaPublicJwk,
  { name: "ECDSA", namedCurve: "P-256" },
  true,
  ["verify"],
);
const ecdsaJwkSignature = await crypto.subtle.sign(
  { name: "ECDSA", hash: "SHA-256" },
  ecdsaImportedPrivateJwk,
  aesPlaintext,
);
const ecdsaJwkVerified = await crypto.subtle.verify(
  { name: "ECDSA", hash: "SHA-256" },
  ecdsaImportedPublicJwk,
  ecdsaJwkSignature,
  aesPlaintext,
);
const additionalEcdsaResults = [];
for (const [namedCurve, hash, expectedSize] of [
  ["P-384", "SHA-384", 96],
  ["P-521", "SHA-512", 132],
]) {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = await crypto.subtle.exportKey("pkcs8", pair.privateKey);
  const spki = await crypto.subtle.exportKey("spki", pair.publicKey);
  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    pkcs8,
    { name: "ECDSA", namedCurve },
    false,
    ["sign"],
  );
  const publicKey = await crypto.subtle.importKey(
    "spki",
    spki,
    { name: "ECDSA", namedCurve },
    true,
    ["verify"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash },
    privateKey,
    aesPlaintext,
  );
  const verified = await crypto.subtle.verify(
    { name: "ECDSA", hash },
    publicKey,
    signature,
    aesPlaintext,
  );
  additionalEcdsaResults.push(`${namedCurve}:${signature.byteLength}:${signature.byteLength === expectedSize && verified}`);
}

console.log(key.algorithm.name + ":" + key.algorithm.hash.name);
console.log(key.type);
console.log(String(key.extractable));
console.log(key.usages.join(","));
console.log(String(signature.byteLength));
console.log(String(verified));
console.log(String(rejected));
console.log(String(equalBytes(digestFromView, digestFromCopy)));
console.log(String(exportRejected));
console.log(generatedKey.algorithm.name + ":" + generatedKey.algorithm.hash.name);
console.log(String(generatedKey.algorithm.length));
console.log(String(generatedKey.extractable));
console.log(String(exported.byteLength));
console.log(String(generatedSignature.byteLength));
console.log(String(generatedVerified));
console.log(edPair.publicKey.algorithm.name + ":" + edPair.privateKey.algorithm.name);
console.log(edPair.publicKey.type + ":" + edPair.privateKey.type);
console.log(String(edPair.publicKey.extractable) + ":" + String(edPair.privateKey.extractable));
console.log(String(edSignature.byteLength));
console.log(String(edVerified));
console.log(String(edRejected));
console.log(String(exportedEdPublic.byteLength));
console.log(importedEdPublic.algorithm.name + ":" + importedEdPublic.type);
console.log(String(importedEdVerified));
console.log(aesCbcKey.algorithm.name + ":" + String(aesCbcKey.algorithm.length));
console.log(String(aesCbcCiphertext.byteLength));
console.log(String(equalBytes(aesCbcDecrypted, aesPlaintext)));
console.log(String(equalBytes(aesCbcExported, aesCbcKeyBytes.buffer)));
console.log(aesCtrKey.algorithm.name + ":" + String(aesCtrKey.algorithm.length));
console.log(String(aesCtrCiphertext.byteLength));
console.log(String(equalBytes(aesCtrDecrypted, aesPlaintext)));
console.log(String(aesCtrExported.byteLength));
console.log(pbkdf2BaseKey.algorithm.name + ":" + pbkdf2BaseKey.type);
console.log(toHex(pbkdf2Bits));
console.log(pbkdf2AesKey.algorithm.name + ":" + String(pbkdf2AesKey.algorithm.length));
console.log(String(pbkdf2AesExported.byteLength));
console.log(pbkdf2HmacKey.algorithm.name + ":" + pbkdf2HmacKey.algorithm.hash.name + ":" + String(pbkdf2HmacKey.algorithm.length));
console.log(String(pbkdf2HmacSignature.byteLength));
console.log(String(pbkdf2HmacVerified));
console.log(ecdsaPair.publicKey.algorithm.name + ":" + ecdsaPair.publicKey.algorithm.namedCurve);
console.log(ecdsaPair.publicKey.type + ":" + ecdsaPair.privateKey.type);
console.log(String(ecdsaSignature.byteLength));
console.log(String(ecdsaVerified));
console.log(String(ecdsaRejected));
console.log(String(ecdsaMalformedRejected));
console.log(String(ecdsaExportedPublic.byteLength));
console.log(String(ecdsaImportedRawVerified));
console.log(String(ecdsaPkcs8.byteLength > 0));
console.log(String(ecdsaSpki.byteLength > 0));
console.log(`${ecdsaPrivateJwk.kty}:${ecdsaPrivateJwk.crv}:${typeof ecdsaPrivateJwk.d}`);
console.log(`${ecdsaPublicJwk.kty}:${ecdsaPublicJwk.crv}:${String("d" in ecdsaPublicJwk)}`);
console.log(String(ecdsaRestoredSignature.byteLength));
console.log(String(ecdsaRestoredVerified));
console.log(String(ecdsaJwkSignature.byteLength));
console.log(String(ecdsaJwkVerified));
console.log(additionalEcdsaResults.join("\n"));
console.log(Object.prototype.toString.call(key));
console.log(Object.prototype.toString.call(crypto.subtle));
