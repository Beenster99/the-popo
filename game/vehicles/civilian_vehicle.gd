class_name CivilianVehicle
extends PoliceCar
## Wave 2, Phase 2.4: every civilian vehicle, from the models made by
## tools/blender/build_vehicles.py, on the same Car physics as the police
## car. Bodies dent, panels and bumpers come off, windows shatter, and an
## officer can get in any of them (commandeering).
##
## Types: sedan, hatchback, van_panel, van_box (delivery), minibus,
## trash_truck (with a working bin lifter), hgv_tractor (pulls a Trailer:
## box, tanker or flatbed), motorbike. Each sets its size, wheels, mass,
## engine, seats and doors from TYPES, and gets a body colour.

const TYPES := {
	"sedan": {"size": Vector3(1.82, 0.85, 4.5), "cabin": [Vector3(1.55, 0.62, 2.0), Vector3(0, 0.66, -0.2)],
		"wheels": [Vector3(-0.8, -0.25, 1.4), Vector3(0.8, -0.25, 1.4), Vector3(-0.8, -0.25, -1.4), Vector3(0.8, -0.25, -1.4)],
		"radius": 0.34, "mass": 1350.0, "engine": 9000.0, "top": 36.0,
		"seats": "car", "colours": ["8a1f24", "1f3a5c", "d9d6cf", "2b2b2e", "6f7378", "3f5d3a", "b78a2c", "5a2a4a"]},
	"hatchback": {"size": Vector3(1.74, 0.85, 3.9), "cabin": [Vector3(1.5, 0.66, 2.2), Vector3(0, 0.7, -0.45)],
		"wheels": [Vector3(-0.76, -0.25, 1.2), Vector3(0.76, -0.25, 1.2), Vector3(-0.76, -0.25, -1.2), Vector3(0.76, -0.25, -1.2)],
		"radius": 0.32, "mass": 1100.0, "engine": 7600.0, "top": 33.0,
		"seats": "car", "colours": ["d03a2a", "e2c23a", "2f6f9a", "e8e6e0", "4a8a4a", "222226", "9a9ea4"]},
	"van_panel": {"size": Vector3(2.0, 0.95, 5.2), "cabin": [Vector3(1.85, 1.15, 4.1), Vector3(0, 1.0, -0.5)],
		"wheels": [Vector3(-0.86, -0.3, 1.75), Vector3(0.86, -0.3, 1.75), Vector3(-0.86, -0.3, -1.65), Vector3(0.86, -0.3, -1.65)],
		"radius": 0.36, "mass": 2100.0, "engine": 11000.0, "top": 31.0,
		"seats": "van", "colours": ["e8e6e0", "e8e6e0", "1f3a5c", "c9302c", "6f7378"]},
	"van_box": {"size": Vector3(2.05, 0.95, 6.0), "cabin": [Vector3(2.0, 2.0, 3.7), Vector3(0, 1.3, -1.2)],
		"wheels": [Vector3(-0.88, -0.3, 2.1), Vector3(0.88, -0.3, 2.1), Vector3(-0.88, -0.3, -1.9), Vector3(0.88, -0.3, -1.9)],
		"radius": 0.38, "mass": 3200.0, "engine": 13500.0, "top": 28.0,
		"seats": "cab", "colours": ["e8e6e0", "e2c23a", "2f6f9a", "d9d6cf"]},
	"minibus": {"size": Vector3(2.0, 0.95, 5.6), "cabin": [Vector3(1.85, 1.15, 4.5), Vector3(0, 1.0, -0.4)],
		"wheels": [Vector3(-0.86, -0.3, 1.9), Vector3(0.86, -0.3, 1.9), Vector3(-0.86, -0.3, -1.85), Vector3(0.86, -0.3, -1.85)],
		"radius": 0.36, "mass": 2600.0, "engine": 12000.0, "top": 30.0,
		"seats": "car", "colours": ["e8e6e0", "2f6f9a", "e2c23a"]},
	"trash_truck": {"size": Vector3(2.45, 1.0, 8.2), "cabin": [Vector3(2.4, 2.6, 7.0), Vector3(0, 1.0, -0.4)],
		"wheels": [Vector3(-1.0, -0.4, 2.9), Vector3(1.0, -0.4, 2.9), Vector3(-1.0, -0.4, -1.6), Vector3(1.0, -0.4, -1.6), Vector3(-1.0, -0.4, -2.9), Vector3(1.0, -0.4, -2.9)],
		"radius": 0.52, "mass": 14000.0, "engine": 30000.0, "top": 22.0,
		"seats": "cab", "colours": ["3f6b3a", "e8e6e0", "2f5f8a"]},
	"hgv_tractor": {"size": Vector3(2.48, 1.0, 5.9), "cabin": [Vector3(2.4, 2.0, 2.2), Vector3(0, 1.0, 1.8)],
		"wheels": [Vector3(-1.0, -0.4, 2.0), Vector3(1.0, -0.4, 2.0), Vector3(-1.0, -0.4, -1.4), Vector3(1.0, -0.4, -1.4), Vector3(-1.0, -0.4, -2.6), Vector3(1.0, -0.4, -2.6)],
		"radius": 0.52, "mass": 8500.0, "engine": 34000.0, "top": 27.0,
		"seats": "cab", "colours": ["c9302c", "1f3a5c", "e8e6e0", "e2c23a", "2b2b2e", "3f6b3a"]},
	"motorbike": {"size": Vector3(0.55, 0.6, 2.0), "cabin": [],
		"wheels": [Vector3(-0.32, -0.15, 0.72), Vector3(0.32, -0.15, 0.72), Vector3(-0.32, -0.15, -0.68), Vector3(0.32, -0.15, -0.68)],
		"radius": 0.32, "mass": 260.0, "engine": 3600.0, "top": 44.0,
		"seats": "bike", "colours": ["c9302c", "222226", "2f6f9a", "e2c23a", "e8e6e0"]},
}
## Wave 5 (Phase 5.1): liveries on the same bodies. model: the body it's
## built on; extras: what's bolted on (see _add_extras).
const VARIANTS := {
	"taxi": {"model": "sedan", "colours": ["1c1c1e", "e2b51e"], "extras": "taxi"},
	"work_van": {"model": "van_panel", "colours": ["e8e6e0", "f08a24", "e8e6e0"], "extras": "ladders"},
	"ice_cream": {"model": "van_box", "colours": ["f4b6c8", "f2efe6"], "extras": "ice_cream"},
	"courier": {"model": "van_box", "colours": ["c9302c", "e2c23a", "2f6f9a"], "extras": "stripe"},
}

## Seat layouts: seats (car space, feet), doors (where you stand to get in),
## and the window each seat leans out of.
const LAYOUTS := {
	"car": {"seats": [Vector3(-0.40, -0.40, 0.08), Vector3(0.40, -0.40, 0.08), Vector3(-0.42, -0.40, -0.78), Vector3(0.42, -0.40, -0.78)],
		"doors": [Vector3(-1.45, 0, 0.25), Vector3(1.45, 0, 0.25), Vector3(-1.45, 0, -0.70), Vector3(1.45, 0, -0.70)],
		"windows": ["win_fl", "win_fr", "win_rl", "win_rr"]},
	"van": {"seats": [Vector3(-0.45, -0.35, 0.8), Vector3(0.45, -0.35, 0.8)],
		"doors": [Vector3(-1.55, 0, 0.9), Vector3(1.55, 0, 0.9)], "windows": ["win_fl", "win_fr"]},
	"cab": {"seats": [Vector3(-0.5, 0.0, 0.0), Vector3(0.5, 0.0, 0.0)],
		"doors": [Vector3(-1.7, 0, 0.0), Vector3(1.7, 0, 0.0)], "windows": ["win_fl", "win_fr"]},
	"bike": {"seats": [Vector3(0, -0.05, -0.25), Vector3(0, 0.0, -0.75)],
		"doors": [Vector3(-0.9, 0, -0.25), Vector3(0.9, 0, -0.5)], "windows": ["", ""]},
}
## Where the driver sits in a cab (car space z), for trucks: the cab is at
## the front, so the seats move forward.
const CAB_SEAT_Z := {"van_box": 1.25, "trash_truck": 3.0, "hgv_tractor": 2.0}

var kind := "sedan"
var extras := ""
var paint := Color.WHITE
## The trash truck's bin lifter (raised while it empties a bin).
var _lifter: Node3D
var lifter_up := 0.0


static func make(kind_name: String, colour_seed := 0) -> CivilianVehicle:
	var v := CivilianVehicle.new()
	v.setup(kind_name, colour_seed)
	return v


## The body a kind is built on (a taxi is a sedan underneath).
static func base_of(kind_name: String) -> String:
	return String(VARIANTS[kind_name].model) if VARIANTS.has(kind_name) else kind_name


func setup(kind_name: String, colour_seed := 0) -> void:
	kind = kind_name
	var base := base_of(kind)
	var t: Dictionary = TYPES[base]
	extras = String(VARIANTS[kind].extras) if VARIANTS.has(kind) else ""
	is_police = false
	model_scene = load("res://assets/models/vehicles/%s.glb" % base)
	size = t.size
	cabin_box = t.cabin
	wheel_mounts = (t.wheels as Array).duplicate()
	wheel_radius = t.radius
	mass = t.mass
	var k: float = t.mass / 1250.0
	spring = SPRING * k
	damp = DAMP * k
	engine = t.engine
	top_speed = t.top
	brake_force = BRAKE * k
	if base in ["trash_truck", "hgv_tractor", "van_box"]:
		steer_max = 0.5
		yaw_assist = 0.45
	var lay: Dictionary = LAYOUTS[t.seats]
	seats = (lay.seats as Array).duplicate()
	doors = (lay.doors as Array).duplicate()
	seat_windows = lay.windows
	if CAB_SEAT_Z.has(base):
		var z: float = CAB_SEAT_Z[base]
		for i in seats.size():
			seats[i] = Vector3(seats[i].x, seats[i].y, z)
			doors[i] = Vector3(doors[i].x, 0, z)
	boot = Vector3(0, 0, -size.z * 0.5 - 0.6)
	var r := RandomNumberGenerator.new()
	r.seed = colour_seed * 7919 + kind.hash()
	var cols: Array = VARIANTS[kind].colours if VARIANTS.has(kind) else t.colours
	paint = Color(cols[r.randi_range(0, cols.size() - 1)])
	color = paint
	center_of_mass = Vector3(0, -0.3, 0.1)


func _style_model(model: Node3D) -> void:
	var mat := Cel.material(paint, true, 0.02)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(i)
			if src and src.resource_name.begins_with("paint"):
				m.set_surface_override_material(i, mat)


func _build_body() -> void:
	super._build_body()
	var model := get_node_or_null("Model")
	if model == null:
		return
	_lifter = model.find_child("bin_lifter", true, false) as Node3D
	_add_extras(model)
	for n in ["cargo_box", "compactor", "hopper", "cab_shell"]:
		var mi := _mesh(model, n)
		if mi:
			add_deformable(mi)


## Bits bolted onto a body for a livery.
func _add_extras(model: Node3D) -> void:
	if extras == "":
		return
	var top := size.y * 0.5 + (cabin_box[0] as Vector3).y + (cabin_box[1] as Vector3).y - (cabin_box[0] as Vector3).y * 0.5 if not cabin_box.is_empty() else size.y
	match extras:
		"taxi":
			var roof_sign := _box(Vector3(0.7, 0.2, 0.28), Vector3(0, top + 0.1, (cabin_box[1] as Vector3).z), Color("f6d23a"))
			model.add_child(roof_sign)
			var l := Label3D.new()
			l.text = "TAXI"
			l.font_size = 40
			l.pixel_size = 0.004
			l.modulate = Color("1c1c1e")
			l.position = Vector3(0, 0, 0.145)
			roof_sign.add_child(l)
			var back := l.duplicate() as Label3D
			back.position = Vector3(0, 0, -0.145)
			back.rotation.y = PI
			roof_sign.add_child(back)
			if paint.r > 0.5:
				return
			# A chequer band on the black cabs.
			for i in 10:
				var c := Color("f6d23a") if i % 2 == 0 else Color("1c1c1e")
				model.add_child(_box(Vector3(0.02, 0.1, 0.25), Vector3(-size.x * 0.5 - 0.005, 0.05, -1.1 + i * 0.25), c))
				model.add_child(_box(Vector3(0.02, 0.1, 0.25), Vector3(size.x * 0.5 + 0.005, 0.05, -1.1 + i * 0.25), c))
		"ladders":
			var z := (cabin_box[1] as Vector3).z
			var rail := (cabin_box[0] as Vector3).z * 0.85
			for x in [-0.35, 0.35]:
				model.add_child(_box(Vector3(0.06, 0.06, rail), Vector3(x, top + 0.12, z), Color("b8bcc2")))
			for i in 7:
				model.add_child(_box(Vector3(0.7, 0.04, 0.04), Vector3(0, top + 0.12, z - rail * 0.5 + i * rail / 6.0), Color("b8bcc2")))
			model.add_child(_box(Vector3(0.18, 0.12, 0.18), Vector3(0, top + 0.06, z + rail * 0.5 + 0.1), Color("ff9a1a")))
		"ice_cream":
			var z := (cabin_box[1] as Vector3).z
			var cone := _box(Vector3(0.4, 0.7, 0.4), Vector3(0, top + 0.35, z + 0.6), Color("d9a45a"))
			model.add_child(cone)
			model.add_child(_box(Vector3(0.55, 0.4, 0.55), Vector3(0, top + 0.85, z + 0.6), Color("f8e8f0")))
			for side in [-1.0, 1.0]:
				model.add_child(_box(Vector3(0.02, 0.3, 2.4), Vector3(side * ((cabin_box[0] as Vector3).x * 0.5 + 0.01), (cabin_box[1] as Vector3).y + 0.5, z), Color("7ac8e0")))
				model.add_child(_box(Vector3(0.02, 0.6, 1.0), Vector3(side * ((cabin_box[0] as Vector3).x * 0.5 + 0.012), (cabin_box[1] as Vector3).y, z + 0.3), Color("3a3a3e")))
		"stripe":
			var z := (cabin_box[1] as Vector3).z
			for side in [-1.0, 1.0]:
				model.add_child(_box(Vector3(0.02, 0.35, (cabin_box[0] as Vector3).z * 0.9), Vector3(side * ((cabin_box[0] as Vector3).x * 0.5 + 0.01), (cabin_box[1] as Vector3).y, z), Color("f2efe6")))


static func _box(sz: Vector3, at: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = Cel.material(col, true, 0.012)
	mi.position = at
	return mi


func _ready() -> void:
	super._ready()
	if kind == "motorbike":
		# Four contact points for stability, two wheels drawn on the centre line.
		for w in _wheels:
			var mesh := (w.node as Node3D).get_child(0) as Node3D
			if mesh:
				mesh.position.x = -(w.pos as Vector3).x
			if (w.pos as Vector3).x > 0.0:
				(w.node as Node3D).visible = false


func _process(delta: float) -> void:
	super._process(delta)
	if _lifter:
		_lifter.position.y = lerpf(_lifter.position.y, lifter_up * 1.6, 1.0 - exp(-3.0 * delta))
		_lifter.rotation.x = lerpf(_lifter.rotation.x, -lifter_up * 1.9, 1.0 - exp(-3.0 * delta))


## A motorbike leans into its turns and stays upright when parked (no
## real two-wheel balance: four contact points close together, and a lean
## drawn on the model).
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if kind == "motorbike":
		var model := get_node_or_null("Model") as Node3D
		if model:
			var lean := -_steer_lean() * clampf(linear_velocity.length() / 12.0, 0.0, 1.0) * 0.45
			model.rotation.z = lerpf(model.rotation.z, lean, 1.0 - exp(-6.0 * delta))


## Anti-roll: an arcade helper that keeps tall vans and the motorbike on
## their wheels through hard corners (a crash can still roll them: it gives
## up past 50 degrees).
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	super._integrate_forces(state)
	if freeze:
		return
	var b := state.transform.basis
	var tilt := b.x.dot(Vector3.UP)        # + when rolled to the left
	if absf(tilt) > 0.77:
		return
	var k: float = 14.0 if kind == "motorbike" else 3.5
	var roll_rate := state.angular_velocity.dot(b.z)
	state.apply_torque(b.z * (-tilt * k - roll_rate * 0.8) * mass * 2.0)


func _steer_lean() -> float:
	return steer
