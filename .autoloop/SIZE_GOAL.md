# Size Optimization Goal — `optimize/firmware-size`

## Metric

The single metric the loop optimizes is the PlatformIO-reported **flash used
bytes** from `pio run -e default`, extracted by `scripts/autoloop/measure_size.sh`
into the `flash_used_bytes` JSON field.

**Baseline (integration/reader-improvements, commit HEAD at loop start):**
- `flash_used_bytes`: 6,357,455
- `flash_pct`: 97.01%
- `ram_used_bytes`: 99,996 (30.52%)
- build time: ~2 min

## Goal

Reduce `flash_used_bytes` by **at least 16 KB (16,384 bytes)** — roughly
recovering the 2 KB spent by the three new features, plus a real margin for
the next feature (~14 KB). Ideal target: 6,341,070 bytes (96.76%).

Stretch goal: 6,291,455 bytes (96.00%) — recovers ~65 KB. Not required.

## Hard invariants (any violation → discard the change)

1. **Build must succeed.** `pio run -e default` exits 0.
2. **Guardrail script must pass.** `scripts/autoloop/verify_guardrails.sh`
   returns 0. This checks that our three features are still present in source:
   - `FileBrowserActivity::launchFilter` / `applyFilter`
   - `STR_FILTER` translation key
   - OPDS always-available search render logic + no reintroduction of the
     `selectorIndex == 0` gate
   - OTA `logWifiAndHeap` helper + `otaSetupRetryCount` retry loop
3. **RAM must not regress by more than 2 KB** from baseline. Trading DRAM for
   flash via `PROGMEM`-style tricks is fine in general but the ESP32-C3 has
   no PSRAM and ~228 KB of headroom is precious.
4. **No changes under `open-x4-sdk/`** — it is a submodule pointing at
   `jpirnay/community-sdk`. Optimizations there belong in a separate PR
   upstream.
5. **No changes to `src/activities/home/FileBrowserActivity.*`,
   `src/activities/browser/OpdsBookBrowserActivity.cpp`, or
   `src/network/OtaUpdater.cpp`** that remove guarded functionality. Cleanup
   of dead code inside these files is acceptable only if the guardrail script
   still passes.
6. **No deletion of translation strings.** `lib/I18n/translations/*.yaml`
   `STR_*` keys are load-bearing; the `gen_i18n.py` build step will warn if
   keys are referenced but missing, and silently drop unused ones. Adding a
   `--strip-unused` flag to the build is OK if it demonstrably compiles.
7. **`pio check -e default --fail-on-defect medium`** must not regress (new
   defects added by the change are disqualifying). Existing defects are not
   the loop's problem.
8. **One change per iteration.** Each commit must be small, labelled with a
   conventional-commits subject, and include the before/after bytes in the
   commit body.

## Soft guidance (preference order)

1. **Linker-level diet first.** Dead-code elimination via
   `build_flags += -ffunction-sections -fdata-sections` paired with
   `-Wl,--gc-sections` if not already present. Check `platformio.ini` before
   adding.
2. **Translation pruning.** `scripts/gen_i18n.py` has a `--strip-unused` flag
   that drops `STR_*` keys referenced nowhere. Toggle on for the release
   build. Expected save: single-digit KB to tens of KB depending on overhead.
3. **Debug string shrinking.** Behind `ENABLE_SERIAL_LOG` / `LOG_LEVEL=2` in
   the default env — these are development-only. The `gh_release` env in
   `platformio.ini` is the right template to adapt. Consider dropping log
   format strings for `LOG_DBG` in release.
4. **Duplicated string constants.** `grep -rE '\"[A-Za-z0-9 _.-]{20,}\"' src/`
   will find candidates. `static constexpr char foo[]` in anonymous namespaces
   coalesces where possible.
5. **Unused libraries.** `lib_deps` in `platformio.ini` — check for anything
   the current source doesn't actually use. Do not delete without a grep pass.
6. **`-Os` vs `-O2`.** Arduino ESP32 defaults to `-Os`; confirm and leave
   alone if so.

## Out of scope / forbidden

- Disabling features flagged in `SCOPE.md`.
- Rewriting algorithms for density.
- Shrinking the reader's render path (the hot path — correctness beats bytes).
- Font or image asset changes (touch them in a separate, visual-review PR).
- Touching `.pio/build/`, `.platformio/`, or any cached artifact.
- Re-ordering #includes just to touch files.

## Measurement protocol

Every iteration:
1. Apply change.
2. Run `scripts/autoloop/measure_size.sh` — capture the JSON as the "after"
   snapshot.
3. Run `scripts/autoloop/verify_guardrails.sh`.
4. If both pass AND `flash_used_bytes` decreased by at least 512 bytes,
   commit with a conventional message and log the delta. If either fails or
   the delta is <512 bytes (noise floor), revert with `git checkout -- .`
   and `git clean -fd`.

## Stopping condition

Stop and emit `LOOP_COMPLETE` when ANY of:
- Goal met (≥16 KB saved).
- Three consecutive iterations with no accepted change.
- `max_iterations = 10` reached.
- A guardrail failure is caused by the loop itself (regression in our code).
