# Real-Package Conformance Policy

vjsx does not claim general Node.js or npm compatibility. A named third-party
package is verified only when a pinned fixture exercises it in CI against local,
deterministic services.

## Maintained fixtures

| Fixture | Pinned packages | CI owner | Covered behavior |
| --- | --- | --- | --- |
| `tests/integration/openai_sdk` | `openai@6.34.0`, `ai@6.0.168`, `@ai-sdk/openai-compatible@2.0.41` | vjsx maintainers | model listing, chat completion, OpenAI streaming, AI SDK generation and streaming |

The fixture runs on Ubuntu x64 in the pull-request matrix. Its HTTP peer is a
repository-local mock server, so conformance does not depend on credentials or
an external API.

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
