class_name PoliceCar
extends Car
## Phase 1.3 patrol car: the Blender model (police_car.glb) on the Car
## physics. Body, doors, bonnet and boot dent; doors, bonnet, boot, bumpers,
## push bar and mirrors come off when hit hard enough; every window shatters
## when shot. Roof lights and a siren (wail or yelp). Four seats: driver,
## front passenger and two in the back. The boot holds an ammo box and a
## first aid kit.

const MODEL := preload("res://assets/models/vehicles/police_car.glb")
const GLASS_COLOR := Color("1e2a36")

## Seats in car space, where the officer's feet go: driver, front passenger,
## rear left, rear right.
const SEATS := [Vector3(-0.40, -0.40, 0.08), Vector3(0.40, -0.40, 0.08), Vector3(-0.42, -0.40, -0.78), Vector3(0.42, -0.40, -0.78)]
## Where you stand to get in each seat (car space, x/z), and where you get out.
const DOORS := [Vector3(-1.45, 0, 0.25), Vector3(1.45, 0, 0.25), Vector3(-1.45, 0, -0.70), Vector3(1.45, 0, -0.70)]
## The window each seat leans out of.
const SEAT_WINDOW := ["win_fl", "win_fr", "win_rl", "win_rr"]
## Behind the car: the boot, with the ammo box and first aid kit.
const BOOT := Vector3(0, 0, -2.75)
const PANEL_LIMIT := 0.55
const LIGHTS_RATE := 2.6        # flash cycles a second

## Wave 2 (Phase 2.4): civilian vehicles are this class too (seats, doors,
## glass, dents and parts work the same), with their own model, seats and
## doors and no lights, siren or boot kit.
var model_scene: PackedScene = MODEL
var seats: Array = SEATS
var doors: Array = DOORS
var seat_windows: Array = SEAT_WINDOW
var boot := BOOT
var is_police := true
## The colours the roof lights flash (left, right) and the siren sounds
## (wail, yelp): the ambulance has blue both sides and its own two-tone.
var flash_cols: Array = [Color("ff2a36"), Color("3a78ff")]
var siren_stems: Array = ["siren_wail", "siren_yelp"]

var lights := false
var siren := 0                  # 0 off, 1 wail, 2 yelp
var glass := {}                 # window name -> {node, box, broken: bool}
var _wheel_proto: Node3D
var _lens_red: MeshInstance3D
var _lens_blue: MeshInstance3D
var _mat_red: ShaderMaterial
var _mat_blue: ShaderMaterial
var _light_red: OmniLight3D
var _light_blue: OmniLight3D
var _siren_player: AudioStreamPlayer3D
var _siren_playing := -1
var _flash_t := 0.0


func _init() -> void:
	super._init()
	add_to_group("vehicles")
	color = Color("eeeeea")


func _enter_tree() -> void:
	if is_police and not is_in_group("police_cars"):
		add_to_group("police_cars")


func _build_body() -> void:
	var model: Node3D = model_scene.instantiate()
	model.name = "Model"
	add_child(model)
	Cel.apply(model)
	_style_model(model)
	_wheel_proto = model.find_child("wheel", true, false)
	if _wheel_proto:
		_wheel_proto.get_parent().remove_child(_wheel_proto)
		# Keep the turn that stands the tyre up (axle along x); only centre it.
		_wheel_proto.position = Vector3.ZERO
	for n in ["body", "door_fl", "door_fr", "door_rl", "door_rr", "bonnet", "boot", "roof"]:
		var mi := _mesh(model, n)
		if mi:
			add_deformable(mi)
	for n in ["door_fl", "door_fr", "door_rl", "door_rr"]:
		_part(model, n, PANEL_LIMIT, 16.0)
	_part(model, "bonnet", PANEL_LIMIT * 0.8, 14.0)
	_part(model, "boot", PANEL_LIMIT * 0.8, 12.0)
	_part(model, "bumper_f", 0.26, 14.0)
	_part(model, "bumper_r", 0.26, 14.0)
	_part(model, "push_bar", 0.34, 10.0)
	_part(model, "mirror_l", 0.05, 2.0)
	_part(model, "mirror_r", 0.05, 2.0)
	var glass_mat := Cel.material(GLASS_COLOR, true, 0.02, null, 0.55)
	for n in ["win_front", "win_rear", "win_fl", "win_fr", "win_rl", "win_rr"]:
		var mi := _mesh(model, n)
		if mi == null:
			continue
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, glass_mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glass[n] = {"node": mi, "box": _local_xf(mi) * mi.get_aabb(), "broken": false}
	# Roof lights: their own materials so they can flash.
	_lens_red = _mesh(model, "lens_red")
	_lens_blue = _mesh(model, "lens_blue")
	_mat_red = Cel.unique_material((flash_cols[0] as Color).darkened(0.75))
	_mat_blue = Cel.unique_material((flash_cols[1] as Color).darkened(0.75))
	if _lens_red:
		_lens_red.set_surface_override_material(0, _mat_red)
	if _lens_blue:
		_lens_blue.set_surface_override_material(0, _mat_blue)
	for side in [[-1.0, flash_cols[0]], [1.0, flash_cols[1]]]:
		var l := OmniLight3D.new()
		l.light_color = side[1]
		l.omni_range = 9.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.position = Vector3(0.3 * side[0], 1.35, -0.25)
		add_child(l)
		if side[0] < 0:
			_light_red = l
		else:
			_light_blue = l
	_siren_player = AudioStreamPlayer3D.new()
	_siren_player.position = Vector3(0, 0.6, 1.8)
	_siren_player.unit_size = 14.0
	_siren_player.max_distance = 220.0
	_siren_player.volume_db = -4.0
	_siren_player.bus = "SFX"
	add_child(_siren_player)


## Wave 2: civilian vehicles recolour their paint here, before the panels
## are made dentable.
func _style_model(_model: Node3D) -> void:
	pass


func _make_wheel() -> Node3D:
	if _wheel_proto:
		return _wheel_proto.duplicate()
	return super._make_wheel()


func _mesh(root: Node, n: String) -> MeshInstance3D:
	var node := root.find_child(n, true, false)
	if node is MeshInstance3D:
		return node
	if node:
		for c in node.get_children():
			if c is MeshInstance3D:
				return c
	return null


func _part(root: Node, n: String, limit: float, m: float) -> void:
	var node := root.find_child(n, true, false) as Node3D
	if node:
		add_part(n, node, limit, m)


# --- lights and siren ------------------------------------------------------

## Driver's T: off -> lights -> lights and wail -> lights and yelp -> off.
func cycle_lights() -> void:
	if not is_police:
		return
	if not lights:
		lights = true
		siren = 0
	elif siren < 2:
		siren += 1
	else:
		lights = false
		siren = 0


func _process(delta: float) -> void:
	_flash_t += delta
	var k := fmod(_flash_t * LIGHTS_RATE, 1.0)
	# Each colour double-flashes in its half of the cycle.
	var red := lights and k < 0.5 and fmod(k * 4.0, 1.0) < 0.6
	var blue := lights and k >= 0.5 and fmod(k * 4.0, 1.0) < 0.6
	if _mat_red:
		_mat_red.set_shader_parameter("albedo", (flash_cols[0] as Color) * 1.6 if red else (flash_cols[0] as Color).darkened(0.75))
	if _mat_blue:
		_mat_blue.set_shader_parameter("albedo", (flash_cols[1] as Color) * 1.6 if blue else (flash_cols[1] as Color).darkened(0.75))
	if _light_red:
		_light_red.light_energy = 3.0 if red else 0.0
		_light_blue.light_energy = 3.0 if blue else 0.0
	var want := siren if lights else 0
	if want != _siren_playing:
		_siren_playing = want
		if want == 0:
			_siren_player.stop()
		else:
			var st: AudioStreamWAV = Sfx.stream(siren_stems[0] if want == 1 else siren_stems[1], 1)
			st.loop_mode = AudioStreamWAV.LOOP_FORWARD
			st.loop_begin = 0
			st.loop_end = st.data.size() / 2
			_siren_player.stream = st
			_siren_player.play()


# --- glass -----------------------------------------------------------------

## A bullet at this point (car space). Returns the window it broke, or "".
func window_at(local_point: Vector3) -> String:
	for n in glass:
		var g: Dictionary = glass[n]
		if not g.broken and (g.box as AABB).grow(0.08).has_point(local_point):
			return n
	return ""


func shatter(n: String) -> void:
	if not glass.has(n) or glass[n].broken:
		return
	var g: Dictionary = glass[n]
	g.broken = true
	var mi: MeshInstance3D = g.node
	mi.visible = false
	var centre: Vector3 = global_transform * (g.box as AABB).get_center()
	if is_inside_tree():
		Sfx.glass_break(get_parent(), centre)
		# A few loose shards (cosmetic, local only).
		for i in 6:
			var rb := RigidBody3D.new()
			rb.mass = 0.2
			rb.collision_layer = 0
			rb.collision_mask = 1
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(0.09, 0.01, 0.07)
			cs.shape = bs
			rb.add_child(cs)
			var m := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = bs.size
			m.mesh = bm
			m.material_override = Cel.material(Color("9fc4d8"), false)
			rb.add_child(m)
			get_parent().add_child(rb)
			rb.global_position = centre + Vector3(randf_range(-0.3, 0.3), randf_range(-0.1, 0.2), randf_range(-0.3, 0.3))
			rb.linear_velocity = linear_velocity + Vector3(randf_range(-1.5, 1.5), randf_range(0.5, 2.0), randf_range(-1.5, 1.5))
			get_tree().create_timer(4.0).timeout.connect(rb.queue_free)


## A passenger leaning out has wound the window down.
func set_window_down(n: String, down: bool) -> void:
	if glass.has(n) and not glass[n].broken:
		(glass[n].node as Node3D).visible = not down


func window_broken(n: String) -> bool:
	return glass.has(n) and glass[n].broken


func broken_windows() -> int:
	var c := 0
	for n in glass:
		if glass[n].broken:
			c += 1
	return c


# --- seats -------------------------------------------------------------------

## Officers (and prisoners) sitting in this car, by seat index.
func occupants() -> Dictionary:
	var out := {}
	if not is_inside_tree():
		return out
	for o in get_tree().get_nodes_in_group("officers"):
		if o.get("car") == self and o.state == Officer.S.VEHICLE:
			out[o.seat] = o
	for s in get_tree().get_nodes_in_group("suspects"):
		if s.get("car") == self and s.state == Suspect.S.IN_CAR:
			out[s.seat] = s
	return out


## Wave 2: officers can get into any vehicle (commandeering). Whoever is
## driving it (a civilian) is pulled out first: see TrafficSystem.
signal commandeered(by: Node)


func can_enter() -> bool:
	return not has_meta("locked")   # Phase 3.5: not bought yet


func commandeer(by: Node) -> void:
	commandeered.emit(by)


func seat_free(i: int) -> bool:
	return not occupants().has(i)


## World position of a seat or door.
func seat_point(i: int) -> Vector3:
	return global_transform * (seats[i] as Vector3)


func door_point(i: int) -> Vector3:
	return global_transform * (doors[i] as Vector3)


func boot_point() -> Vector3:
	return global_transform * boot


# --- network ---------------------------------------------------------------

func encode_state(b: StreamPeerBuffer) -> void:
	super.encode_state(b)
	b.put_u8((1 if lights else 0) | (siren << 1))


func extra_state(b: StreamPeerBuffer) -> Dictionary:
	var f := b.get_u8()
	return {"lights": (f & 1) != 0, "siren": (f >> 1) & 3}
