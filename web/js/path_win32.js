(() => {
  function normalize(path) {
    if (typeof path !== "string") throw new TypeError("path must be a string");
    path = path.replaceAll("/", "\\");
    const drive = /^[a-z]:/i.exec(path)?.[0] ?? "";
    const share = !drive && /^\\\\([^\\]+)\\+([^\\]+)(?:\\+|$)/.exec(path);
    const absolute = Boolean(share || path[drive.length] === "\\");
    const prefix = share ? "\\\\" + share[1] + "\\" + share[2] + "\\"
      : drive + (absolute ? "\\" : "");
    const tail = share ? path.slice(share[0].length) : path.slice(drive.length);
    const parts = [];
    for (const part of tail.split("\\")) {
      if (!part || part === ".") continue;
      if (part !== "..") parts.push(part);
      else if (parts.length && parts.at(-1) !== "..") parts.pop();
      else if (!absolute) parts.push(part);
    }
    let result = prefix + (parts.join("\\") || (absolute ? "" : "."));
    if (!drive && !absolute && /^[a-z]:/i.test(result)) result = ".\\" + result;
    if (path.endsWith("\\") && !result.endsWith("\\")) result += "\\";
    return result;
  }

  return {
    sep: "\\",
    delimiter: ";",
    normalize,
    join(...parts) {
      if (parts.some((part) => typeof part !== "string")) throw new TypeError("path must be a string");
      const nonempty = parts.filter(Boolean);
      let joined = nonempty.join("\\");
      if (!/^[\\/]{2}[^\\/]/.test(nonempty[0] ?? "")) {
        joined = joined.replace(/^[\\/]{2,}/, "\\");
      }
      return normalize(joined);
    },
  };
})()
