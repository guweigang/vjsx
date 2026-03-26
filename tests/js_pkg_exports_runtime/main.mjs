import { featureMessage } from "js-exports-pkg/feature";
import { rootMessage } from "js-exports-pkg";
import { rm, writeFile } from "fs";
import { join } from "path";

const outputPath = join(".", ".js_pkg_exports_output.txt");
const output = `${rootMessage()} + ${featureMessage()}`;

await writeFile(outputPath, output);
console.log(output);
await rm(outputPath);
