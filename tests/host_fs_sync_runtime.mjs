import fs from "fs";
import path from "path";

const tmpDir = fs.mkdtempSync(path.join(".", ".host_fs_sync_"));
const source = path.join(tmpDir, "source.txt");
const copied = path.join(tmpDir, "copied.txt");
const nested = path.join(tmpDir, "nested");

fs.mkdirSync(nested, { recursive: true });
fs.writeFileSync(source, "sync text");
console.log(fs.readFileSync(source));
console.log(String(fs.existsSync(source)));
console.log(String(fs.statSync(source).isFile()));
fs.copyFileSync(source, copied);
fs.chmodSync(copied, 0o644);
console.log(fs.readdirSync(tmpDir).sort().join(","));
console.log(fs.readFileSync(copied));
fs.rmSync(tmpDir, { recursive: true, force: true });
console.log(String(fs.existsSync(tmpDir)));
