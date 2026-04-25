function abortError(signal) {
  const err = new Error("The operation was aborted");
  err.name = "AbortError";
  if (signal && "reason" in signal) {
    err.cause = signal.reason;
  }
  return err;
}

function normalizeDelay(delay) {
  const n = Number(delay ?? 1);
  if (!Number.isFinite(n) || n < 0) {
    return 0;
  }
  return Math.trunc(n);
}

function promiseSetTimeout(delay = 1, value = undefined, options = {}) {
  const signal = options && options.signal;
  return new Promise((resolve, reject) => {
    if (signal && signal.aborted) {
      reject(abortError(signal));
      return;
    }
    let settled = false;
    let timer = null;
    const cleanup = () => {
      if (signal && typeof signal.removeEventListener === "function") {
        signal.removeEventListener("abort", onAbort);
      }
    };
    const onAbort = () => {
      if (settled) {
        return;
      }
      settled = true;
      if (timer !== null) {
        clearTimeout(timer);
      }
      cleanup();
      reject(abortError(signal));
    };
    if (signal && typeof signal.addEventListener === "function") {
      signal.addEventListener("abort", onAbort, { once: true });
    }
    timer = setTimeout(() => {
      if (settled) {
        return;
      }
      settled = true;
      cleanup();
      resolve(value);
    }, normalizeDelay(delay));
  });
}

globalThis.__vjsxNodeTimersPromises = {
  setTimeout: promiseSetTimeout,
};
