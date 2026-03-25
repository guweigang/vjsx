import { mkdir, writeFile, readdir, rm, exists } from "fs";
import { join, extname, resolve } from "path";

const dirPath = join(".host_fs_path_runtime_dir", "nested");
const filePath = join(dirPath, "note.txt");

await mkdir(dirPath);
await writeFile(filePath, "runtime text");

const entries = await readdir(dirPath);
console.log(entries.join(","));
console.error(extname(filePath));
console.log(String((await exists(filePath))));
console.log(resolve(".", dirPath, "..", "nested", "note.txt"));

await rm(".host_fs_path_runtime_dir", true);
console.log(String((await exists(filePath))));
