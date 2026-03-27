/* Credit: All VJS Author */
const {
  rand_uuid,
  rand_bytes,
  digest_sha1,
  digest_sha256,
  digest_sha384,
  digest_sha512,
  hmac_sha1,
  hmac_sha256,
  hmac_sha384,
  hmac_sha512,
  timing_safe_equal,
  ed25519_generate_key,
  ed25519_public_from_private,
  ed25519_sign,
  ed25519_verify,
  aes_cbc_encrypt,
  aes_cbc_decrypt,
  aes_ctr_xor,
  pbkdf2_sha256,
  pbkdf2_sha384,
  pbkdf2_sha512,
  ecdsa_generate_key,
  ecdsa_public_from_private,
  ecdsa_sign,
  ecdsa_verify_with_private,
} = globalThis.__bootstrap.crypto;

const { isArrayBuffer, isTypedArray } = globalThis.__bootstrap.util;

const kKeyMaterial = Symbol("CryptoKeyMaterial");
const keyHidden = new WeakMap();

class DumpTypeError extends TypeError {
  constructor(name, input, pos = 0) {
    const msg = `args[${pos}] expected ${name} but got ${
      input?.constructor?.name ?? typeof input
    }`;
    super(msg);
  }
}

const digestByHash = {
  "SHA-1": digest_sha1,
  "SHA-256": digest_sha256,
  "SHA-384": digest_sha384,
  "SHA-512": digest_sha512,
};

const hmacByHash = {
  "SHA-1": hmac_sha1,
  "SHA-256": hmac_sha256,
  "SHA-384": hmac_sha384,
  "SHA-512": hmac_sha512,
};

const hmacDefaultLengthByHash = {
  "SHA-1": 512,
  "SHA-256": 512,
  "SHA-384": 1024,
  "SHA-512": 1024,
};

const aesAllowedLengths = new Set([128, 192, 256]);
const pbkdf2ByHash = {
  "SHA-256": pbkdf2_sha256,
  "SHA-384": pbkdf2_sha384,
  "SHA-512": pbkdf2_sha512,
};
const ecdsaCurves = new Set(["P-256", "P-384", "P-521"]);

function promiseTry(cb) {
  try {
    return Promise.resolve(cb());
  } catch (err) {
    return Promise.reject(err);
  }
}

function toExactArrayBuffer(input, pos = 0) {
  if (isArrayBuffer(input)) return input;
  if (isTypedArray(input) || ArrayBuffer.isView(input)) {
    return new Uint8Array(
      input.buffer,
      input.byteOffset,
      input.byteLength,
    ).slice().buffer;
  }
  throw new DumpTypeError("BufferSource", input, pos);
}

function normalizeHashName(hash, pos = 0) {
  const raw = typeof hash === "object" && hash !== null ? (hash.name ?? "") : hash;
  const value = String(raw ?? "").toUpperCase().replace(/\s+/g, "");
  if (value === "SHA1" || value === "SHA-1") return "SHA-1";
  if (value === "SHA256" || value === "SHA-256") return "SHA-256";
  if (value === "SHA384" || value === "SHA-384") return "SHA-384";
  if (value === "SHA512" || value === "SHA-512") return "SHA-512";
  throw new TypeError(`args[${pos}] expected SHA-(1/256/384/512) but got ${raw}`);
}

function normalizeHmacAlgorithm(algorithm, pos = 0, options = {}) {
  const { requireHash = false } = options;
  const input =
    typeof algorithm === "object" && algorithm !== null
      ? algorithm
      : { name: algorithm };
  const name = String(input.name ?? "").toUpperCase();
  if (name !== "HMAC") {
    throw new TypeError(`args[${pos}] expected HMAC but got ${input.name ?? algorithm}`);
  }
  const normalized = { name: "HMAC" };
  if (requireHash || input.hash != null) {
    normalized.hash = Object.freeze({ name: normalizeHashName(input.hash, pos) });
  }
  if (typeof input.length === "number" && Number.isFinite(input.length)) {
    normalized.length = input.length;
  }
  return Object.freeze(normalized);
}

function normalizeKeyUsages(keyUsages, pos = 0) {
  if (!Array.isArray(keyUsages)) {
    throw new DumpTypeError("Array", keyUsages, pos);
  }
  const allowed = new Set(["sign", "verify"]);
  const seen = new Set();
  const usages = [];
  for (const usage of keyUsages) {
    const value = String(usage);
    if (!allowed.has(value)) {
      throw new TypeError(`args[${pos}] expected HMAC key usages sign/verify but got ${value}`);
    }
    if (!seen.has(value)) {
      usages.push(value);
      seen.add(value);
    }
  }
  return Object.freeze(usages);
}

function resolveDigest(algorithm) {
  return digestByHash[normalizeHashName(algorithm, 0)];
}

function resolveHmac(algorithm) {
  return hmacByHash[algorithm.hash.name];
}

function cloneHmacAlgorithm(algorithm, keyLength) {
  const length = Number.isFinite(algorithm.length) ? algorithm.length : keyLength * 8;
  return Object.freeze({
    name: "HMAC",
    hash: Object.freeze({ name: algorithm.hash.name }),
    length,
  });
}

function cloneArrayBuffer(buffer) {
  return new Uint8Array(buffer).slice().buffer;
}

function bitsToBytes(length, pos = 0) {
  if (!Number.isInteger(length) || length <= 0) {
    throw new TypeError(`args[${pos}] expected a positive integer key length but got ${length}`);
  }
  return Math.ceil(length / 8);
}

function normalizeExtractable(extractable) {
  return !!extractable;
}

function toByteArray(buffer) {
  return new Uint8Array(buffer);
}

function normalizeAesName(name, pos = 0) {
  const value = String(name ?? "").toUpperCase();
  if (value === "AES-CBC") return "AES-CBC";
  if (value === "AES-CTR") return "AES-CTR";
  throw new TypeError(`args[${pos}] expected AES-CBC/AES-CTR but got ${name}`);
}

function normalizeAesKeyAlgorithm(algorithm, pos = 0, options = {}) {
  const { requireLength = false } = options;
  const input =
    typeof algorithm === "object" && algorithm !== null
      ? algorithm
      : { name: algorithm };
  const name = normalizeAesName(input.name ?? algorithm, pos);
  const normalized = { name };
  if (requireLength || input.length != null) {
    const length = Number(input.length);
    if (!aesAllowedLengths.has(length)) {
      throw new TypeError(`args[${pos}] expected AES key length 128/192/256 but got ${input.length}`);
    }
    normalized.length = length;
  }
  return Object.freeze(normalized);
}

function normalizeAesUsages(keyUsages, pos = 0) {
  if (!Array.isArray(keyUsages)) {
    throw new DumpTypeError("Array", keyUsages, pos);
  }
  const allowed = new Set(["encrypt", "decrypt"]);
  const seen = new Set();
  const usages = [];
  for (const usage of keyUsages) {
    const value = String(usage);
    if (!allowed.has(value)) {
      throw new TypeError(`args[${pos}] expected AES key usages encrypt/decrypt but got ${value}`);
    }
    if (!seen.has(value)) {
      usages.push(value);
      seen.add(value);
    }
  }
  return Object.freeze(usages);
}

function cloneAesAlgorithm(algorithm, keyLength) {
  const length = Number.isFinite(algorithm.length) ? algorithm.length : keyLength * 8;
  return Object.freeze({
    name: algorithm.name,
    length,
  });
}

function normalizeAesCbcParams(algorithm, pos = 0) {
  const input =
    typeof algorithm === "object" && algorithm !== null
      ? algorithm
      : { name: algorithm };
  const name = normalizeAesName(input.name ?? algorithm, pos);
  if (name !== "AES-CBC") {
    throw new TypeError(`args[${pos}] expected AES-CBC but got ${input.name ?? algorithm}`);
  }
  const iv = toExactArrayBuffer(input.iv, pos);
  if (iv.byteLength !== 16) {
    throw new TypeError(`args[${pos}] expected 16-byte AES-CBC iv but got ${iv.byteLength}`);
  }
  return Object.freeze({ name, iv });
}

function normalizeAesCtrParams(algorithm, pos = 0) {
  const input =
    typeof algorithm === "object" && algorithm !== null
      ? algorithm
      : { name: algorithm };
  const name = normalizeAesName(input.name ?? algorithm, pos);
  if (name !== "AES-CTR") {
    throw new TypeError(`args[${pos}] expected AES-CTR but got ${input.name ?? algorithm}`);
  }
  const counter = toExactArrayBuffer(input.counter, pos);
  if (counter.byteLength !== 16) {
    throw new TypeError(`args[${pos}] expected 16-byte AES-CTR counter but got ${counter.byteLength}`);
  }
  const length = Number(input.length);
  if (length !== 128) {
    throw new TypeError(`args[${pos}] currently supports AES-CTR length 128 only, got ${input.length}`);
  }
  return Object.freeze({ name, counter, length });
}

function normalizePbkdf2Algorithm(algorithm, pos = 0) {
  const input =
    typeof algorithm === "object" && algorithm !== null
      ? algorithm
      : { name: algorithm };
  const name = String(input.name ?? "").toUpperCase();
  if (name !== "PBKDF2") {
    throw new TypeError(`args[${pos}] expected PBKDF2 but got ${input.name ?? algorithm}`);
  }
  return Object.freeze({ name: "PBKDF2" });
}

function normalizePbkdf2ImportUsages(keyUsages, pos = 0) {
  if (!Array.isArray(keyUsages)) {
    throw new DumpTypeError("Array", keyUsages, pos);
  }
  const allowed = new Set(["deriveBits", "deriveKey"]);
  const seen = new Set();
  const usages = [];
  for (const usage of keyUsages) {
    const value = String(usage);
    if (!allowed.has(value)) {
      throw new TypeError(`args[${pos}] expected PBKDF2 key usages deriveBits/deriveKey but got ${value}`);
    }
    if (!seen.has(value)) {
      usages.push(value);
      seen.add(value);
    }
  }
  return Object.freeze(usages);
}

function normalizePbkdf2Params(algorithm, pos = 0) {
  const input =
    typeof algorithm === "object" && algorithm !== null
      ? algorithm
      : { name: algorithm };
  const name = String(input.name ?? "").toUpperCase();
  if (name !== "PBKDF2") {
    throw new TypeError(`args[${pos}] expected PBKDF2 but got ${input.name ?? algorithm}`);
  }
  const salt = toExactArrayBuffer(input.salt, pos);
  const iterations = Number(input.iterations);
  if (!Number.isInteger(iterations) || iterations <= 0) {
    throw new TypeError(`args[${pos}] expected positive PBKDF2 iterations but got ${input.iterations}`);
  }
  const hash = normalizeHashName(input.hash, pos);
  if (!(hash in pbkdf2ByHash)) {
    throw new TypeError(`args[${pos}] currently supports PBKDF2 with SHA-256/384/512, got ${hash}`);
  }
  return Object.freeze({
    name: "PBKDF2",
    salt,
    iterations,
    hash: Object.freeze({ name: hash }),
  });
}

function normalizeEcdsaNamedCurve(namedCurve, pos = 0) {
  const value = String(namedCurve ?? "").toUpperCase();
  if (value === "P-256") return "P-256";
  if (value === "P-384") return "P-384";
  if (value === "P-521") return "P-521";
  throw new TypeError(`args[${pos}] expected P-256/P-384/P-521 but got ${namedCurve}`);
}

function normalizeEcdsaKeyGenParams(algorithm, pos = 0) {
  const input =
    typeof algorithm === "object" && algorithm !== null
      ? algorithm
      : { name: algorithm };
  const name = String(input.name ?? "").toUpperCase();
  if (name !== "ECDSA") {
    throw new TypeError(`args[${pos}] expected ECDSA but got ${input.name ?? algorithm}`);
  }
  return Object.freeze({
    name: "ECDSA",
    namedCurve: normalizeEcdsaNamedCurve(input.namedCurve, pos),
  });
}

function normalizeEcdsaParams(algorithm, pos = 0) {
  const input =
    typeof algorithm === "object" && algorithm !== null
      ? algorithm
      : { name: algorithm };
  const name = String(input.name ?? "").toUpperCase();
  if (name !== "ECDSA") {
    throw new TypeError(`args[${pos}] expected ECDSA but got ${input.name ?? algorithm}`);
  }
  return Object.freeze({
    name: "ECDSA",
    hash: Object.freeze({ name: normalizeHashName(input.hash, pos) }),
  });
}

function normalizeEcdsaUsages(keyUsages, type, pos = 0) {
  if (!Array.isArray(keyUsages)) {
    throw new DumpTypeError("Array", keyUsages, pos);
  }
  const allowed = new Set(type === "private" ? ["sign"] : ["verify"]);
  const seen = new Set();
  const usages = [];
  for (const usage of keyUsages) {
    const value = String(usage);
    if (!allowed.has(value)) {
      throw new TypeError(
        `args[${pos}] expected ECDSA ${type} key usages ${[...allowed].join("/")} but got ${value}`,
      );
    }
    if (!seen.has(value)) {
      usages.push(value);
      seen.add(value);
    }
  }
  return Object.freeze(usages);
}

function pkcs7Pad(buffer, blockSize) {
  const bytes = toByteArray(buffer);
  const padding = blockSize - (bytes.length % blockSize || blockSize) + (bytes.length % blockSize === 0 ? blockSize : 0);
  const out = new Uint8Array(bytes.length + padding);
  out.set(bytes, 0);
  out.fill(padding, bytes.length);
  return out.buffer;
}

function pkcs7Unpad(buffer, blockSize) {
  const bytes = toByteArray(buffer);
  if (bytes.length === 0 || bytes.length % blockSize !== 0) {
    throw new TypeError("AES-CBC plaintext has invalid padded length");
  }
  const padding = bytes[bytes.length - 1];
  if (padding < 1 || padding > blockSize || padding > bytes.length) {
    throw new TypeError("AES-CBC plaintext has invalid padding");
  }
  for (let i = bytes.length - padding; i < bytes.length; i += 1) {
    if (bytes[i] !== padding) {
      throw new TypeError("AES-CBC plaintext has invalid padding");
    }
  }
  return bytes.slice(0, bytes.length - padding).buffer;
}

function normalizeEd25519Algorithm(algorithm, pos = 0) {
  const input =
    typeof algorithm === "object" && algorithm !== null
      ? algorithm
      : { name: algorithm };
  const name = String(input.name ?? "").toUpperCase();
  if (name !== "ED25519") {
    throw new TypeError(`args[${pos}] expected Ed25519 but got ${input.name ?? algorithm}`);
  }
  return Object.freeze({ name: "Ed25519" });
}

function normalizeEd25519Usages(keyUsages, type, pos = 0) {
  if (!Array.isArray(keyUsages)) {
    throw new DumpTypeError("Array", keyUsages, pos);
  }
  const allowed = new Set(type === "private" ? ["sign"] : ["verify"]);
  const seen = new Set();
  const usages = [];
  for (const usage of keyUsages) {
    const value = String(usage);
    if (!allowed.has(value)) {
      throw new TypeError(
        `args[${pos}] expected Ed25519 ${type} key usages ${[...allowed].join("/")} but got ${value}`,
      );
    }
    if (!seen.has(value)) {
      usages.push(value);
      seen.add(value);
    }
  }
  return Object.freeze(usages);
}

function assertCryptoKey(key, pos = 1) {
  if (!(key instanceof CryptoKey)) {
    throw new DumpTypeError("CryptoKey", key, pos);
  }
  return key;
}

function assertHmacKey(key, usage) {
  const cryptoKey = assertCryptoKey(key, 1);
  if (cryptoKey.type !== "secret" || cryptoKey.algorithm?.name !== "HMAC") {
    throw new TypeError("CryptoKey is not an HMAC secret key");
  }
  if (!cryptoKey.usages.includes(usage)) {
    throw new TypeError(`CryptoKey does not allow "${usage}"`);
  }
  return cryptoKey;
}

function assertHmacAlgorithmMatchesKey(algorithm, keyAlgorithm) {
  const normalized = normalizeHmacAlgorithm(algorithm, 0);
  if (normalized.hash && normalized.hash.name !== keyAlgorithm.hash.name) {
    throw new TypeError(
      `HMAC hash mismatch: expected ${keyAlgorithm.hash.name} but got ${normalized.hash.name}`,
    );
  }
}

function assertEd25519Key(key, usage) {
  const cryptoKey = assertCryptoKey(key, 1);
  if (cryptoKey.algorithm?.name !== "Ed25519") {
    throw new TypeError("CryptoKey is not an Ed25519 key");
  }
  if (!cryptoKey.usages.includes(usage)) {
    throw new TypeError(`CryptoKey does not allow "${usage}"`);
  }
  if (usage === "sign" && cryptoKey.type !== "private") {
    throw new TypeError("Ed25519 signing requires a private key");
  }
  if (usage === "verify" && cryptoKey.type !== "public") {
    throw new TypeError("Ed25519 verification requires a public key");
  }
  return cryptoKey;
}

function assertEd25519AlgorithmMatchesKey(algorithm, keyAlgorithm) {
  const normalized = normalizeEd25519Algorithm(algorithm, 0);
  if (normalized.name !== keyAlgorithm.name) {
    throw new TypeError(`Ed25519 algorithm mismatch: expected ${keyAlgorithm.name}`);
  }
}

function assertAesKey(key, usage, expectedName) {
  const cryptoKey = assertCryptoKey(key, 1);
  if (cryptoKey.type !== "secret") {
    throw new TypeError("AES operations require a secret key");
  }
  if (cryptoKey.algorithm?.name !== expectedName) {
    throw new TypeError(`CryptoKey algorithm mismatch: expected ${expectedName} but got ${cryptoKey.algorithm?.name}`);
  }
  if (!cryptoKey.usages.includes(usage)) {
    throw new TypeError(`CryptoKey does not allow "${usage}"`);
  }
  return cryptoKey;
}

function assertPbkdf2Key(key, usage) {
  const cryptoKey = assertCryptoKey(key, 1);
  if (cryptoKey.type !== "secret" || cryptoKey.algorithm?.name !== "PBKDF2") {
    throw new TypeError("CryptoKey is not a PBKDF2 base key");
  }
  if (!cryptoKey.usages.includes(usage)) {
    throw new TypeError(`CryptoKey does not allow "${usage}"`);
  }
  return cryptoKey;
}

function assertEcdsaKey(key, usage) {
  const cryptoKey = assertCryptoKey(key, 1);
  if (cryptoKey.algorithm?.name !== "ECDSA" || !ecdsaCurves.has(cryptoKey.algorithm?.namedCurve)) {
    throw new TypeError("CryptoKey is not an ECDSA key");
  }
  if (!cryptoKey.usages.includes(usage)) {
    throw new TypeError(`CryptoKey does not allow "${usage}"`);
  }
  if (usage === "sign" && cryptoKey.type !== "private") {
    throw new TypeError("ECDSA signing requires a private key");
  }
  if (usage === "verify" && cryptoKey.type !== "public") {
    throw new TypeError("ECDSA verification requires a public key");
  }
  return cryptoKey;
}

function derivePbkdf2Bits(params, baseKey, length) {
  if (!Number.isInteger(length) || length <= 0 || length % 8 !== 0) {
    throw new TypeError(`args[2] expected positive bit length divisible by 8 but got ${length}`);
  }
  return pbkdf2ByHash[params.hash.name](
    baseKey[kKeyMaterial],
    params.salt,
    params.iterations,
    bitsToBytes(length, 2),
  );
}

class CryptoKey {
  constructor(type, extractable, algorithm, usages, material) {
    Object.defineProperties(this, {
      type: { value: type, enumerable: true },
      extractable: { value: !!extractable, enumerable: true },
      algorithm: { value: algorithm, enumerable: true },
      usages: { value: usages, enumerable: true },
      [kKeyMaterial]: { value: material },
    });
  }
}

Object.defineProperty(CryptoKey.prototype, Symbol.toStringTag, {
  value: "CryptoKey",
});

class SubtleCrypto {
  digest(algorithm, buffer) {
    return promiseTry(() => resolveDigest(algorithm)(toExactArrayBuffer(buffer, 1)));
  }

  deriveBits(algorithm, baseKey, length) {
    return promiseTry(() => {
      const params = normalizePbkdf2Params(algorithm, 0);
      const cryptoKey = assertPbkdf2Key(baseKey, "deriveBits");
      return derivePbkdf2Bits(params, cryptoKey, length);
    });
  }

  deriveKey(algorithm, baseKey, derivedKeyType, extractable, keyUsages) {
    return promiseTry(async () => {
      const params = normalizePbkdf2Params(algorithm, 0);
      const cryptoKey = assertPbkdf2Key(baseKey, "deriveKey");
      const typeName =
        typeof derivedKeyType === "object" && derivedKeyType !== null
          ? String(derivedKeyType.name ?? "").toUpperCase()
          : String(derivedKeyType ?? "").toUpperCase();
      if (typeName === "HMAC") {
        const normalized = normalizeHmacAlgorithm(derivedKeyType, 2, {
          requireHash: true,
        });
        const length = Number.isFinite(normalized.length)
          ? normalized.length
          : hmacDefaultLengthByHash[normalized.hash.name];
        const bits = derivePbkdf2Bits(params, cryptoKey, length);
        return new CryptoKey(
          "secret",
          normalizeExtractable(extractable),
          cloneHmacAlgorithm({ ...normalized, length }, bits.byteLength),
          normalizeKeyUsages(keyUsages, 4),
          bits,
        );
      }
      if (typeName === "AES-CBC" || typeName === "AES-CTR") {
        const normalized = normalizeAesKeyAlgorithm(derivedKeyType, 2, {
          requireLength: true,
        });
        const bits = derivePbkdf2Bits(params, cryptoKey, normalized.length);
        return new CryptoKey(
          "secret",
          normalizeExtractable(extractable),
          cloneAesAlgorithm(normalized, bits.byteLength),
          normalizeAesUsages(keyUsages, 4),
          bits,
        );
      }
      throw new TypeError(`args[2] expected HMAC/AES-CBC/AES-CTR but got ${derivedKeyType?.name ?? derivedKeyType}`);
    });
  }

  encrypt(algorithm, key, data) {
    return promiseTry(() => {
      const algoName =
        typeof algorithm === "object" && algorithm !== null
          ? String(algorithm.name ?? "").toUpperCase()
          : String(algorithm ?? "").toUpperCase();
      if (algoName === "AES-CBC") {
        const params = normalizeAesCbcParams(algorithm, 0);
        const cryptoKey = assertAesKey(key, "encrypt", "AES-CBC");
        return aes_cbc_encrypt(
          cryptoKey[kKeyMaterial],
          pkcs7Pad(toExactArrayBuffer(data, 2), 16),
          params.iv,
        );
      }
      if (algoName === "AES-CTR") {
        const params = normalizeAesCtrParams(algorithm, 0);
        const cryptoKey = assertAesKey(key, "encrypt", "AES-CTR");
        return aes_ctr_xor(
          cryptoKey[kKeyMaterial],
          toExactArrayBuffer(data, 2),
          params.counter,
        );
      }
      throw new TypeError(`args[0] expected AES-CBC/AES-CTR but got ${algorithm?.name ?? algorithm}`);
    });
  }

  decrypt(algorithm, key, data) {
    return promiseTry(() => {
      const algoName =
        typeof algorithm === "object" && algorithm !== null
          ? String(algorithm.name ?? "").toUpperCase()
          : String(algorithm ?? "").toUpperCase();
      if (algoName === "AES-CBC") {
        const params = normalizeAesCbcParams(algorithm, 0);
        const cryptoKey = assertAesKey(key, "decrypt", "AES-CBC");
        const plain = aes_cbc_decrypt(
          cryptoKey[kKeyMaterial],
          toExactArrayBuffer(data, 2),
          params.iv,
        );
        return pkcs7Unpad(plain, 16);
      }
      if (algoName === "AES-CTR") {
        const params = normalizeAesCtrParams(algorithm, 0);
        const cryptoKey = assertAesKey(key, "decrypt", "AES-CTR");
        return aes_ctr_xor(
          cryptoKey[kKeyMaterial],
          toExactArrayBuffer(data, 2),
          params.counter,
        );
      }
      throw new TypeError(`args[0] expected AES-CBC/AES-CTR but got ${algorithm?.name ?? algorithm}`);
    });
  }

  exportKey(format, key) {
    return promiseTry(() => {
      const cryptoKey = assertCryptoKey(key, 1);
      if (!cryptoKey.extractable) {
        throw new TypeError("CryptoKey is not extractable");
      }
      if (format !== "raw") {
        throw new TypeError(`args[0] expected raw but got ${format}`);
      }
      if (cryptoKey.algorithm?.name === "HMAC") {
        return cloneArrayBuffer(cryptoKey[kKeyMaterial]);
      }
      if (cryptoKey.algorithm?.name === "AES-CBC" || cryptoKey.algorithm?.name === "AES-CTR") {
        return cloneArrayBuffer(cryptoKey[kKeyMaterial]);
      }
      if (cryptoKey.algorithm?.name === "ECDSA" && cryptoKey.type === "public") {
        return cloneArrayBuffer(cryptoKey[kKeyMaterial]);
      }
      if (cryptoKey.algorithm?.name === "Ed25519" && cryptoKey.type === "public") {
        return cloneArrayBuffer(cryptoKey[kKeyMaterial]);
      }
      throw new TypeError(`args[1] expected exportable HMAC/AES/ECDSA public/Ed25519 public CryptoKey but got ${cryptoKey.algorithm?.name ?? cryptoKey.type}`);
    });
  }

  generateKey(algorithm, extractable, keyUsages) {
    return promiseTry(() => {
      const algoName =
        typeof algorithm === "object" && algorithm !== null
          ? String(algorithm.name ?? "").toUpperCase()
          : String(algorithm ?? "").toUpperCase();
      if (algoName === "ED25519") {
        normalizeEd25519Algorithm(algorithm, 0);
        if (!Array.isArray(keyUsages)) {
          throw new DumpTypeError("Array", keyUsages, 2);
        }
        const wantsSign = keyUsages.includes("sign");
        const wantsVerify = keyUsages.includes("verify");
        for (const usage of keyUsages) {
          if (usage !== "sign" && usage !== "verify") {
            throw new TypeError(`args[2] expected Ed25519 key usages sign/verify but got ${usage}`);
          }
        }
        if (!wantsSign && !wantsVerify) {
          throw new TypeError('args[2] expected at least one Ed25519 key usage');
        }
        const pair = ed25519_generate_key();
        const publicMaterial = toExactArrayBuffer(pair.publicKey);
        const privateMaterial = toExactArrayBuffer(pair.privateKey);
        return {
          publicKey: new CryptoKey(
            "public",
            true,
            Object.freeze({ name: "Ed25519" }),
            Object.freeze(wantsVerify ? ["verify"] : []),
            publicMaterial,
          ),
          privateKey: new CryptoKey(
            "private",
            normalizeExtractable(extractable),
            Object.freeze({ name: "Ed25519" }),
            Object.freeze(wantsSign ? ["sign"] : []),
            privateMaterial,
          ),
        };
      }
      if (algoName === "ECDSA") {
        const normalized = normalizeEcdsaKeyGenParams(algorithm, 0);
        if (!Array.isArray(keyUsages)) {
          throw new DumpTypeError("Array", keyUsages, 2);
        }
        const wantsSign = keyUsages.includes("sign");
        const wantsVerify = keyUsages.includes("verify");
        for (const usage of keyUsages) {
          if (usage !== "sign" && usage !== "verify") {
            throw new TypeError(`args[2] expected ECDSA key usages sign/verify but got ${usage}`);
          }
        }
        if (!wantsSign && !wantsVerify) {
          throw new TypeError('args[2] expected at least one ECDSA key usage');
        }
        const pair = ecdsa_generate_key(normalized.namedCurve);
        const publicMaterial = toExactArrayBuffer(pair.publicKey);
        const privateMaterial = toExactArrayBuffer(pair.privateKey);
        const publicKey = new CryptoKey(
          "public",
          true,
          Object.freeze({ name: "ECDSA", namedCurve: normalized.namedCurve }),
          Object.freeze(wantsVerify ? ["verify"] : []),
          publicMaterial,
        );
        const privateKey = new CryptoKey(
          "private",
          normalizeExtractable(extractable),
          Object.freeze({ name: "ECDSA", namedCurve: normalized.namedCurve }),
          Object.freeze(wantsSign ? ["sign"] : []),
          privateMaterial,
        );
        keyHidden.set(publicKey, {
          ecdsaPrivateMaterial: privateMaterial,
        });
        return { publicKey, privateKey };
      }
      if (algoName === "AES-CBC" || algoName === "AES-CTR") {
        const normalizedAlgorithm = normalizeAesKeyAlgorithm(algorithm, 0, {
          requireLength: true,
        });
        const usages = normalizeAesUsages(keyUsages, 2);
        const material = rand_bytes(bitsToBytes(normalizedAlgorithm.length, 0));
        return new CryptoKey(
          "secret",
          normalizeExtractable(extractable),
          cloneAesAlgorithm(normalizedAlgorithm, material.byteLength),
          usages,
          material,
        );
      }
      const normalizedAlgorithm = normalizeHmacAlgorithm(algorithm, 0, {
        requireHash: true,
      });
      const usages = normalizeKeyUsages(keyUsages, 2);
      const length =
        Number.isFinite(normalizedAlgorithm.length)
          ? normalizedAlgorithm.length
          : hmacDefaultLengthByHash[normalizedAlgorithm.hash.name];
      const material = rand_bytes(bitsToBytes(length, 0));
      return new CryptoKey(
        "secret",
        normalizeExtractable(extractable),
        cloneHmacAlgorithm({ ...normalizedAlgorithm, length }, material.byteLength),
        usages,
        material,
      );
    });
  }

  importKey(format, keyData, algorithm, extractable, keyUsages) {
    return promiseTry(() => {
      const algoName =
        typeof algorithm === "object" && algorithm !== null
          ? String(algorithm.name ?? "").toUpperCase()
          : String(algorithm ?? "").toUpperCase();
      if (algoName === "ED25519") {
        if (format !== "raw") {
          throw new TypeError(`args[0] expected raw but got ${format}`);
        }
        normalizeEd25519Algorithm(algorithm, 2);
        const material = toExactArrayBuffer(keyData, 1);
        if (material.byteLength !== 32) {
          throw new TypeError(`args[1] expected 32-byte Ed25519 public key but got ${material.byteLength}`);
        }
        return new CryptoKey(
          "public",
          normalizeExtractable(extractable),
          Object.freeze({ name: "Ed25519" }),
          normalizeEd25519Usages(keyUsages, "public", 4),
          material,
        );
      }
      if (algoName === "PBKDF2") {
        if (format !== "raw") {
          throw new TypeError(`args[0] expected raw but got ${format}`);
        }
        normalizePbkdf2Algorithm(algorithm, 2);
        const material = toExactArrayBuffer(keyData, 1);
        return new CryptoKey(
          "secret",
          normalizeExtractable(extractable),
          Object.freeze({ name: "PBKDF2" }),
          normalizePbkdf2ImportUsages(keyUsages, 4),
          material,
        );
      }
      if (algoName === "AES-CBC" || algoName === "AES-CTR") {
        if (format !== "raw") {
          throw new TypeError(`args[0] expected raw but got ${format}`);
        }
        const normalizedAlgorithm = normalizeAesKeyAlgorithm(algorithm, 2);
        const material = toExactArrayBuffer(keyData, 1);
        const bitLength = material.byteLength * 8;
        if (!aesAllowedLengths.has(bitLength)) {
          throw new TypeError(`args[1] expected 16/24/32-byte AES key but got ${material.byteLength}`);
        }
        if (normalizedAlgorithm.length != null && normalizedAlgorithm.length !== bitLength) {
          throw new TypeError(`args[2] AES key length mismatch: expected ${normalizedAlgorithm.length} but got ${bitLength}`);
        }
        return new CryptoKey(
          "secret",
          normalizeExtractable(extractable),
          cloneAesAlgorithm(normalizedAlgorithm, material.byteLength),
          normalizeAesUsages(keyUsages, 4),
          material,
        );
      }
      if (format !== "raw") {
        throw new TypeError(`args[0] expected raw but got ${format}`);
      }
      const normalizedAlgorithm = normalizeHmacAlgorithm(algorithm, 2, {
        requireHash: true,
      });
      const material = toExactArrayBuffer(keyData, 1);
      const usages = normalizeKeyUsages(keyUsages, 4);
      return new CryptoKey(
        "secret",
        normalizeExtractable(extractable),
        cloneHmacAlgorithm(normalizedAlgorithm, material.byteLength),
        usages,
        material,
      );
    });
  }

  sign(algorithm, key, data) {
    return promiseTry(() => {
      const algoName =
        typeof algorithm === "object" && algorithm !== null
          ? String(algorithm.name ?? "").toUpperCase()
          : String(algorithm ?? "").toUpperCase();
      if (algoName === "ED25519") {
        const cryptoKey = assertEd25519Key(key, "sign");
        assertEd25519AlgorithmMatchesKey(algorithm, cryptoKey.algorithm);
        return ed25519_sign(cryptoKey[kKeyMaterial], toExactArrayBuffer(data, 2));
      }
      if (algoName === "ECDSA") {
        const cryptoKey = assertEcdsaKey(key, "sign");
        const params = normalizeEcdsaParams(algorithm, 0);
        return ecdsa_sign(
          cryptoKey[kKeyMaterial],
          toExactArrayBuffer(data, 2),
          cryptoKey.algorithm.namedCurve,
          params.hash.name,
        );
      }
      const cryptoKey = assertHmacKey(key, "sign");
      assertHmacAlgorithmMatchesKey(algorithm, cryptoKey.algorithm);
      return resolveHmac(cryptoKey.algorithm)(
        cryptoKey[kKeyMaterial],
        toExactArrayBuffer(data, 2),
      );
    });
  }

  verify(algorithm, key, signature, data) {
    return promiseTry(() => {
      const algoName =
        typeof algorithm === "object" && algorithm !== null
          ? String(algorithm.name ?? "").toUpperCase()
          : String(algorithm ?? "").toUpperCase();
      if (algoName === "ED25519") {
        const cryptoKey = assertEd25519Key(key, "verify");
        assertEd25519AlgorithmMatchesKey(algorithm, cryptoKey.algorithm);
        return ed25519_verify(
          cryptoKey[kKeyMaterial],
          toExactArrayBuffer(data, 3),
          toExactArrayBuffer(signature, 2),
        );
      }
      if (algoName === "ECDSA") {
        const cryptoKey = assertEcdsaKey(key, "verify");
        const params = normalizeEcdsaParams(algorithm, 0);
        const hidden = keyHidden.get(cryptoKey);
        if (!hidden?.ecdsaPrivateMaterial) {
          throw new TypeError("ECDSA verify currently supports generated public keys only");
        }
        return ecdsa_verify_with_private(
          hidden.ecdsaPrivateMaterial,
          toExactArrayBuffer(data, 3),
          toExactArrayBuffer(signature, 2),
          cryptoKey.algorithm.namedCurve,
          params.hash.name,
        );
      }
      const cryptoKey = assertHmacKey(key, "verify");
      assertHmacAlgorithmMatchesKey(algorithm, cryptoKey.algorithm);
      const actual = resolveHmac(cryptoKey.algorithm)(
        cryptoKey[kKeyMaterial],
        toExactArrayBuffer(data, 3),
      );
      return timing_safe_equal(toExactArrayBuffer(signature, 2), actual);
    });
  }
}

Object.defineProperty(SubtleCrypto.prototype, Symbol.toStringTag, {
  value: "SubtleCrypto",
});

globalThis.CryptoKey = CryptoKey;
globalThis.SubtleCrypto = SubtleCrypto;

globalThis.crypto = {
  randomUUID: rand_uuid,
  getRandomValues: (input) => {
    if (isTypedArray(input)) {
      const { BYTES_PER_ELEMENT, length } = input;
      Reflect.construct(input.constructor, [
        rand_bytes(BYTES_PER_ELEMENT * length),
      ]).forEach((val, i) => (input[i] = val));
      return input;
    }
    throw new DumpTypeError("TypedArray", input);
  },
  subtle: new SubtleCrypto(),
};
