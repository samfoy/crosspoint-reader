#!/usr/bin/env bash
# verify_guardrails.sh — invariants that must hold after any proposed change.
# Run by the autoloop judge before accepting an optimization. Exit 0 = pass,
# exit 1 = fail with a human-readable reason printed to stderr.

set -eu

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || cd "$(dirname "$0")/../.." || exit 1

fail() {
  echo "GUARDRAIL FAILED: $1" >&2
  exit 1
}

# --- Feature 1: filebrowser filter must still exist ---
grep -q 'launchFilter' src/activities/home/FileBrowserActivity.h ||
  fail "FileBrowser filter feature removed (launchFilter missing from header)"
grep -q 'applyFilter' src/activities/home/FileBrowserActivity.cpp ||
  fail "FileBrowser applyFilter() missing from implementation"
grep -q 'STR_FILTER:' lib/I18n/translations/english.yaml ||
  fail "STR_FILTER translation removed"

# --- Feature 2: OPDS always-available search ---
grep -q '!searchTemplate.empty() ? tr(STR_SEARCH)' src/activities/browser/OpdsBookBrowserActivity.cpp ||
  fail "OPDS always-available search reverted (render label changed)"
# The selector-zero gate must NOT be back
if grep -q 'searchTemplate.empty() && selectorIndex == 0' src/activities/browser/OpdsBookBrowserActivity.cpp; then
  fail "OPDS selector==0 gate reintroduced"
fi

# --- Feature 3: OTA stability ---
grep -q 'logWifiAndHeap' src/network/OtaUpdater.cpp ||
  fail "OTA logWifiAndHeap helper removed"
grep -q 'otaSetupRetryCount' src/network/OtaUpdater.cpp ||
  fail "OTA retry loop removed"

# --- Build health ---
if [[ ! -f .pio/build/default/firmware.bin ]]; then
  fail "firmware.bin missing (last build failed or never ran)"
fi

# --- Public APIs still linkable ---
if grep -qE 'class OtaUpdater' src/network/OtaUpdater.h; then
  grep -q 'checkForUpdate' src/network/OtaUpdater.h ||
    fail "OtaUpdater::checkForUpdate declaration missing"
  grep -q 'beginInstallUpdate' src/network/OtaUpdater.h ||
    fail "OtaUpdater::beginInstallUpdate declaration missing"
fi

# --- No hardcoded English strings added in src/ (project i18n rule) ---
# Flag only the obvious case: \"some text\" with 2+ uppercase-starting words.
# This is a best-effort check; acceptance lives with the reviewer.
# (Skipped for now; tr() compliance is linted by gen_i18n.py instead.)

echo "guardrails ok"
exit 0
