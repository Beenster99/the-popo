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

enum S { MOVE, CROUCH, PRONE, COVER, AIR, ROLL, SLIDE, VAULT, CLIMB, KICK }

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
const ROLL_PLAYBACK := 1.25
const MANTLE_PLAYBACK := 1.35
const CLIMB_PLAYBACK := 1.0
const CAPSULE_H := 1.8
const VAULT_MIN := 0.45
const VAULT_MAX := 1.3
const CLIMB_MAX := 2.4

signal fired(origin: Vector3, dir: Vector3, alt_tool: bool)

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
# Cover: the wall's outward normal, where the officer tucked in, and whether
# the wall is low enough to crouch behind and aim over.
var _cover_n := Vector3.FORWARD
var _cover_anchor := Vector3.ZERO
var _cover_low := false
const LOW_COVER := 1.35   # walls lower than this are crouched behind
const BODY_HALF := 0.35   # half the body's width, kept behind the wall
const PEEK_OUT := 0.6     # how far the officer leans out past a wall's edge
var _shape: CollisionShape3D
var _visual: Node3D


func _init() -> void:
	collision_layer = 2
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
	return (buttons & PlayerInput.AIM) != 0 and state in [S.MOVE, S.CROUCH, S.PRONE, S.COVER, S.AIR]


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

	match state:
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
			_set_state(S.MOVE)
		elif state in [S.MOVE, S.CROUCH]:
			_try_cover()

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
	if _pressed(PlayerInput.PUNCH) and state in [S.MOVE, S.CROUCH, S.AIR]:
		punch_t = 0.55

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
	var target := wish * speed
	var accel := ACCEL if on_floor else AIR_ACCEL
	var h := Vector3(velocity.x, 0, velocity.z).move_toward(target, accel * delta)
	velocity.x = h.x
	velocity.z = h.z
	if not on_floor:
		velocity.y -= GRAVITY * delta
		if state != S.AIR and velocity.y < -2.0:
			_set_state(S.AIR)
	elif state == S.AIR and state_t > 0.1:
		_set_state(S.MOVE)
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

	if buttons & PlayerInput.FIRE and is_aiming() and _cooldown <= 0.0 and Net.is_host():
		_cooldown = 0.18
		var muzzle := muzzle_position()
		fired.emit(muzzle, shot_direction(muzzle), false)


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
		S.PRONE: h = 0.6
		S.COVER: h = 1.1 if _cover_low and not is_aiming() else CAPSULE_H
	var cap := _shape.shape as CapsuleShape3D
	if not is_equal_approx(cap.height, h):
		cap.height = h
		_shape.position.y = h * 0.5


# --- Traversal -----------------------------------------------------------------

## Looks ahead for something to vault or climb. Returns true if it started one.
func _try_traverse() -> bool:
	var space := get_world_3d().direct_space_state
	var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var base := global_position
	var ex := [get_rid()]
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(base + Vector3(0, 0.35, 0), base + Vector3(0, 0.35, 0) + fwd * 1.1, 1 | 16, ex))
	if hit.is_empty():
		return false
	var wall: Vector3 = hit.position
	# Find the top of the obstacle just past its face.
	var probe := wall + fwd * 0.2
	var top_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(probe.x, base.y + CLIMB_MAX + 0.3, probe.z), Vector3(probe.x, base.y + 0.1, probe.z), 1 | 16, ex))
	if top_hit.is_empty():
		return false
	var height: float = top_hit.position.y - base.y
	# Room to stand on top?
	var clear := space.intersect_ray(PhysicsRayQueryParameters3D.create(top_hit.position + Vector3(0, 0.05, 0), top_hit.position + Vector3(0, 1.7, 0), 1 | 16, ex))
	if not clear.is_empty():
		return false
	rotation.y = atan2(fwd.x, fwd.z)
	if height >= VAULT_MIN and height <= VAULT_MAX:
		# Thin wall with ground behind it: vault over. Otherwise step up onto it.
		var behind := wall + fwd * 1.3
		var far := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(behind.x, top_hit.position.y + 0.2, behind.z), Vector3(behind.x, base.y - 0.5, behind.z), 1 | 16, ex))
		var lands_low: bool = not far.is_empty() and far.position.y < base.y + 0.3
		_begin_scripted(S.VAULT, 0.0 if lands_low else height)
		return true
	if height > VAULT_MAX and height <= CLIMB_MAX:
		_begin_scripted(S.CLIMB, height)
		return true
	return false


func _try_cover() -> void:
	var space := get_world_3d().direct_space_state
	var fwd := Vector3(sin(rotation.y), 0, cos(rotation.y))
	var o := global_position + Vector3(0, 1.0, 0)
	var hit := {}
	# Chest height first, then knee height for low walls.
	for h in [1.0, 0.5]:
		o = global_position + Vector3(0, h, 0)
		hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + fwd * 1.2, 1 | 16, [get_rid()]))
		if not hit.is_empty() and absf(hit.normal.y) < 0.3:
			break
	if hit.is_empty() or absf(hit.normal.y) > 0.3:
		return
	var n: Vector3 = Vector3(hit.normal.x, 0, hit.normal.z).normalized()
	_cover_n = n
	# How tall is the wall here? Low walls are crouched behind.
	var inside: Vector3 = hit.position - n * 0.15
	var top := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(inside.x, global_position.y + 3.0, inside.z), Vector3(inside.x, global_position.y, inside.z), 1 | 16, [get_rid()]))
	var height := 3.0 if top.is_empty() else float(top.position.y - global_position.y)
	_cover_low = height < LOW_COVER
	var p := Vector3(hit.position.x, global_position.y, hit.position.z) + n * 0.45
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


## How far the cover wall carries on from p in direction dir (up to 1 m).
func _wall_reach(p: Vector3, dir: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var h := 0.6 if _cover_low else 1.0
	var d := 0.0
	while d <= 1.0:
		var o := p + dir * d + Vector3(0, h, 0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(o, o - _cover_n * 0.8, 1 | 16, [get_rid()]))
		if hit.is_empty():
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
	velocity = Vector3(sin(_move_yaw), 0, cos(_move_yaw)) * (RUN * 0.6 if was == S.ROLL else 0.5)


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
	b.put_u8(1 if _cover_low else 0)


func decode_state(b: StreamPeerBuffer) -> Dictionary:
	return {
		"pos": Vector3(b.get_float(), b.get_float(), b.get_float()),
		"vel": Vector3(b.get_half(), b.get_half(), b.get_half()),
		"yaw": b.get_half(), "aim": b.get_half(), "state": b.get_u8(), "st": b.get_half(),
		"buttons": b.get_u16(), "punch": b.get_half(),
		"ms": Vector3(b.get_float(), b.get_float(), b.get_float()), "my": b.get_half(), "mr": b.get_half(),
		"cn": Vector3(b.get_half(), 0.0, b.get_half()), "ca": Vector3(b.get_float(), b.get_float(), b.get_float()),
		"cl": b.get_u8() == 1,
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
	_cover_low = s.cl
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
		rig.update_from(self, delta)
		for g in rig.model.find_children("gun_*", "", true, false):
			g.visible = is_aiming() or state in [S.COVER, S.CROUCH, S.PRONE]
