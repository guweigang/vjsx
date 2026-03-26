globalThis.Buffer = globalThis.Buffer || {
  from(input, encoding) {
    const text = String(input ?? "");
    if (encoding === "base64") {
      const binary = typeof atob === "function" ? atob(text) : text;
      return {
        __vjs_buffer: true,
        length: binary.length,
        toString(outputEncoding) {
          if (
            outputEncoding == null || outputEncoding === "binary" ||
            outputEncoding === "latin1" || outputEncoding === "utf8" ||
            outputEncoding === "utf-8"
          ) {
            return binary;
          }
          throw new Error("Unsupported Buffer encoding: " + outputEncoding);
        },
      };
    }
    return {
      __vjs_buffer: true,
      length: text.length,
      toString(outputEncoding) {
        if (
          outputEncoding == null || outputEncoding === "utf8" ||
          outputEncoding === "utf-8" || outputEncoding === "binary" ||
          outputEncoding === "latin1"
        ) {
          return text;
        }
        throw new Error("Unsupported Buffer encoding: " + outputEncoding);
      },
    };
  },
  alloc(size, fill) {
    const ch = typeof fill === "string" && fill.length > 0 ? fill[0] : "\0";
    return this.from(ch.repeat(Math.max(0, Number(size) || 0)), "binary");
  },
  allocUnsafe(size) {
    return this.alloc(size);
  },
  allocUnsafeSlow(size) {
    return this.alloc(size);
  },
  isBuffer(value) {
    return !!(value && value.__vjs_buffer);
  },
  byteLength(value) {
    return String(value ?? "").length;
  },
};
