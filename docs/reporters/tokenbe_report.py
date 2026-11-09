"""TokenBe harness reporter (v1 line format, see docs/06-harness-ingest.md). Append-only. Stdlib only."""
import json, os, time, uuid

PATH = os.path.expanduser("~/Library/Application Support/TokenBe/ingest/harness.jsonl")

def report(provider: str, app: str, model: str, usage: dict, key: str,
           request_id: str | None = None, status: str = "ok", cost_cents: int | None = None) -> None:
    line = {
        "v": 1,
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()) + "Z",
        "provider": provider,            # openai | anthropic | openrouter | deepseek | xai
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
