extends Node3D
## Phase 0.5 look spike: a street corner in the cel look, by day and night.
## N toggles day and night. Q/E rotate the camera (tap to snap 45 degrees,
## hold to turn), the mouse wheel zooms. Walk into a shop through its door:
## the floors above you and the roof fade out so you can see inside.

const SHOP_A := Vector3(-10, 0, -6)
const SHOP_B := Vector3(4, 0, -6)
const DUMPSTER := preload("res://assets/models/props/dumpster.glb")

var night := false
var cam: IsoCamera
var sync: PawnSync
var world: DestructionWorld
var fader: RoofFader
var _sun: DirectionalLight3D
var _env: WorldEnvironment
var _lamps: Array = []


func _ready() -> void:
	_env = ProtoWorld.environment(self)
	_sun = ProtoWorld.sun(self)
	ProtoWorld.ground(self, 200.0, Color("3d4045"))  # asphalt
	# Pavement along the shop fronts, kerbs and lane markings.
	ProtoWorld.block(self, Vector3(40, 0.15, 6), Vector3(0, 0.075, -9.5 + 12.5), Color("a7a59e"), "Pavement", false)
	ProtoWorld.block(self, Vector3(40, 0.15, 3), Vector3(0, 0.075, -12.5), Color("a7a59e"), "PavementBack", false)
	for i in 10:
		ProtoWorld.block(self, Vector3(2.5, 0.02, 0.18), Vector3(-18 + i * 4.0, 0.01, 12), Color("e9e4cf"), "Lane", false)
	world = DestructionWorld.new()
	add_child(world)
	BuildingLayout.shop(world, SHOP_A + Vector3(0, 0.15, 0))
	BuildingLayout.shop(world, SHOP_B + Vector3(0, 0.15, 0))
	world.finalize()
	_shop_interior(SHOP_A)
	_shop_interior(SHOP_B)
	for x in [-14.0, -2.0, 10.0]:
		_lamp(Vector3(x, 0.15, 5.5))
	for i in 2:
		var d: Node3D = DUMPSTER.instantiate()
		d.position = Vector3(-15 + i * 2.2, 0.15, 5.0)
		d.rotation_degrees.y = 90
		Cel.apply(d)
		add_child(d)
	var cols := [Color("ecebe6"), Color("1d3e7a"), Color("b8322f"), Color("3c6e47")]
	for i in 4:
		var c := Car.new()
		c.color = cols[i]
		c.position = Vector3(-14 + i * 7.5, 0.9, 9.0)
		c.rotation_degrees.y = 90 if i % 2 == 0 else -90
		add_child(c)

	cam = IsoCamera.new()
	cam.zoom = 18.0
	add_child(cam)
	sync = PawnSync.new()
	sync.pawn_parent = self
	sync.pawn_factory = func(id):
		var p := CapsuleOfficer.new()
		p.peer_id = id
		p.position = Vector3(-6 + Net.player_ids().find(id) * 1.5, 0.3, 4)
		return p
	sync.input_source = func(): return PlayerInput.sample(cam, sync.my_pawn())
	add_child(sync)
	fader = RoofFader.new()
	add_child(fader)
	fader.add_building_from_world(world, AABB(SHOP_A + Vector3(-0.2, 0, -0.3), Vector3(8.4, 7, 4.6)))
	fader.add_building_from_world(world, AABB(SHOP_B + Vector3(-0.2, 0, -0.3), Vector3(8.4, 7, 4.6)))
	sync.pawn_spawned.connect(func(id, p):
		if id == Net.my_id():
			cam.target = p
			fader.watch = p)

	var overlay := NetOverlay.new()
	overlay.extra_lines = func(): return "N day/night (%s)   pieces faded %d" % ["night" if night else "day", fader.faded_count()]
	add_child(overlay)


func _shop_interior(o: Vector3) -> void:
	var y := 0.15
	ProtoWorld.block(self, Vector3(2.4, 1.0, 0.7), o + Vector3(2.0, y + 0.5, 2.6), Color("7a4f2e"), "Counter")
	ProtoWorld.block(self, Vector3(0.6, 1.8, 2.6), o + Vector3(7.4, y + 0.9, 2.2), Color("6b6f7d"), "Shelf")
	ProtoWorld.block(self, Vector3(0.9, 0.75, 0.9), o + Vector3(5.8, y + 0.375, 1.2), Color("a0703a"), "Table")
	var l := OmniLight3D.new()
	l.position = o + Vector3(4, 2.7, 2)
	l.omni_range = 7.0
	l.light_color = Color("ffd9a0")
	l.light_energy = 0.0
	add_child(l)
	_lamps.append([l, 1.6])


func _lamp(at: Vector3) -> void:
	ProtoWorld.block(self, Vector3(0.15, 4.5, 0.15), at + Vector3(0, 2.25, 0), Color("2d3138"), "LampPost")
	ProtoWorld.block(self, Vector3(0.9, 0.12, 0.3), at + Vector3(0.35, 4.5, 0), Color("2d3138"), "LampArm")
	var l := SpotLight3D.new()
	l.position = at + Vector3(0.6, 4.4, 0)
	l.rotation_degrees.x = -90
	l.spot_range = 9.0
	l.spot_angle = 55.0
	l.light_color = Color("ffcf8a")
	l.shadow_enabled = true
	l.light_energy = 0.0
	add_child(l)
	_lamps.append([l, 6.0])


func set_night(on: bool) -> void:
	night = on
	var env := _env.environment
	env.background_color = Color("0b1020") if on else Color("8fb3cf")
	env.ambient_light_color = Color("2a3757") if on else Color("b9c6d6")
	env.ambient_light_energy = 0.8 if on else 0.9
	_sun.light_color = Color("8fa3d9") if on else Color("fff1dc")
	_sun.light_energy = 0.35 if on else 1.2
	for l in _lamps:
		l[0].light_energy = l[1] if on else 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_day_night"):
		set_night(not night)
