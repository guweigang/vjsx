# Pi Durable with DeepSeek

Run a text agent on vjsx with the DeepSeek provider from `pi-ai`, a `double`
tool, and JSONL session storage. The provider consumes the model's response
stream. The CLI prints the final answer after Pi Durable commits it.

From the vjsx repository root, use Node.js 22.19 or later to install the
pinned packages and initialize the local config.

```sh
npm ci --ignore-scripts --prefix examples/pi_durable_demo
test -f examples/pi_durable_demo/config.json || \
  cp examples/pi_durable_demo/config.example.json examples/pi_durable_demo/config.json
```

The template points to the official DeepSeek endpoint and selects
`deepseek-flash`. Set `DEEPSEEK_API_KEY` in your shell environment. In Bash or
Zsh, you can enter it without echoing it or putting it in your shell history.

```sh
read -rs DEEPSEEK_API_KEY
export DEEPSEEK_API_KEY
```

Run the demo with vjsx from this checkout.

```sh
./vjsx --module examples/pi_durable_demo/main.mjs \
  "$PWD/examples/pi_durable_demo/config.json" \
  "Use the double tool to double 21, then tell me the result." \
  double-21
```

The last argument is an optional request ID. Reusing it with the same config
and session directory retrieves the original submission. Omit it for a new
submission. The session path is relative to the config file. Use a fresh
directory for an independent conversation. Keep one running CLI process per
session directory. The logs contain conversation and tool output.

The demo uses the model IDs in the pinned `pi-ai` DeepSeek catalog.
`deepseek-v4-pro` is another supported config value. The official model
names and endpoint are listed in the [DeepSeek API docs](https://api-docs.deepseek.com/).
