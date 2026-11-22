class_name Block
extends Node3D
## The game for now (Single Player and Online start here): a generated city
## block with two police cars parked on the north road, and (Phase 1.4) the
## dispatcher: calls, suspects, the custody bay and the crime level.
## Phase 1.1: a generated city block. Roads, pavements and 4 to 6 buildings
## from the Wave 1 kit, laid out from a seed; two of them can be entered
## (rooms, stairs, upper floor). Everything is breakable: 1 pistol,
## 2 demolition charge. The host picks the seed and sends it to everyone, so
## all machines build the same block. G (host): a new block for everyone.

const MSG_SEED_ASK := 70
const MSG_SEED := 71
const SCENE := "res://prototypes/p08_block/block.tscn"

## The host's seed for the next load (G sets it; 0 picks one at random).
static var next_seed := 0
## The host's next load continues the saved block (Continue on the menus).
static var resume := false

var cam: IsoCamera
var sync: PawnSync
var world: DestructionWorld
var fader: RoofFader
var gen: BlockGenerator
var cars: CarSync
var nav: BlockNav
var dispatch: Dispatcher
var civ_car: Car
var sounds: GameSounds
var props: PropWorld
var fire: FireSystem
var state: BlockState
var seed_value := 0
var _names := {}     # peer id -> name, to say who came and went


func _ready() -> void:
	ProtoWorld.environment(self)
	var sun := ProtoWorld.sun(self)
	sun.directional_shadow_max_distance = 120.0
	# Grass round the block, just below the road surface (no z-fighting).
	var grass := ProtoWorld.block(self, Vector3(400, 1, 400), Vector3(24, -0.56, 24), Color("4b5a45"), "Ground", false)
	grass.get_child(0).material_override = Cel.material(Color("4b5a45"), false, 0.025, null, 1.0, true)
	grass.set_meta("surface", "dirt")
	cam = IsoCamera.new()
	cam.zoom = 16.0
	add_child(cam)
	sync = PawnSync.new()
	sync.pawn_parent = self
	sync.pawn_factory = func(id):
		var p := Officer.new()
		p.peer_id = id
		p.position = _spawn_point(max(Net.player_ids().find(id), 0))
		if Net.is_host():
			p.fired.connect(_on_fired.bind(p))
			p.struck.connect(func(o, d, k): Melee.resolve(p, world, o, d, k))
		return p
	sync.input_source = func(): return PlayerInput.sample(cam, sync.my_pawn())
	sync.pawn_spawned.connect(func(id, p):
		if id == Net.my_id():
			cam.target = p
			fader.watch = p)
	world = DestructionWorld.new()
	world.sync = sync
	add_child(world)
	fader = RoofFader.new()
	add_child(fader)
	# Phase 1.4: calls, suspects and the crime level (before the block is built,
	# which hands it the layout).
	dispatch = Dispatcher.new()
	dispatch.name = "Dispatcher"
	add_child(dispatch)
	Net.register(MSG_SEED_ASK, _on_seed_ask)
	Net.register(MSG_SEED, _on_seed)
	# Phase 1.7: friends coming and going.
	Net.host_lost.connect(_on_host_lost)
	Net.lobby_changed.connect(_on_lobby_changed)
	for sl in Net.slots:
		_names[sl.id] = sl.name
	if Net.is_host():
		var s := next_seed
		var saved := BlockState.peek()
		if resume and not saved.is_empty():
			s = saved.seed
		if s == 0:
			s = randi_range(1, 999999)
		next_seed = 0
		_build(s)
		if not (resume and state.load_save()):
			state.dirty = true   # a fresh block replaces the old save
		resume = false
	else:
		Net.send(1, MSG_SEED_ASK, PackedByteArray())
	var reticle := Reticle.new()
	reticle.pawn_getter = func(): return sync.my_pawn()
	add_child(reticle)
	var hud := AmmoHud.new()
	hud.pawn_getter = func(): return sync.my_pawn()
	add_child(hud)
	var dhud := DispatchHud.new()
	dhud.dispatcher = dispatch
	dhud.pawn_getter = func(): return sync.my_pawn()
	add_child(dhud)
	var overlay := NetOverlay.new()
	overlay.extra_lines = func():
		var o: Officer = sync.my_pawn()
		var state: String = Officer.S.keys()[o.state] if o else "-"
		return "block seed %d   %d pieces   %s\n1 pistol  2 charge [%s]   G new block (host)   J call in a job (host)   %s" % [
			seed_value, world.pieces.size(), state, "charge" if PlayerInput.alt_tool else "pistol",
			Controls.help(["stance", "cover", "aim", "fire", "reload", "kick", "interact"])]
	add_child(overlay)


func _exit_tree() -> void:
	Net.unregister(MSG_SEED_ASK)
	Net.unregister(MSG_SEED)
	if Net.host_lost.is_connected(_on_host_lost):
		Net.host_lost.disconnect(_on_host_lost)
	if Net.lobby_changed.is_connected(_on_lobby_changed):
		Net.lobby_changed.disconnect(_on_lobby_changed)


## A friend's game: the host has gone, so back to the menu and say why.
func _on_host_lost(reason: String) -> void:
	Net.last_notice = reason
	get_tree().paused = false
	PlayerInput.blocked = false
	get_tree().change_scene_to_file.call_deferred("res://game/ui/main_menu.tscn")


## Host: who joined and who left, on the radio for everyone.
func _on_lobby_changed() -> void:
	if not Net.is_host() or dispatch == null:
		return
	var now := {}
	for sl in Net.slots:
		now[sl.id] = sl.name
		if not _names.has(sl.id):
			dispatch.say("DISPATCH: %s is joining the shift." % sl.name)
	for id in _names:
		if not now.has(id):
			dispatch.say("DISPATCH: %s has gone off shift." % _names[id])
	_names = now


func _build(s: int) -> void:
	if gen != null:
		return
	seed_value = s
	gen = CityBlock.build(world, s, fader)
	# Two patrol cars parked on the north road (the same on every machine).
	cars = CarSync.new()
	cars.destruction = world
	cars.use_seats = true
	cars.sync = sync
	add_child(cars)
	for c in [[Vector3(14, 0.95, -3.5), 90.0], [Vector3(34, 0.95, -8.5), -90.0]]:
		var pc := PoliceCar.new()
		pc.position = c[0]
		pc.rotation_degrees.y = c[1]
		add_child(pc)
		cars.add_car(pc)
	# The traffic stop's car, parked on the south road between calls.
	civ_car = Car.new()
	civ_car.color = Color("2f5f9a")
	civ_car.position = Vector3(20, 0.95, 54)
	civ_car.rotation_degrees.y = -90.0
	add_child(civ_car)
	cars.add_car(civ_car)
	add_child(sync)
	nav = BlockNav.new()
	nav.name = "BlockNav"
	add_child(nav)
	if Net.is_host():
		nav.bake_from(self)
	dispatch.setup(gen, world, cars, nav, civ_car)
	# Phase 1.5: furniture and loose things, and fire.
	props = PropWorld.new()
	props.name = "Props"
	props.world = world
	props.cars = cars
	add_child(props)
	props.furnish(gen)
	fire = FireSystem.new()
	fire.name = "Fire"
	fire.world = world
	fire.props = props
	fire.cars = cars
	add_child(fire)
	# Phase 1.6: the sound of the block.
	sounds = GameSounds.new()
	sounds.name = "GameSounds"
	sounds.world = world
	sounds.cars = cars
	sounds.pawn_getter = func(): return sync.my_pawn()
	add_child(sounds)
	sounds.add_building_zones(gen)
	# Phase 1.7: the damage, for friends joining late and for the save.
	state = BlockState.new()
	state.name = "BlockState"
	state.world = world
	state.props = props
	state.cars = cars
	state.dispatch = dispatch
	state.seed_value = s
	add_child(state)
	state.ask()
	# Camera starts over the first enterable building's door.
	cam.global_position = _spawn_point(0)


## Pavement just outside an enterable building's front door.
func _spawn_point(i: int) -> Vector3:
	if gen == null:
		return Vector3(24, 0.3, -2)
	var doors: Array = gen.buildings.filter(func(b): return b.enterable).map(func(b): return b.door)
	var d: Vector3 = doors[0] if doors.size() > 0 else Vector3(24, 0, 2)
	var side := Vector3(1.2, 0, 0) * (i - 1)
	return Vector3(d.x, BlockGenerator.BASE_Y + 0.05, d.z) + side


func _on_seed_ask(from: int, _data: PackedByteArray) -> void:
	if Net.is_host() and seed_value != 0:
		var b := StreamPeerBuffer.new()
		b.put_u32(seed_value)
		Net.send(from, MSG_SEED, b.data_array)


func _on_seed(_from: int, data: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	_build(b.get_u32())


func _on_fired(origin: Vector3, dir: Vector3, alt: bool, shooter: Officer) -> void:
	Gunfire.resolve(world, cars, origin, dir, alt, shooter)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and (event as InputEventKey).physical_keycode == KEY_J and Net.is_host() and dispatch:
		# Host: call in the next job now (testing).
		dispatch.start_call(dispatch._pick_kind())
	if event.is_pressed() and not event.is_echo() and (event as InputEventKey).physical_keycode == KEY_G and Net.is_host():
		next_seed = randi_range(1, 999999)
		Net.load_scene_for_all(SCENE)
