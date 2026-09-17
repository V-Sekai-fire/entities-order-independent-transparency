#!/usr/bin/env bash
# Runs the order check on the stack and the hair, mono, under 4x MSAA, in stereo, and with
# the planted and occluded controls, against a Godot binary built from 4-entities/godot-oit.
# The whole matrix runs on the Mobile renderer, and again on Forward+, whose rows carry the
# forward_plus_ prefix.
# The check draws to a window; it cannot run headless. Bands are pixels over tolerance,
# and the mono run of each scene is the baseline for its other rows.
#   checks/run.sh <godot binary>
set -u
G="${1:?path to a godot editor binary}"
cd "$(dirname "$0")/.."
fails=0
runs=0
printf '%-30s %-6s  %s\n' "run" "exit" "parity band / order band / verdict"
for r in mobile forward_plus; do
for m in "--scene=stack" "--scene=stack --msaa=4" "--scene=stack --stereo" "--scene=stack --stereo --msaa=4" "--scene=stack --plant" "--scene=stack --occlude" \
         "--scene=hair" "--scene=hair --msaa=4" "--scene=hair --stereo --msaa=4" "--scene=hair --plant"; do
  name="${m//--scene=/}"
  name="${name// /_}"
  [ "$r" = mobile ] || name="${r}_$name"
  out="checks/out/$name"
  mkdir -p "$out"
  # shellcheck disable=SC2086
  timeout 180 "$G" --path . --resolution 800x500 --rendering-method "$r" res://checks/check.tscn -- $m "--out=$PWD/$out" > "$out/log.txt" 2>&1
  code=$?
  parity=$(grep -h '^parity:' "$out/log.txt" | sed -E 's/.*diff [0-9.]+, ([0-9]+ of [0-9]+) pixels.*\(bound ([0-9]+)\)/\1 (bound \2)/')
  order=$(grep -h '^order:' "$out/log.txt" | sed -E 's/.*diff [0-9.]+, ([0-9]+ of [0-9]+) pixels.*/\1/')
  verdict=$(grep -h "DONE\|control caught\|^FAIL" "$out/log.txt" | tail -1)
  printf '%-30s %-6d  %s / %s / %s\n' "$name" "$code" "${parity:-none}" "${order:-none}" "$verdict"
  runs=$((runs + 1))
  [ "$code" -eq 0 ] || fails=$((fails + 1))
done
done
echo "$fails of $runs runs failed"
exit $fails
