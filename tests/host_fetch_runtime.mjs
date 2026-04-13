const base = process.argv[1];

const req = new Request(`${base}/echo?via=request`, {
  method: "POST",
  headers: new Headers({
    "content-type": "text/plain",
    "x-client": "vjsx",
  }),
  body: "ping",
});

const res = await fetch(req);
const body = await res.text();
const jsonRes = Response.json({ ok: true });

globalThis.__host_fetch_result = [
  typeof fetch,
  typeof Request,
  typeof Response,
  typeof Headers,
  String(res.status),
  String(res.ok),
  String(res.headers.get("x-echo-method")),
  String(res.headers.get("x-echo-query")),
  String(res.headers.get("x-echo-client")),
  body,
  String(jsonRes.headers.get("content-type")),
  await jsonRes.text(),
].join("\n");
