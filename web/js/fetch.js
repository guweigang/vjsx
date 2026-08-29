import { Request } from "./fetch/request.js";
import { Response } from "./fetch/response.js";
import { Headers } from "./fetch/headers.js";

const { core_fetch } = globalThis.__bootstrap;

function abortError(reason) {
  if (reason !== void 0) {
    return reason;
  }
  const err = new Error("This operation was aborted");
  err.name = "AbortError";
  return err;
}

function validateSignal(signal) {
  if (signal == null) {
    return null;
  }
  if (typeof signal !== "object" || typeof signal.aborted !== "boolean") {
    throw new TypeError("fetch signal must be an AbortSignal.");
  }
  return signal;
}

async function fetch(input, opts = {}) {
  const req = new Request(input, opts);
  const signal = validateSignal(req.signal);
  if (signal?.aborted) {
    throw abortError(signal.reason);
  }
  const url = req.url;
  let aborted = false;
  let cancelCoreFetch = () => false;
  let cleanupAbort = () => {};
  const abortPromise = signal == null
    ? null
    : new Promise((_, reject) => {
      const onAbort = () => {
        aborted = true;
        cancelCoreFetch();
        reject(abortError(signal.reason));
      };
      signal.addEventListener("abort", onAbort, { once: true });
      cleanupAbort = () => signal.removeEventListener("abort", onAbort);
    });
  const requestPromise = (async () => {
    const boundary = typeof FormData !== "undefined" && opts.body instanceof FormData
      ? Math.random().toString()
      : void 0;
    const body = opts.body == null
      ? ""
      : typeof opts.body === "string"
        ? opts.body
        : opts.body instanceof ArrayBuffer || ArrayBuffer.isView(opts.body)
          ? opts.body
          : await req.text(boundary);
    if (aborted || signal?.aborted) {
      throw abortError(signal?.reason);
    }
    const res = await new Promise((resolve, reject) => {
      const cancel = core_fetch(url, {
        method: req.method,
        headers: req.headers.toJSON(),
        body: body,
        boundary: boundary,
      }, resolve, reject);
      if (typeof cancel === "function") {
        cancelCoreFetch = cancel;
      }
    });
    if (aborted || signal?.aborted) {
      throw abortError(signal?.reason);
    }
    const resInit = {};
    resInit.status = res.status;
    resInit.statusText = res.status_message;
    resInit.headers = res.header;
    resInit.url = url;
    return new Response(res.body, resInit);
  })();
  try {
    return await (abortPromise == null
      ? requestPromise
      : Promise.race([requestPromise, abortPromise]));
  } finally {
    cleanupAbort();
  }
}

globalThis.Headers = Headers;
globalThis.Request = Request;
globalThis.Response = Response;
globalThis.fetch = fetch;
