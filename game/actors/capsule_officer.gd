class_name CapsuleOfficer
extends CharacterBody3D
## Phase 0.2 stand-in officer: a capsule with a facing marker. Moves the same
## way on host and client so prediction lines up.

const WALK := 4.5
const SPRINT := 7.5
const ACCEL := 40.0
const JUMP_V := 5.0
const GRAVITY := 18.0

var peer_id := 1
var color := Color("2c4a8c")
var _visual: Node3D
var _label: Label3D


func _init() -> void:
	collision_layer = 2
	collision_mask = 1 | 4 | 16


func _ready() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	_visual = Node3D.new()
	add_child(_visual)
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = 1.8
	mi.mesh = cm
	mi.position.y = 0.9
	mi.material_override = Cel.material(color)
	_visual.add_child(mi)
	var nose := MeshInstance3D.new()
	var nb := BoxMesh.new()
	nb.size = Vector3(0.2, 0.15, 0.35)
	nose.mesh = nb
	nose.position = Vector3(0, 1.45, 0.35)
	nose.material_override = Cel.material(Color("e8c547"))
	_visual.add_child(nose)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 2.3
	_label.font_size = 48
	_label.outline_size = 12
	_label.no_depth_test = true
	for s in Net.slots:
		if s.id == peer_id:
			_label.text = s.name
	add_child(_label)


func sim_step(cmd: Dictionary, delta: float) -> void:
	var move: Vector2 = cmd.get("move", Vector2.ZERO)
	var buttons: int = cmd.get("buttons", 0)
	var speed := SPRINT if buttons & PlayerInput.SPRINT else WALK
	var target := Vector3(move.x, 0, move.y) * speed
	var h := Vector3(velocity.x, 0, velocity.z).move_toward(target, ACCEL * delta)
	velocity.x = h.x
	velocity.z = h.z
	if is_on_floor():
		if buttons & PlayerInput.JUMP:
			velocity.y = JUMP_V
	else:
		velocity.y -= GRAVITY * delta
	if move.length() > 0.1:
		rotation.y = atan2(move.x, move.y)
	if buttons & PlayerInput.AIM:
		rotation.y = cmd.get("aim_yaw", rotation.y)
	move_and_slide()


func encode_state(b: StreamPeerBuffer) -> void:
	b.put_float(global_position.x)
	b.put_float(global_position.y)
	b.put_float(global_position.z)
	b.put_half(velocity.x)
	b.put_half(velocity.y)
	b.put_half(velocity.z)
	b.put_half(rotation.y)


func decode_state(b: StreamPeerBuffer) -> Dictionary:
	return {
		"pos": Vector3(b.get_float(), b.get_float(), b.get_float()),
		"vel": Vector3(b.get_half(), b.get_half(), b.get_half()),
		"yaw": b.get_half(),
	}


func apply_state(s: Dictionary) -> void:
	global_position = s.pos
	velocity = s.vel
	rotation.y = s.yaw


func blend_state(a: Dictionary, c: Dictionary, t: float) -> Dictionary:
	return {"pos": a.pos.lerp(c.pos, t), "vel": a.vel.lerp(c.vel, t), "yaw": lerp_angle(a.yaw, c.yaw, t)}


func set_visual_offset(v: Vector3) -> void:
	if _visual:
		_visual.position = v
