import { readSharedMessage } from "@shared/message";
import { rm, writeFile } from "fs";
import { join } from "path";

const outputPath = join(".", ".tsconfig_extends_output.txt");

await writeFile(outputPath, readSharedMessage());
console.log(readSharedMessage());
await rm(outputPath);
