const nodeCryptoNative = globalThis.__bootstrap.nodeCrypto;

const ED25519_OID = [0x06, 0x03, 0x2b, 0x65, 0x70];
const keyMaterial = new WeakMap();

function fail(message) {
  throw new Error(message);
}

function utf8Bytes(value) {
  if (typeof TextEncoder === "function") return new TextEncoder().encode(String(value));
  const encoded = unescape(encodeURIComponent(String(value)));
  return Uint8Array.from(encoded, (ch) => ch.charCodeAt(0));
}

function bytesFromBinaryString(value) {
  const bytes = new Uint8Array(value.length);
  for (let i = 0; i < value.length; i++) bytes[i] = value.charCodeAt(i) & 0xff;
  return bytes;
}

function exactBytes(value, label = "data") {
  if (value instanceof ArrayBuffer) return new Uint8Array(value.slice(0));
  if (ArrayBuffer.isView(value)) {
    return new Uint8Array(value.buffer, value.byteOffset, value.byteLength).slice();
  }
  if (value && value.__vjs_buffer && typeof value.toString === "function") {
    return bytesFromBinaryString(value.toString("latin1"));
  }
  if (typeof value === "string") return utf8Bytes(value);
  throw new TypeError(`${label} must be a string, Buffer, TypedArray, or ArrayBuffer`);
}

function binaryString(bytes) {
  let result = "";
  for (let i = 0; i < bytes.length; i += 0x4000) {
    result += String.fromCharCode(...bytes.subarray(i, i + 0x4000));
  }
  return result;
}

function base64Encode(bytes) {
  return Buffer.from(bytes).toString("base64");
}

function base64Decode(value) {
  return Uint8Array.from(Buffer.from(value, "base64"));
}

function base64UrlDecode(value) {
  const normalized = String(value).replace(/-/g, "+").replace(/_/g, "/");
  return base64Decode(normalized + "=".repeat((4 - normalized.length % 4) % 4));
}

function makeBuffer(input) {
  const bytes = input instanceof Uint8Array ? input.slice() : new Uint8Array(input);
  Object.defineProperty(bytes, "__vjs_buffer", { value: true });
	Object.defineProperty(bytes, "subarray", {
	  configurable: true,
	  value(start, end) { return makeBuffer(Uint8Array.prototype.subarray.call(this, start, end)); },
	});
	Object.defineProperty(bytes, "slice", {
	  configurable: true,
	  value(start, end) { return makeBuffer(Uint8Array.prototype.slice.call(this, start, end)); },
	});
  Object.defineProperty(bytes, "toString", {
    configurable: true,
    value(encoding = "utf8") {
      const normalized = String(encoding).toLowerCase();
      if (normalized === "hex") {
        return Array.from(this, (byte) => byte.toString(16).padStart(2, "0")).join("");
      }
      if (normalized === "base64") return base64Encode(this);
      if (normalized === "binary" || normalized === "latin1") return binaryString(this);
      if (normalized === "utf8" || normalized === "utf-8") {
        if (typeof TextDecoder === "function") return new TextDecoder().decode(this);
        return decodeURIComponent(escape(binaryString(this)));
      }
      throw new TypeError(`Unknown encoding: ${encoding}`);
    },
  });
  return bytes;
}

function derLength(length) {
  if (length < 0x80) return [length];
  const bytes = [];
  for (let value = length; value > 0; value >>= 8) bytes.unshift(value & 0xff);
  return [0x80 | bytes.length, ...bytes];
}

function der(tag, content) {
  return Uint8Array.from([tag, ...derLength(content.length), ...content]);
}

function concat(...parts) {
  const length = parts.reduce((sum, part) => sum + part.length, 0);
  const out = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

function algorithmIdentifier() {
  return der(0x30, Uint8Array.from(ED25519_OID));
}

function encodePkcs8(seed) {
  return der(0x30, concat(
    der(0x02, Uint8Array.of(0)),
    algorithmIdentifier(),
    der(0x04, der(0x04, seed)),
  ));
}

function encodeSpki(publicKey) {
  return der(0x30, concat(
    algorithmIdentifier(),
    der(0x03, concat(Uint8Array.of(0), publicKey)),
  ));
}

class DerReader {
  constructor(bytes) {
    this.bytes = bytes;
    this.offset = 0;
  }

  readLength() {
    if (this.offset >= this.bytes.length) fail("Truncated DER length");
    const first = this.bytes[this.offset++];
    if ((first & 0x80) === 0) return first;
    const count = first & 0x7f;
    if (count === 0 || count > 4 || this.offset + count > this.bytes.length) {
      fail("Invalid DER length");
    }
    if (this.bytes[this.offset] === 0) fail("Non-canonical DER length");
    let length = 0;
    for (let i = 0; i < count; i++) length = length * 256 + this.bytes[this.offset++];
    if (length < 0x80) fail("Non-canonical DER length");
    return length;
  }

  read(tag) {
    if (this.offset >= this.bytes.length || this.bytes[this.offset++] !== tag) {
      fail(`Invalid DER tag; expected 0x${tag.toString(16)}`);
    }
    const length = this.readLength();
    if (this.offset + length > this.bytes.length) fail("Truncated DER value");
    const value = this.bytes.slice(this.offset, this.offset + length);
    this.offset += length;
    return value;
  }

  done() {
    if (this.offset !== this.bytes.length) fail("Unexpected trailing DER data");
  }
}

function parseAlgorithm(bytes) {
  const reader = new DerReader(bytes);
  const oid = reader.read(0x06);
  reader.done();
  if (oid.length !== 3 || oid[0] !== 0x2b || oid[1] !== 0x65 || oid[2] !== 0x70) {
    fail("Key algorithm is not Ed25519");
  }
}

function parsePkcs8(bytes) {
  const outer = new DerReader(bytes);
  const sequence = new DerReader(outer.read(0x30));
  outer.done();
  const version = sequence.read(0x02);
  if (version.length !== 1 || (version[0] !== 0 && version[0] !== 1)) {
    fail("Invalid PKCS8 version");
  }
  parseAlgorithm(sequence.read(0x30));
  const wrapped = new DerReader(sequence.read(0x04));
  const seed = wrapped.read(0x04);
  wrapped.done();
  if (seed.length !== 32) fail("Ed25519 PKCS8 seed must be 32 bytes");
  // RFC 5958 version 1 may append context-specific public-key/attribute fields.
  while (sequence.offset < sequence.bytes.length) {
    const tag = sequence.bytes[sequence.offset];
    if ((tag & 0xc0) !== 0x80) fail("Invalid PKCS8 optional field");
    sequence.read(tag);
  }
  return seed;
}

function parseSpki(bytes) {
  const outer = new DerReader(bytes);
  const sequence = new DerReader(outer.read(0x30));
  outer.done();
  parseAlgorithm(sequence.read(0x30));
  const bits = sequence.read(0x03);
  sequence.done();
  if (bits.length !== 33 || bits[0] !== 0) fail("Invalid Ed25519 SPKI public key");
  return bits.slice(1);
}

function decodePem(value, expectedLabel) {
  const pattern = /-----BEGIN ([A-Z0-9 ]+)-----([\s\S]*?)-----END \1-----/;
  const match = pattern.exec(String(value));
  if (!match) fail("Invalid PEM formatted message");
  if (match[1] !== expectedLabel) fail(`Expected ${expectedLabel} PEM block`);
  return base64Decode(match[2]);
}

function encodePem(label, bytes) {
  const body = base64Encode(bytes).replace(/.{1,64}/g, "$&\n");
  return `-----BEGIN ${label}-----\n${body}-----END ${label}-----\n`;
}

function normalizeKeyInput(input, kind) {
  let key = input;
  let format;
  let type;
  if (input && typeof input === "object" && !keyMaterial.has(input) && "key" in input) {
    key = input.key;
    format = input.format;
    type = input.type;
    if (input.passphrase != null) fail("Encrypted private keys are not supported");
  }
  if (keyMaterial.has(key)) return key;
	if (format == null && typeof key !== "string") {
	  const bytes = exactBytes(key, "key");
	  const text = typeof TextDecoder === "function" ? new TextDecoder().decode(bytes) : binaryString(bytes);
	  if (text.startsWith("-----BEGIN ")) {
	    key = text;
	    format = "pem";
	  }
	}
	if (format == null) format = typeof key === "string" ? "pem" : "der";
  format = String(format).toLowerCase();
  if (format === "jwk") {
    if (kind !== "public" || !key || key.kty !== "OKP" || key.crv !== "Ed25519" || typeof key.x !== "string") {
      fail("Ed25519 public JWK must use kty OKP, crv Ed25519, and x");
    }
    const publicKey = base64UrlDecode(key.x);
    if (publicKey.length !== 32) fail("Ed25519 JWK public key must be 32 bytes");
    return publicKey;
  }
  if (format === "pem") {
    const label = kind === "private" ? "PRIVATE KEY" : "PUBLIC KEY";
    return kind === "private"
      ? parsePkcs8(decodePem(key, label))
      : parseSpki(decodePem(key, label));
  }
  if (format !== "der") fail(`Unsupported key format: ${format}`);
  const expectedType = kind === "private" ? "pkcs8" : "spki";
  if (String(type || expectedType).toLowerCase() !== expectedType) {
    fail(`Ed25519 ${kind} keys require ${expectedType} format`);
  }
  const bytes = exactBytes(key, "key");
  return kind === "private" ? parsePkcs8(bytes) : parseSpki(bytes);
}

class KeyObject {
  constructor(token, type, material) {
    if (token !== keyMaterial) throw new TypeError("Illegal constructor");
    this.type = type;
    this.asymmetricKeyType = "ed25519";
    keyMaterial.set(this, material.slice());
    Object.freeze(this);
  }

  export(options = {}) {
    const format = String(options.format || "der").toLowerCase();
    const expectedType = this.type === "private" ? "pkcs8" : "spki";
    const type = String(options.type || expectedType).toLowerCase();
    if (type !== expectedType) throw new TypeError(`Ed25519 ${this.type} keys require ${expectedType}`);
    const material = keyMaterial.get(this);
    const derBytes = this.type === "private"
      ? encodePkcs8(material.slice(0, 32))
      : encodeSpki(material);
    if (format === "der") return makeBuffer(derBytes);
    if (format === "pem") return encodePem(this.type === "private" ? "PRIVATE KEY" : "PUBLIC KEY", derBytes);
    throw new TypeError(`Unsupported key export format: ${format}`);
  }

  equals(other) {
    if (!keyMaterial.has(other) || other.type !== this.type) return false;
    const left = keyMaterial.get(this);
    const right = keyMaterial.get(other);
    if (left.length !== right.length) return false;
    let difference = 0;
    for (let i = 0; i < left.length; i++) difference |= left[i] ^ right[i];
    return difference === 0;
  }
}

function privateKeyFromSeed(seed) {
  return new KeyObject(keyMaterial, "private", new Uint8Array(nodeCryptoNative.privateFromSeed(seed.slice().buffer)));
}

function createPrivateKey(input) {
  if (keyMaterial.has(input)) {
    if (input.type !== "private") throw new TypeError("Private key required");
    return new KeyObject(keyMaterial, "private", keyMaterial.get(input));
  }
  return privateKeyFromSeed(normalizeKeyInput(input, "private"));
}

function createPublicKey(input) {
  if (keyMaterial.has(input)) {
    const material = keyMaterial.get(input);
    if (input.type === "public") return new KeyObject(keyMaterial, "public", material);
    const publicKey = nodeCryptoNative.publicFromPrivate(material.slice().buffer);
    return new KeyObject(keyMaterial, "public", new Uint8Array(publicKey));
  }
  const rawKey = input && typeof input === "object" && "key" in input ? input.key : input;
  const declaredType = input && typeof input === "object" ? input.type : undefined;
  if (
    (typeof rawKey === "string" && rawKey.includes("-----BEGIN PRIVATE KEY-----")) ||
    String(declaredType || "").toLowerCase() === "pkcs8"
  ) {
    return createPublicKey(createPrivateKey(input));
  }
  return new KeyObject(keyMaterial, "public", normalizeKeyInput(input, "public"));
}

function requireKey(input, type) {
  const key = keyMaterial.has(input)
    ? input
    : type === "private" ? createPrivateKey(input) : createPublicKey(input);
  if (key.type !== type) throw new TypeError(`${type} key required`);
  return key;
}

function validateEd25519Algorithm(algorithm) {
  if (algorithm !== null && algorithm !== undefined) {
    throw new TypeError("Ed25519 requires algorithm to be null or undefined");
  }
}

function sign(algorithm, data, key) {
  validateEd25519Algorithm(algorithm);
  const privateKey = requireKey(key, "private");
  const message = exactBytes(data);
  const signature = nodeCryptoNative.sign(
    keyMaterial.get(privateKey).slice().buffer,
    message.buffer,
  );
  return makeBuffer(new Uint8Array(signature));
}

function verify(algorithm, data, key, signature) {
  validateEd25519Algorithm(algorithm);
  const publicKey = requireKey(key, "public");
  const message = exactBytes(data);
  const signatureBytes = exactBytes(signature, "signature");
  return nodeCryptoNative.verify(
    keyMaterial.get(publicKey).slice().buffer,
    message.buffer,
    signatureBytes.buffer,
  );
}

function createHash(algorithm) {
  const name = String(algorithm).toLowerCase();
  if (name !== "sha256" && name !== "sha-256" && name !== "md5") {
    throw new TypeError(`Digest method not supported: ${algorithm}`);
  }
  const chunks = [];
  let finalized = false;
  return {
    update(data, encoding) {
      if (finalized) throw new Error("Digest already called");
      chunks.push(typeof data === "string" && encoding ? exactBytes(Buffer.from(data, encoding)) : exactBytes(data));
      return this;
    },
    digest(encoding) {
      if (finalized) throw new Error("Digest already called");
      finalized = true;
      const result = makeBuffer(new Uint8Array(nodeCryptoNative.digest(name, concat(...chunks).buffer)));
      return encoding == null ? result : result.toString(encoding);
    },
  };
}

function randomUUID() {
  return nodeCryptoNative.randomUUID();
}

function encodeGeneratedKey(key, options) {
  return options ? key.export(options) : key;
}

function generateKeyPairSync(type, options = {}) {
  if (String(type).toLowerCase() !== "ed25519") throw new TypeError("Only Ed25519 is supported");
  const pair = nodeCryptoNative.generateKey();
  const privateKey = new KeyObject(keyMaterial, "private", new Uint8Array(pair.privateKey));
  const publicKey = new KeyObject(keyMaterial, "public", new Uint8Array(pair.publicKey));
  return {
    publicKey: encodeGeneratedKey(publicKey, options.publicKeyEncoding),
    privateKey: encodeGeneratedKey(privateKey, options.privateKeyEncoding),
  };
}

function generateKeyPair(type, options, callback) {
  if (typeof options === "function") {
    callback = options;
    options = {};
  }
  if (typeof callback !== "function") throw new TypeError("callback must be a function");
  Promise.resolve().then(() => {
    try {
      const pair = generateKeyPairSync(type, options || {});
      callback(null, pair.publicKey, pair.privateKey);
    } catch (error) {
      callback(error);
    }
  });
}

globalThis.__vjsxNodeCrypto = Object.freeze({
  KeyObject,
  createHash,
  createPrivateKey,
  createPublicKey,
  generateKeyPair,
  generateKeyPairSync,
  randomUUID,
  sign,
  verify,
});
