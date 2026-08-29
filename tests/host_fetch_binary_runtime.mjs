const response = await fetch(`${process.argv[1]}/echo`, {
  method: "PUT",
  headers: { "content-type": "application/octet-stream" },
  body: Uint8Array.from([0, 255, 1, 128]),
});
globalThis.__host_fetch_binary_result = Array.from(
  new Uint8Array(await response.arrayBuffer()),
).join(",");
