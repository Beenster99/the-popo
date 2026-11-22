extends Node3D
## Phase 1.2 training yard: everything new in movement and gunplay in one
## place. A street front of kit walls (smash a window and vault through it,
## kick a door in), parked cars to vault and hide behind, a cover lane for
## cover-to-cover runs and corner swings, a climbing tower to jump off (falls
## hurt) and targets. Friendly fire is on: down a teammate and revive them
## (hold interact next to them). K (host): go down yourself. G (host): reset.

const SCENE := "res://prototypes/p09_yard/yard.tscn"
const AMMO_BOX := Vector3(-4.5, 0, -7.0)

var cam: IsoCamera
var sync: PawnSync
var world: DestructionWorld


func _ready() -> void:
	ProtoWorld.environment(self)
	ProtoWorld.sun(self)
	ProtoWorld.ground(self, 240.0, Color("6f7a6a"))
	world = DestructionWorld.new()
	add_child(world)
	var r90 := Basis(Vector3.UP, PI * 0.5)
	# Street front at z = 8, facing the start (-Z): door, two windows, a
	# half-height wall, and another door at the end.
	var tint := Color("c9b79a")
	var front := [["wall_door", "door_closed"], ["wall_window", "glass_window"], ["wall_window", "glass_window"],
		["wall_shopfront", "glass_shopfront"], ["wall_door", "door_closed"]]
	for i in front.size():
		var xf := Transform3D(Basis(), Vector3(-8.0 + i * 4.0, 0, 8.0))
		var wi := world.add_piece(front[i][0], xf, true, tint)
		if front[i][1] != "":
			world.add_piece(front[i][1], xf, false, Color(0, 0, 0, 0), wi)
	# Side walls make it a room you can get into.
	for j in 2:
		world.add_piece("wall", Transform3D(r90, Vector3(-10.0, 0, 10.0 + j * 4.0)), true, tint)
		world.add_piece("wall", Transform3D(r90, Vector3(10.0, 0, 10.0 + j * 4.0)), true, tint)
	for i in 5:
		var wi := world.add_piece("wall_window", Transform3D(Basis(), Vector3(-8.0 + i * 4.0, 0, 16.0)), true, tint)
		world.add_piece("glass_window", Transform3D(Basis(), Vector3(-8.0 + i * 4.0, 0, 16.0)), false, Color(0, 0, 0, 0), wi)
	# Low street walls to vault.
	for i in 3:
		world.add_piece("low_wall", Transform3D(Basis(), Vector3(-6.0 + i * 6.0, 0, 3.5)), true)
	world.finalize()
	# Parked cars (held still): vault the bonnet, crouch behind them.
	for c in [[Vector3(-4, 0.9, -1.0), 90.0], [Vector3(5, 0.9, -1.5), 0.0]]:
		var car := Car.new()
		car.position = c[0]
		car.rotation_degrees.y = c[1]
		car.freeze = true
		add_child(car)
	# Cover lane: staggered low and tall walls, 5 m apart, for runs between them.
	var conc := Color("a9a49a")
	for i in 5:
		var tall := i % 2 == 1
		var h := 2.2 if tall else 1.1
		ProtoWorld.block(self, Vector3(2.4, h, 0.4), Vector3(16.0 + (2.5 if tall else -2.5), h * 0.5, -6.0 + i * 5.0), conc, "Cover")
	# Climbing tower: three 2.2 m steps up to 6.6 m. Jump off the top: it hurts.
	var brick := Color("8a4a36")
	for i in 3:
		var top := 2.2 * (i + 1)
		ProtoWorld.block(self, Vector3(3.0, top, 3.0), Vector3(-17.0, top * 0.5, -4.0 + i * 3.0), brick, "Tower")
	# Targets on posts.
	for i in 6:
		ProtoWorld.rigid_box(self, Vector3(0.5, 0.8, 0.1), Vector3(-7.5 + i * 3.0, 1.2, -12), Color("f0f0f0"), 3.0)
		ProtoWorld.block(self, Vector3(0.1, 0.8, 0.1), Vector3(-7.5 + i * 3.0, 0.4, -12), Color("333333"), "Post")
	_label3d("SMASH A WINDOW, VAULT IN", Vector3(-2, 0.1, 6.2))
	_label3d("KICK THE DOOR", Vector3(-8, 0.1, 6.2))
	_label3d("VAULT", Vector3(0, 0.1, 2.2))
	_label3d("CARS", Vector3(0, 0.1, -3.5))
	_label3d("COVER TO COVER", Vector3(16, 0.1, -8.5))
	_label3d("CLIMB, THEN JUMP", Vector3(-17, 0.1, -6.5))
	_label3d("TARGETS", Vector3(0, 0.1, -10))
	# Ammo box: hold interact next to it to fill your belt.
	ProtoWorld.block(self, Vector3(0.7, 0.45, 0.45), AMMO_BOX + Vector3(0, 0.225, 0), Color("4d5a2e"), "AmmoBox")
	_label3d("AMMO (HOLD F)", AMMO_BOX + Vector3(0, 0, -0.9))

	cam = IsoCamera.new()
	cam.zoom = 14.0
	add_child(cam)
	sync = PawnSync.new()
	sync.pawn_parent = self
	sync.pawn_factory = func(id):
		var p := Officer.new()
		p.peer_id = id
		p.position = Vector3(-1.5 + max(Net.player_ids().find(id), 0) * 1.5, 0.05, -6)
		if Net.is_host():
			p.fired.connect(_on_fired.bind(p))
			p.struck.connect(func(o, d, k): Melee.resolve(p, world, o, d, k))
		return p
	sync.input_source = func(): return PlayerInput.sample(cam, sync.my_pawn())
	sync.pawn_spawned.connect(func(id, p): if id == Net.my_id(): cam.target = p)
	world.sync = sync
	add_child(sync)
	# Phase 1.6: sound (footsteps, guns, brass, engines, background).
	var sounds := GameSounds.new()
	sounds.world = world
	sounds.pawn_getter = func(): return sync.my_pawn()
	add_child(sounds)
	var reticle := Reticle.new()
	reticle.pawn_getter = func(): return sync.my_pawn()
	add_child(reticle)
	var hud := AmmoHud.new()
	hud.pawn_getter = func(): return sync.my_pawn()
	add_child(hud)
	var overlay := NetOverlay.new()
	overlay.extra_lines = func():
		var o: Officer = sync.my_pawn()
		if o == null:
			return ""
		var down := ""
		if o.state == Officer.S.DOWNED:
			down = "\nDOWN: a teammate holds %s next to you (%.0f%%), or you get up in %.0f s" % [
				Controls.describe(Controls.pc_event("interact")), 100.0 * o.revive_t / Officer.REVIVE_TIME, maxf(0.0, Officer.SELF_REVIVE - o.state_t)]
		return "hp %d   ammo %d/%d%s   state %s%s\n%s\n%s\nK go down (host)   G reset (host)" % [
			int(o.hp), o.ammo, Officer.MAG, "  (holstered)" if o.holstered else "", Officer.S.keys()[o.state], down,
			Controls.help(["sprint", "jump", "stance", "dive", "cover"]),
			Controls.help(["aim", "fire", "reload", "holster", "torch", "punch", "kick", "interact"])]
	add_child(overlay)


func _physics_process(_delta: float) -> void:
	if not Net.is_host() or sync == null:
		return
	for o in get_tree().get_nodes_in_group("officers"):
		var off: Officer = o
		if (off.buttons & PlayerInput.INTERACT) != 0 and off.global_position.distance_to(AMMO_BOX) < 1.4:
			off.refill_ammo()


func _label3d(t: String, at: Vector3) -> void:
	var l := Label3D.new()
	l.text = t
	l.position = at + Vector3(0, 0.02, 0)
	l.rotation_degrees.x = -90
	l.font_size = 72
	l.outline_size = 14
	l.modulate = Color("fff6d0")
	add_child(l)


func _on_fired(origin: Vector3, dir: Vector3, alt: bool, shooter: Officer) -> void:
	var end := Gunfire.resolve(world, null, origin, dir, alt, shooter)
	_tracer(origin, end)


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
	if not event.is_pressed() or event.is_echo() or not Net.is_host():
		return
	match (event as InputEventKey).physical_keycode:
		KEY_K:
			var o: Officer = sync.my_pawn()
			if o:
				o.take_damage(999.0, -o._fwd())
		KEY_G:
			Net.load_scene_for_all(SCENE)
