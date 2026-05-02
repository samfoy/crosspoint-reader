# CrossPoint++ Fork — Work Handoff (2026-05-01)

## What shipped

Three feature branches, each independently reviewable, rebuilt clean, and pushed to `origin` (`github.com/samfoy/crosspoint-reader`).

| Branch | Flash Δ | RAM Δ | What |
|---|---|---|---|
| `feat/filebrowser-filter` | +1,050 B | 0 | In-folder case-insensitive filter on the FileBrowser. Left short-press opens the keyboard. Back clears an active filter before leaving the folder. |
| `feat/opds-search-always` | +62 B | 0 | OPDS search is now triggered by Left from any row, not only from row 0. Fixes upstream crosspoint-reader/crosspoint-reader#1430. |
| `feat/ota-stability` | +1,026 B | 0 | Retry loop around `esp_https_ota_begin`, pre-flight wifi check, progress heartbeat every 256 KB, WiFi/RSSI/heap snapshot logged at every phase and on every error. |
| `integration/reader-improvements` | **+2,050 B total** | 0 | Octopus merge of the three above. |

All four branches are up on `origin`.

## Baseline measurements (default env)

```
master:       6,355,439 bytes  (97.00%)
integration:  6,357,489 bytes  (97.01%)
```

We still have ~196 KB of flash headroom in the default env. No optimization was strictly required to ship; Sam asked for one anyway to reclaim space for future work.

## Autoloop — RUNNING 🟢

Actually launched successfully once the backend was switched from claude to pi and the metareview was disabled. Run id: `lunar-embed`.

**Progress as of handover:**
- Iteration 1 profiler identified the right optimization on the first shot: flip `LOG_LEVEL=2` → `LOG_LEVEL=1` in `[env:default]` of `platformio.ini`. ~679 `LOG_DBG` call sites vanish when the macro is compiled out, expected ~25-35 KB flash saved, no guardrail impact (our `logWifiAndHeap` uses `LOG_INF`).
- See `.autoloop/worktrees/lunar-embed/tree/.autoloop/perf-profile.md` and `progress.md` for the full profiler report.
- Loop is currently in the optimizer → measurer → judge cycle. Each pi call takes ~8–15 min with the harness prompt + Bedrock Opus 4.7 (~30 KB prompt, cacheWrite dominates latency).

**To check on it:**
```bash
tmux attach -t cpp-size       # interactive view
tail -f ~/Projects/crosspoint-plus/.autoloop/diagnostics/latest.log
```

**To monitor progress:**
```bash
cd ~/Projects/crosspoint-plus
wc -l .autoloop/worktrees/lunar-embed/tree/.autoloop/journal.jsonl
tail -5 .autoloop/worktrees/lunar-embed/tree/.autoloop/journal.jsonl \
  | python3 -c "import sys,json
for l in sys.stdin:
  d=json.loads(l); print(d.get('iteration','-'), d['topic'], d.get('payload','')[:80])"
```

**Expected total runtime:** 3–5 hours for a full 12-iteration run (4 roles × 12 iters × ~10 min + 12 × 2-min builds). Budget ~$5–10 in Bedrock token cost.

**Guardrails that are already enforced:**
- `verify_guardrails.sh` runs before every judge-accepted commit — trips if any of the three features' signatures disappear.
- Changes below the 512-byte noise floor are auto-discarded.
- RAM regressions >2 KB are auto-discarded.
- `--worktree` isolation — the loop commits to `.autoloop/worktrees/lunar-embed/tree/` on branch `autoloop/lunar-embed`. Nothing lands in your main working tree without a manual merge.

**When the run finishes, either:**
- succeeded → `autoloop worktree show lunar-embed` to see the commits; `git merge` them onto `optimize/firmware-size` if you like
- failed → `autoloop worktree show lunar-embed` for the failure reason, `autoloop worktree clean lunar-embed` to delete, restart with a tweaked prompt

## If the autoloop wedges again

Based on what I saw: a bare `pi -p --mode json --no-session` with a huge stdin prompt occasionally just… sits there at 0% CPU. Two mitigations baked in:
1. `backend.timeout_ms = 900000` (15 min) in `autoloops.toml` so individual roles can't hang forever.
2. `review.enabled = false` so the adversarial gate (which is the thing that hung the first time) is skipped.

If a role times out, autoloop will mark the iteration failed and move on. Check `~/Projects/crosspoint-plus/.autoloop/worktrees/lunar-embed/tree/.autoloop/pi-stream.<N>.jsonl` for the raw pi output when debugging.

## One-command relaunch (clean state)

```bash
cd ~/Projects/crosspoint-plus
tmux kill-session -t cpp-size 2>/dev/null
rm -rf .autoloop/worktrees/*/ 2>/dev/null
LOG=.autoloop/diagnostics/autoloop-run-$(date +%Y%m%d-%H%M%S).log
ln -sf "$(basename $LOG)" .autoloop/diagnostics/latest.log
tmux new-session -d -s cpp-size -x 220 -y 50 \
  "zsh -lc 'cd ~/Projects/crosspoint-plus && autoloop run ./.autoloop/presets/autosize \"Optimize firmware.bin flash size per {{STATE_DIR}}/SIZE_GOAL.md. Use scripts/autoloop/measure_size.sh as the metric source and scripts/autoloop/verify_guardrails.sh before any commit.\" --worktree -v 2>&1 | tee $LOG; sleep 99999'"
```

The `zsh -lc` wrapper is essential — pi needs `.zshrc` env vars (AWS creds for Bedrock) loaded, and tmux does not run a login shell by default.

## Previous (superseded) notes

## Flash / RAM inspection notes (for profiler phase)

Top rodata contributors (use `~/.platformio/packages/toolchain-riscv32-esp/bin/riscv32-esp-elf-nm --size-sort` on `.pio/build/default/firmware.elf`):

| Size | Source | Notes |
|---|---|---|
| 213,545 B | `lib445/SPI/SPI.cpp.o` | Arduino SPI rodata block. Touching this means patching framework — out of scope. |
| 206,259 B | `LanguageRegistry.cpp.o` → `de_trie_data` | German hyphenation trie. User feature, out of scope without a runtime flag. |
| 68,987 B | `libmbedtls.a(x509_crt_bundle.S.obj)` | Full Mozilla CA bundle. Trimmable via `esp_crt_bundle_set` but **high risk** — breaks any user-configured HTTPS endpoint (OPDS, KOSync, weather, etc.) whose CA is dropped. |
| 35,927 B | `CrossPointWebServer.cpp.o` → `FilesPageHtml` | Already minified + gzip level 9. No further trivial wins. |
| ~30-50 KB × ~20 | Font bitmaps (notosans, bookerly, opendyslexic at many sizes/weights) | Each user-visible, out of scope per SIZE_GOAL.md. |

Easy wins the profiler can go after first:
1. `--strip-unused` flag on `gen_i18n.py` — **already on** when invoked from SCons (see `scripts/gen_i18n.py:1063`), so nothing to do here.
2. `-ffunction-sections -fdata-sections` + `-Wl,--gc-sections` — verify whether pioarduino already adds these; if not, adding them is a mechanical win (often -5 to -15 KB).
3. `LOG_DBG` bodies in `default` env — we're on `LOG_LEVEL=2`. Release envs (`gh_release`, `slim`) run at lower levels so shipped-to-user builds are already leaner.
4. Duplicated string literals (search for `"[A-Za-z][^"]{20,}"` repeats).

## What NOT to touch without explicit discussion

From SCOPE.md / GOVERNANCE.md / CLAUDE.md and our own goals:

- `open-x4-sdk/` submodule (separate upstream PR territory)
- Font or image assets (visual-review PR)
- Hyphenation data (user feature)
- HTTPS cert bundle (endpoint breakage risk)
- Reader hot path (correctness > bytes)

## Next actions (in order)

1. Come home, log in to claude
2. Run the one-command block above
3. Review the worktree's commits, cherry-pick or merge what you like onto `optimize/firmware-size`
4. Consider opening PRs upstream to jpirnay:
   - `feat/opds-search-always` is the strongest candidate — it maps 1:1 to upstream daveallie #1430
   - `feat/filebrowser-filter` is good for the ++ fork; daveallie upstream might want a governance discussion first
   - `feat/ota-stability` is good to propose once you have real crash-log evidence from the new logging to justify it
5. Flash `optimize/firmware-size` `gh_release` build to the X4 once you're ready to smoke-test the features end-to-end.

## Files changed this session

```
lib/I18n/translations/english.yaml          +1   (STR_FILTER)
src/activities/browser/OpdsBookBrowserActivity.cpp   +5 -2
src/activities/home/FileBrowserActivity.h    +9
src/activities/home/FileBrowserActivity.cpp  +86 -1
src/network/OtaUpdater.cpp                   +84 -2
.autoloop/SIZE_GOAL.md                        new
.autoloop/presets/autosize/*                  new (preset)
scripts/autoloop/measure_size.sh              new
scripts/autoloop/verify_guardrails.sh         new
.gitignore                                   +6
```
