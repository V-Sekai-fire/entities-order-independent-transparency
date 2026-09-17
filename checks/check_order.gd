extends Node3D
# Captures the three-box stack sorted and scrambled, with OIT on and off, and compares.
#   <godot> --path . -- [--plant] [--out=<dir>]
# The scramble gives the front box a lower render priority, so sorted blending draws it first.
# --plant skips the scramble while claiming it, and the check must then fail.

const PARITY_TOLERANCE := 3.0 / 255.0
# Froxel columns are 6 px wide, so the transmittance a fragment reads bleeds across
# silhouettes by up to a tile; those pixels are counted and bounded, not hidden.
const PARITY_MAX_PIXELS := 1000
const SCRAMBLE_MIN := 8.0 / 255.0
const SETTLE_FRAMES := 12

var plant := false
var out_dir := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--plant":
			plant = true
		elif a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	_run()


func _run() -> void:
	var on_sorted := await _capture("on_sorted", true, 0)
	var off_sorted := await _capture("off_sorted", false, 0)
	var off_scrambled := await _capture("off_scrambled", false, 0 if plant else -1)
	var on_scrambled := await _capture("on_scrambled", true, -1)

	var fails := 0
	var parity := _diff(on_sorted, off_sorted)
	print("parity: OIT on vs sorted blend, max channel diff %.4f, %d of %d pixels over %.4f (bound %d)" % [parity.max, parity.over, parity.total, PARITY_TOLERANCE, PARITY_MAX_PIXELS])
	if parity.over > PARITY_MAX_PIXELS:
		print("FAIL parity")
		fails += 1

	var scramble := _diff(off_sorted, off_scrambled)
	print("scramble: sorted blend sorted vs scrambled, max channel diff %.4f (needs > %.4f)" % [scramble.max, SCRAMBLE_MIN])
	if scramble.max <= SCRAMBLE_MIN:
		print("FAIL scramble is invisible to sorted blending")
		fails += 1

	var order := _diff(on_sorted, on_scrambled)
	print("order: OIT on sorted vs scrambled, max channel diff %.4f, %d of %d pixels over %.4f (bound %d)" % [order.max, order.over, order.total, PARITY_TOLERANCE, PARITY_MAX_PIXELS])
	if order.over > PARITY_MAX_PIXELS:
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


func _capture(label: String, oit: bool, front_priority: int) -> Image:
	ProjectSettings.set_setting("rendering/oit/enabled", oit)
	($Red as MeshInstance3D).get_active_material(0).render_priority = front_priority
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if out_dir != "":
		img.save_png(out_dir.path_join(label + ".png"))
	return img


func _diff(a: Image, b: Image) -> Dictionary:
	var w := a.get_width()
	var h := a.get_height()
	assert(w == b.get_width() and h == b.get_height())
	var worst := 0.0
	var over := 0
	for y in h:
		for x in w:
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			var d := maxf(absf(p.r - q.r), maxf(absf(p.g - q.g), absf(p.b - q.b)))
			worst = maxf(worst, d)
			if d > PARITY_TOLERANCE:
				over += 1
	return {"max": worst, "over": over, "total": w * h}
