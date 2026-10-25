import fs from "fs";
import http from "http";
import https from "https";
import nodeHttp, { get as nodeGet } from "node:http";
import nodeHttps, { get as nodeSecureGet } from "node:https";
import os from "os";
import path from "path";

if (http !== nodeHttp || https !== nodeHttps || http.get !== nodeGet || https.get !== nodeSecureGet) {
  throw new Error("HTTP module aliases must share their native exports");
}
const base = process.argv[1];
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "vjsx-http-"));
const target = path.join(tmpDir, "payload.bin");
const lines = [typeof http.get, typeof https.get];

await new Promise((resolve, reject) => {
  http.get(`${base}/redirect`, (res) => {
    lines.push(String(res.statusCode));
    lines.push(String(res.headers.location));
    const file = fs.createWriteStream(target);
    file.on("finish", () => {
      file.close();
      resolve();
    });
    nodeGet(`${base}${res.headers.location}`, (finalRes) => {
      lines.push(String(finalRes.statusCode));
      finalRes.pipe(file);
    }).on("error", reject);
  }).on("error", reject);
});

globalThis.__host_http_result = lines.join("\n");
globalThis.__host_http_target = target;
