import http from "node:http";

const port = Number(process.env.MOCK_OPENAI_PORT || "19191");

function writeJson(res, status, body) {
  res.writeHead(status, {
    "content-type": "application/json",
    "x-request-id": "req_mock_123",
  });
  res.end(JSON.stringify(body));
}

const server = http.createServer((req, res) => {
  if (req.method === "GET" && req.url === "/v1/models") {
    writeJson(res, 200, {
      object: "list",
      data: [{ id: "mock-chat", object: "model", created: 0, owned_by: "mock" }],
    });
    return;
  }

  if (req.method === "POST" && req.url === "/v1/chat/completions") {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
    });
    req.on("end", () => {
      const payload = JSON.parse(body || "{}");
      if (payload.stream) {
        res.writeHead(200, {
          "content-type": "text/event-stream",
          "cache-control": "no-cache",
          connection: "keep-alive",
          "x-request-id": "req_mock_stream_123",
        });
        res.write('data: {"id":"chatcmpl_mock","object":"chat.completion.chunk","created":0,"model":"mock-chat","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}\n\n');
        res.write('data: {"id":"chatcmpl_mock","object":"chat.completion.chunk","created":0,"model":"mock-chat","choices":[{"index":0,"delta":{"content":"hello"},"finish_reason":null}]}\n\n');
        res.write('data: {"id":"chatcmpl_mock","object":"chat.completion.chunk","created":0,"model":"mock-chat","choices":[{"index":0,"delta":{"content":" vjsx"},"finish_reason":null}]}\n\n');
        res.write('data: {"id":"chatcmpl_mock","object":"chat.completion.chunk","created":0,"model":"mock-chat","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}\n\n');
        res.end("data: [DONE]\n\n");
        return;
      }
      writeJson(res, 200, {
        id: "chatcmpl_mock",
        object: "chat.completion",
        created: 0,
        model: payload.model || "mock-chat",
        choices: [
          {
            index: 0,
            message: { role: "assistant", content: "hello vjsx" },
            finish_reason: "stop",
          },
        ],
        usage: { prompt_tokens: 1, completion_tokens: 2, total_tokens: 3 },
      });
    });
    return;
  }

  writeJson(res, 404, { error: { message: "not found", type: "invalid_request_error" } });
});

server.listen(port, "127.0.0.1", () => {
  console.log(`mock-openai listening http://127.0.0.1:${port}`);
});
