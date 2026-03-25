import { packageMessage } from "answer-pkg";
import { rm, writeFile } from "fs";
import { join } from "path";

const outputPath = join(".", ".ts_pkg_output.txt");

await writeFile(outputPath, packageMessage());
console.log(packageMessage());
await rm(outputPath);
