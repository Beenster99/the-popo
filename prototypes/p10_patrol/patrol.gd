extends Node3D
## Phase 1.3 patrol: two police cars on a test track with a street of kit
## shops, parked civilian cars to shunt, barriers and cones. Get in with
## interact by a door (up to all three officers in one car), drive, switch
## seats, lean out of a passenger window and shoot (aim), work the roof
## lights and siren (torch key), and restock ammo and first aid at the boot.
## Shoot the glass out, ram things until the doors and bumpers fall off.
## Injuries: legs limp, arms shake the aim, bleeding drains health; hold
## interact to treat yourself or a teammate. K (host): wound yourself.

const SCENE := "res://prototypes/p10_patrol/patrol.tscn"

var cam: IsoCamera
var sync: PawnSync
var world: DestructionWorld
var cars: CarSync


func _ready() -> void:
	ProtoWorld.environment(self)
	var sun := ProtoWorld.sun(self)
	sun.directional_shadow_max_distance = 120.0
	ProtoWorld.ground(self, 320.0, Color("4f5459"))
	# A long straight with dashed centre line, and a loop round the far end.
	for i in 24:
		ProtoWorld.block(self, Vector3(0.22, 0.02, 3.0), Vector3(0, 0.01, -60 + i * 8.0), Color("e9e4cf"), "Line", false)
	for i in 10:
		ProtoWorld.block(self, Vector3(1.0, 0.9, 2.0), Vector3(-14, 0.45, -30 + i * 7.0), Color("b9b5ab"), "Barrier")
		ProtoWorld.block(self, Vector3(1.0, 0.9, 2.0), Vector3(30, 0.45, -30 + i * 7.0), Color("b9b5ab"), "Barrier")
	# A kerb ramp to jump.
	var ramp := ProtoWorld.block(self, Vector3(4.0, 0.3, 6.0), Vector3(8, 0.5, 40), Color("8d8a82"), "Ramp")
	ramp.rotation_degrees.x = -12
	for i in 30:
		var cone := ProtoWorld.rigid_box(self, Vector3(0.4, 0.7, 0.4), Vector3(14 + (i % 6) * 2.0, 0.36, -10 + (i / 6) * 2.5), Color("ff7b1c"), 4.0)
		cone.collision_layer = 16
	world = DestructionWorld.new()
	add_child(world)
	BuildingLayout.shop(world, Vector3(-28, 0, 10))
	BuildingLayout.shop(world, Vector3(-28, 0, 26))
	BuildingLayout.wall_row(world, Vector3(18, 0, 60), 5)
	world.finalize()

	cam = IsoCamera.new()
	cam.zoom = 16.0
	cam.zoom_max = 60.0
	add_child(cam)
	cars = CarSync.new()
	cars.destruction = world
	cars.use_seats = true
	add_child(cars)
	for c in [[Vector3(4, 0.95, -2), 0.0], [Vector3(-6, 0.95, -2), 0.0]]:
		var pc := PoliceCar.new()
		pc.position = c[0]
		pc.rotation_degrees.y = c[1]
		add_child(pc)
		cars.add_car(pc)
	# Civilian cars parked down the street (box cars, not drivable here).
	var civ := [Color("1d3e7a"), Color("b8322f"), Color("6b7f3a")]
	for i in 3:
		var c := Car.new()
		c.color = civ[i]
		c.position = Vector3(-9, 0.95, 14 + i * 7.0)
		add_child(c)
		cars.add_car(c)

	sync = PawnSync.new()
	sync.pawn_parent = self
	sync.pawn_factory = func(id):
		var p := Officer.new()
		p.peer_id = id
		p.position = Vector3(1.6 + max(Net.player_ids().find(id), 0) * 1.2, 0.05, -5.5)
		if Net.is_host():
			p.fired.connect(_on_fired.bind(p))
			p.struck.connect(func(o, d, k): Melee.resolve(p, world, o, d, k))
		return p
	sync.input_source = func(): return PlayerInput.sample(cam, sync.my_pawn())
	sync.pawn_spawned.connect(func(id, p): if id == Net.my_id(): cam.target = p)
	world.sync = sync
	cars.sync = sync
	add_child(sync)
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
		var c: Car = o.car if o.car else cars.cars[0]
		return "hp %d   state %s   seat %d\ncar %d km/h   dents %.2f   parts %d   windows broken %d\nK wound yourself (host)   G reset (host)" % [
			int(o.hp), Officer.S.keys()[o.state], o.seat, c.speed_kmh(), c.dent_amount(), c.parts.size(),
			(c as PoliceCar).broken_windows() if c is PoliceCar else 0]
	add_child(overlay)


func _process(_delta: float) -> void:
	# Pull the camera out a little at speed.
	var o: Officer = sync.my_pawn() if sync else null
	if o and o.in_car():
		var v := o.car.linear_velocity.length()
		cam.zoom = lerpf(cam.zoom, clampf(16.0 + v * 0.6, 16.0, 34.0), 0.02)


func _on_fired(origin: Vector3, dir: Vector3, alt: bool, shooter: Officer) -> void:
	var end := Gunfire.resolve(world, cars, origin, dir, alt, shooter)
	if DisplayServer.get_name() == "headless":
		return
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, Cel.material(Color("ffe38a"), false))
	im.surface_add_vertex(origin)
	im.surface_add_vertex(end)
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
				o.injuries = Officer.LEG | Officer.ARM | Officer.BLEED
		KEY_G:
			Net.load_scene_for_all(SCENE)
