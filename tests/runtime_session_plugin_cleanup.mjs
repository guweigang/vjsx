import { writeFileSync } from "fs";

let dispose_path = "";

export function activate(path) {
  dispose_path = path;
  return `activate:${path !== ""}`;
}

export function dispose() {
  if (dispose_path !== "") {
    writeFileSync(dispose_path, "disposed");
  }
  return `dispose:${dispose_path !== ""}`;
}
