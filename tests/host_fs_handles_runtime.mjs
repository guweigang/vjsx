import fs, { constants } from "node:fs";
import bareFs from "fs";
import {
  access, appendFile, constants as promiseConstants, mkdtemp, open, opendir, readdir, readFile, realpath, rm,
} from "node:fs/promises";
import { constants as osConstants, tmpdir } from "node:os";
import { join, win32 } from "node:path";

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

assert(constants === fs.constants && constants === bareFs.constants && constants === promiseConstants, "constants aliases differ");
assert(constants.F_OK === 0 && Number.isInteger(osConstants.signals.SIGTERM), "missing native constants");
assert(win32.join("C:\\root", "sub", "..", "file") === "C:\\root\\file", "invalid drive join");
assert(win32.normalize("\\\\server\\share\\dir\\..") === "\\\\server\\share\\", "invalid UNC normalization");

const root = await mkdtemp(join(tmpdir(), "vjsx-fs-handles-"));
const path = join(root, "sample");
try {
  await rejects(() => access(path, constants.F_OK), "ENOENT");
  await appendFile(path, "a\0b");
  await appendFile(path, new Uint8Array([99]));
  await access(path, constants.F_OK);
  assert(typeof await realpath(path) === "string", "realpath did not resolve");
  const handle = await open(path, "r+");
  try {
    const data = new Uint8Array([255, 255, 255, 255]);
    const read = await handle.read(data, 1, 2, 1);
    assert(read.buffer === data && read.bytesRead === 2 && String(data) === "255,0,98,255", "positional read failed");
    await handle.truncate(2);
    await handle.sync();
    const stat = await handle.stat();
    assert(stat.isFile() && stat.size === 2 && typeof stat.mtimeMs === "number", "invalid handle stat");
  } finally {
    await handle.close();
  }
  await rejects(() => handle.stat(), "EBADF");
  const readonly = await open(path, constants.O_RDONLY | (constants.O_NONBLOCK ?? 0));
  await readonly.close();
  assert((await readFile(path)).length === 2, "truncate did not persist");
  const [entry] = await readdir(root, { withFileTypes: true });
  assert(entry.name === "sample" && entry.isFile(), "invalid directory entry");
  const dir = await opendir(root);
  try {
    assert((await dir.read()).name === "sample" && await dir.read() === null, "directory read failed");
  } finally {
    await dir.close();
  }
  await rejects(() => open(path + "\0suffix"), "ERR_INVALID_ARG_VALUE");
  await rm(path, { force: true });
  await rm(path, { force: true });
} finally {
  await rm(root, { recursive: true, force: true });
}
console.log("filesystem handles ok");
