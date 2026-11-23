class_name Charge
extends Node3D
## Phase 3.6: a breach charge or a block of C4, stuck where an officer
## aimed. It blinks and beeps faster and faster, then goes off. The host
## sets it off; everyone sees the blast (Blast syncs it). The host tells
## the clients where it is so they see and hear it blink (MSG_CHARGE).

const MSG_CHARGE := 105   # host -> all: a charge placed (pos, big, fuse)

var world: DestructionWorld
var cars: CarSync
var blast: Dictionary
var big := false
var cosmetic := false
var _t := 0.0
var _beep_t := 0.0
var _light: OmniLight3D
var _lamp: MeshInstance3D


static func place(tree: SceneTree, parent: Node, w: DestructionWorld, c: CarSync, at: Vector3, b: Dictionary, is_c4: bool) -> Charge:
	var ch := Charge.new()
	ch.world = w
	ch.cars = c
	ch.blast = b
	ch.big = is_c4
	parent.add_child(ch)
	ch.global_position = at
	if Net.is_host() and Net.is_online():
		var buf := StreamPeerBuffer.new()
		for v in [at.x, at.y, at.z, float(b.get("fuse", 2.5))]:
			buf.put_float(v)
		buf.put_u8(1 if is_c4 else 0)
		Net.broadcast(MSG_CHARGE, buf.data_array)
	return ch


## Client: the host placed one (cosmetic here: the host sets it off).
static func on_placed(parent: Node, data: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var at := Vector3(b.get_float(), b.get_float(), b.get_float())
	var fuse := b.get_float()
	var ch := Charge.new()
	ch.blast = {"fuse": fuse}
	ch.big = b.get_u8() == 1
	ch.cosmetic = true
	parent.add_child(ch)
	ch.global_position = at


func _ready() -> void:
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.28, 0.12, 0.18) if big else Vector3(0.16, 0.08, 0.1)
	body.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("c9b98c") if big else Color("3a3a3a")
	body.material_override = mat
	add_child(body)
	_lamp = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.025
	sm.height = 0.05
	_lamp.mesh = sm
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(1, 0.1, 0.05)
	_lamp.material_override = lm
	_lamp.position = Vector3(0, 0.08, 0)
	add_child(_lamp)
	_light = OmniLight3D.new()
	_light.light_color = Color(1, 0.15, 0.1)
	_light.omni_range = 2.0
	_light.light_energy = 0.0
	add_child(_light)
	Sfx.play(get_parent(), "holster", global_position, -4.0, 14.0, 0.05)


func _physics_process(delta: float) -> void:
	_t += delta
	var fuse: float = blast.get("fuse", 2.5)
	var left := fuse - _t
	_beep_t -= delta
	if _beep_t <= 0.0:
		_beep_t = clampf(left * 0.25, 0.08, 0.5)
		_light.light_energy = 2.5
		_lamp.visible = true
		Sfx.play(get_parent(), "ping", global_position, -14.0, 20.0, 0.0)
	else:
		_light.light_energy = maxf(0.0, _light.light_energy - delta * 20.0)
		_lamp.visible = _light.light_energy > 0.5
	if left <= 0.0 and cosmetic:
		queue_free()
	elif left <= 0.0:
		Blast.go(get_tree(), world, cars, global_position, blast.radius, blast.damage, blast.strength)
		queue_free()
