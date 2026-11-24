class_name WorksSite
extends Node3D
## What a repair site looks like, on every machine (beenster, 2026-11-24:
## "a big truck to park up with concrete slabs and beams, a crew who are
## installing and a crane to lift parts into place").
##
## A flatbed lorry loaded with precast slabs and steel beams and a mobile
## crane drive in and park at the kerb. The crane puts its outriggers down,
## raises its boom, and for each piece of building that fell it lifts the
## piece off the lorry, swings it over and lowers it into place while a
## banksman guides it in. Then a fitter drills it home, welds it or grinds a
## beam on the trestles, with sparks, dust and noise. While there's rubble
## the crew shovels and sweeps. Barriers, cones and a sign go round it all.
##
## RepairCrews (host) decides where everything is and what each worker is
## doing and sends it (MSG_SITES, MSG_LIFT); this node only shows it. The
## lift is a fixed path in time, so every machine runs it from the start
## message and they agree on where the load is.

enum Job { NONE, SLING, BANKSMAN, DRILL, WELD, GRIND, SHOVEL, SWEEP }

const LORRY := preload("res://assets/models/works/works_lorry.glb")
const CRANE := preload("res://assets/models/works/crane_truck.glb")
const KIT := preload("res://assets/models/works/works_kit.glb")

const ARRIVE := 9.0          # s to drive in and park
const SET_UP := 3.5          # s to put the outriggers down
const ROLL_IN := 42.0        # m they come from
const LIFT_TIME := 12.0      # s for one lift, watched
const RESTORE_AT := 0.74     # the piece is set in place this far through a lift
const SLING := 2.6           # m from the hook block's top to the top of its load
const PICK := Vector3(0, 2.95, 1.0)     # lorry-local: top of the slab stack
const TRESTLE := Vector3(3.6, 0, -2.0)  # lorry-local, on the pavement side (x flipped to that side)
const SHOW_FX := 80.0        # m from the camera: sparks, dust and work sounds

var id := 0
var at := Vector3.ZERO           # the site (on the pavement)
var age := 0.0                   # s since the crew was sent
var working := true
var build_stage := false
var leaving := false
var _leave_t := 0.0

var lorry: Node3D
var crane: Node3D
var _lorry_park := Transform3D()
var _crane_park := Transform3D()
var _side := 1.0                 # +1: the pavement is on the vehicles' local -x side... see _place
var _parked := false

# crane parts
var _slew: Node3D
var _boom: Node3D
var _secs: Array = []            # boom_2..4
var _sec_z: Array = []
var _head: Node3D
var _outriggers: Array = []      # [node, x0, sign]
var _ram_a: Node3D
var _ram_b: Node3D
var _ram: MeshInstance3D
var _cable: MeshInstance3D
var _hook: Node3D
var _slings: Array = []
var _deploy := 0.0               # boom raised and working
var _legs := 0.0                 # outriggers out
var _wheels_l: Array = []
var _wheels_c: Array = []

# the lift
var _lift_piece := -1
var _lift_t := 0.0
var _lift_len := LIFT_TIME
var _lift_load: MeshInstance3D
var _load_off := Transform3D()   # piece transform relative to the hook, at rest
var _load_h := 1.0
var _load_size := Vector3.ONE
var _target := Vector3.ZERO      # hook point over the piece's place
var _yaw_end := 0.0
var _sounds_done := {}
var _taken := 0                  # loads taken off the lorry
var _hook_now := Vector3.ZERO

# the crew
var _crew := {}                  # net_id -> {w, job, point, tool, visor, t}
var _sparks: CPUParticles3D
var _dust: CPUParticles3D
var _flash: OmniLight3D
var _snd_t := {}

var world: DestructionWorld


static func make(site_id: int, site_at: Vector3, dw: DestructionWorld) -> WorksSite:
	var s := WorksSite.new()
	s.id = site_id
	s.at = site_at
	s.world = dw
	s.name = "WorksSite%d" % site_id
	return s


func _ready() -> void:
	lorry = LORRY.instantiate()
	crane = CRANE.instantiate()
	Cel.apply(lorry, true, 0.02)
	Cel.apply(crane, true, 0.02)
	add_child(lorry)
	add_child(crane)
	_wheels_l = _find_all(lorry, "wheel")
	_wheels_c = _find_all(crane, "wheel")
	_slew = crane.find_child("slew", true, false)
	_boom = crane.find_child("boom", true, false)
	for n in ["boom_2", "boom_3", "boom_4"]:
		var s: Node3D = crane.find_child(n, true, false)
		_secs.append(s)
		_sec_z.append(s.position.z)
	_head = crane.find_child("boom_head", true, false)
	for n in ["outrigger_fl", "outrigger_fr", "outrigger_rl", "outrigger_rr"]:
		var o: Node3D = crane.find_child(n, true, false)
		if o:
			_outriggers.append([o, o.position.x, signf(o.position.x)])
	_ram_a = crane.find_child("ram_mount", true, false)
	_ram_b = crane.find_child("ram_lug", true, false)
	var steel := Cel.material(Color(0.55, 0.57, 0.6), true, 0.01)
	_ram = _rod(0.13, steel)
	_ram.material_override = Cel.material(Color(0.2, 0.2, 0.22), true, 0.012)
	_cable = _rod(0.035, Cel.material(Color(0.1, 0.1, 0.1), false))
	_hook = _kit("hook_block")
	add_child(_hook)
	_hook.visible = false
	for i in 4:
		var sl := _rod(0.035, Cel.material(Color(0.95, 0.85, 0.1), true, 0.01))
		sl.visible = false
		_slings.append(sl)
	_make_fx()
	if _lorry_park != Transform3D():
		_place()


func _rod(radius: float, m: Material) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = 1.0
	c.radial_segments = 6
	c.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## A rod from a to b (a cylinder stretched between them).
static func _span(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		mi.visible = false
		return
	mi.visible = true
	var y := d / l
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mi.global_transform = Transform3D(Basis(x, y * l, z), (a + b) * 0.5)


static var _kit_cache := {}


## One item out of works_kit.glb (a fresh copy).
static func _kit(item: String) -> Node3D:
	if not _kit_cache.has(item):
		var all: Node3D = KIT.instantiate()
		Cel.apply(all, true, 0.008)
		var src: Node3D = all.find_child(item, true, false)
		var keep := src.duplicate() as Node3D
		keep.transform = Transform3D()
		all.free()
		_kit_cache[item] = keep
	return (_kit_cache[item] as Node3D).duplicate()


func _find_all(root: Node, prefix: String) -> Array:
	var out: Array = []
	for c in root.find_children(prefix + "*", "MeshInstance3D", true, false):
		if not String(c.name).contains("_rim") and not String(c.name).contains("_hub") and not String(c.name).contains("arch"):
			out.append(c)
	return out


# --- placing ---------------------------------------------------------------------------

## Where the lorry and crane park (from the host), and how long ago the crew
## was sent. A new message only nudges our clock if it's drifted.
func set_park(lorry_xf: Transform3D, crane_xf: Transform3D, host_age: float) -> void:
	var fresh := _lorry_park == Transform3D()
	_lorry_park = lorry_xf
	_crane_park = crane_xf
	if fresh or absf(host_age - age) > 1.5:
		age = host_age
	if fresh and is_inside_tree():
		_place()
	elif lorry and not leaving:
		_update_vehicles(0.0)


func _place() -> void:
	# Which side of the vehicles the pavement (the site) is on.
	var right := _lorry_park.basis.x
	_side = 1.0 if (at - _lorry_park.origin).dot(right) > 0.0 else -1.0
	var dir := _lorry_park.basis.z
	var side := right * _side
	var kit := Node3D.new()
	kit.name = "Kit"
	add_child(kit)
	# Barriers along the road side of the vehicles, a taper of cones behind.
	var a := _crane_park.origin - dir * 7.0
	var b := _lorry_park.origin + dir * 6.0
	var n := int(a.distance_to(b) / 2.0)
	for i in n + 1:
		var p := a.lerp(b, float(i) / n) - side * 2.4
		var br := _kit("barrier")
		br.transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z) + PI * 0.5), p)
		kit.add_child(br)
	for i in 6:
		var k := float(i) / 5.0
		var p := a - dir * (14.0 * (1.0 - k)) - side * lerpf(0.2, 2.4, k)
		kit.add_child(_cone(p))
	var sg := _kit("sign")
	sg.transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), a - dir * 18.0 + side * 0.4)
	kit.add_child(sg)
	var plate := Label3D.new()
	plate.text = "ROAD WORKS"
	plate.font_size = 40
	plate.outline_size = 0
	plate.pixel_size = 0.006
	plate.modulate = Color.BLACK
	plate.position = Vector3(0, 1.1, 0.02)
	sg.add_child(plate)
	# Round the work itself: cones on the pavement, the generator, trestles.
	for i in 8:
		var ang := TAU * i / 8.0
		kit.add_child(_cone(at + Vector3(cos(ang), 0, sin(ang)) * 6.5))
	var gen := _kit("generator")
	gen.position = at + side * 1.5 - dir * 4.0
	gen.position.y = at.y
	kit.add_child(gen)
	var tr := _kit("trestle_beam")
	tr.transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z) + PI * 0.5), trestle_point())
	kit.add_child(tr)
	var bk := _kit("bucket")
	bk.position = at + side * 0.8 + dir * 3.0
	kit.add_child(bk)
	# Solid once parked (officers can't walk through them, bullets clang).
	for v in [[lorry, Vector3(2.5, 3.3, 10.0), Vector3(0, 1.65, 0)], [crane, Vector3(2.55, 3.0, 11.0), Vector3(0, 1.5, -0.3)]]:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("surface", "metal")
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = v[1]
		cs.shape = bs
		cs.position = v[2]
		body.add_child(cs)
		body.name = "Solid"
		(v[0] as Node3D).add_child(body)
	_update_vehicles(0.0)


static var _cone_mesh: Mesh
static var _cone_mat: Material


func _cone(p: Vector3) -> MeshInstance3D:
	if _cone_mesh == null:
		var c := CylinderMesh.new()
		c.top_radius = 0.03
		c.bottom_radius = 0.17
		c.height = 0.7
		c.radial_segments = 10
		_cone_mesh = c
		_cone_mat = Cel.material(Color("ff6a13"), true, 0.012)
	var mi := MeshInstance3D.new()
	mi.mesh = _cone_mesh
	mi.material_override = _cone_mat
	mi.position = p + Vector3(0, 0.35, 0)
	return mi


## Where the trestles with a beam on them stand (on the pavement by the lorry).
func trestle_point() -> Vector3:
	var p := _lorry_park * Vector3(TRESTLE.x * _side, 0, TRESTLE.z)
	return Vector3(p.x, at.y, p.z)


## The top of the lorry's load, in the world.
func pick_point() -> Vector3:
	return _lorry_park * PICK


# --- every frame -----------------------------------------------------------------------

func _process(delta: float) -> void:
	if _lorry_park == Transform3D():
		return
	var cam := get_viewport().get_camera_3d()
	var near := cam != null and cam.global_position.distance_to(at) < SHOW_FX
	if leaving:
		_leave_t += delta
		_deploy = move_toward(_deploy, 0.0, delta * 0.5)
		if _deploy <= 0.0:
			_legs = move_toward(_legs, 0.0, delta * 0.5)
		_lift_piece = -1
		if _lift_load:
			_lift_load.visible = false
		for sl in _slings:
			(sl as Node3D).visible = false
		_update_vehicles(delta)
		_pose_crane(_hook_now)
		if _leave_t > 14.0:
			queue_free()
		return
	age += delta
	_update_vehicles(delta)
	if age < ARRIVE:
		return
	if not _parked:
		_parked = true
		if near:
			_play("works_beep", _crane_park.origin, -2.0, 50.0, 3)
	_legs = move_toward(_legs, 1.0, delta / SET_UP)
	var want := 1.0 if _legs >= 1.0 else 0.0
	var was := _deploy
	_deploy = move_toward(_deploy, want, delta * 0.3)
	if near and was == 0.0 and _deploy > 0.0:
		_play("works_hyd", _crane_park.origin, 0.0, 60.0)
	var hook := _rest_hook()
	if _lift_piece >= 0:
		if working:
			_lift_t += delta
		hook = _lift_step(near)
	_hook_now = hook
	_pose_crane(hook)
	_animate_crew(delta, near)


func _update_vehicles(delta: float) -> void:
	var k := clampf(age / ARRIVE, 0.0, 1.0)
	var ease := 1.0 - pow(1.0 - k, 2.2)
	var back := ROLL_IN * (1.0 - ease)
	var speed := ROLL_IN * 2.2 * pow(1.0 - k, 1.2) / ARRIVE if k < 1.0 else 0.0
	if leaving:
		var lk := clampf((_leave_t - 4.5) / 9.0, 0.0, 1.0)
		back = -ROLL_IN * 1.4 * lk * lk
		speed = ROLL_IN * 2.8 * lk / 9.0 if lk > 0.0 and lk < 1.0 else 0.0
		if lk >= 1.0:
			visible = false
	lorry.global_transform = _lorry_park.translated(-_lorry_park.basis.z * back)
	crane.global_transform = _crane_park.translated(-_crane_park.basis.z * back)
	if speed > 0.0 and delta > 0.0:
		for w in _wheels_l:
			(w as Node3D).rotate_object_local(Vector3.UP, speed * delta / 0.52)
		for w in _wheels_c:
			(w as Node3D).rotate_object_local(Vector3.UP, speed * delta / 0.62)
	for o in _outriggers:
		var n := o[0] as Node3D
		n.position.x = float(o[1]) + float(o[2]) * 2.1 * _legs


## Between lifts the hook waits over the lorry, high.
func _rest_hook() -> Vector3:
	return pick_point() + Vector3(0, SLING + 5.0, 0)


## The crane follows the hook: the slew turns to face it, the boom luffs and
## telescopes so its head is just above it, and the cable drops to it.
func _pose_crane(hook: Vector3) -> void:
	var base := _slew.get_parent() as Node3D
	var lc := base.to_local(hook)
	var d := lc - _slew.position
	var yaw := atan2(d.x, d.z)
	_slew.rotation.y = lerp_angle(0.0, yaw, _deploy)
	var piv := _boom.global_position
	var dh := Vector2(hook.x - piv.x, hook.z - piv.z).length()
	var dy := hook.y + 1.2 - piv.y
	var theta := clampf(atan2(dy, maxf(dh, 0.1)), deg_to_rad(4.0), deg_to_rad(78.0))
	var reach := dh / cos(theta)
	if reach < 12.0:
		reach = 12.0
		theta = acos(clampf(dh / 12.0, cos(deg_to_rad(78.0)), 1.0))
	var ext := clampf((reach - 12.0) / 3.0, 0.0, 10.0)
	theta = lerpf(-0.03, theta, _deploy)
	ext *= _deploy
	_boom.rotation.x = -theta
	for i in _secs.size():
		(_secs[i] as Node3D).position.z = float(_sec_z[i]) + ext
	if _ram_a and _ram_b:
		_span(_ram, _ram_a.global_position, _ram_b.global_position)
	var tip := _head.global_transform * Vector3(0, -0.4, 0.5)
	var show := _deploy > 0.6
	_hook.visible = show
	_cable.visible = show
	if show:
		var h := Vector3(tip.x, minf(hook.y, tip.y - 0.8), tip.z)
		h = h.lerp(Vector3(hook.x, h.y, hook.z), 0.0)
		_hook.global_transform = Transform3D(Basis(Vector3.UP, _slew.global_rotation.y), h)
		_span(_cable, tip, h)


# --- the lift ------------------------------------------------------------------------------

## Start lifting a piece back into place (every machine, from MSG_LIFT).
func start_lift(piece: int, length: float) -> void:
	if world == null or not world.pieces.has(piece):
		return
	var p: Dictionary = world.pieces[piece]
	var box: AABB = p.aabb
	var top := Vector3(box.get_center().x, box.end.y, box.get_center().z)
	_target = top + Vector3(0, SLING, 0)
	_load_h = box.size.y
	_load_size = box.size
	var xf: Transform3D = p.xform
	var hook_end := Transform3D(Basis(), _target)
	_load_off = hook_end.affine_inverse() * xf
	_yaw_end = _yaw_to(_target)
	if _lift_load == null:
		_lift_load = MeshInstance3D.new()
		add_child(_lift_load)
	var kit := KitLibrary.get_piece(p.kind)
	_lift_load.mesh = kit.mesh
	KitLibrary.tint(_lift_load, kit.surfaces, p.tint)
	_lift_load.visible = false
	_lift_piece = piece
	_lift_t = 0.0
	_lift_len = length
	_sounds_done.clear()
	_taken += 1
	_take_off_lorry(String(p.kind))


## A slab or a beam goes off the lorry's load (a few stay so it never looks
## empty).
func _take_off_lorry(kind: String) -> void:
	var beam := kind.begins_with("column")
	var names := ["load_beam_3", "load_beam_2"] if beam else ["load_slab_5", "load_slab_4", "load_slab_3", "load_slab_2"]
	for n in names:
		var it := lorry.find_child(n, true, false) as Node3D
		if it and it.visible:
			it.visible = false
			return


func _yaw_to(p: Vector3) -> float:
	var c := _slew.global_position
	return atan2(p.x - c.x, p.z - c.z)


## Cylindrical point round the slew: yaw, radius, height.
func _cyl(p: Vector3) -> Vector3:
	var c := _slew.global_position
	return Vector3(atan2(p.x - c.x, p.z - c.z), Vector2(p.x - c.x, p.z - c.z).length(), p.y)


func _uncyl(q: Vector3) -> Vector3:
	var c := _slew.global_position
	return Vector3(c.x + sin(q.x) * q.y, q.z, c.z + cos(q.x) * q.y)


func _swing(a: Vector3, b: Vector3, k: float) -> Vector3:
	var ca := _cyl(a)
	var cb := _cyl(b)
	return _uncyl(Vector3(lerp_angle(ca.x, cb.x, k), lerpf(ca.y, cb.y, k), lerpf(ca.z, cb.z, k)))


static func _seg(u: float, a: float, b: float) -> float:
	return smoothstep(0.0, 1.0, clampf((u - a) / (b - a), 0.0, 1.0))


## Where the hook is now in the lift, and the load on it.
func _lift_step(near: bool) -> Vector3:
	var u := _lift_t / _lift_len
	var pick := pick_point() + Vector3(0, _load_h + SLING, 0)
	var rest := _rest_hook()
	var high := maxf(pick.y, _target.y) + 3.0
	var pick_hi := Vector3(pick.x, high, pick.z)
	var tgt_hi := Vector3(_target.x, high, _target.z)
	var h: Vector3
	if u < 0.12:
		h = rest.lerp(pick, _seg(u, 0.0, 0.12))
	elif u < 0.2:
		h = pick
	elif u < 0.3:
		h = pick.lerp(pick_hi, _seg(u, 0.2, 0.3))
	elif u < 0.55:
		h = _swing(pick_hi, tgt_hi, _seg(u, 0.3, 0.55))
	elif u < 0.7:
		h = tgt_hi.lerp(_target, _seg(u, 0.55, 0.7))
	elif u < 0.8:
		h = _target
	elif u < 0.86:
		h = _target.lerp(tgt_hi, _seg(u, 0.8, 0.86))
	else:
		h = _swing(tgt_hi, rest, _seg(u, 0.86, 1.0))
	# The load: on from the sling-up until it's set in place.
	var carried := u >= 0.15 and u < RESTORE_AT + 0.01
	if world and world.pieces.has(_lift_piece) and world.pieces[_lift_piece].state == "intact" and u > 0.5:
		carried = false    # already put back (the host's restore came in)
	_lift_load.visible = carried
	var hook_rot := _cyl(h).x - _yaw_end
	if carried:
		var hx := Transform3D(Basis(Vector3.UP, hook_rot), h)
		_lift_load.global_transform = hx * _load_off
		var tip := h - Vector3(0, 1.15, 0)
		var hs := Vector3(_load_size.x * 0.4, 0, _load_size.z * 0.4)
		var top := h - Vector3(0, SLING, 0)
		for i in 4:
			var c := Vector3(hs.x * (1 if i & 1 else -1), 0, hs.z * (1 if i & 2 else -1))
			_span(_slings[i], tip, top + Basis(Vector3.UP, hook_rot) * c)
	else:
		for sl in _slings:
			(sl as Node3D).visible = false
	if near:
		_lift_sound(u, "pick", 0.12, "works_chain", pick)
		_lift_sound(u, "up", 0.2, "works_hyd", _crane_park.origin)
		_lift_sound(u, "land", 0.68, "works_chain", _target - Vector3(0, SLING, 0))
		_lift_sound(u, "set", RESTORE_AT, "impact_concrete", _target - Vector3(0, SLING, 0))
	if u >= 1.0:
		_lift_piece = -1
		_lift_load.visible = false
		for sl in _slings:
			(sl as Node3D).visible = false
		return rest
	return h


func _lift_sound(u: float, tag: String, at_u: float, stem: String, pos: Vector3) -> void:
	if u >= at_u and not _sounds_done.has(tag):
		_sounds_done[tag] = true
		_play(stem, pos, 0.0, 70.0)


func _play(stem: String, pos: Vector3, db := 0.0, dist := 60.0, times := 1) -> void:
	for i in times:
		if i == 0:
			Sfx.play(self, stem, pos, db, dist)
		else:
			Sfx.later(self, float(i), stem, pos, db, dist)


## The hook's load is low enough to grab (slinger, banksman).
func load_low() -> bool:
	if _lift_piece < 0:
		return false
	var u := _lift_t / _lift_len
	return (u > 0.08 and u < 0.24) or (u > 0.6 and u < 0.8)


## Drive away (the site's done).
func leave() -> void:
	leaving = true
	_leave_t = 0.0
	var kit := get_node_or_null("Kit")
	if kit:
		kit.queue_free()
	for c in [lorry, crane]:
		var s := (c as Node).get_node_or_null("Solid")
		if s:
			s.queue_free()
	for nid in _crew.keys():
		_drop_worker(nid)


# --- the crew -----------------------------------------------------------------------------

## Who's doing what (from the host): {net_id: [job, point]}.
func set_crew(jobs: Dictionary, suspects: Dictionary) -> void:
	for nid in _crew.keys():
		if not jobs.has(nid):
			_drop_worker(nid)
	for nid in jobs:
		var w: Suspect = suspects.get(nid)
		if w == null or not is_instance_valid(w):
			continue
		var job: int = jobs[nid][0]
		var c: Dictionary = _crew.get(nid, {})
		if c.is_empty() or c.job != job:
			if not c.is_empty():
				_drop_worker(nid)
			c = {"w": w, "job": job, "tool": _tool_for(job), "visor": null, "t": randf() * 3.0, "on": false}
			if job == Job.WELD:
				c.visor = _kit("weld_visor")
				add_child(c.visor)
			if c.tool:
				add_child(c.tool)
			_crew[nid] = c
		c.point = jobs[nid][1]
		w.work_crouch = job in [Job.WELD, Job.SHOVEL]


func _tool_for(job: int) -> Node3D:
	match job:
		Job.DRILL:
			return _kit("drill")
		Job.WELD:
			return _kit("weld_torch")
		Job.GRIND:
			return _kit("grinder")
		Job.SHOVEL:
			return _kit("shovel")
		Job.SWEEP:
			return _kit("broom")
	return null


func _drop_worker(nid: int) -> void:
	var c: Dictionary = _crew.get(nid, {})
	_crew.erase(nid)
	if c.is_empty():
		return
	for k in ["tool", "visor"]:
		if c[k] and is_instance_valid(c[k]):
			(c[k] as Node).queue_free()
	var w = c.w
	if is_instance_valid(w):
		(w as Suspect).work_crouch = false
		var r := (w as Suspect).rig
		if r and r.procedural:
			r.procedural.work_weight = 0.0


func _animate_crew(delta: float, near: bool) -> void:
	var spark_at := Vector3.INF
	var spark_dir := Vector3.UP
	var spark_big := false
	var dust_at := Vector3.INF
	for nid in _crew.keys():
		var c: Dictionary = _crew[nid]
		var w = c.w
		if not is_instance_valid(w):
			_drop_worker(nid)
			continue
		var s := w as Suspect
		var r := s.rig
		if r == null or r.procedural == null:
			continue
		var hs := Vector2(s.velocity.x, s.velocity.z).length() if s.is_host_side() else s.net_speed
		var busy := s.state == Suspect.S.WANDER and hs < 0.3 and working and r.downed == false
		var pr := r.procedural
		var tool := c.tool as Node3D
		var visor := c.visor as Node3D
		if not busy:
			pr.work_weight = move_toward(pr.work_weight, 0.0, delta * 3.0)
			if tool:
				tool.visible = false
			if visor:
				visor.visible = false
			continue
		c.t += delta
		var t: float = c.t
		var pos := s.global_position
		var fwd := s.global_transform.basis.z
		fwd = Vector3(fwd.x, 0, fwd.z).normalized()
		var right := fwd.cross(Vector3.UP)
		var crouch := s.work_crouch
		var chest := pos + Vector3(0, 0.85 if crouch else 1.3, 0)
		var point: Vector3 = c.point
		var weight := 1.0
		var l := chest
		var rr := chest
		match int(c.job):
			Job.SLING:
				if load_low() and _hook_now.distance_to(pos) < 6.0:
					var g := _hook_now - Vector3(0, SLING - 0.1, 0)
					g.y = minf(g.y, pos.y + 2.0)
					l = g - right * 0.25
					rr = g + right * 0.25
				else:
					weight = 0.0
			Job.BANKSMAN:
				var to := (_hook_now - chest)
				if load_low() and to.length() < 5.0:
					# Hands on the load, steadying it in.
					var g := _hook_now - Vector3(0, SLING + 0.3, 0)
					g.y = clampf(g.y, pos.y + 0.9, pos.y + 2.1)
					l = g - right * 0.3
					rr = g + right * 0.3
				else:
					# Signalling the driver: one arm up, a slow circling hand.
					l = chest + Vector3(0, 0.72 + sin(t * 2.0) * 0.06, 0) - right * 0.28 + fwd * 0.1
					var dir := Vector3(to.x, 0, to.z).normalized() if to.length() > 0.1 else fwd
					rr = chest + right * 0.2 + dir * 0.45 + Vector3(0, 0.25 + sin(t * 3.0) * 0.12, 0)
			Job.DRILL:
				var on := fmod(t, 3.0) < 1.7
				var j := Vector3(randf_range(-0.01, 0.01), randf_range(-0.01, 0.01), 0) if on else Vector3.ZERO
				rr = chest + fwd * 0.42 + right * 0.1 + j
				l = chest + fwd * 0.48 - right * 0.08 + Vector3(0, 0.08, 0) + j
				if tool:
					tool.global_transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP), rr)
				if on and near:
					dust_at = rr + fwd * 0.3
					_sound_burst(nid, "works_drill", rr, 3.0)
			Job.WELD:
				var on := fmod(t, 4.5) < 3.0
				rr = chest + fwd * 0.42 + right * 0.06 + Vector3(0, -0.15, 0)
				l = chest + fwd * 0.3 - right * 0.22 + Vector3(0, -0.1, 0)
				if tool:
					tool.global_transform = Transform3D(Basis.looking_at(-(fwd - Vector3(0, 0.6, 0)).normalized(), Vector3.UP), rr)
				if visor:
					visor.visible = true
					var head := pos + Vector3(0, 1.2, 0) + fwd * 0.12
					if r.skeleton:
						var hb := r.skeleton.find_bone("head_2")
						if hb >= 0:
							head = r.skeleton.global_transform * r.skeleton.get_bone_global_pose(hb).origin + fwd * 0.12 + Vector3(0, 0.08, 0)
					visor.global_transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP).rotated(right, -0.2 if on else 0.9), head)
				if on and near:
					spark_at = rr + fwd * 0.2 + Vector3(0, -0.1, 0)
					spark_dir = Vector3.UP
					_sound_burst(nid, "works_weld", rr, 2.1)
			Job.GRIND:
				var on := fmod(t, 4.0) < 2.6
				rr = chest + fwd * 0.4 + right * 0.18 + Vector3(0, -0.28, 0)
				l = chest + fwd * 0.4 - right * 0.2 + Vector3(0, -0.22, 0)
				if tool:
					tool.global_transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP), (l + rr) * 0.5 + fwd * 0.05)
				if on and near:
					spark_at = (l + rr) * 0.5 + fwd * 0.18 + Vector3(0, -0.08, 0)
					spark_dir = (right * 0.8 - Vector3(0, 0.2, 0) + fwd * 0.2).normalized()
					spark_big = true
					_sound_burst(nid, "works_grind", spark_at, 2.0)
			Job.SHOVEL:
				var k := fmod(t, 2.4) / 2.4
				var scoop := sin(k * TAU) * 0.5 + 0.5
				var blade := pos + fwd * 0.9 + Vector3(0, 0.05 + scoop * 0.5, 0) + right * scoop * 0.3
				rr = pos + fwd * 0.45 + Vector3(0, 0.55 + scoop * 0.35, 0) + right * 0.12
				l = pos + fwd * 0.15 + Vector3(0, 0.8 + scoop * 0.3, 0) - right * 0.1
				if tool:
					var up := (l - blade).normalized()
					tool.global_transform = Transform3D(Basis.looking_at(-(blade - l).normalized(), right), blade.lerp(l, 0.5))
					tool.global_position = l + (blade - l) * 0.5
				if near and k < 0.08:
					dust_at = blade
			Job.SWEEP:
				var swing := sin(t * 3.2)
				var head := pos + fwd * 0.85 + right * swing * 0.35 + Vector3(0, 0.05, 0)
				rr = pos + Vector3(0, 0.95, 0) + fwd * 0.35 + right * swing * 0.12
				l = pos + Vector3(0, 1.25, 0) + fwd * 0.15 + right * swing * 0.05
				if tool:
					tool.global_transform = Transform3D(Basis.looking_at(-(head - l).normalized(), Vector3.UP), (head + l) * 0.5)
		if tool:
			tool.visible = true
			if int(c.job) in [Job.DRILL, Job.GRIND]:
				tool.scale_object_local(Vector3.ONE * 1.5)    # read at a distance
		pr.work_weight = move_toward(pr.work_weight, weight, delta * 3.0)
		pr.work_l = l
		pr.work_r = rr
	_fx(spark_at, spark_dir, spark_big, dust_at)


func _sound_burst(nid: int, stem: String, pos: Vector3, gap: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_snd_t.get(nid, -99.0)) >= gap:
		_snd_t[nid] = now
		Sfx.play(self, stem, pos, -2.0, 45.0)


# --- sparks and dust -----------------------------------------------------------------------

func _make_fx() -> void:
	_sparks = CPUParticles3D.new()
	_sparks.amount = 40
	_sparks.lifetime = 0.55
	_sparks.emitting = false
	_sparks.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.025)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.75, 0.3)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.6, 0.15)
	m.emission_energy_multiplier = 4.0
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = m
	_sparks.mesh = q
	_sparks.direction = Vector3.UP
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 2.0
	_sparks.initial_velocity_max = 5.0
	_sparks.gravity = Vector3(0, -9.8, 0)
	_sparks.scale_amount_min = 0.6
	_sparks.scale_amount_max = 1.4
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sparks)
	_dust = CPUParticles3D.new()
	_dust.amount = 16
	_dust.lifetime = 1.2
	_dust.emitting = false
	_dust.local_coords = false
	var dq := QuadMesh.new()
	dq.size = Vector2(0.18, 0.18)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.75, 0.72, 0.66, 0.45)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.vertex_color_use_as_albedo = true
	dq.material = dm
	_dust.mesh = dq
	_dust.direction = Vector3.UP
	_dust.spread = 50.0
	_dust.initial_velocity_min = 0.3
	_dust.initial_velocity_max = 0.9
	_dust.gravity = Vector3(0, 0.1, 0)
	_dust.scale_amount_min = 0.6
	_dust.scale_amount_max = 1.8
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.8))
	g.set_color(1, Color(1, 1, 1, 0.0))
	_dust.color_ramp = g
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dust)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(0.75, 0.85, 1.0)
	_flash.omni_range = 5.0
	_flash.shadow_enabled = false
	_flash.visible = false
	add_child(_flash)


func _fx(spark_at: Vector3, spark_dir: Vector3, big: bool, dust_at: Vector3) -> void:
	_sparks.emitting = spark_at != Vector3.INF
	if _sparks.emitting:
		_sparks.global_position = spark_at
		_sparks.direction = spark_dir
		_sparks.spread = 25.0 if big else 80.0
		_sparks.initial_velocity_max = 7.0 if big else 3.5
	_flash.visible = spark_at != Vector3.INF and not big
	if _flash.visible:
		_flash.global_position = spark_at + Vector3(0, 0.3, 0)
		_flash.light_energy = randf_range(1.5, 4.0)
	_dust.emitting = dust_at != Vector3.INF
	if _dust.emitting:
		_dust.global_position = dust_at
