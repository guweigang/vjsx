/* Credit: All VJS Author */
import { vjs_inspect } from "./util.js";
// Credit URLSearchParams => https://github.com/jerrybendy/url-search-params-polyfill/blob/master/index.js
function decode(str) {
  return str.replace(/\+/g, " ").replace(/(?:%[a-f0-9]{2})+/ig, match => {
    const bytes = match.match(/%../g).map(byte => parseInt(byte.slice(1), 16));
    let result = "";
    for (let i = 0; i < bytes.length;) {
      const first = bytes[i++];
      if (first < 0x80) { result += String.fromCharCode(first); continue; }
      const count = first >= 0xc2 && first <= 0xdf ? 1
        : first >= 0xe0 && first <= 0xef ? 2
        : first >= 0xf0 && first <= 0xf4 ? 3 : 0;
      if (!count) { result += "\uFFFD"; continue; }
      let point = first & (0x7f >> count);
      let consumed = 0;
      while (consumed < count && i < bytes.length) {
        const byte = bytes[i];
        const lower = consumed === 0 && first === 0xe0 ? 0xa0
          : consumed === 0 && first === 0xf0 ? 0x90 : 0x80;
        const upper = consumed === 0 && first === 0xed ? 0x9f
          : consumed === 0 && first === 0xf4 ? 0x8f : 0xbf;
        if (byte < lower || byte > upper) break;
        point = (point << 6) | (byte & 0x3f);
        consumed++; i++;
      }
      result += consumed === count ? String.fromCodePoint(point) : "\uFFFD";
    }
    return result;
  });
}
function parse(search) {
  if (search instanceof URLSearchParams) return [...search];
  if (search !== null && typeof search === "object") {
    if (typeof search[Symbol.iterator] === "function") {
      return Array.from(search, item => {
        const pair = Array.from(item);
        if (pair.length !== 2) throw new TypeError("Expected a name/value pair");
        return pair.map(String);
      });
    }
    return Object.keys(search).map(key => [key, String(search[key])]);
  }
  return String(search).replace(/^\?/, "").split("&").filter(Boolean).map(pair => {
    const index = pair.indexOf("=");
    return index < 0 ? [decode(pair), ""]
      : [decode(pair.slice(0, index)), decode(pair.slice(index + 1))];
  });
}
const parameterLists = new WeakMap();
const parameterUpdates = new WeakMap();
function updateURL(params) {
  const update = parameterUpdates.get(params);
  if (update) update(params.toString());
}
function encode(str) {
  const replace = {
    "!": "%21",
    "'": "%27",
    "(": "%28",
    ")": "%29",
    "~": "%7E",
    "%20": "+",
  };
  return encodeURIComponent(str).replace(
    /[!'\(\)~]|%20/g,
    function (match) {
      return replace[match];
    },
  );
}
class URLSearchParams {
  constructor(search = "") {
    parameterLists.set(this, parse(search));
  }
  append(name, value) {
    parameterLists.get(this).push([String(name), String(value)]);
    updateURL(this);
  }
  set(name, value) {
    name = String(name); value = String(value);
    const pairs = parameterLists.get(this);
    const index = pairs.findIndex(pair => pair[0] === name);
    if (index < 0) pairs.push([name, value]);
    else {
      pairs[index][1] = value;
      parameterLists.set(this, pairs.filter((pair, i) => pair[0] !== name || i === index));
    }
    updateURL(this);
  }
  has(name, value) {
    name = String(name);
    if (value !== undefined) value = String(value);
    return parameterLists.get(this).some(pair => pair[0] === name &&
      (value === undefined || pair[1] === value));
  }
  get(name) {
    const pair = parameterLists.get(this).find(pair => pair[0] === String(name));
    return pair ? pair[1] : null;
  }
  getAll(name) {
    name = String(name);
    return parameterLists.get(this).filter(pair => pair[0] === name).map(pair => pair[1]);
  }
  delete(name, value) {
    name = String(name);
    if (value !== undefined) value = String(value);
    parameterLists.set(this, parameterLists.get(this).filter(pair =>
      pair[0] !== name || (value !== undefined && pair[1] !== value)));
    updateURL(this);
  }
  sort() {
    parameterLists.get(this).sort((a, b) => a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0);
    updateURL(this);
  }
  toString() {
    return parameterLists.get(this).map(pair => encode(pair[0]) + "=" + encode(pair[1])).join("&");
  }
  get size() { return parameterLists.get(this).length; }
  forEach(callback, thisArg) {
    for (let i = 0; i < parameterLists.get(this).length; i++) {
      const [name, value] = parameterLists.get(this)[i];
      callback.call(thisArg, value, name, this);
    }
  }
  *entries() {
    for (let i = 0; i < parameterLists.get(this).length; i++) {
      yield parameterLists.get(this)[i].slice();
    }
  }
  *keys() { for (const [name] of this) yield name; }
  *values() { for (const [, value] of this) yield value; }
  [Symbol.iterator]() { return this.entries(); }
  [vjs_inspect](format) { return "URLSearchParams " + format([...this]); }
}
URLSearchParams.prototype[Symbol.toStringTag] = "URLSearchParams";
globalThis.URLSearchParams = URLSearchParams;

// Preserve existing percent escapes while encoding spaces and non-ASCII input.
function encodeURLPart(value) {
  return encodeURI(value).replace(/%25/g, "%");
}

const iof8 = (a, b = "/") => a.indexOf(b, 8);

function normalizeURLPath(pathname) {
  const absolute = pathname.startsWith("/");
  const trailingSlash = pathname.endsWith("/");
  const output = [];
  for (const segment of pathname.split("/")) {
    if (segment === "" || segment === ".") continue;
    if (segment === "..") {
      output.pop();
    } else {
      output.push(segment);
    }
  }
  let normalized = `${absolute ? "/" : ""}${output.join("/")}`;
  if (trailingSlash && normalized !== "/") normalized += "/";
  return normalized || (absolute ? "/" : "");
}

function splitURLSuffix(value) {
  const hashIndex = value.indexOf("#");
  const hash = hashIndex === -1 ? "" : value.slice(hashIndex);
  const withoutHash = hashIndex === -1 ? value : value.slice(0, hashIndex);
  const queryIndex = withoutHash.indexOf("?");
  return {
    pathname: queryIndex === -1 ? withoutHash : withoutHash.slice(0, queryIndex),
    search: queryIndex === -1 ? "" : withoutHash.slice(queryIndex),
    hash,
  };
}

function normalizeAbsoluteURL(value) {
  const match = String(value).match(/^([a-zA-Z][a-zA-Z0-9+.-]*:\/\/[^/?#]*)(.*)$/);
  if (!match) throw new TypeError(`Invalid URL ${value}`);
  const suffix = splitURLSuffix(match[2] || "/");
  const pathname = encodeURLPart(normalizeURLPath(suffix.pathname || "/"));
  const search = suffix.search ? `?${encodeURLPart(suffix.search.slice(1))}` : "";
  const hash = suffix.hash ? `#${encodeURLPart(suffix.hash.slice(1))}` : "";
  return `${match[1]}${pathname}${search}${hash}`;
}

function resolveURLInput(input, base) {
  input = String(input);
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(input)) {
    return normalizeAbsoluteURL(input);
  }
  if (!base) throw new TypeError(`Invalid URL ${input}`);
  const normalizedBase = normalizeAbsoluteURL(base);
  const baseMatch = normalizedBase.match(/^([a-zA-Z][a-zA-Z0-9+.-]*:)(\/\/[^/?#]*)(.*)$/);
  if (!baseMatch) throw new TypeError(`Invalid base URL ${base}`);
  if (input.startsWith("//")) return normalizeAbsoluteURL(baseMatch[1] + input);
  const baseSuffix = splitURLSuffix(baseMatch[3]);
  if (input.startsWith("?")) {
    return normalizeAbsoluteURL(`${baseMatch[1]}${baseMatch[2]}${baseSuffix.pathname}${input}`);
  }
  if (input.startsWith("#")) {
    return normalizeAbsoluteURL(
      `${baseMatch[1]}${baseMatch[2]}${baseSuffix.pathname}${baseSuffix.search}${input}`,
    );
  }
  const suffix = splitURLSuffix(input);
  const pathname = suffix.pathname.startsWith("/")
    ? suffix.pathname
    : `${baseSuffix.pathname.slice(0, baseSuffix.pathname.lastIndexOf("/") + 1)}${suffix.pathname}`;
  return normalizeAbsoluteURL(
    `${baseMatch[1]}${baseMatch[2]}${pathname}${suffix.search}${suffix.hash}`,
  );
}

class URL {
  #pathname = void 0;
  #protocol = void 0;
  #host = void 0;
  #hostname = void 0;
  #port = void 0;
  #hash = void 0;
  #username = void 0;
  #password = void 0;
  #idx = -1;
  #href = "";
  #searchParams = new URLSearchParams();
  constructor(input, base) {
    if (base instanceof URL) {
      base = base.href;
    }
    if (input instanceof URL) {
      input = input.href;
    }
    this.href = resolveURLInput(input, base);
    parameterUpdates.set(this.#searchParams, query => {
      this.#replaceSearch(query ? "?" + query : "");
    });
  }
  get href() { return this.#href; }
  set href(value) {
    const href = resolveURLInput(value);
    const search = splitURLSuffix(href.slice(href.indexOf("://") + 3)).search;
    const pairs = parse(search);
    this.#href = href;
    this.#idx = search ? href.indexOf("?") : -1;
    parameterLists.set(this.#searchParams, pairs);
    this.#pathname = this.#protocol = this.#host = this.#hostname = undefined;
    this.#port = this.#hash = this.#username = this.#password = undefined;
  }
  get search() {
    return splitURLSuffix(this.#href.slice(this.#href.indexOf("://") + 3)).search.replace(/^\?$/, "");
  }
  set search(value) {
    value = String(value);
    const search = value ? "?" + encodeURLPart(value.replace(/^\?/, "")).replace(/#/g, "%23") : "";
    const pairs = parse(search);
    this.#replaceSearch(search);
    parameterLists.set(this.#searchParams, pairs);
  }
  #replaceSearch(search) {
    const hashIndex = this.#href.indexOf("#");
    const hash = hashIndex < 0 ? "" : this.#href.slice(hashIndex);
    const end = this.#idx >= 0 ? this.#idx : hashIndex >= 0 ? hashIndex : this.#href.length;
    this.#href = this.#href.slice(0, end) + search + hash;
    this.#idx = search ? end : -1;
  }
  static canParse(input, base) {
    try {
      new URL(input, base);
      return true;
    } catch {
      return false;
    }
  }
  static createObjectURL() {
    throw new Error("createObjectURL not implemented yet.");
  }
  static revokeObjectURL() {
    throw new Error("revokeObjectURL not implemented yet.");
  }
  get origin() {
    return this.href.slice(0, iof8(this.href));
  }
  get protocol() {
    return this.#protocol ?? this.href.match(/[^/:]*/)[0] + ":";
  }
  set protocol(val) {
    this.#protocol = val;
  }
  #oriHost() {
    return this.href.match(/:\/+(.*)/)[1].split("/")[0];
  }
  get host() {
    if (this.#host) return this.#host;
    const host = this.#oriHost();
    return host.includes("@") ? host.slice(host.indexOf("@") + 1) : host;
  }
  set host(val) {
    this.#host = val;
  }
  get username() {
    if (this.#username) return this.#username;
    const val = this.#oriHost();
    return val.includes("@")
      ? val.slice(0, val.indexOf("@")).split(":")[0] ?? ""
      : "";
  }
  set username(val) {
    this.#username = val;
  }
  get password() {
    if (this.#password) return this.#password;
    const val = this.#oriHost();
    return val.includes("@")
      ? val.slice(0, val.indexOf("@")).split(":")[1] ?? ""
      : "";
  }
  set password(val) {
    this.#password = val;
  }
  get hostname() {
    return this.#hostname ?? this.host.split(":")[0] ?? "";
  }
  set hostname(val) {
    this.#hostname = val;
  }
  get port() {
    return this.#port ?? this.host.split(":")[1] ?? "";
  }
  set port(val) {
    this.#port = val;
  }
  #oriPathname() {
    const idx = iof8(this.href);
    const hashIndex = iof8(this.href, "#");
    const end = this.#idx !== -1
      ? this.#idx
      : hashIndex !== -1
      ? hashIndex
      : undefined;
    return this.href.slice(idx, end);
  }
  get hash() {
    if (this.#hash) return this.#hash;
    const index = iof8(this.href, "#");
    return index === -1 ? "" : this.href.slice(index);
  }
  set hash(val) {
    this.#hash = val;
  }
  get pathname() {
    if (this.#pathname) return this.#pathname;
    const path = this.#oriPathname();
    if (path.includes("#")) {
      return path.slice(0, path.indexOf("#"));
    }
    return path;
  }
  set pathname(val) {
    this.#pathname = val;
  }
  get searchParams() {
    return this.#searchParams;
  }
  toString() {
    return this.href;
  }
  toJSON() {
    return this.href;
  }
  [vjs_inspect](format) {
    return "URL " + format({
      href: this.href,
      origin: this.origin,
      protocol: this.protocol,
      username: this.username,
      password: this.password,
      host: this.host,
      hostname: this.hostname,
      port: this.port,
      pathname: this.pathname,
      search: this.search,
      searchParams: this.searchParams,
      hash: this.hash,
    });
  }
}

globalThis.URL = URL;
