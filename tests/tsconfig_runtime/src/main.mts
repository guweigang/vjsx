import { readAliasMessage } from "@lib/message";
import { rm, writeFile } from "fs";
import { join } from "path";

const outputPath = join(".", ".tsconfig_runtime_output.txt");

await writeFile(outputPath, readAliasMessage());
console.log(readAliasMessage());
await rm(outputPath);
