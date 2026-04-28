import OpenAI from "openai";
import { createOpenAICompatible } from "@ai-sdk/openai-compatible";
import { generateText, streamText } from "ai";

const baseURL = process.env.MOCK_OPENAI_BASE_URL || "http://127.0.0.1:19191/v1";
const client = new OpenAI({ apiKey: "test-key", baseURL });

const models = await client.models.list();
const completion = await client.chat.completions.create({
  model: "mock-chat",
  messages: [{ role: "user", content: "hello" }],
});

const chunks: string[] = [];
const stream = await client.chat.completions.create({
  model: "mock-chat",
  messages: [{ role: "user", content: "hello" }],
  stream: true,
});
for await (const chunk of stream) {
  chunks.push(chunk.choices[0]?.delta?.content || "");
}

const provider = createOpenAICompatible({
  name: "mock",
  apiKey: "test-key",
  baseURL,
});

const generated = await generateText({
  model: provider("mock-chat"),
  prompt: "hello",
});

const streamed = streamText({
  model: provider("mock-chat"),
  prompt: "hello",
});
let aiSdkStreamText = "";
for await (const part of streamed.textStream) {
  aiSdkStreamText += part;
}

const result = {
  models: models.data.map((model) => model.id),
  completionText: completion.choices[0]?.message?.content,
  streamText: chunks.join(""),
  aiSdkText: generated.text,
  aiSdkStreamText,
};

const expected = {
  models: ["mock-chat"],
  completionText: "hello vjsx",
  streamText: "hello vjsx",
  aiSdkText: "hello vjsx",
  aiSdkStreamText: "hello vjsx",
};

console.log(JSON.stringify(result, null, 2));

if (JSON.stringify(result) !== JSON.stringify(expected)) {
  console.error("unexpected OpenAI SDK integration result");
  process.exit(1);
}
