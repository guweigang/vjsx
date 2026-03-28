import { rm } from "fs";
import { open } from "sqlite";

const dbPath = ".examples_sqlite_basic.db";
const db = await open({ path: dbPath, busyTimeout: 1000 });

await db.exec("drop table if exists users");
await db.exec("create table users (id integer primary key, name text)");
await db.execMany("insert into users(name) values (?)", [["alice"], ["bob"], ["carol"]]);

const firstUser = await db.queryOne("select id, name from users order by id");
const userCount = await db.scalar("select count(*) from users");
const stmt = await db.prepareCached("select id, name from users where name <> ? order by id");
const batches = await stmt.queryMany([["carol"], ["alice"]]);

console.log(firstUser ? `${firstUser.id}:${firstUser.name}` : "null");
console.log(String(userCount));
console.log(batches.map((group) => group.map((row) => row.name).join(",")).join("|"));

await stmt.close();
await db.close();
await rm(dbPath);
