class_name CarSync
extends Node
## Networks the cars. Two driving authority modes, switchable by the host:
##
##  HOST:   the driver sends inputs; the host simulates the car and everyone,
##          the driver included, sees it interpolated from snapshots. Fair for
##          collisions, but the driver feels round trip plus buffer delay.
##  DRIVER: the driver's machine simulates its own car and streams its state
##          to the host, which moves its copy kinematically and relays it.
##          Steering is instant for the driver; others see the car slightly
##          in the past, and host-side rubble reacts to the kinematic copy.
##
## Dents and the bumper are events sent by whoever simulates the car.

const MSG_CAR_INPUT := 30
const MSG_CAR_STATE := 31   # driver -> host (DRIVER mode)
const MSG_CAR_SNAP := 32    # host -> all
const MSG_CAR_DENT := 33
const MSG_CAR_MODE := 34
const MSG_CAR_HIT := 35     # driver -> host: hit a building piece

enum Mode { HOST, DRIVER }

var mode := Mode.DRIVER
var cars: Array = []          # Car, index = slot
var destruction: DestructionWorld
var sync: PawnSync            # only for its clock when present
var _owner := {}              # car index -> peer id
var _buffers := {}            # car index -> [[time, state]]
var _inputs := {}             # host: car index -> latest input dict
var _clock := 0.0
var _tick := 0


func _ready() -> void:
	Net.register(MSG_CAR_INPUT, _on_input)
	Net.register(MSG_CAR_STATE, _on_state)
	Net.register(MSG_CAR_SNAP, _on_snap)
	Net.register(MSG_CAR_DENT, _on_dent)
	Net.register(MSG_CAR_MODE, _on_mode)
	Net.register(MSG_CAR_HIT, _on_hit)


func _exit_tree() -> void:
	for m in [MSG_CAR_INPUT, MSG_CAR_STATE, MSG_CAR_SNAP, MSG_CAR_DENT, MSG_CAR_MODE, MSG_CAR_HIT]:
		Net.unregister(m)


func add_car(car: Car) -> void:
	car.net_id = cars.size()
	cars.append(car)
	var idx := car.net_id
	car.dented.connect(func(p, d, a): _local_dent(idx, p, d, a))
	car.hit_piece.connect(func(pid, imp): _local_hit(pid, imp))


## Car index driven by a peer: slot order in the lobby.
func car_for(peer_id: int) -> int:
	return Net.player_ids().find(peer_id)


func driver_of(idx: int) -> int:
	var ids := Net.player_ids()
	return ids[idx] if idx < ids.size() else 1


func simulates_locally(idx: int) -> bool:
	if Net.is_host():
		return mode == Mode.HOST or driver_of(idx) == 1 or not Net.player_ids().has(driver_of(idx))
	return mode == Mode.DRIVER and driver_of(idx) == Net.my_id()


func set_mode(m: Mode) -> void:
	if not Net.is_host():
		return
	var b := PackedByteArray([m])
	Net.broadcast(MSG_CAR_MODE, b)
	_on_mode(1, b)


func _on_mode(from: int, data: PackedByteArray) -> void:
	if from != 1:
		return
	mode = data[0] as Mode
	_buffers.clear()


func _physics_process(delta: float) -> void:
	_tick += 1
	_clock += delta
	for i in cars.size():
		var car: Car = cars[i]
		var local := simulates_locally(i)
		if car.freeze == local:
			car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			car.freeze = not local
	# Driver input.
	var mine := car_for(Net.my_id())
	if mine >= 0 and mine < cars.size():
		var inp := {
			"throttle": Input.get_axis("move_back", "move_forward"),
			"steer": Input.get_axis("move_right", "move_left"),
			"handbrake": Input.is_action_pressed("handbrake"),
			"horn": Input.is_action_pressed("horn"),
		}
		if simulates_locally(mine):
			_apply_input(cars[mine], inp)
		else:
			var b := StreamPeerBuffer.new()
			b.put_u8(mine)
			b.put_half(inp.throttle)
			b.put_half(inp.steer)
			b.put_u8((1 if inp.handbrake else 0) | (2 if inp.horn else 0))
			Net.send(1, MSG_CAR_INPUT, b.data_array, Net.UNRELIABLE, 2)
	if Net.is_host():
		for i in _inputs:
			if i < cars.size() and simulates_locally(i):
				_apply_input(cars[i], _inputs[i])
		if _tick % 3 == 0 and Net.is_online():
			var b := StreamPeerBuffer.new()
			b.put_double(_clock)
			b.put_u8(cars.size())
			for c in cars:
				c.encode_state(b)
			Net.broadcast(MSG_CAR_SNAP, b.data_array, Net.ORDERED, 3)
	elif mode == Mode.DRIVER and mine >= 0 and mine < cars.size() and _tick % 2 == 0:
		var b := StreamPeerBuffer.new()
		b.put_double(_clock)
		b.put_u8(mine)
		cars[mine].encode_state(b)
		Net.send(1, MSG_CAR_STATE, b.data_array, Net.ORDERED, 3)
	_interpolate()


func _apply_input(car: Car, inp: Dictionary) -> void:
	var t: float = inp.throttle
	var fwd_speed := car.linear_velocity.dot(car.global_transform.basis.z)
	# Pulling back while rolling forward brakes; when stopped, it reverses.
	if t < 0.0 and fwd_speed > 1.0:
		car.throttle = 0.0
		car.brake = -t
	else:
		car.throttle = t
		car.brake = 0.0
	car.steer = inp.steer
	car.handbrake = inp.handbrake
	car.horn = inp.get("horn", false)


func _on_input(from: int, data: PackedByteArray) -> void:
	if not Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var idx := b.get_u8()
	if driver_of(idx) != from:
		return
	var th := b.get_half()
	var st := b.get_half()
	var flags := b.get_u8()
	_inputs[idx] = {"throttle": th, "steer": st, "handbrake": (flags & 1) != 0, "horn": (flags & 2) != 0}


func _push(idx: int, t: float, s: Dictionary) -> void:
	var buf: Array = _buffers.get(idx, [])
	buf.append([t, s, _clock])
	while buf.size() > 20:
		buf.pop_front()
	_buffers[idx] = buf


func _on_state(from: int, data: PackedByteArray) -> void:
	if not Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var t := b.get_double()
	var idx := b.get_u8()
	if driver_of(idx) != from or mode != Mode.DRIVER:
		return
	_push(idx, t, Car.decode_state(b))


func _on_snap(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var t := b.get_double()
	var n := b.get_u8()
	for i in n:
		var s := Car.decode_state(b)
		if i < cars.size() and not simulates_locally(i):
			_push(i, t, s)


## Plays remote cars 100 ms behind the newest state, mapped onto local time.
func _interpolate() -> void:
	for idx in _buffers:
		var buf: Array = _buffers[idx]
		if buf.is_empty() or idx >= cars.size() or simulates_locally(idx):
			continue
		var car: Car = cars[idx]
		var newest: Array = buf.back()
		# Sender clock -> our clock offset, from the newest arrival.
		var offset: float = newest[2] - newest[0]
		var rt := _clock - offset - 0.1
		while buf.size() >= 3 and buf[1][0] <= rt:
			buf.pop_front()
		var s: Dictionary
		if buf.size() >= 2 and buf[0][0] <= rt:
			var a: Dictionary = buf[0][1]
			var c: Dictionary = buf[1][1]
			var k: float = clamp((rt - buf[0][0]) / max(buf[1][0] - buf[0][0], 0.0001), 0.0, 1.0)
			s = {"pos": a.pos.lerp(c.pos, k), "rot": (a.rot as Quaternion).slerp(c.rot, k), "lv": a.lv.lerp(c.lv, k), "av": a.av.lerp(c.av, k), "steer": lerpf(a.steer, c.steer, k), "horn": c.horn}
		else:
			s = buf[0][1]
		car.global_transform = Transform3D(Basis(s.rot), s.pos)
		car.linear_velocity = s.lv
		car.angular_velocity = s.av
		car.steer = s.steer
		car.horn = s.get("horn", false)


func _local_dent(idx: int, p: Vector3, d: Vector3, a: float) -> void:
	if not simulates_locally(idx):
		return
	var b := StreamPeerBuffer.new()
	b.put_u8(idx)
	for v in [p, d]:
		b.put_float(v.x)
		b.put_float(v.y)
		b.put_float(v.z)
	b.put_float(a)
	if Net.is_host():
		Net.broadcast(MSG_CAR_DENT, b.data_array)
	else:
		Net.send(1, MSG_CAR_DENT, b.data_array)
	cars[idx].apply_dent(p, d, a)


func _on_dent(from: int, data: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var idx := b.get_u8()
	if Net.is_host():
		if driver_of(idx) != from:
			return
		Net.broadcast(MSG_CAR_DENT, data)  # relay to the other client
	var p := Vector3(b.get_float(), b.get_float(), b.get_float())
	var d := Vector3(b.get_float(), b.get_float(), b.get_float())
	cars[idx].apply_dent(p, d, b.get_float())


func _local_hit(piece_id: int, imp: float) -> void:
	if destruction == null:
		return
	if Net.is_host():
		destruction.damage_piece(piece_id, imp / 160.0, Vector3.ZERO, 2.0)
	else:
		var b := StreamPeerBuffer.new()
		b.put_u32(piece_id)
		b.put_float(imp)
		Net.send(1, MSG_CAR_HIT, b.data_array)


func _on_hit(_from: int, data: PackedByteArray) -> void:
	if not Net.is_host() or destruction == null:
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var pid := b.get_u32()
	var imp: float = min(b.get_float(), 60000.0)
	if destruction.pieces.has(pid):
		destruction.damage_piece(pid, imp / 160.0, destruction.pieces[pid].aabb.get_center(), 2.0)
