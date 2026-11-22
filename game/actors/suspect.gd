class_name Suspect
extends CharacterBody3D
## Phase 1.4: someone the police are after. The host runs every suspect's
## head and body; clients get their state from the Dispatcher's snapshots and
## only animate them.
##
## Suspects loiter or commit their crime until officers turn up, then run
## (along the block's navigation mesh) to somewhere out of sight, often
## indoors and upstairs, and hide there. Pressure makes them give up: an
## officer aiming at them, a punch or a kick, getting shot. A surrendered
## suspect kneels with their hands up; an officer holding interact next to
## them cuffs them, and they follow that officer until they are put in a
## police car and driven to the custody bay. Armed suspects shoot back now
## and then while they run (real combat behaviour is Phase 1.5).
## Same skeleton and clips as the officers, dressed as civilians.

enum S { LOITER, ROB, FLEE, HIDE, SHOOT, STAGGER, SURRENDER, CUFFED, IN_CAR, DOWN, BOOKED, DRIVE }

const WALK := 1.4
const RUN := 4.4              # officers sprint at 5.6, so they can catch one
const ACCEL := 20.0
const GRAVITY := 16.0
const MAX_HP := 60.0
const CAPSULE_H := 1.75
const NOTICE := 14.0          # m: sees an officer coming
const CLOSE := 5.0            # m: notices an officer even out of sight
const SURRENDER_AT := 1.6     # pressure that makes them give up
const SHOT_GAP := 0.9         # s between an armed suspect's shots
const SHOOT_RANGE := 16.0
const FOLLOW_GAP := 1.1       # m behind the officer escorting them

signal state_changed(s: Suspect)

var net_id := 0
var look := 0
var armed := false
var hp := MAX_HP
var state := S.LOITER
var state_t := 0.0
var call_id := -1
## Host: who is walking them in, and the dispatcher (for shots and paths).
var escort: Officer
## Every machine: the peer whose officer is escorting them (0 for none).
var escort_peer := 0
var dispatcher: Node
var nav: BlockNav
var hide_spots: Array = []
var home := Vector3.ZERO
var car: PoliceCar
var seat := -1
var pressure := 0.0
## Where an armed suspect is pointing their gun (for the pose), or zero.
var aim_at := Vector3.ZERO
var rig: OfficerRig
## Clients: speed from interpolation, for the walk and run clips.
var net_speed := 0.0

var _path := PackedVector3Array()
var _path_i := 0
var _goal := Vector3.INF
var _repath_t := 0.0
var _shoot_t := 0.0
var _wander_t := 0.0
var _alone_t := 0.0
var _check_t := 0.0
var _last_spot := Vector3.INF
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	add_to_group("suspects")


func _ready() -> void:
	_rng.seed = hash(net_id * 7919 + look)
	collision_layer = 2
	collision_mask = 1 | 4 | 16
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = CAPSULE_H
	cs.shape = cap
	cs.position.y = CAPSULE_H * 0.5
	add_child(cs)
	rig = OfficerRig.new()
	add_child(rig)
	SuspectLook.apply(rig.model, look)
	_show_gun()


func is_host_side() -> bool:
	return Net.is_host()


func is_free() -> bool:
	return state in [S.LOITER, S.ROB, S.FLEE, S.HIDE, S.SHOOT, S.STAGGER]


## Dealt with: no longer part of the call's trouble.
func is_done() -> bool:
	return state in [S.DOWN, S.BOOKED]


func set_state(s: S) -> void:
	if s == state:
		return
	state = s
	state_t = 0.0
	_path = PackedVector3Array()
	_goal = Vector3.INF
	if s in [S.SURRENDER, S.CUFFED, S.IN_CAR, S.DOWN, S.BOOKED]:
		armed = false   # the gun is dropped (picked up in a later phase)
		aim_at = Vector3.ZERO
	if s == S.DOWN:
		collision_layer = 0
		collision_mask = 1
		if rig:
			rig.set_downed(true, velocity)
	if s in [S.IN_CAR, S.DRIVE, S.BOOKED]:
		collision_layer = 0
		collision_mask = 0
	elif s != S.DOWN:
		collision_layer = 2
		collision_mask = 1 | 4 | 16
	visible = s not in [S.DRIVE, S.BOOKED]
	_show_gun()
	state_changed.emit(self)


func _show_gun() -> void:
	if rig == null or rig.model == null:
		return
	for n in ["gun_grip", "gun_slide"]:
		var g := rig.model.find_child(n, true, false) as Node3D
		if g:
			g.visible = armed


# --- host: hits ----------------------------------------------------------------

func take_damage(amount: float, dir := Vector3.ZERO, _where := "") -> void:
	if state in [S.DOWN, S.BOOKED, S.DRIVE]:
		return
	hp -= amount
	if rig and dir != Vector3.ZERO:
		rig.hit_reaction(dir, 5.0)
	if hp <= 0.0:
		velocity = dir * 3.0
		set_state(S.DOWN)
		return
	pressure += 1.0 if hp > MAX_HP * 0.5 else 2.0


## A punch, kick or barge: knocked off balance, and much keener to give up.
func struck(dir: Vector3, damage: float, shove: float) -> void:
	if not is_free() and state != S.SURRENDER:
		return
	take_damage(damage, dir)
	if state == S.DOWN:
		return
	velocity = dir * shove
	pressure += 1.2
	if is_free():
		set_state(S.STAGGER)


func cuff(by: Officer) -> void:
	escort = by
	escort_peer = by.peer_id
	set_state(S.CUFFED)


func put_in_car(c: PoliceCar, s: int) -> void:
	car = c
	seat = s
	escort = null
	escort_peer = 0
	set_state(S.IN_CAR)
	_place_in_seat()


func _place_in_seat() -> void:
	if car == null or not is_instance_valid(car):
		return
	global_position = car.global_transform * (PoliceCar.SEATS[seat] as Vector3)
	var f := car.global_transform.basis.z
	rotation.y = atan2(f.x, f.z)
	velocity = car.linear_velocity


# --- host: brain -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_host_side():
		return
	state_t += delta
	_shoot_t -= delta
	pressure = maxf(0.0, pressure - 0.2 * delta)
	if state == S.IN_CAR:
		if car == null or not is_instance_valid(car):
			set_state(S.CUFFED)
		else:
			_place_in_seat()
		return
	if state in [S.DOWN, S.BOOKED, S.DRIVE]:
		return
	var t := _threat()
	if is_free():
		_feel_pressure(delta)
	var wish := Vector3.ZERO
	var speed := 0.0
	aim_at = Vector3.ZERO
	match state:
		S.LOITER:
			if _notices(t):
				_bolt(t)
			elif armed:
				_wander_t -= delta
				if _wander_t <= 0.0 or _goal == Vector3.INF:
					_wander_t = _rng.randf_range(4.0, 8.0)
					_goal = _near(home, 6.0)
				wish = _steer(_goal, delta)
				speed = WALK
		S.ROB:
			# Turning the place over until officers show up or they have it.
			if _notices(t) or state_t > 70.0:
				_bolt(t)
		S.SHOOT:
			if t.o:
				_face(t.o.global_position)
				aim_at = (t.o as Officer).global_position + Vector3(0, 1.2, 0)
				if _shoot_t <= 0.0 and t.los and t.d < SHOOT_RANGE:
					_fire(t.o)
			if state_t > 2.5 or t.o == null:
				_run_to_hide(t)
		S.FLEE:
			if _goal == Vector3.INF:
				_run_to_hide(t)
			wish = _steer(_goal, delta)
			speed = RUN
			if armed and t.o and t.los and t.d < SHOOT_RANGE * 0.8 and _shoot_t <= 0.0 and _rng.randf() < 0.6:
				aim_at = (t.o as Officer).global_position + Vector3(0, 1.2, 0)
				_fire(t.o)
			if wish == Vector3.ZERO and _arrived():
				set_state(S.HIDE)
		S.HIDE:
			_check_t -= delta
			if t.o and t.los and _check_t <= 0.0:
				_check_t = 1.5
				if t.d < 4.0:
					if _rng.randf() < 0.7:
						set_state(S.SURRENDER)
					else:
						_bolt(t)
				elif t.d < 10.0 and _rng.randf() < 0.25:
					_bolt(t)
		S.STAGGER:
			if state_t > 1.0:
				if pressure >= 1.0 or not armed:
					set_state(S.SURRENDER)
				else:
					_bolt(t)
		S.SURRENDER:
			# Nobody watching for a while: some get up and run again.
			_alone_t = _alone_t + delta if (t.o == null or t.d > 18.0) else 0.0
			if _alone_t > 12.0:
				_alone_t = 0.0
				if _rng.randf() < 0.4:
					pressure = 0.0
					_bolt(t)
		S.CUFFED:
			if escort and is_instance_valid(escort) and escort.state not in [Officer.S.DOWNED, Officer.S.VEHICLE]:
				var e := escort.global_position
				var back := Vector3(sin(escort.rotation.y), 0, cos(escort.rotation.y))
				var spot := e - back * FOLLOW_GAP
				var to := spot - global_position
				to.y = 0.0
				if to.length() > 0.3:
					wish = to.normalized()
					speed = clampf(to.length() * 2.5, 0.0, RUN)
				_face(e)
	# Move.
	var target := wish * speed
	velocity.x = move_toward(velocity.x, target.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * delta)
	if state == S.STAGGER:
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	if wish.length() > 0.1 and state != S.CUFFED and aim_at == Vector3.ZERO:
		rotation.y = lerp_angle(rotation.y, atan2(wish.x, wish.z), 12.0 * delta)
	elif aim_at != Vector3.ZERO:
		_face(aim_at)
	move_and_slide()
	_step_up()


## The nearest officer on their feet: {o, d, los}.
func _threat() -> Dictionary:
	var best: Officer = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("officers"):
		var o := n as Officer
		if o == null or o.state == Officer.S.DOWNED:
			continue
		var d := o.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = o
	var los := false
	if best:
		var a := global_position + Vector3(0, 1.5, 0)
		var b := best.global_position + Vector3(0, 1.4, 0)
		var q := PhysicsRayQueryParameters3D.create(a, b, 1, [get_rid()])
		los = get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	return {"o": best, "d": bd, "los": los}


func _notices(t: Dictionary) -> bool:
	return t.o != null and ((t.los and t.d < NOTICE) or t.d < CLOSE)


## An officer aiming at them, close and in sight, wears them down.
func _feel_pressure(delta: float) -> void:
	var chest := global_position + Vector3(0, 1.2, 0)
	for n in get_tree().get_nodes_in_group("officers"):
		var o := n as Officer
		if o == null or not o.is_aiming() or o.aim_point == Vector3.ZERO:
			continue
		var from := o.global_position + Vector3(0, 1.4, 0)
		var d := from.distance_to(chest)
		if d > 14.0:
			continue
		var aim_dir := (o.aim_point - from).normalized()
		if aim_dir.angle_to((chest - from).normalized()) > 0.22:
			continue
		var q := PhysicsRayQueryParameters3D.create(from, chest, 1, [get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		pressure += delta * (0.5 if armed else 1.0) * (1.5 if d < 6.0 else 1.0)
	if pressure >= SURRENDER_AT:
		if not armed or _rng.randf() < 0.6:
			set_state(S.SURRENDER)
		else:
			pressure = 0.6
			set_state(S.SHOOT)


## Off they go: armed ones sometimes stand and shoot first.
func _bolt(t: Dictionary) -> void:
	if armed and t.o != null and t.los and _rng.randf() < 0.5:
		set_state(S.SHOOT)
	else:
		_run_to_hide(t)


func _run_to_hide(t: Dictionary) -> void:
	set_state(S.FLEE)
	_goal = _pick_hide(t)
	_last_spot = _goal


## Somewhere far from the officers that can be reached: rooms upstairs and
## round the back first.
func _pick_hide(t: Dictionary) -> Vector3:
	var threat_p: Vector3 = (t.o as Officer).global_position if t.o else global_position
	var best := Vector3.INF
	var best_score := -INF
	var spots := hide_spots.duplicate()
	for i in spots.size():
		var j := _rng.randi_range(i, spots.size() - 1)
		var tmp = spots[i]
		spots[i] = spots[j]
		spots[j] = tmp
	var tried := 0
	for sp in spots:
		var p: Vector3 = sp
		if _last_spot != Vector3.INF and p.distance_to(_last_spot) < 3.0:
			continue
		var score := p.distance_to(threat_p) - p.distance_to(global_position) * 0.35 + _rng.randf() * 6.0
		if score <= best_score:
			continue
		if nav and nav.ready_to_use and not nav.reaches(global_position, p):
			continue
		best = p
		best_score = score
		tried += 1
		if tried >= 6:
			break
	if best == Vector3.INF:
		# Nowhere known: straight away from the officer.
		var away := global_position - threat_p
		away.y = 0.0
		best = global_position + (away.normalized() if away.length() > 0.1 else Vector3.FORWARD) * 15.0
	return best


func _near(p: Vector3, r: float) -> Vector3:
	var q := p + Vector3(_rng.randf_range(-r, r), 0, _rng.randf_range(-r, r))
	return nav.closest(q) if nav and nav.ready_to_use else q


## Direction along the path to goal (zero once there).
func _steer(goal: Vector3, delta: float) -> Vector3:
	if goal == Vector3.INF:
		return Vector3.ZERO
	_repath_t -= delta
	if nav and nav.ready_to_use and (_path.is_empty() or _repath_t <= 0.0 or _path[_path.size() - 1].distance_to(goal) > 1.0):
		_repath_t = 2.0
		_path = nav.path(global_position, goal)
		_path_i = 0
	var next := goal
	if not _path.is_empty():
		while _path_i < _path.size() - 1 and Vector2(_path[_path_i].x - global_position.x, _path[_path_i].z - global_position.z).length() < 0.45:
			_path_i += 1
		next = _path[_path_i]
	var to := next - global_position
	to.y = 0.0
	var left := goal - global_position
	left.y = 0.0
	if left.length() < 0.5:
		return Vector3.ZERO
	return to.normalized() if to.length() > 0.05 else left.normalized()


func _arrived() -> bool:
	if _goal == Vector3.INF:
		return true
	var d := _goal - global_position
	return Vector2(d.x, d.z).length() < 0.6


func _face(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), 0.25)


func _fire(o: Officer) -> void:
	_shoot_t = SHOT_GAP * _rng.randf_range(0.8, 1.5)
	if dispatcher and dispatcher.has_method("suspect_shot"):
		var muzzle := global_position + Vector3(0, 1.4, 0) + Vector3(sin(rotation.y), 0, cos(rotation.y)) * 0.5
		var target := o.global_position + Vector3(0, 1.1, 0)
		var spread := target.distance_to(muzzle) * 0.09
		target += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 0.6), _rng.randf_range(-1, 1)) * spread
		dispatcher.suspect_shot(self, muzzle, (target - muzzle).normalized())


## Kerbs and stair treads: hop up small steps the capsule catches on.
func _step_up() -> void:
	if not is_on_wall() or Vector2(velocity.x, velocity.z).length() < 0.3:
		return
	var fwd := Vector3(velocity.x, 0, velocity.z).normalized()
	var space := get_world_3d().direct_space_state
	var from := global_position + fwd * 0.4 + Vector3(0, 0.45, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 0.5, 0), 1 | 16, [get_rid()])
	var hit := space.intersect_ray(q)
	if hit and hit.position.y > global_position.y + 0.02 and hit.position.y < global_position.y + 0.42:
		global_position.y = hit.position.y + 0.02
		global_position += fwd * 0.05


# --- every machine: looks -------------------------------------------------------------

func _process(delta: float) -> void:
	if rig == null or state == S.DOWN:
		return
	var hs := Vector2(velocity.x, velocity.z).length() if is_host_side() else net_speed
	var lower := "idle"
	var upper := "none"
	match state:
		S.HIDE, S.STAGGER:
			lower = "crouch_walk" if hs > 0.3 else "crouch_idle"
		S.SURRENDER:
			lower = "kneel"
			upper = "hands_up"
		S.CUFFED:
			lower = "idle" if hs < 0.2 else ("walk" if hs < 2.2 else "run")
			upper = "cuffed"
		S.IN_CAR:
			lower = "sit"
			upper = "cuffed"
		_:
			lower = "idle" if hs < 0.2 else ("walk" if hs < 2.2 else "run")
			if aim_at != Vector3.ZERO:
				upper = "aim_hold"
			elif armed and state == S.LOITER:
				upper = "ready_hold"
	rig.update_pose(lower, upper, hs, delta, aim_at)


# --- network (the Dispatcher sends these) -----------------------------------------------

func encode(b: StreamPeerBuffer) -> void:
	b.put_u16(net_id)
	b.put_u8(look)
	b.put_u8(state | (128 if armed else 0))
	b.put_float(global_position.x)
	b.put_float(global_position.y)
	b.put_float(global_position.z)
	b.put_half(rotation.y)
	b.put_half(Vector2(velocity.x, velocity.z).length())
	b.put_half(aim_at.x)
	b.put_half(aim_at.y)
	b.put_half(aim_at.z)
	b.put_8(car.net_id if car and state == S.IN_CAR else -1)
	b.put_8(seat)
	b.put_u8(int(clampf(hp, 0.0, 255.0)))
	b.put_u32(escort_peer if state == S.CUFFED else 0)


static func decode(b: StreamPeerBuffer) -> Dictionary:
	var d := {}
	d.id = b.get_u16()
	d.look = b.get_u8()
	var st := b.get_u8()
	d.state = st & 127
	d.armed = (st & 128) != 0
	d.pos = Vector3(b.get_float(), b.get_float(), b.get_float())
	d.yaw = b.get_half()
	d.speed = b.get_half()
	d.aim = Vector3(b.get_half(), b.get_half(), b.get_half())
	d.car = b.get_8()
	d.seat = b.get_8()
	d.hp = b.get_u8()
	d.escort = b.get_u32()
	return d


## Clients: take the host's word for everything but the smoothed position.
func apply_net(d: Dictionary) -> void:
	armed = d.armed
	aim_at = d.aim
	hp = d.hp
	seat = d.seat
	escort_peer = d.escort
	if d.state != state:
		set_state(d.state)
	_show_gun()
