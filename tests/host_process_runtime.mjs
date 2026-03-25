import { copyFile, stat, readFile, writeFile, rm } from "fs";
import { join, relative } from "path";

const source = join(".", ".host_process_source.txt");
const copied = join(".", ".host_process_copy.txt");

await writeFile(source, "copy source");
await copyFile(source, copied);

const info = await stat(copied);
console.log(String(info.isFile()));
console.error(String(info.size));
console.log(await readFile(copied));
console.log(relative(process.cwd(), join(process.cwd(), copied)));
console.log(process.env.VJS_PROCESS_MARKER);

await rm(source);
await rm(copied);
