class_name PlayerInput
extends RefCounted
## Samples mouse and keyboard into a network input command.

const SPRINT := 1
const JUMP := 2
const CROUCH := 4
const PRONE := 8
const DIVE := 16
const COVER := 32
const PUNCH := 64
const KICK := 128
const AIM := 256
const FIRE := 512
const INTERACT := 1024
const ALT_TOOL := 2048  # weapon slot 2 (demolition charge in the destruction spike)
const STAND := 4096    # stand up from crouch or prone
const RELOAD := 8192
const HOLSTER := 16384
const TORCH := 32768   # a state, not a press: the torch is switched on
const DRAG := 65536    # held: drag a downed teammate by the collar
const SHOUT := 131072  # "Police! Get down!"
const THROW := 262144  # throw a grenade
## Which grenade is picked (Grenades.Kind 0-2), in two bits from here.
const NADE_SHIFT := 19
static var nade_kind := 0
static var torch_on := false

## The stance key (Ctrl): tap to crouch or stand back up, hold to lie prone,
## hold while running to roll (slide when sprinting). It is turned into the
## one-tick CROUCH / PRONE / DIVE / STAND presses the officer already knows.
const STANCE_HOLD := 0.3        # s held before a hold counts as prone
const STANCE_DIVE_HOLD := 0.12  # s held while running before rolling
const RUNNING_SPEED := 2.5      # m/s
static var _stance_down_at := -1.0
static var _stance_used := false

static var alt_tool := false
## Walk mode (Alt, or tap L3 on a controller): moves at a walk instead of a
## run, with the mocap walk (tactical with the gun out, relaxed holstered).
## Sprint still runs while held. A controller also walks by tilting the
## stick part of the way.
static var walk_on := false
const WALK_SPEED := 1.3         # m/s, a steady patrol pace
## Tapping L3 (shorter than this) switches walk mode; holding it sprints.
const PAD_WALK_TAP := 0.25
static var _l3_down_at := -1.0
## Where the local player is aiming, for the reticle.
static var aim_point := Vector3.ZERO
static var aim_normal := Vector3.UP
static var aim_on_surface := false
static var using_pad := false
## A menu is open over the game (pause menu, settings): the player stands still.
static var blocked := false
const CHEST := 1.3
const PAD_AIM_RANGE := 10.0

const _MAP := {
	"sprint": SPRINT, "jump": JUMP, "crouch": CROUCH, "prone": PRONE, "dive": DIVE,
	"cover": COVER, "punch": PUNCH, "kick": KICK, "aim": AIM, "fire": FIRE, "interact": INTERACT,
	"reload": RELOAD, "holster": HOLSTER, "drag": DRAG, "shout": SHOUT,
}


## cam: the IsoCamera (movement is relative to the view).
## from: the pawn, for the aim direction toward the mouse.
static func sample(cam: IsoCamera, from: Node3D) -> Dictionary:
	if blocked:
		var tb := TORCH if torch_on else 0
		var yaw := from.rotation.y if from else 0.0
		return {"move": Vector2.ZERO, "buttons": tb, "aim_yaw": yaw, "aim_point": Vector3.ZERO}
	var raw := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var world := cam.view_relative(raw) if cam else Vector3(raw.x, 0, raw.y)
	if InputMap.has_action("walk") and Input.is_action_just_pressed("walk"):
		walk_on = not walk_on
	if pad_walk_tap(_any_pad_l3(), Time.get_ticks_msec() / 1000.0):
		walk_on = not walk_on
	if walk_on and not Input.is_action_pressed("sprint"):
		world = world.limit_length(WALK_SPEED / Officer.RUN)
	var buttons := 0
	for a in _MAP:
		if Input.is_action_pressed(a):
			buttons |= _MAP[a]
	buttons |= stance_buttons(Input.is_action_pressed("stance"), Time.get_ticks_msec() / 1000.0, from)
	if Input.is_action_just_pressed("torch"):
		torch_on = not torch_on
	if torch_on:
		buttons |= TORCH
	if Input.is_action_just_pressed("weapon_1"):
		alt_tool = false
	elif Input.is_action_just_pressed("weapon_2"):
		alt_tool = true
	if alt_tool:
		buttons |= ALT_TOOL
	if Input.is_action_just_pressed("grenade_next"):
		nade_kind = (nade_kind + 1) % 3
	if Input.is_action_pressed("throw"):
		buttons |= THROW
	buttons |= nade_kind << NADE_SHIFT
	var aim_yaw := 0.0
	var point := Vector3.ZERO
	if cam and from:
		var chest := from.global_position + Vector3(0, CHEST, 0)
		var exclude: Array[RID] = []
		if from is CollisionObject3D:
			exclude.append((from as CollisionObject3D).get_rid())
		var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down", float(Settings.values.get("pad_deadzone", 0.25)))
		if stick.length() > 0.0:
			using_pad = true
		elif Input.get_last_mouse_velocity().length() > 50.0:
			using_pad = false
		if using_pad and not IsoCamera.third_person:
			# Right stick: aim along the stick, reticle on the first thing hit.
			var d := cam.view_relative(stick.normalized()) if stick.length() > 0.0 else Vector3(sin(from.rotation.y), 0, cos(from.rotation.y))
			var q := PhysicsRayQueryParameters3D.create(chest, chest + d * PAD_AIM_RANGE, 1 | 4 | 16, exclude)
			var hit := from.get_world_3d().direct_space_state.intersect_ray(q)
			aim_on_surface = not hit.is_empty()
			aim_point = hit.position if hit else chest + d * PAD_AIM_RANGE
			aim_normal = hit.normal if hit else -d
		else:
			var r := cam.mouse_on_world(chest.y, exclude)
			aim_point = r.point
			aim_normal = r.normal
			aim_on_surface = r.hit
		point = aim_point
		var d2 := point - from.global_position
		aim_yaw = atan2(d2.x, d2.z)
	return {"move": Vector2(world.x, world.z), "buttons": buttons, "aim_yaw": aim_yaw, "aim_point": point}


## L3 on a controller: a quick tap switches walk mode (a hold is sprint).
## Returns true on the tap's release.
static func pad_walk_tap(held: bool, now: float) -> bool:
	if held:
		if _l3_down_at < 0.0:
			_l3_down_at = now
		return false
	if _l3_down_at < 0.0:
		return false
	var tap := now - _l3_down_at < PAD_WALK_TAP
	_l3_down_at = -1.0
	return tap


static func _any_pad_l3() -> bool:
	for dev in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_LEFT_STICK):
			return true
	return false


## Turns the stance key into officer presses. held: the key is down now;
## now: seconds; pawn: the local officer (for its stance and speed).
static func stance_buttons(held: bool, now: float, pawn: Node3D) -> int:
	var st := -1
	var speed := 0.0
	if pawn is Officer:
		st = (pawn as Officer).state
		speed = Vector2(pawn.velocity.x, pawn.velocity.z).length()
	if held and _stance_down_at < 0.0:
		_stance_down_at = now
		_stance_used = false
	if held:
		var t := now - _stance_down_at
		if not _stance_used:
			if speed > RUNNING_SPEED and st == Officer.S.MOVE and t >= STANCE_DIVE_HOLD:
				_stance_used = true
				return DIVE
			if t >= STANCE_HOLD:
				_stance_used = true
				return PRONE if st != Officer.S.PRONE else 0
		return 0
	if _stance_down_at >= 0.0:
		_stance_down_at = -1.0
		if not _stance_used:
			return STAND if st in [Officer.S.CROUCH, Officer.S.PRONE, Officer.S.COVER] else CROUCH
	return 0
