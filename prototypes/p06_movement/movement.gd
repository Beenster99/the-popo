extends Node3D
## Phase 0.6 movement course: run, vault, climb, slide, roll, crawl and take
## cover through an obstacle course with the Blender officer (mocap base plus
## hand-keyed clips). Uneven steps and rubble test foot placement. Targets to
## shoot. J: take a hit (partial ragdoll), K: go down (full ragdoll) / get up.

var cam: IsoCamera
var sync: PawnSync
var _hud: Label


func _ready() -> void:
	ProtoWorld.environment(self)
	ProtoWorld.sun(self)
	ProtoWorld.ground(self, 120.0, Color("6f7a6a"))
	var conc := Color("a9a49a")
	var brick := Color("8a4a36")
	# Lane 1: low walls to vault, then a step up onto a platform.
	for i in 3:
		ProtoWorld.block(self, Vector3(3.0, 1.0, 0.3), Vector3(-6, 0.5, 4 + i * 4.0), conc, "VaultWall")
	ProtoWorld.block(self, Vector3(3.0, 1.0, 4.0), Vector3(-6, 0.5, 18.0), conc, "Platform")
	# Lane 2: climbable walls (1.6 m, 2.0 m, 2.3 m) with a deck behind each.
	for i in 3:
		var hgt: float = [1.6, 2.0, 2.3][i]
		ProtoWorld.block(self, Vector3(3.0, hgt, 3.0), Vector3(0, hgt * 0.5, 6 + i * 6.0), brick, "ClimbBlock")
	# Lane 3: long run for sprint and slide under a bar; roll mat.
	ProtoWorld.block(self, Vector3(3.0, 0.2, 0.2), Vector3(6, 1.05, 10), Color("ffcc33"), "SlideBar")
	ProtoWorld.block(self, Vector3(0.2, 1.15, 0.2), Vector3(4.4, 0.575, 10), Color("333333"), "BarPost")
	ProtoWorld.block(self, Vector3(0.2, 1.15, 0.2), Vector3(7.6, 0.575, 10), Color("333333"), "BarPost")
	ProtoWorld.block(self, Vector3(3.0, 0.05, 6.0), Vector3(6, 0.025, 18), Color("4a6fa5"), "RollMat", false)
	# Lane 4: uneven steps and scattered rubble for foot placement.
	for i in 6:
		ProtoWorld.block(self, Vector3(3.0, 0.18 * (i + 1), 1.0), Vector3(12, 0.09 * (i + 1), 4 + i * 1.0), conc, "Step")
	ProtoWorld.block(self, Vector3(3.0, 1.08, 4.0), Vector3(12, 0.54, 12), conc, "StepTop")
	for i in 14:
		var r := ProtoWorld.block(self, Vector3(randf_range(0.2, 0.6), randf_range(0.08, 0.25), randf_range(0.2, 0.6)), Vector3(10.6 + randf() * 2.8, 0.05, 16 + randf() * 5), Color("8d877d"), "Rubble")
		r.rotation_degrees = Vector3(randf_range(-8, 8), randf() * 90, randf_range(-8, 8))
	# Cover wall and targets.
	ProtoWorld.block(self, Vector3(4.0, 1.4, 0.4), Vector3(-1, 0.7, -6), conc, "CoverWall")
	ProtoWorld.block(self, Vector3(0.4, 2.4, 3.0), Vector3(-8, 1.2, -6), brick, "CornerWall")
	for i in 5:
		var t := ProtoWorld.rigid_box(self, Vector3(0.5, 0.8, 0.1), Vector3(-6 + i * 3.0, 1.2, -16), Color("f0f0f0"), 3.0)
		var post := ProtoWorld.block(self, Vector3(0.1, 0.8, 0.1), Vector3(-6 + i * 3.0, 0.4, -16), Color("333333"), "Post")
	# Crawl tunnel.
	ProtoWorld.block(self, Vector3(3.0, 0.2, 4.0), Vector3(18, 0.85, 8), Color("666a70"), "TunnelRoof")
	ProtoWorld.block(self, Vector3(0.2, 0.75, 4.0), Vector3(16.4, 0.375, 8), Color("666a70"), "TunnelSide")
	ProtoWorld.block(self, Vector3(0.2, 0.75, 4.0), Vector3(19.6, 0.375, 8), Color("666a70"), "TunnelSide")
	_label3d("VAULT", Vector3(-6, 0.1, 1.5))
	_label3d("CLIMB", Vector3(0, 0.1, 2.5))
	_label3d("SLIDE / ROLL", Vector3(6, 0.1, 6.5))
	_label3d("STEPS + RUBBLE", Vector3(12, 0.1, 2.0))
	_label3d("CRAWL", Vector3(18, 0.1, 5.0))
	_label3d("COVER", Vector3(-1, 0.1, -4.5))

	cam = IsoCamera.new()
	cam.zoom = 12.0
	add_child(cam)
	sync = PawnSync.new()
	sync.pawn_parent = self
	sync.pawn_factory = func(id):
		var p := Officer.new()
		p.peer_id = id
		p.position = Vector3(-2 + Net.player_ids().find(id) * 1.5, 0.05, -1)
		if Net.is_host():
			p.fired.connect(_on_fired)
		return p
	sync.input_source = func(): return PlayerInput.sample(cam, sync.my_pawn())
	sync.pawn_spawned.connect(func(id, p): if id == Net.my_id(): cam.target = p)
	add_child(sync)
	var reticle := Reticle.new()
	reticle.pawn_getter = func(): return sync.my_pawn()
	add_child(reticle)
	var overlay := NetOverlay.new()
	overlay.extra_lines = func():
		var o: Officer = sync.my_pawn()
		if o == null:
			return ""
		return "state %s  speed %.1f m/s\n%s\n%s   J take a hit   K go down / get up   (controller works too)" % [
			Officer.S.keys()[o.state], Vector2(o.velocity.x, o.velocity.z).length(),
			Controls.help(["sprint", "jump", "crouch", "prone", "dive"]),
			Controls.help(["cover", "aim", "fire", "punch", "kick"])]
	add_child(overlay)


func _label3d(t: String, at: Vector3) -> void:
	var l := Label3D.new()
	l.text = t
	l.position = at + Vector3(0, 0.02, 0)
	l.rotation_degrees.x = -90
	l.font_size = 96
	l.outline_size = 16
	l.modulate = Color("fff6d0")
	add_child(l)


func _on_fired(origin: Vector3, dir: Vector3, _alt: bool) -> void:
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + dir * 50.0, 1 | 16))
	if hit and hit.collider is RigidBody3D:
		(hit.collider as RigidBody3D).apply_impulse(dir * 6.0, hit.position - hit.collider.global_position)
	_tracer(origin, hit.position if hit else origin + dir * 50.0)


func _tracer(a: Vector3, b: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, Cel.material(Color("ffe38a"), false))
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_end()
	mi.mesh = im
	add_child(mi)
	get_tree().create_timer(0.06).timeout.connect(mi.queue_free)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	var o: Officer = sync.my_pawn()
	if o == null:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_J:
			o.rig.hit_reaction(-Vector3(sin(o.rotation.y), 0, cos(o.rotation.y)), 8.0)
		KEY_K:
			o.rig.set_downed(not o.rig.downed, -Vector3(sin(o.rotation.y), 0.3, cos(o.rotation.y)) * 30.0)
