import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { BACKGROUND_CONTEXT as context } from "@earendil-works/chord/context";
import { createModels } from "@earendil-works/pi-ai/models";
import { deepseekProvider } from "@earendil-works/pi-ai/providers/deepseek";
import { AssistantEntry, createRegistry, defineExtension, defineTool, Harness } from "@earendil-works/pi-durable";
import { openNodeJsonlStorage } from "@earendil-works/pi-durable/storage/jsonl/node";
import { num, obj } from "@earendil-works/pi-schema";

function requestArgs(argv) {
  const [configPath, prompt, requestId, ...rest] = argv;
  if (!configPath || !prompt?.trim() || rest.length) {
    throw new Error('Usage: vjsx --module main.mjs <config.json> "prompt" [request-id]');
  }
  return { configPath: resolve(configPath), prompt, requestId };
}

async function run() {
  const { configPath, prompt, requestId } = requestArgs(process.argv.slice(1));
  const { baseUrl, model, sessionDir } = JSON.parse(await readFile(configPath, "utf8"));
  if (![baseUrl, model, sessionDir].every((value) => typeof value === "string" && value.trim())) {
    throw new Error("Config requires baseUrl, model, and sessionDir strings.");
  }
  const endpoint = new URL(baseUrl);
  if (endpoint.username || endpoint.password || endpoint.search || endpoint.hash ||
      (endpoint.protocol !== "https:" && !(endpoint.protocol === "http:" && endpoint.hostname === "127.0.0.1"))) {
    throw new Error("Use an HTTPS API base URL or a local HTTP fixture at 127.0.0.1.");
  }
  if (!process.env.DEEPSEEK_API_KEY?.trim()) {
    throw new Error("Set the DEEPSEEK_API_KEY environment variable before starting the demo.");
  }

  const deepseek = deepseekProvider();
  const catalog = deepseek.getModels().map((entry) => ({ ...entry, baseUrl }));
  const models = createModels();
  models.setProvider({ ...deepseek, baseUrl, getModels: () => catalog, getAllModels: () => catalog });
  if (!models.getModel(deepseek.id, model)) {
    throw new Error(`Unknown model ${model}. The pinned DeepSeek catalog includes ${catalog.map((entry) => entry.id).join(", ")}.`);
  }

  const registry = createRegistry();
  registry.install(defineExtension({
    name: "arithmetic",
    tools: [defineTool({
      name: "double",
      description: "Return twice the supplied number.",
      parameters: obj({ n: num() }),
      async execute({ n }) {
        if (!Number.isFinite(n * 2)) throw new RangeError("The doubled value is outside the supported range.");
        return { output: [{ type: "text", text: String(n * 2) }] };
      },
    })],
  }));

  const storage = await openNodeJsonlStorage(resolve(dirname(configPath), sessionDir), context, { fsync: true });
  const harness = await Harness.open(storage, { models, registry }, context);
  try {
    const root = await harness.root(context, {
      agent: { model: { provider: deepseek.id, modelId: model }, thinkingLevel: "off" },
    });
    const submission = await root.submit({
      type: "input", content: prompt, ...(requestId === undefined ? {} : { requestId }),
    }, context);
    const outcome = await submission.wait(context);
    if (outcome.status !== "done" || outcome.type !== "input") {
      throw new Error(`Submission ${submission.id} failed: ${outcome.reason ?? outcome.status}`);
    }
    const answer = await root.commit((tx) => tx.entry(AssistantEntry, outcome.answer), context);
    const text = answer?.model?.flatMap((message) =>
      message.content.filter((part) => part.type === "text").map((part) => part.text)
    ).join("\n");
    if (!text) throw new Error(`Submission ${submission.id} returned no text.`);
    console.log(text);
  } finally {
    await harness.close(context);
  }
}

try {
  await run();
} catch (error) {
  console.error(error?.message ?? String(error));
  process.exit(1);
}
