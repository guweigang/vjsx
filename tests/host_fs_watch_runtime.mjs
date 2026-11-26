import fs, { watch as bareWatch } from "fs";
import { mkdirSync, mkdtempSync, renameSync, rmSync, watch, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function nextChange(watcher, event, filename, change) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      watcher.off("change", onChange);
      reject(new Error("missing " + event + " event for " + filename));
    }, 3000);
    function onChange(kind, name) {
      if (kind !== event || String(name) !== filename) return;
      watcher.off("change", onChange);
      clearTimeout(timer);
      resolve(name);
    }
    watcher.on("change", onChange);
    change();
  });
}

assert(watch === bareWatch && watch === fs.watch, "watch aliases differ");

if (process.argv.includes("--idle")) {
  watch(".", { persistent: false }).ref().unref();
  console.log("unreferenced watcher");
} else {
  const root = mkdtempSync(join(tmpdir(), "vjsx-fs-watch-"));
  const dir = join(root, "nested");
  const file = join(dir, "before.txt");
  const renamed = join(dir, "after.txt");
  mkdirSync(dir);
  writeFileSync(file, "old");
  const controller = new AbortController();
  const tree = watch(root, { recursive: true, encoding: "buffer", signal: controller.signal, persistent: false });
  const fileWatcher = watch(file);
  try {
    const change = await Promise.all([
      nextChange(tree, "change", join("nested", "before.txt"), () => {}),
      nextChange(fileWatcher, "change", "before.txt", () => writeFileSync(file, "new")),
    ]);
    assert(Buffer.isBuffer(change[0]), "buffer filename");

    await nextChange(tree, "rename", join("nested", "after.txt"), () => renameSync(file, renamed));
    const closed = new Promise((resolve) => tree.once("close", resolve));
    controller.abort();
    await closed;
    tree.close();
    fileWatcher.close();
    const unreferenced = watch(renamed, { persistent: false });
    try {
      const changed = new Promise((resolve) => unreferenced.once("change", resolve));
      writeFileSync(renamed, "another edit");
      assert(await changed === "change", "unreferenced watcher during an explicit await");
    } finally {
      unreferenced.close();
    }
    console.log("watch callbacks ok");
  } finally {
    tree.close();
    fileWatcher.close();
    rmSync(root, { recursive: true, force: true });
  }
}
