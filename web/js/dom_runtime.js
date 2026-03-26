if (!globalThis.__vjs_dom_runtime_bootstrap) {
  globalThis.__vjs_dom_runtime_bootstrap = function (DOMParserCtor) {
    if (typeof DOMParserCtor !== "function") return;
    if (DOMParserCtor.prototype && DOMParserCtor.prototype.__vjs_dom_runtime_patched) return;
    if (DOMParserCtor.prototype) {
      Object.defineProperty(DOMParserCtor.prototype, "__vjs_dom_runtime_patched", {
        value: true,
        configurable: true,
      });
    }

    globalThis.DOMParser = globalThis.DOMParser || DOMParserCtor;

    globalThis.__vjs_split_selector_chunks = globalThis.__vjs_split_selector_chunks || function (selector) {
      if (typeof selector !== "string" || selector.indexOf(",") === -1) return [selector];
      const parts = [];
      let current = "";
      let roundDepth = 0;
      let squareDepth = 0;
      let quote = "";
      for (let i = 0; i < selector.length; i++) {
        const ch = selector[i];
        if (quote) {
          current += ch;
          if (ch === quote && selector[i - 1] !== "\\") quote = "";
          continue;
        }
        if (ch === '"' || ch === "'") {
          quote = ch;
          current += ch;
          continue;
        }
        if (ch === "(") roundDepth++;
        else if (ch === ")" && roundDepth > 0) roundDepth--;
        else if (ch === "[") squareDepth++;
        else if (ch === "]" && squareDepth > 0) squareDepth--;
        if (ch === "," && roundDepth === 0 && squareDepth === 0) {
          if (current.trim()) parts.push(current.trim());
          current = "";
          continue;
        }
        current += ch;
      }
      if (current.trim()) parts.push(current.trim());
      return parts.length > 0 ? parts : [selector];
    };

    globalThis.__vjs_patch_dom_document = globalThis.__vjs_patch_dom_document || function (doc) {
      if (!doc || typeof doc !== "object") return doc;

      const split = globalThis.__vjs_split_selector_chunks;
      const mergeResults = (items) => {
        const out = [];
        const seen = new Set();
        for (const item of items) {
          if (!item || seen.has(item)) continue;
          seen.add(item);
          out.push(item);
        }
        return out;
      };

      const patchProto = (proto, isElementProto) => {
        if (!proto || proto.__vjs_selector_chunk_patch) return;
        Object.defineProperty(proto, "__vjs_selector_chunk_patch", {
          value: true,
          configurable: true,
        });

        if (typeof proto.querySelectorAll === "function") {
          const original = proto.querySelectorAll;
          proto.querySelectorAll = function (selector) {
            if (typeof selector !== "string" || selector.indexOf(",") === -1) {
              return original.call(this, selector);
            }
            const chunks = split(selector);
            if (chunks.length <= 1) return original.call(this, selector);
            return mergeResults(chunks.flatMap((chunk) => Array.from(original.call(this, chunk) || [])));
          };
        }

        if (typeof proto.querySelector === "function") {
          const original = proto.querySelector;
          proto.querySelector = function (selector) {
            if (typeof selector !== "string" || selector.indexOf(",") === -1) {
              return original.call(this, selector);
            }
            const chunks = split(selector);
            if (chunks.length <= 1) return original.call(this, selector);
            for (const chunk of chunks) {
              const found = original.call(this, chunk);
              if (found) return found;
            }
            return null;
          };
        }

        if (isElementProto && typeof proto.matches === "function") {
          const original = proto.matches;
          proto.matches = function (selector) {
            if (typeof selector !== "string" || selector.indexOf(",") === -1) {
              return original.call(this, selector);
            }
            const chunks = split(selector);
            if (chunks.length <= 1) return original.call(this, selector);
            return chunks.some((chunk) => original.call(this, chunk));
          };
        }

        if (isElementProto && typeof proto.closest === "function") {
          const original = proto.closest;
          proto.closest = function (selector) {
            if (typeof selector !== "string" || selector.indexOf(",") === -1) {
              return original.call(this, selector);
            }
            const chunks = split(selector);
            if (chunks.length <= 1) return original.call(this, selector);
            for (const chunk of chunks) {
              const found = original.call(this, chunk);
              if (found) return found;
            }
            return null;
          };
        }
      };

      patchProto(Object.getPrototypeOf(doc), false);
      const rootEl = doc.documentElement || doc.body || null;
      if (rootEl) patchProto(Object.getPrototypeOf(rootEl), true);

      const view = doc.defaultView || null;
      if (view && typeof view.getComputedStyle !== "function") {
        view.getComputedStyle = function () {
          return {
            display: "block",
            visibility: "visible",
            opacity: "1",
            getPropertyValue: function () {
              return "";
            },
          };
        };
      }
      if (view && typeof view.DOMParser !== "function") view.DOMParser = DOMParserCtor;
      if (view && typeof globalThis.window === "undefined") globalThis.window = view;
      if (typeof globalThis.self === "undefined" && typeof globalThis.window !== "undefined") {
        globalThis.self = globalThis.window;
      }
      if (typeof globalThis.DOMParser !== "function") globalThis.DOMParser = DOMParserCtor;

      if (!doc.implementation) doc.implementation = {};
      if (typeof doc.implementation.createHTMLDocument !== "function") {
        doc.implementation.createHTMLDocument = function (html) {
          const holder = {
            __vjs_buffer: html || "<!doctype html><html><body></body></html>",
            __vjs_doc: null,
            __vjs_sync() {
              this.__vjs_doc = globalThis.__vjs_patch_dom_document(
                (new DOMParserCtor()).parseFromString(
                  this.__vjs_buffer || "<!doctype html><html><body></body></html>",
                  "text/html",
                ),
              );
              return this.__vjs_doc;
            },
            open() {
              this.__vjs_buffer = "";
              return this;
            },
            write(chunk) {
              this.__vjs_buffer += String(chunk || "");
            },
            close() {
              this.__vjs_sync();
              return this;
            },
            getElementById(id) {
              return (this.__vjs_doc || this.__vjs_sync()).getElementById(id);
            },
            querySelector(selector) {
              return (this.__vjs_doc || this.__vjs_sync()).querySelector(selector);
            },
            querySelectorAll(selector) {
              return (this.__vjs_doc || this.__vjs_sync()).querySelectorAll(selector);
            },
          };
          Object.defineProperty(holder, "body", {
            get() {
              return (this.__vjs_doc || this.__vjs_sync()).body;
            },
          });
          Object.defineProperty(holder, "documentElement", {
            get() {
              return (this.__vjs_doc || this.__vjs_sync()).documentElement;
            },
          });
          Object.defineProperty(holder, "defaultView", {
            get() {
              return (this.__vjs_doc || this.__vjs_sync()).defaultView;
            },
          });
          holder.__vjs_sync();
          return holder;
        };
      }

      return doc;
    };

    if (typeof globalThis.document === "undefined") {
      const bootDocument = globalThis.__vjs_patch_dom_document(
        (new DOMParserCtor()).parseFromString(
          "<!doctype html><html><body></body></html>",
          "text/html",
        ),
      );
      globalThis.document = bootDocument;
      if (typeof globalThis.window === "undefined" && bootDocument && bootDocument.defaultView) {
        globalThis.window = bootDocument.defaultView;
      }
      if (typeof globalThis.self === "undefined" && typeof globalThis.window !== "undefined") {
        globalThis.self = globalThis.window;
      }
    }

    const originalParseFromString = DOMParserCtor.prototype.parseFromString;
    DOMParserCtor.prototype.parseFromString = function (...args) {
      return globalThis.__vjs_patch_dom_document(originalParseFromString.apply(this, args));
    };
  };
}

if (typeof globalThis.DOMParser === "function") {
  globalThis.__vjs_dom_runtime_bootstrap(globalThis.DOMParser);
}
