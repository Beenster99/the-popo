class_name MiniMap
extends CanvasLayer
## v0.15.0: the mini map, bottom left. Roads, lots and buildings from the
## city generator, you (white arrow), the other officers (their ping
## colours), patrol cars, the custody bay while anyone has a prisoner, a
## cuffed prisoner doing a runner, and the open jobs with a route along the
## roads to the nearest one. Jobs off the edge sit on the rim, so the way to
## go is always on screen.
##
## Small (the default) follows you and turns with the camera, so up on the
## map is the way the camera looks; it zooms out as you drive faster. Large
## shows the whole city, north up. The mini map key (M) goes Small, Large,
## Off; the choice is saved (Settings > Gameplay > Mini map).

const SMALL := 260.0
const LARGE := 520.0
const MARGIN := 24.0
const FOOT_RANGE := 70.0        # m from the centre to the edge of the small map, on foot
const CAR_RANGE := 160.0        # ... at full speed in a car

const COL_OUTSIDE := Color("1c2b36")
const COL_ROAD := Color("8d939b")
const COL_LOT := Color("3c434c")
const COL_PARK := Color("33553a")
const COL_BUILDING := Color("5d6773")
const COL_STATION := Color("2f5ea8")
const COL_ME := Color(1, 1, 1)
const COL_JOB := Color("ff4646")
const COL_JOB_LOW := Color("ffb030")
const COL_BAY := Color("4a8cff")
const COL_RUNNER := Color("ff8030")
const COL_CAR := Color("2a4fa0")

var dispatcher: Dispatcher
var city: City
var pawn_getter: Callable   # () -> Officer, or null

var _frame: Panel
var _map: Control
var _street: Label
var _range := FOOT_RANGE
var _last_pos := Vector3.INF
var _speed := 0.0
var _t := 0.0


func _ready() -> void:
	layer = 5
	_frame = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_OUTSIDE
	sb.border_color = Color(0, 0, 0, 0.85)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	_frame.add_theme_stylebox_override("panel", sb)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.anchor_top = 1.0
	_frame.anchor_bottom = 1.0
	add_child(_frame)
	_map = Control.new()
	_map.clip_contents = true
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map.offset_left = 3
	_map.offset_top = 3
	_map.offset_right = -3
	_map.offset_bottom = -3
	_map.draw.connect(_draw_map)
	_frame.add_child(_map)
	_street = Label.new()
	_street.add_theme_font_size_override("font_size", 14)
	_street.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	_street.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_street.add_theme_constant_override("outline_size", 5)
	_street.anchor_top = 1.0
	_street.anchor_bottom = 1.0
	add_child(_street)
	_layout()
	Settings.changed.connect(func(k): if k == "minimap": _layout())


## Where the map is on screen (empty when it's off), so other HUD bits keep clear.
func screen_rect() -> Rect2:
	return _frame.get_global_rect() if _frame and _frame.visible else Rect2()


static func mode() -> int:
	return int(Settings.values.get("minimap", 1))


func _layout() -> void:
	var m := mode()
	_frame.visible = m != 0
	_street.visible = m == 1
	var s := LARGE if m == 2 else SMALL
	_frame.offset_left = MARGIN
	_frame.offset_right = MARGIN + s
	_frame.offset_bottom = -MARGIN - 22.0
	_frame.offset_top = -MARGIN - 22.0 - s
	_street.offset_left = MARGIN + 4.0
	_street.offset_top = -MARGIN - 20.0
	_street.offset_bottom = -MARGIN


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("minimap") and not PlayerInput.blocked:
		Settings.set_value("minimap", (mode() + 1) % 3)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_t += delta
	if mode() == 0:
		return
	var o := _me()
	if o:
		var p := _pos_of(o)
		if _last_pos != Vector3.INF and delta > 0.0:
			var v := Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length() / delta
			_speed = lerpf(_speed, minf(v, 40.0), clampf(delta * 2.0, 0.0, 1.0))
		_last_pos = p
		var want := lerpf(FOOT_RANGE, CAR_RANGE, clampf((_speed - 4.0) / 22.0, 0.0, 1.0))
		_range = lerpf(_range, want, clampf(delta * 1.5, 0.0, 1.0))
		_street.text = CityGenerator.street_at(p) if city and city.gen else ""
	_map.queue_redraw()


func _me() -> Node3D:
	var o: Node3D = pawn_getter.call() if pawn_getter.is_valid() else null
	return o if o and o.is_inside_tree() else null


## Where a pawn is on the map: its car when it's in one.
static func _pos_of(o: Node3D) -> Vector3:
	if o is Officer and (o as Officer).in_car() and is_instance_valid((o as Officer).car):
		return (o as Officer).car.global_position
	return o.global_position


static func _facing_of(o: Node3D) -> Vector3:
	if o is Officer and (o as Officer).in_car() and is_instance_valid((o as Officer).car):
		return (o as Officer).car.global_transform.basis.z
	return o.global_transform.basis.z


## The map's world-to-screen transform (world x/z in, map pixels out), and
## its rotation.
func _view() -> Array:
	var size := _map.size
	var centre := size * 0.5
	if mode() == 2 or _me() == null:
		# The whole city, north up.
		var ex := CityGenerator.extent_x()
		var ez := CityGenerator.extent_z()
		var k := minf(size.x / ex, size.y / ez) * 0.96
		return [Transform2D(0.0, Vector2(k, k), 0.0, centre) * Transform2D(0.0, Vector2(-ex * 0.5, -ez * 0.5)), 0.0, k]
	var me := _pos_of(_me())
	var ang := 0.0
	if Settings.values.get("minimap_rotate", true):
		var cam := _map.get_viewport().get_camera_3d()
		if cam:
			var f := -cam.global_transform.basis.z
			if Vector2(f.x, f.z).length() > 0.01:
				ang = -PI * 0.5 - atan2(f.z, f.x)
	var k := (size.x * 0.5) / _range
	return [Transform2D(ang, Vector2(k, k), 0.0, centre) * Transform2D(0.0, Vector2(-me.x, -me.z)), ang, k]


func _draw_map() -> void:
	if city == null or city.gen == null:
		return
	var v := _view()
	var xf: Transform2D = v[0]
	var ang: float = v[1]
	var k: float = v[2]
	var size := _map.size
	var centre := size * 0.5
	# --- The city: roads under everything, then the lots, then buildings.
	_map.draw_set_transform_matrix(xf)
	_map.draw_rect(Rect2(0, 0, CityGenerator.extent_x(), CityGenerator.extent_z()), COL_ROAD)
	for b in city.gen.blocks:
		var st: String = b.get("style", "")
		_map.draw_rect(b.rect, COL_PARK if st == "park" else COL_LOT)
	for b in city.gen.buildings:
		var bb: AABB = b.get("bounds", AABB())
		if bb.size == Vector3.ZERO:
			continue
		var col := COL_STATION if b.get("type", "") == "station" else COL_BUILDING
		_map.draw_rect(Rect2(bb.position.x + 0.3, bb.position.z + 0.3, bb.size.x - 0.6, bb.size.z - 0.6), col)
	# Patrol cars (handy for finding yours again).
	for pc in city.police_cars:
		if is_instance_valid(pc) and pc.is_inside_tree():
			var p: Vector3 = pc.global_position
			_map.draw_circle(Vector2(p.x, p.z), 2.2, COL_CAR)
	_map.draw_set_transform_matrix(Transform2D())
	# --- The route to the nearest job, along the roads.
	var me := _me()
	var jobs := _targets()
	if me and not jobs.is_empty():
		var near: Array = jobs[0]
		var mp := _pos_of(me)
		for t in jobs:
			if _flat(t[0]).distance_to(_flat(mp)) < _flat(near[0]).distance_to(_flat(mp)):
				near = t
		var pts := PackedVector2Array()
		for w in route(mp, near[0]):
			pts.append(xf * w)
		var rc: Color = near[1]
		_map.draw_polyline(pts, Color(0, 0, 0, 0.6), maxf(6.0, k * 5.0), true)
		_map.draw_polyline(pts, Color(rc.r, rc.g, rc.b, 0.95), maxf(3.0, k * 3.0), true)
	# --- Markers, upright whatever the map's rotation.
	var rim := Rect2(Vector2.ZERO, size).grow(-12.0)
	var pulse := 0.5 + 0.5 * sin(_t * 6.0)
	for t in jobs:
		var sp := xf * _flat(t[0])
		var col: Color = t[1]
		var kind: String = t[2]
		if rim.has_point(sp):
			if kind == "job":
				_map.draw_circle(sp, 9.0 + 4.0 * pulse, Color(col.r, col.g, col.b, 0.35))
				_map.draw_circle(sp, 7.0, col)
				_map.draw_circle(sp, 7.0, Color.BLACK, false, 1.5, true)
				_bang(sp)
			else:
				_map.draw_rect(Rect2(sp - Vector2(6, 6), Vector2(12, 12)), col)
				_map.draw_rect(Rect2(sp - Vector2(6, 6), Vector2(12, 12)), Color.BLACK, false, 1.5)
		else:
			# Off the edge: pinned to the rim, pointing out.
			var d := (sp - centre).normalized()
			var e := _rim_point(centre, d, size, 12.0)
			var side := Vector2(-d.y, d.x)
			var tri := PackedVector2Array([e + d * 10.0, e - d * 6.0 + side * 9.0, e - d * 6.0 - side * 9.0])
			_map.draw_colored_polygon(tri, col)
			tri.append(tri[0])
			_map.draw_polyline(tri, Color.BLACK, 1.5, true)
	# --- The other officers, then you on top.
	var sync := city.sync
	if sync:
		for id in sync.pawns:
			var p: Node3D = sync.pawns[id]
			if p == me or not is_instance_valid(p) or not p.is_inside_tree():
				continue
			var sp := xf * _flat(_pos_of(p))
			var col: Color = Pings.COLORS[Pings._slot(id) % Pings.COLORS.size()]
			if rim.has_point(sp):
				_arrow(sp, _facing_of(p), ang, col, 7.0)
			else:
				_map.draw_circle(_rim_point(centre, (sp - centre).normalized(), size, 8.0), 5.0, col)
	if me:
		_arrow(xf * _flat(_pos_of(me)), _facing_of(me), ang, COL_ME, 9.0)
	# North, on the rim, when the map turns.
	if mode() == 1 and absf(ang) > 0.0001:
		var n := Vector2(0, -1).rotated(ang)
		var np := _rim_point(centre, n, size, 14.0)
		_map.draw_circle(np, 10.0, Color(0, 0, 0, 0.7))
		var font := ThemeDB.fallback_font
		_map.draw_string(font, np + Vector2(-5, 6), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1))


## Open jobs, the custody bay while anyone has a prisoner, and cuffed
## runners: [position, colour, "job" | "bay" | "runner"].
func _targets() -> Array:
	var out: Array = []
	if dispatcher == null:
		return out
	for c in dispatcher.active_calls():
		out.append([c.marker, job_colour(c.kind), "job"])
	var prisoner := false
	for s in dispatcher.suspects.values():
		var su := s as Suspect
		if su.state in [Suspect.S.CUFFED, Suspect.S.IN_CAR]:
			prisoner = true
		elif su.state == Suspect.S.CUFF_RUN:
			out.append([su.global_position, COL_RUNNER, "runner"])
	if prisoner:
		out.append([dispatcher.bay_position(), COL_BAY, "bay"])
	return out


static func job_colour(kind: int) -> Color:
	if kind in [Dispatcher.Kind.TRAFFIC, Dispatcher.Kind.THEFT, Dispatcher.Kind.PURSUIT]:
		return COL_JOB_LOW
	return COL_JOB


static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


## Where a ray from the centre leaves the map, inset by pad.
static func _rim_point(centre: Vector2, d: Vector2, size: Vector2, pad: float) -> Vector2:
	var hx := size.x * 0.5 - pad
	var hy := size.y * 0.5 - pad
	var tx := hx / absf(d.x) if absf(d.x) > 0.0001 else INF
	var ty := hy / absf(d.y) if absf(d.y) > 0.0001 else INF
	return centre + d * minf(tx, ty)


func _arrow(at: Vector2, facing: Vector3, ang: float, col: Color, s: float) -> void:
	var f := Vector2(facing.x, facing.z)
	f = f.normalized().rotated(ang) if f.length() > 0.01 else Vector2(0, -1)
	var side := Vector2(-f.y, f.x)
	var pts := PackedVector2Array([at + f * s * 1.3, at - f * s * 0.8 + side * s * 0.9, at - f * s * 0.35, at - f * s * 0.8 - side * s * 0.9])
	_map.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	_map.draw_polyline(pts, Color.BLACK, 1.5, true)


func _bang(at: Vector2) -> void:
	_map.draw_rect(Rect2(at + Vector2(-1.2, -4.5), Vector2(2.4, 5.5)), Color.WHITE)
	_map.draw_rect(Rect2(at + Vector2(-1.2, 2.2), Vector2(2.4, 2.2)), Color.WHITE)


## A route along the roads from a to b (world x/z points): onto the road
## you're nearest, along it to the cross street nearest the target, along
## that, then to the target. The city's roads are a full grid, so this is
## always on the road and no longer than it needs to be by more than a block.
static func route(a: Vector3, b: Vector3) -> Array:
	var half := CityGenerator.ROAD_W * 0.5
	# a's road: one running along X (fixed z) or along Z (fixed x).
	var kz := CityGenerator.nearest_road(a.z, 1)
	var kx := CityGenerator.nearest_road(a.x, 0)
	var rz := CityGenerator.road_at(kz, 1) + half
	var rx := CityGenerator.road_at(kx, 0) + half
	var pts: Array = [Vector2(a.x, a.z)]
	if absf(a.z - rz) <= absf(a.x - rx):
		# Along X, then down the Z road nearest b.
		var bx := CityGenerator.road_at(CityGenerator.nearest_road(b.x, 0), 0) + half
		pts.append(Vector2(a.x, rz))
		pts.append(Vector2(bx, rz))
		pts.append(Vector2(bx, b.z))
	else:
		var bz := CityGenerator.road_at(CityGenerator.nearest_road(b.z, 1), 1) + half
		pts.append(Vector2(rx, a.z))
		pts.append(Vector2(rx, bz))
		pts.append(Vector2(b.x, bz))
	pts.append(Vector2(b.x, b.z))
	return pts
