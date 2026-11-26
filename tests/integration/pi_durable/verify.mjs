import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { appendFileSync, existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { setTimeout } from "node:timers/promises";
import { fileURLToPath } from "node:url";

const binary = resolve(process.env.VJSX_BIN);
const fixture = fileURLToPath(new URL("./turn.mjs", import.meta.url));
const tornLine = '{"torn":"é';

function sqliteSubmissions(database) {
  const db = new DatabaseSync(database, { readOnly: true });
  try {
    return db.prepare("SELECT id, request_id, status FROM submissions ORDER BY id").all();
  } finally {
    db.close();
  }
}

function jsonlSubmissions(log) {
  const text = readFileSync(log, "utf8");
  assert.ok(text.endsWith("\n"), "log ends with a partial line");
  const latest = new Map();
  for (const line of text.trimEnd().split("\n")) {
    for (const write of JSON.parse(line).writes) {
      if (write.type === "submission") latest.set(write.value.id, write.value);
    }
  }
  return [...latest.values()].map(({ id, requestId, status }) => ({ id, request_id: requestId, status }));
}

async function verify(backend) {
  const temp = mkdtempSync(join(tmpdir(), "vjsx-pi-durable-"));
  const storage = join(temp, backend === "sqlite" ? "session.sqlite" : "session");
  const marker = join(temp, "model-started");
  const log = join(storage, "main.jsonl");
  const submissions = backend === "sqlite" ? () => sqliteSubmissions(storage) : () => jsonlSubmissions(log);
  function run(arg) {
    const child = spawn(binary, ["check", "--runtime", "node", fixture, backend, storage, arg], { stdio: "inherit" });
    return { child, stopped: once(child, "exit") };
  }

  let running;
  try {
    running = run(marker);
    const deadline = Date.now() + 15000;
    while (!existsSync(marker)) {
      assert.equal(running.child.exitCode, null, "process exited before model dispatch");
      assert.equal(running.child.signalCode, null, "process was killed before model dispatch");
      assert.ok(Date.now() < deadline, "timed out waiting for model dispatch");
      await setTimeout(50);
    }
    running.child.kill("SIGKILL");
    assert.deepEqual(await running.stopped, [null, "SIGKILL"]);
    const before = submissions();
    assert.equal(before.length, 1);
    assert.equal(before[0].status, "placed");
    if (backend === "jsonl") appendFileSync(log, tornLine);

    running = run("--resume");
    assert.deepEqual(await running.stopped, [0, null]);
    const after = submissions();
    assert.equal(after.length, 1);
    assert.equal(after[0].id, before[0].id);
    assert.equal(after[0].request_id, before[0].request_id);
    assert.equal(after[0].status, "done");
    if (backend === "jsonl") assert.ok(!readFileSync(log, "utf8").includes(tornLine));
  } finally {
    if (running && running.child.exitCode === null && running.child.signalCode === null) {
      running.child.kill("SIGKILL");
      await running.stopped.catch(() => {});
    }
    rmSync(temp, { recursive: true, force: true });
  }
}

for (const backend of process.argv.length > 2 ? process.argv.slice(2) : ["sqlite", "jsonl"]) {
  await verify(backend);
}
