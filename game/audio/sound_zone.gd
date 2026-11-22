class_name SoundZone
extends Node3D
## A box of space that sounds indoors: shots and hits inside it go through
## the Indoor reverb bus and lose the outdoor echo tail.

const GROUP := "sound_zone"
@export var size := Vector3(4, 3, 4)


func _enter_tree() -> void:
	add_to_group(GROUP)


func contains(world_pos: Vector3) -> bool:
	var p := global_transform.affine_inverse() * world_pos
	return absf(p.x) <= size.x * 0.5 and absf(p.y) <= size.y * 0.5 and absf(p.z) <= size.z * 0.5
