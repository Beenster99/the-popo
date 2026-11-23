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

enum S { MOVE, CROUCH, PRONE, COVER, AIR, ROLL, SLIDE, VAULT, CLIMB, KICK, DOWNED, VEHICLE }
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
const LIMP_SPEED := 2.0       # m/s top speed with a leg wound
## Hold interact this long next to a downed teammate to get them up.
const REVIVE_TIME := 2.0
const REVIVE_RANGE := 1.6
## v0.2.11 (beenster: "grab my downed friend by the collar on the back of his
## neck and drag him into cover"): hold drag next to a downed teammate.
const DRAG_RANGE := 1.6
const DRAG_SPEED := 1.5       # m/s, walking backwards with them
const DRAG_LEASH := 0.9       # m from the dragger's feet to theirs
## Alone, a downed officer gets up by themselves after this long.
const SELF_REVIVE := 30.0
## Downed: after this long R respawns you back where you started, healed,
## patched up and with full ammo (beenster, v0.2.9).
const RESPAWN_AFTER := 3.0
## Where this officer came into the game; respawns put them back here.
var home := Vector3.INF
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

# --- Vehicles (Phase 1.3) ---
## The police car this officer sits in, and which seat (0 driver, 1 front
## passenger, 2 rear left, 3 rear right).
var car: PoliceCar = null
var seat := -1
const ENTER_RANGE := 1.4      # m from a door to get in
const BOOT_RANGE := 1.4       # m from the boot to use the ammo box and kit
const BOOT_TIME := 1.5        # s holding interact at the boot
var _boot_t := 0.0

# --- Injuries (Phase 1.2 addition) ---
## Wounds that last until treated: a leg wound limps, an arm wound shakes
## the aim, bleeding drains health.
const LEG := 1
const ARM := 2
const BLEED := 4
const BLEED_RATE := 1.2       # hp a second
const POUCH_MAX := 3          # field dressings in the first aid pouch
const TREAT_SELF := 3.0       # s to treat yourself
const TREAT_MATE := 1.5       # s for a teammate to treat you
## Health first aid gives back (beenster, v0.2.10: heal your friends). A
## teammate does a better job than you can on yourself.
const HEAL_SELF := 25.0
const HEAL_MATE := 45.0
const HURT_MARGIN := 5.0
var injuries := 0
var pouch := POUCH_MAX
var treat_t := 0.0
## Phase 1.4: holding interact next to a suspect who has given up cuffs them.
const CUFF_TIME := 1.2
const CUFF_RANGE := 1.6
var cuff_t := 0.0
var _rng_inj := RandomNumberGenerator.new()
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
var _shown_gun := -1
var _pellet_rng := RandomNumberGenerator.new()
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
## Holstering or drawing the pistol takes this long. The hand reaches the
## holster HOLSTER_GRIP seconds into holstering (the gun disappears there).
const HOLSTER_TIME := 0.6
const HOLSTER_GRIP := 0.42
const FIRE_GAP := 0.18
var ammo := MAG
## Spare rounds on the belt (magazines), used up by reloading.
const RESERVE_START := 60
const RESERVE_MAX := 90
var reserve := RESERVE_START
const WEAPON_NAME := "Service pistol"
## Phase 1.5: a gun picked up off the floor (EnemyGuns.PISTOL or SHOTGUN),
## or EnemyGuns.NONE for the service pistol. It has only the rounds that
## were in it: no reloading. Empty, or H, drops it.
var gun := EnemyGuns.NONE
var gun_ammo := 0
const PICK_RANGE := 1.4
var reload_t := 0.0       # seconds of reload left
var holstered := true          # officers start the game with the gun holstered
var holster_t := 0.0      # seconds of holstering / drawing left
var drawing := false      # holster_t counts down a draw (else a holster)
var bloom := 0.0          # grows with rapid fire, widens the spread
## Cosmetic: chest kick after a shot, and how long the gun stays up after a
## blind-fire shot from cover.
var recoil := 0.0
var blind_t := 0.0
var _cover_lost_t := 0
var _cover_armed := false
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
const COVER_GAP := 0.36   # body centre to the wall: back pressed against it
const COVER_SNAP := 1.6   # cover within this reach is snapped to
const PEEK_OUT := 0.22    # the small side step at a wall's edge; the body leans the rest
var _shape: CollisionShape3D
var _visual: Node3D


func _init() -> void:
	collision_layer = 2
	add_to_group("officers")
	collision_mask = 1 | 4 | 16
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50)


func _ready() -> void:
	home = global_position
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
	if state == S.VEHICLE:
		return (buttons & PlayerInput.AIM) != 0 and gun_up() and seat > 0
	return (buttons & PlayerInput.AIM) != 0 and gun_up() and state in [S.MOVE, S.CROUCH, S.PRONE, S.COVER, S.AIR]


## The pistol is out and in the hand (not mid-holster, nearly done drawing).
func gun_up() -> bool:
	if holstered:
		return false
	if holster_t <= 0.0:
		return true
	return drawing and holster_t < 0.15


## The pistol mesh shows in the hand (part way through a holster or draw).
func gun_in_hand() -> bool:
	if holstered:
		return false
	if holster_t <= 0.0:
		return true
	if drawing:
		return holster_t < HOLSTER_GRIP
	return holster_t > HOLSTER_TIME - HOLSTER_GRIP


## Firing over or round cover without looking (fire held, aim not).
func is_blind_firing() -> bool:
	return state == S.COVER and (buttons & PlayerInput.FIRE) != 0 and (buttons & PlayerInput.AIM) == 0 and gun_up()


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

	if injuries & BLEED and state != S.DOWNED:
		hp = maxf(hp - BLEED_RATE * delta, 0.5)
		if hp <= 0.5 and Net.is_host():
			take_damage(1.0, Vector3.ZERO, "bleed")
	match state:
		S.DOWNED:
			_downed_step(delta)
			return
		S.VEHICLE:
			_vehicle_step()
			_fire_step()
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
			_try_cover(wish)
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
	if state in [S.MOVE, S.CROUCH] and _pressed(PlayerInput.INTERACT) and not is_reviving() and _try_seat_prisoner():
		pass
	elif state in [S.MOVE, S.CROUCH] and _pressed(PlayerInput.INTERACT) and not is_reviving() and cuff_target() == null and _try_pick_gun():
		pass
	elif state in [S.MOVE, S.CROUCH] and _pressed(PlayerInput.INTERACT) and not is_reviving() and _try_enter_car():
		return
	_boot_and_treat(delta)
	if treat_t > 0.0 or _boot_t > 0.0 or cuff_t > 0.0:
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
			elif buttons & PlayerInput.SPRINT and not injuries & LEG:
				speed = SPRINT
	if injuries & LEG:
		speed = minf(speed, LIMP_SPEED)
	var dragged := drag_target()
	if dragged:
		speed = minf(speed, DRAG_SPEED)
	if state == S.COVER:
		# Moving away from the cover leaves it; so does the cover being
		# shot or blown away.
		# (Only once the stick has come off the way in: holding the run to
		# cover, or the corner swing, does not pop you straight back out.)
		if wish.dot(_cover_n) < 0.3:
			_cover_armed = true
		if not is_aiming() and _cover_armed and wish.dot(_cover_n) > 0.6:
			_set_state(S.MOVE)
		elif _cover_gone():
			_set_state(S.MOVE)
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
			take_damage((_fall_v - FALL_HURT_V) * 18.0, Vector3.DOWN, "fall")
	if state == S.AIR:
		_fall_v = maxf(_fall_v, -velocity.y)
	else:
		_fall_v = 0.0
	# Facing: toward the aim when aiming, else toward travel (not in cover).
	turning = false
	if state == S.COVER:
		# Back to the wall while hidden; facing the aim while peeking or
		# blind firing over or round it.
		var yaw := aim_yaw if is_aiming() or blind_t > 0.0 else atan2(_cover_n.x, _cover_n.z)
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
		elif wish.length() > 0.1 and not dragged:
			rotation.y = lerp_angle(rotation.y, atan2(wish.x, wish.z), 14.0 * delta)
	if dragged and not is_aiming():
		# Backing away, facing them, a hand in their collar.
		var to := dragged.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 10.0 * delta)
	var before := global_position
	move_and_slide()
	if on_floor and state in [S.MOVE, S.CROUCH, S.COVER]:
		_step_up(target * delta, global_position - before)
	_set_capsule()
	_fire_step()


func _fire_step() -> void:
	if buttons & PlayerInput.FIRE and (is_aiming() or is_blind_firing()) and _cooldown <= 0.0 and reload_t <= 0.0 and gun != EnemyGuns.NONE:
		_cooldown = EnemyGuns.GAP[gun]
		if gun_ammo <= 0:
			_drop_gun()   # empty: back to the service pistol
		else:
			gun_ammo -= 1
			recoil = 1.0 if gun == EnemyGuns.PISTOL else 1.6
			var blind := is_blind_firing()
			if blind:
				blind_t = 0.4
			if Net.is_host():
				var muzzle := muzzle_position()
				var d := _spread(shot_direction(muzzle), blind)
				for pd in EnemyGuns.pellet_dirs(gun, d, _pellet_rng):
					fired.emit(muzzle, pd, false)
			bloom = minf(bloom + (0.8 if gun == EnemyGuns.PISTOL else 2.0), 4.0)
	elif buttons & PlayerInput.FIRE and (is_aiming() or is_blind_firing()) and _cooldown <= 0.0 and reload_t <= 0.0:
		_cooldown = FIRE_GAP
		if ammo <= 0:
			if reserve > 0:
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


## Damage of one bullet (or pellet) from the gun in hand.
func shot_damage() -> float:
	return Gunfire.BULLET_DAMAGE if gun == EnemyGuns.NONE else float(EnemyGuns.DAMAGE[gun])


func weapon_name() -> String:
	return WEAPON_NAME if gun == EnemyGuns.NONE else String(EnemyGuns.NAMES[gun])


## The nearest gun on the floor within reach, or null.
func gun_on_floor() -> DroppedGun:
	var best: DroppedGun = null
	var bd := PICK_RANGE
	for n in get_tree().get_nodes_in_group("dropped_guns"):
		var g := n as DroppedGun
		var d := g.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = g
	return best


## Use next to a dropped gun: take it (host decides; clients are corrected).
func _try_pick_gun() -> bool:
	var g := gun_on_floor()
	if g == null:
		return false
	if Net.is_host():
		var disp := get_tree().get_first_node_in_group("dispatcher")
		if gun != EnemyGuns.NONE:
			_drop_gun()
		gun = g.kind
		gun_ammo = g.rounds
		holstered = false
		reload_t = 0.0
		if disp:
			disp.take_gun(g)
		else:
			g.queue_free()
	return true


## Lets go of the picked-up gun (left on the floor with what is left in it).
func _drop_gun() -> void:
	if gun == EnemyGuns.NONE:
		return
	if Net.is_host():
		var disp := get_tree().get_first_node_in_group("dispatcher")
		if disp and gun_ammo > 0:
			disp.drop_gun(global_position + _fwd() * 0.4, gun, gun_ammo)
	gun = EnemyGuns.NONE
	gun_ammo = 0
	_shown_gun = -1


## Host only: bullets, blasts, falls and blows. At 0 hp the officer is downed.
## where: "leg", "arm", "torso", "blast", "fall", "burn", "bleed" or "" (unknown),
## for the wound it may leave.
func take_damage(amount: float, dir := Vector3.ZERO, where := "") -> void:
	if not Net.is_host() or state == S.DOWNED or amount <= 0.0:
		return
	hp -= amount
	_wound(amount, where)
	if hp <= 0.0 and state == S.VEHICLE:
		_leave_car(true)
	if hp <= 0.0:
		hp = 0.0
		revive_t = 0.0
		_dash = false
		collision_mask = 1 | 4 | 16
		_set_state(S.DOWNED)
		if rig:
			rig.set_downed(true, (dir + Vector3.UP * 0.3) * 14.0, Vector3(velocity.x, 0.0, velocity.z))
	elif rig:
		rig.hit_reaction(dir, clampf(amount * 0.25, 2.0, 10.0))


## Which wound a hit leaves, if any (host only).
func _wound(amount: float, where: String) -> void:
	if amount < 8.0 or where == "bleed":
		return
	var r := _rng_inj.randf()
	match where:
		"leg":
			if r < 0.7:
				injuries |= LEG
		"arm":
			if r < 0.7:
				injuries |= ARM
		"torso":
			if r < 0.5:
				injuries |= BLEED
		"blast":
			injuries |= BLEED
			if r < 0.5:
				injuries |= LEG
		"fall":
			if amount >= 15.0:
				injuries |= LEG
		"burn":
			pass
		_:
			if r < 0.3:
				injuries |= BLEED


## Where on the body a point is, for wounds.
func body_part_at(p: Vector3) -> String:
	var h := p.y - global_position.y
	var low := 0.35 if state == S.PRONE else 0.85
	if state in [S.PRONE, S.DOWNED]:
		return "torso"
	if h < low:
		return "leg"
	var side := (p - global_position) * Vector3(1, 0, 1)
	var right := Vector3(cos(rotation.y), 0, -sin(rotation.y))
	if absf(side.dot(right)) > 0.2:
		return "arm"
	return "torso"


## Treats the worst wound: bleeding (bandage), then the leg (splint), then
## the arm (sling). Returns what was used.
func treat_one(heal := HEAL_SELF) -> String:
	var used := ""
	if injuries & BLEED:
		injuries &= ~BLEED
		used = "bandage"
	elif injuries & LEG:
		injuries &= ~LEG
		used = "splint"
	elif injuries & ARM:
		injuries &= ~ARM
		used = "sling"
	elif hp < MAX_HP - 1.0:
		used = "dressing"
	if used != "" and Net.is_host():
		hp = minf(hp + heal, MAX_HP)
	return used


## Lost health or a wound: first aid will help.
func needs_aid() -> bool:
	return injuries != 0 or hp < MAX_HP - HURT_MARGIN


static func injury_names(bits: int) -> PackedStringArray:
	var out: PackedStringArray = []
	if bits & BLEED:
		out.append("BLEEDING")
	if bits & LEG:
		out.append("LEG WOUND")
	if bits & ARM:
		out.append("ARM WOUND")
	return out


## Holding interact: at a police car's boot, restock ammo and first aid; next
## to a wounded teammate, treat them; else treat yourself (pouch permitting).
func _boot_and_treat(delta: float) -> void:
	var held := (buttons & PlayerInput.INTERACT) != 0 and state in [S.MOVE, S.CROUCH] and not is_reviving()
	if not held:
		_boot_t = 0.0
		treat_t = 0.0
		cuff_t = 0.0
		return
	# A suspect on their knees close by: cuffs first.
	var cs := cuff_target()
	if cs:
		_boot_t = 0.0
		treat_t = 0.0
		cuff_t += delta
		if cuff_t >= CUFF_TIME:
			cuff_t = 0.0
			if Net.is_host():
				cs.cuff(self)
		return
	cuff_t = 0.0
	var at_boot := false
	for c in get_tree().get_nodes_in_group("police_cars"):
		var bp: Vector3 = (c as PoliceCar).boot_point()
		if Vector2(bp.x - global_position.x, bp.z - global_position.z).length() < BOOT_RANGE:
			at_boot = true
	if at_boot:
		treat_t = 0.0
		_boot_t += delta
		if _boot_t >= BOOT_TIME:
			_boot_t = 0.0
			reserve = RESERVE_MAX
			pouch = POUCH_MAX
			injuries = 0
			hp = minf(hp + 25.0, MAX_HP)
		return
	_boot_t = 0.0
	if pouch <= 0:
		treat_t = 0.0
		return
	var target := treat_target()
	if target == null:
		treat_t = 0.0
		return
	treat_t += delta
	if treat_t >= (TREAT_SELF if target == self else TREAT_MATE):
		treat_t = 0.0
		if target.treat_one(HEAL_SELF if target == self else HEAL_MATE) != "":
			pouch -= 1


## A suspect close by who has given up (or whose escort is gone): holding
## interact cuffs them, or takes them over.
func cuff_target() -> Suspect:
	if not is_inside_tree():
		return null
	for n in get_tree().get_nodes_in_group("suspects"):
		var s := n as Suspect
		if s == null or s.global_position.distance_to(global_position) > CUFF_RANGE:
			continue
		if s.state == Suspect.S.SURRENDER and s.part == "":
			return s
		if s.state == Suspect.S.CUFFED and s.escort_peer != peer_id and not _escort_here(s):
			return s
	return null


func _escort_here(s: Suspect) -> bool:
	for n in get_tree().get_nodes_in_group("officers"):
		var o := n as Officer
		if o and o.peer_id == s.escort_peer and o.state not in [S.DOWNED, S.VEHICLE] \
				and o.global_position.distance_to(s.global_position) < 12.0:
			return true
	return false


## The suspect this officer is walking in, if any.
func prisoner() -> Suspect:
	if not is_inside_tree():
		return null
	for n in get_tree().get_nodes_in_group("suspects"):
		var s := n as Suspect
		if s and s.state == Suspect.S.CUFFED and s.escort_peer == peer_id and s.global_position.distance_to(global_position) < 5.0:
			return s
	return null


## Interact at a police car door while walking a prisoner: they go in the
## back (or the front passenger seat if the back is full).
func _try_seat_prisoner() -> bool:
	var pr := prisoner()
	if pr == null:
		return false
	var best: PoliceCar = null
	var best_d := ENTER_RANGE + 0.4
	for c in get_tree().get_nodes_in_group("vehicles"):
		var pc := c as PoliceCar
		for i in pc.doors.size():
			var dp := pc.door_point(i)
			var d := Vector2(dp.x - global_position.x, dp.z - global_position.z).length()
			if d < best_d:
				best_d = d
				best = pc
	if best == null:
		return false
	var taken := best.occupants()
	for s in [2, 3, 1]:
		if s >= best.seats.size():
			continue
		if not taken.has(s):
			if Net.is_host():
				pr.put_in_car(best, s)
			return true
	return false


## Who holding interact would treat: a wounded teammate close by first.
func treat_target() -> Officer:
	for n in get_tree().get_nodes_in_group("officers"):
		var o := n as Officer
		if o and o != self and o.needs_aid() and o.state in [S.MOVE, S.CROUCH, S.COVER, S.PRONE] \
				and o.global_position.distance_to(global_position) < REVIVE_RANGE:
			return o
	return self if needs_aid() else null


func treat_time() -> float:
	var tt := treat_target()
	return TREAT_SELF if tt == self else TREAT_MATE


# --- Vehicles ----------------------------------------------------------------

## Interact next to a police car door: get in that seat, or the nearest
## free one in the car.
func _try_enter_car() -> bool:
	var best: PoliceCar = null
	var best_d := ENTER_RANGE
	var best_door := -1
	for c in get_tree().get_nodes_in_group("vehicles"):
		var pc := c as PoliceCar
		if not pc.can_enter():
			continue
		for i in pc.doors.size():
			var dp := pc.door_point(i)
			var d := Vector2(dp.x - global_position.x, dp.z - global_position.z).length()
			if d < best_d:
				best_d = d
				best = pc
				best_door = i
	if best == null:
		return false
	var taken := best.occupants()
	var s := best_door
	# Whoever gets in first drives, whichever door they used (Phase 1.7: it
	# was too easy to end up a passenger and wonder why WASD did nothing).
	if not taken.has(0) and (best_door in [0, 1] or taken.is_empty()):
		s = 0
	if taken.has(s):
		s = -1
		var dd := INF
		for i in best.seats.size():
			if not taken.has(i):
				var d := best.door_point(i).distance_to(global_position)
				if d < dd:
					dd = d
					s = i
	if s < 0:
		return false
	best.commandeer(self)
	_enter_seat(best, s)
	return true


func _enter_seat(c: PoliceCar, s: int) -> void:
	car = c
	seat = s
	_dash = false
	_boot_t = 0.0
	treat_t = 0.0
	velocity = Vector3.ZERO
	_set_state(S.VEHICLE)
	collision_layer = 0
	collision_mask = 0
	_place_in_seat()


## In a car: sit in the seat as it moves. Interact gets out; the stance key
## (Ctrl / B) shuffles to the next free seat. Passengers aim out of their
## window and can shoot.
func _vehicle_step() -> void:
	if car == null or not is_instance_valid(car):
		_leave_car(true)
		return
	if _pressed(PlayerInput.INTERACT):
		_leave_car()
		return
	if _pressed(PlayerInput.CROUCH) or _pressed(PlayerInput.STAND) or _pressed(PlayerInput.PRONE) or _pressed(PlayerInput.DIVE):
		var taken := car.occupants()
		var n: int = car.seats.size()
		for k in range(1, n):
			var j := (seat + k) % n
			if not taken.has(j):
				seat = j
				break
	_place_in_seat()


func _place_in_seat() -> void:
	if car == null:
		return
	var local: Vector3 = car.seats[seat]
	if is_aiming():
		# Leaning out of the window, sat on the sill.
		local.x += signf(local.x) * 0.42
		local.y += 0.22
	global_position = car.global_transform * local
	var f := car.global_transform.basis.z
	rotation.y = atan2(f.x, f.z)
	velocity = car.linear_velocity


## Out of the car by this seat's door, or the other side's if that is
## blocked. forced: thrown out (downed, car gone) wherever there is room.
func _leave_car(forced := false) -> void:
	var c := car
	var s := seat
	car = null
	seat = -1
	collision_layer = 2
	collision_mask = 1 | 4 | 16
	if c == null or not is_instance_valid(c):
		_set_state(S.MOVE)
		return
	var spot := Vector3.INF
	var nd: int = c.doors.size()
	for d in [s, s ^ 1, (s + 2) % 4, (s + 2) % 4 ^ 1]:
		if d >= nd:
			continue
		var p := c.door_point(d)
		if _room_at(p):
			spot = p
			break
	if spot == Vector3.INF:
		if not forced:
			car = c
			seat = s
			collision_layer = 0
			collision_mask = 0
			return   # boxed in: stay put
		spot = c.global_position + Vector3(0, 1.6, 0)
	global_position = _ground_below(spot)
	velocity = c.linear_velocity * Vector3(0.6, 0, 0.6)
	_set_state(S.MOVE)


func _room_at(p: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.6
	q.shape = cap
	q.transform = Transform3D(Basis(), _ground_below(p) + Vector3(0, 0.85, 0))
	q.collision_mask = 1 | 4 | 16
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _ground_below(p: Vector3) -> Vector3:
	var from := p + Vector3(0, 1.5, 0)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0, 1 | 16, [get_rid()]))
	return (hit.position + Vector3(0, 0.05, 0)) if hit else Vector3(p.x, p.y, p.z)


func in_car() -> bool:
	return state == S.VEHICLE and car != null


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
	var d := _dragger()
	if d:
		# Pulled along by the collar, a step behind whoever has hold.
		var away := Vector3(global_position.x - d.global_position.x, 0.0, global_position.z - d.global_position.z)
		if away.length() > DRAG_LEASH:
			var to := d.global_position + away.normalized() * DRAG_LEASH
			var pull := Vector3(to.x - global_position.x, 0.0, to.z - global_position.z) / maxf(delta, 0.001)
			pull = pull.limit_length(4.0)
			velocity.x = pull.x
			velocity.z = pull.z
	move_and_slide()
	if _reviver() != null:
		revive_t += delta
	else:
		revive_t = maxf(0.0, revive_t - delta)
	if state_t >= RESPAWN_AFTER and _pressed(PlayerInput.RELOAD) and revive_t <= 0.0:
		respawn()
		return
	if revive_t >= REVIVE_TIME or state_t >= SELF_REVIVE:
		hp = 50.0 if revive_t >= REVIVE_TIME else 25.0
		if revive_t >= REVIVE_TIME:
			injuries &= ~BLEED   # the teammate patched the bleeding
		revive_t = 0.0
		_set_state(S.CROUCH)


## Back on your feet where you came into the game, as good as new: full
## health, wounds and pouch seen to, a full magazine and belt, service pistol
## holstered (a picked-up gun is lost).
func respawn() -> void:
	var to := home if home != Vector3.INF else global_position
	# Step aside if a teammate is standing on the spot.
	for n in get_tree().get_nodes_in_group("officers"):
		var o := n as Officer
		if o and o != self and Vector2(o.global_position.x - to.x, o.global_position.z - to.z).length() < 0.8:
			to += Vector3(1.0, 0, 0)
	global_position = to + Vector3(0, 0.05, 0)
	velocity = Vector3.ZERO
	hp = MAX_HP
	injuries = 0
	pouch = POUCH_MAX
	ammo = MAG
	reserve = RESERVE_MAX
	reload_t = 0.0
	revive_t = 0.0
	gun = EnemyGuns.NONE
	gun_ammo = 0
	_shown_gun = -1
	holstered = true
	collision_mask = 1 | 4 | 16
	_set_state(S.MOVE)


var _tag: Label3D

## Over a teammate's head (never your own): their health when they are
## hurt, wounded or down, so you can see who needs first aid.
func _health_tag() -> void:
	var show := peer_id != Net.my_id() and state != S.VEHICLE and (needs_aid() or state == S.DOWNED)
	if not show:
		if _tag:
			_tag.visible = false
		return
	if _tag == null:
		_tag = Label3D.new()
		_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_tag.no_depth_test = true
		_tag.fixed_size = true
		_tag.pixel_size = 0.0012
		_tag.font_size = 26
		_tag.outline_size = 8
		_tag.position = Vector3(0, 2.25, 0)
		add_child(_tag)
	_tag.visible = true
	if state == S.DOWNED:
		_tag.text = "DOWN - hold %s to revive, %s to drag" % [Controls.describe(Controls.pc_event("interact")), Controls.describe(Controls.pc_event("drag"))]
		_tag.modulate = Color(1.0, 0.35, 0.3)
	else:
		var w := injury_names(injuries)
		_tag.text = "+ %d%%%s" % [roundi(hp), ("  " + " ".join(w)) if not w.is_empty() else ""]
		_tag.modulate = Color(1.0, 0.45, 0.4) if hp < 40.0 or not w.is_empty() else Color(1.0, 0.85, 0.45)


## Seconds until R respawns (0 once it can).
func respawn_wait() -> float:
	return maxf(RESPAWN_AFTER - state_t, 0.0) if state == S.DOWNED else 0.0


## A teammate close by, up, and holding interact.
func _reviver() -> Officer:
	for n in get_tree().get_nodes_in_group("officers"):
		var o := n as Officer
		if o and o != self and o.state in [S.MOVE, S.CROUCH] and (o.buttons & PlayerInput.INTERACT) != 0 \
				and o.global_position.distance_to(global_position) < REVIVE_RANGE:
			return o
	return null


## The downed teammate this officer has by the collar (holding drag, up,
## and close enough), or null.
func drag_target() -> Officer:
	if state not in [S.MOVE, S.CROUCH] or (buttons & PlayerInput.DRAG) == 0 or not is_inside_tree():
		return null
	var best: Officer = null
	var best_d := DRAG_RANGE
	for n in get_tree().get_nodes_in_group("officers"):
		var o := n as Officer
		if o and o != self and o.state == S.DOWNED:
			var dd := o.global_position.distance_to(global_position)
			if dd < best_d:
				best = o
				best_d = dd
	return best


## Who is dragging this downed officer, or null.
func _dragger() -> Officer:
	for n in get_tree().get_nodes_in_group("officers"):
		var o := n as Officer
		if o and o != self and o.drag_target() == self:
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


## Host only: refill the belt (an ammo box). Returns true if any was taken.
func refill_ammo() -> bool:
	if not Net.is_host() or reserve >= RESERVE_MAX:
		return false
	reserve = RESERVE_MAX
	return true


## Draw, holster and reload.
func _weapon(delta: float) -> void:
	if holster_t > 0.0:
		holster_t = maxf(holster_t - delta, 0.0)
		if holster_t <= 0.0 and not drawing:
			holstered = true
	# On a controller, Y both holsters and drags: next to a downed teammate
	# it drags.
	var hol := _pressed(PlayerInput.HOLSTER) and drag_target() == null
	var draw_now := holstered and (hol or _pressed(PlayerInput.AIM))
	if draw_now:
		holstered = false   # aiming draws the gun too
		drawing = true
		holster_t = HOLSTER_TIME
	elif hol and holster_t <= 0.0 and gun != EnemyGuns.NONE:
		_drop_gun()   # H with a picked-up gun drops it
	elif hol and holster_t <= 0.0:
		drawing = false
		holster_t = HOLSTER_TIME
		reload_t = 0.0
	if _pressed(PlayerInput.RELOAD) and gun == EnemyGuns.NONE and gun_up() and holster_t <= 0.0 and ammo < MAG and reserve > 0 and reload_t <= 0.0:
		reload_t = RELOAD_TIME
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			reload_t = 0.0
			var take := mini(MAG - ammo, reserve)
			ammo += take
			reserve -= take


## Bullets go where you point, give or take: steady aimed shots are tight,
## rapid fire opens up, blind fire from cover is wild.
func _spread(dir: Vector3, blind: bool) -> Vector3:
	var deg := 0.4 + bloom * 1.2 + (9.0 if blind else 0.0) + (2.2 if injuries & ARM else 0.0)
	if state == S.VEHICLE:
		deg += 1.0 + car.linear_velocity.length() * 0.08 if car else 1.0
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
		return xf.origin - xf.basis.y.normalized() * float(EnemyGuns.MUZZLE[gun])
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


## Snaps into cover against the nearest wall, car or rubble within reach,
## any way round (ahead and the way the stick points count first).
func _try_cover(wish := Vector3.ZERO) -> void:
	var dirs: Array = []
	if wish.length() > 0.3:
		dirs.append(wish.normalized())
	dirs.append(Vector3(sin(rotation.y), 0, cos(rotation.y)))
	for i in 16:
		var a := TAU * i / 16.0
		dirs.append(Vector3(sin(a), 0, cos(a)))
	var best := {}
	var best_d := INF
	for k in dirs.size():
		var hit := _cover_ray(global_position, dirs[k], COVER_SNAP)
		if hit.is_empty():
			continue
		var d := Vector2(hit.position.x - global_position.x, hit.position.z - global_position.z).length()
		if k < dirs.size() - 16:
			d -= 0.3   # prefer the cover you are facing or heading for
		if d < best_d:
			best_d = d
			best = hit
	if not best.is_empty():
		_enter_cover(best.position, best.normal)


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
	var p := Vector3(at.x, global_position.y, at.z) + n * COVER_GAP
	# At the end of a wall, shuffle in so the whole body is behind it.
	var along := Vector3(-n.z, 0, n.x)
	for side in [-1.0, 1.0]:
		var reach := _wall_reach(p, along * side)
		if reach < BODY_HALF:
			p -= along * side * (BODY_HALF - reach)
	global_position = p
	_cover_anchor = p
	rotation.y = atan2(n.x, n.z)   # back to the wall
	velocity = Vector3.ZERO
	_cover_lost_t = 0
	_cover_armed = false
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
	var spot := _cover_anchor + _cover_n * COVER_GAP
	var to := spot - global_position
	to.y = 0.0
	if to.length() < 0.25:
		_enter_cover(_cover_anchor, _cover_n)
		return Vector3.ZERO
	return to.normalized()


## The wall behind the cover spot is no longer there (broken or knocked over).
func _cover_gone() -> bool:
	var h := 0.6 if _cover_low else 1.0
	var o := _cover_anchor + Vector3(0, h, 0)
	if _solid_ray(o, o - _cover_n * (COVER_GAP + 0.5), COVER_MASK).is_empty():
		_cover_lost_t += 1
	else:
		_cover_lost_t = 0
	return _cover_lost_t > 6


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


## Which way the officer leans out round the end of a tall wall while
## aiming from cover (world direction along the wall), or zero.
func peek_dir() -> Vector3:
	if state != S.COVER or _cover_low or not is_aiming():
		return Vector3.ZERO
	var along := Vector3(-_cover_n.z, 0, _cover_n.x)
	for side in [-1.0, 1.0]:
		if _wall_reach(_cover_anchor, along * side) < BODY_HALF + 0.15:
			return along * side
	return Vector3.ZERO


## Movement while in cover: slide along the wall but not past its end. Aiming
## peeks: over a low wall by standing up, round the end of a tall wall by
## leaning out, and back in again when the aim is let go.
func _cover_wish(wish: Vector3) -> Vector3:
	var along := Vector3(-_cover_n.z, 0, _cover_n.x)
	var here := global_position
	if is_aiming():
		if _cover_low:
			return Vector3.ZERO
		# Feet stay put at the end of the wall (a small side step at most)
		# and the body leans out round it (the rig does the lean).
		var target := _cover_anchor + peek_dir() * PEEK_OUT
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
	b.put_u32(buttons)
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
	b.put_u8((1 if _cover_low else 0) | (2 if _dash else 0) | (4 if _cover_armed else 0))
	b.put_u8(ammo | (128 if holstered else 0))
	b.put_u8(reserve)
	b.put_half(reload_t)
	b.put_half(holster_t * (-1.0 if drawing else 1.0))
	b.put_half(_cooldown)
	b.put_half(bloom)
	b.put_u8(int(hp))
	b.put_half(revive_t)
	b.put_u8(1 if barging else 0)
	b.put_half(stagger_t)
	b.put_8(car.net_id if car else -1)
	b.put_u8(seat + 1)
	b.put_u8(injuries | (pouch << 4))
	b.put_half(treat_t)
	b.put_half(_boot_t)
	b.put_half(cuff_t)
	b.put_u8(gun)
	b.put_u8(gun_ammo)


func decode_state(b: StreamPeerBuffer) -> Dictionary:
	return {
		"pos": Vector3(b.get_float(), b.get_float(), b.get_float()),
		"vel": Vector3(b.get_half(), b.get_half(), b.get_half()),
		"yaw": b.get_half(), "aim": b.get_half(), "state": b.get_u8(), "st": b.get_half(),
		"buttons": b.get_u32(), "punch": b.get_half(),
		"ms": Vector3(b.get_float(), b.get_float(), b.get_float()), "my": b.get_half(), "mr": b.get_half(),
		"cn": Vector3(b.get_half(), 0.0, b.get_half()), "ca": Vector3(b.get_float(), b.get_float(), b.get_float()),
		"cl": b.get_u8(),
		"ammo": b.get_u8(), "rs": b.get_u8(), "rl": b.get_half(), "ht": b.get_half(), "cd": b.get_half(), "bl": b.get_half(),
		"hp": b.get_u8(), "rv": b.get_half(), "bg": b.get_u8() == 1, "sg": b.get_half(),
		"car": b.get_8(), "seat": b.get_u8() - 1, "inj": b.get_u8(), "tr": b.get_half(), "bt": b.get_half(), "cf": b.get_half(),
		"gn": b.get_u8(), "ga": b.get_u8(),
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
	_cover_armed = (s.cl & 4) != 0
	ammo = s.ammo & 127
	holstered = (s.ammo & 128) != 0
	reserve = s.rs
	gun = s.gn
	gun_ammo = s.ga
	reload_t = s.rl
	holster_t = absf(s.ht)
	drawing = s.ht < 0.0
	_cooldown = s.cd
	bloom = s.bl
	hp = s.hp
	revive_t = s.rv
	barging = s.bg
	stagger_t = s.sg
	injuries = s.inj & 15
	pouch = s.inj >> 4
	treat_t = s.tr
	_boot_t = s.bt
	cuff_t = s.cf
	seat = s.seat
	car = null
	if s.car >= 0 and is_inside_tree():
		for c in get_tree().get_nodes_in_group("vehicles"):
			if c.net_id == s.car:
				car = c
	collision_mask = 0 if state in [S.VAULT, S.CLIMB, S.VEHICLE] else (1 | 4 | 16)
	collision_layer = 0 if state == S.VEHICLE else 2


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
	_health_tag()
	if rig and rig.tree:
		if rig.downed != (state == S.DOWNED):
			rig.set_downed(state == S.DOWNED)
		if state == S.VEHICLE and car:
			_place_in_seat()   # stay in the seat between ticks (and on remote copies)
			car.set_window_down(car.seat_windows[seat], is_aiming())
		rig.update_from(self, delta)
		if _shown_gun != gun:
			_shown_gun = gun
			EnemyGuns.show_in_hand(rig.model, EnemyGuns.PISTOL if gun == EnemyGuns.NONE else gun)
		var show := gun_in_hand() and state not in [S.ROLL, S.VAULT, S.CLIMB, S.SLIDE, S.KICK, S.DOWNED] and not (state == S.VEHICLE and seat == 0)
		var hand := rig.model.find_child("gun_slide", true, false) as Node3D
		if hand and hand.get_parent():
			(hand.get_parent() as Node3D).visible = true
			for g in hand.get_parent().get_children():
				if g is Node3D and (g.name.begins_with("gun_") or g.name == "shotgun"):
					var right: bool = (g.name == "shotgun") == (gun == EnemyGuns.SHOTGUN)
					(g as Node3D).visible = show and right
		_update_torch()


## The torch: a beam from the chest along the aim, on while the player has it
## switched on (a synced button), so everyone sees it.
func _update_torch() -> void:
	var on := (buttons & PlayerInput.TORCH) != 0 and not holstered and state != S.VEHICLE
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
