function normalizeIndex(index, length, fallback) {
  const value = index == null ? fallback : Number(index);
  if (!Number.isFinite(value)) {
    return fallback;
  }
  const integer = Math.trunc(value);
  return integer < 0 ? Math.max(length + integer, 0) : Math.min(integer, length);
}

function fixedSubarray(start, end) {
  const length = this.length;
  const from = normalizeIndex(start, length, 0);
  const to = normalizeIndex(end, length, length);
  return this.slice(from, Math.max(from, to));
}

function installOwnSubarray(view) {
  if (!view || typeof view.slice !== "function") {
    return view;
  }
  Object.defineProperty(view, "subarray", {
    configurable: true,
    writable: true,
    value: fixedSubarray,
  });
  return view;
}

function patchTypedArraySubarray(TypedArrayCtor) {
  if (typeof TypedArrayCtor !== "function") {
    return;
  }
  const proto = TypedArrayCtor.prototype;
  if (!proto || typeof proto.slice !== "function") {
    return;
  }
  try {
    const sample = new TypedArrayCtor([1, 2, 3]);
    if (sample.subarray(1, 2).length === 1 && sample.subarray(1, 2)[0] === 2) {
      return;
    }
  } catch {
    return;
  }
  Object.defineProperty(proto, "subarray", {
    configurable: true,
    writable: true,
    value: fixedSubarray,
  });
}

function patchTypedArrayConstructor(name) {
  const TypedArrayCtor = globalThis[name];
  if (typeof TypedArrayCtor !== "function") {
    return;
  }
  patchTypedArraySubarray(TypedArrayCtor);
  globalThis[name] = new Proxy(TypedArrayCtor, {
    apply(target, thisArg, args) {
      return installOwnSubarray(Reflect.apply(target, thisArg, args));
    },
    construct(target, args, newTarget) {
      return installOwnSubarray(Reflect.construct(target, args, newTarget));
    },
  });
}

[
  "Int8Array",
  "Uint8Array",
  "Uint8ClampedArray",
  "Int16Array",
  "Uint16Array",
  "Int32Array",
  "Uint32Array",
  "Float32Array",
  "Float64Array",
  "BigInt64Array",
  "BigUint64Array",
].forEach(patchTypedArrayConstructor);
