#!/usr/bin/env bash
# Runs the order check and its planted control against a Godot binary built from
# 4-entities/godot-oit. The check draws to a window; it cannot run headless.
#   checks/run.sh <godot binary>
set -u
G="${1:?path to a godot editor binary}"
cd "$(dirname "$0")/.."
mkdir -p checks/out
fails=0
for m in "" "--plant"; do
  log="checks/order${m}.log"
  timeout 120 "$G" --path . --resolution 800x500 -- $m "--out=$PWD/checks/out" > "$log" 2>&1
  code=$?
  verdict=$(grep -h "DONE\|planted control\|^FAIL" "$log" | tail -1)
  printf '%-6s %-8s exit=%d  %s\n' "order" "${m:-run}" "$code" "$verdict"
  [ "$code" -eq 0 ] || fails=$((fails + 1))
done
echo "$fails of 2 runs failed"
exit $fails
