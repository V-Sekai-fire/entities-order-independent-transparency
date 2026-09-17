extends Node
# Plays a recording back through the engine's own CineForm decoder and checks the phases
# against each other: the turn repeats every two phases, so frame i of "sorted blending,
# sorted" and frame i of "OIT on, scrambled" show the same pose and must agree, while frame i
# of "OIT on, sorted" and of "sorted blending, scrambled" show the same pose and must differ.
#   <godot> --path . --fixed-fps 60 res://videos/check_video.tscn -- --video=<mkv> --scene=stack|hair [--plant]
# --plant names a recording made with --plant, whose scramble never happened, and the check
# must then fail.

const PHASE_FRAMES := 120
const SAMPLE_FRAMES := [30, 60, 90]
const TOLERANCE := 12.0 / 255.0
# Pixels the scramble must add over the parity count across the three sample frames. Measured
# 6815 on the stack and 16695 on the hair; the planted recordings added -3560 and 364.
const SCRAMBLE_EXTRA := 3000
# Codec noise and the silhouette band together, over three 1280x720 frames. Measured 13568
# on the stack and 15379 on the hair; the planted recordings, where the pair is OIT against
# sorted blending with nothing scrambled, reach the same count, so this is the floor.
const PARITY_MAX_PIXELS := {"stack": 20000, "hair": 30000}

var video := ""
var scene_name := "stack"
var plant := false
var player: VideoStreamPlayer
var frame := 0
var kept := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--plant":
			plant = true
		elif a.begins_with("--video="):
			video = a.trim_prefix("--video=")
		elif a.begins_with("--scene="):
			scene_name = a.trim_prefix("--scene=")
	var stream: VideoStream = load(video)
	if stream == null:
		print("FAIL no stream loaded from %s" % video)
		get_tree().quit(1)
		return
	player = VideoStreamPlayer.new()
	player.stream = stream
	add_child(player)
	player.play()


func _process(_delta: float) -> void:
	if player.is_playing():
		var phase := frame / PHASE_FRAMES
		var i := frame % PHASE_FRAMES
		if i in SAMPLE_FRAMES and phase < 4:
			kept[[phase, i]] = player.get_video_texture().get_image()
		frame += 1
		return
	_report()


func _report() -> void:
	var fails := 0
	print("frames: %d played (expected %d)" % [frame, 4 * PHASE_FRAMES])
	if frame < 4 * PHASE_FRAMES:
		print("FAIL the recording is short")
		fails += 1
	var parity_over := 0
	var parity_total := 0
	var scramble_over := 0
	for i in SAMPLE_FRAMES:
		if not (kept.has([1, i]) and kept.has([3, i]) and kept.has([0, i]) and kept.has([2, i])):
			print("FAIL sample frame %d missing" % i)
			fails += 1
			continue
		var parity := _diff(kept[[1, i]], kept[[3, i]])
		parity_over += parity.over
		parity_total += parity.total
		scramble_over += _diff(kept[[0, i]], kept[[2, i]]).over
	print("parity: sorted blend vs OIT scrambled at the same pose, %d of %d pixels over %.4f (bound %d)" % [parity_over, parity_total, TOLERANCE, PARITY_MAX_PIXELS[scene_name]])
	if parity_over > PARITY_MAX_PIXELS[scene_name]:
		print("FAIL parity")
		fails += 1
	print("scramble: OIT sorted vs sorted blend scrambled at the same pose, %d of %d pixels over, %d more than parity (needs > %d)" % [scramble_over, parity_total, scramble_over - parity_over, SCRAMBLE_EXTRA])
	if scramble_over - parity_over <= SCRAMBLE_EXTRA:
		print("FAIL scramble is invisible in the recording")
		fails += 1
	if plant:
		print("planted control caught" if fails > 0 else "FAIL planted control passed")
		get_tree().quit(0 if fails > 0 else 1)
		return
	print("DONE" if fails == 0 else "FAIL %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)


func _diff(a: Image, b: Image) -> Dictionary:
	var w := a.get_width()
	var h := a.get_height()
	var worst := 0.0
	var over := 0
	for y in h:
		for x in w:
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			var d := maxf(absf(p.r - q.r), maxf(absf(p.g - q.g), absf(p.b - q.b)))
			worst = maxf(worst, d)
			if d > TOLERANCE:
				over += 1
	return {"max": worst, "over": over, "total": w * h}
