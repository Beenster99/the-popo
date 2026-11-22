extends Node3D
## Phase 0.4 car spike. Each player drives the car in their slot.
## W/S throttle and brake/reverse, A/D steer, Space handbrake.
## Host: T switches driving authority (host simulates vs driver simulates).
## Drive into the concrete blocks to dent the car; a hard frontal hit knocks
## the bumper off. The two shops at the end are breakable.

const COLORS := [Color("ecebe6"), Color("1d3e7a"), Color("b8322f")]

var cam: IsoCamera
var cars: CarSync
var world: DestructionWorld
var _hud: Label


func _ready() -> void:
	ProtoWorld.environment(self)
	ProtoWorld.sun(self)
	ProtoWorld.ground(self, 260.0, Color("55595d"))
	# Road markings and a loop of barriers.
	for i in 20:
		ProtoWorld.block(self, Vector3(0.25, 0.02, 3.0), Vector3(0, 0.01, -90 + i * 9.0), Color("e9e4cf"), "Line", false)
	for i in 8:
		ProtoWorld.block(self, Vector3(2.0, 1.0, 1.0), Vector3(-14 + i * 4.0, 0.5, 40), Color("b9b5ab"), "Barrier")
		ProtoWorld.block(self, Vector3(1.0, 1.0, 2.0), Vector3(22, 0.5, -30 + i * 6.0), Color("b9b5ab"), "Barrier")
	for i in 30:
		var cone := ProtoWorld.rigid_box(self, Vector3(0.4, 0.7, 0.4), Vector3(-25 + (i % 6) * 2.0, 0.36, -20 + (i / 6) * 2.0), Color("ff7b1c"), 4.0)
		cone.collision_layer = 16
	world = DestructionWorld.new()
	add_child(world)
	BuildingLayout.shop(world, Vector3(-6, 0, 60))
	BuildingLayout.wall_row(world, Vector3(-40, 0, 20), 4)
	world.finalize()

	cam = IsoCamera.new()
	cam.zoom = 26.0
	cam.zoom_max = 70.0
	add_child(cam)
	cars = CarSync.new()
	cars.destruction = world
	add_child(cars)
	for i in Net.MAX_PLAYERS:
		var c := Car.new()
		c.color = COLORS[i]
		c.position = Vector3(-4 + i * 4.0, 1.0, -10)
		add_child(c)
		cars.add_car(c)
	var mine := cars.car_for(Net.my_id())
	cam.target = cars.cars[max(mine, 0)]

	var overlay := NetOverlay.new()
	overlay.extra_lines = func():
		var c: Car = cars.cars[max(cars.car_for(Net.my_id()), 0)]
		return "driving authority: %s (host presses T)\n%d km/h   dents %.3f   bumper %s" % [
			"HOST simulates" if cars.mode == CarSync.Mode.HOST else "DRIVER simulates", c.speed_kmh(), c.dent_amount(), "on" if c.bumper_attached else "off"]
	add_child(overlay)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).physical_keycode == KEY_T and Net.is_host():
		cars.set_mode(CarSync.Mode.HOST if cars.mode == CarSync.Mode.DRIVER else CarSync.Mode.DRIVER)
