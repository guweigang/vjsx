import { writeJson, readJson, copyFile, stat, rm } from "fs";
import { isAbsolute, relative, resolve } from "path";

const jsonPath = ".host_next.json";
const copyPath = ".host_next_copy.json";

await writeJson(jsonPath, { ok: true, count: 7 });
await copyFile(jsonPath, copyPath);

const data = await readJson(copyPath);
const info = await stat(copyPath);

console.log(String(data.ok));
console.error(String(data.count));
console.log(String(info.isFile()));
console.log(String(isAbsolute(resolve(copyPath))));
console.log(relative(process.cwd(), resolve(copyPath)));
console.log(process.argv.join("|"));

await rm(jsonPath);
await rm(copyPath);
