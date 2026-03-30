import * as os from "os";
import {
  EOL,
  arch,
  availableParallelism,
  cpus,
  devNull,
  endianness,
  freemem,
  homedir,
  hostname,
  loadavg,
  machine,
  platform,
  release,
  tmpdir,
  totalmem,
  type,
  userInfo,
  version,
} from "os";

const info = userInfo();

console.log(typeof os);
console.log(String(os.arch() === arch()));
console.log(String(os.platform() === platform()));
console.log(String(EOL.length > 0));
console.log(String(devNull.length > 0));
console.log(platform());
console.log(arch());
console.log(String(type().length > 0));
console.log(String(release().length > 0));
console.log(String(typeof version() === "string"));
console.log(String(machine().length > 0));
console.log(String(hostname().length > 0));
console.log(String(homedir().length > 0));
console.log(String(tmpdir().length > 0));
console.log(endianness());
console.log(String(availableParallelism() >= 1));
console.log(String(cpus().length >= 1));
console.log(String(totalmem() > 0));
console.log(String(freemem() >= 0));
console.log(String(Array.isArray(loadavg()) && loadavg().length === 3));
console.log(String(info.username.length > 0));
console.log(String(info.homedir.length > 0));
console.log(String(typeof info.shell === "string"));
