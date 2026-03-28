import { rm } from "fs";
import { open } from "sqlite";

const dbPath = ".host_sqlite_runtime.db";
const db = await open({ path: dbPath, busyTimeout: 1000 });

await db.exec("drop table if exists users");
await db.exec("create table users (id integer primary key, name text)");
console.log(String(db.inTransaction));
await db.begin();
console.log(String(db.inTransaction));
const rolledInsert = await db.exec("insert into users(name) values (?)", ["temp"]);
await db.rollback();
console.log(String(db.inTransaction));
const afterRollback = await db.query("select count(*) as count from users");
await db.begin();
const insertOne = await db.exec("insert into users(name) values (?)", ["alice"]);
await db.commit();
const insertTwo = await db.exec("insert into users(name) values (?)", ["bob"]);
const rows = await db.query("select id, name from users where name <> ? order by id", ["bob"]);
const firstRow = await db.queryOne("select id, name from users where name <> ? order by id", ["bob"]);
const missingRow = await db.queryOne("select id, name from users where name = ?", ["nobody"]);
const countValue = await db.scalar("select count(*) from users");
const missingValue = await db.scalar("select name from users where name = ?", ["nobody"]);
const rowBatches = await db.queryMany("select id, name from users where name <> ? order by id", [["bob"], ["alice"]]);
const insertBatch = await db.execMany("insert into users(name) values (?)", [["carol"], ["dave"]]);

console.log(db.path.endsWith(dbPath));
console.log(String(rolledInsert.changes));
console.log(String(afterRollback[0].count));
console.log(String(insertOne.changes));
console.log(String(insertOne.rowsAffected));
console.log(String(insertOne.lastInsertRowid));
console.log(String(insertOne.insertId));
console.log(String(insertTwo.lastInsertRowid));
console.log(rows.map((row) => `${row.id}:${row.name}`).join(","));
console.log(firstRow ? `${firstRow.id}:${firstRow.name}` : "null");
console.log(String(missingRow === null));
console.log(String(countValue));
console.log(String(missingValue === null));
console.log(rowBatches.map((group) => group.map((row) => row.name).join(",")).join("|"));
console.log(String(insertBatch.length));
console.log(String(insertBatch[0].insertId));
console.log(String(insertBatch[1].insertId));

await db.close();
await rm(dbPath);
