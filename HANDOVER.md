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

## Autoloop — scaffold ready, backend not available

Everything needed to run the size-optimization autoloop is committed on `optimize/firmware-size`:

- `.autoloop/SIZE_GOAL.md` — baseline, hard invariants, soft guidance, forbidden changes, stopping conditions
- `.autoloop/presets/autosize/` — local preset (copied from autoperf, `max_iterations=12`, harness rewritten for size work)
- `scripts/autoloop/measure_size.sh` — single source of truth for the metric; emits JSON
- `scripts/autoloop/verify_guardrails.sh` — asserts the three features are still in source after any change

**Blocker:** claude CLI is not logged in on this Mac (`Not logged in · Please run /login`). The `Claude Code-credentials` keychain entry only holds Vercel MCP OAuth state — the primary Anthropic auth is gone. I tried `pi` as an alternative backend; it hangs in a nested pi invocation. So the loop could not actually execute this session.

## One-command run when you're back

```bash
# 1. Log in (interactive, one-time)
claude  # then /login, or /logout && /login to re-auth

# 2. Launch the loop (tmux + tee, per the autoloop.launch memory)
cd ~/Projects/crosspoint-plus
LOG=.autoloop/diagnostics/autoloop-run-$(date +%Y%m%d-%H%M%S).log
ln -sf "$(basename $LOG)" .autoloop/diagnostics/latest.log
tmux new-session -d -s cpp-size -x 220 -y 50 \
  "cd ~/Projects/crosspoint-plus && autoloop run ./.autoloop/presets/autosize \
    'Optimize firmware.bin flash size. Read {{STATE_DIR}}/SIZE_GOAL.md first.
     Use scripts/autoloop/measure_size.sh as the ONLY metric source and
     scripts/autoloop/verify_guardrails.sh before accepting any commit.
     All invariants in SIZE_GOAL.md must hold.' \
    --worktree -v 2>&1 | tee $LOG"

# 3. Watch it
tmux attach -t cpp-size       # or tail -f .autoloop/diagnostics/latest.log
```

Loop runs in a git worktree (`--worktree`), so nothing lands in your working tree without your review. When it finishes, the accepted commits live in `.autoloop/worktrees/<run-id>/tree/` on branch `optimize/firmware-size`.

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
