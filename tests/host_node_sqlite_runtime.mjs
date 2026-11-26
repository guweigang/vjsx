import sqlite, { DatabaseSync } from "node:sqlite";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function throws(callback, expected) {
  try {
    callback();
  } catch (error) {
    assert(error.message.includes(expected), error.message);
    return;
  }
  throw new Error("expected failure: " + expected);
}

assert(sqlite.DatabaseSync === DatabaseSync, "default export");
const db = new DatabaseSync(":memory:", { timeout: 100 });
db.exec("CREATE TABLE fixture (id INTEGER PRIMARY KEY, number REAL, text TEXT, data BLOB); BEGIN IMMEDIATE");
const insert = db.prepare("INSERT INTO fixture VALUES (?, ?, ?, ?)");
const bytes = new Uint8Array([99, 0, 255, 99]);
assert(insert.run(7n, 0.5, "a\0b", bytes.subarray(1, 3)).changes === 1, "changes");
insert.run(8n, null, "", new Uint8Array());
db.exec("COMMIT");
const rows = db.prepare("SELECT * FROM fixture ORDER BY id").all();
assert(rows[0].id === 7 && rows[0].number === 0.5 && rows[0].text === "a\0b", "typed columns");
assert(rows[0].data instanceof Uint8Array && String(rows[0].data) === "0,255", "blob slice");
assert(rows[1].number === null && rows[1].text === "" && rows[1].data.length === 0, "null and empty values");
assert(db.prepare("SELECT id FROM fixture WHERE id = ?").get(4) === undefined, "empty get");
assert(db.prepare("SELECT 1 AS __proto__").get().__proto__ === 1, "column name");
assert(db.prepare("SELECT 1 AS value; -- comment").get().value === 1, "trailing comment");
throws(() => db.prepare("SELECT 1; SELECT 2"), "one SQLite statement");

const bigint = db.prepare("SELECT ?");
bigint.setReadBigInts(true);
assert(bigint.get(-9223372036854775808n)["?"] === -9223372036854775808n, "signed 64-bit integer");
throws(() => bigint.get(9223372036854775808n), "signed 64-bit range");
throws(() => db.prepare("SELECT 9007199254740992").get(), "safe range");

db.exec("BEGIN IMMEDIATE");
insert.run(9n, null, null, null);
throws(() => insert.run(9n, null, null, null), "UNIQUE");
db.exec("ROLLBACK");
assert(db.prepare("SELECT count(*) AS total FROM fixture").get().total === 2, "rollback");
db.close();
throws(() => insert.run(10n, null, null, null), "closed");
console.log("node:sqlite ok");
