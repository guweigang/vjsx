import fs from "node:fs";
import { readFile, rm, writeFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { deflateRawSync } from "node:zlib";

const asyncPath = ".host_binary_compat_async.bin";
const syncPath = ".host_binary_compat_sync.bin";

try {
  const input = Buffer.from("abcdefghijklmnopqrstuvwxyz0123456789".repeat(200));
  const compressed = deflateRawSync(input, { level: 9 });
  console.log(String(Buffer.isBuffer(compressed)));
  try {
    deflateRawSync(input, { level: 0 });
    console.log("unsupported-level-accepted");
  } catch (error) {
    console.log(error.name);
  }

  const short = Buffer.alloc(1);
  try {
    short.writeUInt32LE(1);
    console.log("missing-range-error");
  } catch (error) {
    console.log(error.name);
  }

  await writeFile(asyncPath, Uint8Array.from([0, 255, 1, 128]), { flag: "wx", mode: 0o600 });
  console.log(Array.from(await readFile(asyncPath)).join(","));
  console.log(await readFile(asyncPath, { encoding: "utf8" }).then((value) => typeof value));

  try {
    await writeFile(asyncPath, "overwrite", { flag: "wx+" });
    console.log("exclusive-overwrite");
  } catch (error) {
    console.log("exclusive-rejected");
  }

  try {
    await writeFile(asyncPath, "append", { flag: "ax" });
    console.log("unsupported-accepted");
  } catch (error) {
    console.log(error.name);
  }

  fs.writeFileSync(syncPath, Uint8Array.from([2, 254, 3, 129]), { flag: "wx", mode: 0o600 });
  const syncBytes = fs.readFileSync(syncPath);
  console.log(String(Buffer.isBuffer(syncBytes)) + ":" + Array.from(syncBytes).join(","));

  const uuid = randomUUID();
  console.log(String(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(uuid)));
} finally {
  await rm(asyncPath).catch(() => {});
  await rm(syncPath).catch(() => {});
}
