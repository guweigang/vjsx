import { readFile, writeFile } from "fs";
import { join } from "path";

const outputPath = join(".", ".host_runtime_output.txt");

await writeFile(outputPath, "written text");
console.error(await readFile(outputPath));
console.log(join("a", "b", "c"));
