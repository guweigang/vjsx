import { rm } from "fs";
import { open } from "sqlite";

const dbPath = ".host_sqlite_statement_runtime.db";
const db = await open({ path: dbPath });

await db.exec("drop table if exists users");
await db.exec("create table users (id integer primary key, name text)");

const cachedSelectOne = await db.prepareCached("select id, name from users where name <> ? order by id");
const cachedSelectTwo = await db.prepareCached("select id, name from users where name <> ? order by id");
const insertStmt = await db.prepare("insert into users(name) values (?)");
const selectStmt = cachedSelectOne;

const first = await insertStmt.exec(["alice"]);
const batch = await insertStmt.execMany([["bob"], ["carol"]]);
const rows = await selectStmt.query(["carol"]);
const firstRow = await selectStmt.queryOne(["bob"]);
const missingRow = await db.queryOne("select id, name from users where name = ?", ["nobody"]);
const countStmt = await db.prepare("select count(*) as count from users");
const missingStmt = await db.prepare("select name from users where name = ?");
const countValue = await countStmt.scalar();
const missingValue = await missingStmt.scalar(["nobody"]);
const rowBatches = await selectStmt.queryMany([["carol"], ["alice"]]);

console.log(db.driver);
console.log(String(db.supportsTransactions));
console.log(insertStmt.driver);
console.log(String(insertStmt.supportsTransactions));
console.log(db.toString());
console.log(insertStmt.toString());
console.log(String(cachedSelectOne === cachedSelectTwo));
console.log(insertStmt.sql);
console.log(insertStmt.kind);
console.log(selectStmt.kind);
console.log(String(insertStmt.closed));
console.log(String(first.rowsAffected));
console.log(String(first.insertId));
console.log(String(batch.length));
console.log(String(batch[0].insertId));
console.log(String(batch[1].insertId));
console.log(rows.map((row) => `${row.id}:${row.name}`).join(","));
console.log(firstRow ? `${firstRow.id}:${firstRow.name}` : "null");
console.log(String(missingRow === null));
console.log(String(countValue));
console.log(String(missingValue));
console.log(rowBatches.map((group) => group.map((row) => row.name).join(",")).join("|"));

await insertStmt.close();
await countStmt.close();
await missingStmt.close();
await cachedSelectOne.close();
const cachedSelectThree = await db.prepareCached("select id, name from users where name <> ? order by id");
console.log(String(insertStmt.closed));
console.log(String(selectStmt.closed));
console.log(String(cachedSelectThree === cachedSelectOne));

await db.close();
console.log(String(cachedSelectThree.closed));
await rm(dbPath);
