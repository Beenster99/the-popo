class_name City
extends Node3D
## Wave 2: the game. The whole city from one seed (CityGenerator): six by six
## blocks in four districts, the police station on the south side of
## downtown (everyone starts at its door, the patrol cars are parked out
## front and prisoners are booked in at its custody bay), parks, a car park
## and the docks.
##
## The host picks the seed and sends it to everyone, so every machine builds
## the same city with the same piece ids. Furniture is put in a block at a
## time as officers come near (the host decides, so ids line up), and the
## walking routes are baked a block at a time in the background, nearest
## first.
##
## G (host): a new city for everyone. J (host): call in a job now.

const MSG_SEED_ASK := 70
const MSG_SEED := 71
const MSG_FURNISH := 72      # host -> all: furnish these blocks (u16 each)
const SCENE := "res://game/city/city.tscn"
const SAVE_PATH := "user://saves/city.save"
## Officers this close to a block (m from its lot) get it furnished.
const FURNISH_RANGE := 70.0

static var next_seed := 0
static var resume := false
## Wave 5: start the first-shift tutorial (single player; never saved).
static var tutorial := false
var first_shift: FirstShift

var cam: IsoCamera
var sync: PawnSync
var world: DestructionWorld
var fader: RoofFader
var gen: CityGenerator
var ground: CityGround
var cars: CarSync
var nav: CityNav
var dispatch: Dispatcher
var civ_car: Car
var sounds: GameSounds
var props: PropWorld
var fire: FireSystem
var state: BlockState
var seed_value := 0
var police_cars: Array = []
var traffic: TrafficSystem
var env: Environment
var skyline: CitySkyline
var peds: PedSystem
## Wave 4: the light follows the clock; rain and storms.
var weather: CityWeather
var repairs: RepairCrews
var sun: DirectionalLight3D
## Wave 3, Phase 3.5: what the station has bought, and the vehicles waiting
## in its yard until it does.
var armoury: Armoury
var yard_cars := {}       # armoury item -> PoliceCar
var _garage: Node3D
var _alarm_t := 0.0
var build_ms := 0
var _names := {}
var _furnish_t := 0.0


func _ready() -> void:
	BlockState.save_path = SAVE_PATH
	env = ProtoWorld.environment(self).environment
	sun = ProtoWorld.sun(self)
	sun.directional_shadow_max_distance = 140.0
	cam = IsoCamera.new()
	cam.zoom = 16.0
	add_child(cam)
	sync = PawnSync.new()
	sync.pawn_parent = self
	sync.pawn_factory = func(id):
		var p := Officer.new()
		p.peer_id = id
		p.position = _spawn_point(max(Net.player_ids().find(id), 0))
		if gen:
			# Out of the station door, facing the street.
			var v: Vector3 = gen.station().v
			p.rotation.y = atan2(-v.x, -v.z)
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
	dispatch = Dispatcher.new()
	dispatch.name = "Dispatcher"
	add_child(dispatch)
	armoury = Armoury.new()
	armoury.name = "Armoury"
	armoury.dispatcher = dispatch
	armoury.sync = sync
	add_child(armoury)
	armoury.changed.connect(_station_grows)
	Net.register(MSG_SEED_ASK, _on_seed_ask)
	Net.register(MSG_SEED, _on_seed)
	Net.register(MSG_FURNISH, _on_furnish)
	Net.host_lost.connect(_on_host_lost)
	Net.lobby_changed.connect(_on_lobby_changed)
	for sl in Net.slots:
		_names[sl.id] = sl.name
	if Net.is_host():
		var s := next_seed
		var saved := BlockState.peek()
		KitLibrary.detail = int(Settings.values.get("debris_detail", 2))
		if resume and not saved.is_empty():
			s = saved.seed
			KitLibrary.detail = int(saved.get("detail", KitLibrary.detail))
		if s == 0:
			s = randi_range(1, 999999)
		next_seed = 0
		_build(s)
		if tutorial:
			state.no_save = true
			dispatch.enabled = false
			first_shift = FirstShift.new()
			first_shift.city = self
			add_child(first_shift)
		elif not (resume and state.load_save()):
			state.dirty = true
		resume = false
		tutorial = false
	else:
		Net.send(1, MSG_SEED_ASK, PackedByteArray())
	var reticle := Reticle.new()
	reticle.pawn_getter = func(): return sync.my_pawn()
	add_child(reticle)
	var hud := AmmoHud.new()
	hud.pawn_getter = func(): return sync.my_pawn()
	add_child(hud)
	var radio := PoliceRadio.new()
	radio.name = "Radio"
	radio.dispatcher = dispatch
	add_child(radio)
	var music := MusicDirector.new()
	music.name = "Music"
	music.pawn_getter = func(): return sync.my_pawn()
	add_child(music)
	var dhud := DispatchHud.new()
	dhud.dispatcher = dispatch
	dhud.armoury = armoury
	dhud.pawn_getter = func(): return sync.my_pawn()
	add_child(dhud)
	var overlay := NetOverlay.new()
	overlay.extra_lines = func():
		var o: Officer = sync.my_pawn()
		var st: String = Officer.S.keys()[o.state] if o else "-"
		var where := "-"
		if o and gen:
			where = "%s, %s" % [gen.district_at(o.global_position), CityGenerator.street_at(o.global_position)]
		return "city seed %d   %d pieces (built in %d ms)   walk routes %d/%d   %s\n%s\n1 pistol  2 charge [%s]   G new city   J call in a job   K weather   N +3 hours (host)   %s" % [
			seed_value, world.pieces.size(), build_ms, nav.baked_count() if nav else 0, gen.blocks.size() if gen else 0, st, where,
			"charge" if PlayerInput.alt_tool else "pistol",
			Controls.help(["stance", "cover", "aim", "fire", "reload", "kick", "interact"])]
	add_child(overlay)


func _exit_tree() -> void:
	for m in [MSG_SEED_ASK, MSG_SEED, MSG_FURNISH]:
		Net.unregister(m)
	if Net.host_lost.is_connected(_on_host_lost):
		Net.host_lost.disconnect(_on_host_lost)
	if Net.lobby_changed.is_connected(_on_lobby_changed):
		Net.lobby_changed.disconnect(_on_lobby_changed)


func _on_host_lost(reason: String) -> void:
	Net.last_notice = reason
	get_tree().paused = false
	PlayerInput.blocked = false
	get_tree().change_scene_to_file.call_deferred("res://game/ui/main_menu.tscn")


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
	var t0 := Time.get_ticks_msec()
	seed_value = s
	gen = CityGenerator.generate_city(s)
	for p in gen.pieces:
		world.add_piece(p.kind, p.xform, p.bears, p.tint, p.held_by + 1 if p.held_by >= 0 else -1, p.group)
	world.finalize()
	fader.add_city(world, gen)
	ground = CityGround.new()
	ground.name = "Ground"
	add_child(ground)
	ground.build(gen)
	skyline = CitySkyline.new()
	skyline.name = "Skyline"
	add_child(skyline)
	skyline.build(gen, world, env)
	weather = CityWeather.new()
	weather.name = "Weather"
	weather.dispatcher = dispatch
	weather.world = world
	weather.env = env
	weather.sun = sun
	weather.ground = ground
	weather.skyline = skyline
	add_child(weather)
	cars = CarSync.new()
	cars.destruction = world
	cars.use_seats = true
	cars.sync = sync
	add_child(cars)
	# Patrol cars parked on the kerb in front of the station, nose east.
	var st := gen.station()
	var front: Vector3 = (st.origin as Vector3) - (st.v as Vector3) * 5.1 + Vector3(0, 0.8, 0)
	for k in 3:
		var pc := PoliceCar.new()
		pc.position = front + (st.u as Vector3) * (6.0 + k * 6.5)
		pc.rotation_degrees.y = 90.0
		add_child(pc)
		cars.add_car(pc)
		police_cars.append(pc)
	_build_yard(st)
	# The traffic stop's car, parked on the far side of the station block.
	civ_car = Car.new()
	civ_car.color = Color("2f5f9a")
	var lot: Vector3 = gen.blocks[gen.block_index(CityGenerator.STATION.x, CityGenerator.STATION.y)].offset
	civ_car.position = lot + Vector3(20, 0.95, CityGenerator.lot_size(CityGenerator.STATION.x, CityGenerator.STATION.y).y + 2.4)
	civ_car.rotation_degrees.y = -90.0
	add_child(civ_car)
	cars.add_car(civ_car)
	# Traffic and parked cars (the same cars in the same order everywhere).
	traffic = TrafficSystem.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.build(gen, cars, dispatch)
	add_child(sync)
	nav = CityNav.new()
	nav.name = "CityNav"
	add_child(nav)
	if Net.is_host():
		nav.bake_city(world, gen, _spawn_point(0))
	dispatch.setup(gen, world, cars, nav, civ_car)
	dispatch.traffic = traffic
	peds = PedSystem.new()
	peds.name = "Peds"
	peds.gen = gen
	peds.dispatch = dispatch
	peds.nav = nav
	add_child(peds)
	repairs = RepairCrews.new()
	repairs.name = "Repairs"
	repairs.world = world
	repairs.dispatch = dispatch
	repairs.traffic = traffic
	repairs.gen = gen
	add_child(repairs)
	# Something big coming down: people and drivers near it scatter.
	world.piece_broken.connect(func(id):
		if Net.is_host() and _alarm_t <= 0.0 and world.pieces.has(id):
			_alarm_t = 0.6
			get_tree().call_group("alarm_listeners", "on_alarm", (world.pieces[id].aabb as AABB).get_center(), 30.0))
	props = PropWorld.new()
	props.name = "Props"
	props.world = world
	props.cars = cars
	props.city = gen
	add_child(props)
	fire = FireSystem.new()
	fire.name = "Fire"
	fire.world = world
	fire.props = props
	fire.cars = cars
	add_child(fire)
	sounds = GameSounds.new()
	sounds.name = "GameSounds"
	sounds.world = world
	sounds.cars = cars
	sounds.pawn_getter = func(): return sync.my_pawn()
	add_child(sounds)
	sounds.add_building_zones(gen)
	state = BlockState.new()
	state.name = "BlockState"
	state.world = world
	state.props = props
	state.cars = cars
	state.dispatch = dispatch
	state.seed_value = s
	state.weather = weather
	state.sync = sync
	state.name_of = func(id): return _names.get(id, "")
	add_child(state)
	if Net.is_host():
		_furnish_near(true)
	state.ask()
	cam.global_position = _spawn_point(0)
	build_ms = Time.get_ticks_msec() - t0
	print("City %d built in %d ms: %d pieces, %d buildings" % [s, build_ms, world.pieces.size(), gen.buildings.size()])


## Pavement just outside the station's front door, side by side.
func _spawn_point(i: int) -> Vector3:
	if gen == null:
		return Vector3(150, 0.3, 250)
	var st := gen.station()
	var d: Vector3 = st.door
	var side := (st.u as Vector3) * 1.2 * (i - 1)
	return Vector3(d.x, BlockGenerator.BASE_Y + 0.05, d.z) + side


## Host: furnish the blocks officers are near, and tell everyone.
func _physics_process(delta: float) -> void:
	if not Net.is_host() or gen == null:
		return
	_furnish_t -= delta
	_alarm_t -= delta
	if _furnish_t <= 0.0:
		_furnish_t = 1.0
		_furnish_near(false)
		var o := sync.my_pawn() as Node3D
		if o:
			nav.set_focus(o.global_position)


func _furnish_near(_first: bool) -> void:
	var want: Array = []
	var near: Array = []
	for o in get_tree().get_nodes_in_group("officers"):
		near.append((o as Node3D).global_position)
	if near.is_empty():
		near.append(_spawn_point(0))
	for k in gen.blocks.size():
		if props.furnished.has(k):
			continue
		var r: Rect2 = (gen.blocks[k].rect as Rect2).grow(FURNISH_RANGE)
		for p in near:
			if r.has_point(Vector2(p.x, p.z)):
				want.append(k)
				break
	if want.is_empty():
		return
	var b := StreamPeerBuffer.new()
	b.put_u16(want.size())
	for k in want:
		b.put_u16(k)
		props.furnish_block(k)
	if Net.is_online():
		Net.broadcast(MSG_FURNISH, b.data_array, Net.RELIABLE)


func _on_furnish(_from: int, data: PackedByteArray) -> void:
	if Net.is_host() or props == null:
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	for i in b.get_u16():
		props.furnish_block(b.get_u16())


func _on_seed_ask(from: int, _data: PackedByteArray) -> void:
	if Net.is_host() and seed_value != 0:
		var b := StreamPeerBuffer.new()
		b.put_u32(seed_value)
		b.put_u8(KitLibrary.detail)
		Net.send(from, MSG_SEED, b.data_array)


func _on_seed(_from: int, data: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var sv := b.get_u32()
	if b.get_available_bytes() > 0:
		KitLibrary.detail = b.get_u8()
	_build(sv)


func _on_fired(origin: Vector3, dir: Vector3, alt: bool, shooter: Officer) -> void:
	Gunfire.resolve(world, cars, origin, dir, alt, shooter)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event.is_pressed() and not event.is_echo()):
		return
	var key := (event as InputEventKey).physical_keycode
	# Wave 4 (host): K changes the weather, N moves the clock on three hours.
	if key == KEY_K and Net.is_host() and weather:
		weather.set_weather((weather.kind + 1) % 4)
	if key == KEY_N and Net.is_host() and dispatch and dispatch.missions:
		dispatch.missions.minute = fposmod(dispatch.missions.minute + 180.0, Missions.DAY_MINUTES)
	if key == KEY_J and Net.is_host() and dispatch:
		dispatch.start_call(dispatch._pick_kind())
	if key == KEY_G and Net.is_host():
		next_seed = randi_range(1, 999999)
		Net.load_scene_for_all(SCENE)


# --- the station grows (Phase 3.5) -------------------------------------------------------

## The armoury counter just inside the door, and the vehicles the station
## can buy, parked in the yard beside it, locked until it does.
func _build_yard(st: Dictionary) -> void:
	var u: Vector3 = st.u
	var v: Vector3 = st.v
	var door: Vector3 = st.door
	armoury.counter = Vector3(door.x, BlockGenerator.BASE_Y, door.z) + v * 2.6
	var mark := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.9
	disc.bottom_radius = 0.9
	disc.height = 0.02
	mark.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.8, 0.25, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mark.material_override = mat
	mark.position = armoury.counter + Vector3(0, 0.03, 0)
	add_child(mark)
	var sign := Label3D.new()
	sign.text = "ARMOURY"
	sign.font_size = 48
	sign.outline_size = 10
	sign.pixel_size = 0.006
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.modulate = Color(1.0, 0.85, 0.35)
	sign.position = armoury.counter + Vector3(0, 2.3, 0)
	add_child(sign)
	var yard: Vector3 = (st.origin as Vector3) + u * (float(st.w) * BlockGenerator.M + 6.0) + Vector3(0, 0.8, 0)
	var ic := PoliceCar.new()
	ic.color = Color("1d2433")
	ic.engine *= 1.4
	ic.top_speed *= 1.2
	ic.position = yard + v * 3.5
	ic.rotation_degrees.y = 180.0
	var van := CivilianVehicle.new()
	van.setup("van_panel")
	van.paint = Color("f0f0ea")
	van.position = yard + v * 10.5
	van.rotation_degrees.y = 180.0
	van.set_meta("prisoner_van", true)
	var um := CivilianVehicle.new()
	um.setup("sedan")
	um.paint = Color("6d7176")
	um.position = yard + v * 17.5
	um.rotation_degrees.y = 180.0
	um.set_meta("unmarked", true)
	for pair in [[Armoury.INTERCEPTOR, ic], [Armoury.VAN, van], [Armoury.UNMARKED, um]]:
		var c: PoliceCar = pair[1]
		c.set_meta("locked", true)
		add_child(c)
		cars.add_car(c)
		yard_cars[pair[0]] = c
	_station_grows()


## Everyone: what's been bought shows up at the station.
func _station_grows() -> void:
	for i in yard_cars:
		var c: PoliceCar = yard_cars[i]
		if Armoury.owns(i) and c.has_meta("locked"):
			c.remove_meta("locked")
	if Armoury.owns(Armoury.GARAGE) and _garage == null and gen:
		_garage = _make_garage(gen.station())
	if Armoury.owns(Armoury.RANGE) and gen and get_node_or_null("Range") == null:
		var r := FiringRange.new()
		r.name = "Range"
		r.dispatcher = dispatch
		add_child(r)
		r.build(gen.station())


## A steel-framed garage over the yard: posts, a roof and a back wall.
func _make_garage(st: Dictionary) -> Node3D:
	var u: Vector3 = st.u
	var v: Vector3 = st.v
	var corner: Vector3 = (st.origin as Vector3) + u * (float(st.w) * BlockGenerator.M + 1.0)
	var g := StaticBody3D.new()
	g.name = "Garage"
	add_child(g)
	var w := 10.0
	var d := 15.0
	var h := 3.6
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("3d4a57")
	var roof := StandardMaterial3D.new()
	roof.albedo_color = Color("8c9399")
	var parts := [
		[Vector3(w, 0.2, d), Vector3(w * 0.5, h, d * 0.5), roof],
		[Vector3(w, h, 0.25), Vector3(w * 0.5, h * 0.5, d), steel],
	]
	for px in [0.2, w - 0.2]:
		for pz in [0.2, d * 0.5, d - 0.2]:
			parts.append([Vector3(0.25, h, 0.25), Vector3(px, h * 0.5, pz), steel])
	for p in parts:
		var size: Vector3 = p[0]
		var at: Vector3 = corner + u * (p[1] as Vector3).x + Vector3.UP * (p[1] as Vector3).y + v * (p[1] as Vector3).z
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		m.mesh = bm
		m.material_override = p[2]
		m.position = at
		g.add_child(m)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = at
		g.add_child(cs)
	Cel.apply(g)
	var sign := Label3D.new()
	sign.text = "POLICE GARAGE"
	sign.font_size = 40
	sign.outline_size = 8
	sign.pixel_size = 0.008
	sign.position = corner + u * (w * 0.5) + Vector3.UP * (h + 0.6)
	sign.rotation.y = atan2(-v.x, -v.z)
	g.add_child(sign)
	return g
