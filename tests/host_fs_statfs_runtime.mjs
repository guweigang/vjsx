import fs, { statfs as bareStatfs } from "fs/promises";
import nodeFs, { statfs } from "node:fs/promises";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
async function rejects(operation, code) {
  try {
    await operation();
  } catch (error) {
    assert(error.code === code, "expected " + code + " but got " + error.code);
    return;
  }
  throw new Error("expected rejection with " + code);
}

assert(statfs === bareStatfs && statfs === fs.statfs && statfs === nodeFs.statfs, "statfs aliases differ");
const numeric = await statfs(".");
const exact = await statfs(".", { bigint: true });
for (const field of ["type", "bsize", "frsize", "blocks", "bfree", "bavail", "files", "ffree"]) {
  assert(Number.isInteger(numeric[field]) && typeof exact[field] === "bigint", "invalid " + field);
}
assert(numeric.bsize > 0 && numeric.frsize > 0 && numeric.blocks > 0, "invalid disk geometry");
assert(numeric.bsize === Number(exact.bsize), "different block sizes");
const onFile = await statfs("./tests/host_fs_statfs_runtime.mjs");
assert(onFile.bsize === numeric.bsize && onFile.type === numeric.type, "incorrect filesystem for file");

if (process.platform !== "win32") {
  await rejects(() => statfs("./tests/host_fs_statfs_runtime.mjs/missing"), "ENOTDIR");
}
await rejects(() => statfs("./tests/.missing-statfs-fixture"), "ENOENT");
await rejects(() => statfs(".\0extra"), "ERR_INVALID_ARG_VALUE");
await rejects(() => statfs(1), "ERR_INVALID_ARG_TYPE");
await rejects(() => statfs(".", { bigint: 1 }), "ERR_INVALID_ARG_TYPE");
console.log("statfs ok");
