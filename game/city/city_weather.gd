class_name CityWeather
extends Node
## Wave 4, Phase 4.3: day, night and weather.
##
## The light follows the city clock (Missions.minute): the sun rises about
## six, sets about eight, and at night the street lamps come on round the
## officers. The host picks the weather now and then (clear, cloudy, rain,
## a storm with thunder) and tells everyone. Rain wets the roads: they go
## dark and shiny, and cars lose grip (Car.grip_k) until they dry out again.

const MSG_WEATHER := 107     # host -> all: kind, rain, wet (every 2 s)
enum W { CLEAR, CLOUDY, RAIN, STORM }
const NAMES := ["clear", "cloudy", "rain", "storm"]
const SPELL := Vector2(240.0, 600.0)    # real seconds between weather changes
const CLOUD := [0.0, 0.45, 0.65, 0.85]
const LAMPS := 14                        # street lamp lights round the camera
const LAMP_REACH := 70.0

static var current: CityWeather
var dispatcher: Dispatcher
var world: DestructionWorld
var env: Environment
var sun: DirectionalLight3D
var ground: Node
var skyline: CitySkyline
var kind := W.CLEAR
var rain := 0.0          # 0..1, how hard it's raining now
var wet := 0.0           # 0..1, how wet the roads are
var night := 0.0         # 0 day .. 1 full night (everyone works it out from the clock)
var _target_rain := 0.0
var _spell_t := 0.0
var _send_t := 0.0
var _lamp_t := 0.0
var _lamps: Array = []
var _lamp_ids: Array = []
var _rain_fx: GPUParticles3D
var _wet_mat: StandardMaterial3D
var _thunder_t := 20.0
var _flash := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	current = self
	_rng.randomize()
	_spell_t = _rng.randf_range(SPELL.x * 0.5, SPELL.y * 0.5)
	Net.register(MSG_WEATHER, _on_weather)
	_wet_mat = StandardMaterial3D.new()
	_wet_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wet_mat.albedo_color = Color(0.02, 0.03, 0.05, 0.0)
	_wet_mat.roughness = 0.3
	_wet_mat.metallic_specular = 0.45
	if ground:
		for c in ground.get_children():
			if c is MultiMeshInstance3D and (String(c.name).contains("road") or String(c.name).contains("pavement") or String(c.name).contains("kerb")):
				(c as MultiMeshInstance3D).material_overlay = _wet_mat
	for i in LAMPS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.82, 0.55)
		l.omni_range = 13.0
		l.omni_attenuation = 1.3
		l.light_energy = 0.0
		l.visible = false
		add_child(l)
		_lamps.append(l)
	_rain_fx = _make_rain()
	add_child(_rain_fx)


func _exit_tree() -> void:
	if current == self:
		current = null
	Net.unregister(MSG_WEATHER)
	Car.grip_k = 1.0


## Host: change the weather now (tests and the host's key).
func set_weather(k: int) -> void:
	kind = k
	_target_rain = float([0.0, 0.0, 0.6, 1.0][k])
	_spell_t = _rng.randf_range(SPELL.x, SPELL.y)
	if dispatcher:
		dispatcher.say("WEATHER: %s." % ["clearing up", "clouding over", "rain coming in", "a storm's coming in, thunder and all"][k])


func _physics_process(delta: float) -> void:
	if Net.is_host():
		_spell_t -= delta
		if _spell_t <= 0.0:
			# Mostly fair; rain now and then; a storm once in a while.
			var r := _rng.randf()
			set_weather(W.CLEAR if r < 0.4 else (W.CLOUDY if r < 0.65 else (W.RAIN if r < 0.9 else W.STORM)))
		rain = move_toward(rain, _target_rain, delta / 25.0)
		# Roads wet quickly in rain and dry slowly after it.
		wet = move_toward(wet, 1.0, delta * rain / 40.0) if rain > 0.05 else move_toward(wet, 0.0, delta / 240.0)
		_send_t -= delta
		if Net.is_online() and _send_t <= 0.0:
			_send_t = 2.0
			var b := StreamPeerBuffer.new()
			b.put_u8(kind)
			b.put_float(rain)
			b.put_float(wet)
			Net.broadcast(MSG_WEATHER, b.data_array, Net.UNRELIABLE)
		if kind == W.STORM and rain > 0.6:
			_thunder_t -= delta
			if _thunder_t <= 0.0:
				_thunder_t = _rng.randf_range(12.0, 35.0)
				_thunder()
	Car.grip_k = lerpf(1.0, 0.7, wet)


func _process(delta: float) -> void:
	var minute: float = dispatcher.missions.minute if dispatcher and dispatcher.missions else 12 * 60.0
	_light(minute, delta)
	_rain_follow()
	_lamp_t -= delta
	if _lamp_t <= 0.0:
		_lamp_t = 1.0
		_place_lamps()
	_wet_mat.albedo_color.a = wet * 0.32


## Sun height from the clock: up at 6:00, highest at 13:00, down at 20:00.
static func sun_height(minute: float) -> float:
	var h := minute / 60.0
	return sin(clampf((h - 6.0) / 14.0, -0.15, 1.15) * PI)


func _light(minute: float, delta: float) -> void:
	var up := sun_height(minute)
	var cloud: float = maxf(float(CLOUD[kind]), rain * 0.8)
	night = clampf(1.0 - (up + 0.12) / 0.32, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(up - 0.08) / 0.22, 0.0, 1.0)    # the low, warm light either end of the day
	_flash = maxf(0.0, _flash - delta * 4.0)
	if sun:
		var h := minute / 60.0
		var az := lerpf(-100.0, 100.0, clampf((h - 6.0) / 14.0, 0.0, 1.0))
		sun.rotation_degrees = Vector3(-lerpf(8.0, 62.0, clampf(up, 0.0, 1.0)), az, 0)
		var day_col := Color("fff1dc").lerp(Color("ffb070"), dusk * 0.8)
		sun.light_color = day_col.lerp(Color("7f93c9"), night)
		sun.light_energy = lerpf(1.25, 0.22, night) * lerpf(1.0, 0.45, cloud) + _flash * 2.0
		sun.shadow_enabled = night < 0.9
	if env:
		var sky := Color("8fb3cf").lerp(Color("e0a27a"), dusk * 0.6).lerp(Color("0b1020"), night)
		sky = sky.lerp(Color("6b7480").lerp(Color("0a0d14"), night), cloud * 0.8)
		env.background_color = sky.lerp(Color(0.8, 0.85, 1.0), _flash * 0.6)
		env.ambient_light_color = Color("b9c6d6").lerp(Color("223049"), night).lerp(Color(0.7, 0.75, 0.85), _flash * 0.5)
		env.ambient_light_energy = lerpf(0.9, 0.55, night) * lerpf(1.0, 0.8, cloud)
		if skyline and skyline.tower_mat:
			skyline.tower_mat.albedo_color = Color(1, 1, 1).lerp(Color(0.55, 0.58, 0.62), cloud * 0.6).lerp(Color(0.1, 0.12, 0.18), night)
		if env.fog_enabled:
			env.fog_light_color = sky
			env.fog_density = 0.0016 + rain * 0.004


## The nearest standing lamp posts to the camera get a light, at night.
func _place_lamps() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var on := night > 0.25 or (rain > 0.6 and night > 0.05)
	if cam == null or world == null or not on:
		for l in _lamps:
			(l as OmniLight3D).visible = false
		return
	var eye := cam.global_position
	var near: Array = []
	for id in world.pieces_near(eye, LAMP_REACH):
		var p: Dictionary = world.pieces[id]
		if p.kind == "lamp_post" and p.state == "intact":
			near.append(p)
	near.sort_custom(func(a, b): return (a.aabb as AABB).get_center().distance_squared_to(eye) < (b.aabb as AABB).get_center().distance_squared_to(eye))
	for i in _lamps.size():
		var l := _lamps[i] as OmniLight3D
		if i < near.size():
			var bb: AABB = near[i].aabb
			l.global_position = Vector3(bb.get_center().x, bb.end.y - 0.4, bb.get_center().z)
			l.light_energy = 1.6 * clampf(night * 1.4, 0.3, 1.0)
			l.visible = true
		else:
			l.visible = false


func _make_rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Rain"
	p.amount = 1500
	p.lifetime = 0.9
	p.visibility_aabb = AABB(Vector3(-25, -25, -25), Vector3(50, 50, 50))
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(18, 0.5, 18)
	pm.direction = Vector3(0.08, -1, 0.03)
	pm.spread = 2.0
	pm.initial_velocity_min = 22.0
	pm.initial_velocity_max = 26.0
	pm.gravity = Vector3(0, -9.8, 0)
	p.process_material = pm
	var streak := QuadMesh.new()
	streak.size = Vector2(0.015, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.8, 0.9, 0.35)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	streak.material = m
	p.draw_pass_1 = streak
	return p


func _rain_follow() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	_rain_fx.emitting = rain > 0.05 and cam != null
	if cam:
		_rain_fx.global_position = cam.global_position + Vector3(0, 14, 0)
	_rain_fx.amount_ratio = clampf(rain, 0.05, 1.0)


## Host: a lightning flash and a roll of thunder for everyone.
func _thunder() -> void:
	_flash = 1.0
	var cam := get_viewport().get_camera_3d()
	if cam:
		Sfx.play(get_parent(), "thunder", cam.global_position + Vector3(_rng.randf_range(-200, 200), 120, _rng.randf_range(-200, 200)), 6.0, 2000.0, 0.1, Sfx.BUS_AMBIENCE_OUT)
	if Net.is_online():
		var b := StreamPeerBuffer.new()
		b.put_u8(kind | 128)
		b.put_float(rain)
		b.put_float(wet)
		Net.broadcast(MSG_WEATHER, b.data_array)


func _on_weather(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var k := b.get_u8()
	kind = k & 3
	rain = b.get_float()
	wet = b.get_float()
	if k & 128:
		_flash = 1.0
		var cam := get_viewport().get_camera_3d()
		if cam:
			Sfx.play(get_parent(), "thunder", cam.global_position + Vector3(150, 120, -100), 6.0, 2000.0, 0.1, Sfx.BUS_AMBIENCE_OUT)
