import { rm } from "fs";
import { open } from "sqlite";

const dbPath = ".host_sqlite_transaction_runtime.db";
const db = await open({ path: dbPath });

await db.exec("drop table if exists users");
await db.exec("create table users (id integer primary key, name text)");
console.log(String(db.inTransaction));

const committedCount = await db.transaction(async (tx) => {
  console.log(String(tx.inTransaction));
  await tx.exec("insert into users(name) values (?)", ["alice"]);
  await tx.exec("insert into users(name) values (?)", ["bob"]);
  const rows = await tx.query("select count(*) as count from users");
  return rows[0].count;
});

let rollbackMessage = "";
try {
  await db.transaction(async (tx) => {
    await tx.exec("insert into users(name) values (?)", ["temp"]);
    throw new Error("rollback-me");
  });
} catch (err) {
  rollbackMessage = err.message;
}

const rows = await db.query("select name from users order by id");
console.log(String(db.inTransaction));

console.log(String(committedCount));
console.log(rollbackMessage);
console.log(rows.map((row) => row.name).join(","));

await db.close();
await rm(dbPath);
