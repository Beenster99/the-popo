class_name EnemyGuns
extends RefCounted
## Phase 1.5: the guns criminals carry. Officers can pick one up off the
## floor, but they only get the rounds still loaded in it: there is no spare
## ammo for these, and R does nothing. Once it is empty (or H is pressed)
## the officer drops it and goes back to the service pistol.

enum { NONE, PISTOL, SHOTGUN }

const NAMES := ["Service pistol", "Street pistol", "Sawn-off pump"]
const MAG := [15, 12, 5]
const DAMAGE := [25.0, 22.0, 13.0]   # per bullet or pellet
const GAP := [0.18, 0.22, 0.85]      # s between shots
const PELLETS := [1, 1, 7]
const SPREAD_DEG := [0.0, 0.6, 4.5]  # extra spread on top of the shooter's own
const RELOAD := [1.7, 1.9, 3.0]      # s (enemies only, apart from the service pistol)
## How far the muzzle is in front of the gun_slide node, along its -Y.
const MUZZLE := [0.095, 0.095, 0.42]


## Directions for one trigger pull: pellets fan out round dir.
static func pellet_dirs(kind: int, dir: Vector3, rng: RandomNumberGenerator) -> Array:
	var out := []
	var n: int = PELLETS[kind]
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(dir).normalized()
	for i in n:
		if n == 1 and SPREAD_DEG[kind] <= 0.0:
			out.append(dir)
			continue
		var r := deg_to_rad(SPREAD_DEG[kind]) * sqrt(rng.randf())
		var a := rng.randf() * TAU
		out.append((dir + side * tan(r) * cos(a) + up * tan(r) * sin(a)).normalized())
	return out


## The sawn-off: a short pump shotgun made from boxes, held where the pistol
## is (child of the hand attachment, laid along the pistol slide's frame).
static func make_shotgun() -> Node3D:
	var root := Node3D.new()
	root.name = "shotgun"
	var metal := Cel.material(Color("2b2d31"), true, 0.012)
	var wood := Cel.material(Color("6b4a2e"), true, 0.012)
	# Along -Y is forward (the slide's frame), +Z is down under the barrel.
	_box(root, Vector3(0.022, 0.40, 0.022), Vector3(0, -0.16, 0.0), metal)       # barrel
	_box(root, Vector3(0.020, 0.30, 0.018), Vector3(0, -0.13, 0.026), metal)     # magazine tube
	_box(root, Vector3(0.034, 0.12, 0.036), Vector3(0, -0.20, 0.026), wood)      # pump
	_box(root, Vector3(0.036, 0.13, 0.05), Vector3(0, 0.04, 0.012), metal)       # receiver
	_box(root, Vector3(0.03, 0.09, 0.03), Vector3(0, 0.12, 0.05), wood)          # pistol grip stub
	return root


static func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = at
	m.material_override = mat
	parent.add_child(m)


## Shows the right gun in a character's hand: the pistol model's own parts,
## or the shotgun laid where the slide is. kind NONE hides everything
## (officers pass PISTOL for their service pistol: it is the same model).
static func show_in_hand(model: Node, kind: int) -> void:
	if model == null:
		return
	var slide := model.find_child("gun_slide", true, false) as Node3D
	var grip := model.find_child("gun_grip", true, false) as Node3D
	var pistol := kind == PISTOL
	if slide:
		slide.visible = pistol
	if grip:
		grip.visible = pistol
	var sg: Node3D = null
	if slide and slide.get_parent():
		sg = slide.get_parent().get_node_or_null("shotgun") as Node3D
		if sg == null and kind == SHOTGUN:
			sg = make_shotgun()
			slide.get_parent().add_child(sg)
			sg.transform = slide.transform
	if sg:
		sg.visible = kind == SHOTGUN
