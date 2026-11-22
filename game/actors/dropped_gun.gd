class_name DroppedGun
extends Node3D
## Phase 1.5: a gun on the floor where a suspect dropped it (giving up,
## cuffed or down). An officer presses use next to it to pick it up and gets
## only the rounds still in it. The Dispatcher owns these and syncs them.

const PICK_RANGE := 1.4

var net_id := 0
var kind := EnemyGuns.PISTOL
var rounds := 0


func _ready() -> void:
	add_to_group("dropped_guns")
	add_to_group(RoofFader.CUTAWAY_GROUP)
	var model: Node3D
	if kind == EnemyGuns.SHOTGUN:
		model = EnemyGuns.make_shotgun()
	else:
		model = Node3D.new()
		var metal := Cel.material(Color("26282c"), true, 0.012)
		EnemyGuns._box(model, Vector3(0.03, 0.19, 0.05), Vector3(0, 0, 0), metal)
		EnemyGuns._box(model, Vector3(0.028, 0.04, 0.10), Vector3(0, 0.07, 0.06), metal)
	# Lie it flat on its side, barrel along a random-ish heading.
	model.rotation = Vector3(0, 0, PI * 0.5)
	model.position.y = 0.03
	add_child(model)
	rotation.y = float(net_id * 1.7)


## Drops to the floor under p (static world only).
func settle(space: PhysicsDirectSpaceState3D, p: Vector3) -> void:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.6, 0), p - Vector3(0, 2.0, 0), 1)
	var hit := space.intersect_ray(q)
	global_position = hit.position if hit else p
