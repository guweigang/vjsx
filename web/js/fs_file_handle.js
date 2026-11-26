(native) => (fd) => ({
  async close() { native.close(fd); },
  async stat() { return native.stat(fd); },
  async sync() { native.sync(fd); },
  async truncate(length = 0) {
    if (!Number.isSafeInteger(length) || length < 0) throw new RangeError("invalid file length");
    native.truncate(fd, length);
  },
  async read(buffer, offset = 0, length, position = null) {
    if (!(buffer instanceof Uint8Array)) throw new TypeError("buffer must be a Uint8Array");
    length ??= buffer.byteLength - offset;
    if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(length) ||
        length < 0 || offset > buffer.byteLength || length > buffer.byteLength - offset ||
        length > 2147483647 ||
        (position !== null && (!Number.isSafeInteger(position) || position < 0))) {
      throw new RangeError("invalid file read range");
    }
    return { bytesRead: native.read(fd, buffer, offset, length, position ?? -1), buffer };
  },
})
