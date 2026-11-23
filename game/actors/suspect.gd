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
## and then while they run.
##
## Phase 1.5: fighters (gang members, armed suspects) stand and fight. They
## find cover between them and the officers (low walls they can pop up over,
## corners they can lean out of), peek and shoot in short bursts, blind fire
## over the top when pinned down by fire, reload behind cover, move to new
## cover when flanked, retreat when hurt or outnumbered, and push forward
## when they lose sight of the police. In a group one pins the officers down
## while another works round the side, and they call for backup. Without a
## gun (or out of ammo) they grab loose things and throw them. Guns are
## dropped on surrender or when they go down; officers can pick them up.
## Same skeleton and clips as the officers, dressed as civilians.

enum S { LOITER, ROB, FLEE, HIDE, SHOOT, STAGGER, SURRENDER, CUFFED, IN_CAR, DOWN, BOOKED, DRIVE, COVER, SEEK_COVER, THROW, WANDER, PANIC, COWER, BRAWL }
## What a fighter is doing in cover (synced, for the pose).
enum C { HIDE, PEEK, BLIND, RELOAD }

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
const COVER_IDEAL := 9.0      # m from the officers a fighter likes to fight at
const SUPPRESS_TIME := 1.6    # s pinned down after a bullet passes close
const THROW_REACH := 3.0      # m: loose things this close can be grabbed
const THROW_SPEED := 11.0
const ROLE_PIN := 0
const ROLE_FLANK := 1

signal state_changed(s: Suspect)

var net_id := 0
var look := 0
## What they carry (EnemyGuns.NONE, PISTOL or SHOTGUN). armed is the old flag.
var weapon := EnemyGuns.NONE
var armed: bool:
	get:
		return weapon != EnemyGuns.NONE
	set(v):
		if v != (weapon != EnemyGuns.NONE):
			weapon = EnemyGuns.PISTOL if v else EnemyGuns.NONE
			mag = EnemyGuns.MAG[weapon]
var mag := 0                   # rounds in the gun
## Fights from cover instead of running for it (Phase 1.5).
var fighter := false
var role := ROLE_PIN
## Fighters: where they are taking cover, and what they are doing there.
var cover_spot := Vector3.INF
var cphase := C.HIDE
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
var _stuck_t := 0.0             # running but going nowhere
var _stuck_p := Vector3.ZERO
var _stuck_n := 0
var _rng := RandomNumberGenerator.new()
var _ct := 0.0                  # time left in this cover phase
var _burst := 0
var _peek_off := Vector3.ZERO   # sideways step to lean out (zero: stand up)
var _cycles := 0
var _eval_t := 0.0
var _suppressed_t := 0.0
var _last_seen := Vector3.INF   # where an officer was last seen
var _unseen_t := 0.0
var _flanked := false
var _called_backup := false
var _seek_t := 0.0
var _held: RigidBody3D
var _throw_t := 0.0
var _grab: RigidBody3D
var _retreated := false
## Clients: holding something over their head (for the pose).
var holding := false

## Wave 2, Phase 2.3: people out on the street (civilian). They walk a loop
## of pavement (route), and when shots, blasts or falling buildings go off
## near them they run from it (PANIC), then crouch with their hands over
## their heads (COWER) until it has been quiet a while. An officer aiming at
## one makes them put their hands up like anyone else.
var civilian := false
var route: Array = []
var _route_i := 0
var _panic_from := Vector3.INF
var _calm_t := 0.0
var _pace := 1.0

## Wave 3, Phase 3.1: parts people play in a job.
##  part: "" (a suspect or a passer-by), "victim" (stays put, shaken, and
##        tells the first officer to reach them what happened), "witness"
##        (stands by and points the way).
##  brawl_with: someone to fight (BRAWL: squared up, swinging); a Vector3
##        target instead means smashing whatever is there (vandal).
##  drunk: doesn't run from the police, sways about, has to be talked down
##        (aimed at) or wrestled.
var part := ""
var brawl_with: Variant = null
var drunk := false
var _swing_t := 0.0


func _init() -> void:
	add_to_group("suspects")
	add_to_group("alarm_listeners")


func _ready() -> void:
	_rng.seed = hash(net_id * 7919 + look)
	add_to_group(RoofFader.CUTAWAY_GROUP)
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
	return state in [S.LOITER, S.ROB, S.FLEE, S.HIDE, S.SHOOT, S.STAGGER, S.COVER, S.SEEK_COVER, S.THROW, S.WANDER, S.PANIC, S.COWER, S.BRAWL]


## Host: something loud and dangerous at `at` (a shot, a blast, a building
## coming down). Civilians in reach run from it or cower.
func on_alarm(at: Vector3, radius: float) -> void:
	if not civilian or state not in [S.WANDER, S.PANIC, S.COWER]:
		return
	var d := global_position.distance_to(at)
	if d > radius:
		return
	_calm_t = _rng.randf_range(7.0, 12.0)
	_panic_from = at
	if state == S.COWER and d > 6.0:
		return   # already down, stay down
	if d < 7.0 and _rng.randf() < 0.45:
		set_state(S.COWER)
		return
	set_state(S.PANIC)
	var away := global_position - at
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
	_goal = _near(global_position + away.normalized() * _rng.randf_range(18.0, 30.0), 3.0)


## Host: an officer shouted "Police! Get down!" from `at`.
func on_shout(at: Vector3, reach: float) -> void:
	var d := global_position.distance_to(at)
	if d > reach or not is_free():
		return
	suspicion = MADE   # "Police!" gives the game away
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.5, 0), at + Vector3(0, 1.4, 0), 1, [get_rid()])
	var heard_clearly := get_world_3d().direct_space_state.intersect_ray(q).is_empty() or d < 6.0
	if not heard_clearly:
		return
	if part != "":
		return   # victims and witnesses already know who we are
	if civilian:
		if state in [S.WANDER, S.PANIC] and d < 10.0:
			_calm_t = _rng.randf_range(5.0, 8.0)
			set_state(S.COWER)
		return
	if state == S.BRAWL:
		brawl_with = null   # the fight's over
	if drunk:
		pressure += 1.2 if d < 5.0 else 0.3
	elif not armed and not fighter:
		pressure += 1.8 if d < 10.0 else 0.8
	elif not fighter:
		pressure += 0.6
	else:
		pressure += 0.15
	if pressure >= SURRENDER_AT and (not armed or not fighter):
		set_state(S.SURRENDER)
	elif state == S.BRAWL:
		set_state(S.LOITER)


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
		# The gun goes on the floor, for an officer to pick up.
		if weapon != EnemyGuns.NONE and s != S.BOOKED and is_host_side() and dispatcher and dispatcher.has_method("drop_gun") and is_inside_tree():
			dispatcher.drop_gun(_toss_spot(), weapon, mag)
		weapon = EnemyGuns.NONE
		aim_at = Vector3.ZERO
		_drop_held(Vector3.ZERO)
	if s not in [S.COVER, S.SEEK_COVER]:
		cover_spot = Vector3.INF
	cphase = C.HIDE
	if s == S.DOWN:
		collision_layer = 0
		collision_mask = 1
		if rig:
			rig.set_downed(true, velocity * 0.6, velocity)
	if s in [S.IN_CAR, S.DRIVE, S.BOOKED]:
		collision_layer = 0
		collision_mask = 0
	elif s != S.DOWN:
		collision_layer = 2
		collision_mask = 1 | 4 | 16
	visible = s not in [S.DRIVE, S.BOOKED]
	_show_gun()
	state_changed.emit(self)


## Where a gun lands when they give up: tossed away a couple of metres in
## front, so the officer can cuff them without picking it up by mistake (and
## short of any wall).
func _toss_spot() -> Vector3:
	var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var from := global_position + Vector3(0, 0.6, 0)
	var to := from + fwd * 1.9
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1 | 4, [get_rid()]))
	if hit:
		to = (hit.position as Vector3) - fwd * 0.3
	return Vector3(to.x, global_position.y, to.z)


func _show_gun() -> void:
	if rig == null or rig.model == null:
		return
	EnemyGuns.show_in_hand(rig.model, weapon)


# --- host: hits ----------------------------------------------------------------

func take_damage(amount: float, dir := Vector3.ZERO, _where := "") -> void:
	if state in [S.DOWN, S.BOOKED, S.DRIVE]:
		return
	hp -= amount
	if rig and dir != Vector3.ZERO:
		rig.hit_reaction(dir, 5.0)
	if hp <= 0.0:
		# Blasts throw them; a runner carries on the way they were going.
		velocity = Vector3(velocity.x, 0.0, velocity.z) + dir * clampf(1.0 + amount * 0.05, 2.0, 22.0) * (1.0 if dir != Vector3.ZERO else 0.0)
		set_state(S.DOWN)
		return
	pressure += (0.4 if fighter else 1.0) if hp > MAX_HP * 0.5 else (1.0 if fighter else 2.0)
	_suppressed_t = SUPPRESS_TIME


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
	global_position = car.global_transform * (car.seats[seat] as Vector3)
	var f := car.global_transform.basis.z
	rotation.y = atan2(f.x, f.z)
	velocity = car.linear_velocity


# --- host: brain -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_host_side():
		return
	state_t += delta
	_shoot_t -= delta
	_suppressed_t -= delta
	pressure = maxf(0.0, pressure - 0.2 * delta)
	if state == S.IN_CAR:
		if car == null or not is_instance_valid(car):
			set_state(S.CUFFED)
		else:
			_place_in_seat()
		return
	if state in [S.DOWN, S.BOOKED, S.DRIVE]:
		return
	if not civilian and part == "":
		_suspicion_step(delta)
	var t := _threat()
	if t.o and t.los:
		_last_seen = (t.o as Officer).global_position
		_unseen_t = 0.0
	else:
		_unseen_t += delta
	if is_free():
		_feel_pressure(delta)
		if not is_free():
			return
	var wish := Vector3.ZERO
	var speed := 0.0
	aim_at = Vector3.ZERO
	match state:
		S.LOITER:
			if drunk:
				# Sways about near where they are; the police don't scare them.
				_wander_t -= delta
				if _wander_t <= 0.0 or _goal == Vector3.INF:
					_wander_t = _rng.randf_range(3.0, 6.0)
					_goal = _near(home, 3.0)
				wish = _steer(_goal, delta)
				wish = (wish + Vector3(sin(state_t * 1.7) * 0.6, 0, cos(state_t * 1.3) * 0.6)).normalized() if wish != Vector3.ZERO else wish
				speed = WALK * 0.6
				if t.o and t.d < 2.0 and _rng.randf() < delta * 0.5:
					set_state(S.STAGGER)   # takes a wild swing and falls about
			elif _notices(t):
				_react(t)
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
				_react(t)
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
			elif _flee_stuck(delta):
				# Wedged on a step or a corner: try somewhere else, and after
				# a couple of goes just hide where they are.
				_stuck_n += 1
				if _stuck_n >= 2:
					set_state(S.HIDE)
				else:
					_run_to_hide(t)
		S.HIDE:
			_check_t -= delta
			if fighter and t.o and t.los and t.d < 16.0 and (armed or _throwable_near() != null):
				_engage(t)
			elif t.o and t.los and _check_t <= 0.0:
				_check_t = 1.5
				if t.d < 4.0:
					if _rng.randf() < 0.7:
						set_state(S.SURRENDER)
					else:
						_bolt(t)
				elif t.d < 10.0 and _rng.randf() < 0.25:
					_bolt(t)
		S.STAGGER:
			if state_t > 1.0 and civilian:
				set_state(S.COWER)
				_calm_t = 8.0
			elif state_t > 1.0:
				if pressure >= (2.0 if fighter else 1.0) or (not armed and not fighter):
					set_state(S.SURRENDER)
				else:
					_react(t)
		S.SEEK_COVER:
			var r := _seek_cover_step(t, delta)
			wish = r[0]
			speed = r[1]
		S.COVER:
			var r := _cover_step(t, delta)
			wish = r[0]
			speed = r[1]
		S.THROW:
			var r := _throw_step(t, delta)
			wish = r[0]
			speed = r[1]
		S.BRAWL:
			var gunfight := armed and (brawl_with is Suspect or has_meta("crew"))
			if gunfight and not _brawl_alive():
				brawl_with = _next_rival()
			if gunfight and brawl_with == null:
				set_state(S.LOITER)   # the other lot are done: now it's the police
			elif gunfight:
				# Phase 3.4, gang war: shooting it out with the other crew, too
				# busy to notice the police until they're close or shooting.
				if t.o and t.los and (t.d < 12.0 or pressure > 0.5):
					brawl_with = null
					_react(t)
				else:
					var foe := brawl_with as Suspect
					var fp := foe.global_position
					_face(fp)
					aim_at = fp + Vector3(0, 1.1, 0)
					var gap := Vector2(fp.x - global_position.x, fp.z - global_position.z).length()
					if gap > 18.0:
						wish = _steer(fp, delta)
						speed = WALK * 1.5
					elif gap < 6.0:
						wish = _steer(global_position + (global_position - fp).normalized() * 3.0, delta)
						speed = WALK
					_swing_t -= delta
					if _swing_t <= 0.0:
						if mag <= 0:
							mag = EnemyGuns.MAG[weapon]
							_swing_t = EnemyGuns.RELOAD[weapon]
						else:
							_swing_t = _rng.randf_range(0.5, 1.4)
							_fire_at(aim_at, 0.07)
			elif _notices(t) and _rng.randf() < delta * 1.5:
				brawl_with = null
				_react(t)
			else:
				var at := _brawl_point()
				if at == Vector3.INF:
					set_state(S.LOITER)
				else:
					_face(at)
					var gap := Vector2(at.x - global_position.x, at.z - global_position.z).length()
					if gap > 1.1:
						wish = _steer(at, delta)
						speed = WALK * 1.5
					_swing_t -= delta
					if _swing_t <= 0.0 and gap < 1.6:
						_swing_t = _rng.randf_range(0.9, 1.6)
						_land_swing()
		S.WANDER:
			if route.is_empty():
				pass
			else:
				var g: Vector3 = route[_route_i % route.size()]
				if Vector2(g.x - global_position.x, g.z - global_position.z).length() < 1.2:
					_route_i = (_route_i + 1) % route.size()
					g = route[_route_i]
				wish = _steer(g, delta)
				speed = WALK * _pace
		S.PANIC:
			wish = _steer(_goal, delta)
			speed = RUN * 0.95
			if (wish == Vector3.ZERO and _arrived()) or _flee_stuck(delta) or state_t > 9.0:
				set_state(S.COWER)
		S.COWER:
			_calm_t -= delta
			if _calm_t <= 0.0:
				_back_to_route()
		S.SURRENDER:
			# Nobody watching for a while: some get up and run again.
			_alone_t = _alone_t + delta if (t.o == null or t.d > 18.0) else 0.0
			if civilian and part == "hostage":
				_alone_t = 0.0      # held: they stay down until it's over
			elif civilian and _alone_t > 6.0:
				_alone_t = 0.0
				pressure = 0.0
				_back_to_route()
			elif _alone_t > 12.0:
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
	_carry_held()
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
	_step_up(target)


## Where the fight is: the other brawler, or the thing being smashed.
func _brawl_alive() -> bool:
	return brawl_with is Suspect and is_instance_valid(brawl_with) and (brawl_with as Suspect).is_free() \
		and (brawl_with as Suspect).state != S.SURRENDER


## Gang war: someone else from the other crew still standing.
func _next_rival() -> Suspect:
	if dispatcher == null or not has_meta("crew"):
		return null
	var best: Suspect = null
	var bd := INF
	for s in dispatcher.suspects.values():
		var o := s as Suspect
		if o == self or o.call_id != call_id or not o.has_meta("crew") or o.get_meta("crew") == get_meta("crew"):
			continue
		if not o.is_free():
			continue
		var d := o.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = o
	return best


func _brawl_point() -> Vector3:
	if brawl_with is Vector3:
		return brawl_with
	if brawl_with is Suspect and is_instance_valid(brawl_with) and (brawl_with as Suspect).is_free():
		return (brawl_with as Suspect).global_position
	return Vector3.INF


## A punch at whoever they're fighting, or a kick at the window.
func _land_swing() -> void:
	if brawl_with is Suspect:
		var o := brawl_with as Suspect
		o.take_damage(4.0, (o.global_position - global_position).normalized())
		if o.state == Suspect.S.DOWN:
			brawl_with = null
	elif brawl_with is Vector3 and dispatcher and dispatcher.world:
		var w: DestructionWorld = dispatcher.world
		var at: Vector3 = brawl_with
		var best := -1
		var bd := 2.6
		for id in w.pieces_near(at, 2.6):
			var p: Dictionary = w.pieces[id]
			if p.state != "intact":
				continue
			var d := (p.aabb as AABB).get_center().distance_to(at)
			if d < bd and (String(p.kind).begins_with("glass") or p.kind in ["bollard", "lamp_post"]):
				bd = d
				best = id
		if best >= 0:
			w.damage_piece(best, 60.0, at, 1.0)
		else:
			brawl_with = null    # nothing left to smash: on their way


## A civilian picks up their walk again from the nearest point of it.
func _back_to_route() -> void:
	set_state(S.WANDER)
	var best := INF
	for i in route.size():
		var d := (route[i] as Vector3).distance_to(global_position)
		if d < best:
			best = d
			_route_i = i


## The nearest officer on their feet: {o, d, los}.
## Phase 3.7: how sure they are that the plain-clothes officer hanging about
## is the police (1: they've made them, and they're treated like uniforms).
var suspicion := 0.0
const MADE := 1.0


func _suspicion_step(delta: float) -> void:
	var near := false
	for n in get_tree().get_nodes_in_group("officers"):
		var o := n as Officer
		if o == null or not o.plain:
			continue
		var d := o.global_position.distance_to(global_position)
		if d > 14.0:
			continue
		if not o.undercover() and d < 20.0:
			suspicion = MADE   # a gun out, or a marked car: that's the police
			return
		near = true
		# Lingering close is what gives you away; across the street is fine.
		suspicion += delta * (0.22 if d < 3.0 else (0.08 if d < 7.0 else 0.025))
	if not near:
		suspicion = maxf(0.0, suspicion - 0.04 * delta)
	suspicion = minf(suspicion, MADE)


func _threat() -> Dictionary:
	var best: Officer = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("officers"):
		var o := n as Officer
		if o == null or o.state == Officer.S.DOWNED:
			continue
		if o.undercover() and suspicion < MADE and not civilian:
			continue   # just someone on the street
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
		pressure += delta * (0.25 if fighter else (0.5 if armed else 1.0)) * (1.5 if d < 6.0 else 1.0)
	if pressure >= SURRENDER_AT:
		if fighter and hp > MAX_HP * 0.35 and _rng.randf() < 0.75:
			# Not giving up yet: get out of the line of fire.
			pressure = 0.8
			_retreat(_threat())
		elif not armed or _rng.randf() < 0.6:
			set_state(S.SURRENDER)
		else:
			pressure = 0.6
			set_state(S.SHOOT)


## Seen the police: fighters fight, the rest run.
func _react(t: Dictionary) -> void:
	if fighter:
		_engage(t)
	else:
		_bolt(t)


## Off they go: armed ones sometimes stand and shoot first.
func _bolt(t: Dictionary) -> void:
	if armed and t.o != null and t.los and _rng.randf() < 0.5:
		set_state(S.SHOOT)
	else:
		_run_to_hide(t)


func _run_to_hide(t: Dictionary) -> void:
	if state != S.FLEE:
		_stuck_n = 0
	set_state(S.FLEE)
	_stuck_t = 0.0
	_stuck_p = global_position
	_goal = _pick_hide(t)
	_last_spot = _goal


## True once a run has made under half a metre in two seconds.
func _flee_stuck(delta: float) -> bool:
	if global_position.distance_to(_stuck_p) > 0.5:
		_stuck_p = global_position
		_stuck_t = 0.0
		return false
	_stuck_t += delta
	return _stuck_t > 2.0


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
	if mag <= 0 and not fighter and armed:
		mag = EnemyGuns.MAG[weapon]   # runners reload on the move
	_fire_at(o.global_position + Vector3(0, 1.1, 0), 0.09)


## One trigger pull at target; spread_k is metres of scatter per metre.
func _fire_at(target: Vector3, spread_k: float) -> void:
	if weapon == EnemyGuns.NONE or mag <= 0:
		return
	mag -= 1
	if fighter:
		_shoot_t = EnemyGuns.GAP[weapon] * _rng.randf_range(0.9, 1.3)
	else:
		_shoot_t = maxf(SHOT_GAP, EnemyGuns.GAP[weapon]) * _rng.randf_range(0.8, 1.5)
	if dispatcher == null or not dispatcher.has_method("suspect_shot"):
		return
	var muzzle := muzzle_position()
	var spread := target.distance_to(muzzle) * spread_k
	target += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 0.6), _rng.randf_range(-1, 1)) * spread
	var dir := (target - muzzle).normalized()
	var dmg: float = EnemyGuns.DAMAGE[weapon] * 0.7
	var first := true
	for d in EnemyGuns.pellet_dirs(weapon, dir, _rng):
		dispatcher.suspect_shot(self, muzzle, d, dmg, first)
		first = false


func muzzle_position() -> Vector3:
	var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
	if state == S.COVER and cphase == C.BLIND:
		# The gun held up over the top of the cover.
		return global_position + Vector3(0, 1.3, 0) + fwd * 0.45
	var sl := rig.model.find_child("gun_slide", true, false) as Node3D if rig and rig.model else null
	if sl:
		var xf := sl.global_transform
		var m := xf.origin - xf.basis.y.normalized() * float(EnemyGuns.MUZZLE[weapon])
		if m.distance_to(global_position + Vector3(0, 1.2, 0)) < 1.2:
			return m
	return global_position + Vector3(0, 1.4, 0) + fwd * 0.5


## A bullet went past close by: keep heads down for a moment.
func suppress() -> void:
	if not is_free():
		return
	_suppressed_t = SUPPRESS_TIME
	pressure += 0.06 if fighter else 0.25


# --- host: fighting ------------------------------------------------------------------

## Into the fight: find cover facing the officers (or grab something to throw).
func _engage(t: Dictionary) -> void:
	if not armed:
		var th := _throwable_near()
		if th and _threat_pos(t) != Vector3.INF:
			_start_throw(th)
			return
		_run_to_hide(t)
		return
	if not _called_backup and dispatcher and dispatcher.has_method("call_backup"):
		_called_backup = true
		dispatcher.call_backup(self)
	_take_cover(t, "near")


func _retreat(t: Dictionary) -> void:
	if not fighter or not armed or not _take_cover(t, "retreat"):
		_run_to_hide(t)


## Picks cover of this kind and runs to it. False if there is none.
func _take_cover(t: Dictionary, mode: String) -> bool:
	var tp := _threat_pos(t)
	if tp == Vector3.INF:
		return false
	var c := _find_cover(tp, mode)
	if c.is_empty():
		if mode == "near":
			# No cover about: stand and shoot, then think again.
			if armed and t.o and t.los:
				set_state(S.SHOOT)
			else:
				_run_to_hide(t)
			return true
		return false
	set_state(S.SEEK_COVER)
	cover_spot = c.p
	_peek_off = c.peek
	_goal = c.p
	_path = PackedVector3Array()
	_seek_t = 0.0
	return true


func _threat_pos(t: Dictionary) -> Vector3:
	if t.o:
		return (t.o as Officer).global_position
	return _last_seen


func _chest(o: Officer) -> Vector3:
	return o.global_position + Vector3(0, 1.1, 0)


const COVER_MASK := 1 | 4    # the static world and cars

## Somewhere to fight from: a spot on the walkable floor that is hidden from
## the officers when crouched, with something solid close in front, and
## (unless retreating) a way to shoot from it: standing up over low cover,
## or leaning out a step to the side round a corner.
## mode: "near" (about COVER_IDEAL from them, close by), "advance" (closer),
## "flank" (round the side of them), "retreat" (far away).
## Returns {p, peek} (peek: the lean-out step, zero to stand up), or {}.
func _find_cover(threat_p: Vector3, mode: String) -> Dictionary:
	if nav == null or not nav.ready_to_use:
		return {}
	var space := get_world_3d().direct_space_state
	var eye := threat_p + Vector3(0, 1.4, 0)
	var me := global_position
	var centre := me
	var radii := [1.5, 3.0, 4.5, 6.0, 7.5, 9.0, 11.0]
	if mode == "advance":
		centre = me.lerp(threat_p, 0.5)
		radii = [1.5, 2.5, 3.5, 5.0, 6.5]
	elif mode == "flank":
		centre = threat_p
		radii = [5.0, 6.5, 8.0, 9.5, 11.0, 12.5]
	elif mode == "retreat":
		radii = [5.0, 7.0, 9.0, 11.0, 13.0, 15.0, 17.0]
	var from_threat := me - threat_p
	from_threat.y = 0.0
	var others := []
	for n in get_tree().get_nodes_in_group("suspects"):
		var o := n as Suspect
		if o != self and o.cover_spot != Vector3.INF:
			others.append(o.cover_spot)
	var best := {}
	var best_score := -INF
	for r in radii:
		var steps := 20
		for k in steps:
			var a := TAU * (float(k) + _rng.randf() * 0.6) / steps
			var sample: Vector3 = centre + Vector3(cos(a) * r, 0, sin(a) * r)
			sample.y = me.y
			var p := nav.closest(sample)
			if Vector2(p.x - sample.x, p.z - sample.z).length() > 1.0 or absf(p.y - me.y) > 1.6:
				continue
			var d_threat := Vector2(p.x - threat_p.x, p.z - threat_p.z).length()
			if d_threat < 4.0:
				continue
			var crowded := false
			for q in others:
				if (q as Vector3).distance_to(p) < 1.5:
					crowded = true
			if crowded:
				continue
			var low := p + Vector3(0, 0.85, 0)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(low, eye, COVER_MASK, [get_rid()]))
			if hit.is_empty():
				continue
			var blocker_d := low.distance_to(hit.position)
			if blocker_d > 2.5 and mode != "retreat":
				continue
			var peek := _peek_from(space, p, eye)
			var can_peek := peek != Vector3.INF
			if not can_peek and mode != "retreat":
				continue
			var score := 0.0
			match mode:
				"near":
					score = -absf(d_threat - COVER_IDEAL) * 0.6 - me.distance_to(p) * 0.5
				"advance":
					score = -absf(d_threat - 6.0) * 0.6 - me.distance_to(p) * 0.3
				"flank":
					var v := p - threat_p
					v.y = 0.0
					var ang := rad_to_deg(v.angle_to(from_threat)) if from_threat.length() > 0.1 else 0.0
					score = ang * 0.12 - absf(d_threat - 8.0) * 0.4 - me.distance_to(p) * 0.15
				"retreat":
					score = d_threat * 0.5 - me.distance_to(p) * 0.2 + (2.0 if can_peek else 0.0)
			score += (1.5 if blocker_d < 1.2 else 0.0) + _rng.randf()
			if score <= best_score:
				continue
			if not nav.reaches(me, p):
				continue
			best_score = score
			best = {"p": p, "peek": peek if can_peek else Vector3.ZERO}
	return best


## How to shoot from cover at p: Vector3.ZERO (stand up over it), a step to
## the side (lean out round the corner), or Vector3.INF (no way).
func _peek_from(space: PhysicsDirectSpaceState3D, p: Vector3, eye: Vector3) -> Vector3:
	var up := p + Vector3(0, 1.45, 0)
	if space.intersect_ray(PhysicsRayQueryParameters3D.create(up, eye, COVER_MASK, [get_rid()])).is_empty():
		return Vector3.ZERO
	var to := eye - p
	to.y = 0.0
	to = to.normalized()
	var side := Vector3(-to.z, 0, to.x)
	for sgn in [1.0, -1.0]:
		var off: Vector3 = side * 0.75 * sgn
		var mid := p + Vector3(0, 1.0, 0)
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(mid, mid + off * 1.4, COVER_MASK, [get_rid()])).is_empty():
			continue
		var q := p + off + Vector3(0, 1.4, 0)
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(q, eye, COVER_MASK, [get_rid()])).is_empty():
			return off
	return Vector3.INF


func _seek_cover_step(t: Dictionary, delta: float) -> Array:
	_seek_t += delta
	var wish := _steer(cover_spot, delta)
	# The one pinning them down shoots on the move.
	if armed and mag > 0 and t.o and t.los and t.d < SHOOT_RANGE and _shoot_t <= 0.0 and role == ROLE_PIN and _rng.randf() < 0.5:
		aim_at = _chest(t.o)
		_fire_at(aim_at, 0.14)
	if (wish == Vector3.ZERO and _arrived()) or _seek_t > 9.0:
		set_state(S.COVER)
		_ct = _rng.randf_range(0.4, 1.0)
		_eval_t = 0.8
		return [Vector3.ZERO, 0.0]
	return [wish, RUN]


func _cover_step(t: Dictionary, delta: float) -> Array:
	var wish := Vector3.ZERO
	var speed := 0.0
	if cover_spot == Vector3.INF:
		cover_spot = global_position
	var want := cover_spot + (_peek_off if cphase == C.PEEK else Vector3.ZERO)
	var to := want - global_position
	to.y = 0.0
	if to.length() > 0.12:
		wish = to.normalized()
		speed = minf(WALK * 1.8, to.length() * 6.0)
	var tp := _threat_pos(t)
	_ct -= delta
	_eval_t -= delta
	if _eval_t <= 0.0:
		_eval_t = 1.0
		if _re_evaluate(t):
			return [Vector3.ZERO, 0.0]
	match cphase:
		C.HIDE:
			if _ct <= 0.0:
				_next_move(t)
		C.RELOAD:
			if _ct <= 0.0:
				mag = EnemyGuns.MAG[weapon]
				_hide(0.2)
		C.PEEK:
			if tp != Vector3.INF:
				aim_at = tp + Vector3(0, 1.1, 0)
			if _ct < 1.35 and _burst > 0 and _shoot_t <= 0.0 and mag > 0:
				if t.o and t.los:
					aim_at = _chest(t.o)
					_burst -= 1
					_fire_at(aim_at, 0.045 + (0.05 if _cycles == 0 else 0.0))
				elif role == ROLE_PIN and _last_seen != Vector3.INF:
					# Suppressing fire at where they were last seen.
					_burst -= 1
					_fire_at(_last_seen + Vector3(0, 1.0, 0), 0.12)
			if _ct <= 0.0 or (_burst <= 0 and _shoot_t <= -0.15) or mag <= 0:
				_hide(0.0)
		C.BLIND:
			if tp != Vector3.INF:
				aim_at = tp + Vector3(0, 1.0, 0)
				if _burst > 0 and _shoot_t <= 0.0 and _ct < 1.1 and mag > 0:
					_burst -= 1
					_fire_at(aim_at, 0.3)
			if _ct <= 0.0 or (_burst <= 0 and _shoot_t <= -0.2) or mag <= 0:
				_hide(0.0)
	return [wish, speed]


func _hide(extra: float) -> void:
	cphase = C.HIDE
	_cycles += 1
	_ct = _rng.randf_range(0.9, 2.0) * (0.6 if role == ROLE_PIN else 1.0) + extra
	if _suppressed_t > 0.0:
		_ct += 1.0


## Out of the hide: reload, shoot, move, throw something.
func _next_move(t: Dictionary) -> void:
	if armed and mag <= 0:
		cphase = C.RELOAD
		_ct = EnemyGuns.RELOAD[weapon]
		return
	var tp := _threat_pos(t)
	if not armed:
		var th := _throwable_near()
		if th and tp != Vector3.INF:
			_start_throw(th)
		else:
			_retreat(t)
		return
	if tp == Vector3.INF:
		set_state(S.LOITER)
		home = global_position
		return
	if _unseen_t > 7.0:
		# Lost them: push up to where they were.
		_unseen_t = 0.0
		if _take_cover({"o": null, "d": INF, "los": false}, "advance"):
			return
	if role == ROLE_FLANK and _cycles >= 2 and not _flanked:
		_flanked = true
		if _take_cover(t, "flank"):
			return
	var th := _throwable_near()
	if th and t.o and t.d < 14.0 and _rng.randf() < 0.12:
		_start_throw(th)
		return
	var shotgun := weapon == EnemyGuns.SHOTGUN
	if _suppressed_t > 0.0 or _rng.randf() < 0.22:
		cphase = C.BLIND
		_burst = 1 if shotgun else _rng.randi_range(2, 3)
		_ct = 1.4
	else:
		cphase = C.PEEK
		_burst = 1 if shotgun else _rng.randi_range(2, 4) + (1 if role == ROLE_PIN else 0)
		_ct = 1.9
		_shoot_t = maxf(_shoot_t, 0.0)


## Every second in cover: is it still any good? True if they moved on.
func _re_evaluate(t: Dictionary) -> bool:
	if t.o == null:
		return false
	if hp < MAX_HP * 0.4 and not _retreated:
		_retreated = true
		_retreat(t)
		return true
	if t.d < 3.0:
		if pressure > 0.8 and _rng.randf() < 0.5:
			set_state(S.SURRENDER)
		else:
			_bolt(t)
		return true
	# Flanked: an officer can see them even crouched.
	if cphase in [C.HIDE, C.RELOAD] and t.d < 22.0:
		var eye := (t.o as Officer).global_position + Vector3(0, 1.4, 0)
		var q := PhysicsRayQueryParameters3D.create(eye, global_position + Vector3(0, 0.85, 0), COVER_MASK, [get_rid()])
		if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			_take_cover(t, "near")
			return true
	# Outnumbered: back off.
	var officers := 0
	for n in get_tree().get_nodes_in_group("officers"):
		var o := n as Officer
		if o and o.state != Officer.S.DOWNED and o.global_position.distance_to(global_position) < 20.0:
			officers += 1
	var allies := 0
	for n in get_tree().get_nodes_in_group("suspects"):
		var s2 := n as Suspect
		if s2 != self and s2.fighter and s2.is_free() and s2.global_position.distance_to(global_position) < 15.0:
			allies += 1
	if officers >= allies + 3 and not _retreated and _rng.randf() < 0.3:
		_retreated = true
		_retreat(t)
		return true
	return false


# --- host: throwing things -------------------------------------------------------------

## Loose things close by that can be picked up and thrown (bottles, chairs,
## bins: rigid bodies in the "throwable" group).
func _throwable_near() -> RigidBody3D:
	var best: RigidBody3D = null
	var bd := THROW_REACH
	for n in get_tree().get_nodes_in_group("throwable"):
		var rb := n as RigidBody3D
		if rb == null or rb.has_meta("held") or rb.mass > 25.0 or not rb.is_inside_tree():
			continue
		var d := rb.global_position.distance_to(global_position)
		if d < bd and absf(rb.global_position.y - global_position.y) < 1.5:
			bd = d
			best = rb
	return best


func _start_throw(rb: RigidBody3D) -> void:
	set_state(S.THROW)
	_grab = rb
	_held = null
	_throw_t = 0.0


func _throw_step(t: Dictionary, delta: float) -> Array:
	var tp := _threat_pos(t)
	if _held == null:
		if _grab == null or not is_instance_valid(_grab) or _grab.has_meta("held") or state_t > 5.0:
			_after_throw(t)
			return [Vector3.ZERO, 0.0]
		var to := _grab.global_position - global_position
		to.y = 0.0
		if to.length() > 0.9:
			return [_steer(_grab.global_position, delta), RUN]
		_held = _grab
		_held.set_meta("held", true)
		_held.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		_held.freeze = true
		holding = true
		_throw_t = 0.6
		return [Vector3.ZERO, 0.0]
	if tp != Vector3.INF:
		_face(tp)
	_throw_t -= delta
	if _throw_t <= 0.0:
		if tp != Vector3.INF:
			var lead := Vector3.ZERO
			if t.o:
				lead = (t.o as Officer).velocity * 0.3
			_drop_held(Thrown.launch_velocity(_held.global_position, tp + lead + Vector3(0, 1.0, 0), THROW_SPEED))
		else:
			_drop_held(Vector3.ZERO)
		_after_throw(t)
	return [Vector3.ZERO, 0.0]


func _after_throw(t: Dictionary) -> void:
	_grab = null
	if fighter and armed:
		_take_cover(t, "near")
	elif fighter and _throwable_near() and t.o and t.d < 16.0:
		_start_throw(_throwable_near())
	else:
		_run_to_hide(t)


## Host: keeps a held thing over their head.
func _carry_held() -> void:
	if _held == null:
		return
	if not is_instance_valid(_held):
		_held = null
		holding = false
		return
	var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
	_held.global_position = global_position + Vector3(0, 2.05, 0) - fwd * 0.1
	_held.linear_velocity = Vector3.ZERO


## Lets go of what they hold, at velocity v (zero just drops it).
func _drop_held(v: Vector3) -> void:
	holding = false
	if _held == null or not is_instance_valid(_held):
		_held = null
		return
	var rb := _held
	_held = null
	rb.remove_meta("held")
	rb.freeze = false
	rb.linear_velocity = v
	if v != Vector3.ZERO:
		rb.angular_velocity = Vector3(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6), _rng.randf_range(-6, 6))
		Thrown.arm(rb, self)


## Kerbs and stair treads: hop up small steps the capsule catches on.
## want: where they are trying to go (their velocity is zero once a step
## stops them dead, so it can't be used for this).
func _step_up(want: Vector3) -> void:
	if not is_on_wall() or Vector2(want.x, want.z).length() < 0.3:
		return
	var fwd := Vector3(want.x, 0, want.z).normalized()
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
		S.COVER:
			match cphase:
				C.PEEK:
					lower = "idle" if hs < 0.2 else "walk"
					upper = "aim_hold"
				C.BLIND:
					lower = "crouch_idle"
					upper = "aim_hold"
				C.RELOAD:
					lower = "crouch_idle"
					upper = "reload"
				_:
					lower = "crouch_walk" if hs > 0.3 else "crouch_idle"
					upper = "ready_hold" if armed else "none"
		S.THROW:
			lower = "idle" if hs < 0.2 else ("walk" if hs < 2.2 else "run")
			upper = "hands_up" if holding else "none"
		S.SURRENDER:
			lower = "kneel"
			upper = "hands_up"
		S.COWER:
			lower = "crouch_idle"
			upper = "hands_up"
		S.BRAWL:
			lower = "idle" if hs < 0.2 else "walk"
			upper = "aim_hold" if armed else "punch" if fmod(Time.get_ticks_msec() / 1000.0 + net_id * 0.37, 1.3) < 0.55 else "none"
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
	b.put_u8(state)
	b.put_u8(cphase | (weapon << 2) | (16 if holding else 0) | (32 if fighter else 0) | (64 if civilian else 0))
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
	d.state = b.get_u8()
	var fl := b.get_u8()
	d.cphase = fl & 3
	d.weapon = (fl >> 2) & 3
	d.holding = (fl & 16) != 0
	d.fighter = (fl & 32) != 0
	d.civilian = (fl & 64) != 0
	d.armed = d.weapon != EnemyGuns.NONE
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
	if d.look != look:
		look = d.look
		if rig:
			SuspectLook.apply(rig.model, look)
	if d.state != state:
		set_state(d.state)
	weapon = d.weapon
	cphase = d.cphase
	holding = d.holding
	fighter = d.fighter
	civilian = d.get("civilian", false)
	aim_at = d.aim
	hp = d.hp
	seat = d.seat
	escort_peer = d.escort
	_show_gun()
