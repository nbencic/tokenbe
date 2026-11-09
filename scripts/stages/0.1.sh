# Stage 0.1 — Repository skeleton & Core package (14 § Stage 0.1). Sourced by scripts/verify-stage.sh.

check "swift build" scripts/run.sh build
check "swift test" scripts/run.sh test
check "swiftlint --strict" scripts/run.sh lint

inventory=(
  LICENSE .gitignore .editorconfig Package.swift .swiftlint.yml CHANGELOG.md README.md
  Sources/TokenBeCore/TokenBeCore.swift Tests/TokenBeCoreTests/SmokeTests.swift
  Sources/TokenBeCore/Store/Migrations/README.md Tests/Fixtures/README.md
  scripts/run.sh scripts/wait.sh scripts/bootstrap.sh scripts/verify-stage.sh scripts/stages/0.1.sh
  docs/00-README.md docs/01-product-scope.md docs/02-provider-apis.md docs/03-data-model.md
  docs/04-architecture.md docs/05-normalization-pricing-runway.md docs/06-harness-ingest.md
  docs/07-logging.md docs/08-ui-spec.md docs/09-settings-spec.md docs/10-repo-build-release.md
  docs/11-testing.md docs/12-agent-rules.md docs/13-decisions.md docs/14-development-plan.md
  docs/QUESTIONS.md docs/reporters/tokenbe_report.py docs/reporters/tokenbe_report.js
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done
check "docs/postmortems/ present" test -d docs/postmortems
check "scripts executable" test -x scripts/run.sh -a -x scripts/wait.sh -a -x scripts/bootstrap.sh -a -x scripts/verify-stage.sh
check "exactly one exact: pin in Package.swift" test "$(grep -c 'exact:' Package.swift)" -eq 1
