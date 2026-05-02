#!/usr/bin/env bash
# measure_size.sh — single source of truth for the size metric used by the
# optimize/firmware-size autoloop run. Prints one JSON line to stdout:
#
#   {"ok": true, "firmware_bytes": 6357489, "ram_bytes": 99996,
#    "flash_used_bytes": 6357489, "flash_capacity_bytes": 6553600,
#    "flash_pct": 97.0, "ram_pct": 30.5, "build_seconds": 123}
#
# On build failure: {"ok": false, "error": "...", "log": "path"}
#
# Always prints a single JSON line even on failure so the autoloop measurer
# has something deterministic to key off of.

set -u

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || cd "$(dirname "$0")/../.." || exit 1

LOGDIR=".logs"
mkdir -p "$LOGDIR"
stamp=$(date +%Y%m%d-%H%M%S)
log="$LOGDIR/size-build-$stamp.log"

# Always run a full, repeatable build. We do NOT clean; incremental keeps us
# fast, and the size we care about is the final link, which scons always
# redoes when anything it depends on changes.
start=$(date +%s)
if ! pio run -e default >"$log" 2>&1; then
  end=$(date +%s)
  printf '{"ok":false,"error":"pio_run_failed","log":"%s","build_seconds":%d}\n' "$log" $((end - start))
  exit 1
fi
end=$(date +%s)

bin=".pio/build/default/firmware.bin"
if [[ ! -f "$bin" ]]; then
  printf '{"ok":false,"error":"firmware_bin_missing","log":"%s"}\n' "$log"
  exit 1
fi

# Pull the pio-reported sizes out of the log (those are the authoritative
# flash.bin data size and RAM bss+data footprint for the ESP32-C3 image).
flash_used=$(grep -oE 'Flash: \[.*\] +[0-9.]+% \(used [0-9]+' "$log" | grep -oE 'used [0-9]+' | awk '{print $2}' | tail -1)
flash_cap=$(grep -oE 'Flash: \[.*\] +[0-9.]+% \(used [0-9]+ bytes from [0-9]+' "$log" | grep -oE 'from [0-9]+' | awk '{print $2}' | tail -1)
ram_used=$(grep -oE 'RAM:   \[.*\] +[0-9.]+% \(used [0-9]+' "$log" | grep -oE 'used [0-9]+' | awk '{print $2}' | tail -1)
ram_cap=$(grep -oE 'RAM:   \[.*\] +[0-9.]+% \(used [0-9]+ bytes from [0-9]+' "$log" | grep -oE 'from [0-9]+' | awk '{print $2}' | tail -1)

# File size on disk (bytes after padding, for reference).
firmware_bytes=$(stat -f%z "$bin" 2>/dev/null || stat -c%s "$bin")

flash_pct=$(awk -v u="${flash_used:-0}" -v c="${flash_cap:-1}" 'BEGIN{printf "%.2f", (u/c)*100}')
ram_pct=$(awk -v u="${ram_used:-0}" -v c="${ram_cap:-1}" 'BEGIN{printf "%.2f", (u/c)*100}')

printf '{"ok":true,"firmware_bytes":%s,"flash_used_bytes":%s,"flash_capacity_bytes":%s,"flash_pct":%s,"ram_used_bytes":%s,"ram_capacity_bytes":%s,"ram_pct":%s,"build_seconds":%d,"log":"%s"}\n' \
  "$firmware_bytes" "${flash_used:-null}" "${flash_cap:-null}" "$flash_pct" \
  "${ram_used:-null}" "${ram_cap:-null}" "$ram_pct" $((end - start)) "$log"
