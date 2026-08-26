export function contractSnapshot() {
  const encoded = Array.from(new TextEncoder().encode("vjsx-世界"));
  const url = new URL("../next?q=hello world#frag ment", "https://example.test/a/b/");
  const controller = new AbortController();
  controller.abort("done");
  return JSON.stringify({
    array: [1, 2, 3, 4].filter((value) => value % 2 === 0).map((value) => value * 10),
    base64: atob(btoa("runtime-contract")),
    encoded,
    object: Object.entries({ z: 1, a: 2 }).sort(([left], [right]) => left.localeCompare(right)),
    url: {
      href: url.href,
      origin: url.origin,
      pathname: url.pathname,
      search: url.search,
      hash: url.hash,
    },
    aborted: controller.signal.aborted,
    reason: controller.signal.reason,
  });
}
