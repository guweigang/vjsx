import { writeFileSync } from "node:fs";
import { BACKGROUND_CONTEXT as context } from "@earendil-works/chord/context";
import { createAssistantMessageEventStream } from "@earendil-works/pi-ai/utils/event-stream";
import {
  AssistantEntry,
  Harness,
  createRegistry,
  defineExtension,
  defineTool,
} from "@earendil-works/pi-durable";
import { openNodeJsonlStorage } from "@earendil-works/pi-durable/storage/jsonl/node";
import { num, obj } from "@earendil-works/pi-schema";

const [backend, dbPath, marker] = process.argv.slice(-3);
const registry = createRegistry();
let toolCalls = 0;
registry.install(defineExtension({
  name: "arithmetic",
  tools: [defineTool({
    name: "double",
    description: "Double a number",
    parameters: obj({ n: num() }),
    async execute({ n }) {
      toolCalls++;
      return { output: [{ type: "text", text: String(n * 2) }] };
    },
  })],
}));

const model = {
  api: "openai-completions", provider: "mock", id: "offline", name: "Offline",
  contextWindow: 10000, maxTokens: 1024, input: ["text"], reasoning: false,
};
const usage = {
  input: 1, output: 1, cacheRead: 0, cacheWrite: 0, totalTokens: 2,
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
};
let modelCalls = 0;
const models = {
  getModel: () => model,
  getAuth: () => undefined,
  streamSimple(_model, { messages }) {
    const stream = createAssistantMessageEventStream();
    if (marker !== "--resume") {
      writeFileSync(marker, "model dispatched");
      return stream;
    }
    const first = ++modelCalls === 1;
    if (!first && !messages.some((message) => message.role === "toolResult" && message.content[0]?.text === "42")) {
      throw new Error("missing tool result in second model request");
    }
    const message = {
      role: "assistant", api: model.api, provider: model.provider, model: model.id, timestamp: Date.now(), usage,
      content: first
        ? [{ type: "toolCall", id: "call1", name: "double", arguments: { n: 21 } }]
        : [{ type: "text", text: "42" }],
      stopReason: first ? "toolUse" : "stop",
    };
    stream.push({ type: "done", reason: message.stopReason, message });
    return stream;
  },
};

const storage = backend === "jsonl"
  ? await openNodeJsonlStorage(dbPath, context, { fsync: true })
  : await (await import("@earendil-works/pi-durable/storage/sqlite/node")).openNodeSqliteStorage(dbPath);
const harness = await Harness.open(storage, { models, registry, onReport: (report) => console.error(report) }, context);
const root = await harness.root(context, { agent: { model: { provider: model.provider, modelId: model.id } } });
const submission = await root.submit({ type: "input", content: "Double 21", requestId: "double-21" }, context);
// Keep the event loop alive while the first process is waiting for its simulated model.
const waiting = setTimeout(() => {
  console.error("timed out waiting for the submission");
  process.exit(1);
}, 20000);
try {
  const settled = await submission.wait(context);
  if (settled.status !== "done") throw new Error(JSON.stringify(settled));
  const answer = await root.commit((tx) => tx.entry(AssistantEntry, settled.answer), context);
  if (answer?.model?.[0]?.content?.[0]?.text !== "42" || modelCalls !== 2 || toolCalls !== 1) {
    throw new Error("unexpected model or tool result");
  }
  console.log(`Pi Durable ${backend} settled submission ${submission.id}: 42`);
} finally {
  clearTimeout(waiting);
  await harness.close(context);
}
