import { readFile, rm, writeFile } from "fs";
import { join } from "path";

const outputPath: string = join(".", ".ts_runtime_output.txt");

await writeFile(outputPath, "ts module");
console.log(await readFile(outputPath));
await rm(outputPath);
