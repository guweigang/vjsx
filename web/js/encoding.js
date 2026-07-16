/* Credit: All VJS Author */

const { text_encode, text_decode, text_encode_into, decode_text } = globalThis.__bootstrap;

const replacement = "\uFFFD";

const encodingLabels = new Map([
  ["unicode-1-1-utf-8", "utf-8"],
  ["unicode11utf8", "utf-8"],
  ["unicode20utf8", "utf-8"],
  ["utf-8", "utf-8"],
  ["utf8", "utf-8"],
  ["x-unicode20utf8", "utf-8"],
  ["chinese", "gbk"],
  ["csgb2312", "gbk"],
  ["csiso58gb231280", "gbk"],
  ["gb2312", "gbk"],
  ["gb_2312", "gbk"],
  ["gb_2312-80", "gbk"],
  ["gbk", "gbk"],
  ["iso-ir-58", "gbk"],
  ["x-gbk", "gbk"],
  ["gb18030", "gb18030"],
]);

function normalizeEncodingLabel(label) {
  const normalized = String(label ?? "utf-8").trim().toLowerCase();
  const encoding = encodingLabels.get(normalized);
  if (encoding === undefined) {
    throw new RangeError(`The encoding label provided ('${label}') is invalid.`);
  }
  return encoding;
}

function encodeUtf8(input) {
  const text = String(input ?? "");
  const bytes = [];
  for (let i = 0; i < text.length; i++) {
    let codePoint = text.charCodeAt(i);
    if (codePoint >= 0xd800 && codePoint <= 0xdbff && i + 1 < text.length) {
      const next = text.charCodeAt(i + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        codePoint = 0x10000 + ((codePoint - 0xd800) << 10) + (next - 0xdc00);
        i++;
      }
    }
    if (codePoint <= 0x7f) {
      bytes.push(codePoint);
    } else if (codePoint <= 0x7ff) {
      bytes.push(0xc0 | (codePoint >> 6));
      bytes.push(0x80 | (codePoint & 0x3f));
    } else if (codePoint <= 0xffff) {
      bytes.push(0xe0 | (codePoint >> 12));
      bytes.push(0x80 | ((codePoint >> 6) & 0x3f));
      bytes.push(0x80 | (codePoint & 0x3f));
    } else {
      bytes.push(0xf0 | (codePoint >> 18));
      bytes.push(0x80 | ((codePoint >> 12) & 0x3f));
      bytes.push(0x80 | ((codePoint >> 6) & 0x3f));
      bytes.push(0x80 | (codePoint & 0x3f));
    }
  }
  return new Uint8Array(bytes);
}

function bytesFromInput(input) {
  if (input == null) {
    return new Uint8Array();
  }
  if (input instanceof ArrayBuffer) {
    return new Uint8Array(input);
  }
  if (ArrayBuffer.isView(input)) {
    return new Uint8Array(input.buffer.slice(input.byteOffset, input.byteOffset + input.byteLength));
  }
  return new Uint8Array(input);
}

function decodeUtf8(input) {
  const bytes = bytesFromInput(input);
  let out = "";
  for (let i = 0; i < bytes.length; i++) {
    const first = bytes[i];
    if (first < 0x80) {
      out += String.fromCharCode(first);
    } else if ((first & 0xe0) === 0xc0 && i + 1 < bytes.length) {
      const second = bytes[++i];
      out += String.fromCharCode(((first & 0x1f) << 6) | (second & 0x3f));
    } else if ((first & 0xf0) === 0xe0 && i + 2 < bytes.length) {
      const second = bytes[++i];
      const third = bytes[++i];
      out += String.fromCharCode(
        ((first & 0x0f) << 12) | ((second & 0x3f) << 6) | (third & 0x3f),
      );
    } else if ((first & 0xf8) === 0xf0 && i + 3 < bytes.length) {
      const second = bytes[++i];
      const third = bytes[++i];
      const fourth = bytes[++i];
      const codePoint =
        ((first & 0x07) << 18) |
        ((second & 0x3f) << 12) |
        ((third & 0x3f) << 6) |
        (fourth & 0x3f);
      const offset = codePoint - 0x10000;
      out += String.fromCharCode(0xd800 + (offset >> 10), 0xdc00 + (offset & 0x3ff));
    }
  }
  return out;
}

class TextEncoder {
  get encoding() {
    return "utf-8";
  }
  encode(input) {
    return encodeUtf8(input);
  }
  encodeInto(input, typed_array) {
    return text_encode_into(input, typed_array);
  }
}
class TextDecoder {
  #label;
  #opts;
  #pending;
  constructor(label = "utf-8", opts = {}) {
    this.#label = normalizeEncodingLabel(label);
    this.#opts = opts;
    this.#pending = new Uint8Array();
  }
  get encoding() {
    return this.#label;
  }
  get fatal() {
    return this.#opts.fatal ?? false;
  }
  get ignoreBOM() {
    return this.#opts.ignoreBOM ?? false;
  }
  decode(input, opts = {}) {
    if (this.#label === "utf-8") {
      return decodeUtf8(input);
    }
    let bytes = bytesFromInput(input);
    if (this.#pending.length > 0) {
      const joined = new Uint8Array(this.#pending.length + bytes.length);
      joined.set(this.#pending);
      joined.set(bytes, this.#pending.length);
      bytes = joined;
      this.#pending = new Uint8Array();
    }
    if (opts.stream === true && bytes.length > 0) {
      // Count consecutive high bytes (>= 0x80) from the end of the buffer.
      // For GBK-family encodings each character is 2 bytes (both >= 0x80),
      // so an odd count means the last byte is an incomplete lead byte.
      let tailHigh = 0;
      for (let i = bytes.length - 1; i >= 0 && bytes[i] >= 0x80; i--) tailHigh++;
      if (tailHigh % 2 === 1) {
        this.#pending = bytes.slice(bytes.length - 1);
        bytes = bytes.slice(0, bytes.length - 1);
      }
    }
    if (bytes.length === 0) {
      return "";
    }
    try {
      return decode_text(this.#label, bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
    } catch (err) {
      if (this.fatal) {
        throw err;
      }
      return replacement;
    }
  }
}

// Credit: https://github.com/GoogleChromeLabs/text-encode-transform-polyfill

const codec = Symbol("codec");
const transform = Symbol("transform");

class TextEncoderStream {
  constructor() {
    this[codec] = new TextEncoder();
    this[transform] = new TransformStream(
      new TextEncodeTransformer(this[codec]),
    );
  }
  get readable() {
    return this[transform].readable;
  }
  get writable() {
    return this[transform].writable;
  }
}

class TextDecoderStream {
  constructor(encoding, opts) {
    this[codec] = new TextDecoder(encoding, opts);
    this[transform] = new TransformStream(
      new TextDecodeTransformer(this[codec]),
    );
  }
  get readable() {
    return this[transform].readable;
  }
  get writable() {
    return this[transform].writable;
  }
}

class TextEncodeTransformer {
  #encoder;
  #carry;
  constructor() {
    this.#encoder = new TextEncoder();
    this.#carry = void 0;
  }

  transform(chunk, ctrl) {
    chunk = String(chunk);
    if (this.#carry !== void 0) {
      chunk = this.#carry + chunk;
      this.#carry = void 0;
    }
    const term = chunk.charCodeAt(chunk.length - 1);
    if (term >= 0xD800 && term < 0xDC00) {
      this.#carry = chunk.substring(chunk.length - 1);
      chunk = chunk.substring(0, chunk.length - 1);
    }
    const enc = this.#encoder.encode(chunk);
    if (enc.length > 0) ctrl.enqueue(enc);
  }

  flush(ctrl) {
    if (this.#carry !== void 0) {
      ctrl.enqueue(this.#encoder.encode(this.#carry));
      this.#carry = void 0;
    }
  }
}

class TextDecodeTransformer {
  #decoder;
  constructor(decoder = {}) {
    this.#decoder = new TextDecoder(decoder.encoding, {
      fatal: decoder.fatal,
      ignoreBOM: decoder.ignoreBOM,
    });
  }

  transform(chunk, ctrl) {
    const dec = this.#decoder.decode(chunk, { stream: true });
    if (dec != "") ctrl.enqueue(dec);
  }

  flush(ctrl) {
    const out = this.#decoder.decode();
    if (out !== "") ctrl.enqueue(out);
  }
}

globalThis.TextEncoder = TextEncoder;
globalThis.TextDecoder = TextDecoder;
globalThis.TextEncoderStream = TextEncoderStream;
globalThis.TextDecoderStream = TextDecoderStream;
