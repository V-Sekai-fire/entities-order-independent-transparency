#!/usr/bin/env bash
# Records the stack and hair demonstrations to CineForm Matroska and plays each back through
# the engine's decoder, with a planted recording per scene that the playback check must reject.
#   bash videos/run.sh <godot binary>
set -u
G=${1:?godot binary}
cd "$(dirname "$0")/.."
mkdir -p videos/out
fails=0
for scene in stack hair; do
	for plant in "" "--plant"; do
		out=videos/out/$scene${plant:+_plant}.mkv
		"$G" --path . --resolution 1280x720 --write-movie "$out" --fixed-fps 60 --quit-after 480 \
			res://videos/record.tscn -- --scene=$scene $plant 2>&1 | grep -E "ERROR|SCRIPT"
		echo "== $out"
		"$G" --path . --fixed-fps 60 res://videos/check_video.tscn -- --video="$out" --scene=$scene $plant 2>&1 \
			| grep -E "ERROR|SCRIPT|frames:|parity|scramble|DONE|FAIL|control" | tee /dev/stderr | grep -q "^DONE\|^planted control caught" || fails=$((fails + 1))
	done
done
echo "$fails of 4 recordings failed"
exit $fails
