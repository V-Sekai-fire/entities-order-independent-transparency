extends Node3D
# Captures a scene sorted and scrambled, with OIT on and off, and compares.
#   <godot> --path . res://checks/check.tscn -- [--scene=stack|hair] [--plant] [--occlude] [--msaa=<2|4|8>] [--stereo] [--out=<dir>]
# The stack's scramble gives the front box a lower render priority, so sorted blending draws
# it first; the hair's scramble reverses the strand segments from back-to-front to front-to-back.
# --plant skips the scramble while claiming it, and the check must then fail.
# --stereo renders both eyes through the built-in mobile VR interface and compares each.
# macOS stops drawing an occluded window, so each capture waits for drawn frames rather
# than processed ones and fails when none arrive; the window stays on top to keep them coming.
# --occlude stops the render loop instead, which is what an occluded window does to it, and
# the capture must then fail.

const PARITY_TOLERANCE := 3.0 / 255.0
# Froxel columns are 6 px wide, so the transmittance a fragment reads bleeds across
# silhouettes by up to a tile; those pixels are counted and bounded, not hidden. Under MSAA
# transparents accumulate at one sample, so every silhouette edge differs by a pixel-wide
# line as well. Bounds are set from measurement: stack 710 of 400000 mono, 1701 at 4x,
# 1923 of 900000 stereo at 4x; hair 33042 mono, 53575 at 4x, 54414 of 900000 stereo at 4x.
const PARITY_MAX_PIXELS := {"stack": 1000, "stack_msaa": 2500, "hair": 40000, "hair_msaa": 65000}
const SCRAMBLE_MIN := 8.0 / 255.0
const SETTLE_FRAMES := 12
const SETTLE_TIMEOUT_FRAMES := 600

var scene_name := "stack"
var plant := false
var occlude := false
var stereo := false
var msaa := 0
var out_dir := ""
var scene: Node3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--plant":
			plant = true
		elif a == "--occlude":
			occlude = true
		elif a == "--stereo":
			stereo = true
		elif a.begins_with("--scene="):
			scene_name = a.trim_prefix("--scene=")
		elif a.begins_with("--msaa="):
			msaa = int(a.trim_prefix("--msaa="))
		elif a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	if not _configure():
		get_tree().quit(1)
		return
	_run()


func _configure() -> bool:
	if not PARITY_MAX_PIXELS.has(scene_name):
		print("FAIL --scene=%s is not stack or hair" % scene_name)
		return false
	scene = load("res://scenes/%s.tscn" % scene_name).instantiate()
	add_child(scene)
	match msaa:
		0:
			pass
		2:
			get_viewport().msaa_3d = Viewport.MSAA_2X
		4:
			get_viewport().msaa_3d = Viewport.MSAA_4X
		8:
			get_viewport().msaa_3d = Viewport.MSAA_8X
		_:
			print("FAIL --msaa=%d is not 2, 4 or 8" % msaa)
			return false
	if stereo:
		var xr: MobileVRInterface = XRServer.find_interface("Native mobile")
		if xr == null or not xr.initialize():
			print("FAIL the built-in mobile VR interface did not initialise")
			return false
		# The interface views from the world origin at eye height, so the origin takes the camera's place.
		xr.eye_height = 0.0
		XRServer.world_origin = get_viewport().get_camera_3d().global_transform
		get_viewport().use_xr = true
	get_window().always_on_top = true
	if occlude:
		RenderingServer.render_loop_enabled = false
	print("config: scene=%s msaa=%d stereo=%s" % [scene_name, msaa, stereo])
	return true


func _run() -> void:
	var on_sorted := await _capture("on_sorted", true, false)
	var off_sorted := await _capture("off_sorted", false, false)
	var off_scrambled := await _capture("off_scrambled", false, not plant)
	var on_scrambled := await _capture("on_scrambled", true, true)

	var fails := 0
	var parity_bound: int = PARITY_MAX_PIXELS[scene_name + ("_msaa" if msaa > 0 else "")]
	var parity := _diff(on_sorted, off_sorted)
	print("parity: OIT on vs sorted blend, max channel diff %.4f, %d of %d pixels over %.4f (bound %d)" % [parity.max, parity.over, parity.total, PARITY_TOLERANCE, parity_bound])
	if parity.over > parity_bound:
		print("FAIL parity")
		fails += 1

	var scramble := _diff(off_sorted, off_scrambled)
	print("scramble: sorted blend sorted vs scrambled, max channel diff %.4f (needs > %.4f)" % [scramble.max, SCRAMBLE_MIN])
	if scramble.max <= SCRAMBLE_MIN:
		print("FAIL scramble is invisible to sorted blending")
		fails += 1

	var order := _diff(on_sorted, on_scrambled)
	print("order: OIT on sorted vs scrambled, max channel diff %.4f, %d of %d pixels over %.4f (bound %d)" % [order.max, order.over, order.total, PARITY_TOLERANCE, PARITY_MAX_PIXELS[scene_name]])
	if order.over > PARITY_MAX_PIXELS[scene_name]:
		print("FAIL order")
		fails += 1

	if plant:
		if fails > 0:
			print("planted control caught")
			get_tree().quit(0)
		else:
			print("FAIL planted control passed")
			get_tree().quit(1)
		return
	print("DONE" if fails == 0 else "FAIL %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)


func _scramble(on: bool) -> void:
	if scene.has_node("Red"):
		(scene.get_node("Red") as MeshInstance3D).get_active_material(0).render_priority = -1 if on else 0
	else:
		scene.get_node("Hair").reversed = on


func _capture(label: String, oit: bool, scrambled: bool) -> Array[Image]:
	ProjectSettings.set_setting("rendering/oit/enabled", oit)
	_scramble(scrambled)
	var drawn := Engine.get_frames_drawn()
	var waited := 0
	while Engine.get_frames_drawn() < drawn + SETTLE_FRAMES:
		await get_tree().process_frame
		waited += 1
		if waited > SETTLE_TIMEOUT_FRAMES:
			print("FAIL %s: %d frames drawn in %d processed; the window is occluded" % [label, Engine.get_frames_drawn() - drawn, waited])
			if occlude:
				print("occlusion control caught")
			get_tree().quit(0 if occlude else 1)
			await get_tree().process_frame
	var eyes: Array[Image] = []
	var texture := get_viewport().get_texture()
	if stereo:
		for layer in 2:
			eyes.append(RenderingServer.texture_2d_layer_get(texture.get_rid(), layer))
	else:
		eyes.append(texture.get_image())
	if out_dir != "":
		for i in eyes.size():
			eyes[i].save_png(out_dir.path_join("%s%s.png" % [label, "_eye%d" % i if stereo else ""]))
	return eyes


func _diff(a: Array[Image], b: Array[Image]) -> Dictionary:
	assert(a.size() == b.size())
	var worst := 0.0
	var over := 0
	var total := 0
	for eye in a.size():
		var w := a[eye].get_width()
		var h := a[eye].get_height()
		assert(w == b[eye].get_width() and h == b[eye].get_height())
		total += w * h
		for y in h:
			for x in w:
				var p := a[eye].get_pixel(x, y)
				var q := b[eye].get_pixel(x, y)
				var d := maxf(absf(p.r - q.r), maxf(absf(p.g - q.g), absf(p.b - q.b)))
				worst = maxf(worst, d)
				if d > PARITY_TOLERANCE:
					over += 1
	return {"max": worst, "over": over, "total": total}
