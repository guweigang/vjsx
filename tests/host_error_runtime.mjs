import { rm } from "fs";
import { connect } from "mysql";
import { open } from "sqlite";

const dbPath = ".host_error_runtime.db";

try {
  await open({});
} catch (err) {
  console.log(`${err.name}:${err.message}`);
}

try {
  await open({ path: dbPath, busyTimeout: "1000" });
} catch (err) {
  console.log(`${err.name}:${err.message}`);
}

const db = await open({ path: dbPath });
const stmt = await db.prepare("select 1 as value");

try {
  await db.query("select 1 as value", "bad");
} catch (err) {
  console.log(`${err.name}:${err.message}`);
}

try {
  await db.queryMany("select 1 as value", [1]);
} catch (err) {
  console.log(`${err.name}:${err.message}`);
}

try {
  await stmt.query("bad");
} catch (err) {
  console.log(`${err.name}:${err.message}`);
}

await stmt.close();
try {
  await stmt.query([]);
} catch (err) {
  console.log(`${err.name}:${err.message}`);
}

await db.close();
try {
  await db.query("select 1 as value");
} catch (err) {
  console.log(`${err.name}:${err.message}`);
}

try {
  await connect("bad");
} catch (err) {
  console.log(`${err.name}:${err.message}`);
}

try {
  await connect({ port: "3306" });
} catch (err) {
  console.log(`${err.name}:${err.message}`);
}

try {
  await connect({});
} catch (err) {
  console.log(`${err.name}:${err.message}`);
}

await rm(dbPath);
