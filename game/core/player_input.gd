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

static var alt_tool := false
## Where the local player is aiming, for the reticle.
static var aim_point := Vector3.ZERO
static var aim_normal := Vector3.UP
static var aim_on_surface := false
static var using_pad := false
const CHEST := 1.3
const PAD_AIM_RANGE := 10.0

const _MAP := {
	"sprint": SPRINT, "jump": JUMP, "crouch": CROUCH, "prone": PRONE, "dive": DIVE,
	"cover": COVER, "punch": PUNCH, "kick": KICK, "aim": AIM, "fire": FIRE, "interact": INTERACT,
}


## cam: the IsoCamera (movement is relative to the view).
## from: the pawn, for the aim direction toward the mouse.
static func sample(cam: IsoCamera, from: Node3D) -> Dictionary:
	var raw := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var world := cam.view_relative(raw) if cam else Vector3(raw.x, 0, raw.y)
	var buttons := 0
	for a in _MAP:
		if Input.is_action_pressed(a):
			buttons |= _MAP[a]
	if Input.is_action_just_pressed("weapon_1"):
		alt_tool = false
	elif Input.is_action_just_pressed("weapon_2"):
		alt_tool = true
	if alt_tool:
		buttons |= ALT_TOOL
	var aim_yaw := 0.0
	var point := Vector3.ZERO
	if cam and from:
		var chest := from.global_position + Vector3(0, CHEST, 0)
		var exclude: Array[RID] = []
		if from is CollisionObject3D:
			exclude.append((from as CollisionObject3D).get_rid())
		var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down", 0.25)
		if stick.length() > 0.0:
			using_pad = true
		elif Input.get_last_mouse_velocity().length() > 50.0:
			using_pad = false
		if using_pad:
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
