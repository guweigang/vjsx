import { exec, execFile, fork, spawn } from "child_process";
import fs from "fs";
import os from "os";
import path from "path";

const shell = process.platform === "win32" ? "cmd" : "sh";
const printArgs = process.platform === "win32"
  ? ["/d", "/c", "echo hello-async"]
  : ["-c", "printf hello-async"];
const failArgs = process.platform === "win32"
  ? ["/d", "/c", "echo async-fail 1>&2 & exit /b 5"]
  : ["-c", "printf async-fail >&2; exit 5"];

const lines = [];

await new Promise((resolve, reject) => {
  const child = execFile(shell, printArgs, { encoding: "utf8" }, (err, stdout, stderr) => {
    lines.push(String(err === null));
    lines.push(String(stdout).trim());
    lines.push(String(stderr).trim() === "");
  });
  child.stdout.on("data", (chunk) => {
    lines.push(`execFile:${String(chunk).trim()}`);
  });
  child.on("exit", (code) => {
    lines.push(`execFile-exit:${String(code)}`);
  });
  child.on("close", (code) => {
    lines.push(`execFile-close:${String(code)}`);
    resolve();
  });
  child.on("error", reject);
});

await new Promise((resolve, reject) => {
  const child = exec(process.platform === "win32" ? "echo shell-async" : "printf shell-async", { encoding: "utf8" }, (err, stdout, stderr) => {
    lines.push(String(err === null));
    lines.push(String(stdout).trim());
    lines.push(String(stderr).trim() === "");
  });
  child.on("close", () => resolve());
  child.on("error", reject);
});

await new Promise((resolve, reject) => {
  const child = spawn(shell, printArgs);
  const removedListener = () => {
    lines.push("removed-listener-fired");
  };
  child.stdout.on("data", removedListener);
  lines.push(`listenerCount:${String(child.stdout.listenerCount("data"))}`);
  child.stdout.off("data", removedListener);
  lines.push(`listenerCountAfterOff:${String(child.stdout.listenerCount("data"))}`);
  lines.push(`stdio:${String(child.stdio[0] === child.stdin)}:${String(child.stdio[1] === child.stdout)}:${String(child.stdio[2] === child.stderr)}`);
  child.on("custom", (value) => {
    lines.push(`emit:${String(value)}`);
  });
  lines.push(`listeners:${String(child.listeners("custom").length)}`);
  lines.push(`emitReturn:${String(child.emit("custom", "ok"))}`);
  lines.push(`listenerCountAfterEmit:${String(child.listenerCount("custom"))}`);
  child.removeAllListeners("custom");
  lines.push(`listenerCountAfterRemoveAll:${String(child.listenerCount("custom"))}`);
  child.stdout.on("data", (chunk) => {
    lines.push(`spawn:${String(chunk).trim()}`);
  });
  child.on("exit", (code) => {
    lines.push(`spawn-exit:${String(code)}`);
  });
  child.on("close", (code) => {
    lines.push(`spawn-close:${String(code)}`);
    resolve();
  });
  child.on("error", reject);
});

await new Promise((resolve, reject) => {
  const child = spawn(process.platform === "win32" ? "echo shell-spawn" : "printf shell-spawn", [], { shell: true });
  child.stdout.on("data", (chunk) => {
    lines.push(`spawn-shell:${String(chunk).trim()}`);
  });
  child.on("close", () => resolve());
  child.on("error", reject);
});

await new Promise((resolve, reject) => {
  const child = fork("./host_child_process_fork_child.mjs", ["fork-arg"], {
    cwd: process.cwd(),
    env: { ...process.env, FORK_ENV: "fork-env" },
  });
  child.stdout.on("data", (chunk) => {
    lines.push(`fork:${String(chunk).trim()}`);
  });
  child.on("close", (code) => {
    lines.push(`fork-close:${String(code)}`);
    resolve();
  });
  child.on("error", reject);
});

await new Promise((resolve, reject) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "vjsx-child-pipe-"));
  const target = path.join(tmpDir, "child.txt");
  const child = spawn(shell, printArgs);
  const file = fs.createWriteStream(target);
  file.on("finish", () => {
    lines.push(`pipe:${fs.readFileSync(target).trim()}`);
    fs.rmSync(tmpDir, { recursive: true, force: true });
    resolve();
  });
  child.stdout.pipe(file);
  child.on("error", reject);
});

await new Promise((resolve, reject) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "vjsx-child-unpipe-"));
  const target = path.join(tmpDir, "child.txt");
  const delayedArgs = process.platform === "win32"
    ? ["/d", "/c", "ping -n 2 127.0.0.1 >nul & echo delayed-unpipe"]
    : ["-c", "sleep 1; printf delayed-unpipe"];
  const child = spawn(shell, delayedArgs);
  const file = fs.createWriteStream(target);
  child.stdout.pipe(file);
  child.stdout.unpipe(file);
  child.on("close", () => {
    lines.push(`unpipe:${String(fs.readFileSync(target).trim() === "")}`);
    fs.rmSync(tmpDir, { recursive: true, force: true });
    resolve();
  });
  child.on("error", reject);
});

await new Promise((resolve) => {
  const child = execFile(shell, failArgs, { encoding: "utf8" }, (err, stdout, stderr) => {
    lines.push(String(err.status));
    lines.push(String(stdout).trim());
    lines.push(String(stderr).trim());
  });
  child.on("close", () => resolve());
});

await new Promise((resolve) => {
  const child = spawn("__vjsx_missing_command__");
  child.on("error", (err) => {
    lines.push(String(err.message.includes("command not found")));
  });
  child.on("close", () => resolve());
});

await new Promise((resolve, reject) => {
  const liveArgs = process.platform === "win32"
    ? ["/d", "/c", "set /p line=& echo echo:%line% & echo done 1>&2"]
    : ["-c", 'IFS= read line; printf "echo:%s" "$line"; printf "done" >&2'];
  const child = spawn(shell, liveArgs);
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk) => {
    lines.push(`live:${String(chunk).trim()}`);
  });
  child.stderr.on("data", (chunk) => {
    lines.push(`liveerr:${String(chunk).trim()}`);
  });
  child.on("close", (code, signal) => {
    lines.push(`live-close:${String(code)}:${String(signal)}`);
    resolve();
  });
  child.on("error", reject);
  child.stdin.write("line-from-stdin\n");
  child.stdin.end();
});

await new Promise((resolve, reject) => {
  const killArgs = process.platform === "win32"
    ? ["/d", "/c", "echo ready & ping -n 6 127.0.0.1 >nul"]
    : ["-c", 'printf "ready\n"; sleep 5'];
  const child = spawn(shell, killArgs);
  let killed = false;
  child.stdout.setEncoding("utf8");
  child.stdout.on("data", (chunk) => {
    lines.push(`kill:${String(chunk).trim()}`);
    if (!killed) {
      killed = true;
      lines.push(String(child.kill("SIGTERM")));
    }
  });
  child.on("close", (code, signal) => {
    lines.push(`kill-close:${String(code)}:${String(signal)}`);
    resolve();
  });
  child.on("error", reject);
});

console.log(lines.join("\n"));
