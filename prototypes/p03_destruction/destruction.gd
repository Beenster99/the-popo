extends Node3D
## Phase 0.3: destruction spike. Two shops built from pre-fractured kit
## pieces. 1 = pistol (chips walls, pushes rubble), 2 = demolition charge
## (thrown at what you aim at). Knock out a ground-floor side wall and the
## floor above loses support and falls. Host simulates; big chunks are synced.

const COLORS := [Color("2c4a8c"), Color("8c2c3c"), Color("2c8c5a")]

var sync: PawnSync
var cam: IsoCamera
var world: DestructionWorld


func _ready() -> void:
	ProtoWorld.environment(self)
	ProtoWorld.sun(self)
	ProtoWorld.ground(self, 80.0, Color("6d7276"))
	cam = IsoCamera.new()
	cam.zoom = 22.0
	add_child(cam)

	sync = PawnSync.new()
	sync.pawn_parent = self
	sync.pawn_factory = func(id):
		var p := CapsuleOfficer.new()
		p.peer_id = id
		var idx: int = max(Net.player_ids().find(id), 0)
		p.color = COLORS[idx % 3]
		p.position = Vector3(-2 + idx * 2, 0.1, 10)
		if Net.is_host():
			p.fired.connect(_on_fired)
		return p
	sync.input_source = func(): return PlayerInput.sample(cam, sync.my_pawn())
	sync.pawn_spawned.connect(func(id, p): if id == Net.my_id(): cam.target = p)

	world = DestructionWorld.new()
	world.sync = sync
	add_child(world)
	add_child(sync)
	BuildingLayout.shop(world, Vector3(-10, 0, -4))
	BuildingLayout.shop(world, Vector3(3, 0, -4))
	world.finalize()

	var overlay := NetOverlay.new()
	overlay.extra_lines = func():
		return "synced awake chunks %d (%d B per snapshot)   chunks %d\n1 pistol  2 charge  [%s]   LMB fire, aim with the mouse" % [
			world.synced_awake, world.bytes_per_snapshot, world.chunk_count, "charge" if PlayerInput.alt_tool else "pistol"]
	add_child(overlay)


func _on_fired(origin: Vector3, dir: Vector3, alt: bool) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 40.0, 1 | 16)
	var hit := space.intersect_ray(q)
	if alt:
		var at: Vector3 = hit.position if hit else origin + dir * 8.0
		world.explode(at, 3.5, 200.0, 9.0)
	elif hit:
		world.bullet_hit(hit.collider, hit.position, hit.normal, dir)
