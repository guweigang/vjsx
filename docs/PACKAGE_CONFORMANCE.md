# Real-Package Conformance Policy

vjsx does not claim general Node.js or npm compatibility. A named third-party
package is verified only when a pinned fixture exercises it in CI against local,
deterministic services.

## Maintained fixtures

| Fixture | Pinned packages | CI owner | Covered behavior |
| --- | --- | --- | --- |
| `tests/integration/openai_sdk` | `openai@6.34.0`, `ai@6.0.168`, `@ai-sdk/openai-compatible@2.0.41` | vjsx maintainers | model listing, chat completion, OpenAI streaming, AI SDK generation and streaming |
| `tests/integration/pi_durable` | `@earendil-works/pi-durable@1.6.1` | vjsx maintainers | SQLite and JSONL checkpoints, process kill during an offline model request, recovery of the same submission, JavaScript tool call and final answer. JSONL also covers recovery from a partial final line. |

The fixtures run on Ubuntu x64 in the pull-request matrix. The OpenAI SDK
fixture uses a local mock HTTP server. The Pi Durable fixture uses an in-process
model mock and a vjsx binary built with `-d vjsx_sqlite`.

## GitHub CI functional regression plan

The four scenarios below are planned for functional regression coverage in
GitHub Actions. The table records existing evidence and the behavior each
test should cover. Implementation of any missing fixtures and workflow
integration is deferred. Release gating is deferred pending a separate decision.

| Scenario | Packages | Existing evidence | Functional regression to cover |
| --- | --- | --- | --- |
| URL to Markdown | Defuddle (`defuddle/node`) and `linkedom` | An earlier vjs run extracted a title and Markdown from a saved WeChat article. The historical run used an external download step. The [CLI examples](../README.md#cli) also mention Defuddle. | Fetch a local HTTP article through vjsx, parse its HTML with LinkeDOM, and assert the Markdown title, body, and links produced by Defuddle. Pin both packages when a fixture is added. |
| Stock quotes | `stock-sdk` | The repository has an [offline quote pipeline probe](../tests/stock_sdk_step4_pipeline.mjs) and a [live quote probe](../tests/stock_sdk_live_test.mjs), both using a previously installed local package. The [stock demo lockfile](../examples/stock_demo/package-lock.json) resolves version `2.4.1`. | Use a fixed GBK quote response and assert the decoded name, symbol, price, and timezone conversion. |
| Feishu message channel | Satori `@satorijs/adapter-lark@3.12.6` and `@satorijs/core@4.6.0` | The [Satori validation](websocket-host.md#satori-integration) records local gateway discovery, WebSocket events, and protobuf acknowledgements. The [employee messaging fixture](../tests/integration/satori/run-employee.py) also checks replies and proactive sends. | Exercise message receipt, acknowledgement, reply, and proactive send against the local Feishu gateway and API fixtures. |
| Durable agent harness | Pi Durable `@earendil-works/pi-durable@1.6.1` | The [pinned recovery fixture](../tests/integration/pi_durable/verify.mjs) covers JSONL and SQLite and is wired into [package conformance CI](../.github/workflows/test.yml). | Recover the same submission after process termination, repair a partial JSONL record, and verify the tool call and final answer. |

## Update policy

- Package versions must be exact in `package.json` and committed in
  `package-lock.json`; moving tags and unlocked ranges are not accepted.
- Maintainers review fixture updates before each vjsx minor release and at
  least monthly while the package is named as verified.
- An update PR must run the fixture, describe newly required runtime behavior,
  and update the support boundary when a dependency stops working.
- A failing upstream upgrade does not silently broaden the Node compatibility
  layer. It is either supported with focused tests and documentation, or the
  last verified version remains listed.
- Adding another named package requires a pinned fixture, a maintainer owner,
  deterministic test services, and a CI gate.

This policy verifies the listed versions and exercised behavior only. It is not
a promise that every export or future release of those packages works.
