class_name CitySkyline
extends Node3D
## Wave 2, Phase 2.5: what you see in the distance, cheaply.
##
##  - Far buildings: past VIEW_RANGE every building's hundreds of breakable
##    pieces stop drawing and a single box in its wall colour (with a darker
##    roof cap) stands in for it. Near it, the pieces are back.
##  - The skyline: a ring of taller towers well beyond the edge of town,
##    hazed into the sky colour, so the city doesn't stop at the docks.
##  - A light haze over distance, so far boxes and the towers sit back.
##
## A building that has been knocked about still shows whole from far off;
## the stand-in drops away once most of it is gone.

const VIEW_RANGE := 170.0       # m: pieces drawn up to here
const SMALL_RANGE := 110.0      # m: small pieces (glass, doors, rails)
const MARGIN := 8.0

## Wave 4: the far towers' material (CityWeather darkens it at night).
var tower_mat: StandardMaterial3D
var gen: CityGenerator
var world: DestructionWorld
var _boxes := {}                # building index -> MeshInstance3D
var _pieces_left := {}          # building index -> pieces still standing
var _pieces_all := {}


func build(g: CityGenerator, w: DestructionWorld, env: Environment) -> void:
	gen = g
	world = w
	_ranges()
	_stand_ins()
	_towers()
	if env:
		env.fog_enabled = true
		env.fog_light_color = Color("9fbcd4")
		env.fog_density = 0.0016
		env.fog_sky_affect = 0.0
		env.fog_height = 40.0
		env.fog_height_density = 0.0


## Every piece stops drawing at its range (all pieces were added in the
## generator's order, so piece k is world piece k + 1).
func _ranges() -> void:
	for id in world.pieces:
		var p: Dictionary = world.pieces[id]
		var body := p.node as Node3D
		if body == null or body.get_child_count() == 0:
			continue
		var mi := body.get_child(0) as GeometryInstance3D
		if mi == null:
			continue
		var big: float = (p.aabb as AABB).get_longest_axis_size()
		mi.visibility_range_end = SMALL_RANGE if big < 1.3 or String(p.kind).begins_with("glass") else VIEW_RANGE
		mi.visibility_range_end_margin = MARGIN


func _stand_ins() -> void:
	var roof := Cel.material(Color("4a4d52"), false)
	for bi in gen.buildings.size():
		var b: Dictionary = gen.buildings[bi]
		var box: AABB = b.bounds
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(box.size.x - 0.2, box.size.y - 1.0, box.size.z - 0.2)
		mi.mesh = m
		mi.material_override = Cel.material((b.tint as Color) if b.has("tint") else Color("9a948a"), false)
		mi.position = box.get_center() - Vector3(0, 0.5, 0)
		mi.visibility_range_begin = VIEW_RANGE - MARGIN
		mi.visibility_range_begin_margin = MARGIN
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var cap := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(box.size.x, 0.4, box.size.z)
		cap.mesh = cm
		cap.material_override = roof
		cap.position = Vector3(0, m.size.y * 0.5 + 0.2, 0)
		cap.visibility_range_begin = VIEW_RANGE - MARGIN
		cap.visibility_range_begin_margin = MARGIN
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(cap)
		_boxes[bi] = mi
	for p in gen.pieces:
		var bi: int = p.get("building", -1)
		if bi >= 0:
			_pieces_all[bi] = _pieces_all.get(bi, 0) + 1
	_pieces_left = _pieces_all.duplicate()
	world.piece_broken.connect(_on_broken)


func _on_broken(id: int) -> void:
	var k := id - 1
	if k < 0 or k >= gen.pieces.size():
		return
	var bi: int = gen.pieces[k].get("building", -1)
	if bi < 0 or not _boxes.has(bi):
		return
	_pieces_left[bi] = int(_pieces_left[bi]) - 1
	if _pieces_left[bi] < _pieces_all[bi] * 0.5:
		(_boxes[bi] as Node3D).queue_free()
		_boxes.erase(bi)


## A ring of far towers round the city, the colour of the haze.
func _towers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.seed_value * 3 + 11
	var centre := Vector3(CityGenerator.extent_x() * 0.5, 0, CityGenerator.extent_z() * 0.5)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	mm.mesh = bm
	var xfs: Array = []
	var cols: Array = []
	var a := 0.0
	while a < TAU:
		# Not out over the sea to the south: lower and sparser there.
		var dir := Vector3(cos(a), 0, sin(a))
		var sea := dir.z > 0.5
		var r := rng.randf_range(470.0, 720.0)
		var h := rng.randf_range(18.0, 46.0) if sea else rng.randf_range(25.0, 120.0)
		if not (sea and rng.randf() < 0.6):
			var w := rng.randf_range(18.0, 40.0)
			var d := rng.randf_range(18.0, 40.0)
			var basis := Basis(Vector3.UP, rng.randf_range(0, PI)).scaled(Vector3(w, h, d))
			xfs.append(Transform3D(basis, centre + dir * r + Vector3(0, h * 0.5 - 2.0, 0)))
			var k := clampf((r - 470.0) / 250.0, 0.0, 1.0)
			cols.append(Color("7d8e9e").lerp(Color("9fb6cb"), k * 0.7 + rng.randf() * 0.15))
		a += rng.randf_range(0.03, 0.07)
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, cols[i])
	var mat := StandardMaterial3D.new()
	tower_mat = mat
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Towers"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
