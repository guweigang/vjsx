const path = require("path");
const dep = require("./cjs_runtime_dep.cjs");

console.log(path.join("cjs", dep.value));
console.log(__filename.endsWith("cjs_runtime.cjs"));
console.log(__dirname.endsWith(path.join("vjsx", "tests")));
