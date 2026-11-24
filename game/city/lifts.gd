class_name Lifts
extends Node3D
## v0.10.0: the lifts in the downtown towers. One car per tower runs up and
## down the shaft beside the stairs (CityStyles._shaft). Press the use key
## at a lift door to call it; inside, press it again for the floor buttons.
## The doors on a floor slide open only while the car is standing there.
##
## The host runs the cars and sends where they are to everyone; clients run
## the same movement in between, so riding one feels smooth. Suspects and
## the AI take the stairs.

const MSG_LIFTS := 130      # host -> all: every car's y, target floor, doors (4x a second)
const MSG_LIFT_CALL := 131  # client -> host: lift (u8), floor (u8)
const SPEED := 3.2          # m/s: ten storeys in about ten seconds
const OPEN_TIME := 4.0      # doors stay open this long at a stop
const DOOR_SPEED := 1.6     # door slide, fractions per second
const CALL_REACH := 1.8
const CAR := 3.6            # the car's inside, metres square
const DOOR_W := 1.05        # the panel over the 1 m doorway

static var current: Lifts

## Each: {building, floors, origin (shaft centre, ground floor level), u, v,
## car: AnimatableBody3D, doors: Array of Node3D, y, target, queue: Array,
## wait, open (0..1), front (world position outside the ground floor door)}.
var lifts: Array = []
var _send_t := 0.0


func _ready() -> void:
	current = self
	Net.register(MSG_LIFTS, _on_state)
	Net.register(MSG_LIFT_CALL, _on_call)


func _exit_tree() -> void:
	if current == self:
		current = null
	Net.unregister(MSG_LIFTS)
	Net.unregister(MSG_LIFT_CALL)


## One lift per tower in the city.
func build(gen: CityGenerator) -> void:
	for b in gen.buildings:
		if b.get("lift", false):
			_add_lift(b)


func _add_lift(b: Dictionary) -> void:
	var M := BlockGenerator.M
	var sr := CityStyles.shaft_rect(b)
	var u: Vector3 = b.u
	var v: Vector3 = b.v
	var origin: Vector3 = (b.origin as Vector3) + u * sr.get_center().x + v * sr.get_center().y
	var basis := Basis(u, Vector3.UP, v)
	var L := {"building": b, "floors": int(b.storeys), "origin": origin, "u": u, "v": v,
		"y": 0.0, "target": 0, "queue": [], "wait": 0.0, "open": 0.0, "doors": []}
	# The car: a floor you stand on, a back wall with a mirror strip, a
	# handrail and a lit ceiling.
	var car := AnimatableBody3D.new()
	car.name = "LiftCar%d" % lifts.size()
	car.sync_to_physics = false
	car.collision_layer = 1
	car.collision_mask = 0
	car.transform = Transform3D(basis, origin)
	_box(car, Vector3(CAR, 0.2, CAR), Vector3(0, -0.1, 0), Color("4a4f55"), true)
	_box(car, Vector3(CAR, 2.6, 0.06), Vector3(0, 1.3, CAR * 0.5), Color("9aa1a8"), true)
	_box(car, Vector3(CAR * 0.9, 1.1, 0.02), Vector3(0, 1.45, CAR * 0.5 - 0.04), Color("c9d6de"), false)
	_box(car, Vector3(CAR * 0.8, 0.05, 0.05), Vector3(0, 0.95, CAR * 0.5 - 0.12), Color("cfcfcf"), false)
	for side in [-1.0, 1.0]:
		_box(car, Vector3(0.06, 2.6, CAR), Vector3(side * CAR * 0.5, 1.3, 0), Color("8d949b"), true)
	var lid := _box(car, Vector3(CAR, 0.08, CAR), Vector3(0, 2.64, 0), Color("dfe4e8"), true)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.3, 0)
	lamp.omni_range = 4.0
	lamp.light_energy = 0.7
	lamp.light_color = Color("fff3dc")
	lid.add_child(lamp)
	add_child(car)
	L.car = car
	# A door panel in front of the doorway on every floor (shaft side).
	for f in L.floors:
		var door := StaticBody3D.new()
		door.name = "LiftDoor%d_%d" % [lifts.size(), f]
		door.collision_layer = 1
		door.transform = Transform3D(basis, _door_base(L, f))
		_box(door, Vector3(DOOR_W, 2.2, 0.05), Vector3(0, 1.1, 0), Color("b8bec4"), true)
		_box(door, Vector3(0.6, 0.16, 0.02), Vector3(0, 2.45, -0.06), Color("1c1f22"), false)
		var sign_ := Label3D.new()
		sign_.text = "G" if f == 0 else str(f)
		sign_.font_size = 48
		sign_.pixel_size = 0.004
		sign_.modulate = Color("ffb030")
		sign_.position = Vector3(0, 2.45, -0.08)
		sign_.rotation.y = PI
		door.add_child(sign_)
		add_child(door)
		L.doors.append(door)
	lifts.append(L)
	_place(L)


## The doorway on floor f, just inside the shaft.
static func _door_base(L: Dictionary, f: int) -> Vector3:
	return (L.origin as Vector3) - (L.v as Vector3) * (BlockGenerator.M * 0.5 - 0.12) + Vector3.UP * floor_height(f)


static func floor_height(f: int) -> float:
	return f * BlockGenerator.STOREY


## Where you stand to call the lift on floor f (just outside its door).
static func call_point(L: Dictionary, f: int) -> Vector3:
	return (L.origin as Vector3) - (L.v as Vector3) * (BlockGenerator.M * 0.5 + 0.9) + Vector3.UP * floor_height(f)


func _box(parent: Node3D, size: Vector3, at: Vector3, colour: Color, solid: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = Cel.material(colour)
	mi.position = at
	parent.add_child(mi)
	if solid:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = at
		parent.add_child(cs)
	return mi


# --- running -----------------------------------------------------------------------

## The floor the car stands at (or is passing).
static func floor_of(L: Dictionary) -> int:
	return clampi(roundi(float(L.y) / BlockGenerator.STOREY), 0, int(L.floors) - 1)


static func moving(L: Dictionary) -> bool:
	return absf(float(L.y) - floor_height(L.target)) > 0.01


## Anyone: send the lift to floor f (the host runs it).
func ask(li: int, f: int) -> void:
	if Net.is_host():
		request(li, f)
	else:
		var b := StreamPeerBuffer.new()
		b.put_u8(li)
		b.put_u8(f)
		Net.send(1, MSG_LIFT_CALL, b.data_array)


## Host: a call for lift li to floor f.
func request(li: int, f: int) -> void:
	if li < 0 or li >= lifts.size():
		return
	var L: Dictionary = lifts[li]
	f = clampi(f, 0, int(L.floors) - 1)
	if f == L.target and not moving(L):
		L.wait = OPEN_TIME    # already here: hold the doors
		return
	if f != L.target and not (L.queue as Array).has(f):
		(L.queue as Array).append(f)
		L.wait = minf(float(L.wait), 1.0)    # somewhere to be: doors shut soon


func _on_call(_from: int, data: PackedByteArray) -> void:
	if not Net.is_host() or data.size() < 2:
		return
	request(data[0], data[1])


func _physics_process(delta: float) -> void:
	for li in lifts.size():
		_step(lifts[li], delta)
	if Net.is_host() and Net.is_online():
		_send_t -= delta
		if _send_t <= 0.0:
			_send_t = 0.25
			var b := StreamPeerBuffer.new()
			b.put_u8(lifts.size())
			for L in lifts:
				b.put_float(L.y)
				b.put_u8(L.target)
				b.put_half(L.wait)
			Net.broadcast(MSG_LIFTS, b.data_array, Net.ORDERED)


func _step(L: Dictionary, delta: float) -> void:
	var goal := floor_height(L.target)
	var y: float = L.y
	var doors_shut: bool = L.open <= 0.0
	if absf(y - goal) > 0.001:
		# Doors shut before it moves.
		L.open = maxf(float(L.open) - DOOR_SPEED * delta, 0.0)
		if doors_shut:
			L.y = move_toward(y, goal, SPEED * delta)
			if absf(float(L.y) - goal) <= 0.001:
				L.y = goal
				L.wait = OPEN_TIME
				Sfx.play(self, "lift_ding", L.car.global_position + Vector3.UP * 2.0, -4.0, 25.0, 0.0)
	else:
		L.wait = maxf(float(L.wait) - delta, 0.0)
		if L.wait > 0.0:
			L.open = minf(float(L.open) + DOOR_SPEED * delta, 1.0)
		else:
			L.open = maxf(float(L.open) - DOOR_SPEED * delta, 0.0)
			if Net.is_host() and not (L.queue as Array).is_empty() and L.open <= 0.0:
				L.target = (L.queue as Array).pop_front()
	_place(L)


func _place(L: Dictionary) -> void:
	var car: AnimatableBody3D = L.car
	car.global_position = (L.origin as Vector3) + Vector3.UP * float(L.y)
	var here := floor_of(L) if not moving(L) else -1
	for f in (L.doors as Array).size():
		var door: Node3D = L.doors[f]
		var o: float = L.open if f == here else 0.0
		door.global_position = _door_base(L, f) + (L.u as Vector3) * (DOOR_W * o)


func _on_state(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var n := mini(b.get_u8(), lifts.size())
	for i in n:
		var L: Dictionary = lifts[i]
		var y := b.get_float()
		L.target = b.get_u8()
		L.wait = b.get_half()
		if absf(y - float(L.y)) > 0.6:
			L.y = y
		if L.wait > 0.0 and not moving(L):
			L.open = maxf(float(L.open), 0.01)


# --- players -----------------------------------------------------------------------

## The lift p is standing in, or -1.
func lift_inside(p: Vector3) -> int:
	for li in lifts.size():
		var L: Dictionary = lifts[li]
		var rel := p - (L.origin as Vector3)
		var lx := rel.dot(L.u)
		var lz := rel.dot(L.v)
		var ly := rel.y - float(L.y)
		if absf(lx) < CAR * 0.5 and absf(lz) < CAR * 0.5 and ly > -0.6 and ly < 2.2:
			return li
	return -1


## [lift, floor] of the lift door p is standing at, or [-1, -1].
func door_near(p: Vector3) -> Array:
	for li in lifts.size():
		var L: Dictionary = lifts[li]
		var rel := p - call_point(L, 0)
		if Vector2(rel.dot(L.u), rel.dot(L.v)).length() > CALL_REACH:
			continue
		var f := roundi(rel.y / BlockGenerator.STOREY)
		if f >= 0 and f < int(L.floors) and absf(rel.y - floor_height(f)) < 1.2:
			return [li, f]
	return [-1, -1]


## One line for the HUD about the lift here, or "".
func prompt_for(p: Vector3) -> String:
	var use := Controls.key_name("interact")
	var inside := lift_inside(p)
	if inside >= 0:
		var L: Dictionary = lifts[inside]
		return "LIFT  floor %s   %s choose a floor" % [floor_name(floor_of(L)), use]
	var at := door_near(p)
	if at[0] >= 0:
		var L: Dictionary = lifts[at[0]]
		if not moving(L) and floor_of(L) == at[1] and float(L.open) > 0.5:
			return "LIFT is here"
		return "%s call the lift (at %s)" % [use, floor_name(floor_of(L))]
	return ""


## The use key, for the local officer: call the lift or open the buttons.
## Returns true when it was for a lift.
func use(p: Vector3, tree: SceneTree) -> bool:
	var inside := lift_inside(p)
	if inside >= 0:
		LiftPanel.open(tree, self, inside)
		return true
	var at := door_near(p)
	if at[0] >= 0:
		ask(at[0], at[1])
		return true
	return false


static func floor_name(f: int) -> String:
	return "G" if f == 0 else str(f)
