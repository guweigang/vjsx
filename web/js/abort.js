const abort_reason = (reason) => {
  if (reason === void 0) {
    return new Error("This operation was aborted");
  }
  return reason;
};

class AbortSignal extends EventTarget {
  #aborted = false;
  #reason = void 0;
  onabort = null;

  constructor() {
    super();
  }

  get aborted() {
    return this.#aborted;
  }

  get reason() {
    return this.#reason;
  }

  throwIfAborted() {
    if (this.#aborted) {
      throw this.#reason;
    }
  }

  __abort(reason) {
    if (this.#aborted) {
      return;
    }
    this.#aborted = true;
    this.#reason = reason;
    const event = new Event("abort");
    this.dispatchEvent(event);
    if (typeof this.onabort === "function") {
      this.onabort.call(this, event);
    }
  }

  static abort(reason) {
    const signal = new AbortSignal();
    signal.__abort(abort_reason(reason));
    return signal;
  }

  static timeout(ms) {
    if (typeof setTimeout !== "function") {
      throw new TypeError("AbortSignal.timeout requires setTimeout");
    }
    const controller = new AbortController();
    setTimeout(() => {
      controller.abort(new Error("The operation timed out"));
    }, ms);
    return controller.signal;
  }

  static any(signals) {
    const controller = new AbortController();
    const cleanups = [];
    const abort = (signal) => {
      for (const cleanup of cleanups) {
        cleanup();
      }
      controller.abort(signal.reason);
    };
    for (const signal of signals) {
      if (signal.aborted) {
        abort(signal);
        return controller.signal;
      }
      const listener = () => abort(signal);
      signal.addEventListener("abort", listener, { once: true });
      cleanups.push(() => signal.removeEventListener("abort", listener));
    }
    return controller.signal;
  }
}

class AbortController {
  #signal = new AbortSignal();

  get signal() {
    return this.#signal;
  }

  abort(reason) {
    this.#signal.__abort(abort_reason(reason));
  }
}

globalThis.AbortSignal = AbortSignal;
globalThis.AbortController = AbortController;
