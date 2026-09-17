extends MeshInstance3D
# A head of ribbon strands grown from a seed, so the mesh is the same on every desk.
# Segments are emitted back to front from the camera, which is the sorted reference a
# single draw can reach; reversed emits them front to back, the worst case for blending.

@export var strand_count := 3000
@export var segments := 14
@export var strand_length := 0.32
@export var ribbon_width := 0.003
@export var scalp_radius := 0.1
@export var rng_seed := 7
@export var reversed := false:
	set(value):
		reversed = value
		if is_inside_tree():
			_rebuild_indices()

var _vertices := PackedVector3Array()
var _colors := PackedColorArray()
var _segment_mids := PackedVector3Array()


func _ready() -> void:
	_grow()
	_rebuild_indices()


func _grow() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var camera_pos := get_viewport().get_camera_3d().global_position
	var gravity := Vector3(0, -1, 0)
	var step := strand_length / segments
	_vertices.clear()
	_colors.clear()
	_segment_mids.clear()
	for s in strand_count:
		var root := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 1), rng.randf_range(-1, 1)).normalized() * scalp_radius
		var tangent := (root.normalized() + gravity * 0.4).normalized()
		var shade := rng.randf_range(0.7, 1.3)
		var length_scale := rng.randf_range(0.7, 1.0)
		var p := root
		for i in segments + 1:
			var t := float(i) / segments
			var to_camera := (camera_pos - p).normalized()
			var side := tangent.cross(to_camera).normalized() * ribbon_width * 0.5 * (1.0 - 0.6 * t)
			var color := Color(0.16 * shade, 0.09 * shade, 0.04 * shade).lerp(Color(0.5 * shade, 0.32 * shade, 0.15 * shade), t)
			_vertices.append(p - side)
			_vertices.append(p + side)
			_colors.append(color)
			_colors.append(color)
			if i < segments:
				_segment_mids.append(p + tangent * step * 0.5)
				var wobble := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.25
				tangent = (tangent + gravity * 0.35 + wobble).normalized()
				var next := p + tangent * step * length_scale
				if next.length() < scalp_radius:
					next = next.normalized() * scalp_radius
					tangent = (next - p).normalized()
				p = next


func resort() -> void:
	_rebuild_indices()


# Sorts against the camera as the mesh sees it now, so a moving mesh stays sorted.
func _rebuild_indices() -> void:
	var camera_pos := to_local(get_viewport().get_camera_3d().global_position)
	var depths := PackedFloat32Array()
	depths.resize(_segment_mids.size())
	for i in depths.size():
		depths[i] = camera_pos.distance_squared_to(_segment_mids[i])
	var order := PackedInt32Array()
	order.resize(depths.size())
	for i in order.size():
		order[i] = i
	var sorted := Array(order)
	sorted.sort_custom(func(a: int, b: int) -> bool: return depths[a] > depths[b])
	if reversed:
		sorted.reverse()
	var indices := PackedInt32Array()
	for seg in sorted:
		var strand: int = seg / segments
		var i: int = seg % segments
		var base := strand * (segments + 1) * 2 + i * 2
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var material := material_override
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = array_mesh
	material_override = material
