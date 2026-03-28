import { connect } from "mysql";

const host = process.env.VJS_TEST_MYSQL_HOST || "127.0.0.1";
const port = Number(process.env.VJS_TEST_MYSQL_PORT || "3306");
const user = process.env.VJS_TEST_MYSQL_USER || "root";
const password = process.env.VJS_TEST_MYSQL_PASSWORD || "";
const database = process.env.VJS_TEST_MYSQL_DBNAME || "mysql";
const table = process.env.VJS_TEST_MYSQL_TABLE || "vjsx_example_mysql_basic";

const db = await connect({ host, port, user, password, database });

await db.exec(`drop table if exists ${table}`);
await db.exec(`create table ${table} (id int primary key auto_increment, name text)`);
await db.execMany(`insert into ${table}(name) values (?)`, [["alice"], ["bob"], ["carol"]]);

const firstUser = await db.queryOne(`select id, name from ${table} order by id`);
const userCount = await db.scalar(`select count(*) from ${table}`);
const stmt = await db.prepareCached(`select id, name from ${table} where name <> ? order by id`);
const batches = await stmt.queryMany([["carol"], ["alice"]]);

console.log(firstUser ? `${firstUser.id}:${firstUser.name}` : "null");
console.log(String(userCount));
console.log(batches.map((group) => group.map((row) => row.name).join(",")).join("|"));

await stmt.close();
await db.exec(`drop table if exists ${table}`);
await db.close();
