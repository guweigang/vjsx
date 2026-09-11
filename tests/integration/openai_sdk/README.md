# OpenAI SDK integration smoke

Pinned smoke test for real npm packages in the vjsx Node runtime profile. It is
part of the Ubuntu x64 CI gate and uses only the local mock server; no API key or
external model request is required.

It verifies:

- `openai` SDK model listing
- `openai` SDK chat completions
- `openai` SDK streaming chat completions
- AI SDK `generateText`
- AI SDK `streamText`

The dependency versions are exact in both `package.json` and
`package-lock.json`. Updates are reviewed deliberately rather than following
moving npm tags.

Run it manually from this directory:

```sh
./run.sh
```

Set `VJSX_BIN` to exercise an already-built CLI, as CI does:

```sh
VJSX_BIN=/path/to/vjsx ./run.sh
```
