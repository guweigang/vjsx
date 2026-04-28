# OpenAI SDK integration smoke

Optional smoke test for real npm packages in the vjsx Node runtime profile.

It verifies:

- `openai` SDK model listing
- `openai` SDK chat completions
- `openai` SDK streaming chat completions
- AI SDK `generateText`
- AI SDK `streamText`

This fixture is intentionally not part of the default `v test` suite because it
requires npm dependencies.

Run it manually from this directory:

```sh
./run.sh
```
