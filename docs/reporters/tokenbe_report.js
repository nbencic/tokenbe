// TokenBe harness reporter (v1 line format, see docs/06-harness-ingest.md). Append-only. Node stdlib only.
const fs = require("fs");
const os = require("os");
const path = require("path");
const { randomUUID } = require("crypto");

const PATH = path.join(os.homedir(), "Library/Application Support/TokenBe/ingest/harness.jsonl");

function report(provider, app, model, usage, key, { requestId, status = "ok", costCents } = {}) {
  const line = {
    v: 1,
    ts: new Date().toISOString(),
    provider,                         // openai | anthropic | openrouter | deepseek | xai
    app,                              // ^[a-z0-9][a-z0-9._-]{0,63}$
    key_hint: String(key).slice(-4),
    request_id: requestId || randomUUID(),
    model,
    usage,                            // provider's usage object, verbatim
    status,                           // ok | error
  };
  if (Number.isInteger(costCents)) line.cost_cents = costCents;
  fs.mkdirSync(path.dirname(PATH), { recursive: true });
  fs.appendFileSync(PATH, JSON.stringify(line) + "\n");
}

module.exports = { report };
