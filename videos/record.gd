extends Node3D
# Records a scene through Movie Maker in four phases, OIT on and off, sorted and scrambled,
# turning the transparents the whole time so the depth order keeps changing under them.
#   <godot> --path . --resolution 1280x720 --write-movie videos/out/<name>.mkv --fixed-fps 60 --quit-after 480 res://videos/record.tscn -- --scene=stack|hair [--plant]
# The stack's scramble gives the front box a lower render priority; the hair's reverses the
# strand segments to front-to-back, re-sorted every frame so "sorted" stays true as it turns.
# The turn repeats every two phases, so videos/check_video.gd can pair frames by pose.
# --plant skips the scramble while claiming it, and the check on that recording must fail.

const PHASE_FRAMES := 120
# The check's framing fills the window; the recording stands further back.
const ZOOM_OUT := 1.4
const PHASES := [
	["OIT on, sorted", true, false],
	["sorted blending, sorted", false, false],
	["sorted blending, scrambled", false, true],
	["OIT on, scrambled", true, true],
]

var scene_name := "stack"
var plant := false
var scene: Node3D
var label: Label
var frame := 0
var phase := -1


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--plant":
			plant = true
		elif a.begins_with("--scene="):
			scene_name = a.trim_prefix("--scene=")
	scene = load("res://scenes/%s.tscn" % scene_name).instantiate()
	add_child(scene)
	var camera := get_viewport().get_camera_3d()
	camera.position *= ZOOM_OUT
	label = Label.new()
	label.position = Vector2(24, 24)
	label.add_theme_font_size_override("font_size", 36)
	var layer := CanvasLayer.new()
	layer.add_child(label)
	add_child(layer)


func _process(_delta: float) -> void:
	var next_phase := mini(frame / PHASE_FRAMES, PHASES.size() - 1)
	if next_phase != phase:
		phase = next_phase
		ProjectSettings.set_setting("rendering/oit/enabled", PHASES[phase][1])
		_scramble(PHASES[phase][2] and not plant)
		label.text = "%s: %s" % [scene_name, PHASES[phase][0]]
	var turn := 0.35 * sin(float(frame) / (2 * PHASE_FRAMES) * TAU)
	if scene.has_node("Hair"):
		var hair: MeshInstance3D = scene.get_node("Hair")
		hair.rotation.y = turn
		hair.resort()
	else:
		for n in ["Red", "Green", "Blue"]:
			(scene.get_node(n) as Node3D).rotation.y = turn
	frame += 1


func _scramble(on: bool) -> void:
	if scene.has_node("Red"):
		(scene.get_node("Red") as MeshInstance3D).get_active_material(0).render_priority = -1 if on else 0
	else:
		scene.get_node("Hair").reversed = on
