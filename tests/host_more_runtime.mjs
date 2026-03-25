import { exists, mkdir, writeFile } from "fs";
import { join, dirname, basename } from "path";

const dirPath = join(".host_more_runtime_dir", "nested");
const filePath = join(dirPath, "note.txt");

await mkdir(dirPath);
await writeFile(filePath, "nested text");

console.log(String(await exists(filePath)));
console.log(dirname(filePath));
console.error(basename(filePath));
