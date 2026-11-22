extends Node3D
## Phase 1.6 listening room (grown from the Phase 0.7 sound spike): a street
## with a breakable shop, a thick wall, a parked car and loose crates, to
## judge and tune every sound in the game. Walk about with your own gun and
## shoot things, and use the test keys:
##   5, 6, 7  a pistol in the street, inside the shop, behind the thick wall
##   8        a shotgun right next to you (ears ring)
##   9        a bullet cracking past your head, then one whizzing further off
##   0        a blast 15 m away
##   F4       the three test pistols in turn, over and over
## What to listen for:
##   street   crack, low thump and tail, then slapback off the facades
##   inside   tight and loud, with the room's reverb; the street goes muffled
##   walls    each wall between the shot and your ears muffles it
##   targets  the shop's glass (pane, shop front), door (wood), walls
##            (concrete), the car (metal and glass), crates and metal boxes
##            that clatter when knocked over
##   brass    your cases bounce on the pavement; reload (R) from empty for the
##            full mag out, mag on the floor, mag in and slide
## G (host) rebuilds the room.

const ROOM := Vector3(6, 0, -6)       # centre of the shop floor
const TEST_GUNS := [
	["street", Vector3(-8, 1.3, 4)],
	["inside the shop", Vector3(6, 1.3, -7)],
	["behind the wall", Vector3(-8, 1.3, -12)],
]
const GUN_EVERY := 1.6
const SCENE := "res://prototypes/p07_sound/sound.tscn"

var cam: IsoCamera
var sync: PawnSync
var world: DestructionWorld
var cars: CarSync
var sounds: GameSounds
var auto_fire := false
var _next_gun := 0
var _timer := 0.8
var _last_test := ""


func _ready() -> void:
	ProtoWorld.environment(self)
	ProtoWorld.sun(self)
	ProtoWorld.ground(self, 120.0, Color("3d4045"))
	var conc := Color("a9a49a")
	# A tall facade at the back of the block, for the slapback.
	ProtoWorld.block(self, Vector3(40, 9, 1), Vector3(0, 4.5, -20), Color("7d6f63"), "FacadeBack")
	world = DestructionWorld.new()
	add_child(world)
	_build_shop()
	world.finalize()
	# A thick freestanding wall between the street and the third test gun.
	ProtoWorld.block(self, Vector3(8, 3.5, 0.6), Vector3(-8, 1.75, -9), conc, "ThickWall")
	# Loose things to knock about.
	for i in 3:
		_prop("wood", Vector3(-4 + i * 1.3, 0.5, 9), Vector3(0.9, 0.9, 0.9), Color("9b6a3c"), 8.0)
	for i in 2:
		_prop("metal", Vector3(8 + i * 1.4, 0.7, 9.5), Vector3(1.0, 1.4, 0.7), Color("5c6a75"), 25.0)

	cam = IsoCamera.new()
	cam.zoom = 16.0
	add_child(cam)
	cars = CarSync.new()
	cars.destruction = world
	cars.use_seats = true
	add_child(cars)
	var car := Car.new()
	car.color = Color("b8322f")
	car.position = Vector3(1, 0.95, 13)
	car.rotation_degrees.y = 90.0
	add_child(car)
	cars.add_car(car)
	sync = PawnSync.new()
	sync.pawn_parent = self
	sync.pawn_factory = func(id):
		var p := Officer.new()
		p.peer_id = id
		p.position = Vector3(-1 + max(Net.player_ids().find(id), 0) * 1.5, 0.05, 4)
		if Net.is_host():
			p.fired.connect(_on_fired.bind(p))
			p.struck.connect(func(o, d, k): Melee.resolve(p, world, o, d, k))
		return p
	sync.input_source = func(): return PlayerInput.sample(cam, sync.my_pawn())
	sync.pawn_spawned.connect(func(id, p):
		if id == Net.my_id():
			cam.target = p)
	world.sync = sync
	cars.sync = sync
	add_child(sync)
	sounds = GameSounds.new()
	sounds.name = "GameSounds"
	sounds.world = world
	sounds.cars = cars
	sounds.pawn_getter = func(): return sync.my_pawn()
	add_child(sounds)
	var zone := SoundZone.new()
	zone.size = Vector3(11.6, 3.2, 7.6)
	zone.position = ROOM + Vector3(0, 1.6, 0)
	sounds.add_child(zone)
	for g in TEST_GUNS:
		_gun_marker(g[1], g[0])
	var reticle := Reticle.new()
	reticle.pawn_getter = func(): return sync.my_pawn()
	add_child(reticle)
	var hud := AmmoHud.new()
	hud.pawn_getter = func(): return sync.my_pawn()
	add_child(hud)
	var overlay := NetOverlay.new()
	overlay.extra_lines = _hud_text
	add_child(overlay)


## The shop: a shop front, a door and a window on the street side, plain
## walls round the rest, all breakable kit pieces.
func _build_shop() -> void:
	var tint := Color("8a4a36")
	var r90 := Basis(Vector3.UP, PI * 0.5)
	var z_front := ROOM.z + 4.0
	var front := [["wall_window", "glass_window"], ["wall_shopfront", "glass_shopfront"], ["wall_door", "door_closed"]]
	for i in front.size():
		var xf := Transform3D(Basis(), Vector3(ROOM.x - 4.0 + i * 4.0, 0, z_front))
		var wi := world.add_piece(front[i][0], xf, true, tint)
		world.add_piece(front[i][1], xf, false, Color(0, 0, 0, 0), wi)
	for i in 3:
		world.add_piece("wall", Transform3D(Basis(), Vector3(ROOM.x - 4.0 + i * 4.0, 0, ROOM.z - 4.0)), true, tint)
	for j in 2:
		world.add_piece("wall", Transform3D(r90, Vector3(ROOM.x - 6.0, 0, ROOM.z - 2.0 + j * 4.0)), true, tint)
		world.add_piece("wall", Transform3D(r90, Vector3(ROOM.x + 6.0, 0, ROOM.z - 2.0 + j * 4.0)), true, tint)


func _hud_text() -> String:
	var last := "none yet"
	if not Sfx.history.is_empty():
		var s: Dictionary = Sfx.history[-1]
		last = "%s on %s, %d wall(s) to your ears" % [s.stem, s.played_on, s.walls]
	return "LISTENING ROOM   5 street gun  6 shop gun  7 gun behind the wall  8 shotgun by you  9 bullets past you  0 blast   F4 auto-fire (%s)   last test: %s\nLast sound: %s\nShoot the glass, door, walls, car and crates. R from empty for the full reload. G (host) rebuilds the room." % [
		"on" if auto_fire else "off", _last_test, last]


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo) or not Net.is_host():
		return
	var o: Officer = sync.my_pawn()
	var head := o.global_position + Vector3(0, 1.6, 0) if o else Vector3(0, 1.6, 4)
	match e.keycode:
		KEY_F4:
			auto_fire = not auto_fire
		KEY_5, KEY_6, KEY_7:
			var g: Array = TEST_GUNS[e.keycode - KEY_5]
			_last_test = g[0]
			sounds.sync.gunshot(g[1])
		KEY_8:
			_last_test = "shotgun next to you"
			sounds.sync.gunshot(head + Vector3(1.2, -0.3, 0.6), Sfx.SHOTGUN)
		KEY_9:
			_last_test = "bullets past your head"
			sounds.sync.gunshot(head + Vector3(-25, -0.2, 0))
			sounds.sync.bullet(head + Vector3(-25, -0.2, 0.7), head + Vector3(25, -0.2, 0.7), "concrete", 2)
			get_tree().create_timer(0.8).timeout.connect(func():
				if is_instance_valid(sounds):
					sounds.sync.gunshot(head + Vector3(-25, -0.2, 2))
					sounds.sync.bullet(head + Vector3(-25, -0.2, 2.0), head + Vector3(25, -0.2, 2.0), "concrete", 2))
		KEY_0:
			_last_test = "blast"
			world.explode(Vector3(-6, 0.5, 18), 3.0, 120.0, 8.0)
		KEY_G:
			Scenes.load_scene(get_tree(), SCENE)


func _physics_process(delta: float) -> void:
	if not Net.is_host() or not auto_fire:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = GUN_EVERY
	var g: Array = TEST_GUNS[_next_gun]
	_next_gun = (_next_gun + 1) % TEST_GUNS.size()
	_last_test = g[0]
	sounds.sync.gunshot(g[1])


func _on_fired(origin: Vector3, dir: Vector3, alt: bool, shooter: Officer) -> void:
	Gunfire.resolve(world, cars, origin, dir, alt, shooter)


func _prop(surface: String, pos: Vector3, size: Vector3, color: Color, mass: float) -> RigidBody3D:
	var n := ProtoWorld.rigid_box(self, size, pos, color, mass)
	n.set_meta("surface", surface)
	n.add_to_group("props")
	return n


func _gun_marker(at: Vector3, label: String) -> void:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0
	cyl.bottom_radius = 0.25
	cyl.height = 0.5
	m.mesh = cyl
	m.material_override = Cel.material(Color("ffcc33"))
	m.position = Vector3(at.x, 0.25, at.z)
	add_child(m)
	var l := Label3D.new()
	l.text = "TEST GUN: " + label.to_upper()
	l.position = Vector3(at.x, 0.03, at.z + 0.8)
	l.rotation_degrees.x = -90
	l.font_size = 72
	l.outline_size = 14
	l.modulate = Color("fff6d0")
	add_child(l)
