const base = process.argv[1];

function findDoubleNewlineIndex(buffer) {
  for (let i = 0; i < buffer.length - 1; i++) {
    if (buffer[i] === 10 && buffer[i + 1] === 10) {
      return i + 2;
    }
    if (
      i < buffer.length - 3 &&
      buffer[i] === 13 &&
      buffer[i + 1] === 10 &&
      buffer[i + 2] === 13 &&
      buffer[i + 3] === 10
    ) {
      return i + 4;
    }
  }
  return -1;
}

async function readSseChunks(body) {
  const chunks = [];
  let data = new Uint8Array();
  for await (const chunk of body) {
    const binaryChunk =
      chunk instanceof ArrayBuffer
        ? new Uint8Array(chunk)
        : typeof chunk === "string"
          ? new TextEncoder().encode(chunk)
          : chunk;
    const next = new Uint8Array(data.length + binaryChunk.length);
    next.set(data);
    next.set(binaryChunk, data.length);
    data = next;
    let index;
    while ((index = findDoubleNewlineIndex(data)) !== -1) {
      chunks.push(new TextDecoder().decode(data.slice(0, index)));
      data = data.slice(index);
    }
  }
  if (data.length > 0) {
    chunks.push(new TextDecoder().decode(data));
  }
  return chunks;
}

const cloned = structuredClone({
  ok: true,
  nested: { value: 42 },
  list: ["a", "b"],
});
cloned.nested.value = 7;

const bytes = new TextEncoder().encode("abc\n\nxyz");
const typedArraySubarray = [
  new TextDecoder().decode(bytes.subarray(0, 3)),
  new TextDecoder().decode(bytes.subarray(5)),
].join("|");
const typedArrayLiteralSubarray = Array.from(
  new Uint8Array([97, 98, 99, 10, 10, 120, 121, 122]).subarray(0, 3),
).join(",");
const textEncoderUtf8 = Array.from(new TextEncoder().encode("abc")).join(",");

const headers = new Headers({
  authorization: "Bearer test-key",
  "content-type": "application/json",
});
const headerEntries = Array.from(headers.entries())
  .map(([key, value]) => `${key}:${value}`)
  .join(",");

const response = await fetch(`${base}/v1/chat/completions`, {
  method: "POST",
  headers,
  body: JSON.stringify({
    model: "mock-chat",
    messages: [{ role: "user", content: "hello" }],
    stream: true,
  }),
});

const sseChunks = await readSseChunks(response.body);
const events = sseChunks
  .flatMap((chunk) => chunk.split(/\r?\n/))
  .filter((line) => line.startsWith("data: "))
  .map((line) => line.slice(6));

globalThis.__host_fetch_openai_compat_result = [
  typeof structuredClone,
  String(cloned.nested.value),
  typedArraySubarray,
  typedArrayLiteralSubarray,
  textEncoderUtf8,
  headerEntries,
  String(response.status),
  String(response.body && typeof response.body[Symbol.asyncIterator]),
  events.join("|"),
].join("\n");
