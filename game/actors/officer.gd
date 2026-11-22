class_name Officer
extends CharacterBody3D
## The Phase 0.6 officer: a networked character controller with a state
## machine for standing, crouching, prone, cover, vaulting, climbing,
## sliding, rolling, jumping and melee. Same pawn interface as
## CapsuleOfficer, so PawnSync predicts and interpolates it the same way.
##
## Controls: WASD move, Shift sprint, Space jump / vault / climb, Ctrl tap
## crouch or stand, hold prone, hold while running roll (slide when
## sprinting), R take cover at a wall, RMB aim (peeks out of cover), LMB fire
## from the barrel at the reticle, V punch, B kick, MMB ping (defaults;
## players can rebind them, and a controller works too).

enum S { MOVE, CROUCH, PRONE, COVER, AIR, ROLL, SLIDE, VAULT, CLIMB, KICK, DOWNED }
## What a melee strike was (see struck).
enum Strike { PUNCH, KICK, BARGE }

const RUN := 3.6
const SPRINT := 5.6
const WALK_AIM := 1.8
const CROUCH_SPEED := 1.5
const CRAWL_SPEED := 0.6
const COVER_SPEED := 1.2
const ACCEL := 30.0
const AIR_ACCEL := 6.0
const JUMP_V := 4.6
const GRAVITY := 16.0
const SLIDE_TIME := 0.85
const ROLL_PLAYBACK := 1.45
const MANTLE_PLAYBACK := 1.7
const CLIMB_PLAYBACK := 1.0
const CAPSULE_H := 1.8
const VAULT_MIN := 0.45
const VAULT_MAX := 1.45
const CLIMB_MAX := 2.4
## Loose bodies lighter than this do not block traversal.
const DEBRIS_MASS := 25.0
## Walls, cars and rubble all give cover.
const COVER_MASK := 1 | 4 | 16
## How far cover-to-cover looks for the next cover.
const DASH_RANGE := 10.0
## Longest a run to cover may take before it gives up.
const DASH_TIME := 3.0

signal fired(origin: Vector3, dir: Vector3, alt_tool: bool)
## A punch, kick or shoulder barge lands now (host only): the scene finds what
## is in front of origin along dir and hurts or shoves it.
signal struck(origin: Vector3, dir: Vector3, kind: Strike)

const MAX_HP := 100.0
## Hold interact this long next to a downed teammate to get them up.
const REVIVE_TIME := 2.0
const REVIVE_RANGE := 1.6
## Alone, a downed officer gets up by themselves after this long.
const SELF_REVIVE := 30.0
## Landing faster than this hurts.
const FALL_HURT_V := 11.0
const KICK_HIT_T := 0.28
const PUNCH_HIT_T := 0.2   # punch_t counts down from 0.55
const BARGE_SPEED := 6.5

var hp := MAX_HP
var revive_t := 0.0
## Barge rather than punch (sprinting when punch was pressed).
var barging := false
var _fall_v := 0.0
## Knocked back: the push carries on and the legs can't fight it for a moment.
var stagger_t := 0.0

var peer_id := 1
var state: S = S.MOVE
var state_t := 0.0
var aim_yaw := 0.0
var aim_point := Vector3.ZERO
## Turning on the spot to face the aim (the feet step round, see OfficerRig).
var turning := false
const TURN_START := 0.6   # rad between body and aim before the feet step round
const TURN_STOP := 0.12
const TURN_RATE := 7.0    # rad/s
var _turn_active := false
var _slide_node: Node3D
var buttons := 0
var punch_t := 0.0
var rig: OfficerRig

# Traversal bookkeeping (part of the synced state so prediction replays it).
var _move_start := Vector3.ZERO
var _move_yaw := 0.0
var _move_rise := 0.0
var _prev_buttons := 0
var _crouch_toggle := false
var _prone_toggle := false
var _cooldown := 0.0
## Where the hands grip on a climb (cosmetic: other machines work it out
## from the synced start, facing and height).
var _ledge := Vector3.ZERO

# Weapon handling (synced: prediction replays it the same way everywhere).
const MAG := 15
const RELOAD_TIME := 1.7
const FIRE_GAP := 0.18
var ammo := MAG
var reload_t := 0.0       # seconds of reload left
var holstered := false
var bloom := 0.0          # grows with rapid fire, widens the spread
## Cosmetic: chest kick after a shot, and how long the gun stays up after a
## blind-fire shot from cover.
var recoil := 0.0
var blind_t := 0.0
var _rng := RandomNumberGenerator.new()
var _torch: SpotLight3D
# Cover: the wall's outward normal, where the officer tucked in, and whether
# the wall is low enough to crouch behind and aim over.
var _cover_n := Vector3.FORWARD
var _cover_anchor := Vector3.ZERO
var _cover_low := false
## Running to the next cover (target face point in _cover_anchor, normal in _cover_n).
var _dash := false
const LOW_COVER := 1.35   # walls lower than this are crouched behind
const BODY_HALF := 0.35   # half the body's width, kept behind the wall
const PEEK_OUT := 0.6     # how far the officer leans out past a wall's edge
var _shape: CollisionShape3D
var _visual: Node3D


func _init() -> void:
	collision_layer = 2
	add_to_group("officers")
	collision_mask = 1 | 4 | 16
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50)


func _ready() -> void:
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = CAPSULE_H
	_shape.shape = cap
	_shape.position.y = CAPSULE_H * 0.5
	add_child(_shape)
	_visual = Node3D.new()
	add_child(_visual)
	rig = OfficerRig.new()
	_visual.add_child(rig)
	OfficerClips._ensure_loaded()


func is_aiming() -> bool:
	return (buttons & PlayerInput.AIM) != 0 and not holstered and state in [S.MOVE, S.CROUCH, S.PRONE, S.COVER, S.AIR]


## Firing over or round cover without looking (fire held, aim not).
func is_blind_firing() -> bool:
	return state == S.COVER and (buttons & PlayerInput.FIRE) != 0 and (buttons & PlayerInput.AIM) == 0 and not holstered


func is_reloading() -> bool:
	return reload_t > 0.0


func _pressed(bit: int) -> bool:
	return (buttons & bit) != 0 and (_prev_buttons & bit) == 0


func sim_step(cmd: Dictionary, delta: float) -> void:
	_prev_buttons = buttons
	buttons = cmd.get("buttons", 0)
	aim_yaw = cmd.get("aim_yaw", aim_yaw)
	aim_point = cmd.get("aim_point", aim_point)
	var move: Vector2 = cmd.get("move", Vector2.ZERO)
	var wish := Vector3(move.x, 0, move.y)
	state_t += delta
	punch_t = maxf(0.0, punch_t - delta)
	_cooldown -= delta
	recoil = maxf(0.0, recoil - delta * 7.0)
	blind_t = maxf(0.0, blind_t - delta)
	bloom = maxf(0.0, bloom - delta * 2.5)
	stagger_t = maxf(0.0, stagger_t - delta)
	_weapon(delta)

	var punch_before := punch_t + delta
	if punch_t > 0.0 and punch_before > PUNCH_HIT_T and punch_t <= PUNCH_HIT_T and Net.is_host():
		struck.emit(global_position + Vector3(0, 1.3, 0), _fwd(), Strike.BARGE if barging else Strike.PUNCH)
	if punch_t <= 0.0:
		barging = false

	match state:
		S.DOWNED:
			_downed_step(delta)
			return
		S.ROLL, S.VAULT, S.CLIMB:
			_scripted_move(delta)
			return
		S.SLIDE:
			var k := 1.0 - state_t / SLIDE_TIME
			var fwd := Vector3(sin(_move_yaw), 0, cos(_move_yaw))
			velocity.x = fwd.x * lerpf(1.5, SPRINT * 1.15, k)
			velocity.z = fwd.z * lerpf(1.5, SPRINT * 1.15, k)
			velocity.y -= GRAVITY * delta
			move_and_slide()
			if state_t >= SLIDE_TIME:
				_set_state(S.CROUCH)
			return
		S.KICK:
			if state_t - delta < KICK_HIT_T and state_t >= KICK_HIT_T and Net.is_host():
				struck.emit(global_position + Vector3(0, 0.75, 0), _fwd(), Strike.KICK)
			velocity.x = move_toward(velocity.x, 0, ACCEL * delta)
			velocity.z = move_toward(velocity.z, 0, ACCEL * delta)
			velocity.y -= GRAVITY * delta
			move_and_slide()
			if state_t >= 0.7:
				_set_state(S.MOVE)
			return

	# Stance toggles.
	if _pressed(PlayerInput.CROUCH) and state in [S.MOVE, S.CROUCH, S.PRONE]:
		_set_state(S.MOVE if state == S.CROUCH else S.CROUCH)
	if _pressed(PlayerInput.PRONE) and state in [S.MOVE, S.CROUCH, S.PRONE]:
		_set_state(S.MOVE if state == S.PRONE else S.PRONE)
	if _pressed(PlayerInput.STAND) and state in [S.CROUCH, S.PRONE, S.COVER]:
		_set_state(S.MOVE)
	if _pressed(PlayerInput.COVER):
		if state == S.COVER:
			_leave_cover(wish)
		elif _dash:
			_dash = false
		elif state in [S.MOVE, S.CROUCH]:
			_try_cover()
	if _dash and (state != S.MOVE or state_t > DASH_TIME or _pressed(PlayerInput.JUMP) or _pressed(PlayerInput.DIVE)):
		_dash = false

	var on_floor := is_on_floor()
	# Actions.
	if on_floor and state in [S.MOVE, S.CROUCH]:
		if _pressed(PlayerInput.JUMP):
			if not _try_traverse():
				velocity.y = JUMP_V
				_set_state(S.AIR)
		elif _pressed(PlayerInput.DIVE):
			var hs := Vector2(velocity.x, velocity.z).length()
			_move_yaw = atan2(wish.x, wish.z) if wish.length() > 0.1 else rotation.y
			rotation.y = _move_yaw
			if buttons & PlayerInput.SPRINT and hs > RUN:
				_set_state(S.SLIDE)
			else:
				_begin_scripted(S.ROLL, 0.0)
			return
		elif _pressed(PlayerInput.KICK):
			_set_state(S.KICK)
			return
	if _pressed(PlayerInput.PUNCH) and state in [S.MOVE, S.CROUCH, S.AIR] and punch_t <= 0.0:
		punch_t = 0.55
		# Sprinting: a shoulder barge, a lunge that knocks things over.
		barging = state == S.MOVE and (buttons & PlayerInput.SPRINT) != 0 and Vector2(velocity.x, velocity.z).length() > RUN
		if barging:
			var f := _fwd()
			velocity.x = f.x * BARGE_SPEED
			velocity.z = f.z * BARGE_SPEED
	if is_reviving():
		wish = Vector3.ZERO

	# Speed for the current stance.
	var speed := RUN
	match state:
		S.CROUCH: speed = CROUCH_SPEED
		S.PRONE: speed = CRAWL_SPEED
		S.COVER: speed = COVER_SPEED
		_:
			if is_aiming():
				speed = WALK_AIM
			elif buttons & PlayerInput.SPRINT:
				speed = SPRINT
	if state == S.COVER:
		wish = _cover_wish(wish)
	elif _dash:
		wish = _dash_wish()
		speed = SPRINT
	var target := wish * speed
	var accel := ACCEL if on_floor else AIR_ACCEL
	if stagger_t > 0.0:
		target = Vector3.ZERO
		accel = 6.0
	var h := Vector3(velocity.x, 0, velocity.z).move_toward(target, accel * delta)
	velocity.x = h.x
	velocity.z = h.z
	if not on_floor:
		velocity.y -= GRAVITY * delta
		if state != S.AIR and velocity.y < -2.0:
			_set_state(S.AIR)
	elif state == S.AIR and state_t > 0.1:
		_set_state(S.MOVE)
		if _fall_v > FALL_HURT_V:
			take_damage((_fall_v - FALL_HURT_V) * 18.0, Vector3.DOWN)
	if state == S.AIR:
		_fall_v = maxf(_fall_v, -velocity.y)
	else:
		_fall_v = 0.0
	# Facing: toward the aim when aiming, else toward travel (not in cover).
	turning = false
	if state == S.COVER:
		# Facing the wall while hidden; facing the aim while peeking.
		var yaw := aim_yaw if is_aiming() else atan2(-_cover_n.x, -_cover_n.z)
		rotation.y = lerp_angle(rotation.y, yaw, 12.0 * delta)
	else:
		if is_aiming() and state == S.PRONE:
			# Prone: the whole body swings round to the aim.
			rotation.y = lerp_angle(rotation.y, aim_yaw, 6.0 * delta)
		elif is_aiming():
			# Aiming: the body follows the aim. Standing still, it waits until
			# the aim is well off to one side, then the feet step round,
			# instead of the upper body twisting a long way.
			var off := angle_difference(rotation.y, aim_yaw)
			if wish.length() > 0.1:
				rotation.y = lerp_angle(rotation.y, aim_yaw, 10.0 * delta)
				_turn_active = false
			else:
				if absf(off) > TURN_START:
					_turn_active = true
				if _turn_active:
					var step := clampf(off, -TURN_RATE * delta, TURN_RATE * delta)
					rotation.y += step
					turning = true
					if absf(off) < TURN_STOP:
						_turn_active = false
		elif wish.length() > 0.1:
			rotation.y = lerp_angle(rotation.y, atan2(wish.x, wish.z), 14.0 * delta)
	var before := global_position
	move_and_slide()
	if on_floor and state in [S.MOVE, S.CROUCH, S.COVER]:
		_step_up(target * delta, global_position - before)
	_set_capsule()

	if buttons & PlayerInput.FIRE and (is_aiming() or is_blind_firing()) and _cooldown <= 0.0 and reload_t <= 0.0:
		_cooldown = FIRE_GAP
		if ammo <= 0:
			reload_t = RELOAD_TIME   # dry: reload by itself
		else:
			ammo -= 1
			recoil = 1.0
			var blind := is_blind_firing()
			if blind:
				blind_t = 0.4
			if Net.is_host():
				var muzzle := muzzle_position()
				fired.emit(muzzle, _spread(shot_direction(muzzle), blind), false)
			bloom = minf(bloom + 0.7, 4.0)


func _fwd() -> Vector3:
	return Vector3(sin(rotation.y), 0, cos(rotation.y))


## Host only: bullets, blasts, falls and blows. At 0 hp the officer is downed.
func take_damage(amount: float, dir := Vector3.ZERO) -> void:
	if not Net.is_host() or state == S.DOWNED or amount <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		revive_t = 0.0
		_dash = false
		collision_mask = 1 | 4 | 16
		_set_state(S.DOWNED)
		if rig:
			rig.set_downed(true, (dir + Vector3.UP * 0.3) * 30.0)
	elif rig:
		rig.hit_reaction(dir, clampf(amount * 0.25, 2.0, 10.0))


## Host only: a push from a blow or a barge.
func shove(v: Vector3) -> void:
	if Net.is_host():
		velocity += v
		stagger_t = 0.35
		if v.y > 0.5 and state in [S.MOVE, S.CROUCH, S.COVER]:
			_set_state(S.AIR)


## Down: lies still. A teammate holding interact close by gets them up;
## alone, they get up by themselves after a while.
func _downed_step(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, ACCEL * 0.3 * delta)
	velocity.z = move_toward(velocity.z, 0, ACCEL * 0.3 * delta)
	velocity.y -= GRAVITY * delta
	move_and_slide()
	if _reviver() != null:
		revive_t += delta
	else:
		revive_t = maxf(0.0, revive_t - delta)
	if revive_t >= REVIVE_TIME or state_t >= SELF_REVIVE:
		hp = 50.0 if revive_t >= REVIVE_TIME else 25.0
		revive_t = 0.0
		_set_state(S.CROUCH)


## A teammate close by, up, and holding interact.
func _reviver() -> Officer:
	for n in get_tree().get_nodes_in_group("officers"):
		var o := n as Officer
		if o and o != self and o.state in [S.MOVE, S.CROUCH] and (o.buttons & PlayerInput.INTERACT) != 0 \
				and o.global_position.distance_to(global_position) < REVIVE_RANGE:
			return o
	return null


## Kneeling over a downed teammate, holding interact.
func is_reviving() -> bool:
	if state not in [S.MOVE, S.CROUCH] or (buttons & PlayerInput.INTERACT) == 0:
		return false
	for n in get_tree().get_nodes_in_group("officers"):
		var o := n as Officer
		if o and o != self and o.state == S.DOWNED and o.global_position.distance_to(global_position) < REVIVE_RANGE:
			return true
	return false


## Draw, holster and reload.
func _weapon(delta: float) -> void:
	if _pressed(PlayerInput.HOLSTER):
		holstered = not holstered
		reload_t = 0.0
	if holstered and _pressed(PlayerInput.AIM):
		holstered = false   # aiming draws the gun
	if _pressed(PlayerInput.RELOAD) and not holstered and ammo < MAG and reload_t <= 0.0:
		reload_t = RELOAD_TIME
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			reload_t = 0.0
			ammo = MAG


## Bullets go where you point, give or take: steady aimed shots are tight,
## rapid fire opens up, blind fire from cover is wild.
func _spread(dir: Vector3, blind: bool) -> Vector3:
	var deg := 0.4 + bloom * 1.2 + (9.0 if blind else 0.0)
	if state == S.PRONE:
		deg *= 0.5
	var r := deg_to_rad(deg)
	var side := dir.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var up := side.cross(dir).normalized()
	return (dir + side * tan(_rng.randf_range(-r, r)) + up * tan(_rng.randf_range(-r, r) * 0.6)).normalized()

## Stairs and kerbs: when walking is blocked by something no higher than
## STEP_MAX, lift over it. wanted: the horizontal move asked for this tick;
## done: how far the body actually got.
const STEP_MAX := 0.36
func _step_up(wanted: Vector3, done: Vector3) -> void:
	var h := Vector3(wanted.x, 0, wanted.z)
	var got := Vector3(done.x, 0, done.z)
	var left := h - h.normalized() * clampf(got.dot(h.normalized()), 0.0, h.length())
	if left.length() < 0.002:
		return
	var xf := global_transform
	var up := Vector3(0, STEP_MAX, 0)
	if test_move(xf, up):
		return
	var raised := xf.translated(up)
	if test_move(raised, left):
		return
	var col := KinematicCollision3D.new()
	if not test_move(raised.translated(left), -up, col):
		return
	var landing := raised.translated(left).origin + col.get_travel()
	if landing.y - xf.origin.y < 0.02:
		return
	# Only real treads: the surface stepped onto must be walkable.
	if col.get_normal().angle_to(Vector3.UP) > floor_max_angle:
		return
	global_position = landing
	velocity.y = 0.0
	apply_floor_snap()


## The end of the pistol barrel (falls back to chest height without a model).
func muzzle_position() -> Vector3:
	if _slide_node == null and rig and rig.model:
		_slide_node = rig.model.find_child("gun_slide", true, false) as Node3D
	if _slide_node:
		# The slide is a box 19 cm long along its local Y; the muzzle is its
		# far end, away from the grip.
		var xf := _slide_node.global_transform
		return xf.origin - xf.basis.y.normalized() * 0.095
	return global_position + Vector3(0, 1.35 if state != S.CROUCH else 0.95, 0)


## From the barrel toward what the player is pointing at. If the target is
## behind the barrel or right on top of it, shoot straight along the aim.
func shot_direction(muzzle: Vector3) -> Vector3:
	var flat := Vector3(sin(aim_yaw), 0, cos(aim_yaw))
	var to := aim_point - muzzle
	if aim_point == Vector3.ZERO or to.length() < 0.6 or to.normalized().dot(flat) < 0.3:
		return flat
	return to.normalized()


func _set_state(s: S) -> void:
	state = s
	state_t = 0.0
	_set_capsule()


func _set_capsule() -> void:
	if _shape == null:
		return
	var h := CAPSULE_H
	match state:
		S.CROUCH, S.SLIDE, S.ROLL: h = 1.1
		S.PRONE, S.DOWNED: h = 0.6
		S.COVER: h = 1.1 if _cover_low and not is_aiming() else CAPSULE_H
	var cap := _shape.shape as CapsuleShape3D
	if not is_equal_approx(cap.height, h):
		cap.height = h
		_shape.position.y = h * 0.5


# --- Traversal -----------------------------------------------------------------

## Looks ahead for something to vault or climb. Returns true if it started one.
## Scans forward rays upward from knee height: the first open height is the
## top of the obstacle, and the next blocked height above it (a window head,
## a ceiling) gives the headroom. That handles walls, sills with the glass
## gone, car bonnets and rubble heaps the same way.
func _try_traverse() -> bool:
	var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var base := global_position
	var mask := 1 | 4 | 16   # walls, cars, rubble
	var hit := {}
	for y0 in [0.35, 0.6]:
		var o := base + Vector3(0, y0, 0)
		hit = _solid_ray(o, o + fwd * 1.1, mask)
		if not hit.is_empty() and absf(hit.normal.y) < 0.5:
			break
		hit = {}
	if hit.is_empty():
		return false
	var wall: Vector3 = hit.position
	var face := (Vector3(wall.x, base.y, wall.z) - base).length()
	var reach := face + 0.35
	var _open := func(y: float) -> bool:
		var o := base + Vector3(0, y, 0)
		return _solid_ray(o, o + fwd * reach, mask).is_empty()
	var y: float = maxf(0.45, hit.position.y - base.y + 0.1)
	while y <= CLIMB_MAX + 0.05 and not _open.call(y):
		y += 0.1
	if y > CLIMB_MAX + 0.05:
		return false
	# Exact top just past the face.
	var probe := wall + fwd * 0.15
	var top_hit := _solid_ray(Vector3(probe.x, base.y + y + 0.02, probe.z), Vector3(probe.x, base.y + 0.1, probe.z), mask)
	if top_hit.is_empty():
		return false
	var top_y: float = top_hit.position.y
	var height: float = top_y - base.y
	# Headroom: how far up the opening stays open.
	var head := y
	while head < y + 1.7 and _open.call(head):
		head += 0.1
	var headroom: float = minf(head, y + 1.7) - height
	if height >= VAULT_MIN and height <= VAULT_MAX:
		# Thin obstacle with ground behind it: vault over. Otherwise step up onto it.
		# Low ground behind (1.3 m for a wall, 2.3 m across a car): vault over.
		var lands_low := false
		var behind := wall
		for d in [1.3, 2.3]:
			behind = wall + fwd * d
			var far := _solid_ray(Vector3(behind.x, top_y + 0.2, behind.z), Vector3(behind.x, base.y - 0.5, behind.z), mask)
			if not far.is_empty() and far.position.y < base.y + 0.3:
				lands_low = true
				break
		if lands_low:
			if headroom < 0.9:
				return false
			# The way through must be open (no glass left in the window).
			var gy: float = top_y + 0.4
			if not _solid_ray(Vector3(base.x, gy, base.z), Vector3(behind.x, gy, behind.z), mask).is_empty():
				return false
		elif headroom < 1.7:
			return false
		rotation.y = atan2(fwd.x, fwd.z)
		_begin_scripted(S.VAULT, 0.0 if lands_low else height)
		return true
	if height > VAULT_MAX and height <= CLIMB_MAX and headroom >= 1.7:
		rotation.y = atan2(fwd.x, fwd.z)
		_begin_scripted(S.CLIMB, height)
		_ledge = Vector3(wall.x, top_y, wall.z)
		return true
	return false


## A ray that ignores this officer and small loose debris (glass shards,
## splinters): those get brushed aside, so they never block a vault.
func _solid_ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var ex: Array[RID] = [get_rid()]
	for i in 6:
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask, ex))
		var rb := r.get("collider") as RigidBody3D
		if r.is_empty() or rb == null or rb.mass >= DEBRIS_MASS or rb is Car:
			return r
		ex.append(rb.get_rid())
	return {}


## Snaps into cover against whatever is just ahead: walls, cars, rubble.
func _try_cover() -> void:
	var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var hit := _cover_ray(global_position, fwd, 1.2)
	if not hit.is_empty():
		_enter_cover(hit.position, hit.normal)


## Chest height first, then knee height for low walls. Returns a hit on an
## upright face turned toward the officer, or {}.
func _cover_ray(from: Vector3, dir: Vector3, dist: float) -> Dictionary:
	for h in [1.0, 0.5]:
		var o := from + Vector3(0, h, 0)
		var hit := _solid_ray(o, o + dir * dist, COVER_MASK)
		if not hit.is_empty() and absf(hit.normal.y) < 0.3 and Vector3(hit.normal.x, 0, hit.normal.z).normalized().dot(dir) < -0.4:
			return hit
	return {}


func _enter_cover(at: Vector3, normal: Vector3) -> void:
	var n: Vector3 = Vector3(normal.x, 0, normal.z).normalized()
	_cover_n = n
	_dash = false
	# How tall is it here? Low walls and car bodies are crouched behind.
	var inside: Vector3 = at - n * 0.15
	var top := _solid_ray(Vector3(inside.x, global_position.y + 3.0, inside.z), Vector3(inside.x, global_position.y, inside.z), COVER_MASK)
	var height := 3.0 if top.is_empty() else float(top.position.y - global_position.y)
	_cover_low = height < LOW_COVER
	var p := Vector3(at.x, global_position.y, at.z) + n * 0.45
	# At the end of a wall, shuffle in so the whole body is behind it.
	var along := Vector3(-n.z, 0, n.x)
	for side in [-1.0, 1.0]:
		var reach := _wall_reach(p, along * side)
		if reach < BODY_HALF:
			p -= along * side * (BODY_HALF - reach)
	global_position = p
	_cover_anchor = p
	rotation.y = atan2(-n.x, -n.z)
	velocity = Vector3.ZERO
	_set_state(S.COVER)


## Cover pressed while in cover. With a direction held, run to the next
## cover that way (or swing round the end of this wall), else step out.
func _leave_cover(wish: Vector3) -> void:
	if wish.length() < 0.5 or wish.dot(_cover_n) < -0.5:
		_set_state(S.MOVE)
		return
	var dir := Vector3(wish.x, 0, wish.z).normalized()
	var along := Vector3(-_cover_n.z, 0, _cover_n.x)
	var here := global_position
	var side := signf(dir.dot(along))
	# Round the corner: at the end of the wall, heading along it.
	if absf(dir.dot(along)) > 0.7 and _wall_reach(here, along * side) < BODY_HALF + 0.1:
		var reach := _wall_reach(here, along * side)
		var o := here + along * side * (reach + 0.75) - _cover_n * 0.6
		var hit := _cover_ray(o, -along * side, 0.9)
		if not hit.is_empty():
			_start_dash(hit.position, hit.normal)
			return
	var hit := _cover_ray(here, dir, DASH_RANGE)
	if not hit.is_empty() and (hit.position - here).length() > 1.2:
		_start_dash(hit.position, hit.normal)
		return
	_set_state(S.MOVE)


func _start_dash(at: Vector3, normal: Vector3) -> void:
	_dash = true
	_cover_n = Vector3(normal.x, 0, normal.z).normalized()
	_cover_anchor = Vector3(at.x, global_position.y, at.z)
	_set_state(S.MOVE)


## Steering for a run to cover: straight at the spot in front of the face.
func _dash_wish() -> Vector3:
	var spot := _cover_anchor + _cover_n * 0.45
	var to := spot - global_position
	to.y = 0.0
	if to.length() < 0.25:
		_enter_cover(_cover_anchor, _cover_n)
		return Vector3.ZERO
	return to.normalized()


## How far the cover wall carries on from p in direction dir (up to 1 m).
func _wall_reach(p: Vector3, dir: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var h := 0.6 if _cover_low else 1.0
	var d := 0.0
	while d <= 1.0:
		var o := p + dir * d + Vector3(0, h, 0)
		if _solid_ray(o, o - _cover_n * 0.8, COVER_MASK).is_empty():
			return maxf(0.0, d - 0.05)
		d += 0.05
	return 1.0


## Movement while in cover: slide along the wall but not past its end. Aiming
## peeks: over a low wall by standing up, round the end of a tall wall by
## leaning out, and back in again when the aim is let go.
func _cover_wish(wish: Vector3) -> Vector3:
	var along := Vector3(-_cover_n.z, 0, _cover_n.x)
	var here := global_position
	if is_aiming():
		if _cover_low:
			return Vector3.ZERO
		# Lean out past the nearer end of the wall, if there is one close by.
		var target := _cover_anchor
		for side in [-1.0, 1.0]:
			if _wall_reach(_cover_anchor, along * side) < BODY_HALF + 0.15:
				target = _cover_anchor + along * side * PEEK_OUT
		var to := target - here
		to.y = 0.0
		return to.normalized() * clampf(to.length() * 8.0 / COVER_SPEED, 0.0, 1.0) if to.length() > 0.03 else Vector3.ZERO
	# Coming back in from a peek.
	var back := _cover_anchor - here
	back.y = 0.0
	if back.length() > 0.05 and wish.length() < 0.1:
		return back.normalized() * clampf(back.length() * 8.0 / COVER_SPEED, 0.0, 1.0)
	var w := along * wish.dot(along)
	if w.length() > 0.05:
		var side := signf(w.dot(along))
		if _wall_reach(here, along * side) < BODY_HALF:
			w = Vector3.ZERO   # at the end of the wall: stay hidden
		else:
			_cover_anchor = here
	return w


func _begin_scripted(s: S, rise: float) -> void:
	_set_state(s)
	_move_start = global_position
	_move_yaw = rotation.y
	_move_rise = rise
	velocity = Vector3.ZERO
	# Moves through the obstacle on a fixed path: no collisions meanwhile.
	collision_mask = 0


func _scripted_move(delta: float) -> void:
	var clip: String = {S.ROLL: "roll", S.VAULT: "mantle", S.CLIMB: "climb"}[state]
	var rate: float = {S.ROLL: ROLL_PLAYBACK, S.VAULT: MANTLE_PLAYBACK, S.CLIMB: CLIMB_PLAYBACK}[state]
	var length := OfficerClips.move_length(clip) / rate
	var t: float = minf(state_t, length)
	var off := OfficerClips.root_offset(clip, t * rate)
	var p := _move_start + off.rotated(Vector3.UP, _move_yaw)
	var k := clampf(t / length, 0.0, 1.0)
	# Vault onto a platform: rise over the middle of the move. A climb lifts
	# the body along the clip's own hips rise (taken out of the pose), scaled
	# to the real ledge height, so the model never hangs above the body.
	if state == S.VAULT:
		p.y = _move_start.y + _move_rise * smoothstep(0.25, 0.8, k)
	elif state == S.CLIMB:
		var total := maxf(OfficerClips.lift_total("climb"), 0.01)
		p.y = _move_start.y + _move_rise * OfficerClips.lift("climb", t * rate) / total
	else:
		p.y = _move_start.y
	var prev := global_position
	global_position = p
	velocity = (p - prev) / max(delta, 0.0001)
	if state == S.ROLL:
		# A roll is not a teleport through walls: stop at obstacles.
		collision_mask = 1 | 4 | 16
		global_position = prev
		var motion := p - prev
		var col := move_and_collide(motion)
		if col:
			_end_scripted()
			return
	if state_t >= length:
		_end_scripted()


func _end_scripted() -> void:
	collision_mask = 1 | 4 | 16
	var was := state
	if was == S.CLIMB:
		global_position.y = _move_start.y + _move_rise + 0.02
	_set_state(S.CROUCH if was == S.ROLL and (buttons & PlayerInput.CROUCH) else S.MOVE)
	# Come out of a roll or vault already running, so moves flow together.
	velocity = Vector3(sin(_move_yaw), 0, cos(_move_yaw)) * (RUN * 0.85 if was in [S.ROLL, S.VAULT] else 0.5)


# --- Network state --------------------------------------------------------------

func encode_state(b: StreamPeerBuffer) -> void:
	b.put_float(global_position.x)
	b.put_float(global_position.y)
	b.put_float(global_position.z)
	b.put_half(velocity.x)
	b.put_half(velocity.y)
	b.put_half(velocity.z)
	b.put_half(rotation.y)
	b.put_half(aim_yaw)
	b.put_u8(state)
	b.put_half(state_t)
	b.put_u16(buttons)
	b.put_half(punch_t)
	b.put_float(_move_start.x)
	b.put_float(_move_start.y)
	b.put_float(_move_start.z)
	b.put_half(_move_yaw)
	b.put_half(_move_rise)
	b.put_half(_cover_n.x)
	b.put_half(_cover_n.z)
	b.put_float(_cover_anchor.x)
	b.put_float(_cover_anchor.y)
	b.put_float(_cover_anchor.z)
	b.put_u8((1 if _cover_low else 0) | (2 if _dash else 0))
	b.put_u8(ammo | (128 if holstered else 0))
	b.put_half(reload_t)
	b.put_half(_cooldown)
	b.put_half(bloom)
	b.put_u8(int(hp))
	b.put_half(revive_t)
	b.put_u8(1 if barging else 0)
	b.put_half(stagger_t)


func decode_state(b: StreamPeerBuffer) -> Dictionary:
	return {
		"pos": Vector3(b.get_float(), b.get_float(), b.get_float()),
		"vel": Vector3(b.get_half(), b.get_half(), b.get_half()),
		"yaw": b.get_half(), "aim": b.get_half(), "state": b.get_u8(), "st": b.get_half(),
		"buttons": b.get_u16(), "punch": b.get_half(),
		"ms": Vector3(b.get_float(), b.get_float(), b.get_float()), "my": b.get_half(), "mr": b.get_half(),
		"cn": Vector3(b.get_half(), 0.0, b.get_half()), "ca": Vector3(b.get_float(), b.get_float(), b.get_float()),
		"cl": b.get_u8(),
		"ammo": b.get_u8(), "rl": b.get_half(), "cd": b.get_half(), "bl": b.get_half(),
		"hp": b.get_u8(), "rv": b.get_half(), "bg": b.get_u8() == 1, "sg": b.get_half(),
	}


func apply_state(s: Dictionary) -> void:
	global_position = s.pos
	velocity = s.vel
	rotation.y = s.yaw
	aim_yaw = s.aim
	if state != s.state:
		state = s.state
		_set_capsule()
	state_t = s.st
	_prev_buttons = buttons
	buttons = s.buttons
	punch_t = s.punch
	_move_start = s.ms
	_move_yaw = s.my
	_move_rise = s.mr
	_cover_n = s.cn
	_cover_anchor = s.ca
	_cover_low = (s.cl & 1) != 0
	_dash = (s.cl & 2) != 0
	ammo = s.ammo & 127
	holstered = (s.ammo & 128) != 0
	reload_t = s.rl
	_cooldown = s.cd
	bloom = s.bl
	hp = s.hp
	revive_t = s.rv
	barging = s.bg
	stagger_t = s.sg
	collision_mask = 0 if state in [S.VAULT, S.CLIMB] else (1 | 4 | 16)


func blend_state(a: Dictionary, c: Dictionary, t: float) -> Dictionary:
	var out := c.duplicate() if t > 0.5 else a.duplicate()
	out.pos = a.pos.lerp(c.pos, t)
	out.vel = a.vel.lerp(c.vel, t)
	out.yaw = lerp_angle(a.yaw, c.yaw, t)
	out.aim = lerp_angle(a.aim, c.aim, t)
	return out


func set_visual_offset(v: Vector3) -> void:
	if _visual:
		_visual.position = v


func _process(delta: float) -> void:
	if rig and rig.tree:
		if rig.downed != (state == S.DOWNED):
			rig.set_downed(state == S.DOWNED)
		rig.update_from(self, delta)
		for g in rig.model.find_children("gun_*", "", true, false):
			g.visible = not holstered and state not in [S.ROLL, S.VAULT, S.CLIMB, S.SLIDE, S.KICK, S.DOWNED]
		_update_torch()


## The torch: a beam from the chest along the aim, on while the player has it
## switched on (a synced button), so everyone sees it.
func _update_torch() -> void:
	var on := (buttons & PlayerInput.TORCH) != 0 and not holstered
	if on and _torch == null:
		_torch = SpotLight3D.new()
		_torch.light_color = Color("fff4d6")
		_torch.light_energy = 6.0
		_torch.spot_range = 16.0
		_torch.spot_angle = 18.0
		_torch.spot_attenuation = 0.6
		_torch.shadow_enabled = true
		add_child(_torch)
	if _torch:
		_torch.visible = on
		if on:
			var chest := Vector3(0, 1.0 if state == S.CROUCH else (0.35 if state == S.PRONE else 1.35), 0)
			_torch.global_position = global_position + chest
			var target := aim_point if aim_point != Vector3.ZERO else global_position + chest + Vector3(sin(aim_yaw), -0.15, cos(aim_yaw)) * 5.0
			if target.distance_to(_torch.global_position) > 0.3:
				_torch.look_at(target, Vector3.UP)
