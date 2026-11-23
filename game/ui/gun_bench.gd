class_name GunBench
extends SubViewportContainer
## The armoury's inspection bench: one of the station's pistols on a rubber
## mat under a work lamp, in its own little 3D world. Drag to turn it, wheel
## to zoom; on a controller the right stick turns it and the triggers zoom.
## Left alone it turns slowly by itself.
##
## Upgrades the station owns are fitted on the model (extended magazine,
## compensator, match barrel, speed loader, and the torch when it's the
## loadout). A "preview" part can be shown fitted even if it isn't bought.

const MODEL := preload("res://assets/models/guns/pistols.glb")

## Bench upgrade -> the part names it swaps (shown, hidden).
const PARTS := {
	Armoury.EXT_MAG: [["mag_ext"], ["mag_std"]],
	Armoury.MATCH_BARREL: [["barrel_match"], ["barrel_std"]],
	Armoury.SPEED_LOAD: [["loader"], []],
}
## The torch is a loadout item, so it uses this made-up bit in the mask.
const TORCH := 31

var _vp: SubViewport
var _turn: Node3D      # yaw (around up) then pitch
var _tilt: Node3D
var _centre: Node3D    # moves the shown gun so it turns about its middle
var _guns: Node3D
var _cam: Camera3D
var _pistol := -1
var _mask := -1
var _yaw := -0.6
var _pitch := 0.0
var _dist := 0.55
var _idle := 0.0
var _dragging := false


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("10141c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.46, 0.56)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	# Work lamp from the upper left, a cool fill from the right.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -35, 0)
	key.light_energy = 2.2
	key.light_color = Color(1.0, 0.95, 0.86)
	key.shadow_enabled = true
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 140, 0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.7, 0.8, 1.0)
	_vp.add_child(fill)
	_bench()
	_turn = Node3D.new()
	_turn.position = Vector3(0, 0.085, 0)
	_vp.add_child(_turn)
	_tilt = Node3D.new()
	_turn.add_child(_tilt)
	_centre = Node3D.new()
	_tilt.add_child(_centre)
	_guns = MODEL.instantiate()
	_centre.add_child(_guns)
	Cel.apply(_guns, true)
	for g in _guns.get_children():
		(g as Node3D).position = Vector3.ZERO
		(g as Node3D).visible = false
	_cam = Camera3D.new()
	_cam.fov = 30.0
	_cam.near = 0.02
	_vp.add_child(_cam)
	_place_camera()
	if _pistol >= 0:
		show_gun(_pistol, _mask)


## The mat and the wall behind it.
func _bench() -> void:
	var mat := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.01, 0.6)
	mat.mesh = bm
	mat.material_override = Cel.material(Color(0.13, 0.2, 0.16), false, 0.0, null, 1.0, true)
	mat.position = Vector3(0, -0.005, 0)
	_vp.add_child(mat)
	# Cutting-mat grid lines.
	for i in range(-8, 9):
		for along_x in [true, false]:
			var l := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.9, 0.0005, 0.0018) if along_x else Vector3(0.0018, 0.0005, 0.6)
			l.mesh = lm
			l.material_override = Cel.material(Color(0.22, 0.32, 0.25), false, 0.0, null, 1.0, true)
			l.position = Vector3(0, 0.0003, i * 0.035) if along_x else Vector3(i * 0.05, 0.0003, 0)
			_vp.add_child(l)
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(1.6, 0.8, 0.02)
	wall.mesh = wm
	wall.material_override = Cel.material(Color(0.2, 0.22, 0.26), false, 0.0, null, 1.0, true)
	wall.position = Vector3(0, 0.35, -0.32)
	_vp.add_child(wall)
	# Pegboard holes.
	for x in range(-10, 11):
		for y in range(0, 9):
			var h := MeshInstance3D.new()
			var hm := CylinderMesh.new()
			hm.top_radius = 0.004
			hm.bottom_radius = 0.004
			hm.height = 0.002
			hm.radial_segments = 8
			hm.rings = 1
			h.mesh = hm
			h.rotation_degrees = Vector3(90, 0, 0)
			h.material_override = Cel.material(Color(0.08, 0.09, 0.11), false, 0.0, null, 1.0, true)
			h.position = Vector3(x * 0.06, 0.05 + y * 0.06, -0.309)
			_vp.add_child(h)


## Show pistol p (its index in Armoury.PISTOLS) with these upgrades fitted:
## a bitmask of Armoury item bits (and TORCH).
func show_gun(p: int, mask: int) -> void:
	if _guns == null:   # not in the tree yet: shown on _ready
		_pistol = p
		_mask = mask
		return
	if p == _pistol and mask == _mask and _centre.position != Vector3.ZERO:
		return
	if p != _pistol:
		_idle = 0.0
	_pistol = p
	_mask = mask
	var root: Node3D = null
	for g in _guns.get_children():
		var on := String(g.name) == "pistol_%d" % p
		(g as Node3D).visible = on
		if on:
			root = g
	if root == null:
		return
	var pre := "p%d_" % p
	var fitted := func(bit: int) -> bool: return (mask & (1 << bit)) != 0
	_part(root, pre + "mag_ext", fitted.call(Armoury.EXT_MAG))
	_part(root, pre + "mag_std", not fitted.call(Armoury.EXT_MAG))
	_part(root, pre + "barrel_match", fitted.call(Armoury.MATCH_BARREL))
	_part(root, pre + "barrel_std", not fitted.call(Armoury.MATCH_BARREL))
	var comp: bool = fitted.call(Armoury.COMPENSATOR)
	_part(root, pre + "comp", comp and not fitted.call(Armoury.MATCH_BARREL))
	_part(root, pre + "comp_m", comp and fitted.call(Armoury.MATCH_BARREL))
	_part(root, pre + "loader", fitted.call(Armoury.SPEED_LOAD))
	_part(root, pre + "torch", fitted.call(TORCH))
	# Turn about the middle of what's showing.
	var box := _bounds(root, Transform3D.IDENTITY)
	_centre.position = -box.get_center()


func _part(root: Node, name: String, on: bool) -> void:
	var n := root.find_child(name, true, false) as Node3D
	if n:
		n.visible = on


func _bounds(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [[n, xf]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var node: Node = it[0]
		var t: Transform3D = it[1]
		if node is Node3D and not (node as Node3D).visible:
			continue
		if node is MeshInstance3D:
			var b: AABB = t * (node as MeshInstance3D).get_aabb()
			out = b if first else out.merge(b)
			first = false
		for c in node.get_children():
			if c is Node3D:
				stack.append([c, t * (c as Node3D).transform])
	return out


func _place_camera() -> void:
	_turn.rotation.y = _yaw
	_tilt.rotation.z = _pitch
	var look := _turn.position
	_cam.position = look + Vector3(0, 0.3, 1.0).normalized() * _dist
	_cam.look_at(look, Vector3.UP)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var sx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var sy := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	var zoom := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	var stick := Vector2(sx, sy)
	if stick.length() > 0.18:
		_yaw += stick.x * 2.6 * delta
		_pitch = clampf(_pitch - stick.y * 1.8 * delta, -1.3, 1.3)
		_idle = 0.0
	if absf(zoom) > 0.1:
		_dist = clampf(_dist - zoom * 0.35 * delta, 0.2, 0.75)
		_idle = 0.0
	_idle += delta
	if _idle > 2.5 and not _dragging:
		_yaw += delta * 0.45
		_pitch = lerpf(_pitch, 0.0, delta * 0.8)
	_place_camera()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = clampf(_dist - 0.03, 0.2, 0.75)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = clampf(_dist + 0.03, 0.2, 0.75)
		_idle = 0.0
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw += mm.relative.x * 0.012
		_pitch = clampf(_pitch + mm.relative.y * 0.01, -1.3, 1.3)
		_idle = 0.0
		accept_event()
