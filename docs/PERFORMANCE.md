# Performance Baseline

`benchmarks/release_benchmark.v` measures five release-relevant paths:

- Node-profile session startup and close;
- CommonJS bytecode compilation;
- bundle load into a fresh session;
- repeated calls on an initialized module;
- host-async enqueue, settlement and microtask drain.

Run it from a clean checkout with the repository-pinned QuickJS source:

```sh
quickjs_path=$(./scripts/ensure-quickjs.sh)
VJSX_BENCH_ITERATIONS=25 VJS_QUICKJS_PATH="$quickjs_path" \
  v -prod -d build_quickjs run benchmarks/release_benchmark.v
```

Record the commit, `.v-version`, QuickJS commit, OS/architecture, CPU, compiler,
build mode, iteration count and raw output. Warm the machine once, then keep at
least five samples and compare medians. Store reviewed baselines in release
notes or attached CI artifacts; do not encode machine-independent pass/fail
latency thresholds in CI. Investigate sustained regressions on comparable
hardware, especially changes above 15%, but treat that percentage as a review
trigger rather than an automatic release failure.
