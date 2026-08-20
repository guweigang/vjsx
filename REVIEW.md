# vjsx 代码库 Review 报告

**审查日期:** 2026-08-04
**项目版本:** v0.0.3 (commit `7124e07`)
**审查范围:** 核心 V 绑定、host API、CLI/包管理、字节码模块、最近 5 次提交

---

## 总体评价

`vjsx` 是一个结构良好、设计清晰的 V→quickjs-ng 绑定库，对外暴露的 API（`Runtime`/`Context`/`Value`/`ScriptModule`）职责分明。所有权约定有文档化（commit `7178327`），内存边界处理（`@[manualfree]`、`free()`）总体一致。包管理子系统是用户态最复杂的一块，已经做了 integrity 校验与 lifecycle-script 警告。整体质量不错，但存在以下需要重点关注的问题，按严重程度排序。

本报告综合了三个并行 review agents（host API、CLI/包管理、字节码内存安全）的发现。

---

## Critical（必须修复）

### C-1. `function.v` 第 113-137 行 — `unsafe { free(name_ptr) }` 释放 V 字符串指针，叠加未零初始化的 `JSClassDef`

```v
pub fn (ctx &Context) js_class(cls ClassParams) Value {
    ...
    name_ptr := cls.name.str       // V 字符串内部指针
    def := C.JSClassDef{ class_name: name_ptr }   // 只声明了 class_name
    proto := ctx.js_object()
    C.JS_NewClass(ctx.rt.ref, ref, &def)         // 把栈上 struct 拷进 runtime
    ...
    unsafe { free(name_ptr) }       // ← 这里
    return ctx.c_val(class)
}
```

三个 bug 串在一起：

1. **`free(name_ptr)` 是 libc `free()`，但 `cls.name.str` 是 V 字符串池管理的存储**。V 字符串不是 libc `malloc` 出来的，调用 `free()` 直接破坏 V 的字符串池。后果可能是立即崩溃，也可能延迟到 GC 复用该内存时出现 UAF。
2. **`JSClassDef` 在 V 端只声明了 `class_name`**（function.v:18），但 quickjs 的真实 struct 还有 `finalizer`、`gc_mark`、`call`、`construct` 四个函数指针。V 的 struct literal 不会零初始化未声明字段，栈上残留的垃圾被 `*class_def = *def` 拷进 runtime 的类表。一旦 QuickJS 派发这些回调，就会执行栈上的随机函数指针（Windows/MSVC 或 debug build 上更容易暴露，release x86_64 栈恰好是 0 时看起来"工作"）。
3. **即便去掉 `free()`，`name_ptr` 仍然有 use-after-free 风险**。`JS_NewClass` 不复制 `class_name`，runtime 类表里持有的是这个 V 字符串的指针。V GC 一旦回收该字符串（通常在 `js_class` 返回后），后续 `class.toString()` 就读已释放内存。

**修复方向**：在 C shim 里建一个 `vjsx_js_strdup_owned` helper（已经存在 `vjsx_js_strdup`，但属于 js_malloc 体系），把 `cls.name.str` 拷一份永远不释放；或者把 `JSClassDef` 构造挪到 C 端并零初始化全部字段；或者改成把 class name 整体换成 interned `JSAtom` 而不是 `char*`。

### C-2. `function.v` 第 111-112 行 — `JS_NewClassID` 的 out-param 被静默覆盖

```v
id := cls.id or { rand.u32n(1000) or { panic(err) } }
ref := C.JS_NewClassID(&id)
```

`JS_NewClassID(uint32_t *pclass_id)` 在 quickjs 中**总是覆写**入参；调用者传的 `id`（无论是 `ClassParams.id` 还是 0..999 随机数）被丢弃。后果：

- `rand.u32n(1000)` 实际是死代码，误导读者以为它在控制 ID 空间。
- `ClassParams.id` 公开字段是 no-op，调用方以为自己能选 ID，但 runtime 给的 ID 与之无关。
- 如果保留"用户可指定 ID"语义，需要在 C shim 里做"指定 ID 已被占则返回错误"；或改用 V 端 `map[string]int` 维护稳定 ID 映射。

### C-3. `host_child_process.v` 第 999-1006、1346、1424 行 — `exec`/`execSync` 通过 `sh -lc <command>` 执行未转义字符串

```v
shell_command, shell_args := child_process_shell_command(command, options.shell)
result := child_process_run(shell_command, shell_args, child_process_without_shell(options), roots) or { ... }
```

`exec`/`execSync` 的 `command` 字符串直接喂给 `sh -lc`（POSIX）或 `cmd /d /c`（Windows），**没有任何字符转义**。`child_process_shell_escape_arg` 只对 argv 元素起作用，命令本身保持原样。这是 Node.js 标准行为，文档里也明说"this is dangerous"，但缺少权限门。

**配合 C-4（env 写权限）成为 RCE 链**：
1. `process.env.LD_PRELOAD = '/tmp/evil.so'`
2. `child_process.execSync('ls')`
3. shell 启动时自动加载 `evil.so`。

建议至少加一个 `enable_exec` 配置开关（默认关），或在 `install_child_process_module(roots)` 处增加 `enable_shell: bool` 选项。

### C-4. `host_process.v` 第 137-176 行 — `process.env` Proxy 允许 JS 写任何 env 变量

```v
global.set('__vjs_process_env_set', ctx.js_function(fn [ctx] (args []Value) Value {
    if args.len < 2 { return ctx.js_bool(false) }
    os.setenv(args[0].str(), args[1].str(), true)   // overwrite=true
    return ctx.js_bool(true)
}))
```

`__vjs_process_env_set/_unset` 直接调 `os.setenv(..., true)`，无 allowlist、无 denylist。后果：

- **读权限**：泄露 `AWS_*`、`*_TOKEN`、`GITHUB_TOKEN`、DB 凭据、SSH agent 等敏感变量。
- **写权限**：`LD_PRELOAD` (Linux)、`DYLD_INSERT_LIBRARIES` (macOS)、`PATH`、`PYTHONPATH`、`NODE_OPTIONS`、`PYTHONSTARTUP`、`BASH_ENV` 等都是直接 RCE 钩子。
- **env 是与父进程共享的**，JS 写的变量会污染 host 进程本身（不只是子进程）。

**这是单点最严重的权限缺口**，串联上面 C-3 可以一个 `LD_PRELOAD` 设置 + 一次 `execSync('ls')` 就 RCE。建议：默认 `__vjs_process_env_set/_unset` 不安装，或加 denylist（至少 `LD_*`、`DYLD_*`、`NODE_OPTIONS`、`PATH`、各种 `*_PATH`）。

### C-5. `host_fetch.v` 第 131 行 — curl 参数注入：URL 以 `-` 开头被 curl 当成 flag

```v
args << request.url
```

JS 可以传 `fetch("https://x/-o/tmp/evil")` ——curl 把 `-o/tmp/evil` 当成输出路径覆盖任意文件。`-K`/`--config`/`--upload-file` 同理。

**修复**：在 URL 之前插入 `--`，让 curl 停止解析后续参数：
```v
args << '--'
args << request.url
```

同时**校验 header key**（第 120 行）只允许 `^[A-Za-z0-9_-]+$`，并 strip `value` 中的 `\r\n`（CRLF 注入可加任意 curl `-H` 参数）。

---

## High（应当尽快修复）

### H-1. `bytecode.v` 第 158–161 行 — `payload_len_u64` 截断到 `int` 没有上界校验

```v
payload_len_u64 := read_u64_le(data, 24)!
if payload_len_u64 > u64(data.len) {
    return error('invalid vjsx bytecode: payload is too large')
}
payload_len := int(payload_len_u64)   // ← 攻击者控制 64-bit 字段
```

64-bit 字段只检查了不超过 `data.len`，但 `int` 在 32 位平台只有 31-bit 有效位（V 的 `int` 是平台相关；在 Windows 仍为 32-bit）。构造一个 `payload_len = 0xFFFFFFFF` 的恶意 .qbc 会让 `payload_len` 变成 `-1`，随后 `data[header_size..]` 会触发 panic 或越界。**检查应改为 `payload_len_u64 <= u64(max_int)`**，且建议在更早位置加上 256 MB 总量上限。

### H-2. `bytecode.v` 第 254-269 行 — 异常路径上的 `JSValue` 泄漏

```v
mut compiled_ref := ctx.js_undefined().ref
payload_ptr := &artifact.payload[0]
C.vjsx_js_read_bytecode_out(ctx.ref, payload_ptr, usize(artifact.payload.len), &compiled_ref)
compiled := ctx.c_val(compiled_ref)
if compiled.is_exception() {
    return ctx.js_exception()       // ← compiled 没 free
}
mut factory_ref := ctx.js_undefined().ref
C.vjsx_js_eval_function_out(ctx.ref, compiled.ref, &factory_ref)
factory := ctx.c_val(factory_ref)
if factory.is_exception() {
    return ctx.js_exception()       // ← compiled 没 free，factory 也没 free
}
defer { factory.free() }
```

QuickJS 的 `JS_EvalFunction` 在失败时**不**consume 入参，因此 `compiled` 在异常路径上必须由调用方 free。同样 `factory` 在第二个 `is_exception()` 路径上也没 free。

修复：把 `defer { compiled.free() }` 放到 `c_val(compiled_ref)` 之后立刻；并把 `defer { factory.free() }` 提到 `c_val(factory_ref)` 之后。

### H-3. `bytecode.v` 整个 `load_bytecode` 流程 — 没有沙箱边界

`load_bytecode` 是**完全信任的代码加载原语**。integrity 检查（checksum、version、ABI、profile）只防篡改，**不**防恶意源。任何能调用 `load_bytecode` 的路径——下载的 .qbc、网络 fetch、bundle 资源——都会获得与 runtime 同样的能力：在 `node_compat` 装好的 runtime 里，fs/child_process/http/mysql/sqlite 全开，没有签名、没有 allowlist、没有 per-module capability、没有"safe mode"。

建议：
- 文档里把 `load_bytecode` 标为"接收完全可信的字节码"（已是"trusted vjsx CommonJS bytecode artifact"），并把"信任"含义写明。
- 加 `runtime_profile: 'sandboxed'`（不带 node_compat），同时对 `JS_SetMemoryLimit`/`JS_SetMaxStackSize` 做严格限制。
- 或引入可选的 bytecode 签名/校验链（HMAC、x509 等）。

### H-4. `bytecode.v` 第 174-176 行 + 第 172 行 — Checksum 验证前做了大块 `clone()`

```v
payload := data[header_size..].clone()           // 先 memcpy 整块 payload
expected_checksum := data[32..64]
if bytecode_checksum(payload) != expected_checksum { ... }   // 再 hash 整块
```

`clone()` 把 payload 复制进 V 管理内存，紧接着 SHA-256 又对整块跑一遍。如果 checksum 失败，多倍峰值内存浪费，**且 OOM DoS 路径**：恶意 .qbc 可以塞 200 MB 随机字节，让 vjsx 在拒绝之前先 clone + hash 400 MB。

修复顺序：先做 magic/format/length 校验 → 再 checksum 验证 → **最后**才 slice/clone payload。校验失败的字节流不应被 memcpy。

### H-5. `cli_runner_bin/main.v` `parse_env_options()` — `VJS_SCRIPT_FILE`/`VJS_ARGS_FILE`/`VJS_CLI_CWD` 直接执行未校验路径

```v
fn parse_env_options() ?CliOptions {
    file := os.getenv('VJS_SCRIPT_FILE')
    args_file := os.getenv('VJS_ARGS_FILE')
    ...
}
fn main() {
    if cli_cwd := os.getenv_opt('VJS_CLI_CWD') {
        if cli_cwd != '' {
            os.chdir(cli_cwd) or { fail(err.msg()) }   // ← 没 real_path/存在性检查
        }
    }
    ...
}
```

任何能影响这些环境变量的进程（CI 注入、dotenv loader、容器 sibling 进程）都能让 vjsx：
- `VJS_CLI_CWD` 改变工作目录，从而改变 `package.json` 路径 → 加载恶意 `package-lock.json`。
- `VJS_SCRIPT_FILE` 直接执行任意 .js。
- `VJS_ARGS_FILE` 把任意行作为脚本参数。

**且 env 路径会绕过**显式 CLI 的 `--module`/`--runtime` 校验（`parse_env_options` 返回时跳过 line 376-435 的校验分支，默认 `'node'` runtime——`fs`/`child_process`/`http`/`mysql`/`sqlite` 全开）。

修复：
- 加 `--no-env` 开关显式禁用 env-based 启动。
- 对 `VJS_SCRIPT_FILE` 做 `os.real_path` + 必须存在的强制检查，并在 docs 顶部加"Do not set `VJS_SCRIPT_FILE` in untrusted environments"红色警告。
- 至少在 `parse_env_options` 出口处对 `runtime_profile` 做白名单校验（`['node','script','browser']`），不要让 env 路径绕过。

### H-6. `cli_runner_bin/npm_install.v` 整段 — 包安装不接受 URL scheme 白名单

```v
// line 511-520
fn normalize_registry(registry string) string {
    mut trimmed := registry.trim_space()
    if trimmed == '' { trimmed = 'https://registry.npmjs.org' }
    ...
    return trimmed
}

// line 749
resp := http.fetch(url: url, method: .get)!
```

- `--registry http://...`：`http.fetch` 走明文 HTTP，registry 响应可被中间人替换。
- `--registry file://...`：`file://` URL 让 `fetch_tarball`/`fetch_metadata` 直接读本地文件，绕过任何 https 假设。
- `--registry gopher://...` / 其他 scheme：`http.fetch` 行为未定义，可能 crash。
- `VJSX_NPM_REGISTRY` 同样不经任何校验直接喂给 `normalize_registry`（`main.v:236`）。

修复：`normalize_registry` 强制 `starts_with('https://')`（或 `http://` 仅在 CI 显式 opt-in 时允许）；`fetch_tarball` 对每个 tarball URL 单独做 scheme 校验。

### H-7. `cli_runner_bin/npm_install.v` `install_workspace` / `install_locked_package` — 包名/symlink 路径无校验

```v
// line 857-863
fn package_install_path(root string, name string) string {
    if name.starts_with('@') {
        parts := name.split('/')
        return os.join_path(root, 'node_modules', parts[0], parts[1])
    }
    return os.join_path(root, 'node_modules', name)
}

// line 647
os.symlink(workspace.path, target)!    // workspace.path 来自 package.json

// line 677
os.symlink(lock_pkg.resolved, target)!  // resolved 来自 lockfile
```

恶意 `package.json` 里 `"dependencies": {"../../../etc/passwd": "*"}` 直接 `os.join_path` 出 `node_modules/../../../etc/passwd`，后续 `extract_npm_tarball` 会写文件。`install_workspace` 和 `install_locked_package` 里的 `os.symlink` 也信任 `workspace.path` 和 `lock_pkg.resolved`——lockfile `resolved: "/etc"` 会让 `node_modules/foo` 变成指向 `/etc` 的符号链接，所有 `require('foo/...')` 走 `/etc`。

**修复**：
1. 入口加包名校验（`is_valid_package_name`）：禁止 `..`、绝对路径前缀、`\`、超过 214 字符、scoped 包必须恰好一个 `/`。
2. `install_workspace` 的 `workspace.path` 必须是 `os.real_path` 后的子目录且在 `installer.root` 之下。
3. `lock_pkg.resolved` 如果是 `file://` URL 必须做 containment 检查；如果是相对路径必须 resolve 后落在 `installer.install_root` 之内。

### H-8. `cli_runner_bin/npm_install.v` `install_locked_package:688` — 信任 lockfile 的 `resolved` URL

```v
archive := installer.fetch_tarball(lock_pkg.resolved)!
```

`lock_pkg.resolved` 直接来自 `package-lock.json`，可以是任意 URL。结合 H-6 的 scheme 不限 → 投毒的 `package-lock.json` 可以让 vjsx `repair` 时下载任意 URL 的 tarball。

修复：`fetch_tarball` 对 lockfile 路径做 scheme 校验（只允许 `https://`），并对所有 `integrity` 字段强制要求 `sha512-`（目前 line 1338 缺失则静默跳过——应改为缺失即报错）。

### H-9. `cli_runner_bin/npm_install.v` `extract_npm_tarball` — 自实现 tar 解析器

```v
mut name := tar_string(header[0..100])
prefix := tar_string(header[345..500])
if prefix != '' { name = '${prefix}/${name}' }
...
rel := npm_tar_rel_path(name)
if rel != '' {
    out_path := os.join_path(target, rel)
    if typeflag == `5` {
        os.mkdir_all(out_path)!
    } else if typeflag == `0` || typeflag == 0 {
        os.mkdir_all(os.dir(out_path))!
        os.write_file_array(out_path, raw[offset..payload_end])!
    }
}
```

`npm_tar_rel_path` 第 1418-1428 行过滤了 `..` 路径，但解析器本身有多个问题：

1. **`tar_octal` 第 1400-1408 行**：`size` 是 `int`（31-bit）。`size` 字段理论最大 8 GB，溢出会得到负数，然后 `payload_end = offset + size` 比较失败或绕过（与 H-1 同类问题）。应显式拒绝 `size < 0`。
2. **符号链接条目（typeflag = `'2'`）静默跳过**——现代 npm 包少用，但应该报错（"unsupported tar entry type"）而不是默默忽略。
3. **硬链接条目（typeflag = `'1'`）静默跳过**——同上。
4. **没有 pax extended header (typeflag = `'x'` / `'g'`)**——现代 npm 会用，忽略会导致文件名截断。
5. **目录条目 mode 默认 0755，文件条目 0644**——读不到 `header[100..108]` 的 mode 字段，导致 npm 包的 `0755` 脚本变成 0644。
6. **`out_path` 没有 resolve 后 containment check**——理论上 `npm_tar_rel_path` 已经过滤了 `..`，但 `..` 之外的非常规路径仍有 risk。

### H-10. `host_child_process.v` `child_process.fork()` 第 1268-1283 行 — 读取 `VJS_REPO_ROOT` 而 JS 可写该变量

```v
fn child_process_default_fork_exec_path() !string {
    if repo_root := os.getenv_opt('VJS_REPO_ROOT') {
        candidate := os.join_path(repo_root, 'vjsx_cli')
        if os.exists(candidate) {
            return candidate
        }
    }
    return error(...)
}
```

`VJS_REPO_ROOT` 通过 `os.getenv_opt` 读，但因为 C-4（env 可写），JS 可以先 `process.env.VJS_REPO_ROOT = '/tmp/evil'; execSync('cp /tmp/evil vjsx_cli')`，再 `child_process.fork(...)` ——fork 直接执行 `/tmp/evil`（vjsx_cli）。**这是单点 RCE 路径**。

修复：fork exec path 在 runtime 启动时 resolve 一次并 freeze，不再每次 `getenv`；或加 allowlist 验证可执行文件路径前缀。

### H-11. `host_fs.v` `write_target_path` 第 19-27 行 — 路径不约束在 `roots` 内

```v
fn write_target_path(path string, roots []string) string {
    if os.is_abs_path(path) { return path }      // 绝对路径直接放行
    if roots.len > 0 { return os.join_path(roots[0], path) }
    return path
}
```

`writeFileSync`/`mkdir`/`rename` 等都走这个函数。绝对路径（例如 `/etc/cron.d/x`）完全绕开 `roots` 沙箱。`os.join_path(roots[0], "../../etc/passwd")` 同样能逃出 roots。

**修复**：在 `write_target_path` 末尾加 containment check：
```v
resolved := os.real_path(result)
for root in roots {
    if resolved.starts_with(os.real_path(root) + os.path_separator) { return resolved }
}
return error("path is not within roots: ${path}")
```

### H-12. `host_http.v` `get()` 第 92-98 行 + `host_fetch.v` — `http.fetch` 无 scheme/host 白名单

```v
url := args[0].str()
...
resp := http.fetch(method: .get, url: url, allow_redirect: false) or { ... }
```

`url` 可以是 `file://`、`gopher://`、内网 IP、169.254.169.254（云元数据服务）。`allow_redirect: false` 是好的，但 `host_fetch` 路径第 108-110 行的 curl 回退用 `-L`——会跟随重定向到任意 host。

**SSRF** 路径：JS 一行 `http.get('http://169.254.169.254/latest/meta-data/iam/security-credentials/')` 就能拿到云上 EC2/ECS 的 IAM 凭据。

修复：`install_http_like_module` 接受 `url_allowlist: []string` 配置；`fetch_core_run_curl` 在重定向后再次校验 `--max-redirs 1` 并校验每个重定向的 scheme/host。

### H-13. `host_mysql.v`/`host_sqlite.v` — `params.len == 0` 时回退到 raw query

```v
result := if params.len == 0 {
    conn.db.query(query_text) or { ... }   // 原样执行 JS 字符串
} else {
    conn.db.query(query_text, ...params) or { ... }
}
```

Node.js `mysql.query()` 行为相同（无参时直接执行），但**不**意味着这里也该这样。JS 层如果忘了 `?` 占位符，SQL injection 直接生效。`host_sqlite.v:158-164` 同模式。

修复：在 zero-params 分支对 `query_text` 做轻量 SQL 静态检查，或文档里加红色警告，或在 query API 上加 `?` 占位符必须 ≥ 1 的硬约束。

### H-14. `host_child_process.v` `child_process_apply_shell` 第 1035-1041 行 — `command` 不被转义

```v
fn child_process_apply_shell(command string, args []string, options ChildProcessSyncOptions) (string, []string) {
    if !options.use_shell { return command, args }
    command_line := child_process_shell_command_line(command, args)
    return child_process_shell_command(command_line, options.shell)
}
```

`command`（可执行文件名）拼到 shell 命令行时**完全没转义**。`spawn('ls; rm -rf /', [], {shell: true})` 会被 sh 解析为两条命令。

修复：至少把 `command` 也走 `child_process_shell_escape_arg`；但更好的是去掉 `use_shell` 选项，仅支持 `exec`/`execSync` 走 shell。

### H-15. `host_http.v` `http_response_object.pipe` 第 47-76 行 — pipe 目标路径由 JS 控制

```v
path_value := dest.get('_vjsxPath')
...
target := path_value.str()
...
fs_append_bytes(target, body_bytes) or { ... }
```

JS 可以 `http.get('https://x/y').pipe(fs.createWriteStream('/etc/cron.d/foo'))` ——`createWriteStream` 的 path 来自 JS，pipe 不做任何校验。结合 H-11 的 `write_target_path` 不约束 roots，构成 SSRF → 任意文件写。

修复：pipe 之前校验 `dest._vjsxPath` 在 `roots` 范围内。

---

## Medium（建议修复）

### M-1. `bytecode.v` 第 173-176 行 — Checksum 验证在 payload 拷贝前发生，OK；但 `clone()` 之前没大小上限

应增加 `if artifact.payload.len > max_artifact_size { return error(...) }`，建议 256 MB。

### M-2. `runtime.v` 第 15 行 — `pub const version = '0.0.2'` 与 `v.mod` 中的 `0.0.3` 不一致

`runtime.v` 里 `pub const version = '0.0.2'`。`vjsx.version` 被 `cli_runner_bin/main.v` 第 7 行（`const cli_version = vjsx.version`）和字节码 checksum 流程使用，但 `v.mod` 和 `cli_runner_bin` 二进制（commit `7124e07` 已经 bump 到 0.0.3）显示的是 0.0.3。这会导致 `ctx.load_bytecode` 拒绝当前 runtime 编译的字节码（`artifact.vjsx != version`）。**严重的功能 bug**——本次 commit bump 到 0.0.3 时漏改了这里。

### M-3. `value.v` 第 131-146 行 — `error_field_string` 缺少递归防护

```v
fn (v Value) error_field_string(key string) string {
    field := v.get(key)
    defer { field.free() }
    if field.is_exception() { ... }
    ...
}
```

恶意代码可以写一个 getter，触发 `to_error()` → `get('name')` → 抛异常 → 调 `js_exception_value()` → 又返回对象 → 又调用 `to_error()`... 因为是同步执行且 `ctx.js_exception_value` 只 retrieve 一次，没看到无限循环路径，但 `field.to_string()` 在 `field` 是带 getter 的对象时可能再次抛出。建议在 `to_error` 入口加一个"`currently converting`标志位。

### M-4. `host_fs.v` `readdir_sync` / `readdir` 第 297-327、485-498 行 — 符号链接未跟随或限制

`os.ls` 在大多数实现里对符号链接是 follow 行为，目录里含 symlink 时 `os.ls` 会列出 symlink 目标的内容。`readdir` 暴露给 JS 的是"路径名"，可能与实际可访问的目录不同。需要在 `readdir` 中显式 `os.is_link` 过滤或文档化。

### M-5. `host_fs.v` 第 559-569 行 — `chmodSync` 模式值未做范围校验

```v
mode := if args[1].is_number() { args[1].to_int() } else { args[1].str().int() }
os.chmod(target, mode) or { ... }
```

JS 传入 `-1` 或 `99999` 会被传给 libc `chmod()`，可能产生意外行为（例如 `chmod(target, 0o7777)` 在某些平台会启用 setuid）。建议 `mode & 0o7777` 截断。

### M-6. `host_fs.v` `fs_create_write_stream` 第 143-204 行 — 多个 V→JS 闭包持有 `&HostCleanupState` 引用，但 cleanup 顺序未保证

`on_fn`/`write_fn`/`close_fn` 各自把 `ctx` 闭包捕获。如果 `Context` 先于闭包被 `free()`，后续 timer 触发会 use-after-free。建议在每个 stream 闭包里持有 `ctx.ref` 的引用计数。

### M-7. `host_child_process.v` 全文 — `unsafe { goto reject }` 模式

在 `host_fs.v` `read_file`/`write_file`/`exists_fn`/`mkdir_fn`/`readdir_fn`/`rm_fn`/`stat_fn`/`copy_file_fn`/`rename_fn`/`read_json_fn`/`write_json_fn` 全部使用 `unsafe { goto reject }` 跳出 promise reject 路径。

```v
path := args[0].str()
...
unsafe { goto reject }
```

这种写法在 V 语言里 `unsafe { goto }` 是合规的，但容易出错：新增校验分支时必须确保 `goto reject` 之前没有资源泄漏。**应该抽出一个 helper**（例如 `fn reject_promise(ctx, promise, mut err Value, msg string) !`）。

### M-8. `host_sqlite.v` / `host_mysql.v` — `query_text` 字符串作为 cache key 哈希表

`stmt.cache_key = query_text`——长查询会复制整段 SQL 到每个 stmt 里。考虑用 `fnv1a(query_text)` 之类短哈希当 key。

### M-9. `value.v` 第 100-129 行 — `to_error` 入口不再 require `is_error()`，可能误报

`to_error` 现在对任意 thrown 值都返回 `&JSError`，包括 thrown 数字 `42`。这本身是 e48c138 提交的设计选择（更友好），但应文档化。

### M-10. `context.v` 第 67-94 行 — `type_global` 等常量直接导出 `C.JS_EVAL_TYPE_GLOBAL`

quickjs-ng 中这些 flag 是 `int`，在 V 端转成 `pub const int = ...`，用户使用 `ctx.eval(code, vjsx.type_module)` 时要传 `int`。**没问题但应统一**：所有 `flag` 参数可考虑改成 named struct 或 enum 类型。

### M-11. `function.v` `js_class` 111 行 — `rand.u32n(1000)` 选 class ID

`1000` 个 class ID 中重复概率不可忽略。`JS_NewClassID` 内部会检查冲突并拒绝，但用户调用不会知道。建议给一个冲突后重试的循环。

### M-12. `npm_install.v` `parse_package_spec` 第 549-578 行 — 解析 scoped 包时只取 `last_index('@')`

`@org/pkg@next` 解析为 name=@org/pkg, tag=next 是 OK 的，但如果版本是 dist-tag 包含 `@`（实际不会出现）会出错。边界用例。

### M-13. `npm_install.v` `lock_package_key` 第 934-936 行 — 包名直接拼到路径里

如果 `name` 来自被入侵的 `package.json`（含 `..`/`/./`/`\\`），整个 lockfile 会被污染。`package_install_path` 在第 857-863 行做 `os.join_path`，**会接受 `'../foo'` 这样的名字**。**强烈建议在 `install_spec` 入口验证包名是合法的 npm name 格式**。

### M-14. `host_child_process.v` `child_process_call_this` 第 280-288 行 — `ctx.c_val` 引用未释放

`args` 是 V slice，不在这里 leak。`callback` 和 `this` 也是参数。但 `ctx` 通过 `&Context` 借用，没问题。**不过 `c_args` 数组在函数返回后会被 V GC 释放——但其持有的 `C.JSValue.ref` 是 dup 过的 JS 引用，**如果 JS 端已经 throw，这些 ref 不会被自动 free（dup 是计数 +1 的）。建议函数退出前手动 `JS_FreeValue` 全部 `c_args`（除了被 JS_Call consume 掉的）。

### M-15. `host_runtime_globals.v` 第 15-22 行 — `structuredClone` 用 JSON round-trip

任何 JSON 不接受的值（`undefined`/`Function`/`Symbol`/循环引用）会丢失或抛错，**这与 spec 不符**（spec 要求保留 `undefined`）。

### M-16. `libs/include/vjsx_quickjs_compat.h` 第 39-69 行 — `vjsx_js_eval_out` 用 libc `malloc`/`free` 而非 `js_malloc`/`js_free`

`js_malloc` 走 QuickJS 自己的分配器，会被 `JS_SetMemoryLimit` 计入；`malloc` 走 libc，不计入 OOM 限制。**长跑 runtime 跑 N 次 eval，每次都泄露到 JS 内存限制之外**。同时任何 `JS_SetMemoryLimit` 的 OOM 钩子也看不到这部分分配。

修复：把 shim 里的 `malloc/free` 替换为 `js_malloc/js_free`。

### M-17. `host_fetch.v` `fetch_proxy_env` 第 83-91 行 — 隐式 trust 环境变量

`HTTPS_PROXY` 大写变体应该被尊重。当前遍历顺序 OK。`all_proxy`/`ALL_PROXY` 是 golang 习惯，可以删以减小 attack surface。

### M-18. `cli_runner_bin/npm_install.v` `parse_package_spec` `name` 字段没长度限制

包名长度上限 214 是 npm 规范。当前 `parse_package_spec` 没有任何长度检查。

### M-19. `cli_runner_bin/npm_install.v` 全文 — TOCTOU between `os.exists` and `os.read_file`

`main.v:596-599`（`run_script`）和 `npm_install.v` 多个地方 `os.exists(path)` 然后 `os.read_file(path)` 没有 race 防护。symlink swap 攻击窗口。

### M-20. `host_child_process.v` `child_process_run` — 同步路径没有 timeout

```v
proc.run()
...
proc.wait()    // 没设超时，挂起的子进程永远等
```

JS 启动一个 hang 的子进程会无限阻塞。

### M-21. `host_child_process.v` `child_process_emit` 整段 — `or { ctx.js_undefined() }` 静默吞 callback 错误

`setTimeout` 失败、callback dispatch 错误、finish 错误全部被静默。隐藏真实 bug。

### M-22. `cli_runner_bin/main.v` 第 230-231 行 — `compile` 子命令 `-o` 路径未约束 cwd

```v
output_file := if os.is_abs_path(opts.output_file) {
    opts.output_file
} else {
    os.join_path(os.getwd(), opts.output_file)
}
```

可以写 `.bashrc`、`.git/hooks/pre-commit`、`.ssh/authorized_keys`。**CLI 信任模型的一部分，docs 必须明确 `-o` 是 host-trusted 输入**。

---

## Low（清理 / 风格）

### L-1. `host_fs.v` `fs_create_write_stream` — `_vjsxFinished` / `_vjsxClosed` 字段带前缀但没注册到 cleanup

私有字段命名一致，可以接受。但闭包对 `ctx` 的捕获在 `Context` 关闭后无法清理。

### L-2. `cli_runner_bin/main.v` `parse_args` — 重复的 `--help` 处理块

在 `parse_args` 中有 5 处 `if arg in ['--help', '-h', 'help']`。可以抽成 helper。

### L-3. `host_child_process.v` 整个文件 2065 行 — 重复的 `child_process_poll_live` 终结块

```v
if was_killed { ... }
if idle_polls >= 5 { ... }
if !proc.is_alive() { ... }
```

每个分支结尾都有同样的 `proc.wait() → 读 stdout/stderr → emit 'end'/'close' → finish piped → proc.close()`，可抽 `fn finalize_live_process(...)`。

### L-4. `runtime.v` `version` 字符串（已在 M-2 提及）

`pub const version = '0.0.2'` 应同步到 `0.0.3`。

### L-5. `bytecode.v` `bytecode_profile_name` 错误信息未暴露当前已知值

`return error('unsupported bytecode runtime profile id: ${profile}')`——应该附 `expected: ${bytecode_profile_node}/${bytecode_profile_script}/${bytecode_profile_browser}`。

### L-6. `host_child_process.v` `child_process_buffer_value` 第 237-247 行 — `Uint8Array` 名字硬编码

`uint_cls := ctx.js_global('Uint8Array')` 在用户改写 `globalThis.Uint8Array` 后会拿到 undefined。建议从 `ArrayBuffer` 的 `Symbol.species` 派生。

### L-7. `npm_install.v` `verify_integrity` 第 1337-1346 行 — `sha512-` 前缀大小写不敏感

`SHA512-`（大写）应被拒绝。npm 行为是大小写敏感接受 `sha512-`。

### L-8. 大量 `or {}` 静默吞错

`host_mysql.v` / `host_sqlite.v` 里的 `or {}`（如 `mysql_rollback_transaction(mut conn) or {}`）可能掩盖关键错误。

### L-9. `host_fetch.v` `fetch_proxy_env` 第 83-91 行 — 代理检测通过环境变量

建议在 `FetchGlobalsConfig` 里加 `proxy: 'none' | 'env' | 'explicit_url'` 显式开关。

### L-10. `value.v` `to_string` 在 V `JS_ToCString` 失败时的 fallback

`v.is_array()` 和 `v.is_object()` 在 `ptr == nil` 时还安全吗？没在注释里说明。

### L-11. `host_intl.v` 第 14-16 行 — `t.local()` on 攻击者控制的 ms

传 `Number.MAX_SAFE_INTEGER` 或 `NaN` 在 V 的 time 模块可能 throw 或 wrap around。Guard overflow。

### L-12. `host_child_process.v` 全文 — `child_process_shell_escape_arg` Windows 分支不安全

`arg.replace('"', '\\"')` 然后用 `"…"` 包起来 **不是** cmd.exe 的 quoting 算法。cmd 只在 `\\` 或闭合 `"` 前把 `\` 当作 escape。攻击者控制输入 + Windows shell=true 可突破。

### L-13. `runtime_assets.v:251-253, 287, 304-323, 325-342` — `VJSX_ASSET_ROOT` env 变量可重定向

`resolve_runtime_asset_path` + 嵌入式 module loader 可被 env 重定向，加载 attacker-controlled JS 当 `vjsx://web/js/...` 模块。Override path 读 root 下任意文件，无校验。

### L-14. `vjsx_cli.vsh:34, 58` — `os.execute` 配合 `shell_quote` 但 work_root 来自 `VJS_CLI_CWD` (env)

shell command 用 `shell_quote` 组装，但 `work_root` 来自 `VJS_CLI_CWD` (env)。如果将来重构成不 quote，立即 shell injection。

### L-15. `host_child_process.v` `child_process_event_emitter` 大量 field 复制

`emitter` 的每个 `on`/`once`/`emit` 都 `events.get/set/free` 来回。考虑把 events 存到 V map 里而不是 JS object 上以减少 alloc。

### L-16. `host_mysql.v:1208-1255` `mysql.connect` 默认 `host='127.0.0.1'` 但接受 `unix:/...` 连接串

不验证连接串格式。`unix:/etc/passwd` 会被 MySQL 驱动尝试连接。

### L-17. `host_runtime_globals.v:15-21` — `structuredClone` 经 `eval` 实现

`eval` + JSON 串本身安全（JSON 不含可执行代码），但 pattern 是 footgun。`ctx.json_parse(text)` 即可。

---

## 测试覆盖观察

- `tests/bytecode_test.v` 覆盖了核心路径（round-trip、profile 不匹配、corruption、format mismatch）——足够。
- `tests/host_fetch_deadline_test.v` / `tests/host_mysql_runtime_test.v` 等使用真实网络/数据库——CI 必须能访问这些外部资源；建议加 mock。
- `tests/main_test.v` / `tests/run_test.v` 是 smolktest 入口，但具体覆盖范围需要展开。
- **没有 fuzzing 或 prop-based tests**。`host_fs.v` 路径拼接、`npm_install.v` 包名解析、`bytecode.v` header parsing 都是 fuzz 的好目标。
- 集成测试覆盖较少。`examples/` 下有 9 个示例但主要是 demo，不是 conformance。

---

## 推荐优先级

| 优先级 | 数量 | 项目 |
|---|---|---|
| Critical | 5 | C-1, C-2, C-3, C-4, C-5 |
| High | 15 | H-1 ... H-15 |
| Medium | 22 | M-1 ... M-22 |
| Low | 17 | L-1 ... L-17 |

**最优先的 3 件事**：
1. **修复 C-4**（`process.env` env 写权限）— 5-10 行代码：denylist `LD_PRELOAD`/`DYLD_*`/`PATH`/`*_PATH`/`NODE_OPTIONS`，或默认不安装 `__vjs_process_env_set/_unset`。这是单点最严重的权限缺口，与 C-3/C-1 串联成 RCE。
2. **修复 C-1**（`unsafe { free(name_ptr) }`）— 5-10 行代码：在 C shim 里加 `vjsx_js_strdup_owned`，V 端用 `unsafe { C.vjsx_js_strdup_owned(cls.name.str) }`。避免随机崩溃。
3. **修复 M-2**（version 字符串与 v.mod 不一致）— 1 行代码，把 `runtime.v:15` 改成 `'0.0.3'`。本次 commit bump 0.0.3 时漏改了，会让 `ctx.load_bytecode` 拒绝当前 runtime 自己编译的字节码。**功能 bug**。

接下来再处理：
4. **H-1 + H-2 + H-4**（bytecode payload size + 内存释放顺序 + checksum 顺序）— 一个 PR 全解决。
5. **C-5**（`fetch` URL 以 `-` 开头）— 1 行代码：`args << '--'`。
6. **H-5**（env-var-based 启动）— 加 `--no-env` 开关 + 对 `VJS_SCRIPT_FILE` 做 `real_path` 校验。

---

## 文档/项目成熟度观察

- README.md (32 KB) 写得非常详细，覆盖安装/嵌入/host API 入门。
- `docs/EMBEDDING.md` 和 `docs/RUNTIME_CONTRACT.md`（commit `7178327` 引入）显示项目对 FFI 边界有自觉。
- 但**没有**显式 SECURITY.md / threat model 文档。建议添加：
  - 哪些 host API 接受"untrusted JS input" vs "trusted host input"
  - "半沙箱"模型：`script_dir` 是不可信边界
  - `load_bytecode` 的信任模型（接收完全可信的字节码）
  - `child_process.use_shell` 等价于 `shell_exec` 的红色警告
  - `process.env` 的能力范围

- 项目结构清晰：`vjsx/` 核心 + `runtimejs/` JS 端 + `host_*.v` host API + `cli_runner_bin/` CLI。前后端职责分明。

- 缺乏 fuzz/property-based test 基建——`bytecode.v` 的 parser、`npm_install.v` 的 tar parser、`host_fs.v` 的 path resolver 都是 fuzz 的好目标。

- 没有 CI 中跑的安全检查（依赖 audit、gosec、trivy 之类的扫描）。

---

## 总结

整体上 `vjsx` 是一个**高质量**的 V→quickjs-ng 绑定实现，所有权约定、内存边界、API 设计都经过认真考虑。但作为一个**"embedded scripting engine"**产品，最需要补的是**安全模型文档化 + 危险 API 的显式开关**——比如把 `process.env` 写权限、`use_shell`、`load_bytecode` 列为"高级"特性，需要 host 显式 opt-in。这是 Node.js/Deno/Bun 都在做的事情（用 `--permission` flag 或类似机制）。

最关键的三件事按修复成本/收益比排序：
1. `process.env` 加 denylist（5 行）— 关掉 RCE 大门
2. `js_class` 修 `free(name_ptr)`（10 行）— 关闭崩溃路径
3. 修 `version` 字符串（1 行）— 关闭自产字节码被拒的功能 bug
