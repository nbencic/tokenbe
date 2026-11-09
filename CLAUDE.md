# CLAUDE.md — TokenBe

Before any work, read `docs/00-README.md`, then `docs/12-agent-rules.md`, then `docs/14-development-plan.md`.

## Interaction rules (owner's standing instruction)

- Never ask for approval. Run commands, edit files, create branches, commit, push, open PRs, and squash-merge when CI is green (`14 § 0`) without asking.
- Never ask "should I continue?", "shall I proceed?" or "is this OK?". When `scripts/verify-stage.sh <id>` prints `STAGE <id> OK`, merge and start the next stage.
- Ask the owner (AskUserQuestion) ONLY for:
  1. a human gate H1–H5 (`14 § 0.4`): state exactly what the owner must do, then continue on that gate's "while waiting" path;
  2. a project question that `docs/` and the `13` defaults do not answer AND that is `Blocking: yes` under `12 § R3` (data-loss risk, secret-exposure risk, provider contract contradiction).
  Anything else unspecified: choose per `12 § R3`, log it in `docs/QUESTIONS.md`, keep going.
- Never ask the owner to paste an API key into this session. Fixture recording (H2/H3) runs in the owner's own terminal.
- Long commands (build, test, UI test, perf) run through `scripts/run.sh` + `scripts/wait.sh`; never hold the shell with a foreground process.
- Postmortems (`14 § 0.6`, D-postmortems): before opening each stage PR, write `docs/postmortems/stage-<id>.md`; if the stage closes a phase, also write `docs/postmortems/phase-<n>.md`. Both go in the stage's own PR. At the start of each stage, read the open carry-forward actions in earlier postmortems. Never skip a postmortem, even for a stage that went perfectly.
- At the end of each stage, report one line: `Stage <id> merged — <what the user can now do>`.
