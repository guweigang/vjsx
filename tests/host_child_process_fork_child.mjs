import path from "path";

console.log([
  process.argv.slice(1).join(","),
  String(process.env.FORK_ENV),
  path.basename(process.cwd()),
].join("|"));
