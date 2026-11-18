# TokenBe

TokenBe is a macOS menu-bar app that shows, per LLM provider account, how much money is left and how long it lasts, attributes spend to your own apps by API key, and never requires a visit to a provider console for that. It is open source (MIT), written in Swift, and keeps provider keys only in the Keychain.

**Status: pre-alpha.** Nothing is installable yet. The engineering documentation and build plan are in [`docs/`](docs/00-README.md).

## Report your apps (harness reports)

Some providers (DeepSeek, xAI) cannot tell which of your programs spent what. Your program can tell TokenBe instead: after each request, append one JSON line to a file in `~/Library/Application Support/TokenBe/ingest/`. TokenBe reads every `*.jsonl` or `*.ndjson` file there within seconds, attributes the spend to the line's `app`, and moves a file that has gone quiet to `ingest/ingested/` (Settings → Sources → Harness reports). A file whose first line is not version-1 JSON goes to `ingest/rejected/`. The line format is in [`docs/06-harness-ingest.md`](docs/06-harness-ingest.md).

Rules for reporters:
- Append only, one `write` per line (a line under 4 KiB is written atomically on APFS).
- Never rewrite or truncate the file. To rotate, start a new file name.

Settings → Sources → Harness reports → `Copy reporter snippet` copies either snippet below.

Python (`docs/reporters/tokenbe_report.py`):

```python
"""TokenBe harness reporter (v1 line format, see docs/06-harness-ingest.md). Append-only. Stdlib only."""
import json, os, time, uuid

PATH = os.path.expanduser("~/Library/Application Support/TokenBe/ingest/harness.jsonl")

def report(provider: str, app: str, model: str, usage: dict, key: str,
           request_id: str | None = None, status: str = "ok", cost_cents: int | None = None) -> None:
    line = {
        "v": 1,
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()) + "Z",
        "provider": provider,            # openai | anthropic | openrouter | deepseek | xai | moonshot | novita
        "app": app,                      # ^[a-z0-9][a-z0-9._-]{0,63}$
        "key_hint": key[-4:],
        "request_id": request_id or str(uuid.uuid4()),
        "model": model,
        "usage": usage,                  # provider's usage object, verbatim
        "status": status,                # ok | error
    }
    if cost_cents is not None:
        line["cost_cents"] = int(cost_cents)
    os.makedirs(os.path.dirname(PATH), exist_ok=True)
    with open(PATH, "a", encoding="utf-8") as f:
        f.write(json.dumps(line, separators=(",", ":")) + "\n")
```

Node (`docs/reporters/tokenbe_report.js`):

```js
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
    provider,                         // openai | anthropic | openrouter | deepseek | xai | moonshot | novita
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
```
