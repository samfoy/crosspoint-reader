This is a size-optimization loop for the CrossPoint++ firmware (ESP32-C3, PlatformIO + Arduino framework).

The loop shrinks the `firmware.bin` flash footprint while preserving correctness, invariants, and the three features introduced on `integration/reader-improvements`.

## Canonical goal document

Before every phase, re-read `.autoloop/SIZE_GOAL.md` in the repo root. That file is the source of truth for:
- The exact metric (`flash_used_bytes` from `scripts/autoloop/measure_size.sh`).
- Baseline numbers.
- Hard invariants (guardrails).
- Soft guidance (preference order).
- Forbidden changes.
- Stopping conditions.

If SIZE_GOAL.md contradicts anything in this harness file, SIZE_GOAL.md wins.

## Global rules

- Shared working files are the source of truth: `{{STATE_DIR}}/perf-profile.md`, `{{STATE_DIR}}/perf-log.jsonl`, `{{STATE_DIR}}/progress.md`.
- **One optimization per iteration.** Do not stack changes. Each iteration must isolate a single hypothesis so the measure→judge outcome is unambiguous.
- Fresh context every iteration: re-read `.autoloop/SIZE_GOAL.md`, the shared working files, and the files you intend to modify before acting.
- Prefer small, surgical, reversible changes.
- **No change is accepted without a before/after measurement.** Use `scripts/autoloop/measure_size.sh` exclusively — its JSON output is the canonical metric.
- **Every change must pass `scripts/autoloop/verify_guardrails.sh`.** The guardrail script enforces that the three features on the branch are still present. A failing guardrail script is an automatic discard.
- False keeps are worse than false discards. When in doubt, revert.
- The judge makes keep/discard decisions. The optimizer proposes, the measurer reports, the judge decides. Do not commit from any role other than judge.
- Use `{{TOOL_PATH}} memory add learning ...` to record durable lessons.

## Metric & tooling

- Measure with: `bash scripts/autoloop/measure_size.sh`
  - Runs `pio run -e default`. First run in a fresh worktree is ~8 min (toolchain cache miss); subsequent runs are ~2 min.
  - Output is a single JSON line on stdout. Parse the `flash_used_bytes` field as the metric.
  - On build failure the script emits `{"ok": false, ...}` — treat that as the worst possible result and discard the change.
- Verify guardrails with: `bash scripts/autoloop/verify_guardrails.sh`
  - Exits 0 on pass, 1 on fail, with a human-readable reason on stderr.
  - Run AFTER every build, BEFORE accepting a change.
- Noise floor: changes that shrink `flash_used_bytes` by fewer than 512 bytes are below the noise floor (mostly PIO re-link jitter); discard them.

## Commit discipline

- Only the judge commits. One optimization per commit.
- Conventional-commits subject: `perf(<area>): <short description>`, e.g. `perf(i18n): strip unused translation keys from release build`.
- Commit body MUST include:
  - `flash_used_bytes` before and after
  - the delta in bytes
  - why the change is safe for the three guarded features
- If a change is discarded, do `git checkout -- .` and `git clean -fd` before starting the next iteration.

## Phase ownership

Stay inside profiler → optimizer → measurer → judge. Do not invent extra phases.

- **profiler** — identifies the largest / most-wasteful symbols or strings in the current binary. Uses `xtensa-esp32-size`-style tooling or, since ESP32-C3 is RISC-V, `size` / `nm` / `objdump` from `~/.platformio/packages/toolchain-riscv32-esp/bin/riscv32-esp-elf-*`. Writes findings to `{{STATE_DIR}}/perf-profile.md`. No code changes.
- **optimizer** — picks ONE item from the profiler's list, implements the smallest change that should move it, records rationale in `{{STATE_DIR}}/progress.md`. No measurement, no commit.
- **measurer** — runs `measure_size.sh` and `verify_guardrails.sh`. Emits a `perf.measured` event with the JSON metric payload. No code changes.
- **judge** — reads the measurement, applies the acceptance rules below, either commits with the conventional message above or reverts with `git checkout -- . && git clean -fd`. Emits the iteration verdict and either `task.complete` (with `LOOP_COMPLETE` in the summary) if the stopping condition is met, or hands back to the profiler.

## Acceptance rules (judge)

KEEP a change iff ALL of:
- `measure_size.sh` returned `ok: true`.
- `verify_guardrails.sh` exited 0.
- `flash_used_bytes` decreased by at least 512 bytes from the previous accepted measurement.
- `ram_used_bytes` did not increase by more than 2048 bytes (2 KB) from the previous accepted measurement.

Otherwise DISCARD:
- Log the failure reason in `perf-log.jsonl`.
- `git checkout -- . && git clean -fd -- src/ lib/ scripts/ .autoloop/ platformio.ini`
- Do not touch `.autoloop/perf-log.jsonl` when reverting.

## Parallel conflict handling

This loop runs inside a git worktree. The repository main worktree may be edited by the user simultaneously. If you encounter unexpected file changes, merge conflicts, or write failures caused by another agent's concurrent edits, do not panic or rollback their changes. Re-read the file and continue attempting your edit.

## Stopping condition

Emit `task.complete` with `LOOP_COMPLETE` in the summary when ANY of the following is true:
- Goal met: total `flash_used_bytes` reduction from the baseline in SIZE_GOAL.md is ≥ 16,384 bytes.
- Three consecutive iterations with no accepted change.
- Iteration 12 has just completed (hard cap from `event_loop.max_iterations`).
- The guardrail script fails with a reason that implicates a prior accepted commit (i.e. the loop has regressed its own output) — in that case, also git-revert the offending commit before emitting `LOOP_COMPLETE`.
