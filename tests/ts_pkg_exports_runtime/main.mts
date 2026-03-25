import { featureMessage } from "exports-pkg/feature";
import { rootMessage } from "exports-pkg";
import { rm, writeFile } from "fs";
import { join } from "path";

const outputPath = join(".", ".ts_pkg_exports_output.txt");
const output = `${rootMessage()} + ${featureMessage()}`;

await writeFile(outputPath, output);
console.log(output);
await rm(outputPath);
