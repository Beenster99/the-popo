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
const MSG_CAR_SHOT := 36    # host -> all: a bullet broke a window
const MSG_CAR_FIRE := 37    # host -> all: a car smokes, burns or is a wreck (Phase 1.5)

## Phase 1.5: cars take damage from bullets, crashes, blasts and fire. Low,
## they smoke; at nothing they catch fire, and a few seconds later go up.
const CAR_HP := 100.0
const SMOKE_AT := 40.0
const BURN_TIME := 7.0
const TANK_DAMAGE := 12.0     # a bullet in the fuel tank (low at the back)
const BODY_DAMAGE := 3.0
enum Fire { OK, SMOKING, BURNING, WRECKED }
const SIZE_Z_TANK := 1.3      # m behind the middle where the tank is

enum Mode { HOST, DRIVER }

var mode := Mode.DRIVER
var cars: Array = []          # Car, index = slot
var destruction: DestructionWorld
var sync: PawnSync            # only for its clock when present
## Drivers come from the officers in the driver's seats (Phase 1.3), instead
## of one car per player slot (the Phase 0.4 car spike).
var use_seats := false
## Host: inputs for cars nobody is driving, by car index (the traffic stop's
## speeding car). Without one, an empty car is parked with the handbrake on.
var ai_inputs := {}
var _owner := {}              # car index -> peer id
var _buffers := {}            # car index -> [[time, state]]
var _inputs := {}             # host: car index -> latest input dict
var _clock := 0.0
var _light_want := {}         # car index -> [lights, siren] asked for, until it shows
var _tick := 0
var car_hp := {}             # car index -> hp (host)
var fire_state := {}         # car index -> Fire
var _burn_t := {}            # host: car index -> s until it goes up


func _ready() -> void:
	Net.register(MSG_CAR_INPUT, _on_input)
	Net.register(MSG_CAR_STATE, _on_state)
	Net.register(MSG_CAR_SNAP, _on_snap)
	Net.register(MSG_CAR_DENT, _on_dent)
	Net.register(MSG_CAR_MODE, _on_mode)
	Net.register(MSG_CAR_HIT, _on_hit)
	Net.register(MSG_CAR_SHOT, _on_shot)
	Net.register(MSG_CAR_FIRE, _on_fire)


func _exit_tree() -> void:
	for m in [MSG_CAR_INPUT, MSG_CAR_STATE, MSG_CAR_SNAP, MSG_CAR_DENT, MSG_CAR_MODE, MSG_CAR_HIT, MSG_CAR_SHOT, MSG_CAR_FIRE]:
		Net.unregister(m)


func add_car(car: Car) -> void:
	car.net_id = cars.size()
	cars.append(car)
	var idx := car.net_id
	car.dented.connect(func(p, d, a): _local_dent(idx, p, d, a))
	car.hit_piece.connect(func(pid, imp): _local_hit(pid, imp))


## Car index driven by a peer: slot order in the lobby, or with seats the
## car whose driver's seat that peer's officer is in (-1 for none).
func car_for(peer_id: int) -> int:
	if use_seats:
		for o in get_tree().get_nodes_in_group("officers"):
			if o.peer_id == peer_id and o.state == Officer.S.VEHICLE and o.seat == 0 and o.car != null:
				return cars.find(o.car)
		return -1
	return Net.player_ids().find(peer_id)


## Who drives car idx (the host when nobody does).
func driver_of(idx: int) -> int:
	if use_seats:
		for o in get_tree().get_nodes_in_group("officers"):
			if o.state == Officer.S.VEHICLE and o.seat == 0 and idx < cars.size() and o.car == cars[idx]:
				return o.peer_id if Net.player_ids().has(o.peer_id) or not Net.is_online() else 1
		return 1
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
	if Net.is_host():
		_burn_step(delta)
	for i in cars.size():
		var car: Car = cars[i]
		var local := simulates_locally(i)
		if car.freeze == local:
			car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			car.freeze = not local
	# Driver input.
	var mine := car_for(Net.my_id())
	if mine >= 0 and mine < cars.size():
		var car_m: Car = cars[mine]
		var on := not PlayerInput.blocked
		var inp := {
			"throttle": Input.get_axis("move_back", "move_forward") if on else 0.0,
			"steer": Input.get_axis("move_right", "move_left") if on else 0.0,
			"handbrake": Input.is_action_pressed("handbrake") and on,
			"horn": Input.is_action_pressed("horn") and on,
			"lights": car_m.get("lights") == true,
			"siren": int(car_m.get("siren")) if car_m.get("siren") != null else 0,
		}
		# The torch key works the roof lights and siren from the driver's seat.
		if on and car_m is PoliceCar and Input.is_action_just_pressed("torch"):
			var tmp := {"lights": inp.lights, "siren": inp.siren}
			car_m.cycle_lights()
			inp.lights = car_m.lights
			inp.siren = car_m.siren
			if not simulates_locally(mine):
				car_m.lights = tmp.lights   # the host's echo decides
				car_m.siren = tmp.siren
				_light_want[mine] = [inp.lights, inp.siren]
		if _light_want.has(mine):
			inp.lights = _light_want[mine][0]
			inp.siren = _light_want[mine][1]
			if car_m.get("lights") == inp.lights and car_m.get("siren") == inp.siren:
				_light_want.erase(mine)
		if simulates_locally(mine):
			_apply_input(car_m, inp)
		else:
			var b := StreamPeerBuffer.new()
			b.put_u8(mine)
			b.put_half(inp.throttle)
			b.put_half(inp.steer)
			b.put_u8((1 if inp.handbrake else 0) | (2 if inp.horn else 0) | (4 if inp.lights else 0) | (inp.siren << 3))
			Net.send(1, MSG_CAR_INPUT, b.data_array, Net.UNRELIABLE, 2)
	if use_seats and Net.is_host():
		# Nobody at the wheel: the car is parked with the handbrake on.
		for i in cars.size():
			if car_for_driver_missing(i) and ai_inputs.has(i):
				_inputs[i] = ai_inputs[i]
			elif car_for_driver_missing(i):
				_inputs[i] = {"throttle": 0.0, "steer": 0.0, "handbrake": true, "horn": false,
					"lights": cars[i].get("lights") == true, "siren": int(cars[i].get("siren")) if cars[i].get("siren") != null else 0}
	if Net.is_host():
		for i in _inputs:
			# Our own car took the live keys above. (Its parked input, the
			# handbrake on, used to be applied over them every frame: the
			# host's car would not move, v0.2.10.)
			if i == mine:
				continue
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


func car_for_driver_missing(i: int) -> bool:
	return driver_of(i) == 1 and car_for(Net.my_id()) != i


func _apply_input(car: Car, inp: Dictionary) -> void:
	if car.wrecked:
		car.throttle = 0.0
		car.brake = 1.0
		car.steer = 0.0
		return
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
	if car is PoliceCar and inp.has("lights"):
		(car as PoliceCar).lights = inp.lights
		(car as PoliceCar).siren = inp.siren


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
	_inputs[idx] = {"throttle": th, "steer": st, "handbrake": (flags & 1) != 0, "horn": (flags & 2) != 0,
		"lights": (flags & 4) != 0, "siren": (flags >> 3) & 3}


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
	_push(idx, t, _decode(idx, b))


func _on_snap(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var t := b.get_double()
	var n := b.get_u8()
	for i in n:
		var s := _decode(i, b)
		if i < cars.size() and not simulates_locally(i):
			_push(i, t, s)


func _decode(idx: int, b: StreamPeerBuffer) -> Dictionary:
	var s := Car.decode_state(b)
	if idx < cars.size() and cars[idx] is PoliceCar:
		s.merge((cars[idx] as PoliceCar).extra_state(b), true)
	return s


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
			s = {"pos": a.pos.lerp(c.pos, k), "rot": (a.rot as Quaternion).slerp(c.rot, k), "lv": a.lv.lerp(c.lv, k), "av": a.av.lerp(c.av, k), "steer": lerpf(a.steer, c.steer, k), "horn": c.horn,
				"lights": c.get("lights", false), "siren": c.get("siren", 0)}
		else:
			s = buf[0][1]
		car.global_transform = Transform3D(Basis(s.rot), s.pos)
		car.linear_velocity = s.lv
		car.angular_velocity = s.av
		car.steer = s.steer
		car.horn = s.get("horn", false)
		if car is PoliceCar:
			(car as PoliceCar).lights = s.get("lights", false)
			(car as PoliceCar).siren = s.get("siren", 0)


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
		damage_car(cars[idx], a * 150.0, cars[idx].global_transform * p)
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
	var a := b.get_float()
	cars[idx].apply_dent(p, d, a)
	if Net.is_host():
		damage_car(cars[idx], a * 150.0, cars[idx].global_transform * p)


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


## Host: a bullet hit a car. Glass breaks for everyone; metal takes a small
## dent (through the usual dent event). Returns the surface hit, for sound.
func bullet_hit(car: Car, point: Vector3, dir: Vector3) -> String:
	var idx := cars.find(car)
	if idx < 0 or not Net.is_host():
		return "metal"
	var lp := car.global_transform.affine_inverse() * point
	if car is PoliceCar:
		var w := (car as PoliceCar).window_at(lp)
		if w != "":
			var names := (car as PoliceCar).glass.keys()
			var b := StreamPeerBuffer.new()
			b.put_u8(idx)
			b.put_u8(names.find(w))
			Net.broadcast(MSG_CAR_SHOT, b.data_array)
			(car as PoliceCar).shatter(w)
			return "glass"
	var ld := (car.global_transform.basis.inverse() * dir).normalized()
	var b2 := StreamPeerBuffer.new()
	b2.put_u8(idx)
	for v in [lp, ld]:
		b2.put_float(v.x)
		b2.put_float(v.y)
		b2.put_float(v.z)
	b2.put_float(0.015)
	Net.broadcast(MSG_CAR_DENT, b2.data_array)
	car.apply_dent(lp, ld, 0.015)
	var tank := lp.z < -SIZE_Z_TANK and lp.y < 0.1
	damage_car(car, TANK_DAMAGE if tank else BODY_DAMAGE, point)
	return "metal"


func _on_shot(from: int, data: PackedByteArray) -> void:
	if from != 1 or Net.is_host():
		return
	var idx := data[0]
	if idx < cars.size() and cars[idx] is PoliceCar:
		var pc := cars[idx] as PoliceCar
		var names := pc.glass.keys()
		if data[1] < names.size():
			pc.shatter(names[data[1]])


## Host: dents a car for everyone (blasts).
func _local_dent_host(car: Car, lp: Vector3, ld: Vector3, amount: float) -> void:
	var idx := cars.find(car)
	if idx < 0 or not Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.put_u8(idx)
	for v in [lp, ld]:
		b.put_float(v.x)
		b.put_float(v.y)
		b.put_float(v.z)
	b.put_float(amount)
	Net.broadcast(MSG_CAR_DENT, b.data_array)
	car.apply_dent(lp, ld, amount)
	if car is PoliceCar:
		var pc := car as PoliceCar
		for n in pc.glass.keys():
			if not pc.glass[n].broken and (pc.glass[n].box as AABB).get_center().distance_to(lp) < 2.5 * amount / 0.3 + 0.5:
				var sb := StreamPeerBuffer.new()
				sb.put_u8(idx)
				sb.put_u8(pc.glass.keys().find(n))
				Net.broadcast(MSG_CAR_SHOT, sb.data_array)
				pc.shatter(n)


# --- Phase 1.5: damage, fire and wrecks ---------------------------------------------------

## Host: hurts a car (bullets, crashes, blasts, fire).
func damage_car(car: Car, amount: float, _at := Vector3.ZERO) -> void:
	var idx := cars.find(car)
	if idx < 0 or not Net.is_host() or amount <= 0.0:
		return
	var st: int = fire_state.get(idx, Fire.OK)
	if st >= Fire.BURNING:
		return
	var hp: float = car_hp.get(idx, CAR_HP) - amount
	car_hp[idx] = hp
	if hp <= 0.0:
		_burn_t[idx] = BURN_TIME
		_set_fire(idx, Fire.BURNING)
		if FireSystem.current:
			FireSystem.current.ignite(car.global_position, 1.4, BURN_TIME + 25.0, -1, idx)
	elif hp < SMOKE_AT and st == Fire.OK:
		_set_fire(idx, Fire.SMOKING)


func _burn_step(delta: float) -> void:
	for idx in _burn_t.keys():
		_burn_t[idx] -= delta
		if _burn_t[idx] > 0.0:
			continue
		_burn_t.erase(idx)
		var car: Car = cars[idx]
		_set_fire(idx, Fire.WRECKED)
		var at := car.global_position + Vector3(0, 0.4, 0)
		Blast.go(get_tree(), destruction, self, at, 4.5, 170.0, 12.0)
		if simulates_locally(idx):
			car.apply_central_impulse(Vector3.UP * car.mass * 5.0)
			car.apply_torque_impulse(car.global_transform.basis.z * car.mass * 0.9)


func _set_fire(idx: int, st: int) -> void:
	if Net.is_host() and Net.is_online():
		var b := PackedByteArray([idx, st])
		Net.broadcast(MSG_CAR_FIRE, b)
	_apply_fire(idx, st)


func _on_fire(from: int, data: PackedByteArray) -> void:
	if from != 1 or Net.is_host() or data.size() < 2:
		return
	if data[0] < cars.size():
		_apply_fire(data[0], data[1])


func _apply_fire(idx: int, st: int) -> void:
	var prev: int = fire_state.get(idx, Fire.OK)
	if st <= prev:
		return
	fire_state[idx] = st
	var car: Car = cars[idx]
	if st >= Fire.SMOKING and car.get_node_or_null("DamageSmoke") == null and DisplayServer.get_name() != "headless":
		var smoke := CPUParticles3D.new()
		smoke.name = "DamageSmoke"
		smoke.amount = 16
		smoke.lifetime = 2.5
		smoke.position = Vector3(0, 0.5, Car.SIZE.z * 0.38)
		smoke.direction = Vector3.UP
		smoke.spread = 15.0
		smoke.gravity = Vector3(0, 1.0, 0)
		smoke.initial_velocity_min = 0.5
		smoke.initial_velocity_max = 1.2
		smoke.scale_amount_min = 0.6
		smoke.scale_amount_max = 1.2
		var grad := Gradient.new()
		grad.set_color(0, Color(0.35, 0.35, 0.36, 0.5))
		grad.set_color(1, Color(0.5, 0.5, 0.5, 0.0))
		smoke.color_ramp = grad
		var q := QuadMesh.new()
		q.size = Vector2(0.8, 0.8)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = FireSystem.soft_texture()
		q.material = m
		smoke.mesh = q
		car.add_child(smoke)
		smoke.emitting = true
	if st >= Fire.BURNING:
		var sm := car.get_node_or_null("DamageSmoke") as CPUParticles3D
		if sm:
			sm.amount = 32
			var g2 := Gradient.new()
			g2.set_color(0, Color(0.08, 0.08, 0.08, 0.7))
			g2.set_color(1, Color(0.2, 0.2, 0.2, 0.0))
			sm.color_ramp = g2
	if st == Fire.WRECKED:
		car.wreck()


# --- Catch-up and saving (Phase 1.7) -------------------------------------------

## Every car as it is now: where it is, how hurt, burning or wrecked, every
## dent and every broken window. For a friend joining late, and the save.
func write_state(b: StreamPeerBuffer) -> void:
	b.put_u8(cars.size())
	for i in cars.size():
		var car: Car = cars[i]
		DestructionWorld._put_xform(b, car.global_transform)
		b.put_float(car_hp.get(i, CAR_HP))
		b.put_u8(fire_state.get(i, Fire.OK))
		b.put_u16(car.dent_log.size())
		for d in car.dent_log:
			DestructionWorld._put_v3(b, d[0])
			DestructionWorld._put_v3(b, d[1])
			b.put_float(d[2])
		var broken: Array = []
		if car is PoliceCar:
			var names: Array = (car as PoliceCar).glass.keys()
			for k in names.size():
				if (car as PoliceCar).glass[names[k]].broken:
					broken.append(k)
		b.put_u8(broken.size())
		for k in broken:
			b.put_u8(k)


## from_save: the host loading a saved block (cars that were on fire are
## burnt-out wrecks by now). Otherwise a client catching up.
func read_state(b: StreamPeerBuffer, from_save := false) -> void:
	var n := b.get_u8()
	for i in n:
		var xf := DestructionWorld._get_xform(b)
		var hp := b.get_float()
		var st := b.get_u8()
		var dents: Array = []
		for k in b.get_u16():
			dents.append([DestructionWorld._get_v3(b), DestructionWorld._get_v3(b), b.get_float()])
		var glass: Array = []
		for k in b.get_u8():
			glass.append(b.get_u8())
		if i >= cars.size():
			continue
		var car: Car = cars[i]
		if from_save:
			car.global_transform = xf
			car.linear_velocity = Vector3.ZERO
			car.angular_velocity = Vector3.ZERO
			car_hp[i] = hp
			if st >= Fire.BURNING:
				st = Fire.WRECKED
		if car.dent_log.is_empty():
			for d in dents:
				car.apply_dent(d[0], d[1], d[2])
		if car is PoliceCar:
			var pc := car as PoliceCar
			var names: Array = pc.glass.keys()
			for k in glass:
				if k < names.size() and not pc.glass[names[k]].broken:
					pc.glass[names[k]].broken = true
					(pc.glass[names[k]].node as Node3D).visible = false
		if st > fire_state.get(i, Fire.OK):
			_apply_fire(i, st)
