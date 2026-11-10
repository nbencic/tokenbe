# Test fixtures

Layout and naming are fixed by `docs/11-testing.md`: `providers/<provider>/<endpoint>.<case>.{recorded,synthetic}.json`, a `RECORDED` marker per verified provider, harness JSONL samples, and one fixture DB per schema version. Recorded fixtures are committed only after `scripts/record-fixtures.sh --verify-redacted` (`docs/12-agent-rules.md § R11`).

Each `providers/` file is one HTTP response in an envelope: `{"status": <int>, "headers": {<name>: <string>}, "body": <JSON>}`, with `headers` optional (`docs/11-testing.md § Fixtures`, Q-026). The body holds the provider's JSON as `docs/02-provider-apis.md` describes it.
