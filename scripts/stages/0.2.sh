# Stage 0.2 — Logging core (14 § Stage 0.2, 07 § Definition of done). Sourced by scripts/verify-stage.sh.

inventory=(
  Sources/TokenBeCore/Logging/Evt.swift Sources/TokenBeCore/Logging/LogRecord.swift
  Sources/TokenBeCore/Logging/Redactor.swift Sources/TokenBeCore/Logging/LogSink.swift
  Sources/TokenBeCore/Logging/NDJSONSink.swift Sources/TokenBeCore/Logging/OSLogSink.swift
  Sources/TokenBeCore/Logging/Breadcrumbs.swift Sources/TokenBeCore/Logging/Log.swift
  Sources/TokenBeCore/Logging/CrashHandler.swift
  Tests/TokenBeCoreTests/RedactorTests.swift Tests/TokenBeCoreTests/LogSinkTests.swift
  Tests/TokenBeCoreTests/CrashHandlerTests.swift Tests/TokenBeCoreTests/LogRecordTests.swift
  scripts/check-log-events.sh scripts/stages/0.2.sh
)
for f in "${inventory[@]}"; do check "non-empty $f" test -s "$f"; done

check "07 table ↔ Evt enum (check-log-events.sh)" scripts/check-log-events.sh
for evt in app.log_dropped crash.signal crash.previous_launch; do
  check "Evt has $evt" grep -q "= \"$evt\"" Sources/TokenBeCore/Logging/Evt.swift
done

check "swift test" scripts/run.sh test
for suite in RedactorTests LogSinkTests CrashHandlerTests LogRecordTests; do
  check "suite $suite passed" suite_passed "$suite"
done

no_print() { [[ "$(grep -R "print(" Sources/ | wc -l | tr -d ' ')" == "0" ]]; }
check "no print( in Sources/" no_print
no_silent_catch() { ! grep -RnE 'catch[[:space:]]*\{[[:space:]]*\}|try\?' Sources Tests --include='*.swift' | grep -v '/Allowlist.swift:'; }
check "no silent catch / try? outside Allowlist.swift (07 DoD 1)" no_silent_catch
