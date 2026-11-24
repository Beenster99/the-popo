extends Node3D
## v0.13.0: a recorded tour of the gun sounds in every kind of space, for
## checking by ear or by meter (movie maker records the mix):
##   godot --path . --write-movie out.avi --fixed-fps 30 --quit-after 1500 res://tools/capture/gun_spaces.tscn
## Each part is built far from the others so the rays only feel its own walls.

var sounds: GameSounds
var cam: Camera3D
var label: Label
var t := 0.0
var _parts: Array = []
var _i := -1
var _fired := []

# [title, where (origin), ears offset, shot offset, kind, weight, rounds, gap, blast]
const PARTS := [
	["Street, service pistol, 8 m", "street", Vector3(0, 1.6, 0), Vector3(0, 1.4, -8), 0, 1.0, 3, 0.6, false],
	["Street, .357 revolver, 8 m", "street", Vector3(0, 1.6, 0), Vector3(0, 1.4, -8), 0, 1.6, 3, 0.9, false],
	["Street, sawn-off shotgun, 8 m", "street", Vector3(0, 1.6, 0), Vector3(0, 1.4, -8), 2, 1.0, 2, 1.2, false],
	["Street, machine pistol burst, 8 m", "street", Vector3(0, 1.6, 0), Vector3(0, 1.4, -8), 0, 0.8, 10, 0.065, false],
	["Alley, service pistol, 6 m", "alley", Vector3(0, 1.6, 6), Vector3(0, 1.4, 0), 0, 1.0, 3, 0.6, false],
	["Small room, service pistol, 2 m", "room", Vector3(0.8, 1.6, 0.8), Vector3(-0.8, 1.4, -0.6), 0, 1.0, 3, 0.6, false],
	["Small room, shotgun, 2 m", "room", Vector3(0.8, 1.6, 0.8), Vector3(-0.8, 1.4, -0.6), 2, 1.0, 2, 1.2, false],
	["Warehouse hall, .45, 10 m", "hall", Vector3(0, 1.6, 6), Vector3(0, 1.4, -4), 0, 1.35, 3, 0.8, false],
	["Rooftop, service pistol, 8 m", "roof", Vector3(0, 1.6, 0), Vector3(0, 1.4, -8), 0, 1.0, 3, 0.6, false],
	["Street, service pistol, 70 m away", "street", Vector3(0, 1.6, 40), Vector3(0, 1.4, -30), 0, 1.0, 3, 0.7, false],
	["Street, shotgun, 180 m away (the bang arrives late)", "street", Vector3(0, 1.6, 90), Vector3(0, 1.4, -90), 2, 1.0, 2, 1.2, false],
	["Shot in the street, you inside a house", "street", Vector3(0, 1.6, 9.5), Vector3(0, 1.4, -6), 0, 1.0, 3, 0.6, false],
	["Grenade in the street, 20 m", "street", Vector3(0, 1.6, 10), Vector3(0, 0.3, -10), 0, 1.0, 1, 1.0, true],
]
const ORIGIN := {"street": Vector3(0, 0, 0), "alley": Vector3(600, 0, 0), "room": Vector3(1200, 0, 0),
	"hall": Vector3(1800, 0, 0), "roof": Vector3(2400, 0, 0)}
const PART_LEN := 4.2


func _ready() -> void:
	Sfx.ensure_buses()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("8fa7bf")
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	_build()
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	sounds = GameSounds.new()
	sounds.pawn_getter = func(): return null
	add_child(sounds)
	var cl := CanvasLayer.new()
	add_child(cl)
	label = Label.new()
	label.position = Vector2(40, 40)
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	cl.add_child(label)


func _box(size: Vector3, pos: Vector3, c := Color.GRAY) -> void:
	ProtoWorld.block(self, size, pos, c, "Wall")


func _build() -> void:
	# Ground everywhere.
	_box(Vector3(3200, 0.2, 600), Vector3(1200, -0.1, 0), Color("55585c"))
	# Street: two rows of buildings 22 m apart, a house on one side with a door gap.
	var o: Vector3 = ORIGIN.street
	for side in [-1, 1]:
		for k in 8:
			_box(Vector3(14, 14, 10), o + Vector3(side * 16, 7, -120 + k * 30), Color("8a7f74"))
	# The house the ears go into (walls round x 0, z 9..12).
	_box(Vector3(6, 3, 0.25), o + Vector3(0, 1.5, 8), Color("b5a58f"))
	_box(Vector3(6, 3, 0.25), o + Vector3(0, 1.5, 11.5), Color("b5a58f"))
	_box(Vector3(0.25, 3, 3.5), o + Vector3(-3, 1.5, 9.75), Color("b5a58f"))
	_box(Vector3(0.25, 3, 3.5), o + Vector3(3, 1.5, 9.75), Color("b5a58f"))
	_box(Vector3(6.2, 0.2, 3.7), o + Vector3(0, 3.1, 9.75), Color("b5a58f"))
	var hz := SoundZone.new()
	hz.size = Vector3(6, 3, 3.5)
	add_child(hz)
	hz.global_position = o + Vector3(0, 1.5, 9.75)
	# Alley: walls 3.5 m apart, long and high.
	o = ORIGIN.alley
	_box(Vector3(0.5, 12, 60), o + Vector3(-1.75, 6, 0), Color("7d5a48"))
	_box(Vector3(0.5, 12, 60), o + Vector3(1.75, 6, 0), Color("7d5a48"))
	# Small room 3.5 x 3.5 with a ceiling.
	o = ORIGIN.room
	_room(o, Vector3(3.5, 3, 3.5))
	# Hall 24 x 30, 9 m high.
	o = ORIGIN.hall
	_room(o, Vector3(24, 9, 30))
	# Roof: a tower top 20 x 20 at 24 m, a parapet.
	o = ORIGIN.roof
	_box(Vector3(20, 24, 20), o + Vector3(0, 12, -4), Color("8a7f74"))
	for k in 30:
		_box(Vector3(14, 10 + (k % 5) * 6, 14), o + Vector3(-90 + (k % 6) * 36, 5 + (k % 5) * 3, -90 + (k / 6) * 40) + Vector3(0, 0, 0), Color("8a7f74"))


func _room(o: Vector3, s: Vector3) -> void:
	var c := Color("c2b8a3")
	_box(Vector3(s.x, s.y, 0.2), o + Vector3(0, s.y / 2, -s.z / 2), c)
	_box(Vector3(s.x, s.y, 0.2), o + Vector3(0, s.y / 2, s.z / 2), c)
	_box(Vector3(0.2, s.y, s.z), o + Vector3(-s.x / 2, s.y / 2, 0), c)
	_box(Vector3(0.2, s.y, s.z), o + Vector3(s.x / 2, s.y / 2, 0), c)
	_box(Vector3(s.x, 0.2, s.z), o + Vector3(0, s.y + 0.1, 0), c)
	var z := SoundZone.new()
	z.size = s
	add_child(z)
	z.global_position = o + Vector3(0, s.y / 2, 0)


func _process(delta: float) -> void:
	t += delta
	var i := int(t / PART_LEN) - 0
	if i >= PARTS.size():
		label.text = "End"
		return
	var p: Array = PARTS[i]
	var o: Vector3 = ORIGIN[p[1]]
	var lift := Vector3(0, 24, 0) if p[1] == "roof" else Vector3.ZERO
	var ears: Vector3 = o + lift + p[2]
	var gun: Vector3 = o + lift + p[3]
	if i != _i:
		_i = i
		_fired = []
		label.text = "%d/%d  %s" % [i + 1, PARTS.size(), p[0]]
		print("%.2f  %s" % [t, p[0]])
		Sfx.forget_spaces()
	cam.global_position = ears
	var look := gun - ears
	look.y = 0.0
	if look.length() > 0.1:
		cam.look_at(ears + look.normalized(), Vector3.UP)
	var local := t - i * PART_LEN - 0.6
	for r in int(p[6]):
		if r in _fired or local < r * float(p[7]):
			continue
		_fired.append(r)
		if p[8]:
			Sfx.explosion(self, gun, 1.2)
			Sfx.play(self, "frag_crack", gun, 8.0, 300.0, 0.05, Sfx.space_bus(self, gun))
		else:
			Sfx.shot(self, gun, int(p[4]), false, float(p[5]))
			if r == 0:
				print("      space: %s" % [Sfx.space_at(self, gun)])
