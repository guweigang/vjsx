import { execFileSync, execSync, spawnSync } from "child_process";

const shell = process.platform === "win32" ? "cmd" : "sh";
const printArgs = process.platform === "win32"
  ? ["/d", "/c", "echo hello-child"]
  : ["-c", "printf hello-child"];
const inheritArgs = process.platform === "win32"
  ? ["/d", "/c", "echo inherit-child"]
  : ["-c", "echo inherit-child"];
const failArgs = process.platform === "win32"
  ? ["/d", "/c", "echo child-fail 1>&2 & exit /b 7"]
  : ["-c", "printf child-fail >&2; exit 7"];

const first = String(execFileSync(shell, printArgs, { encoding: "utf8" })).trim();
execFileSync(shell, inheritArgs, { stdio: "inherit" });
console.log(first);
console.log("after-inherit");
execSync(process.platform === "win32" ? "echo hidden-child" : "printf hidden-child", { stdio: "ignore" });
console.log("after-ignore");

const spawn = spawnSync(shell, printArgs, { encoding: "utf8" });
console.log(String(spawn.status));
console.log(String(spawn.pid > 0));
console.log(String(spawn.stdout).trim());
console.log(String(spawn.stderr).trim() === "");
console.log(String(Array.isArray(spawn.output) && spawn.output.length === 3));
console.log(String(spawn.output[1]).trim());

try {
  execFileSync(shell, failArgs, { encoding: "utf8" });
} catch (err) {
  console.log(String(err.status));
  console.log(String(err.stderr).trim());
}
