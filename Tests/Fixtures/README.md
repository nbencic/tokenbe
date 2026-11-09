# Test fixtures

Layout and naming are fixed by `docs/11-testing.md`: `providers/<provider>/<endpoint>.<case>.{recorded,synthetic}.json`, a `RECORDED` marker per verified provider, harness JSONL samples, and one fixture DB per schema version. Recorded fixtures are committed only after `scripts/record-fixtures.sh --verify-redacted` (`docs/12-agent-rules.md § R11`).
