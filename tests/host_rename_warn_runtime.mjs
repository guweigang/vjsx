import { exists, readFile, rename, rm, writeFile } from "fs";
import { join } from "path";

const source = join(".", ".host_rename_warn_source.txt");
const target = join(".", ".host_rename_warn_target.txt");

await writeFile(source, "rename text");
await rename(source, target);

console.warn("renamed", String(await exists(source)), String(await exists(target)));
console.log(await readFile(target));

await rm(target);
