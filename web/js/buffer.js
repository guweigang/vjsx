const binaryNative = globalThis.__vjsxBinaryNative;

function utf8Encode(value) {
  if (typeof TextEncoder === "function") return new TextEncoder().encode(String(value));
  const encoded = unescape(encodeURIComponent(String(value)));
  return Uint8Array.from(encoded, (ch) => ch.charCodeAt(0));
}

function utf8Decode(bytes) {
  if (typeof TextDecoder === "function") return new TextDecoder().decode(bytes);
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x4000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x4000));
  return decodeURIComponent(escape(binary));
}

function base64Decode(value) {
  return new Uint8Array(binaryNative.base64Decode(String(value).replace(/\s+/g, "")));
}

function base64Encode(bytes) {
  return binaryNative.base64Encode(bytes.slice().buffer);
}

function bytesFrom(input, encoding) {
  if (input instanceof ArrayBuffer) return new Uint8Array(input.slice(0));
  if (ArrayBuffer.isView(input)) return new Uint8Array(input.buffer, input.byteOffset, input.byteLength).slice();
  if (Array.isArray(input)) return Uint8Array.from(input);
  const text = String(input ?? "");
  const normalized = String(encoding || "utf8").toLowerCase();
  if (normalized === "base64") return base64Decode(text);
  if (normalized === "hex") {
    if (text.length % 2 !== 0 || /[^0-9a-f]/i.test(text)) throw new TypeError("Invalid hex data");
    return Uint8Array.from({ length: text.length / 2 }, (_, i) => parseInt(text.slice(i * 2, i * 2 + 2), 16));
  }
  if (normalized === "binary" || normalized === "latin1") return Uint8Array.from(text, (ch) => ch.charCodeAt(0) & 0xff);
  if (normalized === "utf8" || normalized === "utf-8") return utf8Encode(text);
  throw new TypeError("Unsupported Buffer encoding: " + encoding);
}

function compareBytes(left, right) {
  left = bytesFrom(left);
  right = bytesFrom(right);
  const length = Math.min(left.length, right.length);
  for (let i = 0; i < length; i++) if (left[i] !== right[i]) return left[i] < right[i] ? -1 : 1;
  return left.length === right.length ? 0 : left.length < right.length ? -1 : 1;
}

function decorate(bytes) {
  if (bytes.__vjs_buffer) return bytes;
  Object.defineProperty(bytes, "__vjs_buffer", { value: true });
  Object.defineProperties(bytes, {
	 subarray: { value(start, end) { return decorate(Uint8Array.prototype.subarray.call(this, start, end)); } },
	 slice: { value(start, end) { return decorate(Uint8Array.prototype.slice.call(this, start, end)); } },
    toString: { value(encoding = "utf8") {
      const normalized = String(encoding).toLowerCase();
      if (normalized === "hex") return Array.from(this, (byte) => byte.toString(16).padStart(2, "0")).join("");
      if (normalized === "base64") return base64Encode(this);
      if (normalized === "binary" || normalized === "latin1") return String.fromCharCode(...this);
      if (normalized === "utf8" || normalized === "utf-8") return utf8Decode(this);
      throw new TypeError("Unsupported Buffer encoding: " + encoding);
    } },
    compare: { value(other) { return compareBytes(this, other); } },
    writeUInt16LE: { value(value, offset = 0) {
      const number = Number(value) >>> 0;
      this[offset] = number & 0xff; this[offset + 1] = (number >>> 8) & 0xff;
      return offset + 2;
    } },
    writeUInt32LE: { value(value, offset = 0) {
      const number = Number(value) >>> 0;
      this[offset] = number & 0xff; this[offset + 1] = (number >>> 8) & 0xff;
      this[offset + 2] = (number >>> 16) & 0xff; this[offset + 3] = (number >>> 24) & 0xff;
      return offset + 4;
    } },
  });
  return bytes;
}

globalThis.atob = function atob(value) {
  const bytes = base64Decode(value);
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x4000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x4000));
  return binary;
};

globalThis.btoa = function btoa(value) {
  const text = String(value);
  const bytes = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) {
    if (text.charCodeAt(i) > 0xff) throw new TypeError("Invalid character");
    bytes[i] = text.charCodeAt(i);
  }
  return base64Encode(bytes);
};

globalThis.Buffer = globalThis.Buffer || {
  from(input, encoding) { return decorate(bytesFrom(input, encoding)); },
  alloc(size, fill = 0, encoding) {
    const out = decorate(new Uint8Array(Math.max(0, Number(size) || 0)));
    if (typeof fill === "number") out.fill(fill & 0xff);
    else if (fill != null) {
      const pattern = bytesFrom(fill, encoding);
      for (let i = 0; i < out.length && pattern.length; i++) out[i] = pattern[i % pattern.length];
    }
    return out;
  },
  allocUnsafe(size) { return this.alloc(size); },
  allocUnsafeSlow(size) { return this.alloc(size); },
  concat(list, totalLength) {
    const parts = Array.from(list, (part) => bytesFrom(part));
    const length = totalLength == null ? parts.reduce((sum, part) => sum + part.length, 0) : Number(totalLength);
    const out = decorate(new Uint8Array(Math.max(0, length)));
    let offset = 0;
    for (const part of parts) {
      out.set(part.subarray(0, Math.max(0, out.length - offset)), offset);
      offset += part.length;
      if (offset >= out.length) break;
    }
    return out;
  },
  compare: compareBytes,
  isBuffer(value) { return !!(value && value.__vjs_buffer); },
  byteLength(value, encoding) { return bytesFrom(value, encoding).length; },
};
