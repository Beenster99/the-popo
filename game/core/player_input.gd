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
	if cam and from:
		var p := cam.mouse_on_plane(from.global_position.y)
		var d := p - from.global_position
		aim_yaw = atan2(d.x, d.z)
	return {"move": Vector2(world.x, world.z), "buttons": buttons, "aim_yaw": aim_yaw}
