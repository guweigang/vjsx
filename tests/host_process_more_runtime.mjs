import { dirname } from "path";

const original = process.cwd();
const envKey = "VJS_PROCESS_SET_DELETE";

process.env[envKey] = "js-value";

console.log(process.env[envKey]);
delete process.env[envKey];
console.log(String(process.env[envKey] === undefined));
console.log(process.platform);
console.log(process.arch);
console.log(String(process.pid > 0));
console.log(String(process.ppid >= 0));
console.log(String(process.argv0 === process.argv[0]));
console.log(String(process.execPath.length > 0));
console.log(String(process.version.startsWith("v")));
console.log(String(typeof process.versions.node === "string"));
console.log(String(process.release.name === "vjsx"));
console.log(String(Array.isArray(process.execArgv) && process.execArgv.length === 0));
console.log(String(process.title === "vjsx"));
console.log(String(typeof process.stdout.write === "function"));
console.log(String(typeof process.stderr.write === "function"));
console.log(String(typeof process.stdin.isTTY === "boolean"));
process.chdir("..");
console.log(String(process.cwd() === dirname(original)));
process.chdir(original);
console.log(String(process.cwd() === original));
