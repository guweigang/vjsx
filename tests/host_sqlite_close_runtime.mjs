import { rm } from "fs";
import { open } from "sqlite";

const dbPath = ".host_sqlite_close_runtime.db";
const db = await open({ path: dbPath });

const stmt = await db.prepare("select 1 as value");
const cachedOne = await db.prepareCached("select 1 as value");
const cachedTwo = await db.prepareCached("select 1 as value");

console.log(String(cachedOne === cachedTwo));

await stmt.close();
console.log(String(stmt.closed));
await stmt.close();
console.log(String(stmt.closed));

await cachedOne.close();
console.log(String(cachedOne.closed));
await cachedOne.close();
console.log(String(cachedOne.closed));

const cachedThree = await db.prepareCached("select 1 as value");
console.log(String(cachedThree === cachedOne));

await db.close();
console.log(String(cachedThree.closed));
await db.close();
console.log(String(cachedThree.closed));

try {
  await db.prepareCached("select 1 as value");
} catch (err) {
  console.log(`${err.name}:${err.message}`);
}

await rm(dbPath);
