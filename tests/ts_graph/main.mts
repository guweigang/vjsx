import { readMessage } from "./lib/read_message.ts";
import { rm, writeFile } from "fs";
import { join } from "path";

const outputPath = join(".", ".ts_graph_output.txt");

await writeFile(outputPath, readMessage());
console.log(readMessage());
await rm(outputPath);
